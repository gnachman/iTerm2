//
//  worker.js
//  iTerm2 Buddy push relay
//
//  Holds the APNs signing key so the open-source app doesn't have to. Two
//  endpoints, both JSON POST:
//
//    /register  {token, secretHash, sandbox}
//      Called by the PHONE when it obtains an APNs device token. The phone
//      mints a random 32-byte secret per device, registers sha256(secret)
//      here, and hands the secret to its paired Mac over the encrypted
//      pairing channel. Re-registering overwrites: only a caller who knows
//      the token can do so, and tokens are unguessable.
//
//    /push/mutable {token, secret, collapse}
//      Called by the MAC for the Notification Service Extension: a content-free
//      mutable-content push with a generic fallback alert, collapsed per chat by
//      the opaque `collapse` id. Same auth + rate limit as /push; no title/body.
//
//    /push      {token, secret, title, body}
//      Called by the MAC. The relay verifies sha256(secret) matches the
//      registration, rate-limits per token, and forwards to APNs. So a push
//      can only be sent to a phone by someone holding that phone's secret,
//      which only travels over the Noise channel to the paired Mac.
//
//  Secrets (wrangler secret put): APNS_TEAM_ID, APNS_KEY_ID, APNS_P8.
//  Vars: APNS_TOPIC. KV binding: PUSH_KV.
//

const PUSHES_PER_MINUTE = 10;
const MAX_BODY_BYTES = 4096;
// Device registrations self-expire after this idle window so abandoned or junk
// entries cannot accumulate in KV. The phone re-registers on every connection to
// the Mac, so an active pairing refreshes this long before it lapses (a dead
// pairing's registration simply ages out). Override with REGISTRATION_TTL_SECONDS.
const DEFAULT_REGISTRATION_TTL_SECONDS = 90 * 24 * 60 * 60; // 90 days
// KV's minimum expirationTtl.
const MIN_KV_TTL_SECONDS = 60;

// APNs provider JWTs may be reused for up to an hour; Apple rejects tokens
// refreshed more often than twice in 20 minutes, so cache per isolate.
let cachedJWT = null;
let cachedJWTIssuedAt = 0;

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json(405, { error: "POST only" });
    }
    let payload;
    try {
      payload = await readBody(request);
    } catch (e) {
      return json(400, { error: String(e.message || e) });
    }
    const url = new URL(request.url);
    try {
      switch (url.pathname) {
        case "/register":
          return await register(payload, env, request);
        case "/push":
          return await push(payload, env);
        case "/push/mutable":
          return await pushMutable(payload, env);
        default:
          return json(404, { error: "no such endpoint" });
      }
    } catch (e) {
      return json(500, { error: String(e.message || e) });
    }
  },
};

async function readBody(request) {
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) {
    throw new Error("request too large");
  }
  return JSON.parse(text);
}

function json(status, object) {
  return new Response(JSON.stringify(object), {
    status,
    headers: { "content-type": "application/json" },
  });
}

const isHex = (s, minLen, maxLen) =>
  typeof s === "string" &&
  s.length >= minLen &&
  s.length <= maxLen &&
  /^[0-9a-f]+$/.test(s);

// The push nonce is an opaque base64 ciphertext (sealed under the room secret),
// not hex; the relay only forwards it, so just bound the length and charset.
const isBase64 = (s, minLen, maxLen) =>
  typeof s === "string" &&
  s.length >= minLen &&
  s.length <= maxLen &&
  /^[A-Za-z0-9+/]+={0,2}$/.test(s);

async function register(payload, env, request) {
  const { token, secretHash, sandbox } = payload;
  if (!isHex(token, 32, 256) || !isHex(secretHash, 64, 64)) {
    return json(400, { error: "bad token or secretHash" });
  }
  // Abuse cap: /register writes to KV, so an attacker spraying random tokens
  // could fill KV and burn the free-tier write budget. Rate-limit by client IP
  // (used ONLY as an ephemeral limiter key, never logged or stored, consistent
  // with the no-retention posture). The binding is optional so a deployment that
  // has not configured it still serves registrations.
  if (env.REGISTER_RATE_LIMITER) {
    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const { success } = await env.REGISTER_RATE_LIMITER.limit({ key: ip });
    if (!success) {
      return json(429, { error: "rate limited" });
    }
  }
  // Self-expiring write: a registration that is never refreshed (a dead pairing)
  // ages out instead of lingering forever.
  await env.PUSH_KV.put(
    `device:${token}`,
    JSON.stringify({ secretHash, sandbox: !!sandbox, registeredAt: Date.now() }),
    { expirationTtl: registrationTtlSeconds(env) }
  );
  return json(200, { ok: true });
}

function registrationTtlSeconds(env) {
  const v = parseInt(env.REGISTRATION_TTL_SECONDS, 10);
  return Number.isFinite(v) && v >= MIN_KV_TTL_SECONDS
    ? v
    : DEFAULT_REGISTRATION_TTL_SECONDS;
}

// Legacy plaintext push (the notify tool): a visible alert carrying title/body.
async function push(payload, env) {
  const { token, secret, title, body } = payload;
  if (!isHex(token, 32, 256) || !isHex(secret, 64, 64)) {
    return json(400, { error: "bad token or secret" });
  }
  if (typeof title !== "string" || typeof body !== "string") {
    return json(400, { error: "title and body are required strings" });
  }
  const auth = await authorizeDevice(token, secret, env);
  if (auth.error) return auth.error;
  if (await overPushRateLimit(token, env)) return json(429, { error: "rate limited" });
  return deliverToAPNs(env, token, auth.record, {
    aps: { alert: { title, body }, sound: "default" },
  });
}

// Content-free "mutable" push for the Notification Service Extension. The aps
// payload carries NO real content: just mutable-content + a generic fallback
// alert, collapsed per chat by an opaque collapse id (HMAC(roomSecret, chatID),
// computed on the device - the relay never sees the chatID). The NSE wakes,
// fetches the real content over Noise, and rewrites the notification; if it
// can't, the fallback shows. Sound is omitted (the NSE adds it on delivery, so
// the silent push doesn't double-buzz). Auth and rate limit are shared with
// /push; the legacy /push payload is untouched.
async function pushMutable(payload, env) {
  const { token, secret, collapse, nonce } = payload;
  if (!isHex(token, 32, 256) || !isHex(secret, 64, 64)) {
    return json(400, { error: "bad token or secret" });
  }
  if (!isHex(collapse, 1, 64)) {
    return json(400, { error: "bad collapse id" });
  }
  // Optional one-time nonce: a base64 ciphertext (sealed under the room secret)
  // the NSE decrypts and echoes back over the relay so the mac can recognize its
  // own solicited fetch and skip the presence warning. Opaque to the relay; just
  // validated as bounded base64 and forwarded in the payload.
  if (nonce !== undefined && !isBase64(nonce, 1, 256)) {
    return json(400, { error: "bad nonce" });
  }
  const auth = await authorizeDevice(token, secret, env);
  if (auth.error) return auth.error;
  if (await overPushRateLimit(token, env)) return json(429, { error: "rate limited" });
  const apsBody = {
    aps: {
      "mutable-content": 1,
      alert: { title: "iTerm2 Buddy", body: "Your agent has an update." },
    },
  };
  // Custom top-level key the NSE reads from the delivered notification's
  // userInfo. Outside `aps` per APNs convention.
  if (nonce !== undefined) {
    apsBody.n = nonce;
  }
  return deliverToAPNs(env, token, auth.record, apsBody, { "apns-collapse-id": collapse });
}

// Look up + authenticate a device. Returns { record } or { error: Response }.
async function authorizeDevice(token, secret, env) {
  const record = await env.PUSH_KV.get(`device:${token}`, "json");
  if (!record) {
    return { error: json(403, { error: "unknown device token" }) };
  }
  if ((await sha256Hex(secret)) !== record.secretHash) {
    return { error: json(403, { error: "bad secret" }) };
  }
  return { record };
}

// Per-token soft rate limit (KV is eventually consistent, but it stops runaway
// loops cold). Returns true when over the limit.
async function overPushRateLimit(token, env) {
  const bucket = `rl:${token}:${Math.floor(Date.now() / 60000)}`;
  const count = parseInt((await env.PUSH_KV.get(bucket)) || "0", 10);
  if (count >= PUSHES_PER_MINUTE) {
    return true;
  }
  await env.PUSH_KV.put(bucket, String(count + 1), { expirationTtl: 120 });
  return false;
}

// POST an aps payload to APNs for a device. extraHeaders adds per-call headers
// such as apns-collapse-id. Returns a Response to relay back to the caller.
async function deliverToAPNs(env, token, record, apsBody, extraHeaders = {}) {
  const host = record.sandbox
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerJWT(env)}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      ...extraHeaders,
    },
    body: JSON.stringify(apsBody),
  });
  if (response.ok) {
    return json(200, { ok: true });
  }
  const detail = await response.text();
  return json(502, { error: `APNs ${response.status}: ${detail}` });
}

async function sha256Hex(hexString) {
  const bytes = Uint8Array.from(
    hexString.match(/../g).map((b) => parseInt(b, 16))
  );
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ES256-signed APNs provider token, cached for 45 minutes.
async function providerJWT(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWTIssuedAt < 45 * 60) {
    return cachedJWT;
  }
  const key = await importP8(env.APNS_P8);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now }));
  const signingInput = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput)
  );
  cachedJWT = `${signingInput}.${b64url(signature)}`;
  cachedJWTIssuedAt = now;
  return cachedJWT;
}

async function importP8(pem) {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

function b64url(input) {
  const bytes =
    typeof input === "string"
      ? new TextEncoder().encode(input)
      : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) {
    binary += String.fromCharCode(b);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
