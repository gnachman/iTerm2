// POST /register: the phone registers sha256(secret) under its APNs token so the
// paired Mac can later push to it. The record self-expires (expirationTtl) so a
// dead pairing's registration does not linger in KV forever. Input validation
// rejects malformed tokens/hashes and oversized bodies.

import { describe, it, expect } from "vitest";
import { env } from "cloudflare:test";
import { freshToken, makeSecret, post } from "./helpers.js";

describe("POST /register", () => {
  it("stores the device record for a valid registration", async () => {
    const token = freshToken();
    const { secretHash } = await makeSecret();

    const res = await post("/register", { token, secretHash, sandbox: false });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });

    const record = await env.PUSH_KV.get(`device:${token}`, "json");
    expect(record.secretHash).toBe(secretHash);
    expect(record.sandbox).toBe(false);
    expect(typeof record.registeredAt).toBe("number");
  });

  it("carries sandbox through when set", async () => {
    const token = freshToken();
    const { secretHash } = await makeSecret();
    await post("/register", { token, secretHash, sandbox: true });
    const record = await env.PUSH_KV.get(`device:${token}`, "json");
    expect(record.sandbox).toBe(true);
  });

  it("writes the record with a self-expiry TTL (so junk ages out)", async () => {
    const token = freshToken();
    const { secretHash } = await makeSecret();
    await post("/register", { token, secretHash, sandbox: false });

    // REGISTRATION_TTL_SECONDS is 3600 in the test config; KV list reports the
    // absolute expiration (unix seconds), which must sit ~1h out, not unset.
    const { keys } = await env.PUSH_KV.list({ prefix: `device:${token}` });
    expect(keys).toHaveLength(1);
    const nowSec = Math.floor(Date.now() / 1000);
    expect(keys[0].expiration).toBeGreaterThan(nowSec + 3600 - 120);
    expect(keys[0].expiration).toBeLessThan(nowSec + 3600 + 120);
  });

  it("re-registration overwrites the prior record (only the token holder can)", async () => {
    const token = freshToken();
    const first = await makeSecret();
    const second = await makeSecret();
    await post("/register", { token, secretHash: first.secretHash, sandbox: false });
    await post("/register", { token, secretHash: second.secretHash, sandbox: true });
    const record = await env.PUSH_KV.get(`device:${token}`, "json");
    expect(record.secretHash).toBe(second.secretHash);
    expect(record.sandbox).toBe(true);
  });

  it("rejects a malformed token", async () => {
    const { secretHash } = await makeSecret();
    const res = await post("/register", { token: "nothex!!", secretHash, sandbox: false });
    expect(res.status).toBe(400);
  });

  it("rejects a malformed secretHash (wrong length)", async () => {
    const token = freshToken();
    const res = await post("/register", { token, secretHash: "abc123", sandbox: false });
    expect(res.status).toBe(400);
  });

  it("rejects an oversized body before parsing", async () => {
    const res = await post("/register", "x".repeat(5000));
    expect(res.status).toBe(400);
  });

  // The IP rate limiter is an optional binding the worker guards on; it is not
  // wired in the test env (and Miniflare does not exercise it), so registrations
  // succeed regardless of CF-Connecting-IP. This pins the binding-absent path so
  // a future change cannot make /register hard-depend on the limiter.
  it("still serves when no rate-limit binding is configured", async () => {
    const token = freshToken();
    const { secretHash } = await makeSecret();
    const res = await post("/register", { token, secretHash, sandbox: false },
      { "CF-Connecting-IP": "203.0.113.7" });
    expect(res.status).toBe(200);
  });
});
