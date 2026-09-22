// ═══════════════════════════════════════════════════════════════
// EYESAFE — Edge Function « push-notify »
//
// Appelée par le trigger SQL (pg_net) à chaque insertion dans
// public.notifications. Envoie le push FCM à l'appareil de
// l'utilisateur visé (profiles.fcm_token).
//
// Sécurité : vérifie le header Authorization = service_role.
// Secret requis (dashboard → Edge Functions → Secrets) :
//   GOOGLE_SERVICE_ACCOUNT_JSON = contenu complet de la clé du
//   compte de service Firebase (Project Settings → Service accounts
//   → Generate new private key).
// ═══════════════════════════════════════════════════════════════
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { decode } from 'https://deno.land/std@0.208.0/encoding/base64.ts';

const encoder = new TextEncoder();

function base64Url(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function rsaSign(privateKeyPem: string, data: string): Promise<Uint8Array> {
  const pem = privateKeyPem.replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(data)),
  );
}

async function getAccessToken(serviceAccount: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64Url(encoder.encode(JSON.stringify(header)))}.${base64Url(encoder.encode(JSON.stringify(claims)))}`;
  const signature = await rsaSign(serviceAccount.private_key, unsigned);
  const jwt = `${unsigned}.${base64Url(signature)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`oauth: ${res.status} ${await res.text()}`);
  return (await res.json()).access_token;
}

Deno.serve(async (req) => {
  // ── Authentification : la clé fournie doit être une clé service valide.
  // Validation dynamique via l'API admin — accepte l'ancien format (eyJ…)
  // comme le nouveau (sb_secret_…), contrairement à une simple comparaison.
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) {
    return new Response('Unauthorized', { status: 401 });
  }
  const serviceKey = auth.slice('Bearer '.length);
  const keyCheck = await fetch(
    `${Deno.env.get('SUPABASE_URL')}/auth/v1/admin/users?per_page=1`,
    {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    },
  );
  if (!keyCheck.ok) {
    return new Response('Unauthorized', { status: 401 });
  }

  const saJson = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON');
  if (!saJson) return Response.json({ skipped: 'GOOGLE_SERVICE_ACCOUNT_JSON manquant' });

  const payload = await req.json().catch(() => null);
  const row = payload?.notification ?? payload;
  const userId = row?.user_id;
  const title = row?.title ?? 'EyeSafe';
  const body = row?.body ?? '';
  const data = row?.data ?? {};
  if (!userId) return new Response('user_id manquant', { status: 400 });

  // ── Token FCM de l'utilisateur ──
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    serviceKey,
    { auth: { persistSession: false } },
  );
  const { data: profile, error } = await supabase
    .from('profiles')
    .select('fcm_token')
    .eq('id', userId)
    .single();
  if (error || !profile?.fcm_token) {
    return Response.json({ skipped: 'aucun token FCM pour cet utilisateur' });
  }

  // ── Envoi FCM v1 ──
  try {
    const sa = JSON.parse(saJson);
    const accessToken = await getAccessToken(sa);
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: profile.fcm_token,
            notification: { title, body },
            data: Object.fromEntries(
              Object.entries(data).map(([k, v]) => [k, String(v ?? '')]),
            ),
            android: { priority: 'high' },
          },
        }),
      },
    );
    if (!res.ok) {
      return Response.json({ error: await res.text() }, { status: 502 });
    }
    return Response.json({ sent: true });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
