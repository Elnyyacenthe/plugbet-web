-- ============================================================
-- FIX: Permettre aux utilisateurs authentifiés de lire app_settings
-- Problème: Les utilisateurs ne peuvent pas faire de deposit/withdrawal
--           car loadConfig() échoue à cause du RLS trop restrictif
-- ============================================================

-- Supprimer l'ancienne policy restrictive
DROP POLICY IF EXISTS "Admins can read app settings" ON app_settings;

-- Nouvelle policy: Tous les utilisateurs authentifiés peuvent lire app_settings
-- NOTE: Les credentials Freemopay sont nécessaires côté client pour faire les appels API
--       À terme, migrer vers Edge Functions pour plus de sécurité
CREATE POLICY "Authenticated users can read app settings"
  ON app_settings
  FOR SELECT
  USING (auth.role() = 'authenticated');

-- Les autres policies restent inchangées (seuls les admins peuvent modifier)
