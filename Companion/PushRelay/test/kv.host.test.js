// SqliteKV must honor the slice of the Workers KV contract worker.js relies on:
// missing => null, JSON round-trip, TTL expiry on read, and prefix listing.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { SqliteKV } from "../host/kv.js";

describe("SqliteKV", () => {
  let clock;
  let kv;

  beforeEach(() => {
    clock = 1_000_000; // fixed base so TTL math is deterministic
    kv = new SqliteKV(":memory:", { now: () => clock });
  });
  afterEach(() => kv.close());

  it("returns null for a missing key (worker checks !record)", async () => {
    expect(await kv.get("device:nope", "json")).toBe(null);
  });

  it("round-trips a JSON value", async () => {
    await kv.put("device:abc", JSON.stringify({ secretHash: "aa", sandbox: true, registeredAt: clock }));
    expect(await kv.get("device:abc", "json")).toEqual({ secretHash: "aa", sandbox: true, registeredAt: clock });
  });

  it("returns a raw string when no type is given (rate-limit buckets)", async () => {
    await kv.put("rl:tok:42", "3");
    expect(await kv.get("rl:tok:42")).toBe("3");
  });

  it("expires a value once its TTL elapses (read-time)", async () => {
    await kv.put("rl:tok:1", "1", { expirationTtl: 120 }); // expires at clock + 120s
    clock += 119_000;
    expect(await kv.get("rl:tok:1")).toBe("1"); // still inside the window
    clock += 2_000; // now past clock + 120s
    expect(await kv.get("rl:tok:1")).toBe(null);
  });

  it("treats a value with no TTL as permanent", async () => {
    await kv.put("device:forever", "x");
    clock += 10 * 365 * 24 * 3600 * 1000;
    expect(await kv.get("device:forever")).toBe("x");
  });

  it("overwrites on re-put (register's rewrite path)", async () => {
    await kv.put("device:x", JSON.stringify({ secretHash: "old" }));
    await kv.put("device:x", JSON.stringify({ secretHash: "new" }));
    expect(await kv.get("device:x", "json")).toEqual({ secretHash: "new" });
  });

  it("lists by prefix with expiration in unix seconds, sorted, live only", async () => {
    await kv.put("device:b", "1", { expirationTtl: 3600 });
    await kv.put("device:a", "1", { expirationTtl: 3600 });
    await kv.put("other:z", "1");
    await kv.put("device:dead", "1", { expirationTtl: 1 }); // expires quickly

    clock += 2_000; // kill device:dead, keep the 1h ones
    const { keys } = await kv.list({ prefix: "device:" });
    expect(keys.map((k) => k.name)).toEqual(["device:a", "device:b"]); // sorted, no other:z, no dead
    const nowSec = Math.floor(clock / 1000);
    expect(keys[0].expiration).toBeGreaterThan(nowSec + 3600 - 5);
    expect(keys[0].expiration).toBeLessThan(nowSec + 3600 + 5);
  });

  it("sweepExpired bulk-deletes only past-TTL rows", async () => {
    await kv.put("a", "1", { expirationTtl: 10 });
    await kv.put("b", "1", { expirationTtl: 10_000 });
    await kv.put("c", "1"); // no TTL
    clock += 11_000;
    expect(kv.sweepExpired()).toBe(1); // only "a" was past due
    expect(await kv.get("b")).toBe("1");
    expect(await kv.get("c")).toBe("1");
  });
});
