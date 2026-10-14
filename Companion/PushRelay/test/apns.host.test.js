// The HTTP/2 APNs adapter must present the fetch shape worker.js uses
// ({ ok, status, text() }), map init.headers into lowercase h2 headers with the
// right :method/:path pseudo-headers, send the body, and reuse one session per
// origin. A fake ClientHttp2Session stands in for Apple so no TLS/network runs.

import { describe, it, expect } from "vitest";
import { EventEmitter } from "node:events";
import { createApnsClient } from "../host/apns.js";

class FakeReq extends EventEmitter {
  constructor(headers) { super(); this.headers = headers; this.body = []; this.ended = false; }
  setTimeout(ms, cb) { this.timeoutMs = ms; this.timeoutCb = cb; }
  write(c) { this.body.push(c); }
  end() { this.ended = true; }
  close() { this.closedWith = arguments[0]; }
  // Drive a full APNs-style response, then complete the stream.
  respond(status, bodyText = "") {
    this.emit("response", { ":status": status });
    if (bodyText) this.emit("data", Buffer.from(bodyText));
    this.emit("end");
  }
}

class FakeSession extends EventEmitter {
  constructor() { super(); this.closed = false; this.destroyed = false; this.requests = []; }
  unref() {}
  request(headers) { const r = new FakeReq(headers); this.requests.push(r); return r; }
  close() { this.closed = true; this.emit("close"); }
  destroy() { this.destroyed = true; this.emit("close"); }
}

const quiet = () => {};
// apnsFetch acquires its session asynchronously; let it issue the request.
const flush = () => new Promise((r) => setImmediate(r));

describe("createApnsClient", () => {
  it("maps headers, sends the body, and resolves ok on 2xx", async () => {
    const session = new FakeSession();
    const apnsFetch = createApnsClient({ connect: () => session, log: quiet });

    const p = apnsFetch("https://api.push.apple.com/3/device/abc123", {
      method: "POST",
      headers: { authorization: "bearer JWT", "apns-topic": "com.x", host: "drop-me", ":oops": "drop" },
      body: JSON.stringify({ aps: {} }),
    });

    await flush();
    const req = session.requests[0];
    expect(req.headers[":method"]).toBe("POST");
    expect(req.headers[":path"]).toBe("/3/device/abc123");
    expect(req.headers["authorization"]).toBe("bearer JWT");
    expect(req.headers["apns-topic"]).toBe("com.x");
    expect(req.headers["host"]).toBeUndefined();   // connection header stripped
    expect(req.headers[":oops"]).toBeUndefined();  // stray pseudo-header stripped
    expect(req.body.join("")).toBe(JSON.stringify({ aps: {} }));
    expect(req.ended).toBe(true);

    req.respond(200, "");
    const res = await p;
    expect(res.ok).toBe(true);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("");
  });

  it("surfaces a non-2xx APNs response as not-ok with its body", async () => {
    const session = new FakeSession();
    const apnsFetch = createApnsClient({ connect: () => session, log: quiet });
    const p = apnsFetch("https://api.push.apple.com/3/device/x", { method: "POST", body: "{}" });
    await flush();
    session.requests[0].respond(410, '{"reason":"Unregistered"}');
    const res = await p;
    expect(res.ok).toBe(false);
    expect(res.status).toBe(410);
    expect(await res.text()).toBe('{"reason":"Unregistered"}');
  });

  it("reuses one session per origin across pushes", async () => {
    let opened = 0;
    const session = new FakeSession();
    const apnsFetch = createApnsClient({ connect: () => { opened += 1; return session; }, log: quiet });

    const p1 = apnsFetch("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    await flush();
    session.requests[0].respond(200);
    await p1;
    const p2 = apnsFetch("https://api.push.apple.com/3/device/b", { method: "POST", body: "{}" });
    await flush();
    session.requests[1].respond(200);
    await p2;

    expect(opened).toBe(1);           // second push multiplexed over the same session
    expect(session.requests).toHaveLength(2);
  });

  it("reopens a session after it closes (GOAWAY / idle drop)", async () => {
    const sessions = [];
    const apnsFetch = createApnsClient({
      connect: () => { const s = new FakeSession(); sessions.push(s); return s; },
      minConnectIntervalMs: 0,
      log: quiet,
    });

    const p1 = apnsFetch("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    await flush();
    sessions[0].requests[0].respond(200);
    await p1;

    sessions[0].close(); // 'close' evicts it from the pool

    const p2 = apnsFetch("https://api.push.apple.com/3/device/b", { method: "POST", body: "{}" });
    await flush();
    sessions[1].requests[0].respond(200);
    await p2;

    expect(sessions).toHaveLength(2); // a fresh session was opened after the close
  });

  it("discards the session on a request timeout so the next push reconnects", async () => {
    const sessions = [];
    const apnsFetch = createApnsClient({
      connect: () => { const s = new FakeSession(); sessions.push(s); return s; },
      minConnectIntervalMs: 0,
      log: quiet,
    });

    const p1 = apnsFetch("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    await Promise.resolve();
    sessions[0].requests[0].timeoutCb(); // Apple never answered
    await expect(p1).rejects.toThrow("APNs request timed out");
    expect(sessions[0].destroyed).toBe(true);

    const p2 = apnsFetch("https://api.push.apple.com/3/device/b", { method: "POST", body: "{}" });
    await Promise.resolve();
    expect(sessions).toHaveLength(2); // not stuck on the dead session
    sessions[1].requests[0].respond(200);
    expect((await p2).ok).toBe(true);
  });

  it("replaces a session that has sat idle past maxIdleMs", async () => {
    let t = 0;
    const sessions = [];
    const apnsFetch = createApnsClient({
      connect: () => { const s = new FakeSession(); sessions.push(s); return s; },
      now: () => t, maxIdleMs: 1000, minConnectIntervalMs: 0, log: quiet,
    });

    const p1 = apnsFetch("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    await Promise.resolve();
    sessions[0].requests[0].respond(200);
    await p1;

    t = 500; // still fresh: reused
    const p2 = apnsFetch("https://api.push.apple.com/3/device/b", { method: "POST", body: "{}" });
    await Promise.resolve();
    sessions[0].requests[1].respond(200);
    await p2;
    expect(sessions).toHaveLength(1);

    t = 2000; // idle > maxIdleMs since the last use at t=500
    const p3 = apnsFetch("https://api.push.apple.com/3/device/c", { method: "POST", body: "{}" });
    await Promise.resolve();
    expect(sessions[0].destroyed).toBe(true);
    expect(sessions).toHaveLength(2);
    sessions[1].requests[0].respond(200);
    await p3;
  });

  it("opens at most one new connection per second per origin during an outage", async () => {
    let t = 10_000;
    const sleeps = [];
    const sessions = [];
    const apnsFetch = createApnsClient({
      connect: () => { const s = new FakeSession(); sessions.push(s); return s; },
      now: () => t,
      // Advancing the fake clock by the requested wait models real waiting.
      sleep: async (ms) => { sleeps.push(ms); t += ms; },
      log: quiet,
    });

    // Push 1 connects, then dies (connection error evicts it).
    const p1 = apnsFetch("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    await Promise.resolve();
    sessions[0].requests[0].emit("error", new Error("ECONNRESET"));
    sessions[0].emit("error", new Error("ECONNRESET"));
    await expect(p1).rejects.toThrow("ECONNRESET");
    expect(sleeps).toEqual([]);

    // Push 2 arrives 100ms later: it must wait out the rest of the 1s window.
    t += 100;
    const p2 = apnsFetch("https://api.push.apple.com/3/device/b", { method: "POST", body: "{}" });
    await new Promise((r) => setImmediate(r));
    expect(sleeps).toEqual([900]);
    expect(sessions).toHaveLength(2);
    sessions[1].requests[0].respond(200);
    await p2;

    // A different origin (sandbox) has its own window and is not delayed.
    const p3 = apnsFetch("https://api.sandbox.push.apple.com/3/device/c", { method: "POST", body: "{}" });
    await new Promise((r) => setImmediate(r));
    expect(sleeps).toEqual([900]);
    expect(sessions).toHaveLength(3);
    sessions[2].requests[0].respond(200);
    await p3;
  });

  it("makes concurrent pushes during the wait share one new connection", async () => {
    let t = 0;
    const sessions = [];
    const apnsFetch = createApnsClient({
      connect: () => { const s = new FakeSession(); sessions.push(s); return s; },
      now: () => t,
      sleep: async (ms) => { t += ms; },
      log: quiet,
    });

    const first = apnsFetch("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    await Promise.resolve();
    sessions[0].destroy(); // connection lost right after opening
    sessions[0].requests[0].emit("error", new Error("gone"));
    await expect(first).rejects.toThrow("gone");

    const burst = [1, 2, 3, 4, 5].map((i) =>
      apnsFetch(`https://api.push.apple.com/3/device/${i}`, { method: "POST", body: "{}" }));
    await new Promise((r) => setImmediate(r));
    expect(sessions).toHaveLength(2);        // one reconnect for the whole burst
    expect(sessions[1].requests).toHaveLength(5);
    sessions[1].requests.forEach((r) => r.respond(200));
    await Promise.all(burst);
  });
});
