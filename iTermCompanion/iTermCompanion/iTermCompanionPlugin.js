// iTermCompanionPlugin.js
//
// The iTerm2 Companion consent plugin. It is the ONLY outbound path for the
// companion-device feature: the shipped iTerm2 binary contains no relay
// endpoint and no code that opens a companion connection, so installing this
// signed plugin is both the consent and the capability (the same model as the
// AI plugin). It vends two generic, scoped-by-caller primitives, HTTP and a
// WebSocket, and nothing companion-specific (no protocol, no crypto): the app
// drives the admission/Noise/RPC protocol over them.
//
// Pure ECMAScript, no dependencies. All real I/O is done by injected host
// functions (performHTTPRequest / hostWs*). Binary WebSocket frames cross as
// opaque base64 strings tagged isBinary; this file never inspects bytes.

function version() { return JSON.stringify("1.0"); }

// --- HTTP: identical contract to the AI plugin's request() ---
//   in:  JSON {method, url, headers, body}   out: JSON {data, error}
async function request(jsonString) {
  const r = JSON.parse(jsonString);
  return await new Promise((resolve) => {
    performHTTPRequest(r.method, r.url, r.headers || {}, r.body || "", (data, error) => {
      resolve(JSON.stringify({ data: data, error: error || "" }));
    });
  });
}

// --- WebSocket: generic, scoped to the URL the app passes ---
// Connections are keyed by an id; receive() is one-message-per-call (mirrors
// URLSessionWebSocketTask). Messages are { text } | { binary } | { closed }.
const _conns = {};
let _nextId = 1;

function wsOpen(url, headersJSON) {
  const id = String(_nextId++);
  _conns[id] = { queue: [], waiters: [], openResolve: null, openReject: null };
  const opened = new Promise((resolve, reject) => {
    _conns[id].openResolve = resolve;
    _conns[id].openReject = reject;
  });
  hostWsOpen(id, url, headersJSON);
  return opened.then(() => JSON.stringify({ id: id }));
}

function _onOpen(id) {
  const c = _conns[id];
  if (c && c.openResolve) { c.openResolve(); c.openResolve = null; c.openReject = null; }
}
function _deliver(id, message) {
  const c = _conns[id];
  if (!c) return;
  if (c.waiters.length) c.waiters.shift()(message);
  else c.queue.push(message);
}
function _onMessage(id, isBinary, data) { _deliver(id, isBinary ? { binary: data } : { text: data }); }
function _onClosed(id, code, reason) {
  const c = _conns[id];
  if (!c) return;
  if (c.openReject) { c.openReject("closed " + code); c.openResolve = null; c.openReject = null; }
  _deliver(id, { closed: { code: code, reason: reason } });
}

function wsRecv(id) {
  const c = _conns[id];
  if (!c) return Promise.resolve(JSON.stringify({ closed: { code: 1006, reason: "unknown id" } }));
  return new Promise((resolve) => {
    const give = (m) => resolve(JSON.stringify(m));
    if (c.queue.length) give(c.queue.shift());
    else c.waiters.push(give);
  });
}

function wsSend(id, isBinary, data) { hostWsSend(id, isBinary, data); }
function wsClose(id) { hostWsClose(id); delete _conns[id]; }
function wsPing(id) {
  return new Promise((resolve) => {
    hostWsPing(id, (ok) => resolve(JSON.stringify({ ok: ok })));
  });
}
