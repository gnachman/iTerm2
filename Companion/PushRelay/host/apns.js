// HTTP/2 client for Apple Push Notification service, exposed as a fetch-shaped
// function so worker.js's deliverToAPNs can call it unchanged (it injects this
// as env.fetchImpl; see the seam in src/worker.js).
//
// Why this file exists: APNs speaks ONLY HTTP/2. On Cloudflare the global fetch
// negotiates h2 transparently, but Node's global fetch (undici) is HTTP/1.1 by
// default, which APNs refuses. So on the self-hosted host we talk to Apple over
// node:http2 directly and adapt the result to the tiny slice of the Response
// interface the worker uses: { ok, status, text() }.
//
// Connection reuse: opening a TLS+h2 session per push would be slow and would
// churn Apple's connection limits. We keep one persistent session per authority
// (prod vs. sandbox) and multiplex every push over it — exactly APNs's intended
// model. A session that errors, times out, or receives GOAWAY is evicted and
// lazily reopened on the next push. Sessions are unref'd so they never hold the
// process open.

import http2 from "node:http2";

const {
  HTTP2_HEADER_METHOD,
  HTTP2_HEADER_PATH,
  HTTP2_HEADER_STATUS,
} = http2.constants;

// Give up on a single push that Apple neither answers nor rejects, so a stuck
// stream can't pin the caller. Generous: APNs is normally sub-second.
const DEFAULT_REQUEST_TIMEOUT_MS = 10_000;

// A session unused for this long is replaced rather than reused. Nothing sends
// TCP keepalives on these sockets, so a connection that Apple or a middlebox
// silently dropped while we were idle looks healthy (no 'error'/'close'/'goaway')
// and every push written to it would time out. Reconnecting costs one TLS
// handshake; pushes are infrequent enough that this is negligible.
const DEFAULT_MAX_IDLE_MS = 5 * 60_000;

// Floor on how often we open a new connection to the same APNs host, so an
// outage (or a bad network) can't turn every incoming push into a fresh
// connect attempt against Apple. A push that needs a connection sooner than
// this waits out the remainder of the window (at most this long).
const DEFAULT_MIN_CONNECT_INTERVAL_MS = 1_000;

export function createApnsClient({
  requestTimeoutMs = DEFAULT_REQUEST_TIMEOUT_MS,
  maxIdleMs = DEFAULT_MAX_IDLE_MS,
  minConnectIntervalMs = DEFAULT_MIN_CONNECT_INTERVAL_MS,
  // Injectable for tests: returns a ClientHttp2Session for an origin.
  connect = (origin) => http2.connect(origin),
  now = () => Date.now(),
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  log = (msg) => console.error(msg),
  // Telemetry hook: onEvent(name, data). Must never affect delivery, so every
  // call is guarded. Events: connect, connect_throttled, session_error,
  // discard {kind: "idle"|"timeout"}, request {ms, outcome: "ok"|"rejected"|"timeout"|"error"}.
  onEvent = () => {},
} = {}) {
  const emit = (name, data) => { try { onEvent(name, data); } catch { /* telemetry only */ } };
  // origin ("https://host") -> { session, lastUsedAt }, absent when none is open.
  const sessions = new Map();
  // origin -> time of the last connect attempt (successful or not).
  const lastConnectAt = new Map();

  function dropSession(origin, session) {
    if (sessions.get(origin)?.session === session) sessions.delete(origin);
  }

  // Evict and tear down a session we no longer trust.
  function discardSession(origin, session, kind, reason) {
    log(`push-relay: discarding APNs session to ${origin}: ${reason}`);
    emit("discard", { kind });
    dropSession(origin, session);
    try { session.destroy(); } catch { /* already gone */ }
  }

  async function sessionFor(origin) {
    for (;;) {
      const entry = sessions.get(origin);
      if (entry) {
        const { session } = entry;
        if (session.closed || session.destroyed) {
          dropSession(origin, session);
        } else if (now() - entry.lastUsedAt > maxIdleMs) {
          discardSession(origin, session, "idle", "idle too long");
        } else {
          entry.lastUsedAt = now();
          return session;
        }
      }

      // Need a new connection. Respect the per-origin connect floor; after the
      // wait, loop so a connection another waiter opened is reused instead.
      const wait = minConnectIntervalMs - (now() - (lastConnectAt.get(origin) ?? -Infinity));
      if (wait > 0) {
        emit("connect_throttled");
        await sleep(wait);
        continue;
      }

      lastConnectAt.set(origin, now());
      const session = connect(origin);
      emit("connect");
      session.unref(); // never keep the process alive for an idle push channel
      const evict = () => dropSession(origin, session);
      session.on("error", (e) => { log(`push-relay: APNs session to ${origin} error: ${e?.message || e}`); emit("session_error"); evict(); });
      session.on("close", evict);
      session.on("goaway", () => { evict(); try { session.close(); } catch { /* already gone */ } });
      sessions.set(origin, { session, lastUsedAt: now(), openedAt: now() });
      return session;
    }
  }

  // fetch-compatible: (urlString, { method, headers, body }) -> Response-like.
  async function doFetch(urlString, init = {}) {
    const url = new URL(urlString);
    const origin = `${url.protocol}//${url.host}`;

    const h2headers = {
      [HTTP2_HEADER_METHOD]: init.method || "GET",
      [HTTP2_HEADER_PATH]: url.pathname + url.search,
    };
    // HTTP/2 header names must be lowercase; drop any :pseudo the caller passed
    // and the connection-level `host` (h2 uses :authority from the origin).
    for (const [k, v] of Object.entries(init.headers || {})) {
      const name = k.toLowerCase();
      if (name.startsWith(":") || name === "host") continue;
      h2headers[name] = v;
    }

    const session = await sessionFor(origin);

    return await new Promise((resolve, reject) => {
      let req;
      try {
        req = session.request(h2headers);
      } catch (e) {
        // A session that died between selection and use: surface as a network
        // error so the caller (worker -> 502) reports it like any APNs failure.
        reject(e);
        return;
      }
      req.setTimeout(requestTimeoutMs, () => {
        req.close(http2.constants.NGHTTP2_CANCEL);
        // A push that gets no answer at all usually means the connection is
        // dead without telling us. Throw the session away so the next push opens
        // a fresh one (subject to the connect floor) instead of timing out on
        // the same corpse forever.
        discardSession(origin, session, "timeout", "request timed out");
        reject(Object.assign(new Error("APNs request timed out"), { code: "APNS_TIMEOUT" }));
      });

      let status = 0;
      const chunks = [];
      req.on("response", (headers) => { status = Number(headers[HTTP2_HEADER_STATUS]) || 0; });
      req.on("data", (c) => chunks.push(c));
      req.on("error", reject);
      req.on("end", () => {
        const body = Buffer.concat(chunks).toString("utf8");
        resolve({
          ok: status >= 200 && status < 300,
          status,
          // Matches the Response method worker.js calls on the non-ok path.
          text: async () => body,
        });
      });

      if (init.body != null) req.write(init.body);
      req.end();
    });
  }

  // Times the whole exchange (including any connect-throttle wait and TLS setup,
  // i.e. what the caller actually experienced) and reports its outcome.
  async function apnsFetch(urlString, init = {}) {
    const start = now();
    try {
      const res = await doFetch(urlString, init);
      emit("request", { ms: now() - start, outcome: res.ok ? "ok" : "rejected" });
      return res;
    } catch (e) {
      emit("request", { ms: now() - start, outcome: e?.code === "APNS_TIMEOUT" ? "timeout" : "error" });
      throw e;
    }
  }

  // Point-in-time connection state for the metrics gauges.
  apnsFetch.stats = () => {
    let oldest = 0;
    for (const { openedAt } of sessions.values()) oldest = Math.max(oldest, now() - openedAt);
    return { sessions: sessions.size, oldestSessionAgeSeconds: Math.round(oldest / 1000) };
  };

  // Close every open session (graceful shutdown).
  apnsFetch.close = () => {
    for (const { session } of sessions.values()) {
      try { session.close(); } catch { /* already closing */ }
    }
    sessions.clear();
  };

  return apnsFetch;
}
