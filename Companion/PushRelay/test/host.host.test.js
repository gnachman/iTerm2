// End-to-end through the self-hosted bridge: a real HTTP listener -> worker.fetch
// -> SqliteKV, with APNs stubbed via env.fetchImpl. Proves /register and /push
// work off Cloudflare, the secret check still gates delivery, and the idempotent
// write survives the whole stack (the fix that motivated the migration).

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { createPushRelay } from "../host/server.js";

// Throwaway P-256 key so the worker's APNs-JWT signer succeeds; never verified
// here (Apple is stubbed). Same key the Workers test config uses.
const TEST_APNS_P8 = [
  "-----BEGIN PRIVATE KEY-----",
  "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgnjiLVvDqoxAEr50F",
  "Q5IEcY5FGUqvykFYDLxOr7Nn6FehRANCAARj1irFFlMCoD4iS9pNeD6XE/wY6KFh",
  "aA2rAzxkzFeNVZYnNUbNFLRc2G2cWhGGA/MbPTktoQhgwpYnRnoxrtJx",
  "-----END PRIVATE KEY-----",
].join("\n");

const hex = (bytes) => [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");

async function makeCreds() {
  const secretBytes = crypto.getRandomValues(new Uint8Array(32));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", secretBytes));
  return { secret: hex(secretBytes), secretHash: hex(digest) };
}
let tokenSeq = 0;
const freshToken = () => (++tokenSeq).toString(16).padStart(64, "0");

describe("self-hosted push relay (end-to-end)", () => {
  let relay;
  let base;
  const apnsCalls = [];

  const apnsFetch = async (url) => {
    apnsCalls.push(url);
    return { ok: true, status: 200, text: async () => "" };
  };
  apnsFetch.close = () => {};

  const call = (path, body) =>
    fetch(base + path, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });

  beforeAll(async () => {
    relay = createPushRelay({
      dbPath: ":memory:",
      apnsFetch,
      env: {
        APNS_TOPIC: "com.googlecode.iterm2.companion",
        APNS_TEAM_ID: "TEAMID1234",
        APNS_KEY_ID: "KEYID56789",
        APNS_P8: TEST_APNS_P8,
        REGISTRATION_TTL_SECONDS: "3600",
      },
    });
    await relay.listen(0, "127.0.0.1");
    base = `http://127.0.0.1:${relay.address().port}`;
  });
  afterAll(async () => { await relay.close(); });

  it("registers, then delivers a push for the matching secret", async () => {
    const token = freshToken();
    const { secret, secretHash } = await makeCreds();

    const reg = await call("/register", { token, secretHash, sandbox: false });
    expect(reg.status).toBe(200);
    expect(await reg.json()).toEqual({ ok: true });

    apnsCalls.length = 0;
    const push = await call("/push", { token, secret, title: "hi", body: "there" });
    expect(push.status).toBe(200);
    expect(apnsCalls).toHaveLength(1);
    expect(apnsCalls[0]).toBe(`https://api.push.apple.com/3/device/${token}`);
  });

  it("rejects a push with the wrong secret (bad secret), no APNs call", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    const wrong = await makeCreds();
    await call("/register", { token, secretHash, sandbox: false });

    apnsCalls.length = 0;
    const push = await call("/push", { token, secret: wrong.secret, title: "x", body: "y" });
    expect(push.status).toBe(403);
    expect((await push.json()).error).toBe("bad secret");
    expect(apnsCalls).toHaveLength(0);
  });

  it("routes sandbox registrations to Apple's sandbox host", async () => {
    const token = freshToken();
    const { secret, secretHash } = await makeCreds();
    await call("/register", { token, secretHash, sandbox: true });

    apnsCalls.length = 0;
    await call("/push", { token, secret, title: "x", body: "y" });
    expect(apnsCalls[0]).toBe(`https://api.sandbox.push.apple.com/3/device/${token}`);
  });

  it("skips the KV write on an unchanged re-registration (idempotency end-to-end)", async () => {
    const token = freshToken();
    const { secretHash } = await makeCreds();
    expect(await (await call("/register", { token, secretHash, sandbox: false })).json())
      .toEqual({ ok: true });
    expect(await (await call("/register", { token, secretHash, sandbox: false })).json())
      .toEqual({ ok: true, skipped: true });
  });

  it("404s an unknown endpoint and 405s a non-POST", async () => {
    expect((await call("/nope", {})).status).toBe(404);
    const get = await fetch(base + "/push", { method: "GET" });
    expect(get.status).toBe(405);
  });
});
