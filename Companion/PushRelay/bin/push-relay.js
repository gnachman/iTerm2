#!/usr/bin/env node
// Production entrypoint for the self-hosted push relay. Reads configuration
// from the environment (systemd EnvironmentFile drives it), starts the HTTP
// host bound to localhost behind a TLS-terminating reverse proxy, and shuts
// down gracefully on SIGTERM/SIGINT.
//
// This is the off-Cloudflare deployment of src/worker.js: same request logic,
// but KV is SQLite and APNs delivery is HTTP/2 (see host/). The scarce Workers
// resource that forced the move — the free-plan daily KV write cap — does not
// exist here.

import { readFileSync } from "node:fs";
import { createPushRelay } from "../host/server.js";

const HOST = process.env.PUSH_HOST || "127.0.0.1";
const PORT = Number(process.env.PUSH_PORT || process.env.PORT || 8790);
const DB_PATH = process.env.PUSH_DB || "push-relay.db";

// The APNs signing key may be supplied inline (APNS_P8, BEGIN/END lines and
// all) or, more systemd-friendly, as a file path (APNS_P8_FILE) so the multi-
// line PEM never has to live in an EnvironmentFile.
if (!process.env.APNS_P8 && process.env.APNS_P8_FILE) {
  try {
    process.env.APNS_P8 = readFileSync(process.env.APNS_P8_FILE, "utf8");
  } catch (err) {
    console.error(`push-relay: cannot read APNS_P8_FILE (${process.env.APNS_P8_FILE}): ${err.message}`);
    process.exit(1);
  }
}

// Fail fast on missing signing material rather than 500-ing every push at
// runtime (the JWT signer would throw on an undefined key).
const missing = ["APNS_TEAM_ID", "APNS_KEY_ID", "APNS_P8", "APNS_TOPIC"]
  .filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`push-relay: missing required config: ${missing.join(", ")}`);
  process.exit(1);
}

function numEnv(name) {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 ? v : undefined;
}

const relay = createPushRelay({
  dbPath: DB_PATH,
  env: process.env,
  // Abuse cap on /register by client IP (the reverse proxy must forward it as
  // CF-Connecting-IP or the worker falls back to "unknown"). Off unless set.
  registerLimit: numEnv("PUSH_REGISTER_LIMIT"),
  registerWindowSeconds: numEnv("PUSH_REGISTER_WINDOW_SECONDS") || 60,
});

// Last-resort net: a stray throw must not take push delivery down for everyone.
// Log and keep serving; bound the rate so a wedged process still restarts.
const EXC_WINDOW_MS = 60_000;
const EXC_LIMIT = 25;
const excTimes = [];
function onProcessException(kind, err) {
  console.error(`push-relay: ${kind} (continuing):`, err?.message ?? err);
  const now = Date.now();
  excTimes.push(now);
  while (excTimes.length && now - excTimes[0] > EXC_WINDOW_MS) excTimes.shift();
  if (excTimes.length > EXC_LIMIT) {
    console.error(`push-relay: ${excTimes.length} exceptions within ${EXC_WINDOW_MS}ms — exiting for a clean restart`);
    process.exit(1);
  }
}
process.on("unhandledRejection", (reason) => onProcessException("unhandledRejection", reason));
process.on("uncaughtException", (err) => onProcessException("uncaughtException", err));

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`push-relay: ${signal} received, shutting down`);
  try {
    await relay.close();
  } finally {
    process.exit(0);
  }
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

relay.listen(PORT, HOST).then(() => {
  const { port } = relay.address();
  console.log(`push-relay: listening on ${HOST}:${port} (db=${DB_PATH}, topic=${process.env.APNS_TOPIC})`);
}).catch((err) => {
  console.error("push-relay: failed to start:", err.message);
  process.exit(1);
});
