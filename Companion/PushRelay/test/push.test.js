// POST /push: the Mac forwards a notification, authenticated by the per-device
// secret (only it holds, over the Noise channel). The relay verifies
// sha256(secret) against the registration, soft rate-limits per token, signs an
// APNs provider JWT, and forwards to Apple. Apple is stubbed (fetchMock), so
// these assert the relay's contract, not Apple's acceptance.

import { describe, it, expect } from "vitest";
import { freshToken, makeSecret, post, useApnsStub, expectApnsPush } from "./helpers.js";

useApnsStub();

async function registerDevice({ sandbox = false } = {}) {
  const token = freshToken();
  const { secret, secretHash } = await makeSecret();
  await post("/register", { token, secretHash, sandbox });
  return { token, secret };
}

describe("POST /push", () => {
  it("forwards to APNs for a valid secret", async () => {
    const { token, secret } = await registerDevice();
    expectApnsPush(token, { status: 200 });

    const res = await post("/push", { token, secret, title: "Hi", body: "There" });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ ok: true });
  });

  it("routes a sandbox registration to Apple's sandbox host", async () => {
    const { token, secret } = await registerDevice({ sandbox: true });
    expectApnsPush(token, { sandbox: true, status: 200 });

    const res = await post("/push", { token, secret, title: "Hi", body: "There" });
    expect(res.status).toBe(200);
  });

  it("rejects an unknown device token", async () => {
    const res = await post("/push", {
      token: freshToken(), secret: (await makeSecret()).secret, title: "a", body: "b",
    });
    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/unknown device token/);
  });

  it("rejects a wrong secret for a known token", async () => {
    const { token } = await registerDevice();
    const wrong = await makeSecret();
    const res = await post("/push", { token, secret: wrong.secret, title: "a", body: "b" });
    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/bad secret/);
  });

  it("requires title and body strings", async () => {
    const { token, secret } = await registerDevice();
    const res = await post("/push", { token, secret });
    expect(res.status).toBe(400);
  });

  it("rejects a malformed secret format", async () => {
    const { token } = await registerDevice();
    const res = await post("/push", { token, secret: "short", title: "a", body: "b" });
    expect(res.status).toBe(400);
  });

  it("surfaces an APNs failure as 502 with detail", async () => {
    const { token, secret } = await registerDevice();
    expectApnsPush(token, { status: 400, responseBody: "BadDeviceToken" });

    const res = await post("/push", { token, secret, title: "a", body: "b" });
    expect(res.status).toBe(502);
    expect(res.body.error).toMatch(/APNs 400/);
    expect(res.body.error).toMatch(/BadDeviceToken/);
  });

  it("soft rate-limits per token: the 11th push in a window is refused", async () => {
    const { token, secret } = await registerDevice();
    // Ten allowed pushes; arm one APNs interceptor per allowed push.
    for (let i = 0; i < 10; i++) {
      expectApnsPush(token, { status: 200 });
      const ok = await post("/push", { token, secret, title: "a", body: String(i) });
      expect(ok.status).toBe(200);
    }
    // The 11th must be refused BEFORE any APNs call (no interceptor armed; if the
    // worker tried to reach Apple, disableNetConnect would throw instead of 429).
    const limited = await post("/push", { token, secret, title: "a", body: "11" });
    expect(limited.status).toBe(429);
    expect(limited.body.error).toMatch(/rate limited/);
  });
});
