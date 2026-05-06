// ============================================================
// Edge Function : Cron Ludo V2 (alternative à pg_cron)
// ============================================================
// Appelle cette URL toutes les 15 min via cron-job.org / Render / Vercel Cron
//
// Headers requis :
//   Authorization: Bearer <CRON_SECRET>  (configure CRON_SECRET dans Supabase secrets)
//
// Comportement :
//   1. cleanup_stale_games (toutes les 15 min)
//   2. cleanup_rate_limits (toutes les heures - basé sur l'heure ronde)
//   3. daily_snapshot (à 00:00-00:14 UTC)
//   4. reconcile + alert si imbalance (toutes les heures)
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

Deno.serve(async (req) => {
  // Authentification simple par secret
  const auth = req.headers.get('Authorization') ?? ''
  const expected = Deno.env.get('CRON_SECRET') ?? ''
  if (!expected || !auth.includes(expected)) {
    return new Response('Unauthorized', { status: 401 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '', // service role pour bypass RLS
  )

  const now = new Date()
  const minute = now.getUTCMinutes()
  const hour = now.getUTCHours()
  const results: Record<string, unknown> = { ranAt: now.toISOString() }

  // 1. Toujours : cleanup stale games (toutes les 15 min)
  try {
    const { data, error } = await supabase.rpc('ludo_v2_cleanup_stale')
    results.cleanup = error ? { error: error.message } : data
  } catch (e) {
    results.cleanup = { error: String(e) }
  }

  // 2. Toutes les heures (à minute 0-14) : cleanup rate limits + reconcile
  if (minute < 15) {
    try {
      const { data, error } = await supabase.rpc('cleanup_old_rate_limits')
      results.rateCleanup = error ? { error: error.message } : { deleted: data }
    } catch (e) {
      results.rateCleanup = { error: String(e) }
    }

    try {
      const { data, error } = await supabase.rpc('reconcile_money_system')
      results.reconcile = error ? { error: error.message } : data
      if (data && data.consistent === false) {
        await supabase.rpc('raise_admin_alert', {
          p_type: 'money_imbalance',
          p_severity: 'critical',
          p_title: 'Réconciliation échec',
          p_description: `Diff = ${data.diff} coins`,
          p_context: data,
        })
        results.alertRaised = true
      }
    } catch (e) {
      results.reconcile = { error: String(e) }
    }
  }

  // 3. Tous les jours à 00:00-00:14 UTC : snapshot
  if (hour === 0 && minute < 15) {
    try {
      const { data, error } = await supabase.rpc('create_treasury_snapshot')
      results.snapshot = error ? { error: error.message } : data
    } catch (e) {
      results.snapshot = { error: String(e) }
    }
  }

  return new Response(JSON.stringify(results, null, 2), {
    headers: { 'Content-Type': 'application/json' },
  })
})
