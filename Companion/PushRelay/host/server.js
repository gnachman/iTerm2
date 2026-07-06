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
import { Metrics, COUNTER_NAMES } from "./metrics.js";

// Read at most this many bytes before rejecting: the worker enforces the real
// 4 KiB payload cap, this is just a coarse guard so a huge upload can't buffer.
const MAX_REQUEST_BYTES = 64 * 1024;
// Sweep expired KV rows (registrations, rate-limit buckets) on this cadence.
const SWEEP_INTERVAL_MS = 60 * 60 * 1000;

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
function countRequest(metrics, path, status, text) {
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
    if (status === 200) metrics.inc("push_delivered_total");
    else if (status === 429) metrics.inc("rate_limited_total");
    else if (status === 502) metrics.inc("push_apns_error_total");
    else if (status === 403 && body && body.error === "bad secret") metrics.inc("push_bad_secret_total");
    else if (status === 403 && body && body.error === "unknown device token") metrics.inc("push_unknown_token_total");
    return;
  }
}

export function createPushRelay(options = {}) {
  const {
    dbPath = ":memory:",
    env: sourceEnv = process.env,
    // Injectable for tests (a stub APNs sender / clock).
    apnsFetch = createApnsClient(),
    now = () => Date.now(),
    // Register abuse cap (per client IP). Set registerLimit to 0/undefined to
    // disable, matching a deployment without the Cloudflare binding.
    registerLimit,
    registerWindowSeconds = 60,
  } = options;

  const kv = new SqliteKV(dbPath, { now });
  const metrics = new Metrics();
  metrics.preregister(COUNTER_NAMES); // every line present from the first scrape

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
  if (registerLimit) {
    workerEnv.REGISTER_RATE_LIMITER = makeRegisterLimiter({
      limit: registerLimit,
      windowSeconds: registerWindowSeconds,
    });
  }

  async function handleRequest(req, res) {
    const path = (req.url || "").split("?")[0];

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
      res.end(metrics.render({ devices: kv.countPrefix("device:") }));
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
      metrics.inc("http_requests_total");
      metrics.inc("http_errors_total");
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: String(e?.message || e) }));
      return;
    }

    const headers = {};
    for (const [k, v] of response.headers) headers[k] = v;
    const text = await response.text();
    countRequest(metrics, path, response.status, text);
    res.writeHead(response.status, headers);
    res.end(text);
  }

  const httpServer = http.createServer(handleRequest);
  let sweepTimer = null;

  return {
    httpServer,
    kv,
    metrics,
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
          resolve();
        });
      });
    },
    address() {
      return httpServer.address();
    },
    async close() {
      if (sweepTimer) clearInterval(sweepTimer);
      apnsFetch.close?.();
      await new Promise((resolve) => httpServer.close(() => resolve()));
      kv.close();
    },
  };
}
