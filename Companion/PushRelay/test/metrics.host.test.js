// The /metrics endpoint: loopback-only, and its counters reflect exactly the
// decisions worker.js makes — register write vs. skip, push delivered vs.
// bad-secret vs. unknown-token — plus the live device gauge.

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { createPushRelay } from "../host/server.js";

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

// Pull `pushrelay_<name> <value>` out of the exposition text.
function metric(text, name) {
  const m = text.match(new RegExp(`^pushrelay_${name} (\\d+)$`, "m"));
  return m ? Number(m[1]) : undefined;
}

describe("push relay /metrics", () => {
  let relay, base, text;

  beforeAll(async () => {
    relay = createPushRelay({
      dbPath: ":memory:",
      apnsFetch: Object.assign(async () => ({ ok: true, status: 200, text: async () => "" }), { close() {} }),
      env: { APNS_TOPIC: "com.x", APNS_TEAM_ID: "T", APNS_KEY_ID: "K", APNS_P8: TEST_APNS_P8, REGISTRATION_TTL_SECONDS: "3600" },
    });
    await relay.listen(0, "127.0.0.1");
    base = `http://127.0.0.1:${relay.address().port}`;
    const post = (p, b) => fetch(base + p, { method: "POST", body: JSON.stringify(b) });

    const A = await makeCreds();
    const A2 = await makeCreds();
    const tokenA = tok(1);
    await post("/register", { token: tokenA, secretHash: A.secretHash, sandbox: false });   // written
    await post("/register", { token: tokenA, secretHash: A.secretHash, sandbox: false });   // skipped
    await post("/register", { token: tokenA, secretHash: A2.secretHash, sandbox: false });  // written (rotation)
    await post("/register", { token: "nothex", secretHash: A.secretHash });                 // rejected (400)
    await post("/push", { token: tokenA, secret: (await makeCreds()).secret, title: "x", body: "y" }); // bad secret
    await post("/push", { token: tok(999), secret: A.secret, title: "x", body: "y" });      // unknown token
    await post("/push", { token: tokenA, secret: A2.secret, title: "x", body: "y" });       // delivered

    text = await (await fetch(base + "/metrics")).text();
  });
  afterAll(async () => { await relay.close(); });

  it("counts register write / skip / reject", () => {
    expect(metric(text, "register_total")).toBe(4);
    expect(metric(text, "register_written_total")).toBe(2);
    expect(metric(text, "register_skipped_total")).toBe(1);
    expect(metric(text, "register_rejected_total")).toBe(1);
  });

  it("counts push delivered / bad-secret / unknown-token", () => {
    expect(metric(text, "push_total")).toBe(3);
    expect(metric(text, "push_delivered_total")).toBe(1);
    expect(metric(text, "push_bad_secret_total")).toBe(1);
    expect(metric(text, "push_unknown_token_total")).toBe(1);
  });

  it("reports total requests and the live device gauge", () => {
    expect(metric(text, "http_requests_total")).toBe(7);
    expect(metric(text, "devices")).toBe(1); // only tokenA is registered
  });

  it("pre-registers every counter so lines exist from boot", () => {
    expect(text).toMatch(/^pushrelay_push_apns_error_total 0$/m);
    expect(text).toMatch(/# TYPE pushrelay_devices gauge/);
  });

  it("blocks scrapes carrying proxy headers (not a direct loopback peer)", async () => {
    const res = await fetch(base + "/metrics", { headers: { "x-forwarded-for": "1.2.3.4" } });
    expect(res.status).toBe(403);
  });
});
