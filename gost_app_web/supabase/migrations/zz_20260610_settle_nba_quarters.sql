-- ============================================================
-- Settlement marches NBA par quart-temps
-- ============================================================
-- Nouvelle fonction helper qui prend les scores par quart en plus.
-- Wrapper de _settle_virtual_selection : on essaye d'abord le helper
-- universel ; si void et market_code est un quart-time, on resout ici.
--
-- Couvre :
--   ou_q1_over@N / ou_q1_under@N (idem q2/q3/q4)
--   3way_q1_home / _draw / _away (idem q2/q3/q4)
--   ml_q1_home / _away (idem q2/q3/q4, Home/Away par quart)
--   team_total_home_q1 / _away_q1 (avec ligne si dispo)
--   highest_qtr_q1 / _q2 / _q3 / _q4
--   team_highest_qtr_home / _away
--   odd_even_q1_odd / _even (idem q2/q3/q4)
-- ============================================================

create or replace function public._settle_virtual_selection_nba_quarters(
  p_market_code text,
  p_q1_home int, p_q1_away int,
  p_q2_home int, p_q2_away int,
  p_q3_home int, p_q3_away int,
  p_q4_home int, p_q4_away int
) returns text
language plpgsql immutable set search_path = public as $$
declare
  v_qh int; v_qa int;
  v_at int; v_line numeric; v_qtot int;
  v_q1t int; v_q2t int; v_q3t int; v_q4t int;
  v_max int; v_ht_outcome text;
begin
  if p_q1_home is null or p_q1_away is null then return 'void'; end if;
  v_q1t := p_q1_home + p_q1_away;
  v_q2t := p_q2_home + p_q2_away;
  v_q3t := p_q3_home + p_q3_away;
  v_q4t := p_q4_home + p_q4_away;

  -- Selectionne les scores du quart selon le code
  if p_market_code ~ '_q1[_@]?' then v_qh := p_q1_home; v_qa := p_q1_away;
  elsif p_market_code ~ '_q2[_@]?' then v_qh := p_q2_home; v_qa := p_q2_away;
  elsif p_market_code ~ '_q3[_@]?' then v_qh := p_q3_home; v_qa := p_q3_away;
  elsif p_market_code ~ '_q4[_@]?' then v_qh := p_q4_home; v_qa := p_q4_away;
  end if;

  if v_qh is null then v_qh := 0; end if;
  if v_qa is null then v_qa := 0; end if;
  v_qtot := v_qh + v_qa;

  -- ── 3Way Result par quart (Home/Draw/Away) ──
  if p_market_code ~ '^3way_q[1-4]_' then
    if p_market_code like '%_home' then
      return case when v_qh > v_qa then 'won' else 'lost' end;
    elsif p_market_code like '%_draw' then
      return case when v_qh = v_qa then 'won' else 'lost' end;
    elsif p_market_code like '%_away' then
      return case when v_qa > v_qh then 'won' else 'lost' end;
    end if;
  end if;

  -- ── Home/Away par quart (sans nul possible normalement, mais NBA peut tied) ──
  if p_market_code ~ '^ml_q[1-4]_' then
    if p_market_code like '%_home' then
      return case when v_qh > v_qa then 'won' else 'lost' end;
    elsif p_market_code like '%_away' then
      return case when v_qa > v_qh then 'won' else 'lost' end;
    end if;
  end if;

  -- ── OU par quart : ou_q1_over@27.5 / ou_q1_under@27.5 ──
  if p_market_code ~ '^ou_q[1-4]_(over|under)@' then
    v_at := position('@' in p_market_code);
    v_line := substring(p_market_code from v_at + 1)::numeric;
    if p_market_code like '%_over@%' then
      return case when v_qtot > v_line then 'won' else 'lost' end;
    elsif p_market_code like '%_under@%' then
      return case when v_qtot < v_line then 'won' else 'lost' end;
    end if;
  end if;

  -- ── Team Total Points par quart (avec ligne) ──
  if p_market_code ~ '^team_total_(home|away)_q[1-4]_(over|under)@' then
    v_at := position('@' in p_market_code);
    v_line := substring(p_market_code from v_at + 1)::numeric;
    -- v_qh deja set selon q1/q2/q3/q4, mais on doit isoler home vs away
    if p_market_code like 'team_total_home_%_over@%' then
      return case when v_qh > v_line then 'won' else 'lost' end;
    elsif p_market_code like 'team_total_home_%_under@%' then
      return case when v_qh < v_line then 'won' else 'lost' end;
    elsif p_market_code like 'team_total_away_%_over@%' then
      return case when v_qa > v_line then 'won' else 'lost' end;
    elsif p_market_code like 'team_total_away_%_under@%' then
      return case when v_qa < v_line then 'won' else 'lost' end;
    end if;
  end if;

  -- ── Highest Scoring Quarter (chips q1/q2/q3/q4) ──
  if p_market_code ~ '^highest_qtr_q[1-4]$' then
    v_max := greatest(v_q1t, v_q2t, v_q3t, v_q4t);
    if p_market_code = 'highest_qtr_q1' then
      return case when v_q1t = v_max then 'won' else 'lost' end;
    elsif p_market_code = 'highest_qtr_q2' then
      return case when v_q2t = v_max then 'won' else 'lost' end;
    elsif p_market_code = 'highest_qtr_q3' then
      return case when v_q3t = v_max then 'won' else 'lost' end;
    elsif p_market_code = 'highest_qtr_q4' then
      return case when v_q4t = v_max then 'won' else 'lost' end;
    end if;
  end if;

  -- ── Team With Highest Scoring Quarter ──
  -- (quelle equipe a marque le + dans son meilleur quart)
  if p_market_code = 'team_highest_qtr_home' then
    return case when greatest(p_q1_home,p_q2_home,p_q3_home,p_q4_home)
                   > greatest(p_q1_away,p_q2_away,p_q3_away,p_q4_away) then 'won' else 'lost' end;
  elsif p_market_code = 'team_highest_qtr_away' then
    return case when greatest(p_q1_away,p_q2_away,p_q3_away,p_q4_away)
                   > greatest(p_q1_home,p_q2_home,p_q3_home,p_q4_home) then 'won' else 'lost' end;
  end if;

  -- ── Odd/Even par quart (total) ──
  if p_market_code ~ '^odd_even_q[1-4]_' then
    if p_market_code like '%_odd' then
      return case when v_qtot % 2 = 1 then 'won' else 'lost' end;
    elsif p_market_code like '%_even' then
      return case when v_qtot % 2 = 0 then 'won' else 'lost' end;
    end if;
  end if;

  return 'void';
end;
$$;

-- ============================================================
-- Patch _settle_virtual_selection : delegue au helper quart-time
-- ============================================================
-- On wrappe l'ancien helper avec une version qui essaye le quart-time
-- AVANT le fallback void final.
-- (Le helper actuel renvoie 'void' pour ces codes par defaut.)
--
-- IMPORTANT : on ne peut pas modifier _settle_virtual_selection direct
-- car il ne connait pas les scores par quart. On expose donc un NOUVEAU
-- helper top-level qui prend les quarts en plus, et qu'on appelle depuis
-- settle_virtual_bets (cf migration suivante).
-- ============================================================

create or replace function public._settle_virtual_selection_v2(
  p_sport       text,
  p_market_code text,
  p_home_score  int,
  p_away_score  int,
  p_ht_home     int,
  p_ht_away     int,
  p_q1_home     int,
  p_q1_away     int,
  p_q2_home     int,
  p_q2_away     int,
  p_q3_home     int,
  p_q3_away     int,
  p_q4_home     int,
  p_q4_away     int
) returns text
language plpgsql immutable set search_path = public as $$
declare
  v_res text;
begin
  -- D'abord helper universel (couvre 1X2, OU, BTTS, AH, Correct Score, etc.)
  v_res := _settle_virtual_selection(p_sport, p_market_code,
    p_home_score, p_away_score, p_ht_home, p_ht_away);
  if v_res <> 'void' then return v_res; end if;

  -- Sinon : essaye les marches par quart (NBA)
  if p_sport = 'basketball' and p_q1_home is not null then
    return _settle_virtual_selection_nba_quarters(p_market_code,
      p_q1_home, p_q1_away, p_q2_home, p_q2_away,
      p_q3_home, p_q3_away, p_q4_home, p_q4_away);
  end if;

  return 'void';
end;
$$;

-- ============================================================
-- Patch settle_virtual_bets pour utiliser _v2 + lire les quarts
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
        -- HT NBA = Q1 + Q2
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

      -- Utilise _v2 qui supporte les quarts NBA
      v_sel_status := _settle_virtual_selection_v2(
        v_match.sport, v_sel.market_code,
        v_home_score, v_away_score,
        v_ht_home, v_ht_away,
        v_match.q1_home, v_match.q1_away,
        v_match.q2_home, v_match.q2_away,
        v_match.q3_home, v_match.q3_away,
        v_match.q4_home, v_match.q4_away
      );
      update public.bet_selections set selection_status = v_sel_status where id = v_sel.id;
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
