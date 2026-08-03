// Aggregate, non-identifying metrics for the push relay — the same idea as the
// companion relay's host/metrics.js, so the on-box dashboard can chart "is push
// healthy / is delivery failing" without any PII. Only counts and one gauge
// (registered device count); never a token, secret, or IP.
//
// Rendered in Prometheus text format under the `pushrelay_` prefix (distinct
// from the companion relay's `relay_`) and served on a localhost-only endpoint.
// The counters map 1:1 to the decisions worker.js makes so the dashboard can
// show registration write-vs-skip (the idempotency signal that motivated all
// this) and push delivery-vs-bad-secret-vs-APNs-error.

const COUNTER_HELP = {
  http_requests_total: "HTTP requests received.",
  http_errors_total: "Requests that threw and returned 500.",
  register_total: "POST /register calls.",
  register_written_total: "Registrations that wrote KV (new/changed/TTL refresh).",
  register_skipped_total: "Registrations skipped as unchanged (no KV write).",
  register_rejected_total: "Registrations rejected (bad input or rate limited).",
  push_total: "POST /push and /push/mutable calls.",
  push_delivered_total: "Pushes accepted by APNs (2xx).",
  push_bad_secret_total: "Pushes rejected: secret did not match the registration.",
  push_unknown_token_total: "Pushes rejected: device token not registered.",
  push_apns_error_total: "Pushes that reached APNs but got a non-2xx (surfaced as 502).",
  rate_limited_total: "Requests rejected by a rate limit (429).",
  process_exceptions_total: "Process-level exceptions swallowed to keep serving.",
};
const GAUGE_HELP = {
  devices: "Registered devices currently in KV (live, non-expired).",
};

export class Metrics {
  constructor() {
    this.counters = new Map();
  }

  inc(name, by = 1) {
    this.counters.set(name, (this.counters.get(name) || 0) + by);
  }

  // Ensure a counter appears in /metrics from boot (as 0) so the dashboard sees a
  // stable series instead of a line that only springs into existence on first hit.
  preregister(names) {
    for (const n of names) if (!this.counters.has(n)) this.counters.set(n, 0);
  }

  // `gauges` are point-in-time values the host supplies at scrape time (e.g. the
  // live device count from a KV COUNT).
  render(gauges = {}) {
    const lines = [];
    const emitted = new Set();
    const help = (name, type) => {
      if (emitted.has(name)) return;
      emitted.add(name);
      const h = COUNTER_HELP[name] || GAUGE_HELP[name];
      if (h) lines.push(`# HELP pushrelay_${name} ${h}`);
      lines.push(`# TYPE pushrelay_${name} ${type}`);
    };
    for (const [name, value] of this.counters) {
      help(name, "counter");
      lines.push(`pushrelay_${name} ${value}`);
    }
    for (const [name, value] of Object.entries(gauges)) {
      help(name, "gauge");
      lines.push(`pushrelay_${name} ${value}`);
    }
    return lines.join("\n") + "\n";
  }
}

// The counters worker.js decisions map to, pre-registered at boot so every line
// is present from the first scrape.
export const COUNTER_NAMES = Object.keys(COUNTER_HELP);
