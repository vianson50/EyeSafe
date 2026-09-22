-- ═══════════════════════════════════════════════════════════
-- EYESAFE — Backfill des profils
--
-- À exécuter APRÈS la migration initiale, une seule fois :
-- crée les profils des utilisateurs auth.users créés avant
-- l'installation du trigger on_auth_user_created.
-- Idempotent : les profils existants sont ignorés.
-- ═══════════════════════════════════════════════════════════
insert into public.profiles (id, full_name)
select u.id,
       coalesce(u.raw_user_meta_data ->> 'full_name', split_part(u.email, '@', 1))
from auth.users u
where not exists (
  select 1 from public.profiles p where p.id = u.id
);
