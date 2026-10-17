// Peer replication between self-hosted push relay instances.
//
// The apps know several relay hostnames (CompanionPushRelay.swift). The phone
// registers with ONE of them, and the Mac tries them in order when pushing, so
// every instance needs every registration. Each instance therefore passes each
// /register it handles on to its peer, which applies it like a registration of
// its own. There is no database sync:
//
//   - Outbox first: after a /register succeeds, and before the phone gets its
//     reply, the stored record (including its registeredAt) is written to a
//     SQLite outbox table. One row per token, so it is bounded by the device
//     count. A skipped (unchanged) registration is queued too unless the peer
//     is known to hold that exact record (it acknowledged it, or sent it to us,
//     since this process started), so a peer that missed a record gets it the
//     next time the phone connects, while a reconnect storm costs nothing once
//     the peer is in sync.
//   - Then send: a single drain loop POSTs queued records to the peer's
//     /peer/register one at a time, deleting each row only once the peer
//     accepts it (a 2xx carrying PEER_RESPONSE_HEADER and {"ok":true}; any
//     other 2xx, e.g. from a misrouted URL, is a failure). It picks the next row
//     by query after every send: live registrations before backfill rows, so a
//     re-pair doesn't wait behind a startup backlog. A row that fails is retried
//     later with backoff, so it moves behind the others. A pass gives up after a
//     few failures in a row that suggest the peer is down or misconfigured; a
//     row the peer is up and refusing doesn't count toward that. A crash
//     mid-send leaves the row queued.
//   - Startup (and SIGUSR2; see bin/push-relay.js): every live registration is
//     queued at low priority, which seeds a new or rebuilt peer and repairs
//     anything missed while both relays had an outage. That includes records
//     this relay received from the peer, so each restart echoes those back
//     once; the peer doesn't rewrite a record whose contents match what it has
//     and whose stamp is within STAMP_MARGIN_MS of its own.
//   - Ordering: the receiver keeps whichever record has the later registeredAt,
//     compared as stamped, so this relies on NTP keeping the relays' clocks
//     within milliseconds. (Converting stamps by the sender's clock at send time
//     would count each send's network delay, which through Cloudflare can be
//     seconds, as clock difference, and reorder a re-pair during exactly the
//     degraded conditions failover is for.) A phone registration is also
//     stamped after any record the relay already held (stampingKV). A peer
//     whose clock is off by more than MAX_SKEW_MS is refused (409, so its rows
//     stay queued and the monitor sees it), as is a stamp more than
//     FUTURE_SLACK_MS in our future. The clock difference is estimated
//     NTP-style from each round trip and exported as a gauge.
//   - Rebuilt peer: each relay's database has a random instance id, returned on
//     every /peer/* response. When it changes, the peer lost its data, so this
//     relay forgets what it thought the peer held and queues everything again.
//     Each process also has a boot id; when that changes (any peer restart,
//     including one restored from a backup, which keeps its instance id), this
//     relay also forgets what it thought the peer held and queues everything
//     again (at low priority, and the peer ignores what it already has). An
//     idle relay sends /peer/hello once a minute so either is noticed even when
//     there's nothing to forward. Responses also carry the peer's clock, for
//     the skew gauge.
//
// Auth: a shared secret in the Authorization header. Both instances already
// hold the APNs signing key, so trusting each other's registrations does not
// widen what either can do.

import { createHash, randomUUID, timingSafeEqual } from "node:crypto";

// Retry the outbox on this cadence.
const DEFAULT_RETRY_INTERVAL_MS = 60 * 1000;
// Give up on a single send after this long; the outbox retries it.
const DEFAULT_SEND_TIMEOUT_MS = 10 * 1000;
// A drain pass stops after this many sends in a row that the peer didn't
// answer (it's evidently down)...
const MAX_FAILURES_PER_PASS = 3;
// ...or this many in a row that it answered with its own 5xx (its database is
// failing). Higher, so a few rows the peer can't handle don't stop the pass
// before it reaches the rest.
const MAX_PEER_ERRORS_PER_PASS = 20;
// A row that failed waits backoffBase * 2^(attempts-1), up to this, before it
// is tried again (backoffBase defaults to the retry interval).
const MAX_BACKOFF_MS = 15 * 60 * 1000;
// Remember the record the peer holds for up to this many devices.
const MAX_ACKED = 100_000;
// Log when the peer's clock differs from ours by more than this.
const SKEW_WARN_MS = 5 * 1000;
// Refuse records from a peer whose clock differs from ours by more than this.
const MAX_SKEW_MS = 60 * 60 * 1000;
// A received stamp later than our clock plus this is refused (409, retryable):
// the sender's clock is fast, or stepped back since it stamped the record.
const FUTURE_SLACK_MS = 60 * 1000;
// A phone registration is stamped at least this much after the record it
// replaces, so it sorts after a peer record stamped by a clock a little ahead
// of ours. A burst of changed registrations faster than one per second (a
// client bug, or abuse by someone who knows the token) ratchets stamps ahead
// of the clock by this much each; past FUTURE_SLACK_MS the peer answers 409 and
// the rows wait, then go through once the clock catches up. That only delays
// redundancy. An echo of a record with the same contents and a stamp within
// this margin is not rewritten.
const STAMP_MARGIN_MS = 1000;
// After a drain pass gives up (peer down), don't start another for this long,
// so a burst of registrations doesn't turn into a burst of failing sends.
const GIVE_UP_COOLDOWN_MS = 5 * 1000;
// The shortest TTL a peer may ask for (the worker's minimum). The longest is
// our own.
const MIN_TTL_SECONDS = 60;
// Peering is refused with a shorter secret: /peer/register is public.
export const MIN_PEER_SECRET_LENGTH = 32;
// Set on every /peer/register response, so a sender can tell the receiver's own
// 400 ("this record is malformed") from one a proxy, WAF, or misconfigured URL
// produced on the way.
export const PEER_RESPONSE_HEADER = "x-push-peer";
// Also on every /peer/* response: the responder's database instance id, its
// process boot id, and its clock (unix ms).
export const PEER_INSTANCE_HEADER = "x-push-peer-instance";
export const PEER_BOOT_HEADER = "x-push-peer-boot";
export const PEER_TIME_HEADER = "x-push-peer-time";
// Outbox priorities.
const LIVE = 1;
const BACKFILL = 0;

const isHex = (s, minLen, maxLen) =>
  typeof s === "string" && s.length >= minLen && s.length <= maxLen && /^[0-9a-f]+$/.test(s);

const sha256 = (s) => createHash("sha256").update(s).digest();

// True if `incoming` should replace `existing`. Later registeredAt wins. An
// exact tie with different contents is broken by comparing the contents, so two
// relays that each hold one of the pair still converge on the same record.
export function isNewer(incoming, existing) {
  if (!existing) return true;
  if (incoming.registeredAt !== existing.registeredAt) {
    return incoming.registeredAt > existing.registeredAt;
  }
  const key = (r) => `${r.secretHash}:${r.sandbox ? 1 : 0}`;
  return key(incoming) > key(existing);
}

// The KV the worker writes through when a peer is configured. A device record
// the worker writes (only /register does) gets a registeredAt later than the
// one already stored, in the same transaction as the write. Otherwise a record
// received from a peer whose clock runs slightly fast would sort after a newer
// phone registration here, and a later resend of it would undo a re-pair.
// Records received from the peer bypass this (they go to `kv` directly).
export function stampingKV(kv) {
  const putDevice = kv.db.transaction((key, value, options) => {
    const prior = kv.getSync(key);
    if (prior != null) {
      const before = JSON.parse(prior);
      const next = JSON.parse(value);
      if (Number.isFinite(before.registeredAt) && Number.isFinite(next.registeredAt) &&
          next.registeredAt < before.registeredAt + STAMP_MARGIN_MS) {
        next.registeredAt = before.registeredAt + STAMP_MARGIN_MS;
        value = JSON.stringify(next);
      }
    }
    kv.putSync(key, value, options);
  });
  return {
    get: (...args) => kv.get(...args),
    delete: (...args) => kv.delete(...args),
    list: (...args) => kv.list(...args),
    // eslint-disable-next-line require-await -- matches the KV interface
    async put(key, value, options) {
      if (key.startsWith("device:")) putDevice(key, value, options);
      else kv.putSync(key, value, options);
    },
  };
}

export function createPeerSync({
  kv,
  metrics,
  peerUrl,
  peerSecret,
  ttlSeconds,
  fetchImpl = globalThis.fetch,
  now = () => Date.now(),
  retryIntervalMs = DEFAULT_RETRY_INTERVAL_MS,
  retryBackoffMs = retryIntervalMs,
  sendTimeoutMs = DEFAULT_SEND_TIMEOUT_MS,
  giveUpCooldownMs = GIVE_UP_COOLDOWN_MS,
  log = console,
}) {
  if (typeof peerSecret !== "string" || peerSecret.length < MIN_PEER_SECRET_LENGTH) {
    throw new Error(`the peer secret must be at least ${MIN_PEER_SECRET_LENGTH} characters`);
  }
  const endpoint = new URL("/peer/register", peerUrl).toString();
  const helloEndpoint = new URL("/peer/hello", peerUrl).toString();
  const expectedAuth = sha256(`Bearer ${peerSecret}`);

  // This database's instance id, created with it.
  kv.db.exec("CREATE TABLE IF NOT EXISTS peer_meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)");
  kv.db.prepare("INSERT OR IGNORE INTO peer_meta (k, v) VALUES ('instance', ?)").run(randomUUID());
  const instanceId = kv.db.prepare("SELECT v FROM peer_meta WHERE k = 'instance'").get().v;
  const bootId = randomUUID();

  kv.db.exec(
    `CREATE TABLE IF NOT EXISTS peer_outbox (
       token       TEXT PRIMARY KEY,
       record      TEXT NOT NULL,              -- the record JSON when queued
       priority    INTEGER NOT NULL,           -- LIVE or BACKFILL
       attempts    INTEGER NOT NULL DEFAULT 0, -- failed sends so far
       next_try_at INTEGER NOT NULL DEFAULT 0  -- unix ms; not before this
     );
     DROP INDEX IF EXISTS peer_outbox_next;
     CREATE INDEX IF NOT EXISTS peer_outbox_pick ON peer_outbox(priority DESC, next_try_at, token);`
  );
  // A live registration replaces any queued row for the token and is due now.
  const enqueueStmt = kv.db.prepare(
    `INSERT INTO peer_outbox (token, record, priority, attempts, next_try_at)
     VALUES (?, ?, ${LIVE}, 0, 0)
     ON CONFLICT(token) DO UPDATE SET
       record = excluded.record, priority = ${LIVE}, attempts = 0, next_try_at = 0`);
  // The first few due rows; the caller skips any that already failed this pass.
  // peer_outbox_pick covers the whole ORDER BY, so this is an index walk, not a
  // sort of every due row (which made a large backfill quadratic).
  const nextStmt = kv.db.prepare(
    `SELECT token, record, attempts FROM peer_outbox WHERE next_try_at <= ?
     ORDER BY priority DESC, next_try_at, token LIMIT ?`);
  // Delete or defer only the row we read, so a newer record queued while the
  // send was in flight is left due for the next pick.
  const dequeueStmt = kv.db.prepare("DELETE FROM peer_outbox WHERE token = ? AND record = ?");
  const deferStmt = kv.db.prepare(
    `UPDATE peer_outbox SET attempts = attempts + 1, next_try_at = ?
     WHERE token = ? AND record = ?`);
  const dropStmt = kv.db.prepare("DELETE FROM peer_outbox WHERE token = ?");
  const countStmt = kv.db.prepare("SELECT COUNT(*) AS n FROM peer_outbox");
  const dueStmt = kv.db.prepare("SELECT 1 FROM peer_outbox WHERE next_try_at <= ? LIMIT 1");
  const resetBackoffStmt = kv.db.prepare("UPDATE peer_outbox SET next_try_at = 0 WHERE next_try_at > 0");
  const backfillStmt = kv.db.prepare(
    `INSERT OR IGNORE INTO peer_outbox (token, record, priority)
     SELECT substr(key, 8), value, ${BACKFILL} FROM kv
     WHERE key GLOB 'device:*' AND (expires_at IS NULL OR expires_at > ?)`);

  let lastSkewMs = 0;
  // Why the last send failed (for the per-pass log), and whether the peer
  // looked down (a pass gave up, or a hello failed) since it last answered.
  let lastFailure = "";
  let peerDown = false;
  // When the peer last answered an authenticated request (unix ms; 0 = never).
  let lastOkAt = 0;
  let timer = null;
  let draining = null;
  let drainAgain = false;
  // token -> the record JSON the peer is known to hold (in memory: after a
  // restart, the first registration per device is forwarded again).
  const acked = new Map();
  // The peer's instance and boot ids, from its last response.
  let peerInstance = null;
  let peerBoot = null;

  // A changed id means the peer's database was replaced, so it may hold none of
  // what `acked` claims: forget that and queue everything for it again.
  function notePeerInstance(id) {
    if (!id) return;
    if (peerInstance && id !== peerInstance) {
      log.error(`push-relay: peer database changed (${peerInstance} -> ${id}); resending all registrations`);
      metrics.inc("peer_rebuilt_total");
      acked.clear();
      backfillStmt.run(now());
      drainAgain = true;
    }
    peerInstance = id;
  }

  // Everything an authenticated /peer/* response tells us about the peer.
  // `sentAt`/`receivedAt` bracket the request, for an NTP-style clock estimate
  // (error at most half the round trip).
  // Returns false if the "peer" is this relay itself.
  function notePeerResponse(res, sentAt, receivedAt) {
    if (res.headers.get(PEER_RESPONSE_HEADER) !== "1" || !res.headers.get(PEER_INSTANCE_HEADER)) return true;
    if (res.headers.get(PEER_INSTANCE_HEADER) === instanceId) {
      // PUSH_PEER_URL names this relay (e.g. the example value pasted onto the
      // instance it names). Everything would look healthy while nothing
      // reaches the real peer, so fail loudly: rows stay queued and the
      // liveness gauge goes stale.
      log.error("push-relay: PUSH_PEER_URL points at this relay itself; peer replication is not happening");
      metrics.inc("peer_self_total");
      return false;
    }
    lastOkAt = receivedAt;
    if (peerDown) {
      // The peer is back: rows backing off (up to MAX_BACKOFF_MS) go now
      // rather than waiting out their backoff, so a secret the peer missed
      // while it was down reaches it within a pass.
      peerDown = false;
      resetBackoffStmt.run();
      drainAgain = true;
    }
    notePeerInstance(res.headers.get(PEER_INSTANCE_HEADER));
    const boot = res.headers.get(PEER_BOOT_HEADER);
    if (boot) {
      // A restarted peer may have come back with older data (a restored
      // backup keeps its instance id), so stop assuming it holds anything and
      // queue everything for it again.
      if (peerBoot && boot !== peerBoot) {
        acked.clear();
        backfillStmt.run(now());
        drainAgain = true;
      }
      peerBoot = boot;
    }
    const peerTime = Number(res.headers.get(PEER_TIME_HEADER));
    if (Number.isFinite(peerTime) && peerTime > 0) {
      lastSkewMs = Math.round(peerTime - (sentAt + receivedAt) / 2);
      if (Math.abs(lastSkewMs) > SKEW_WARN_MS) {
        log.error(`push-relay: peer clock differs from ours by about ${lastSkewMs}ms`);
      }
    }
    return true;
  }

  // Headers for a /peer/* response. Every one carries the marker (so a sender
  // can tell this code's 400 from a proxy's); only an authenticated caller
  // learns our instance and boot ids and clock.
  const responseHeaders = (authHeader) => isAuthorized(authHeader)
    ? {
      [PEER_RESPONSE_HEADER]: "1",
      [PEER_INSTANCE_HEADER]: instanceId,
      [PEER_BOOT_HEADER]: bootId,
      [PEER_TIME_HEADER]: String(now()),
    }
    : { [PEER_RESPONSE_HEADER]: "1" };

  function noteAcked(token, json) {
    acked.delete(token); // re-insert so the Map's order stays least-recent-first
    acked.set(token, json);
    if (acked.size > MAX_ACKED) acked.delete(acked.keys().next().value);
  }

  // POST one record to the peer. Resolves to:
  //   "ok"       the peer holds it (or something newer);
  //   "expired"  the peer accepted the request but dropped the record as already
  //              expired by its TTL, so it holds nothing (don't count it acked);
  //   "rejected" the peer's own /peer/register refused this record as malformed
  //              (a 400 carrying PEER_RESPONSE_HEADER). Retrying can't help;
  //   "refused"  the peer is up but won't take this record yet (its 409 for a
  //              stamp in its future): retry it later, but it says nothing
  //              about the peer being down;
  //   "erred"    the peer answered with its own 5xx (its database is failing):
  //              counts toward giving up, at the higher MAX_PEER_ERRORS_PER_PASS,
  //              but the peer is up;
  //   "failed"   anything else (unreachable, a 2xx that isn't the peer's own
  //              answer, 5xx from the path, wrong secret, clock too far off,
  //              peering not configured there): the peer didn't answer, or
  //              its configuration is the problem, so it counts toward giving
  //              up.
  // A failure's reason goes in lastFailure; flushOnce logs a summary per pass
  // rather than a line per row.
  async function send(token, record) {
    try {
      const sentAt = now();
      const res = await fetchImpl(endpoint, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${peerSecret}`,
        },
        body: JSON.stringify({ token, ...record, ttlSeconds, sentAt }),
        redirect: "error", // a redirect is never legitimate here
        signal: AbortSignal.timeout(sendTimeoutMs),
      });
      // Always consume the body so the connection can be reused.
      const text = await res.text().catch(() => "");
      if (!notePeerResponse(res, sentAt, now())) {
        lastFailure = "PUSH_PEER_URL points at this relay";
        metrics.inc("peer_forward_failed_total");
        return "failed";
      }
      const fromPeer = res.headers.get(PEER_RESPONSE_HEADER) === "1";
      let body = null;
      try { body = JSON.parse(text); } catch { /* not the peer's answer */ }
      if (res.ok && fromPeer && body?.ok === true) {
        metrics.inc("peer_forward_ok_total");
        return body.expired === true ? "expired" : "ok";
      }
      if (fromPeer && res.status === 400) {
        log.error(`push-relay: peer rejected a record, dropping it: ${text.slice(0, 200)}`);
        metrics.inc("peer_forward_dropped_total");
        return "rejected";
      }
      lastFailure = `HTTP ${res.status}: ${text.slice(0, 200)}`;
      metrics.inc("peer_forward_failed_total");
      if (fromPeer && res.status === 409 && body?.error === "registeredAt is in the future") {
        return "refused";
      }
      if (fromPeer && res.status >= 500) return "erred";
      return "failed";
    } catch (e) {
      lastFailure = String(e?.message || e);
    }
    metrics.inc("peer_forward_failed_total");
    return "failed";
  }

  // Durably queue the stored record for `token`. Call this BEFORE acknowledging
  // the registration, then flush(). With `unlessAcked`, skips the write when the
  // peer is known to hold exactly this record. Returns whether it queued.
  async function enqueue(token, { unlessAcked = false } = {}) {
    const record = await kv.get(`device:${token}`, "json");
    if (!record) return false;
    const json = JSON.stringify(record);
    if (unlessAcked && acked.get(token) === json) return false;
    enqueueStmt.run(token, json);
    return true;
  }

  const backoffMs = (attempts) => Math.min(retryBackoffMs * 2 ** (attempts - 1), MAX_BACKOFF_MS);

  // One pass over the due rows, highest priority first, re-querying after each
  // send so rows queued meanwhile are considered. Sends the CURRENT record for
  // each token (which may be newer than the one queued). Returns false if it
  // gave up because the peer looks down.
  async function flushOnce() {
    let failures = 0;      // consecutive "failed" (unanswered)
    let peerErrors = 0;    // consecutive "erred" (the peer's own 5xx)
    const failedThisPass = new Set(); // never retried within the same pass
    const summarize = (gaveUp) => {
      if (failedThisPass.size) {
        log.error(`push-relay: ${failedThisPass.size} send(s) to the peer failed this pass` +
          `${gaveUp ? " (giving up for now)" : ""}; last: ${lastFailure}`);
      }
    };
    for (;;) {
      const row = nextStmt.all(now(), failedThisPass.size + 1).find((r) => !failedThisPass.has(r.token));
      if (!row) {
        summarize(false);
        return true;
      }
      const record = await kv.get(`device:${row.token}`, "json");
      if (!record) {
        // Expired since it was queued; nothing left to send.
        dropStmt.run(row.token);
        continue;
      }
      const result = await send(row.token, record);
      if (result === "failed" || result === "erred" || result === "refused") {
        failedThisPass.add(row.token);
        deferStmt.run(now() + backoffMs(row.attempts + 1), row.token, row.record);
        if (result === "failed" && ++failures >= MAX_FAILURES_PER_PASS) {
          // The peer didn't answer: when it does again, retry everything
          // that backed off meanwhile.
          summarize(true);
          peerDown = true;
          return false;
        }
        if (result === "erred" && ++peerErrors >= MAX_PEER_ERRORS_PER_PASS) {
          // It answered, so it isn't "down"; just stop hammering it.
          summarize(true);
          return false;
        }
        continue;
      }
      failures = 0;
      peerErrors = 0;
      dequeueStmt.run(row.token, row.record);
      if (result === "ok") noteAcked(row.token, JSON.stringify(record));
    }
  }

  // Drain the outbox. There is only ever one drain running, which bounds the
  // load on the peer; a call while one runs makes it do another pass when it
  // finishes (unless it gave up), so a newly queued row isn't left for the
  // retry timer.
  //
  // After a pass gives up, a new one waits out GIVE_UP_COOLDOWN_MS (one is
  // scheduled for then), so a registration storm against a dead peer costs a
  // few sends every few seconds rather than a few per registration.
  let gaveUpAt = 0;
  let cooldownTimer = null;
  function flush() {
    if (draining) {
      drainAgain = true;
      return draining;
    }
    const wait = gaveUpAt + giveUpCooldownMs - now();
    if (wait > 0) {
      scheduleAfterCooldown(wait);
      return Promise.resolve();
    }
    draining = (async () => {
      let completed;
      do {
        drainAgain = false;
        completed = await flushOnce();
      } while (drainAgain && completed);
      if (!completed) {
        gaveUpAt = now();
        // A flush was asked for while the pass was giving up (e.g. a new
        // registration): honor it after the cooldown, not the next tick.
        if (drainAgain) scheduleAfterCooldown(giveUpCooldownMs);
      }
    })().finally(() => { draining = null; });
    return draining;
  }

  function scheduleAfterCooldown(wait) {
    if (cooldownTimer) return;
    cooldownTimer = setTimeout(() => {
      cooldownTimer = null;
      flush().catch(() => {});
    }, wait);
    cooldownTimer.unref?.();
  }

  function isAuthorized(header) {
    if (typeof header !== "string") return false;
    return timingSafeEqual(sha256(header), expectedAuth);
  }

  // Apply a record the peer forwarded. Returns { status, body }.
  async function receive(authHeader, bodyText) {
    if (!isAuthorized(authHeader)) {
      metrics.inc("peer_rejected_total");
      return { status: 403, body: { error: "bad peer secret" } };
    }
    let payload;
    try {
      payload = JSON.parse(bodyText);
    } catch {
      metrics.inc("peer_rejected_total");
      return { status: 400, body: { error: "bad json" } };
    }
    const { token, secretHash, sandbox, registeredAt, sentAt, ttlSeconds: senderTtl } = payload || {};
    if (!isHex(token, 32, 256) || !isHex(secretHash, 64, 64) ||
        !Number.isFinite(registeredAt) || typeof sandbox !== "boolean") {
      metrics.inc("peer_rejected_total");
      return { status: 400, body: { error: "bad record" } };
    }
    metrics.inc("peer_received_total");

    // Stamps are compared as sent (see the header). sentAt only screens out a
    // peer whose clock is grossly wrong; it includes the request's network
    // delay, so it's no basis for converting the stamp.
    const t = now();
    const stamp = registeredAt;
    if (Number.isFinite(sentAt) && Math.abs(sentAt - t) > MAX_SKEW_MS) {
      log.error(`push-relay: refusing peer record: peer clock differs from ours by ~${sentAt - t}ms`);
      metrics.inc("peer_rejected_total");
      return { status: 409, body: { error: "clock skew too large" } };
    }
    // In our future: the sender's clock is fast or stepped back since it
    // stamped this. Transient, so 409 (the sender keeps the row and retries)
    // rather than 400 (which would drop it).
    if (stamp > t + FUTURE_SLACK_MS) {
      metrics.inc("peer_rejected_total");
      return { status: 409, body: { error: "registeredAt is in the future" } };
    }

    // Keep the expiry the originating relay gave it (its stamp plus its TTL,
    // but no longer than ours), rather than restarting the TTL here.
    const ttl = Number.isFinite(senderTtl) && senderTtl >= MIN_TTL_SECONDS
      ? Math.min(senderTtl, ttlSeconds)
      : ttlSeconds;
    const remainingSeconds = (Math.min(stamp, t) + ttl * 1000 - t) / 1000;
    if (remainingSeconds <= 0) {
      metrics.inc("peer_ignored_total");
      return { status: 200, body: { ok: true, applied: false, expired: true } };
    }
    const json = JSON.stringify({ secretHash, sandbox, registeredAt: stamp });
    if (!applyIfNewer(`device:${token}`, json, remainingSeconds)) {
      metrics.inc("peer_ignored_total");
      return { status: 200, body: { ok: true, applied: false } };
    }
    // The peer holds this record; a phone re-registering it here needn't send
    // it back.
    noteAcked(token, json);
    metrics.inc("peer_applied_total");
    return { status: 200, body: { ok: true, applied: true } };
  }

  // Compare and write in one transaction, so a /register for the same token
  // can't commit between the read and the write. The same contents with a
  // stamp within STAMP_MARGIN_MS of ours is an echo, not news: writing it would
  // just cost an fsync.
  const applyIfNewer = kv.db.transaction((key, json, expirationTtl) => {
    const prior = kv.getSync(key);
    const existing = prior == null ? null : JSON.parse(prior);
    const incoming = JSON.parse(json);
    if (!isNewer(incoming, existing)) return false;
    if (existing && existing.secretHash === incoming.secretHash &&
        !!existing.sandbox === !!incoming.sandbox &&
        incoming.registeredAt - existing.registeredAt < STAMP_MARGIN_MS) {
      return false;
    }
    kv.putSync(key, json, { expirationTtl });
    return true;
  });

  // Authenticated liveness check that just returns our instance id (in the
  // response header the server adds).
  function hello(authHeader) {
    if (!isAuthorized(authHeader)) {
      metrics.inc("peer_rejected_total");
      return { status: 403, body: { error: "bad peer secret" } };
    }
    return { status: 200, body: { ok: true } };
  }

  // Ask the peer for its ids and clock (to notice a rebuild or restart while
  // idle, and keep the liveness and skew gauges fresh).
  async function sayHello() {
    try {
      const sentAt = now();
      const res = await fetchImpl(helloEndpoint, {
        method: "POST",
        headers: { authorization: `Bearer ${peerSecret}` },
        redirect: "error",
        signal: AbortSignal.timeout(sendTimeoutMs),
      });
      await res.text().catch(() => "");
      if (res.ok && notePeerResponse(res, sentAt, now()) && res.headers.get(PEER_INSTANCE_HEADER)) return;
    } catch { /* unreachable: the liveness gauge and next tick cover it */ }
    peerDown = true;
  }

  // Timer work: when nothing is due, say hello; then drain.
  async function tick() {
    if (!dueStmt.get(now())) await sayHello();
    await flush();
  }

  return {
    instanceId,
    responseHeaders,
    enqueue,
    flush,
    receive,
    hello,
    tick,
    // Queue every live registration at low priority (startup / SIGUSR2).
    backfill: () => backfillStmt.run(now()).changes,
    gauges: () => ({
      peer_outbox: countStmt.get().n,
      peer_clock_skew_ms: lastSkewMs,
      peer_last_ok_timestamp_seconds: Math.floor(lastOkAt / 1000),
    }),
    start() {
      timer = setInterval(() => { tick().catch(() => {}); }, retryIntervalMs);
      timer.unref?.();
    },
    stop() {
      if (timer) clearInterval(timer);
      timer = null;
      if (cooldownTimer) clearTimeout(cooldownTimer);
      cooldownTimer = null;
    },
  };
}
