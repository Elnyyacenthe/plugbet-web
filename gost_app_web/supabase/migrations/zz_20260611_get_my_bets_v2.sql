-- ============================================================
-- get_my_bets_v2 : version etendue avec filtres + pagination
-- ============================================================
-- Additive : ne touche PAS la RPC get_my_bets(int) historique.
-- Les anciens clients continuent d'appeler v1 sans changement.
-- Les nouveaux clients (BetsHistoryScreen refondu) appellent v2.
--
-- Filtres :
--   p_status      : null=tous | 'pending'|'won'|'lost'|'void'|'cashed_out'|'refunded'
--   p_min_payout  : null=tous | int (gain minimum sur potential_payout)
--   p_date_from   : null=pas de borne basse
--   p_date_to     : null=pas de borne haute
--   p_search      : null ou '' = pas de recherche
--                   - 8+ chars : recherche prefix sur bet.id (numero ticket)
--                   - sinon : recherche dans match_label des selections (ILIKE)
--   p_limit       : 50 par defaut, cap 200
--   p_offset      : 0 par defaut (pagination)
--
-- Retour :
--   { items: jsonb[], total: int, has_more: bool }
--
-- Pour preserver totalement la compatibilite : v1 reste intacte.
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

  -- Sanitize
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

  -- Compte total (apres filtres mais avant pagination)
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

  -- Items page courante
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
        'is_live', s.is_live
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

-- ============================================================
-- Tests rapides (a executer apres login):
-- ============================================================
-- 1. Tous les tickets : select get_my_bets_v2();
-- 2. Que les gagnes : select get_my_bets_v2(p_status := 'won');
-- 3. 30 derniers jours : select get_my_bets_v2(p_date_from := now() - interval '30 days');
-- 4. Page 2 : select get_my_bets_v2(p_limit := 20, p_offset := 20);
-- 5. Recherche par ID prefix : select get_my_bets_v2(p_search := 'a1b2c3d4');
-- 6. Recherche par equipe : select get_my_bets_v2(p_search := 'Real Madrid');
