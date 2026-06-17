// iTerm2 relay monitor.
//
// A scheduled Worker that watches the room relay's AGGREGATE metrics (Cloudflare
// GraphQL Analytics: request/error counts and durations -- never per-request
// data or IPs, so it does not reintroduce the logging the relay forbids) and
// emails on three conditions: approaching the daily cap, an error spike, or a
// traffic spike/drop versus the established per-hour-of-week baseline. The
// analysis is pure (src/monitor.js, unit-tested); this file is the I/O shell.
//
// A GET / with the x-monitor-key secret runs a DRY check (fetch + analyze, no
// email, no state write) and returns JSON, so the GraphQL query and thresholds
// can be verified after deploy without waiting for the cron or sending mail.
//
// Secrets (wrangler secret put): CF_API_TOKEN (Account Analytics: Read),
// RESEND_API_KEY, MANUAL_TRIGGER_SECRET. KV binding: MONITOR_KV.

import { analyze, dueAlerts } from "./monitor.js";

const GQL_ENDPOINT = "https://api.cloudflare.com/client/v4/graphql";
const STATE_KEY = "state";

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(run(env, Date.now(), { dry: false }));
  },

  async fetch(request, env) {
    if (request.headers.get("x-monitor-key") !== env.MANUAL_TRIGGER_SECRET || !env.MANUAL_TRIGGER_SECRET) {
      return new Response("not found", { status: 404 });
    }
    // ?test=1 sends a REAL test email, to verify the Resend path end to end
    // (the dry-run check never sends mail). Returns the provider error on failure.
    if (new URL(request.url).searchParams.get("test") === "1") {
      try {
        await sendDigest(env, [{
          key: "test", severity: "warn", title: "Relay monitor test",
          body: "If you received this, the monitor's email path works.",
        }]);
        return json({ emailed: true });
      } catch (e) {
        return json({ emailed: false, error: String(e.message || e) }, 500);
      }
    }
    const result = await run(env, Date.now(), { dry: true });
    return json(result);
  },
};

function num(v, fallback) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj, null, 2), {
    status, headers: { "content-type": "application/json" },
  });
}

function config(env) {
  return {
    requestCap: num(env.DAILY_REQUEST_CAP, 100000),
    requestWarnFrac: num(env.REQUEST_WARN_FRAC, 0.7),
    requestCritFrac: num(env.REQUEST_CRIT_FRAC, 0.9),
    errorRatio: num(env.ERROR_RATIO, 0.05),
    errorMinRequests: num(env.ERROR_MIN_REQUESTS, 100),
    spikeFactor: num(env.SPIKE_FACTOR, 3),
    dropFactor: num(env.DROP_FACTOR, 0.3),
    minBaseline: num(env.MIN_BASELINE, 50),
    minSamples: num(env.MIN_SAMPLES, 14),
    maxSamples: num(env.MAX_SAMPLES, 6),
    cooldownMs: num(env.COOLDOWN_MINUTES, 360) * 60 * 1000,
  };
}

async function run(env, now, { dry }) {
  const cfg = config(env);
  const metrics = await fetchMetrics(env, now);
  const state = dry ? {} : ((await env.MONITOR_KV.get(STATE_KEY, "json")) || {});

  const { alerts, history, lastRecordedHour } = analyze(metrics, state, cfg);
  const { due, sentAt } = dueAlerts(alerts, state.sentAt || {}, now, cfg.cooldownMs);

  if (!dry) {
    if (due.length) await sendDigest(env, due);
    await env.MONITOR_KV.put(STATE_KEY, JSON.stringify({ sentAt, history, lastRecordedHour }));
  }
  return { metrics, alerts, due: due.map((a) => a.key) };
}

// --- Cloudflare GraphQL Analytics (aggregate only) ---

// One UTC hour bucket: { hour: ISO, requests, errors }.
async function fetchMetrics(env, now) {
  const start = new Date(now - 25 * 60 * 60 * 1000).toISOString();
  const end = new Date(now).toISOString();
  const query = `query($account:String!,$script:String!,$start:Time!,$end:Time!){
    viewer{ accounts(filter:{accountTag:$account}){
      workersInvocationsAdaptive(
        limit:1000,
        filter:{ scriptName:$script, datetime_geq:$start, datetime_leq:$end },
        orderBy:[datetimeHour_ASC]
      ){
        dimensions{ datetimeHour }
        sum{ requests errors }
      }
    }}
  }`;
  const res = await fetch(GQL_ENDPOINT, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.CF_API_TOKEN}`, "content-type": "application/json" },
    body: JSON.stringify({
      query,
      variables: { account: env.ACCOUNT_ID, script: env.SCRIPT_NAME, start, end },
    }),
  });
  const body = await res.json();
  if (body.errors && body.errors.length) {
    throw new Error("GraphQL: " + JSON.stringify(body.errors));
  }
  const rows = body?.data?.viewer?.accounts?.[0]?.workersInvocationsAdaptive || [];
  return summarize(rows, now);
}

// Fold the hourly buckets into the figures the analyzer needs: today's totals,
// and the most recent COMPLETED hour (for error rate + the anomaly sample).
function summarize(rows, now) {
  const buckets = rows.map((r) => ({
    hour: r.dimensions.datetimeHour,
    requests: r.sum.requests || 0,
    errors: r.sum.errors || 0,
  }));
  const today = new Date(now).toISOString().slice(0, 10);
  let requestsToday = 0;
  let errorsToday = 0;
  for (const b of buckets) {
    if (b.hour.slice(0, 10) === today) { requestsToday += b.requests; errorsToday += b.errors; }
  }
  // The current hour is still accumulating; the last completed hour is the most
  // recent bucket strictly before it.
  const currentHourKey = new Date(now).toISOString().slice(0, 13); // YYYY-MM-DDTHH
  const completed = buckets.filter((b) => b.hour.slice(0, 13) < currentHourKey);
  const last = completed[completed.length - 1];
  return {
    requestsToday,
    errorsToday,
    requestsLastHour: last ? last.requests : 0,
    errorsLastHour: last ? last.errors : 0,
    lastHourKey: last ? last.hour : null,
    lastHourOfWeek: last ? hourOfWeek(last.hour) : null,
  };
}

// 0..167, Monday 00:00 UTC = 0. Stable bucket for the weekly baseline.
function hourOfWeek(iso) {
  const d = new Date(iso);
  const dow = (d.getUTCDay() + 6) % 7; // Mon=0 .. Sun=6
  return dow * 24 + d.getUTCHours();
}

// --- Email (Resend) ---

async function sendDigest(env, alerts) {
  const worst = alerts.some((a) => a.severity === "critical") ? "CRITICAL" : "warning";
  const subject = `[iTerm2 relay] ${alerts.length} alert(s) (${worst})`;
  const text = alerts.map((a) => `[${a.severity.toUpperCase()}] ${a.title}\n${a.body}`).join("\n\n");
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ from: env.ALERT_FROM, to: [env.ALERT_TO], subject, text }),
  });
  if (!res.ok) {
    throw new Error(`Resend ${res.status}: ${await res.text()}`);
  }
}
