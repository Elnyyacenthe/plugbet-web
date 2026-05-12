// ============================================================
// SEND ANNOUNCEMENT PUSH — FCM v1 broadcaster
// ============================================================
// Edge Function declenchee automatiquement par un trigger Postgres
// quand une ligne est inseree dans `app_announcements`.
// Lit tous les push_tokens valides et envoie une notification push
// FCM v1 a chaque appareil enregistre.
//
// Secrets Supabase requis :
//   - FIREBASE_SERVICE_ACCOUNT  : JSON complet du service account Firebase
//                                  (Project Settings > Service accounts > Generate new key)
//   - SUPABASE_URL              : auto-injecte par Supabase
//   - SUPABASE_SERVICE_ROLE_KEY : auto-injecte par Supabase
// ============================================================

// deno-lint-ignore-file no-explicit-any
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create as jwtCreate, getNumericDate } from 'https://deno.land/x/djwt@v3.0.2/mod.ts';

interface Announcement {
  id: string;
  title: string;
  body: string;
  severity: string;
  target_role: 'all' | 'user' | 'admin' | 'super_admin';
  active: boolean;
  expires_at: string | null;
}

const FIREBASE_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

// ─── Helper : importer la cle privee PEM RSA en CryptoKey ───────────
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

// ─── Echange JWT contre access_token Google OAuth2 ───
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
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`OAuth2 failed: ${res.status} ${txt}`);
  }
  const data = await res.json();
  return data.access_token;
}

// ─── Envoi FCM v1 unitaire ──────────────────────────
async function sendFcm(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; error?: string }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const payload = {
    message: {
      token,
      notification: { title, body },
      data,
      android: {
        priority: 'HIGH',
        notification: {
          channel_id: 'push_messages',
          default_sound: true,
        },
      },
      apns: {
        payload: { aps: { sound: 'default' } },
      },
    },
  };
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  if (res.ok) return { ok: true };
  const text = await res.text();
  return { ok: false, error: `${res.status} ${text}` };
}

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    const body = await req.json();
    const announcementId: string | undefined = body.announcement_id;
    if (!announcementId) {
      return new Response(JSON.stringify({ error: 'announcement_id required' }), { status: 400 });
    }

    // ─── Init Supabase admin client ───
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(supabaseUrl, serviceKey);

    // ─── Charger l'annonce ───
    const { data: ann, error: annErr } = await admin
      .from('app_announcements')
      .select('*')
      .eq('id', announcementId)
      .maybeSingle();
    if (annErr || !ann) {
      return new Response(JSON.stringify({ error: 'Announcement not found', detail: annErr?.message }), { status: 404 });
    }
    const announcement = ann as Announcement;
    if (!announcement.active) {
      return new Response(JSON.stringify({ skipped: true, reason: 'inactive' }), { status: 200 });
    }

    // ─── Charger les push_tokens cibles ───
    // target_role 'all' ou 'user' => tous les tokens
    // target_role 'admin' => admins only
    let tokensQuery = admin.from('push_tokens').select('token, user_id');
    if (announcement.target_role === 'admin' || announcement.target_role === 'super_admin') {
      // Filtrer via user_profiles.role
      const { data: adminUsers } = await admin
        .from('user_profiles')
        .select('id')
        .in('role', announcement.target_role === 'super_admin' ? ['super_admin'] : ['admin', 'super_admin']);
      const ids = (adminUsers ?? []).map((u: any) => u.id);
      if (ids.length === 0) {
        return new Response(JSON.stringify({ sent: 0, skipped: 'no admins' }), { status: 200 });
      }
      tokensQuery = tokensQuery.in('user_id', ids);
    }

    const { data: tokens, error: tokErr } = await tokensQuery;
    if (tokErr) {
      return new Response(JSON.stringify({ error: 'Failed to load tokens', detail: tokErr.message }), { status: 500 });
    }

    if (!tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ sent: 0, message: 'no tokens' }), { status: 200 });
    }

    // ─── Charger Firebase Service Account ───
    const sa = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!sa) {
      return new Response(JSON.stringify({ error: 'FIREBASE_SERVICE_ACCOUNT not set' }), { status: 500 });
    }
    let serviceAccount: any;
    try {
      serviceAccount = JSON.parse(sa);
    } catch (e) {
      return new Response(JSON.stringify({ error: 'Invalid FIREBASE_SERVICE_ACCOUNT JSON', detail: (e as Error).message }), { status: 500 });
    }
    const projectId = serviceAccount.project_id;

    // ─── Auth Google + envoi en parallele ───
    const accessToken = await getAccessToken(serviceAccount);

    const data = {
      type: 'announcement',
      announcement_id: announcement.id,
      severity: announcement.severity,
    };

    let sent = 0, failed = 0;
    const invalidTokens: string[] = [];

    // Limit a 100 en parallele pour eviter rate-limit
    const BATCH = 100;
    for (let i = 0; i < tokens.length; i += BATCH) {
      const slice = tokens.slice(i, i + BATCH);
      const results = await Promise.all(
        slice.map(async (t: any) => {
          const r = await sendFcm(projectId, accessToken, t.token, announcement.title, announcement.body, data);
          if (r.ok) {
            sent++;
          } else {
            failed++;
            // Tokens invalides => suppression
            if (r.error && (r.error.includes('UNREGISTERED') || r.error.includes('INVALID_ARGUMENT'))) {
              invalidTokens.push(t.token);
            }
          }
          return r;
        }),
      );
      void results;
    }

    // Cleanup tokens invalides
    if (invalidTokens.length > 0) {
      await admin.from('push_tokens').delete().in('token', invalidTokens);
    }

    return new Response(
      JSON.stringify({
        announcement_id: announcement.id,
        total_tokens: tokens.length,
        sent,
        failed,
        invalid_removed: invalidTokens.length,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: 'Internal error', detail: (e as Error).message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
});
