// Self-hosted HTTP host for the push relay. It replaces the Cloudflare Worker
// platform with a thin shim: the request-handling LOGIC stays in src/worker.js
// (imported and called verbatim), and this file supplies the platform pieces
// Cloudflare gave for free — an HTTP listener, the KV binding (SQLite; see
// host/kv.js), the APNs transport (HTTP/2; see host/apns.js), and the optional
// register rate-limit binding.
//
// Deploy behind a TLS-terminating reverse proxy (the box already fronts the
// companion relay this way): this process listens on loopback and speaks plain
// HTTP; the proxy owns the public hostname and certificate.

import http from "node:http";
import worker from "../src/worker.js";
import { SqliteKV } from "./kv.js";
import { createApnsClient } from "./apns.js";
import { Metrics, COUNTER_NAMES, apnsEventSink } from "./metrics.js";
import { createPeerSync, stampingKV } from "./peer.js";

// Read at most this many bytes before rejecting: the worker enforces the real
// 4 KiB payload cap, this is just a coarse guard so a huge upload can't buffer.
const MAX_REQUEST_BYTES = 64 * 1024;
// Sweep expired KV rows (registrations, rate-limit buckets) on this cadence.
const SWEEP_INTERVAL_MS = 60 * 60 * 1000;

// Same rule as registrationTtlSeconds() in src/worker.js (default 90 days, min
// 60s). The peer path needs it to carry a forwarded record's expiry over.
function registrationTtlSeconds(env) {
  const v = parseInt(env.REGISTRATION_TTL_SECONDS, 10);
  return Number.isFinite(v) && v >= 60 ? v : 90 * 24 * 60 * 60;
}

// An in-memory stand-in for Cloudflare's rate-limit binding: the same
// `.limit({ key }) -> { success }` shape the worker calls. A fixed window per
// key. Single-process, so this is exact rather than the per-datacenter estimate
// the platform binding gave. Returned only when a limit is configured; the
// worker treats the binding as optional and serves unthrottled without it.
function makeRegisterLimiter({ limit, windowSeconds }) {
  const hits = new Map(); // key -> { count, windowStart(ms) }
  const windowMs = windowSeconds * 1000;
  return {
    // eslint-disable-next-line require-await -- matches the binding's async shape
    async limit({ key }) {
      const now = Date.now();
      const rec = hits.get(key);
      if (!rec || now - rec.windowStart >= windowMs) {
        hits.set(key, { count: 1, windowStart: now });
        return { success: true };
      }
      rec.count += 1;
      return { success: rec.count <= limit };
    },
    _size: () => hits.size,
  };
}

function collectBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let done = false;
    req.on("data", (c) => {
      if (done) return;
      size += c.length;
      if (size > MAX_REQUEST_BYTES) {
        done = true;
        req.destroy();
        reject(new Error("body too large"));
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => { if (!done) resolve(Buffer.concat(chunks)); });
    req.on("error", (e) => { if (!done) { done = true; reject(e); } });
  });
}

// A /metrics scrape is allowed only from a direct loopback peer with no proxy
// headers — so the public Apache vhost (which sets these) can never reach it.
function isLocalScrape(req) {
  const addr = req.socket.remoteAddress || "";
  const loopback = addr === "127.0.0.1" || addr === "::1" || addr === "::ffff:127.0.0.1";
  const h = req.headers;
  return loopback && !h["x-forwarded-for"] && !h["cf-connecting-ip"];
}

// Classify a completed request into the aggregate counters, from (path, status)
// plus the response body for the two 403 reasons and the register skip flag. The
// worker stays metrics-free (it also runs on Cloudflare); classification lives
// here in the host, mirroring how the companion relay counts in host/server.js.
// The worker reports an APNs rejection as {"error":"APNs <status>: <body>"} where
// <body> is Apple's JSON, e.g. {"reason":"BadDeviceToken"}. Pull out just the
// reason string (never a token); anything unparseable yields undefined -> "other".
function apnsReason(body) {
  const m = /^APNs \d+: (.*)$/s.exec(String(body?.error ?? ""));
  if (!m) return undefined;
  try { return JSON.parse(m[1])?.reason; } catch { return undefined; }
}

function countRequest(metrics, path, status, text, onDelivered) {
  metrics.inc("http_requests_total");
  if (status >= 500 && status !== 502) metrics.inc("http_errors_total");
  let body = null;
  try { body = JSON.parse(text); } catch { /* non-JSON (shouldn't happen) */ }

  if (path === "/register") {
    metrics.inc("register_total");
    if (status === 200) metrics.inc(body && body.skipped ? "register_skipped_total" : "register_written_total");
    else if (status === 429) { metrics.inc("register_rejected_total"); metrics.inc("rate_limited_total"); }
    else metrics.inc("register_rejected_total");
    return;
  }
  if (path === "/push" || path === "/push/mutable") {
    metrics.inc("push_total");
    if (status >= 500) metrics.inc("push_failed_total");
    if (status === 200) { metrics.inc("push_delivered_total"); onDelivered?.(); }
    else if (status === 429) metrics.inc("rate_limited_total");
    else if (status === 502) {
      metrics.inc("push_apns_error_total");
      metrics.incReject(apnsReason(body));
    }
    else if (status === 403 && body && body.error === "bad secret") metrics.inc("push_bad_secret_total");
    else if (status === 403 && body && body.error === "unknown device token") metrics.inc("push_unknown_token_total");
    return;
  }
}

// The status to send the client for a worker response. The worker reports every
// APNs rejection as a 502 with body {"error":"APNs <status>: <reason>"}, but
// Cloudflare replaces an origin 502 with its own page, so the Mac can't see
// why. An APNs 4xx other than 403 (410 Unregistered, 400 BadDeviceToken, 429
// TooManyRequests) would be the same from any relay (they share the key and
// topic), so it goes out as a 422, which Cloudflare passes through, and the Mac
// stops instead of retrying on the other relay. These stay 502, so the Mac
// fails over: a 403 (this relay's key or provider token), APNs 5xx, and the
// 400 reasons that come from this relay's APNS_TOPIC rather than the device
// (another relay may be configured correctly). Metrics are counted from the
// worker's status, before this. Mirrors CompanionPushSender.isSharedAPNsRejection.
const RELAY_CONFIG_APNS_REASONS = new Set([
  "BadTopic", "TopicDisallowed", "MissingTopic", "DeviceTokenNotForTopic",
]);

export function isSharedApnsRejection(error) {
  const m = /^APNs (4\d\d)\b:?\s*(.*)$/s.exec(error);
  if (!m || m[1] === "403") return false;
  let reason = null;
  try { reason = JSON.parse(m[2]).reason; } catch { /* no JSON reason */ }
  return !RELAY_CONFIG_APNS_REASONS.has(reason);
}

export function clientStatus(path, status, text) {
  if ((path === "/push" || path === "/push/mutable") && status === 502) {
    let error = null;
    try { error = JSON.parse(text).error; } catch { /* not the worker's JSON */ }
    if (typeof error === "string" && isSharedApnsRejection(error)) {
      return 422;
    }
  }
  return status;
}

export function createPushRelay(options = {}) {
  const {
    dbPath = ":memory:",
    env: sourceEnv = process.env,
    // Injectable for tests (a stub APNs sender / clock).
    apnsFetch: injectedApnsFetch,
    now = () => Date.now(),
    // Register abuse cap (per client IP). Set registerLimit to 0/undefined to
    // disable, matching a deployment without the Cloudflare binding.
    registerLimit,
    registerWindowSeconds = 60,
    // Peer replication (see host/peer.js). Off unless both are set.
    peerUrl,
    peerSecret,
    peerFetch,
    peerRetryIntervalMs,
    peerRetryBackoffMs,
    peerGiveUpCooldownMs,
  } = options;

  const kv = new SqliteKV(dbPath, { now });
  const metrics = new Metrics();
  metrics.preregister(COUNTER_NAMES); // every line present from the first scrape
  let lastDeliveryMs = 0;
  const apnsFetch = injectedApnsFetch ?? createApnsClient({ onEvent: apnsEventSink(metrics) });

  // Point-in-time values read at scrape time. APNs connection state only exists
  // for the real transport (an injected test stub has no stats()).
  const gauges = () => {
    const st = apnsFetch.stats?.();
    return {
      devices: kv.countPrefix("device:"),
      ...(st && { apns_sessions: st.sessions, apns_oldest_session_age_seconds: st.oldestSessionAgeSeconds }),
      last_delivery_timestamp_seconds: Math.floor(lastDeliveryMs / 1000),
      ...peer?.gauges(),
    };
  };


  // The `env` object worker.js reads: KV binding, APNs transport, and the vars
  // that were wrangler [vars]/secrets, now plain environment variables.
  const workerEnv = {
    PUSH_KV: kv,
    fetchImpl: apnsFetch,
    APNS_TOPIC: sourceEnv.APNS_TOPIC,
    APNS_TEAM_ID: sourceEnv.APNS_TEAM_ID,
    APNS_KEY_ID: sourceEnv.APNS_KEY_ID,
    APNS_P8: sourceEnv.APNS_P8,
    REGISTRATION_TTL_SECONDS: sourceEnv.REGISTRATION_TTL_SECONDS,
  };
  // Peering is off unless both are set, and refused (loudly) with a weak secret.
  let peer = null;
  if (peerUrl && peerSecret) {
    try {
      peer = createPeerSync({
        kv,
        metrics,
        peerUrl,
        peerSecret,
        ttlSeconds: registrationTtlSeconds(sourceEnv),
        fetchImpl: peerFetch,
        now,
        retryIntervalMs: peerRetryIntervalMs,
        retryBackoffMs: peerRetryBackoffMs,
        giveUpCooldownMs: peerGiveUpCooldownMs,
      });
      workerEnv.PUSH_KV = stampingKV(kv);
    } catch (e) {
      console.error(`push-relay: peer replication disabled: ${e.message}`);
    }
  }

  if (registerLimit) {
    workerEnv.REGISTER_RATE_LIMITER = makeRegisterLimiter({
      limit: registerLimit,
      windowSeconds: registerWindowSeconds,
    });
  }

  async function handleRequest(req, res) {
    // Normalized the way the worker routes (new URL(...).pathname), so e.g.
    // "/./register" is treated as /register here too.
    let path;
    try { path = new URL(req.url || "/", "http://push.local").pathname; } catch { path = "/"; }

    // Localhost-only aggregate metrics, handled before anything else. Like the
    // companion relay, a scrape must come from loopback with no proxy headers,
    // so /metrics is never reachable through the public Apache vhost (which sets
    // X-Forwarded-For / CF-Connecting-IP).
    if (req.method === "GET" && path === "/metrics") {
      if (!isLocalScrape(req)) {
        res.writeHead(403, { "content-type": "text/plain" });
        res.end("forbidden");
        return;
      }
      res.writeHead(200, { "content-type": "text/plain; version=0.0.4" });
      res.end(metrics.render(gauges()));
      return;
    }

    let bodyBuf;
    try {
      bodyBuf = await collectBody(req);
    } catch {
      res.writeHead(413, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: "request too large" }));
      return;
    }

    // Peer endpoints: /peer/register (a registration forwarded by the peer
    // relay) and /peer/hello (its liveness check). Handled here, not by the
    // worker: a forwarded record carries the original registeredAt and must
    // not be forwarded back. Every answer carries peer.responseHeaders(): a
    // marker so the sender can tell this code's 400 from a proxy's, plus (for
    // an authenticated caller only) our instance and boot ids and our clock.
    // Without peer config these fall through to the worker's 404.
    if (peer && req.method === "POST" && (path === "/peer/register" || path === "/peer/hello")) {
      metrics.inc("http_requests_total");
      let result;
      try {
        result = path === "/peer/hello"
          ? peer.hello(req.headers.authorization)
          : await peer.receive(req.headers.authorization, bodyBuf.toString("utf8"));
      } catch (e) {
        console.error(`push-relay: ${path} failed: ${e?.stack || e}`);
        metrics.inc("http_errors_total");
        result = { status: 500, body: { error: String(e?.message || e) } };
      }
      res.writeHead(result.status, {
        "content-type": "application/json",
        ...peer.responseHeaders(req.headers.authorization),
      });
      res.end(JSON.stringify(result.body));
      return;
    }

    let registerToken = null;
    if (peer && req.method === "POST" && path === "/register") {
      try {
        const { token } = JSON.parse(bodyBuf.toString("utf8"));
        if (typeof token === "string") registerToken = token;
      } catch { /* malformed: the worker rejects it */ }
    }

    // Adapt the Node request into the Web Request the worker expects. The worker
    // only reads request.method, request.url's pathname, the headers (for the
    // register limiter's CF-Connecting-IP), and request.text(); a localhost
    // origin is fine because only the path is routed on.
    const request = new Request(`http://push.local${req.url}`, {
      method: req.method,
      headers: req.headers,
      body: (req.method === "GET" || req.method === "HEAD") ? undefined : bodyBuf,
    });

    let response;
    try {
      response = await worker.fetch(request, workerEnv);
    } catch (e) {
      // Reaches here when the APNs transport itself fails (request timeout, a
      // dead/GOAWAY h2 session — see host/apns.js) or any other worker throw.
      // Log it: this is otherwise invisible, and it's the failure mode a bad
      // .p8 / APNs outage takes. No device token or secret is in the message.
      console.error(`push-relay: ${req.method} ${path} failed before response: ${e?.stack || e}`);
      metrics.inc("http_requests_total");
      metrics.inc("http_errors_total");
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: String(e?.message || e) }));
      return;
    }

    const headers = {};
    for (const [k, v] of response.headers) headers[k] = v;
    const text = await response.text();
    countRequest(metrics, path, response.status, text, () => { lastDeliveryMs = now(); });
    // Surface push delivery failures in the process log. When APNs returns a
    // non-2xx the worker maps it to a 502 whose body carries Apple's status and
    // reason (e.g. `APNs 400: {"reason":"BadDeviceToken"}`) — but that body is
    // the ONLY record of the reason, and Cloudflare replaces an origin 502 with
    // its own page before the client ever sees it. The body holds Apple's error,
    // never a device token or secret, so it is safe to log verbatim.
    // Also log other 5xx: the worker converts a transport throw (e.g. "APNs
    // request timed out") into a 500 itself, so it never reaches the catch above.
    if ((path === "/push" || path === "/push/mutable") && response.status >= 500) {
      console.error(`push-relay: push failed: ${path} -> ${response.status} ${text}`);
    }
    // Pass every successful registration on to the peer. A skipped (unchanged)
    // one is passed on too unless the peer already acknowledged that record, so
    // a peer that missed it catches up on the phone's next connection. It is
    // queued on disk before the phone gets its reply, so a crash can't lose it;
    // the send happens after the reply, so the phone doesn't wait on the peer.
    let queued = false;
    if (registerToken && response.status === 200) {
      try {
        let skipped = false;
        try { skipped = !!JSON.parse(text).skipped; } catch { /* treat as written */ }
        queued = await peer.enqueue(registerToken, { unlessAcked: skipped });
      } catch (e) {
        // The registration itself succeeded; the startup backfill or the
        // phone's next connection will pass it on.
        console.error(`push-relay: queueing for peer failed: ${e?.stack || e}`);
      }
    }

    res.writeHead(clientStatus(path, response.status, text), headers);
    res.end(text);

    if (queued) {
      peer.flush().catch((e) => console.error(`push-relay: peer send threw: ${e?.message || e}`));
    }
  }

  const httpServer = http.createServer(handleRequest);
  let sweepTimer = null;

  return {
    httpServer,
    kv,
    metrics,
    peer,
    // Exposed for tests / diagnostics.
    _env: workerEnv,
    listen(port, host) {
      return new Promise((resolve, reject) => {
        httpServer.once("error", reject);
        httpServer.listen(port, host, () => {
          httpServer.removeListener("error", reject);
          sweepTimer = setInterval(() => {
            try { kv.sweepExpired(); } catch { /* best-effort */ }
          }, SWEEP_INTERVAL_MS);
          sweepTimer.unref?.();
          // Queue every registration for the peer at startup: seeds a newly
          // added peer and repairs anything both relays missed while one was
          // down. The peer ignores records it already has.
          if (peer) {
            peer.backfill();
            peer.start();
            peer.flush().catch(() => {});
          }
          resolve();
        });
      });
    },
    address() {
      return httpServer.address();
    },
    async close() {
      if (sweepTimer) clearInterval(sweepTimer);
      peer?.stop();
      apnsFetch.close?.();
      await new Promise((resolve) => httpServer.close(() => resolve()));
      kv.close();
    },
  };
}
