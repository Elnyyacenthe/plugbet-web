-- ============================================================
-- Lookup d'un ticket par code court (8 derniers chars de l'UUID)
-- ============================================================
-- Permet :
-- 1. JOUEUR -> lookup_bet_by_code (public, infos anonymisees)
--    Cas d'usage : un joueur partage son code de coupon avec un ami
--    pour qu'il voie le ticket ET puisse le dupliquer dans son panier.
--
-- 2. ADMIN -> admin_lookup_bet (privileges admin/super_admin)
--    Cas d'usage : support client charge un ticket par code pour
--    diagnostiquer un soucis. Retourne aussi l'user_id + profil.
--
-- Securite :
--   - Lecture seule (jamais d'update)
--   - lookup_bet_by_code : retourne PAS user_id ni request_id (anonymat)
--   - admin_lookup_bet : check_role admin/super_admin (RLS via profiles)
--   - Code de 8 chars hex = 16^8 = 4.3B combinaisons -> bruteforce difficile
-- ============================================================

-- ============================================================
-- 1) lookup_bet_by_code : public (joueurs)
-- ============================================================
-- Cherche un ticket par les 6-8 derniers chars de son UUID (sans tirets).
-- Si plusieurs matches : retourne le plus recent (devrait pas arriver avec 8 chars).
-- Retour : jsonb (null si rien trouve).

create or replace function public.lookup_bet_by_code(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_clean_code text;
  v_bet record;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'LOOKUP_BET_AUTH_REQUIRED';
  end if;
  if p_code is null or length(trim(p_code)) < 6 then
    raise exception 'LOOKUP_BET_CODE_TOO_SHORT';
  end if;

  -- Sanitize : enleve le #, espaces, tirets, lower
  v_clean_code := lower(regexp_replace(p_code, '[^0-9a-fA-F]', '', 'g'));
  if length(v_clean_code) < 6 then
    raise exception 'LOOKUP_BET_CODE_INVALID';
  end if;
  if length(v_clean_code) > 32 then
    raise exception 'LOOKUP_BET_CODE_TOO_LONG';
  end if;

  -- Recherche par suffix de l'UUID (sans tirets)
  select * into v_bet from public.bets b
  where replace(b.id::text, '-', '') ilike '%' || v_clean_code
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  -- Build JSON anonymise (PAS de user_id ni request_id)
  v_result := jsonb_build_object(
    'found', true,
    'id', v_bet.id,
    'short_id', upper(right(replace(v_bet.id::text, '-', ''), 8)),
    'bet_type', v_bet.bet_type,
    'stake', v_bet.stake,
    'total_odds', v_bet.total_odds,
    'potential_payout', v_bet.potential_payout,
    'status', v_bet.status,
    'actual_payout', v_bet.actual_payout,
    'is_virtual', v_bet.is_virtual,
    'created_at', v_bet.created_at,
    'settled_at', v_bet.settled_at,
    'is_mine', v_bet.user_id = v_uid,
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
      from public.bet_selections s where s.bet_id = v_bet.id
    ), '[]'::jsonb)
  );
  return v_result;
end;
$$;

revoke all on function public.lookup_bet_by_code(text)
  from public, anon;
grant execute on function public.lookup_bet_by_code(text) to authenticated;

-- ============================================================
-- 2) admin_lookup_bet : pour support client (admin/super_admin)
-- ============================================================
-- Idem lookup_bet_by_code MAIS retourne aussi :
--   - user_id de proprietaire du ticket
--   - username du proprietaire (joined sur profiles)
--   - request_id du ticket (utile pour debug idempotence)
-- Verifie role admin/super_admin dans la table profiles (via custom claim
-- ou colonne role).

create or replace function public.admin_lookup_bet(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_clean_code text;
  v_bet record;
  v_owner record;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'ADMIN_LOOKUP_AUTH_REQUIRED';
  end if;

  -- Check role
  select role into v_role from public.user_profiles where id = v_uid;
  if v_role not in ('admin', 'super_admin') then
    raise exception 'ADMIN_LOOKUP_FORBIDDEN: role % does not have access', v_role;
  end if;

  if p_code is null or length(trim(p_code)) < 6 then
    raise exception 'ADMIN_LOOKUP_CODE_TOO_SHORT';
  end if;

  v_clean_code := lower(regexp_replace(p_code, '[^0-9a-fA-F]', '', 'g'));
  if length(v_clean_code) < 6 then
    raise exception 'ADMIN_LOOKUP_CODE_INVALID';
  end if;

  select * into v_bet from public.bets b
  where replace(b.id::text, '-', '') ilike '%' || v_clean_code
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  -- Owner profile (username + email)
  select id, username, coalesce(coins, 0) as coins
    into v_owner
  from public.user_profiles where id = v_bet.user_id;

  v_result := jsonb_build_object(
    'found', true,
    'id', v_bet.id,
    'short_id', upper(right(replace(v_bet.id::text, '-', ''), 8)),
    'bet_type', v_bet.bet_type,
    'stake', v_bet.stake,
    'total_odds', v_bet.total_odds,
    'potential_payout', v_bet.potential_payout,
    'status', v_bet.status,
    'actual_payout', v_bet.actual_payout,
    'is_virtual', v_bet.is_virtual,
    'created_at', v_bet.created_at,
    'settled_at', v_bet.settled_at,
    'request_id', v_bet.request_id,
    'owner', jsonb_build_object(
      'user_id', v_bet.user_id,
      'username', v_owner.username,
      'current_balance', v_owner.coins
    ),
    'selections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'match_id', s.match_id,
        'match_label', s.match_label,
        'market_code', s.market_code,
        'market_label', s.market_label,
        'odds', s.odds,
        'selection_status', s.selection_status,
        'is_virtual', s.is_virtual,
        'is_live', s.is_live,
        'final_home_score', s.final_home_score,
        'final_away_score', s.final_away_score,
        'created_at', s.created_at
      ) order by s.created_at)
      from public.bet_selections s where s.bet_id = v_bet.id
    ), '[]'::jsonb),
    -- Mouvements wallet liés au ticket (debit + payout/refund)
    'wallet_history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', w.id,
        'type', w.type,
        'amount', w.amount,
        'request_id', w.request_id,
        'created_at', w.created_at,
        'metadata', w.metadata
      ) order by w.id)
      from public.wallet_ledger w
      where w.user_id = v_bet.user_id
        and (
          w.request_id = 'bet:' || v_bet.id::text or
          w.request_id = 'payout:' || v_bet.id::text or
          w.request_id = 'refund:' || v_bet.id::text or
          w.request_id = 'payout:real:' || v_bet.id::text or
          w.request_id = 'refund:real:' || v_bet.id::text
        )
    ), '[]'::jsonb)
  );
  return v_result;
end;
$$;

revoke all on function public.admin_lookup_bet(text)
  from public, anon;
grant execute on function public.admin_lookup_bet(text) to authenticated;

-- ============================================================
-- Tests :
-- ============================================================
-- 1. Comme joueur connecte :
--    select lookup_bet_by_code('BC9B7030');
-- 2. Comme admin :
--    select admin_lookup_bet('BC9B7030');
-- 3. Avec code invalide :
--    select lookup_bet_by_code('123');  -- erreur TOO_SHORT
