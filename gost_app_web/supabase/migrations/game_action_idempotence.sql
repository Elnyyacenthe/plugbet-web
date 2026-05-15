-- ============================================================
-- GAME ACTION IDEMPOTENCE (P2b)
-- ============================================================
-- Probleme : cf_choose_side, bj_hit, cora_submit_roll ne sont PAS
-- idempotents. Si le client retry apres un timeout (action reellement
-- passee mais reponse perdue), l'action est rejouee :
--   - bj_hit -> 2 cartes piochees
--   - cora_submit_roll -> 2 lancers
--   - cf_choose_side -> 2e choix (ou erreur "already chosen")
--
-- Solution : wrappers *_idem avec pattern CLAIM-FIRST :
--   1. INSERT request_id dans game_action_dedup (PK unique)
--   2. Si unique_violation -> deja traite/en cours -> return deduped
--   3. Sinon on a le claim exclusif -> execute l'action reelle
--   4. Si l'action throw -> rollback complet (claim libere, retry OK)
--
-- Le client genere UN request_id par action utilisateur et le
-- reutilise sur chaque retry (NetworkRetry).
--
-- Idempotent (CREATE OR REPLACE / IF NOT EXISTS).
-- ============================================================

begin;

-- ============================================================
-- 1) Table dedup
-- ============================================================
create table if not exists public.game_action_dedup (
  request_id text primary key,
  user_id    uuid,
  action     text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_gad_created
  on public.game_action_dedup (created_at);

alter table public.game_action_dedup enable row level security;
-- Aucune policy : seules les fonctions SECURITY DEFINER y accedent.

-- Purge auto > 24h (le retry utile est dans les minutes, pas les jours)
create or replace function public.game_action_dedup_purge()
returns int language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  with d as (
    delete from public.game_action_dedup
    where created_at < now() - interval '24 hours'
    returning 1
  ) select count(*) into v_n from d;
  return v_n;
end $$;
revoke all on function public.game_action_dedup_purge() from public, anon, authenticated;

-- ============================================================
-- 2) Wrapper Coinflip : cf_choose_side_idem
-- ============================================================
create or replace function public.cf_choose_side_idem(
  p_game_id uuid,
  p_choice text,
  p_request_id text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_request_id is null or length(p_request_id) = 0 then
    raise exception 'MISSING_REQUEST_ID';
  end if;

  -- CLAIM-FIRST : si deja claim -> deduped (retry ou double-tap)
  begin
    insert into public.game_action_dedup (request_id, user_id, action)
    values (p_request_id, v_uid, 'cf_choose_side');
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'deduped', true);
  end;

  -- Claim exclusif obtenu : execute l'action reelle.
  -- Si elle throw, la transaction rollback (claim libere -> retry OK).
  perform public.cf_choose_side(p_game_id, p_choice);
  return jsonb_build_object('ok', true, 'deduped', false);
end $$;
grant execute on function public.cf_choose_side_idem(uuid, text, text) to authenticated;

-- ============================================================
-- 3) Wrapper Blackjack : bj_hit_idem + bj_stand_idem
-- ============================================================
create or replace function public.bj_hit_idem(
  p_game_id uuid,
  p_request_id text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_request_id is null or length(p_request_id) = 0 then
    raise exception 'MISSING_REQUEST_ID';
  end if;

  begin
    insert into public.game_action_dedup (request_id, user_id, action)
    values (p_request_id, v_uid, 'bj_hit');
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'deduped', true);
  end;

  perform public.bj_hit(p_game_id);
  return jsonb_build_object('ok', true, 'deduped', false);
end $$;
grant execute on function public.bj_hit_idem(uuid, text) to authenticated;

create or replace function public.bj_stand_idem(
  p_game_id uuid,
  p_request_id text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_request_id is null or length(p_request_id) = 0 then
    raise exception 'MISSING_REQUEST_ID';
  end if;

  begin
    insert into public.game_action_dedup (request_id, user_id, action)
    values (p_request_id, v_uid, 'bj_stand');
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'deduped', true);
  end;

  perform public.bj_stand(p_game_id);
  return jsonb_build_object('ok', true, 'deduped', false);
end $$;
grant execute on function public.bj_stand_idem(uuid, text) to authenticated;

-- ============================================================
-- 4) Wrapper Cora : cora_submit_roll_idem
-- ============================================================
-- cora_submit_roll retourne la valeur des des. En cas de retry deduped
-- on ne peut PAS rejouer (sinon nouveau lancer). Le client recupere de
-- toute facon le resultat via realtime/polling sur game_state.
-- On renvoie deduped=true sans valeur -> le client se base sur le state.
create or replace function public.cora_submit_roll_idem(
  p_game_id uuid,
  p_request_id text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then raise exception 'NOT_AUTH'; end if;
  if p_request_id is null or length(p_request_id) = 0 then
    raise exception 'MISSING_REQUEST_ID';
  end if;

  begin
    insert into public.game_action_dedup (request_id, user_id, action)
    values (p_request_id, v_uid, 'cora_submit_roll');
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'deduped', true);
  end;

  -- cora_submit_roll renvoie le resultat du lancer (jsonb attendu)
  v_result := public.cora_submit_roll(p_game_id);
  return jsonb_build_object('ok', true, 'deduped', false, 'roll', v_result);
end $$;
grant execute on function public.cora_submit_roll_idem(uuid, text) to authenticated;

-- ============================================================
-- 5) Cron purge quotidien
-- ============================================================
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule('game_action_dedup_purge')
      where exists (select 1 from cron.job where jobname = 'game_action_dedup_purge');
    perform cron.schedule('game_action_dedup_purge', '0 3 * * *',
      $cron$ select public.game_action_dedup_purge(); $cron$);
  end if;
end $$;

commit;

-- ============================================================
-- VERIFICATIONS
-- ============================================================
-- 1) Les 4 wrappers existent
--    select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='public' and proname in (
--      'cf_choose_side_idem','bj_hit_idem','bj_stand_idem','cora_submit_roll_idem');
--    -- doit retourner 4 lignes
--
-- 2) Test double-call meme request_id :
--    select public.bj_hit_idem('<game>', 'test-req-1');  -- {deduped:false}
--    select public.bj_hit_idem('<game>', 'test-req-1');  -- {deduped:true} (pas de 2e carte)
--
-- 3) cora_submit_roll : verifier la signature reelle.
--    Si cora_submit_roll(p_game_id) ne renvoie pas jsonb mais autre chose,
--    adapter le cast 'roll' dans cora_submit_roll_idem.
