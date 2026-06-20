// POST /push/mutable: the Mac wakes the Notification Service Extension with a
// content-free push. Same auth + rate limit as /push, but the aps payload
// carries mutable-content, a generic fallback alert, a per-chat collapse id,
// and NO sound (the NSE adds it). The legacy /push payload is unaffected.

import { describe, it, expect } from "vitest";
import { fetchMock } from "cloudflare:test";
import { post, freshToken, makeSecret, useApnsStub } from "./helpers.js";

useApnsStub();

async function registerDevice({ sandbox = false } = {}) {
  const token = freshToken();
  const { secret, secretHash } = await makeSecret();
  await post("/register", { token, secretHash, sandbox });
  return { token, secret };
}

describe("POST /push/mutable", () => {
  it("sends mutable-content + collapse id + no sound, generic fallback", async () => {
    const { token, secret } = await registerDevice();
    const collapse = "ab12cd34ef56";
    // Require the exact aps shape and collapse header: an unmatched request
    // escapes (net disabled) and fails the test, so this asserts the payload.
    fetchMock
      .get("https://api.push.apple.com")
      .intercept({
        path: `/3/device/${token}`,
        method: "POST",
        headers: { "apns-collapse-id": collapse },
        body: (value) => {
          const aps = JSON.parse(value).aps;
          return aps["mutable-content"] === 1 &&
                 aps.sound === undefined &&
                 aps.alert.title === "iTerm2 Buddy" &&
                 typeof aps.alert.body === "string";
        },
      })
      .reply(200, "");
    const res = await post("/push/mutable", { token, secret, collapse });
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it("forwards an optional nonce as a top-level custom key outside aps", async () => {
    const { token, secret } = await registerDevice();
    fetchMock
      .get("https://api.push.apple.com")
      .intercept({
        path: `/3/device/${token}`,
        method: "POST",
        body: (value) => {
          const obj = JSON.parse(value);
          return obj.n === "deadbeef" && obj.aps["mutable-content"] === 1;
        },
      })
      .reply(200, "");
    const res = await post("/push/mutable", { token, secret, collapse: "abcd", nonce: "deadbeef" });
    expect(res.status).toBe(200);
  });

  it("omits the nonce key when none is supplied (older senders)", async () => {
    const { token, secret } = await registerDevice();
    fetchMock
      .get("https://api.push.apple.com")
      .intercept({
        path: `/3/device/${token}`,
        method: "POST",
        body: (value) => JSON.parse(value).n === undefined,
      })
      .reply(200, "");
    const res = await post("/push/mutable", { token, secret, collapse: "abcd" });
    expect(res.status).toBe(200);
  });

  it("rejects a non-hex nonce", async () => {
    const { token, secret } = await registerDevice();
    const res = await post("/push/mutable", { token, secret, collapse: "abcd", nonce: "NOPE!" });
    expect(res.status).toBe(400);
  });

  it("routes a sandbox registration to Apple's sandbox host", async () => {
    const { token, secret } = await registerDevice({ sandbox: true });
    fetchMock
      .get("https://api.sandbox.push.apple.com")
      .intercept({ path: `/3/device/${token}`, method: "POST" })
      .reply(200, "");
    const res = await post("/push/mutable", { token, secret, collapse: "abcd" });
    expect(res.status).toBe(200);
  });

  it("rejects a missing or non-hex collapse id", async () => {
    const { token, secret } = await registerDevice();
    expect((await post("/push/mutable", { token, secret })).status).toBe(400);
    expect((await post("/push/mutable", { token, secret, collapse: "" })).status).toBe(400);
    expect((await post("/push/mutable", { token, secret, collapse: "NOTHEX!" })).status).toBe(400);
  });

  it("rejects an unknown device token", async () => {
    const res = await post("/push/mutable", {
      token: freshToken(),
      secret: "f".repeat(64),
      collapse: "abcd",
    });
    expect(res.status).toBe(403);
  });

  it("rejects a wrong secret for a known token", async () => {
    const { token } = await registerDevice();
    const wrong = await makeSecret();
    const res = await post("/push/mutable", { token, secret: wrong.secret, collapse: "abcd" });
    expect(res.status).toBe(403);
  });

  it("soft rate-limits per token", async () => {
    const { token, secret } = await registerDevice();
    for (let i = 0; i < 10; i++) {
      fetchMock
        .get("https://api.push.apple.com")
        .intercept({ path: `/3/device/${token}`, method: "POST" })
        .reply(200, "");
      const ok = await post("/push/mutable", { token, secret, collapse: "abcd" });
      expect(ok.status).toBe(200);
    }
    const limited = await post("/push/mutable", { token, secret, collapse: "abcd" });
    expect(limited.status).toBe(429);
  });
});
