-- ============================================================
-- CORA DICE FIX : align ledger entries on room_id (not game_id)
-- ============================================================
-- BUG identifie : les bets utilisent cora_rooms.id (room_id) dans le
-- request_id (`cora_bet:<room_id>:<user_id>`), mais les payouts et
-- refunds utilisent cora_games.id (game_id) dans le request_id
-- (`cora_payout:<game_id>` / `cora_refund:<game_id>:<user_id>`).
-- room_id != game_id -> le reporting Treasury voit les payouts/refunds
-- comme orphelins, les bets comme jamais resolus, et la maison perd
-- 2255 FCFA artificiellement dans treasury_game_stats (84% des games
-- mismatched).
--
-- Fix : resoudre le room_id depuis cora_games dans les 2 wrappers
-- cora_pay_winner et cora_refund_participants, et l'utiliser dans le
-- request_id ET le game_id wallet_ledger. Tous les futurs games seront
-- coherents (1 seul identifiant par partie).
--
-- Note : l'historique reste mismatched (ne pas reecrire wallet_ledger
-- retroactivement = source de verite immuable). Le deficit ~2255 FCFA
-- restera dans treasury_game_stats mais ne grossira plus.
--
-- Idempotent (CREATE OR REPLACE).
-- ============================================================

begin;

-- ============================================================
-- 1) cora_pay_winner : utilise room_id dans request_id
-- ============================================================
create or replace function public.cora_pay_winner(
  p_winner_id uuid,
  p_game_id   text,
  p_pot       bigint,
  p_house_cut numeric default null,
  p_loser_ids uuid[] default null
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_cut       bigint;
  v_payout    bigint;
  v_house_pct numeric;
  v_room_id   text;
begin
  if p_pot <= 0 then return; end if;

  -- Resolve room_id : utilise cora_games.room_id, fallback sur p_game_id
  -- si game introuvable (cas edge : appel direct sans game cree).
  select room_id::text into v_room_id from cora_games
    where id = p_game_id::uuid limit 1;
  if v_room_id is null then v_room_id := p_game_id; end if;

  v_house_pct := coalesce(p_house_cut, (select house_cut_pct from cora_dice_config where id = 1), 0.10);
  v_cut       := floor(p_pot * v_house_pct)::bigint;
  v_payout    := p_pot - v_cut;

  -- Credit gagnant - request_id base sur room_id (matche les bets)
  perform _ledger_post(
    p_winner_id, v_payout, 'payout',
    'cora_payout:' || v_room_id,
    'cora_dice', v_room_id,
    jsonb_build_object(
      'pot', p_pot,
      'house_cut_pct', v_house_pct,
      'cut', v_cut,
      'game_id', p_game_id,    -- garde le game_id en metadata pour audit
      'room_id', v_room_id
    )
  );

  -- Debit caisse jeu
  begin
    update game_treasury
      set balance        = balance - p_pot,
          total_paid_out = total_paid_out + p_pot,
          updated_at     = now()
      where id = 1;
  exception when undefined_table then null;
  end;

  -- Commission vers admin
  if v_cut > 0 then
    begin
      update admin_treasury
        set balance      = balance + v_cut,
            total_earned = total_earned + v_cut,
            updated_at   = now()
        where id = 1;
      if not found then
        insert into admin_treasury(id, balance, total_earned, total_withdrawn)
          values (1, v_cut, v_cut, 0);
      end if;
    exception when undefined_table then null;
    end;
  end if;
end; $$;

revoke all on function public.cora_pay_winner(uuid, text, bigint, numeric, uuid[])
  from public, anon, authenticated;

-- ============================================================
-- 2) cora_refund_participants : utilise room_id dans request_id
-- ============================================================
create or replace function public.cora_refund_participants(
  p_game_id     text,
  p_user_ids    uuid[],
  p_amount_each bigint
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_uid     uuid;
  v_n       int := coalesce(array_length(p_user_ids, 1), 0);
  v_total   bigint := p_amount_each * v_n;
  v_room_id text;
begin
  if v_total = 0 or v_n = 0 then return; end if;

  -- Resolve room_id (cf cora_pay_winner ci-dessus)
  select room_id::text into v_room_id from cora_games
    where id = p_game_id::uuid limit 1;
  if v_room_id is null then v_room_id := p_game_id; end if;

  foreach v_uid in array p_user_ids loop
    perform _ledger_post(
      v_uid, p_amount_each, 'refund',
      'cora_refund:' || v_room_id || ':' || v_uid::text,
      'cora_dice', v_room_id,
      jsonb_build_object(
        'reason', 'tie_or_cancel',
        'game_id', p_game_id,   -- garde le game_id en metadata pour audit
        'room_id', v_room_id
      )
    );
  end loop;

  -- Debit caisse jeu
  begin
    update game_treasury
      set balance        = balance - v_total,
          total_paid_out = total_paid_out + v_total,
          updated_at     = now()
      where id = 1;
  exception when undefined_table then null;
  end;
end; $$;

revoke all on function public.cora_refund_participants(text, uuid[], bigint)
  from public, anon, authenticated;

commit;

-- ============================================================
-- VERIFICATION (apres execution + 1-2 nouvelles parties cora_dice)
-- ============================================================
-- 1. Les NOUVEAUX payouts doivent avoir room_id dans request_id ET
--    le room_id stocke en metadata :
--    select request_id, metadata
--    from wallet_ledger
--    where game_type = 'cora_dice' and type = 'payout'
--    order by id desc limit 3;
--
-- 2. La requete de match game_id devrait montrer 0 'orphans' pour les
--    nouvelles parties :
--    with bet_games as (
--      select distinct split_part(request_id, ':', 2) as gid
--      from wallet_ledger
--      where game_type = 'cora_dice' and type = 'bet'
--        and created_at > now() - interval '1 hour'
--    ),
--    payout_games as (
--      select distinct split_part(request_id, ':', 2) as gid
--      from wallet_ledger
--      where game_type = 'cora_dice' and type in ('payout','refund')
--        and created_at > now() - interval '1 hour'
--    )
--    select 'payouts orphans (1h)' as label, count(*)
--      from payout_games where gid not in (select gid from bet_games);
--    -- Doit retourner 0.
