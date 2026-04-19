-- ============================================================
-- FIX URGENT : recursion infinie dans les RLS policies admin
-- A executer IMMEDIATEMENT dans Supabase SQL Editor
-- ============================================================

-- 1. Supprimer les policies qui causent la recursion
DROP POLICY IF EXISTS "Admins read all profiles" ON user_profiles;
DROP POLICY IF EXISTS "Admins update profiles" ON user_profiles;
DROP POLICY IF EXISTS "Admins read all tickets" ON support_tickets;
DROP POLICY IF EXISTS "Admins update all tickets" ON support_tickets;
DROP POLICY IF EXISTS "Admins read all messages" ON support_messages;
DROP POLICY IF EXISTS "Admins insert admin messages" ON support_messages;

-- 2. Creer une fonction helper SECURITY DEFINER qui bypass RLS
-- (elle lit user_profiles sans declencher ses propres policies)
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  SELECT role INTO v_role
    FROM public.user_profiles
    WHERE id = auth.uid();
  RETURN v_role IN ('admin', 'super_admin');
END;
$$;

-- 3. Recreer les policies admin en utilisant is_admin()
-- (plus de recursion car la fonction bypass RLS)

-- user_profiles : les admins peuvent tout lire
CREATE POLICY "Admins read all profiles"
  ON user_profiles FOR SELECT
  USING (is_admin());

CREATE POLICY "Admins update profiles"
  ON user_profiles FOR UPDATE
  USING (is_admin());

-- support_tickets
CREATE POLICY "Admins read all tickets"
  ON support_tickets FOR SELECT
  USING (is_admin());

CREATE POLICY "Admins update all tickets"
  ON support_tickets FOR UPDATE
  USING (is_admin());

-- support_messages
CREATE POLICY "Admins read all messages"
  ON support_messages FOR SELECT
  USING (is_admin());

CREATE POLICY "Admins insert admin messages"
  ON support_messages FOR INSERT
  WITH CHECK (is_admin());
