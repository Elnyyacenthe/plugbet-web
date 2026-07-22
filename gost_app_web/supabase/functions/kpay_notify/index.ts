// ============================================================
// Edge Function : kpay_notify
// ============================================================
// Envoie une notification push (FCM v1) a UN utilisateur precis.
// Appelee en fire-and-forget par kpay_webhook / kpay_reconcile /
// kpay_tx_watcher quand un depot est credite ou un retrait
// finalise/rembourse -> le joueur est prevenu meme app fermee,
// sans ecran d'attente bloquant.
//
// AUTH (interne) : header x-internal-secret == CRON_SECRET
// INPUT  : { user_id, title, body, data? }
// SECRET requis : FIREBASE_SERVICE_ACCOUNT (deja configure pour
//                 send-announcement-push), CRON_SECRET
// config.toml : verify_jwt = false
// ============================================================

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create as jwtCreate, getNumericDate } from 'https://deno.land/x/djwt@v3.0.2/mod.ts';

const FIREBASE_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8', der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
}

async function getAccessToken(serviceAccount: any): Promise<string> {
  const key = await importPrivateKey(serviceAccount.private_key);
  const jwt = await jwtCreate(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: serviceAccount.client_email,
      scope: FIREBASE_SCOPE,
      aud: 'https://oauth2.googleapis.com/token',
      iat: getNumericDate(0),
      exp: getNumericDate(60 * 60),
    },
    key,
  );
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`OAuth2 failed: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

async function sendFcm(
  projectId: string, accessToken: string, token: string,
  title: string, body: string, data: Record<string, string>,
): Promise<boolean> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: { priority: 'HIGH', notification: { channel_id: 'push_messages', default_sound: true } },
          apns: { payload: { aps: { sound: 'default' } } },
        },
      }),
    },
  );
  return res.ok;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const expected = Deno.env.get('CRON_SECRET') ?? '';
  const got = req.headers.get('x-internal-secret') ?? '';
  if (!expected || got !== expected) {
    return new Response(JSON.stringify({ error: 'UNAUTHORIZED' }), { status: 401 });
  }

  let body: { user_id?: string; title?: string; body?: string; data?: Record<string, string> };
  try { body = await req.json(); } catch {
    return new Response(JSON.stringify({ error: 'INVALID_JSON' }), { status: 400 });
  }
  const userId = String(body.user_id ?? '');
  const title = String(body.title ?? '');
  const text = String(body.body ?? '');
  if (!userId || !title || !text) {
    return new Response(JSON.stringify({ error: 'MISSING_FIELDS' }), { status: 400 });
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: tokens } = await admin
    .from('push_tokens').select('token').eq('user_id', userId);
  if (!tokens || tokens.length === 0) {
    return new Response(JSON.stringify({ sent: 0, reason: 'no_tokens' }), { status: 200 });
  }

  const sa = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
  if (!sa) return new Response(JSON.stringify({ error: 'FIREBASE_SERVICE_ACCOUNT not set' }), { status: 500 });
  let serviceAccount: any;
  try { serviceAccount = JSON.parse(sa); } catch (e) {
    return new Response(JSON.stringify({ error: 'Invalid FIREBASE_SERVICE_ACCOUNT', detail: (e as Error).message }), { status: 500 });
  }

  const accessToken = await getAccessToken(serviceAccount);
  const projectId = serviceAccount.project_id;
  const data = { type: 'kpay', ...(body.data ?? {}) };

  let sent = 0;
  for (const t of tokens as Array<{ token: string }>) {
    try { if (await sendFcm(projectId, accessToken, t.token, title, text, data)) sent++; }
    catch { /* ignore individual token failure */ }
  }

  return new Response(JSON.stringify({ sent, total: tokens.length }), { status: 200 });
});
