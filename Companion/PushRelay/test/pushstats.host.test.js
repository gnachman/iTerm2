// The APNs-health and delivery stats: failure/rejection accounting at the HTTP
// layer, the transport's telemetry mapped onto counters + the latency histogram,
// and the exposition format the dashboard parses.

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { EventEmitter } from "node:events";
import { createPushRelay } from "../host/server.js";
import { createApnsClient } from "../host/apns.js";
import { Metrics, apnsEventSink, COUNTER_NAMES } from "../host/metrics.js";

const TEST_APNS_P8 = [
  "-----BEGIN PRIVATE KEY-----",
  "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgnjiLVvDqoxAEr50F",
  "Q5IEcY5FGUqvykFYDLxOr7Nn6FehRANCAARj1irFFlMCoD4iS9pNeD6XE/wY6KFh",
  "aA2rAzxkzFeNVZYnNUbNFLRc2G2cWhGGA/MbPTktoQhgwpYnRnoxrtJx",
  "-----END PRIVATE KEY-----",
].join("\n");

const hex = (b) => [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
async function makeCreds() {
  const s = crypto.getRandomValues(new Uint8Array(32));
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", s));
  return { secret: hex(s), secretHash: hex(d) };
}
const tok = (n) => n.toString(16).padStart(64, "0");
const num = (text, series) => {
  const m = text.match(new RegExp(`^pushrelay_${series} (\\S+)$`, "m"));
  return m ? Number(m[1]) : undefined;
};

describe("delivery stats through the HTTP layer", () => {
  let relay, base, creds, outcomes, clock;

  // Each push consumes the next scripted APNs outcome.
  const apnsFetch = Object.assign(async () => {
    const o = outcomes.shift();
    if (o instanceof Error) throw o;
    return { ok: o.status >= 200 && o.status < 300, status: o.status, text: async () => o.body ?? "" };
  }, { close() {} });

  const scrape = async () => (await fetch(base + "/metrics")).text();
  const push = (t, secret) =>
    fetch(base + "/push", { method: "POST", body: JSON.stringify({ token: t, secret, title: "x", body: "y" }) });

  beforeAll(async () => {
    clock = 1_700_000_000_000;
    relay = createPushRelay({
      dbPath: ":memory:", apnsFetch, now: () => clock,
      env: { APNS_TOPIC: "com.x", APNS_TEAM_ID: "T", APNS_KEY_ID: "K", APNS_P8: TEST_APNS_P8, REGISTRATION_TTL_SECONDS: "3600" },
    });
    await relay.listen(0, "127.0.0.1");
    base = `http://127.0.0.1:${relay.address().port}`;
    creds = await makeCreds();
    await fetch(base + "/register", { method: "POST", body: JSON.stringify({ token: tok(1), secretHash: creds.secretHash, sandbox: false }) });
  });
  afterAll(async () => { await relay.close(); });

  it("reports no delivery yet", async () => {
    expect(num(await scrape(), "last_delivery_timestamp_seconds")).toBe(0);
  });

  it("counts delivered, failed (502 reject + 500 transport) and rejects by reason", async () => {
    outcomes = [
      { status: 200 },
      { status: 400, body: '{"reason":"BadDeviceToken"}' },
      { status: 410, body: '{"reason":"Unregistered"}' },
      { status: 400, body: "<html>not json</html>" },
      Object.assign(new Error("APNs request timed out"), { code: "APNS_TIMEOUT" }),
    ];
    for (let i = 0; i < 5; i++) { clock += 1000; await push(tok(1), creds.secret); }

    const text = await scrape();
    expect(num(text, "push_total")).toBe(5);
    expect(num(text, "push_delivered_total")).toBe(1);
    expect(num(text, "push_apns_error_total")).toBe(3);   // the three 502s
    expect(num(text, "push_failed_total")).toBe(4);       // 3x 502 + 1x 500
    expect(text).toContain('pushrelay_apns_rejected_total{reason="BadDeviceToken"} 1');
    expect(text).toContain('pushrelay_apns_rejected_total{reason="Unregistered"} 1');
    expect(text).toContain('pushrelay_apns_rejected_total{reason="other"} 1');   // unparseable body
    // last delivery = the clock when the first (successful) push ran
    expect(num(text, "last_delivery_timestamp_seconds")).toBe(Math.floor((1_700_000_000_000 + 1000) / 1000));
  });

  it("does not count client faults as failures", async () => {
    const before = num(await scrape(), "push_failed_total");
    await push(tok(1), (await makeCreds()).secret);   // bad secret -> 403
    await push(tok(999), creds.secret);               // unknown token -> 403
    expect(num(await scrape(), "push_failed_total")).toBe(before);
  });

  it("exposes every new counter from boot", () => {
    for (const n of ["push_failed_total", "apns_connects_total", "apns_connect_throttled_total",
      "apns_session_errors_total", "apns_discarded_idle_total", "apns_discarded_timeout_total",
      "apns_request_timeouts_total"]) expect(COUNTER_NAMES).toContain(n);
  });
});

describe("Metrics: reasons and latency histogram", () => {
  it("sanitizes and bounds reject reasons", () => {
    const m = new Metrics();
    m.incReject("BadDeviceToken");
    m.incReject("has spaces & \"quotes\"\n");   // would break exposition if echoed
    m.incReject(undefined);
    for (let i = 0; i < 100; i++) m.incReject("Reason" + "abcdefghij"[i % 10].repeat(1 + Math.floor(i / 10)));
    const text = m.render();
    expect(text).toContain('{reason="BadDeviceToken"} 1');
    expect(text).not.toMatch(/spaces|quotes/);
    const labels = text.match(/pushrelay_apns_rejected_total\{reason=/g);
    expect(labels.length).toBeLessThanOrEqual(40);
  });

  it("renders a cumulative histogram with +Inf, sum and count", () => {
    const m = new Metrics();
    for (const s of [0.03, 0.2, 0.2, 3, 12]) m.observeLatency(s);
    const t = m.render();
    expect(t).toContain('pushrelay_apns_latency_seconds_bucket{le="0.05"} 1');
    expect(t).toContain('pushrelay_apns_latency_seconds_bucket{le="0.25"} 3');
    expect(t).toContain('pushrelay_apns_latency_seconds_bucket{le="5"} 4');
    expect(t).toContain('pushrelay_apns_latency_seconds_bucket{le="10"} 4');   // 12s only in +Inf
    expect(t).toContain('pushrelay_apns_latency_seconds_bucket{le="+Inf"} 5');
    expect(t).toContain("pushrelay_apns_latency_seconds_count 5");
    expect(t).toMatch(/pushrelay_apns_latency_seconds_sum 15\.43/);
  });
});

// The real transport, driven through a fake session, must feed the sink.
class FakeReq extends EventEmitter {
  setTimeout(ms, cb) { this.timeoutCb = cb; }
  write() {} end() {} close() {}
  respond(status) { this.emit("response", { ":status": status }); this.emit("end"); }
}
class FakeSession extends EventEmitter {
  constructor() { super(); this.closed = false; this.destroyed = false; this.requests = []; }
  unref() {}
  request() { const r = new FakeReq(); this.requests.push(r); return r; }
  close() { this.closed = true; this.emit("close"); }
  destroy() { this.destroyed = true; this.emit("close"); }
}
const flush = () => new Promise((r) => setImmediate(r));

describe("APNs transport telemetry -> metrics", () => {
  it("counts connects, timeouts, discards, throttling and latency, and reports session stats", async () => {
    let t = 0;
    const metrics = new Metrics();
    metrics.preregister(COUNTER_NAMES);
    const sessions = [];
    const apns = createApnsClient({
      connect: () => { const s = new FakeSession(); sessions.push(s); return s; },
      now: () => t, sleep: async (ms) => { t += ms; }, maxIdleMs: 60_000, log: () => {},
      onEvent: apnsEventSink(metrics),
    });
    const go = () => apns("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    const text = () => metrics.render();

    // 1) a good push: 1 connect, one latency sample, one live session.
    let p = go(); await flush(); t += 80; sessions[0].requests[0].respond(200); await p;
    expect(apns.stats().sessions).toBe(1);
    expect(text()).toContain("pushrelay_apns_connects_total 1");
    expect(text()).toContain("pushrelay_apns_latency_seconds_count 1");

    // 2) a timeout discards the session...
    p = go(); await flush();
    sessions[0].requests[1].timeoutCb();   // (clock barely moved: reconnect lands inside the 1s window)
    await expect(p).rejects.toThrow("timed out");
    expect(text()).toContain("pushrelay_apns_request_timeouts_total 1");
    expect(text()).toContain("pushrelay_apns_discarded_timeout_total 1");
    expect(apns.stats().sessions).toBe(0);

    // 3) ...and the immediate reconnect (<1s later) is throttled, then succeeds.
    p = go(); await flush(); await flush();
    expect(text()).toContain("pushrelay_apns_connect_throttled_total 1");
    sessions[1].requests[0].respond(200); await p;
    expect(text()).toContain("pushrelay_apns_connects_total 2");

    // 4) idle past maxIdleMs -> replaced and counted.
    t += 120_000;
    p = go(); await flush(); await flush();
    expect(text()).toContain("pushrelay_apns_discarded_idle_total 1");
    sessions[2].requests[0].respond(200); await p;

    // 5) a session error is counted.
    sessions[2].emit("error", new Error("ECONNRESET"));
    expect(text()).toContain("pushrelay_apns_session_errors_total 1");
  });

  it("a throwing telemetry hook never breaks a push", async () => {
    const s = new FakeSession();
    const apns = createApnsClient({ connect: () => s, log: () => {}, onEvent: () => { throw new Error("boom"); } });
    const p = apns("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    await flush(); s.requests[0].respond(200);
    expect((await p).ok).toBe(true);
  });
});
