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
  push_failed_total: "Pushes that failed on our side or Apple's (502 APNs reject or 500 transport error); excludes client faults.",
  apns_connects_total: "New HTTP/2 connections opened to APNs.",
  apns_connect_throttled_total: "Connection attempts delayed by the 1/sec per-host reconnect floor.",
  apns_session_errors_total: "APNs sessions that errored (reset, TLS failure, ...).",
  apns_discarded_idle_total: "APNs sessions replaced because they sat idle too long.",
  apns_discarded_timeout_total: "APNs sessions thrown away after a request timed out.",
  apns_request_timeouts_total: "APNs requests that got no answer within the timeout.",
};
const GAUGE_HELP = {
  devices: "Registered devices currently in KV (live, non-expired).",
  apns_sessions: "Open HTTP/2 sessions to APNs right now.",
  apns_oldest_session_age_seconds: "Age of the oldest open APNs session.",
  last_delivery_timestamp_seconds: "Unix time of the last push APNs accepted; 0 if none since process start.",
};

// Apple's rejection reasons are a small closed set, so labeling by reason is
// bounded and carries nothing identifying. Anything else folds into "other" and
// the distinct-label count is capped, so a misbehaving upstream can't grow it.
const REJECT_HELP = "Pushes APNs rejected, by Apple's reason string.";
const KNOWN_REASONS = [
  "BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic", "TooManyRequests",
  "ExpiredProviderToken", "InvalidProviderToken", "InternalServerError",
  "ServiceUnavailable", "other",
];
const MAX_REASONS = 40;

// APNs round-trip latency, seconds. Upper bound is the 10s request timeout.
export const LATENCY_BUCKETS = [0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];
const LATENCY_HELP = "Round-trip time of pushes sent to APNs (seconds), incl. connect and any throttle wait.";

export class Metrics {
  constructor() {
    this.counters = new Map();
    this.rejects = new Map(KNOWN_REASONS.map((r) => [r, 0]));
    this.latency = { buckets: LATENCY_BUCKETS.map(() => 0), sum: 0, count: 0 };
  }

  // Count one APNs rejection under its reason (sanitized: alphabetic, bounded).
  incReject(reason) {
    let r = typeof reason === "string" && /^[A-Za-z]{1,40}$/.test(reason) ? reason : "other";
    if (!this.rejects.has(r) && this.rejects.size >= MAX_REASONS) r = "other";
    this.rejects.set(r, (this.rejects.get(r) || 0) + 1);
  }

  // Record one APNs round trip (seconds) in the cumulative latency histogram.
  observeLatency(seconds) {
    const l = this.latency;
    LATENCY_BUCKETS.forEach((le, i) => { if (seconds <= le) l.buckets[i] += 1; });
    l.sum += seconds;
    l.count += 1;
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

    lines.push(`# HELP pushrelay_apns_rejected_total ${REJECT_HELP}`);
    lines.push("# TYPE pushrelay_apns_rejected_total counter");
    for (const [reason, value] of this.rejects) {
      lines.push(`pushrelay_apns_rejected_total{reason="${reason}"} ${value}`);
    }

    const l = this.latency;
    lines.push(`# HELP pushrelay_apns_latency_seconds ${LATENCY_HELP}`);
    lines.push("# TYPE pushrelay_apns_latency_seconds histogram");
    LATENCY_BUCKETS.forEach((le, i) => {
      lines.push(`pushrelay_apns_latency_seconds_bucket{le="${le}"} ${l.buckets[i]}`);
    });
    lines.push(`pushrelay_apns_latency_seconds_bucket{le="+Inf"} ${l.count}`);
    lines.push(`pushrelay_apns_latency_seconds_sum ${l.sum}`);
    lines.push(`pushrelay_apns_latency_seconds_count ${l.count}`);
    return lines.join("\n") + "\n";
  }
}

// The counters worker.js decisions map to, pre-registered at boot so every line
// is present from the first scrape.
export const COUNTER_NAMES = Object.keys(COUNTER_HELP);

// Maps the APNs transport's telemetry events (see host/apns.js onEvent) onto
// counters and the latency histogram. Kept here so the mapping is testable
// without standing up the whole server.
export function apnsEventSink(metrics) {
  return (name, data) => {
    switch (name) {
      case "connect": metrics.inc("apns_connects_total"); break;
      case "connect_throttled": metrics.inc("apns_connect_throttled_total"); break;
      case "session_error": metrics.inc("apns_session_errors_total"); break;
      case "discard":
        metrics.inc(data.kind === "idle" ? "apns_discarded_idle_total" : "apns_discarded_timeout_total");
        break;
      case "request":
        metrics.observeLatency(data.ms / 1000);
        if (data.outcome === "timeout") metrics.inc("apns_request_timeouts_total");
        break;
    }
  };
}
