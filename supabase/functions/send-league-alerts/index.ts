// Sends league alerts (fixtures, kick-offs, full time, news) to every subscribed device.
// Reads the league_alerts queue, which the database fills. Public subscribers included.
const enc = new TextEncoder();

function b64uToBytes(s: string): Uint8Array {
  let b = s.replace(/-/g, '+').replace(/_/g, '/');
  while (b.length % 4) b += '=';
  const bin = atob(b);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function bytesToB64u(bytes: Uint8Array): string {
  let s = '';
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function concat(...arrs: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(arrs.reduce((n, a) => n + a.length, 0));
  let o = 0;
  for (const a of arrs) { out.set(a, o); o += a.length; }
  return out;
}
async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt, info }, key, length * 8);
  return new Uint8Array(bits);
}
async function vapidAuthorization(endpoint: string, publicKey: string, privateKey: string, subject: string): Promise<string> {
  const audience = new URL(endpoint).origin;
  const header = bytesToB64u(enc.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const payload = bytesToB64u(enc.encode(JSON.stringify({ aud: audience, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject })));
  const pub = b64uToBytes(publicKey);
  const key = await crypto.subtle.importKey('jwk', {
    kty: 'EC', crv: 'P-256', d: privateKey,
    x: bytesToB64u(pub.slice(1, 33)), y: bytesToB64u(pub.slice(33, 65)), ext: true,
  }, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(header + '.' + payload)));
  return `vapid t=${header}.${payload}.${bytesToB64u(sig)}, k=${publicKey}`;
}
async function encryptForSubscriber(plaintext: string, p256dh: string, authSecret: string): Promise<Uint8Array> {
  const uaPublic = b64uToBytes(p256dh);
  const auth = b64uToBytes(authSecret);
  const as = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPublic = new Uint8Array(await crypto.subtle.exportKey('raw', as.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', uaPublic, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, as.privateKey, 256));
  const ikm = await hkdf(auth, shared, concat(enc.encode('WebPush: info\0'), uaPublic, asPublic), 32);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, enc.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, enc.encode('Content-Encoding: nonce\0'), 12);
  const key = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['encrypt']);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, key, concat(enc.encode(plaintext), new Uint8Array([2]))));
  return concat(salt, new Uint8Array([0, 0, 16, 0]), new Uint8Array([asPublic.length]), asPublic, ct);
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const h = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' };

  const keyRes = await fetch(`${supabaseUrl}/rest/v1/push_vapid_keys?id=eq.1&select=public_key,private_key`, { headers: h });
  const keys = keyRes.ok ? await keyRes.json() : [];
  const vapid = keys[0];
  if (!vapid) return new Response('Push keys are not set', { status: 500 });

  const qRes = await fetch(`${supabaseUrl}/rest/v1/league_alerts?sent_at=is.null&attempts=lt.5&select=id,title,body,url,attempts&order=created_at.asc&limit=10`, { headers: h });
  if (!qRes.ok) return new Response('Could not read the alerts queue', { status: 500 });
  const alerts: Array<{ id: number; title: string; body: string; url: string; attempts: number }> = await qRes.json();

  let pushed = 0;
  for (const a of alerts) {
    const sRes = await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?select=endpoint,p256dh,auth&limit=5000`, { headers: h });
    const subs: Array<{ endpoint: string; p256dh: string; auth: string }> = sRes.ok ? await sRes.json() : [];
    let lastError: string | null = null;
    for (const sub of subs) {
      try {
        const body = await encryptForSubscriber(JSON.stringify({ title: a.title, body: a.body, url: a.url }), sub.p256dh, sub.auth);
        const authz = await vapidAuthorization(sub.endpoint, vapid.public_key, vapid.private_key, 'mailto:koromaalhajiabu0@gmail.com');
        const pRes = await fetch(sub.endpoint, {
          method: 'POST',
          headers: { TTL: '86400', 'Content-Encoding': 'aes128gcm', 'Content-Type': 'application/octet-stream', Authorization: authz },
          body,
        });
        if (pRes.status === 404 || pRes.status === 410) {
          await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(sub.endpoint)}`, { method: 'DELETE', headers: h });
        } else if (pRes.ok) {
          pushed++;
        } else {
          lastError = `Push ${pRes.status}`;
        }
      } catch (e) {
        lastError = String(e).slice(0, 300);
      }
    }
    await fetch(`${supabaseUrl}/rest/v1/league_alerts?id=eq.${a.id}`, {
      method: 'PATCH',
      headers: { ...h, Prefer: 'return=minimal' },
      body: JSON.stringify({ sent_at: new Date().toISOString(), attempts: a.attempts + 1, last_error: lastError }),
    });
  }
  return new Response(JSON.stringify({ alerts: alerts.length, pushed }), { headers: { 'Content-Type': 'application/json' } });
});
