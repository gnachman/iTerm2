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

export function createApnsClient({
  requestTimeoutMs = DEFAULT_REQUEST_TIMEOUT_MS,
  // Injectable for tests: returns a ClientHttp2Session for an origin.
  connect = (origin) => http2.connect(origin),
} = {}) {
  // origin ("https://host") -> live session, or absent when none is open.
  const sessions = new Map();

  function sessionFor(origin) {
    const existing = sessions.get(origin);
    if (existing && !existing.closed && !existing.destroyed) return existing;

    const session = connect(origin);
    session.unref(); // never keep the process alive for an idle push channel
    const evict = () => { if (sessions.get(origin) === session) sessions.delete(origin); };
    session.on("error", evict);
    session.on("close", evict);
    session.on("goaway", () => { evict(); try { session.close(); } catch { /* already gone */ } });
    sessions.set(origin, session);
    return session;
  }

  // fetch-compatible: (urlString, { method, headers, body }) -> Response-like.
  async function apnsFetch(urlString, init = {}) {
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

    const session = sessionFor(origin);

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
        reject(new Error("APNs request timed out"));
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

  // Close every open session (graceful shutdown).
  apnsFetch.close = () => {
    for (const session of sessions.values()) {
      try { session.close(); } catch { /* already closing */ }
    }
    sessions.clear();
  };

  return apnsFetch;
}
