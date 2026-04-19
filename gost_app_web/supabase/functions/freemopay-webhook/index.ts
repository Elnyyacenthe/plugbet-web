// ============================================================
// Freemopay Webhook Handler
// Reçoit les callbacks de Freemopay et traite les paiements
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface FreemopayCallback {
  status: 'SUCCESS' | 'FAILED'
  reference: string
  amount: number
  transactionType: 'DEPOSIT' | 'WITHDRAW'
  externalId: string
  message: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Parse callback payload
    const payload: FreemopayCallback = await req.json()
    console.log('Freemopay callback received:', payload)

    const { status, reference, amount, transactionType, externalId, message } = payload

    // 1. Récupérer la transaction depuis freemopay_transactions
    const { data: transaction, error: txError } = await supabase
      .from('freemopay_transactions')
      .select('*')
      .eq('reference', reference)
      .single()

    if (txError || !transaction) {
      console.error('Transaction not found:', reference)
      return new Response(
        JSON.stringify({ error: 'Transaction not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Éviter les doublons (idempotence)
    if (transaction.status === 'SUCCESS' || transaction.status === 'FAILED') {
      console.log('Transaction already processed:', reference)
      return new Response(
        JSON.stringify({ success: true, message: 'Already processed' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const userId = transaction.user_id

    // 2. Mettre à jour le statut de la transaction
    await supabase
      .from('freemopay_transactions')
      .update({
        status,
        message,
        callback_data: payload,
        updated_at: new Date().toISOString(),
      })
      .eq('reference', reference)

    // 3. Si SUCCESS, créditer/débiter le wallet
    if (status === 'SUCCESS') {
      if (transactionType === 'DEPOSIT') {
        // Créditer le wallet via RPC atomique
        const { error: rpcError } = await supabase.rpc('wallet_apply_delta', {
          p_user_id: userId,
          p_delta: amount,
          p_source: 'freemopay_deposit',
          p_reference_id: reference,
          p_note: `Dépôt Freemopay: ${message}`,
        })

        if (rpcError) {
          console.error('Failed to credit wallet:', rpcError)
          return new Response(
            JSON.stringify({ error: 'Failed to credit wallet', details: rpcError }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        console.log(`✅ Deposited ${amount} coins to user ${userId}`)
      } else if (transactionType === 'WITHDRAW') {
        // Retrait : les coins ont déjà été débités côté client
        // Rien à faire ici, juste logger
        console.log(`✅ Withdrawal of ${amount} coins confirmed for user ${userId}`)
      }
    } else if (status === 'FAILED') {
      // En cas d'échec de retrait, re-créditer les coins
      if (transactionType === 'WITHDRAW') {
        const { error: rpcError } = await supabase.rpc('wallet_apply_delta', {
          p_user_id: userId,
          p_delta: amount,
          p_source: 'freemopay_withdrawal_refund',
          p_reference_id: reference,
          p_note: `Retrait échoué: ${message}`,
        })

        if (rpcError) {
          console.error('Failed to refund wallet:', rpcError)
        } else {
          console.log(`♻️ Refunded ${amount} coins to user ${userId}`)
        }
      }

      console.log(`❌ Transaction failed: ${message}`)
    }

    // 4. Réponse à Freemopay
    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Webhook error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
