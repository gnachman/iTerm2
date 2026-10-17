// Peer replication between two self-hosted relays (host/peer.js): two real
// listeners pointed at each other, with a switch per relay to simulate it being
// unreachable from its peer.

import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdtempSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createPushRelay } from "../host/server.js";
import { isNewer, PEER_RESPONSE_HEADER, PEER_INSTANCE_HEADER, PEER_BOOT_HEADER, PEER_TIME_HEADER } from "../host/peer.js";

// Throwaway P-256 key so the worker's APNs-JWT signer succeeds (Apple is stubbed).
const TEST_APNS_P8 = [
  "-----BEGIN PRIVATE KEY-----",
  "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgnjiLVvDqoxAEr50F",
  "Q5IEcY5FGUqvykFYDLxOr7Nn6FehRANCAARj1irFFlMCoD4iS9pNeD6XE/wY6KFh",
  "aA2rAzxkzFeNVZYnNUbNFLRc2G2cWhGGA/MbPTktoQhgwpYnRnoxrtJx",
  "-----END PRIVATE KEY-----",
].join("\n");
const ENV = {
  APNS_TOPIC: "com.googlecode.iterm2.companion",
  APNS_TEAM_ID: "TEAMID1234",
  APNS_KEY_ID: "KEYID56789",
  APNS_P8: TEST_APNS_P8,
  REGISTRATION_TTL_SECONDS: "3600",
};
const PEER_SECRET = "s3cret-shared-by-both-relays-0123456789";

const hex = (bytes) => [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
async function makeCreds() {
  const secretBytes = crypto.getRandomValues(new Uint8Array(32));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", secretBytes));
  return { secret: hex(secretBytes), secretHash: hex(digest) };
}
let tokenSeq = 0;
const freshToken = () => (++tokenSeq).toString(16).padStart(64, "0");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const apnsFetch = async () => ({ ok: true, status: 200, text: async () => "" });
apnsFetch.close = () => {};

const quietLog = { error: () => {} };

// One relay whose peer is reached through `route`, which the test points at the
// other relay (or makes fail).
// `clockOffsetMs` simulates a relay whose clock is off (its kv expiry and the
// sentAt it puts on forwards; the worker still stamps with the real clock).
function makeRelay(name, route, { peer = true, clockOffsetMs = 0 } = {}) {
  return createPushRelay({
    dbPath: ":memory:",
    now: () => Date.now() + clockOffsetMs,
    apnsFetch,
    env: ENV,
    peerUrl: peer ? `http://peer-of-${name}.invalid` : undefined,
    peerSecret: peer ? PEER_SECRET : undefined,
    peerFetch: (url, init) => route(url, init),
    peerRetryIntervalMs: 60 * 60 * 1000, // tests flush by hand
    peerRetryBackoffMs: 0,
  });
}

// Like makeRelay, on a database file (to restart a relay on the same data).
function makeRelayOn(dbPath, name, route) {
  return createPushRelay({
    dbPath,
    apnsFetch,
    env: ENV,
    peerUrl: `http://peer-of-${name}.invalid`,
    peerSecret: PEER_SECRET,
    peerFetch: (url, init) => route(url, init),
    peerRetryIntervalMs: 60 * 60 * 1000,
    peerRetryBackoffMs: 0,
  });
}

const base = (relay) => `http://127.0.0.1:${relay.address().port}`;
const call = (relay, path, body, headers = {}) =>
  fetch(base(relay) + path, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
const record = (relay, token) => relay.kv.get(`device:${token}`, "json");
// Two relays hold the same record. Stamps are compared and stored as sent, so
// a forwarded record is identical on both.
async function expectSameRecord(x, y, token) {
  const [rx, ry] = [await record(x, token), await record(y, token)];
  expect(rx).not.toBeNull();
  expect(rx).toEqual(ry);
}
const outbox = (relay) => relay.peer.gauges().peer_outbox;
const counter = (relay, name) => relay.metrics.counters.get(name) || 0;

describe("peer replication", () => {
  let a, b;
  const down = { a: false, b: false };

  // Route a forward to `target`, unless it is marked down.
  const routeTo = (getTarget, key) => (url, init) => {
    if (down[key]) return Promise.reject(new Error(`${key} is down`));
    return fetch(base(getTarget()) + new URL(url).pathname, init);
  };

  beforeEach(async () => {
    down.a = false;
    down.b = false;
    vi.spyOn(console, "error").mockImplementation(quietLog.error);
    a = makeRelay("a", routeTo(() => b, "b"));
    b = makeRelay("b", routeTo(() => a, "a"));
    await a.listen(0, "127.0.0.1");
    await b.listen(0, "127.0.0.1");
  });

  afterEach(async () => {
    await a.close();
    await b.close();
    vi.restoreAllMocks();
  });

  it("passes a registration on to the peer, which can then deliver pushes", async () => {
    const token = freshToken();
    const { secret, secretHash } = await makeCreds();
    expect((await call(a, "/register", { token, secretHash, sandbox: false })).status).toBe(200);

    await vi.waitFor(async () => expect(await record(b, token)).not.toBeNull());
    await expectSameRecord(b, a, token);

    const push = await call(b, "/push", { token, secret, title: "t", body: "b" });
    expect(push.status).toBe(200);
  });

  it("does not forward a received record back", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    await call(a, "/register", { token, secretHash, sandbox: false });
    await vi.waitFor(() => expect(counter(b, "peer_applied_total")).toBe(1));
    expect(counter(b, "peer_forward_ok_total")).toBe(0);
    expect(counter(b, "peer_forward_failed_total")).toBe(0);
  });

  it("queues a forward while the peer is down and delivers it on retry", async () => {
    down.b = true;
    const token = freshToken();
    const { secretHash } = await makeCreds();
    await call(a, "/register", { token, secretHash, sandbox: false });
    await vi.waitFor(() => expect(outbox(a)).toBe(1));
    expect(await record(b, token)).toBeNull();

    await a.peer.flush(); // still down: stays queued
    expect(outbox(a)).toBe(1);

    down.b = false;
    await a.peer.flush();
    expect(outbox(a)).toBe(0);
    await expectSameRecord(b, a, token);
  });

  it("queues the record on disk before replying, so a crash mid-send loses nothing", async () => {
    const dbPath = join(mkdtempSync(join(tmpdir(), "push-relay-")), "push.db");
    const token = freshToken();
    const { secretHash } = await makeCreds();
    // A relay whose send to the peer never completes (it crashes first).
    const hung = createPushRelay({
      dbPath,
      apnsFetch,
      env: ENV,
      peerUrl: "http://peer-of-hung.invalid",
      peerSecret: PEER_SECRET,
      peerFetch: () => new Promise(() => {}),
      peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0,
    });
    await hung.listen(0, "127.0.0.1");
    expect((await call(hung, "/register", { token, secretHash, sandbox: false })).status).toBe(200);
    // Already on disk when the phone got its reply.
    expect(outbox(hung)).toBe(1);
    await hung.close();

    // After the restart, the queued record reaches the peer.
    const restarted = createPushRelay({
      dbPath,
      apnsFetch,
      env: ENV,
      peerUrl: "http://peer-of-restarted.invalid",
      peerSecret: PEER_SECRET,
      peerFetch: routeTo(() => b, "b"),
      peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0,
    });
    await restarted.listen(0, "127.0.0.1");
    try {
      await vi.waitFor(() => expectSameRecord(b, restarted, token));
      await vi.waitFor(() => expect(outbox(restarted)).toBe(0));
    } finally {
      await restarted.close();
    }
  });

  it("forwards skipped (unchanged) registrations so a peer that missed one catches up", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    down.b = true;
    await call(a, "/register", { token, secretHash, sandbox: false });
    await vi.waitFor(() => expect(outbox(a)).toBe(1));

    // The phone reconnects; A skips the write but still forwards.
    down.b = false;
    const res = await call(a, "/register", { token, secretHash, sandbox: false });
    expect((await res.json()).skipped).toBe(true);
    await vi.waitFor(async () => expect(await record(b, token)).not.toBeNull());
  });

  it("converges on the newer secret when each relay saw a different one (re-pair)", async () => {
    const token = freshToken();
    const oldCreds = await makeCreds();
    const newCreds = await makeCreds();

    // Old secret registered on A while B is unreachable...
    down.b = true;
    await call(a, "/register", { token, secretHash: oldCreds.secretHash, sandbox: false });
    await vi.waitFor(() => expect(outbox(a)).toBe(1));
    await sleep(5); // distinct registeredAt
    // ...then the phone re-pairs and registers a new secret on B while A is unreachable.
    down.b = false;
    down.a = true;
    await call(b, "/register", { token, secretHash: newCreds.secretHash, sandbox: false });
    await vi.waitFor(() => expect(outbox(b)).toBe(1));

    // Both come back and drain their queues, in either order.
    down.a = false;
    await a.peer.flush();
    await b.peer.flush();
    expect((await record(a, token)).secretHash).toBe(newCreds.secretHash);
    expect((await record(b, token)).secretHash).toBe(newCreds.secretHash);

    // The old Mac's secret no longer works anywhere.
    for (const relay of [a, b]) {
      const push = await call(relay, "/push", { token, secret: oldCreds.secret, title: "t", body: "b" });
      expect(push.status).toBe(403);
    }
  });

  it("rejects a forward with the wrong peer secret", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    const res = await call(b, "/peer/register",
      { token, secretHash, sandbox: false, registeredAt: Date.now() },
      { authorization: "Bearer wrong" });
    expect(res.status).toBe(403);
    expect(await record(b, token)).toBeNull();
    expect(counter(b, "peer_rejected_total")).toBe(1);
  });

  it("ignores an expired forwarded record", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    const res = await call(b, "/peer/register",
      { token, secretHash, sandbox: false, registeredAt: Date.now() - 2 * 3600 * 1000 },
      { authorization: `Bearer ${PEER_SECRET}` });
    expect((await res.json()).applied).toBe(false);
    expect(await record(b, token)).toBeNull();
  });

  it("queues every registration at startup to seed a new peer", async () => {
    const dbPath = join(mkdtempSync(join(tmpdir(), "push-relay-")), "push.db");
    const tokens = [freshToken(), freshToken()];
    // A relay with registrations but no peer yet...
    const solo = createPushRelay({ dbPath, apnsFetch, env: ENV });
    await solo.listen(0, "127.0.0.1");
    for (const token of tokens) {
      await call(solo, "/register", { token, secretHash: (await makeCreds()).secretHash, sandbox: false });
    }
    await solo.close();
    // ...restarted on the same database with B as its peer.
    const c = createPushRelay({
      dbPath,
      apnsFetch,
      env: ENV,
      peerUrl: "http://peer-of-c.invalid",
      peerSecret: PEER_SECRET,
      peerFetch: routeTo(() => b, "b"),
      peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0,
    });
    await c.listen(0, "127.0.0.1");
    try {
      for (const token of tokens) {
        await vi.waitFor(() => expectSameRecord(b, c, token));
      }
      await vi.waitFor(() => expect(outbox(c)).toBe(0));
    } finally {
      await c.close();
    }
  });

  it("keeps a newer record queued when an older send finishes after it was queued", async () => {
    // Hold every send to B until the test releases it.
    const held = [];
    const gated = (url, init) => new Promise((resolve, reject) => {
      held.push(() => routeTo(() => b, "b")(url, init).then(resolve, reject));
    });
    const c = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer-of-c.invalid", peerSecret: PEER_SECRET,
      peerFetch: gated, peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0,
    });
    await c.listen(0, "127.0.0.1");
    try {
      const token = freshToken();
      await call(c, "/register", { token, secretHash: (await makeCreds()).secretHash, sandbox: false });
      await vi.waitFor(() => expect(held.length).toBe(1));
      await sleep(5);
      const newer = await makeCreds();
      await call(c, "/register", { token, secretHash: newer.secretHash, sandbox: false });
      expect(held.length).toBe(1); // one drain at a time: no second send yet

      // The first send completes. Its row was replaced while it was in flight,
      // so the row stays and the drain goes round again with the newer record.
      held[0]();
      await vi.waitFor(() => expect(held.length).toBe(2));
      expect(outbox(c)).toBe(1);

      held[1]();
      await vi.waitFor(() => expect(outbox(c)).toBe(0));
      expect((await record(b, token)).secretHash).toBe(newer.secretHash);
    } finally {
      await c.close();
    }
  });

  it("drops a record the peer refuses as malformed instead of stalling the queue", async () => {
    const tokens = [freshToken(), freshToken(), freshToken()].sort();
    const poisoned = tokens[0]; // sorts first, so it would block the others
    const c = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer-of-c.invalid", peerSecret: PEER_SECRET,
      peerFetch: (url, init) => JSON.parse(init.body).token === poisoned
        ? Promise.resolve(new Response('{"error":"bad record"}',
          { status: 400, headers: { [PEER_RESPONSE_HEADER]: "1" } }))
        : routeTo(() => b, "b")(url, init),
      peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0,
    });
    for (const token of tokens) {
      await c.kv.put(`device:${token}`,
        JSON.stringify({ secretHash: (await makeCreds()).secretHash, sandbox: false, registeredAt: Date.now() }),
        { expirationTtl: 3600 });
    }
    expect(c.peer.backfill()).toBe(3);
    await c.peer.flush();
    expect(outbox(c)).toBe(0);
    expect(await record(b, poisoned)).toBeNull();
    expect(await record(b, tokens[1])).not.toBeNull();
    expect(await record(b, tokens[2])).not.toBeNull();
    expect(counter(c, "peer_forward_dropped_total")).toBe(1);
    c.kv.close();
  });

  // A relay C with records for `tokens` already stored and queued, whose sends
  // go through `peerFetch`. Not listening; tests drive flush() directly.
  async function relayWithQueued(tokens, peerFetch) {
    const c = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer-of-c.invalid", peerSecret: PEER_SECRET,
      peerFetch, peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0,
    });
    for (const token of tokens) {
      await c.kv.put(`device:${token}`,
        JSON.stringify({ secretHash: (await makeCreds()).secretHash, sandbox: false, registeredAt: Date.now() }),
        { expirationTtl: 3600 });
    }
    expect(c.peer.backfill()).toBe(tokens.length);
    return c;
  }

  it("keeps the queue on a 400 that didn't come from the peer's own code", async () => {
    const tokens = [freshToken(), freshToken()];
    // e.g. plain HTTP to a TLS port, or a WAF rule.
    const c = await relayWithQueued(tokens,
      () => Promise.resolve(new Response("<html>400 Bad Request</html>", { status: 400 })));
    await c.peer.flush();
    expect(outbox(c)).toBe(2);
    expect(counter(c, "peer_forward_dropped_total")).toBe(0);
    expect(counter(c, "peer_forward_failed_total")).toBe(2);
    c.kv.close();
  });

  it("skips past a row that keeps failing, so the rows behind it still go", async () => {
    const tokens = [freshToken(), freshToken(), freshToken()].sort();
    const stuck = tokens[0];
    const c = await relayWithQueued(tokens, (url, init) => JSON.parse(init.body).token === stuck
      ? Promise.reject(new Error("timed out"))
      : routeTo(() => b, "b")(url, init));
    await c.peer.flush();
    expect(outbox(c)).toBe(1); // only the failing row is left
    expect(await record(b, tokens[1])).not.toBeNull();
    expect(await record(b, tokens[2])).not.toBeNull();
    c.kv.close();
  });

  it("gives up a pass after a few failures in a row when the peer is down", async () => {
    const tokens = Array.from({ length: 10 }, freshToken);
    let attempts = 0;
    const c = await relayWithQueued(tokens, () => { attempts++; return Promise.reject(new Error("down")); });
    await c.peer.flush();
    expect(attempts).toBe(3);
    expect(outbox(c)).toBe(10);
    c.kv.close();
  });

  it("doesn't queue or send an unchanged registration the peer already has", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    await call(a, "/register", { token, secretHash, sandbox: false });
    await vi.waitFor(() => expect(counter(a, "peer_forward_ok_total")).toBe(1));
    await vi.waitFor(() => expect(outbox(a)).toBe(0));

    // The phone reconnects: skipped by the worker, and the peer has it.
    const res = await call(a, "/register", { token, secretHash, sandbox: false });
    expect((await res.json()).skipped).toBe(true);
    expect(outbox(a)).toBe(0);
    await sleep(20);
    expect(counter(a, "peer_forward_ok_total")).toBe(1);
  });

  it("a phone re-pair sorts after a peer record stamped by a slightly fast clock", async () => {
    const token = freshToken();
    const oldCreds = await makeCreds();
    const newCreds = await makeCreds();
    // A's clock is 30s fast: it stamped the old secret 30s ahead, and B stored it.
    const ahead = Date.now() + 30_000;
    await call(b, "/peer/register",
      { token, secretHash: oldCreds.secretHash, sandbox: false, registeredAt: ahead },
      { authorization: `Bearer ${PEER_SECRET}` });
    await a.kv.put(`device:${token}`,
      JSON.stringify({ secretHash: oldCreds.secretHash, sandbox: false, registeredAt: ahead }), { expirationTtl: 3600 });

    // The user re-pairs, and the phone reaches B (A is unreachable).
    down.a = true;
    await call(b, "/register", { token, secretHash: newCreds.secretHash, sandbox: false });
    expect((await record(b, token)).registeredAt).toBeGreaterThan(ahead);

    // A restarts and backfills its old record to B, then both drain.
    down.a = false;
    a.peer.backfill();
    await a.peer.flush();
    await b.peer.flush();
    expect((await record(b, token)).secretHash).toBe(newCreds.secretHash);
    expect((await record(a, token)).secretHash).toBe(newCreds.secretHash);
  });

  it("answers 500 (marked as the peer's) when applying a record throws", async () => {
    const token = freshToken();
    await b.kv.put(`device:${token}`, "not json", { expirationTtl: 3600 }); // corrupt stored value
    const res = await call(b, "/peer/register",
      { token, secretHash: (await makeCreds()).secretHash, sandbox: false, registeredAt: Date.now() },
      { authorization: `Bearer ${PEER_SECRET}` });
    expect(res.status).toBe(500);
    expect(res.headers.get(PEER_RESPONSE_HEADER)).toBe("1");
  });

  it("keeps the startup backlog queued while the peer is down, then drains it", async () => {
    const dbPath = join(mkdtempSync(join(tmpdir(), "push-relay-")), "push.db");
    const token = freshToken();
    const solo = createPushRelay({ dbPath, apnsFetch, env: ENV });
    await solo.listen(0, "127.0.0.1");
    await call(solo, "/register", { token, secretHash: (await makeCreds()).secretHash, sandbox: false });
    await solo.close();

    down.b = true;
    const c = createPushRelay({
      dbPath, apnsFetch, env: ENV,
      peerUrl: "http://peer-of-c.invalid", peerSecret: PEER_SECRET,
      peerFetch: routeTo(() => b, "b"), peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0,
    });
    await c.listen(0, "127.0.0.1");
    try {
      await vi.waitFor(() => expect(counter(c, "peer_forward_failed_total")).toBe(1));
      expect(outbox(c)).toBe(1);
      down.b = false;
      await c.peer.flush();
      expect(outbox(c)).toBe(0);
      await expectSameRecord(b, c, token);
    } finally {
      await c.close();
    }
  });

  it("refuses a stamp in its future as retryable, keeping it queued", async () => {
    const token = freshToken();
    const res = await call(b, "/peer/register",
      { token, secretHash: (await makeCreds()).secretHash, sandbox: false,
        registeredAt: Date.now() + 3600 * 1000, sentAt: Date.now() },
      { authorization: `Bearer ${PEER_SECRET}` });
    expect(res.status).toBe(409);
    expect(await record(b, token)).toBeNull();

    // From the sender's side (its clock stepped back after stamping): kept.
    const tokens = [freshToken()];
    const c = await relayWithQueued(tokens, (url, init) => {
      const body = JSON.parse(init.body);
      return routeTo(() => b, "b")(url, { ...init, body: JSON.stringify({ ...body, registeredAt: Date.now() + 5 * 60 * 1000 }) });
    });
    await c.peer.flush();
    expect(outbox(c)).toBe(1);
    expect(counter(c, "peer_forward_dropped_total")).toBe(0);
    c.kv.close();
  });

  it("refuses records from a peer whose clock is over an hour off, keeping them queued", async () => {
    const tokens = [freshToken()];
    const skewed = Date.now() + 2 * 3600 * 1000;
    const c = await relayWithQueued(tokens, (url, init) => {
      const body = JSON.parse(init.body);
      return routeTo(() => b, "b")(url, { ...init, body: JSON.stringify({ ...body, sentAt: skewed }) });
    });
    await c.peer.flush();
    expect(outbox(c)).toBe(1);
    expect(await record(b, tokens[0])).toBeNull();
    expect(counter(b, "peer_rejected_total")).toBe(1);
    c.kv.close();
  });

  it("doesn't re-apply or drift a record echoed back over a slow link", async () => {
    // A 20ms link each way, so a converted stamp lands ~20ms later each hop.
    const slow = (getTarget, key) => (url, init) =>
      sleep(20).then(() => routeTo(getTarget, key)(url, init));
    let sa;
    const sb = makeRelay("sb", slow(() => sa, "a"));
    sa = makeRelay("sa", slow(() => sb, "b"));
    await sa.listen(0, "127.0.0.1");
    await sb.listen(0, "127.0.0.1");
    try {
      const token = freshToken();
      await call(sa, "/register", { token, secretHash: (await makeCreds()).secretHash, sandbox: false });
      await vi.waitFor(() => expect(counter(sb, "peer_applied_total")).toBe(1));
      const stampA = (await record(sa, token)).registeredAt;
      const stampB = (await record(sb, token)).registeredAt;

      for (let round = 0; round < 3; round++) {
        sb.peer.backfill();
        await sb.peer.flush();
        sa.peer.backfill();
        await sa.peer.flush();
      }
      expect(counter(sa, "peer_applied_total")).toBe(0);
      expect(counter(sb, "peer_applied_total")).toBe(1);
      expect((await record(sa, token)).registeredAt).toBe(stampA);
      expect((await record(sb, token)).registeredAt).toBe(stampB);
    } finally {
      await sa.close();
      await sb.close();
    }
  });

  it("resends everything after the peer restarts (e.g. from a backup)", async () => {
    const dbPath = join(mkdtempSync(join(tmpdir(), "push-relay-")), "push.db");
    const route = routeTo(() => fileB, "b");
    let fileB = makeRelayOn(dbPath, "fileB", routeTo(() => a2, "a"));
    const a2 = makeRelay("a2", route);
    await fileB.listen(0, "127.0.0.1");
    await a2.listen(0, "127.0.0.1");
    try {
      const token = freshToken();
      const { secretHash } = await makeCreds();
      await call(a2, "/register", { token, secretHash, sandbox: false });
      await vi.waitFor(() => expect(outbox(a2)).toBe(0));
      await a2.peer.tick(); // learn B's boot id

      // B restarts on a database restored from before it had this device.
      await fileB.close();
      const { SqliteKV } = await import("../host/kv.js");
      const raw = new SqliteKV(dbPath);
      await raw.delete(`device:${token}`);
      raw.close();
      fileB = makeRelayOn(dbPath, "fileB", routeTo(() => a2, "a"));
      await fileB.listen(0, "127.0.0.1");

      await a2.peer.tick(); // hello: same instance, new boot
      expect(counter(a2, "peer_rebuilt_total")).toBe(0);
      // A queues everything for it again, with no phone activity needed.
      await vi.waitFor(async () => expect(await record(fileB, token)).not.toBeNull());
    } finally {
      await a2.close();
      await fileB.close();
    }
  });

  it("keeps the clock-skew gauge current on the sending side too", async () => {
    const offset = 90 * 1000;
    let a2;
    const fastB = makeRelay("fastB", routeTo(() => a2, "a"), { clockOffsetMs: offset });
    a2 = makeRelay("a2", routeTo(() => fastB, "b"));
    await fastB.listen(0, "127.0.0.1");
    try {
      await a2.peer.tick(); // just a hello
      expect(a2.peer.gauges().peer_clock_skew_ms).toBeGreaterThan(offset - 1000);
      expect(a2.peer.gauges().peer_clock_skew_ms).toBeLessThan(offset + 1000);
    } finally {
      await fastB.close();
      a2.kv.close();
    }
  });

  it("doesn't count a record the peer dropped as expired as held by it", async () => {
    // A keeps registrations 4h, B only 1h. A's record is 90 minutes old.
    const longA = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: { ...ENV, REGISTRATION_TTL_SECONDS: "14400" },
      peerUrl: "http://peer-of-longA.invalid", peerSecret: PEER_SECRET,
      peerFetch: routeTo(() => b, "b"), peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0,
    });
    await longA.listen(0, "127.0.0.1");
    try {
      const token = freshToken();
      const { secretHash } = await makeCreds();
      await longA.kv.put(`device:${token}`, JSON.stringify(
        { secretHash, sandbox: false, registeredAt: Date.now() - 90 * 60 * 1000 }), { expirationTtl: 14400 });
      longA.peer.backfill();
      await longA.peer.flush();
      expect(await record(b, token)).toBeNull();
      expect(outbox(longA)).toBe(0);
      // The phone re-registers at A: skipped there, but B doesn't hold it, so
      // it must still be queued (B drops it again, which is right for B's TTL).
      const res = await call(longA, "/register", { token, secretHash, sandbox: false });
      expect((await res.json()).skipped).toBe(true);
      await vi.waitFor(() => expect(counter(longA, "peer_forward_ok_total")).toBe(2));
    } finally {
      await longA.close();
    }
  });

  it("holds a burst of re-pairs that outran the clock until the clock catches up", async () => {
    // 70 changed registrations in a moment ratchet A's stamp ~70s ahead.
    const token = freshToken();
    let last;
    for (let i = 0; i < 70; i++) {
      last = await makeCreds();
      await call(a, "/register", { token, secretHash: last.secretHash, sandbox: false });
    }
    expect((await record(a, token)).secretHash).toBe(last.secretHash);
    await a.peer.flush();
    // B refuses the far-future stamp as retryable; A keeps it queued.
    await vi.waitFor(() => expect(counter(b, "peer_rejected_total")).toBeGreaterThan(0));
    expect(outbox(a)).toBe(1);
    expect(counter(a, "peer_forward_dropped_total")).toBe(0);

    // Two minutes pass, for every clock in the process.
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(Date.now() + 2 * 60 * 1000);
      await a.peer.flush();
      await vi.waitFor(() => expect(outbox(a)).toBe(0));
      expect((await record(b, token)).secretHash).toBe(last.secretHash);
    } finally {
      vi.useRealTimers();
    }
  });

  it("tells only an authenticated caller its instance, boot, and clock", async () => {
    for (const path of ["/peer/hello", "/peer/register"]) {
      const anon = await call(b, path, {});
      expect(anon.status).toBe(403);
      expect(anon.headers.get(PEER_RESPONSE_HEADER)).toBe("1");
      expect(anon.headers.get(PEER_INSTANCE_HEADER)).toBeNull();
      expect(anon.headers.get(PEER_BOOT_HEADER)).toBeNull();
      expect(anon.headers.get(PEER_TIME_HEADER)).toBeNull();
    }
    const authed = await call(b, "/peer/hello", {}, { authorization: `Bearer ${PEER_SECRET}` });
    expect(authed.status).toBe(200);
    expect(authed.headers.get(PEER_INSTANCE_HEADER)).toBeTruthy();
  });

  it("after a pass gives up, waits a few seconds before sending again", async () => {
    const tokens = Array.from({ length: 6 }, freshToken);
    let attempts = 0;
    const c = await relayWithQueued(tokens, () => { attempts++; return Promise.reject(new Error("down")); });
    await c.peer.flush();
    expect(attempts).toBe(3);
    // A registration storm right after: no new sends during the cooldown.
    for (let i = 0; i < 5; i++) await c.peer.flush();
    expect(attempts).toBe(3);
    c.peer.stop();
    c.kv.close();
  });

  it("compares stamps as sent, so a slow link can't reorder a re-pair", async () => {
    // A's forwards to B take 1.5s. The phone registers S1 at A, then 200ms
    // later re-pairs with S2 at B (A is the struggling relay).
    let sa;
    const sb = makeRelay("sb", routeTo(() => sa, "a"));
    sa = makeRelay("sa", (url, init) => sleep(1500).then(() => routeTo(() => sb, "b")(url, init)));
    await sa.listen(0, "127.0.0.1");
    await sb.listen(0, "127.0.0.1");
    try {
      const token = freshToken();
      const s1 = await makeCreds();
      const s2 = await makeCreds();
      await call(sa, "/register", { token, secretHash: s1.secretHash, sandbox: false });
      await sleep(200);
      await call(sb, "/register", { token, secretHash: s2.secretHash, sandbox: false });
      await vi.waitFor(() => expect(outbox(sa) + outbox(sb)).toBe(0), { timeout: 5000 });
      expect((await record(sa, token)).secretHash).toBe(s2.secretHash);
      expect((await record(sb, token)).secretHash).toBe(s2.secretHash);
    } finally {
      await sa.close();
      await sb.close();
    }
  }, 10_000);

  it("treats a 2xx that isn't the peer's own answer as a failure", async () => {
    const tokens = [freshToken()];
    // e.g. a misrouted PUSH_PEER_URL whose site answers 200 to anything.
    const c = await relayWithQueued(tokens, () => Promise.resolve(new Response("<html>ok</html>", { status: 200 })));
    await c.peer.flush();
    expect(outbox(c)).toBe(1);
    expect(counter(c, "peer_forward_ok_total")).toBe(0);
    c.kv.close();
  });

  it("doesn't give up on the peer because of rows it is up and refusing", async () => {
    const refused = Array.from({ length: 50 }, freshToken);
    const good = "f".repeat(64); // sorts after all of them
    const c = await relayWithQueued([...refused, good], (url, init) => JSON.parse(init.body).token === good
      ? routeTo(() => b, "b")(url, init)
      : Promise.resolve(new Response('{"error":"registeredAt is in the future"}',
        { status: 409, headers: { [PEER_RESPONSE_HEADER]: "1" } })));
    await c.peer.flush();
    expect(await record(b, good)).not.toBeNull();
    expect(outbox(c)).toBe(50);
    c.kv.close();
  });

  it("records when the peer last answered", async () => {
    expect(a.peer.gauges().peer_last_ok_timestamp_seconds).toBe(0);
    await a.peer.tick(); // hello
    expect(Math.abs(a.peer.gauges().peer_last_ok_timestamp_seconds - Date.now() / 1000)).toBeLessThan(5);

    // A peer that rejects our secret doesn't count.
    const wrong = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer-of-wrong.invalid", peerSecret: "a-different-secret-that-is-long-enough",
      peerFetch: routeTo(() => b, "b"), peerRetryIntervalMs: 60 * 60 * 1000,
    });
    await wrong.peer.tick();
    expect(wrong.peer.gauges().peer_last_ok_timestamp_seconds).toBe(0);
    wrong.kv.close();
  });

  it("notices when PUSH_PEER_URL points at the relay itself", async () => {
    let self;
    self = makeRelay("self", routeTo(() => self, "a"));
    await self.listen(0, "127.0.0.1");
    try {
      const token = freshToken();
      await call(self, "/register", { token, secretHash: (await makeCreds()).secretHash, sandbox: false });
      await vi.waitFor(() => expect(counter(self, "peer_self_total")).toBeGreaterThan(0));
      expect(outbox(self)).toBe(1);
      expect(counter(self, "peer_forward_ok_total")).toBe(0);
      expect(self.peer.gauges().peer_last_ok_timestamp_seconds).toBe(0);
    } finally {
      await self.close();
    }
  });

  it("queues a registration sent to a non-normalized /register path", async () => {
    const token = freshToken();
    const body = JSON.stringify({ token, secretHash: (await makeCreds()).secretHash, sandbox: false });
    // node:http sends the path as written (fetch would normalize it first).
    const status = await new Promise((resolve, reject) => {
      const req = http.request({
        host: "127.0.0.1", port: a.address().port, method: "POST", path: "/./register",
        headers: { "content-type": "application/json", "content-length": Buffer.byteLength(body) },
      }, (res) => { res.resume(); res.on("end", () => resolve(res.statusCode)); });
      req.on("error", reject);
      req.end(body);
    });
    expect(status).toBe(200);
    await vi.waitFor(async () => expect(await record(b, token)).not.toBeNull());
  });

  it("picks outbox rows with an index walk, not a sort", () => {
    const plan = a.kv.db.prepare(
      `EXPLAIN QUERY PLAN SELECT token, record, attempts FROM peer_outbox WHERE next_try_at <= ?
       ORDER BY priority DESC, next_try_at, token LIMIT ?`).all(Date.now(), 1).map((r) => r.detail).join(" | ");
    expect(plan).toMatch(/peer_outbox_pick/);
    expect(plan).not.toMatch(/TEMP B-TREE/);
  });

  it("gives up on a peer whose own code keeps answering 500", async () => {
    // e.g. its disk is full: every record fails, not just one.
    const tokens = Array.from({ length: 30 }, freshToken);
    let sends = 0;
    const c = await relayWithQueued(tokens, () => {
      sends++;
      return Promise.resolve(new Response('{"error":"SQLITE_FULL"}', { status: 500, headers: { [PEER_RESPONSE_HEADER]: "1" } }));
    });
    const errors = [];
    console.error.mockImplementation((...args) => errors.push(args.join(" ")));
    await c.peer.flush();
    expect(sends).toBe(20); // MAX_PEER_ERRORS_PER_PASS
    expect(outbox(c)).toBe(30);
    // One summary line for the pass, not a line per row.
    expect(errors.filter((l) => l.includes("send(s) to the peer failed")).length).toBe(1);
    c.peer.stop();
    c.kv.close();
  });

  it("drains a backlog in one pass despite a few live rows the peer always 500s", async () => {
    const bad = [freshToken(), freshToken(), freshToken()];
    const backlog = Array.from({ length: 50 }, freshToken);
    const c = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer-of-c.invalid", peerSecret: PEER_SECRET,
      peerFetch: (url, init) => bad.includes(JSON.parse(init.body).token)
        ? routeTo(() => b, "b")(url, init).then(() => new Response('{"error":"corrupt"}',
          { status: 500, headers: { [PEER_RESPONSE_HEADER]: "1", [PEER_INSTANCE_HEADER]: b.peer.instanceId } }))
        : routeTo(() => b, "b")(url, init),
      peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 60 * 1000,
    });
    for (const token of [...backlog, ...bad]) {
      await c.kv.put(`device:${token}`,
        JSON.stringify({ secretHash: (await makeCreds()).secretHash, sandbox: false, registeredAt: Date.now() }),
        { expirationTtl: 3600 });
    }
    c.peer.backfill();
    for (const token of bad) await c.peer.enqueue(token); // live, so they sort first
    await c.peer.flush();
    expect(outbox(c)).toBe(3);
    for (const token of backlog) expect(await record(b, token)).not.toBeNull();
    c.peer.stop();
    c.kv.close();
  });

  it("honors a flush asked for while a pass was giving up", async () => {
    let up = false;
    let calls = 0;
    const c = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer-of-c.invalid", peerSecret: PEER_SECRET,
      peerFetch: async (url, init) => {
        calls++;
        if (calls === 3) c.peer.flush(); // a registration lands during the last failing send
        if (!up) throw new Error("timed out");
        return routeTo(() => b, "b")(url, init);
      },
      peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 0, peerGiveUpCooldownMs: 50,
    });
    const tokens = Array.from({ length: 4 }, freshToken);
    for (const token of tokens) {
      await c.kv.put(`device:${token}`,
        JSON.stringify({ secretHash: (await makeCreds()).secretHash, sandbox: false, registeredAt: Date.now() }),
        { expirationTtl: 3600 });
    }
    c.peer.backfill();
    await c.peer.flush();      // gives up after 3
    up = true;                 // the blip passes; nothing else calls flush()
    await vi.waitFor(() => expect(outbox(c)).toBe(0), { timeout: 2000 });
    c.peer.stop();
    c.kv.close();
  });

  it("retries rows that were backing off as soon as the peer is back", async () => {
    const tokens = Array.from({ length: 5 }, freshToken);
    let up = false;
    const c = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer-of-c.invalid", peerSecret: PEER_SECRET,
      peerFetch: (url, init) => up ? routeTo(() => b, "b")(url, init) : Promise.reject(new Error("down")),
      peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 60 * 60 * 1000, // long backoff
    });
    for (const token of tokens) {
      await c.kv.put(`device:${token}`,
        JSON.stringify({ secretHash: (await makeCreds()).secretHash, sandbox: false, registeredAt: Date.now() }),
        { expirationTtl: 3600 });
    }
    c.peer.backfill();
    await c.peer.flush();            // gives up; 3 rows now backing off for an hour
    up = true;
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(Date.now() + 10 * 1000); // past the give-up cooldown
      await c.peer.tick();           // hello succeeds: the peer is back
      await c.peer.flush();
    } finally {
      vi.useRealTimers();
    }
    expect(outbox(c)).toBe(0);
    c.peer.stop();
    c.kv.close();
  });

  it("resends everything when the peer's database is replaced", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    await call(a, "/register", { token, secretHash, sandbox: false });
    await vi.waitFor(() => expect(counter(a, "peer_forward_ok_total")).toBe(1));
    await vi.waitFor(() => expect(outbox(a)).toBe(0));

    // B is rebuilt with an empty database.
    const oldB = b;
    b = makeRelay("b", routeTo(() => a, "a"));
    await b.listen(0, "127.0.0.1");
    await oldB.close();

    // The phone re-registers at A: unchanged, and A thinks B has it.
    expect((await (await call(a, "/register", { token, secretHash, sandbox: false })).json()).skipped).toBe(true);
    expect(outbox(a)).toBe(0);

    // A's next idle tick says hello, sees a new instance, and resends.
    await a.peer.tick();
    await vi.waitFor(async () => expect(await record(b, token)).not.toBeNull());
    expect(counter(a, "peer_rebuilt_total")).toBe(1);
  });

  it("sends a live registration ahead of a startup backlog", async () => {
    const backlog = Array.from({ length: 10 }, freshToken);
    const order = [];
    const c = await relayWithQueued(backlog, (url, init) => {
      order.push(JSON.parse(init.body).token);
      return sleep(5).then(() => routeTo(() => b, "b")(url, init));
    });
    const drain = c.peer.flush();
    await vi.waitFor(() => expect(order.length).toBeGreaterThan(1));
    // A phone registers mid-drain.
    const live = freshToken();
    await c.kv.put(`device:${live}`,
      JSON.stringify({ secretHash: (await makeCreds()).secretHash, sandbox: false, registeredAt: Date.now() }),
      { expirationTtl: 3600 });
    await c.peer.enqueue(live);
    const sentSoFar = order.length; // includes the one in flight
    c.peer.flush();
    await drain;
    await vi.waitFor(() => expect(outbox(c)).toBe(0));
    expect(sentSoFar).toBeLessThan(backlog.length);
    expect(order.indexOf(live)).toBe(sentSoFar); // next after the send in flight, not last
    c.kv.close();
  });

  it("moves a row that failed behind the others until its backoff passes", async () => {
    const tokens = [freshToken(), freshToken()].sort();
    let failFirst = true;
    const c = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer-of-c.invalid", peerSecret: PEER_SECRET,
      peerFetch: (url, init) => JSON.parse(init.body).token === tokens[0] && failFirst
        ? Promise.reject(new Error("blip"))
        : routeTo(() => b, "b")(url, init),
      peerRetryIntervalMs: 60 * 60 * 1000, peerRetryBackoffMs: 60 * 60 * 1000,
    });
    for (const token of tokens) {
      await c.kv.put(`device:${token}`,
        JSON.stringify({ secretHash: (await makeCreds()).secretHash, sandbox: false, registeredAt: Date.now() }),
        { expirationTtl: 3600 });
    }
    c.peer.backfill();
    await c.peer.flush();
    expect(outbox(c)).toBe(1);           // the other row went
    failFirst = false;
    await c.peer.flush();
    expect(outbox(c)).toBe(1);           // still backing off
    c.kv.close();
  });

  it("uses the sender's TTL for the expiry", async () => {
    const auth = { authorization: `Bearer ${PEER_SECRET}` };
    // Our TTL is 3600s. The sender's is 120s, so a record stamped 200s ago has
    // already expired by its rules...
    const stale = freshToken();
    await call(b, "/peer/register",
      { token: stale, secretHash: (await makeCreds()).secretHash, sandbox: false,
        registeredAt: Date.now() - 200 * 1000, ttlSeconds: 120 }, auth);
    expect(await record(b, stale)).toBeNull();

    // ...and one stamped 60s ago has about 60s left, not about an hour.
    const fresh = freshToken();
    await call(b, "/peer/register",
      { token: fresh, secretHash: (await makeCreds()).secretHash, sandbox: false,
        registeredAt: Date.now() - 60 * 1000, ttlSeconds: 120 }, auth);
    const { keys } = await b.kv.list({ prefix: `device:${fresh}` });
    expect(keys[0].expiration - Date.now() / 1000).toBeLessThan(120);
  });

  it("rejects a missing auth header and a malformed body", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    expect((await call(b, "/peer/register", { token, secretHash, sandbox: false, registeredAt: Date.now() })).status)
      .toBe(403);
    const bad = await fetch(base(b) + "/peer/register", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${PEER_SECRET}` },
      body: "{not json",
    });
    expect(bad.status).toBe(400);
    expect((await call(b, "/peer/register", { token, secretHash: "zz", sandbox: false, registeredAt: Date.now() },
      { authorization: `Bearer ${PEER_SECRET}` })).status).toBe(400);
    expect(await record(b, token)).toBeNull();
  });

  it("exports peer metrics", async () => {
    const res = await fetch(base(a) + "/metrics");
    const text = await res.text();
    expect(text).toMatch(/^pushrelay_peer_outbox 0$/m);
    expect(text).toMatch(/^pushrelay_peer_forward_ok_total 0$/m);
  });
});

describe("peer replication disabled", () => {
  it("is refused with a short secret", async () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    const relay = createPushRelay({
      dbPath: ":memory:", apnsFetch, env: ENV,
      peerUrl: "http://peer.invalid", peerSecret: "too-short",
    });
    expect(relay.peer).toBeNull();
    expect(errors.mock.calls.flat().join(" ")).toMatch(/peer replication disabled/);
    errors.mockRestore();
    relay.kv.close();
  });

  it("has no /peer/register endpoint", async () => {
    const relay = makeRelay("solo", () => Promise.reject(new Error("unused")), { peer: false });
    await relay.listen(0, "127.0.0.1");
    try {
      expect(relay.peer).toBeNull();
      const res = await call(relay, "/peer/register", {}, { authorization: `Bearer ${PEER_SECRET}` });
      expect(res.status).toBe(404);
    } finally {
      await relay.close();
    }
  });
});

describe("isNewer", () => {
  const rec = (registeredAt, secretHash = "a".repeat(64), sandbox = false) =>
    ({ registeredAt, secretHash, sandbox });

  it("takes a later registeredAt and anything over nothing", () => {
    expect(isNewer(rec(2), rec(1))).toBe(true);
    expect(isNewer(rec(1), rec(2))).toBe(false);
    expect(isNewer(rec(1), null)).toBe(true);
  });

  it("breaks an exact tie the same way on both sides", () => {
    const x = rec(5, "a".repeat(64));
    const y = rec(5, "b".repeat(64));
    expect(isNewer(x, y)).not.toBe(isNewer(y, x));
    expect(isNewer(x, x)).toBe(false);
  });
});
