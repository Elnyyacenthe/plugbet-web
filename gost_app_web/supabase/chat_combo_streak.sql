-- ============================================================
-- Chat Combo Streak — style multiplicateur paris
-- Incremente quand les 2 utilisateurs echangent dans les 24h
-- Reset a 0 si > 48h sans echange reciproque
-- ============================================================

-- 1. Colonnes ajoutees a la table conversations
ALTER TABLE conversations
  ADD COLUMN IF NOT EXISTS combo_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS combo_max INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS combo_last_user1_msg_date DATE,
  ADD COLUMN IF NOT EXISTS combo_last_user2_msg_date DATE,
  ADD COLUMN IF NOT EXISTS combo_last_increment_date DATE;


-- 2. Fonction a appeler cote client apres chaque message envoye
-- Logique:
--   - Si les 2 utilisateurs ont envoye un message aujourd'hui (ou depuis hier) :
--     * Si combo_last_increment_date < aujourd'hui → incremente combo_count
--     * Met a jour combo_max si depassement
--   - Si le dernier echange reciproque date de > 2 jours → reset a 0
--   - Retourne le nouveau combo
CREATE OR REPLACE FUNCTION update_chat_combo(
  p_conversation_id UUID,
  p_from_user_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_conv       conversations%ROWTYPE;
  v_today      DATE := CURRENT_DATE;
  v_yesterday  DATE := CURRENT_DATE - INTERVAL '1 day';
  v_is_user1   BOOLEAN;
  v_new_combo  INT;
  v_new_max    INT;
  v_u1_date    DATE;
  v_u2_date    DATE;
  v_incr_today BOOLEAN := false;
BEGIN
  -- Verifier auth
  IF p_from_user_id != auth.uid() THEN
    RETURN jsonb_build_object('error', 'unauthorized');
  END IF;

  -- Lock la conversation
  SELECT * INTO v_conv
    FROM conversations
    WHERE id = p_conversation_id
    FOR UPDATE;

  IF v_conv IS NULL THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;

  -- Verifier que l'utilisateur fait bien partie de la conversation
  IF p_from_user_id != v_conv.user1_id AND p_from_user_id != v_conv.user2_id THEN
    RETURN jsonb_build_object('error', 'not_member');
  END IF;

  v_is_user1 := (p_from_user_id = v_conv.user1_id);

  -- Mettre a jour la date du dernier message de l'envoyeur
  IF v_is_user1 THEN
    v_u1_date := v_today;
    v_u2_date := v_conv.combo_last_user2_msg_date;
  ELSE
    v_u1_date := v_conv.combo_last_user1_msg_date;
    v_u2_date := v_today;
  END IF;

  v_new_combo := v_conv.combo_count;
  v_new_max := v_conv.combo_max;

  -- Decider si on incremente
  -- Condition : les 2 utilisateurs ont un message aujourd'hui OU hier (echange recent)
  IF v_u1_date IS NOT NULL AND v_u2_date IS NOT NULL THEN
    -- Les 2 ont envoye recemment (today ou yesterday)
    IF v_u1_date >= v_yesterday AND v_u2_date >= v_yesterday THEN
      -- Eviter de doubler l'increment dans la meme journee
      IF v_conv.combo_last_increment_date IS NULL
         OR v_conv.combo_last_increment_date < v_today THEN
        v_new_combo := v_conv.combo_count + 1;
        v_incr_today := true;
        IF v_new_combo > v_new_max THEN
          v_new_max := v_new_combo;
        END IF;
      END IF;
    -- Reset si echange trop ancien (> 2 jours depuis l'un des deux)
    ELSIF v_u1_date < v_yesterday - INTERVAL '1 day'
       OR v_u2_date < v_yesterday - INTERVAL '1 day' THEN
      v_new_combo := 0;
    END IF;
  END IF;

  -- Ecriture
  UPDATE conversations SET
    combo_count = v_new_combo,
    combo_max = v_new_max,
    combo_last_user1_msg_date = v_u1_date,
    combo_last_user2_msg_date = v_u2_date,
    combo_last_increment_date = CASE
      WHEN v_incr_today THEN v_today
      ELSE combo_last_increment_date
    END
  WHERE id = p_conversation_id;

  RETURN jsonb_build_object(
    'combo_count', v_new_combo,
    'combo_max', v_new_max,
    'incremented', v_incr_today
  );
END;
$$;
