// SQLite-backed stand-in for the subset of the Cloudflare Workers KV API that
// worker.js uses. On Cloudflare, KV is a globally-replicated key/value store
// with a per-account DAILY WRITE CAP on the free plan — the very limit that
// motivated self-hosting (a reconnect storm exhausted it and blocked genuine
// registrations). Here a single process owns one SQLite file with no such cap.
//
// Fidelity that worker.js depends on:
//   - get(missing) === null            (authorizeDevice checks `!record`)
//   - get(key, "json") parses JSON; get(key) / get(key, "text") returns string
//   - put(key, value, {expirationTtl}) stores a string that disappears after
//     `expirationTtl` seconds (registrations self-expire; rate-limit buckets are
//     short-lived). Expiry is enforced on read AND swept periodically.
//   - list({prefix}) returns { keys: [{ name, expiration }] } sorted by name,
//     with `expiration` in unix SECONDS (only used by tests / diagnostics).
//
// better-sqlite3 is synchronous; the methods are async only to match the KV
// interface worker.js awaits. One event-loop thread => the read-modify-write in
// register() (get-then-put) stays atomic without extra locking, exactly as it
// did under Cloudflare's per-key consistency.

import Database from "better-sqlite3";

export class SqliteKV {
  // `path` is a file path or ":memory:". `now` is injectable for tests.
  constructor(path = ":memory:", { now = () => Date.now() } = {}) {
    this.now = now;
    this.db = new Database(path);
    this.db.pragma("journal_mode = WAL");
    this.db.pragma("synchronous = NORMAL");
    this.db.exec(
      `CREATE TABLE IF NOT EXISTS kv (
         key        TEXT PRIMARY KEY,
         value      TEXT NOT NULL,
         expires_at INTEGER          -- unix ms; NULL = never expires
       );
       CREATE INDEX IF NOT EXISTS kv_expires ON kv(expires_at);`
    );
    this._get = this.db.prepare("SELECT value, expires_at FROM kv WHERE key = ?");
    this._put = this.db.prepare(
      `INSERT INTO kv (key, value, expires_at) VALUES (@key, @value, @expires_at)
       ON CONFLICT(key) DO UPDATE SET value = @value, expires_at = @expires_at`
    );
    this._del = this.db.prepare("DELETE FROM kv WHERE key = ?");
    this._sweep = this.db.prepare(
      "DELETE FROM kv WHERE expires_at IS NOT NULL AND expires_at <= ?");
    this._list = this.db.prepare(
      "SELECT key, expires_at FROM kv WHERE key GLOB ? ORDER BY key");
  }

  // eslint-disable-next-line require-await -- async to match the KV interface
  async get(key, type = "text") {
    const row = this._get.get(key);
    if (!row) return null;
    if (row.expires_at != null && row.expires_at <= this.now()) {
      // Lazy expiry: a value past its TTL reads as absent (and is reaped so the
      // row cannot resurface). Mirrors KV, where an expired key is simply gone.
      this._del.run(key);
      return null;
    }
    return type === "json" ? JSON.parse(row.value) : row.value;
  }

  // eslint-disable-next-line require-await
  async put(key, value, { expirationTtl } = {}) {
    if (typeof value !== "string") {
      // KV also accepts ArrayBuffer/stream, but worker.js only ever puts strings.
      throw new TypeError("SqliteKV.put expects a string value");
    }
    const expires_at = Number.isFinite(expirationTtl)
      ? this.now() + expirationTtl * 1000
      : null;
    this._put.run({ key, value, expires_at });
  }

  // eslint-disable-next-line require-await
  async delete(key) {
    this._del.run(key);
  }

  // eslint-disable-next-line require-await
  async list({ prefix = "" } = {}) {
    // GLOB is case-sensitive (KV is too); escape the glob metacharacters that can
    // appear so a prefix is matched literally. device:/rl: keys are hex + ':' so
    // this is belt-and-suspenders, but keep it correct for arbitrary prefixes.
    const escaped = prefix.replace(/[[\]*?]/g, (c) => `[${c}]`);
    const nowMs = this.now();
    const keys = this._list.all(`${escaped}*`)
      .filter((r) => r.expires_at == null || r.expires_at > nowMs)
      .map((r) => ({
        name: r.key,
        expiration: r.expires_at == null ? undefined : Math.floor(r.expires_at / 1000),
      }));
    return { keys, list_complete: true };
  }

  // Bulk-delete every expired row. The server calls this on a timer so expired
  // registrations and rate-limit buckets don't accumulate on disk (lazy expiry
  // only reaps keys that happen to be read again).
  sweepExpired() {
    return this._sweep.run(this.now()).changes;
  }

  close() {
    this.db.close();
  }
}
