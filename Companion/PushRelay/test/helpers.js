// Test helpers for the push relay: typed request drivers and the APNs stub.

import { SELF, fetchMock } from "cloudflare:test";
import { beforeAll, afterEach } from "vitest";

export const ORIGIN = "https://push.example";

let tokenSeq = 0;

/// A fresh, syntactically valid (lowercase hex, >= 32 chars) device token,
/// unique per call so each test's KV records and rate-limit buckets are distinct.
export function freshToken() {
  tokenSeq += 1;
  return tokenSeq.toString(16).padStart(64, "0");
}

/// A 32-byte hex secret and its sha256 (the registered secretHash), the way the
/// phone derives them.
export async function makeSecret() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const secret = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes)));
  const secretHash = [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
  return { secret, secretHash };
}

export async function post(path, body, headers = {}) {
  const res = await SELF.fetch(ORIGIN + path, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  let json = null;
  try { json = await res.json(); } catch { /* non-JSON body */ }
  return { status: res.status, body: json };
}

/// Arm the Miniflare fetchMock so no real network escapes during a test file.
export function useApnsStub() {
  beforeAll(() => {
    fetchMock.activate();
    fetchMock.disableNetConnect();
  });
  afterEach(() => {
    // Every interceptor an individual test set up must have been consumed, so a
    // test that expects an APNs call but the worker skips it (or vice versa)
    // fails loudly.
    fetchMock.assertNoPendingInterceptors();
  });
}

/// Expect one APNs push for `token` and answer it with `status`/`responseBody`.
/// `sandbox` selects Apple's host, matching the registration.
export function expectApnsPush(token, { sandbox = false, status = 200, responseBody = "" } = {}) {
  const host = sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  fetchMock
    .get(host)
    .intercept({ path: `/3/device/${token}`, method: "POST" })
    .reply(status, responseBody);
}
