-- ============================================================
-- bet_selections : stocker le score final du match (pour UI tickets)
-- ============================================================
-- AVANT : les sélections settlées affichent juste won/lost mais pas
--         le score du match. L'utilisateur ne sait pas combien c'etait.
--
-- APRES : 2 colonnes nullables (additive, rétrocompatible) :
--   - final_home_score int
--   - final_away_score int
--   Remplies au moment du settlement (virtual + real).
--
-- L'UI affiche "2 - 1" sous les equipes quand la selection est settled.
-- ============================================================

alter table public.bet_selections
  add column if not exists final_home_score int,
  add column if not exists final_away_score int;

-- ============================================================
-- 1) Patch settle_virtual_bets : remplir scores au settlement
-- ============================================================
create or replace function public.settle_virtual_bets()
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_bet record;
  v_sel record;
  v_match record;
  v_home_score int;
  v_away_score int;
  v_ht_home int;
  v_ht_away int;
  v_goal jsonb;
  v_sec int;
  v_team text;
  v_sel_status text;
  v_settled_count int := 0;
  v_any_lost boolean;
  v_any_void boolean;
  v_any_pending boolean;
  v_payout int;
begin
  for v_bet in
    select id, user_id, stake, total_odds, potential_payout
    from public.bets
    where status = 'pending' and is_virtual = true
  loop
    v_any_lost := false;
    v_any_void := false;
    v_any_pending := false;

    for v_sel in
      select id, match_id, market_code, selection_status
      from public.bet_selections
      where bet_id = v_bet.id and is_virtual = true
    loop
      if v_sel.selection_status <> 'pending' then
        if v_sel.selection_status = 'lost' then v_any_lost := true;
        elsif v_sel.selection_status = 'void' then v_any_void := true; end if;
        continue;
      end if;

      select * into v_match from public.virtual_match
        where id::text = v_sel.match_id;

      if not found then
        update public.bet_selections set selection_status = 'void' where id = v_sel.id;
        v_any_void := true;
        continue;
      end if;

      if v_match.kickoff + interval '30 seconds' > now() then
        v_any_pending := true;
        continue;
      end if;

      if v_match.sport = 'basketball' then
        v_home_score := coalesce(v_match.final_home_score, 0);
        v_away_score := coalesce(v_match.final_away_score, 0);
        v_ht_home := coalesce(v_match.q1_home, 0) + coalesce(v_match.q2_home, 0);
        v_ht_away := coalesce(v_match.q1_away, 0) + coalesce(v_match.q2_away, 0);
      else
        v_home_score := 0; v_away_score := 0;
        v_ht_home := 0; v_ht_away := 0;
        for v_goal in select * from jsonb_array_elements(v_match.goals)
        loop
          v_sec := coalesce((v_goal->>'sec')::int, 99);
          v_team := v_goal->>'team';
          if v_team = 'home' then
            v_home_score := v_home_score + 1;
            if v_sec <= 15 then v_ht_home := v_ht_home + 1; end if;
          else
            v_away_score := v_away_score + 1;
            if v_sec <= 15 then v_ht_away := v_ht_away + 1; end if;
          end if;
        end loop;
      end if;

      v_sel_status := _settle_virtual_selection_v2(
        v_match.sport, v_sel.market_code,
        v_home_score, v_away_score,
        v_ht_home, v_ht_away,
        v_match.q1_home, v_match.q1_away,
        v_match.q2_home, v_match.q2_away,
        v_match.q3_home, v_match.q3_away,
        v_match.q4_home, v_match.q4_away
      );

      -- 👇 Sauvegarde le score final dans la selection (pour UI)
      update public.bet_selections set
        selection_status = v_sel_status,
        final_home_score = v_home_score,
        final_away_score = v_away_score
        where id = v_sel.id;

      if v_sel_status = 'lost' then v_any_lost := true;
      elsif v_sel_status = 'void' then v_any_void := true;
      end if;
    end loop;

    if v_any_pending then continue; end if;

    if v_any_lost then
      update public.bets set status = 'lost', settled_at = now(), actual_payout = 0
        where id = v_bet.id;
      v_settled_count := v_settled_count + 1;
    elsif v_any_void then
      perform public.wallet_apply_delta(
        v_bet.user_id, v_bet.stake,
        'bet_refund', 'bet', v_bet.id::text,
        jsonb_build_object('reason', 'void_no_loss'),
        'refund:' || v_bet.id::text
      );
      update public.bets set status = 'void', settled_at = now(), actual_payout = v_bet.stake
        where id = v_bet.id;
      v_settled_count := v_settled_count + 1;
      insert into public.treasury_movements
        (game_type, game_id, user_id, movement_type, amount)
        values ('virtual', v_bet.id::text, v_bet.user_id, 'payout', v_bet.stake);
    else
      v_payout := v_bet.potential_payout;
      perform public.wallet_apply_delta(
        v_bet.user_id, v_payout,
        'bet_payout', 'bet', v_bet.id::text,
        jsonb_build_object('payout', v_payout, 'odds', v_bet.total_odds),
        'payout:' || v_bet.id::text
      );
      update public.bets set status = 'won', settled_at = now(), actual_payout = v_payout
        where id = v_bet.id;
      v_settled_count := v_settled_count + 1;
      insert into public.treasury_movements
        (game_type, game_id, user_id, movement_type, amount)
        values ('virtual', v_bet.id::text, v_bet.user_id, 'payout', v_payout);
    end if;
  end loop;
  return v_settled_count;
end;
$$;

grant execute on function public.settle_virtual_bets() to service_role;

-- ============================================================
-- 2) Patch settle_real_bets_with_results : remplir scores aussi
-- ============================================================
create or replace function public.settle_real_bets_with_results(
  p_results jsonb
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
      if v_sel.selection_status <> 'pending' then
        if v_sel.selection_status = 'lost' then v_any_lost := true;
        elsif v_sel.selection_status = 'void' then v_any_void := true; end if;
        continue;
      end if;

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

      if v_match is null then
        v_any_pending := true;
        continue;
      end if;

      if not v_is_finished or v_home_score is null or v_away_score is null then
        v_any_pending := true;
        continue;
      end if;

      v_sel_status := _settle_virtual_selection(
        v_sport, v_sel.market_code,
        v_home_score, v_away_score,
        v_ht_home, v_ht_away
      );

      -- 👇 Sauvegarde le score final dans la selection (pour UI)
      update public.bet_selections set
        selection_status = v_sel_status,
        final_home_score = v_home_score,
        final_away_score = v_away_score
        where id = v_sel.id;

      if v_sel_status = 'lost' then v_any_lost := true;
      elsif v_sel_status = 'void' then v_any_void := true;
      end if;
    end loop;

    if v_any_pending then continue; end if;

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
-- 3) Patch get_my_bets_v2 pour exposer les scores
-- ============================================================
create or replace function public.get_my_bets_v2(
  p_limit       int default 50,
  p_offset      int default 0,
  p_status      text default null,
  p_min_payout  int default null,
  p_date_from   timestamptz default null,
  p_date_to     timestamptz default null,
  p_search      text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_limit int;
  v_offset int;
  v_total int;
  v_items jsonb;
  v_search_clean text;
  v_id_search boolean := false;
  v_label_search boolean := false;
begin
  if v_uid is null then
    raise exception 'GET_BETS_AUTH_REQUIRED';
  end if;

  v_limit := greatest(1, least(coalesce(p_limit, 50), 200));
  v_offset := greatest(0, coalesce(p_offset, 0));
  v_search_clean := nullif(trim(coalesce(p_search, '')), '');

  if v_search_clean is not null then
    if length(v_search_clean) >= 6
       and v_search_clean ~ '^[0-9a-fA-F-]+$' then
      v_id_search := true;
    else
      v_label_search := true;
    end if;
  end if;

  with filtered as (
    select b.id
    from public.bets b
    where b.user_id = v_uid
      and (p_status is null or b.status = p_status)
      and (p_min_payout is null or b.potential_payout >= p_min_payout)
      and (p_date_from is null or b.created_at >= p_date_from)
      and (p_date_to   is null or b.created_at <= p_date_to)
      and (
        not v_id_search
        or b.id::text ilike lower(v_search_clean) || '%'
      )
      and (
        not v_label_search
        or exists (
          select 1 from public.bet_selections s
          where s.bet_id = b.id
            and s.match_label ilike '%' || v_search_clean || '%'
        )
      )
  )
  select count(*) into v_total from filtered;

  with page as (
    select b.id, b.bet_type, b.stake, b.total_odds, b.potential_payout,
           b.status, b.actual_payout, b.is_virtual,
           b.created_at, b.settled_at, b.request_id
    from public.bets b
    where b.user_id = v_uid
      and (p_status is null or b.status = p_status)
      and (p_min_payout is null or b.potential_payout >= p_min_payout)
      and (p_date_from is null or b.created_at >= p_date_from)
      and (p_date_to   is null or b.created_at <= p_date_to)
      and (
        not v_id_search
        or b.id::text ilike lower(v_search_clean) || '%'
      )
      and (
        not v_label_search
        or exists (
          select 1 from public.bet_selections s
          where s.bet_id = b.id
            and s.match_label ilike '%' || v_search_clean || '%'
        )
      )
    order by b.created_at desc
    limit v_limit offset v_offset
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'bet_type', p.bet_type,
    'stake', p.stake,
    'total_odds', p.total_odds,
    'potential_payout', p.potential_payout,
    'status', p.status,
    'actual_payout', p.actual_payout,
    'is_virtual', p.is_virtual,
    'created_at', p.created_at,
    'settled_at', p.settled_at,
    'request_id', p.request_id,
    'selections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'match_id', s.match_id,
        'match_label', s.match_label,
        'market_code', s.market_code,
        'market_label', s.market_label,
        'odds', s.odds,
        'selection_status', s.selection_status,
        'is_virtual', s.is_virtual,
        'is_live', s.is_live,
        'final_home_score', s.final_home_score,
        'final_away_score', s.final_away_score
      ) order by s.created_at)
      from public.bet_selections s where s.bet_id = p.id
    ), '[]'::jsonb)
  ) order by p.created_at desc), '[]'::jsonb)
  into v_items
  from page p;

  return jsonb_build_object(
    'items', coalesce(v_items, '[]'::jsonb),
    'total', v_total,
    'has_more', (v_offset + v_limit) < v_total,
    'limit', v_limit,
    'offset', v_offset
  );
end;
$$;

revoke all on function public.get_my_bets_v2(int, int, text, int, timestamptz, timestamptz, text)
  from public, anon;
grant execute on function public.get_my_bets_v2(int, int, text, int, timestamptz, timestamptz, text)
  to authenticated;
