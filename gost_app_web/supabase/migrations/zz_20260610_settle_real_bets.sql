-- ============================================================
-- Settlement des paris REELS (matchs StatPal)
-- ============================================================
-- Architecture :
--   1. Edge function `settle_real_bets` (cron 10 min) :
--      - Liste les match_ids distincts des bet_selections pending non-virtual
--      - Pour chaque match, fetch StatPal pour le score final
--      - Appelle settle_real_bets_with_results(jsonb) en passant les scores
--   2. RPC SQL ci-dessous : applique le settlement atomique
--
-- Avantage : zero appel HTTP cote SQL, separation propre fetch/decision.
-- ============================================================

create or replace function public.settle_real_bets_with_results(
  p_results jsonb  -- [{match_id, sport, home_score, away_score, ht_home, ht_away, is_finished}]
) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_bet record;
  v_sel record;
  v_match jsonb;
  v_match_id text;
  v_sport text;
  v_home_score int;
  v_away_score int;
  v_ht_home int;
  v_ht_away int;
  v_is_finished bool;
  v_sel_status text;
  v_settled_count int := 0;
  v_any_lost bool;
  v_any_void bool;
  v_any_pending bool;
  v_payout int;
begin
  if jsonb_typeof(p_results) <> 'array' then
    raise exception 'SETTLE_REAL_BAD_RESULTS';
  end if;

  -- Boucle sur tous les bets non-virtuels pending
  for v_bet in
    select id, user_id, stake, total_odds, potential_payout
    from public.bets
    where status = 'pending' and is_virtual = false
  loop
    v_any_lost := false;
    v_any_void := false;
    v_any_pending := false;

    for v_sel in
      select id, match_id, market_code, selection_status
      from public.bet_selections
      where bet_id = v_bet.id and is_virtual = false
    loop
      -- Selection deja resolue
      if v_sel.selection_status <> 'pending' then
        if v_sel.selection_status = 'lost' then v_any_lost := true;
        elsif v_sel.selection_status = 'void' then v_any_void := true; end if;
        continue;
      end if;

      -- Cherche le match dans p_results
      v_match := null;
      for v_match_id, v_sport, v_home_score, v_away_score, v_ht_home, v_ht_away, v_is_finished in
        select (r->>'match_id')::text,
               (r->>'sport')::text,
               nullif(r->>'home_score','')::int,
               nullif(r->>'away_score','')::int,
               nullif(r->>'ht_home','')::int,
               nullif(r->>'ht_away','')::int,
               coalesce((r->>'is_finished')::bool, false)
        from jsonb_array_elements(p_results) r
      loop
        if v_match_id = v_sel.match_id then
          v_match := jsonb_build_object('found', true);
          exit;
        end if;
      end loop;

      -- Match pas dans le payload (encore en cours / pas fetched) -> skip
      if v_match is null then
        v_any_pending := true;
        continue;
      end if;

      -- Match pas encore termine -> selection reste pending
      if not v_is_finished or v_home_score is null or v_away_score is null then
        v_any_pending := true;
        continue;
      end if;

      -- Resolution selection via le helper universel deja en place
      -- (_settle_virtual_selection est mal nomme mais fonctionne pour tous
      -- les marches resolvables avec home_score / away_score / ht_*).
      v_sel_status := _settle_virtual_selection(
        v_sport, v_sel.market_code,
        v_home_score, v_away_score,
        v_ht_home, v_ht_away
      );
      update public.bet_selections set selection_status = v_sel_status where id = v_sel.id;
      if v_sel_status = 'lost' then v_any_lost := true;
      elsif v_sel_status = 'void' then v_any_void := true;
      end if;
    end loop;

    if v_any_pending then continue; end if;

    -- ── DECISION FINALE pour ce ticket ──
    if v_any_lost then
      update public.bets set status = 'lost', settled_at = now(), actual_payout = 0
        where id = v_bet.id;
      v_settled_count := v_settled_count + 1;
      insert into public.treasury_movements
        (game_type, game_id, user_id, movement_type, amount, house_cut)
        values ('bet_real', v_bet.id::text, v_bet.user_id, 'house_cut', v_bet.stake, v_bet.stake)
        on conflict do nothing;
    elsif v_any_void then
      perform public.wallet_apply_delta(
        v_bet.user_id, v_bet.stake,
        'bet_refund', 'bet', v_bet.id::text,
        jsonb_build_object('reason', 'void_no_loss', 'bet_type', 'real'),
        'refund:real:' || v_bet.id::text
      );
      update public.bets set status = 'void', settled_at = now(), actual_payout = v_bet.stake
        where id = v_bet.id;
      v_settled_count := v_settled_count + 1;
      insert into public.treasury_movements
        (game_type, game_id, user_id, movement_type, amount)
        values ('bet_real', v_bet.id::text, v_bet.user_id, 'refund', v_bet.stake);
    else
      v_payout := v_bet.potential_payout;
      perform public.wallet_apply_delta(
        v_bet.user_id, v_payout,
        'bet_payout', 'bet', v_bet.id::text,
        jsonb_build_object('payout', v_payout, 'odds', v_bet.total_odds, 'bet_type', 'real'),
        'payout:real:' || v_bet.id::text
      );
      update public.bets set status = 'won', settled_at = now(), actual_payout = v_payout
        where id = v_bet.id;
      v_settled_count := v_settled_count + 1;
      insert into public.treasury_movements
        (game_type, game_id, user_id, movement_type, amount)
        values ('bet_real', v_bet.id::text, v_bet.user_id, 'payout', v_payout);
    end if;
  end loop;

  return v_settled_count;
end;
$$;

revoke all on function public.settle_real_bets_with_results(jsonb)
  from public, anon, authenticated;
grant execute on function public.settle_real_bets_with_results(jsonb) to service_role;

-- ============================================================
-- Helper : liste les match_ids des bets pending (pour l'edge function)
-- ============================================================
create or replace function public.list_pending_real_match_ids()
returns jsonb
language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(distinct match_info), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'match_id', s.match_id,
      'is_live', s.is_live
    ) as match_info
    from public.bet_selections s
    join public.bets b on b.id = s.bet_id
    where b.status = 'pending'
      and b.is_virtual = false
      and s.selection_status = 'pending'
      and s.is_virtual = false
  ) sub;
$$;

revoke all on function public.list_pending_real_match_ids() from public, anon, authenticated;
grant execute on function public.list_pending_real_match_ids() to service_role;
