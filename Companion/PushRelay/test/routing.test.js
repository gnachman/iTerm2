// Request routing and body handling shared by both endpoints.

import { describe, it, expect } from "vitest";
import { SELF } from "cloudflare:test";
import { ORIGIN, post } from "./helpers.js";

describe("routing", () => {
  it("rejects non-POST methods", async () => {
    const res = await SELF.fetch(ORIGIN + "/register", { method: "GET" });
    expect(res.status).toBe(405);
  });

  it("404s an unknown endpoint", async () => {
    const res = await post("/nope", {});
    expect(res.status).toBe(404);
  });

  it("400s a malformed JSON body", async () => {
    const res = await post("/register", "{ not json");
    expect(res.status).toBe(400);
  });
});
