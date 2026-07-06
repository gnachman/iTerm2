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
}

describe("createApnsClient", () => {
  it("maps headers, sends the body, and resolves ok on 2xx", async () => {
    const session = new FakeSession();
    const apnsFetch = createApnsClient({ connect: () => session });

    const p = apnsFetch("https://api.push.apple.com/3/device/abc123", {
      method: "POST",
      headers: { authorization: "bearer JWT", "apns-topic": "com.x", host: "drop-me", ":oops": "drop" },
      body: JSON.stringify({ aps: {} }),
    });

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
    const apnsFetch = createApnsClient({ connect: () => session });
    const p = apnsFetch("https://api.push.apple.com/3/device/x", { method: "POST", body: "{}" });
    session.requests[0].respond(410, '{"reason":"Unregistered"}');
    const res = await p;
    expect(res.ok).toBe(false);
    expect(res.status).toBe(410);
    expect(await res.text()).toBe('{"reason":"Unregistered"}');
  });

  it("reuses one session per origin across pushes", async () => {
    let opened = 0;
    const session = new FakeSession();
    const apnsFetch = createApnsClient({ connect: () => { opened += 1; return session; } });

    const p1 = apnsFetch("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    session.requests[0].respond(200);
    await p1;
    const p2 = apnsFetch("https://api.push.apple.com/3/device/b", { method: "POST", body: "{}" });
    session.requests[1].respond(200);
    await p2;

    expect(opened).toBe(1);           // second push multiplexed over the same session
    expect(session.requests).toHaveLength(2);
  });

  it("reopens a session after it closes (GOAWAY / idle drop)", async () => {
    const sessions = [];
    const apnsFetch = createApnsClient({
      connect: () => { const s = new FakeSession(); sessions.push(s); return s; },
    });

    const p1 = apnsFetch("https://api.push.apple.com/3/device/a", { method: "POST", body: "{}" });
    sessions[0].requests[0].respond(200);
    await p1;

    sessions[0].close(); // 'close' evicts it from the pool

    const p2 = apnsFetch("https://api.push.apple.com/3/device/b", { method: "POST", body: "{}" });
    sessions[1].requests[0].respond(200);
    await p2;

    expect(sessions).toHaveLength(2); // a fresh session was opened after the close
  });
});
