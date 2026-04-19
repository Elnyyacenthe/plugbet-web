-- ============================================================
-- Dashboard Admin — Setup de la table user_profiles
-- Ajoute les colonnes `role`, `email`, `is_blocked` attendues par le dashboard
-- ============================================================

-- 1. Colonnes manquantes sur user_profiles
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'user'
    CHECK (role IN ('user','admin','super_admin','banned')),
  ADD COLUMN IF NOT EXISTS email TEXT,
  ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN NOT NULL DEFAULT false;

-- 2. Index pour recherche par role
CREATE INDEX IF NOT EXISTS idx_user_profiles_role
  ON user_profiles(role)
  WHERE role IN ('admin','super_admin');

-- 3. Synchroniser l'email depuis auth.users quand un utilisateur se connecte
-- (trigger automatique)
CREATE OR REPLACE FUNCTION sync_user_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE user_profiles
    SET email = NEW.email
    WHERE id = NEW.id AND (email IS NULL OR email != NEW.email);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_user_email_trigger ON auth.users;
CREATE TRIGGER sync_user_email_trigger
  AFTER INSERT OR UPDATE OF email ON auth.users
  FOR EACH ROW EXECUTE FUNCTION sync_user_email();

-- 4. RPC pour promouvoir un utilisateur admin par email
-- A executer une seule fois pour creer le premier admin
CREATE OR REPLACE FUNCTION promote_to_admin(p_email TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  -- Trouver l'user via son email dans auth.users
  SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = p_email;

  IF v_user_id IS NULL THEN
    RETURN 'ERREUR : aucun utilisateur avec l''email ' || p_email;
  END IF;

  -- Mettre a jour son profil
  UPDATE user_profiles
    SET role = 'super_admin',
        email = p_email
    WHERE id = v_user_id;

  IF NOT FOUND THEN
    -- Le profil n'existe pas : on le cree
    INSERT INTO user_profiles (id, username, email, role, coins)
      VALUES (
        v_user_id,
        'Admin',
        p_email,
        'super_admin',
        10000
      );
  END IF;

  RETURN 'OK : utilisateur ' || p_email || ' est maintenant super_admin';
END;
$$;

-- 5. Policies RLS pour que les admins puissent lire toutes les tables
-- (Dashboard a besoin de voir tous les users, tickets, etc.)
DROP POLICY IF EXISTS "Admins read all profiles" ON user_profiles;
CREATE POLICY "Admins read all profiles"
  ON user_profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid()
        AND role IN ('admin','super_admin')
    )
  );

DROP POLICY IF EXISTS "Admins update profiles" ON user_profiles;
CREATE POLICY "Admins update profiles"
  ON user_profiles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid()
        AND role IN ('admin','super_admin')
    )
  );

-- Meme chose pour support_tickets
DROP POLICY IF EXISTS "Admins read all tickets" ON support_tickets;
CREATE POLICY "Admins read all tickets"
  ON support_tickets FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid()
        AND role IN ('admin','super_admin')
    )
  );

DROP POLICY IF EXISTS "Admins update all tickets" ON support_tickets;
CREATE POLICY "Admins update all tickets"
  ON support_tickets FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid()
        AND role IN ('admin','super_admin')
    )
  );

-- Meme chose pour support_messages
DROP POLICY IF EXISTS "Admins read all messages" ON support_messages;
CREATE POLICY "Admins read all messages"
  ON support_messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid()
        AND role IN ('admin','super_admin')
    )
  );

DROP POLICY IF EXISTS "Admins insert admin messages" ON support_messages;
CREATE POLICY "Admins insert admin messages"
  ON support_messages FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles
      WHERE id = auth.uid()
        AND role IN ('admin','super_admin')
    )
  );

-- 6. Creer ton premier admin
-- REMPLACE 'ton@email.com' par ton vrai email, puis execute
-- cette ligne UNE SEULE FOIS apres avoir cree un compte via l'app
-- avec cet email (mode signup email+password).
--
-- Exemple :
-- SELECT promote_to_admin('ludovicnkoulou3@gmail.com');
