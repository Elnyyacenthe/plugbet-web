-- ============================================================
-- SUPPORT MESSAGES — image attachment support
-- ============================================================
-- Ajoute la colonne image_url + politique de stockage pour permettre
-- l'envoi de photos dans les conversations support.
-- Reutilise le bucket 'chat-media' deja existant pour eviter une nouvelle
-- config de bucket / RLS.
-- ============================================================

alter table public.support_messages
  add column if not exists image_url text;

-- content devient nullable (un message peut etre 100% image)
alter table public.support_messages
  alter column content drop not null;

-- Garde-fou : au moins un des deux doit etre present
do $$ begin
  alter table public.support_messages
    add constraint support_messages_content_or_image_required
    check (
      (content is not null and length(trim(content)) > 0)
      or (image_url is not null and length(image_url) > 0)
    );
exception when duplicate_object then null;
end $$;

-- ============================================================
-- Politique storage : un user peut uploader/lire sous
-- chat-media/support/<ticket_id>/ pour ses propres tickets
-- ============================================================
do $$ begin
  insert into storage.buckets (id, name, public)
    values ('chat-media', 'chat-media', true)
  on conflict (id) do nothing;
exception when others then null;
end $$;

-- Si la policy existe deja sous un autre nom, on tolere
drop policy if exists "support_attach_owner_upload" on storage.objects;
create policy "support_attach_owner_upload"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[1] = 'support'
    and exists (
      select 1 from public.support_tickets t
      where t.id::text = (storage.foldername(name))[2]
        and t.user_id = auth.uid()
    )
  );

drop policy if exists "support_attach_owner_read" on storage.objects;
create policy "support_attach_owner_read"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'chat-media'
    and (
      (storage.foldername(name))[1] != 'support'
      or exists (
        select 1 from public.support_tickets t
        where t.id::text = (storage.foldername(name))[2]
          and (t.user_id = auth.uid()
               or coalesce((select role from public.user_profiles where id = auth.uid()), '') = 'super_admin')
      )
    )
  );
