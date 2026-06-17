// Pure analysis for the relay monitor. No I/O: the worker shell feeds these
// AGGREGATE metrics (request/error counts, durations -- never per-request data
// or IPs, consistent with the relay's no-logging posture) and sends whatever
// alerts come back. Kept pure so the alerting logic is unit-tested deterministically.

export function median(nums) {
  if (!nums || nums.length === 0) return null;
  const s = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

// Append a sample to the per-hour-of-week history (object: "0".."167" -> array),
// keeping only the most recent `maxSamples` so the baseline tracks recent weeks.
export function pushSample(history, hourOfWeek, value, maxSamples) {
  const key = String(hourOfWeek);
  const arr = [...(history[key] || []), value];
  return { ...history, [key]: arr.slice(-maxSamples) };
}

// Cap proximity: warn/critical when a metered resource crosses a fraction of its
// cap, so there is lead time before the daily allowance is exhausted.
// meters: [{ key, label, used, cap, warnFrac, critFrac, unit }]
export function capAlerts(meters) {
  const alerts = [];
  for (const m of meters) {
    if (!m.cap) continue;
    const frac = m.used / m.cap;
    const pct = Math.round(frac * 100);
    const u = m.unit ? ` ${m.unit}` : "";
    const detail = `${m.label}: ${m.used}${u} of ${m.cap}${u} (${pct}%) used today.`;
    if (frac >= m.critFrac) {
      alerts.push({ key: `cap:${m.key}`, severity: "critical", title: `${m.label} near cap (${pct}%)`, body: detail });
    } else if (frac >= m.warnFrac) {
      alerts.push({ key: `cap:${m.key}`, severity: "warn", title: `${m.label} elevated (${pct}%)`, body: detail });
    }
  }
  return alerts;
}

// Error-rate alert with an absolute-volume floor so a couple of errors over a
// handful of requests never pages.
export function errorAlert({ requests, errors, ratioThreshold, minRequests }) {
  if (requests < minRequests) return null;
  const ratio = requests > 0 ? errors / requests : 0;
  if (ratio < ratioThreshold) return null;
  const pct = (ratio * 100).toFixed(1);
  return {
    key: "errors",
    severity: ratio >= ratioThreshold * 2 ? "critical" : "warn",
    title: `Error rate ${pct}%`,
    body: `${errors} errors of ${requests} requests in the last window (${pct}%).`,
  };
}

// Traffic anomaly vs the baseline for this hour-of-week. Silent until there is
// enough history (minSamples) and the baseline is large enough to be meaningful
// (minBaseline), so it does not cry wolf early or on near-idle hours.
export function anomalyAlert({ key, label, current, samples, spikeFactor, dropFactor, minBaseline, minSamples }) {
  if (!samples || samples.length < minSamples) return null;
  const base = median(samples);
  if (base === null || base < minBaseline) return null;
  if (current >= base * spikeFactor) {
    return {
      key: `anomaly:${key}`, severity: "warn",
      title: `Traffic spike: ${label}`,
      body: `${label} spike: ${current}, ~${(current / base).toFixed(1)}x the usual ${base} for this hour.`,
    };
  }
  if (current <= base * dropFactor) {
    return {
      key: `anomaly:${key}`, severity: "warn",
      title: `Traffic drop: ${label}`,
      body: `${label} drop: ${current}, well below the usual ${base} for this hour (possible outage).`,
    };
  }
  return null;
}

// Orchestrate the three checks against fetched metrics + prior state, and fold
// the just-completed hour into the baseline history (once per hour, guarded by
// lastRecordedHour so a sub-hourly cron does not record duplicates). Pure: the
// worker shell supplies metrics (aggregate), state (from KV), and parsed config.
export function analyze(metrics, state, config) {
  const history = state.history || {};
  const alerts = [];

  alerts.push(...capAlerts([{
    key: "requests", label: "Worker requests", used: metrics.requestsToday,
    cap: config.requestCap, warnFrac: config.requestWarnFrac, critFrac: config.requestCritFrac, unit: "",
  }]));

  const e = errorAlert({
    requests: metrics.requestsLastHour, errors: metrics.errorsLastHour,
    ratioThreshold: config.errorRatio, minRequests: config.errorMinRequests,
  });
  if (e) alerts.push(e);

  // Compare the completed hour to PRIOR weeks for that hour-of-week (baseline
  // read before recording, so it is never compared against itself).
  const priorSamples = history[String(metrics.lastHourOfWeek)] || [];
  const an = anomalyAlert({
    key: "requests", label: "Hourly requests", current: metrics.requestsLastHour, samples: priorSamples,
    spikeFactor: config.spikeFactor, dropFactor: config.dropFactor,
    minBaseline: config.minBaseline, minSamples: config.minSamples,
  });
  if (an) alerts.push(an);

  let newHistory = history;
  let lastRecordedHour = state.lastRecordedHour;
  if (metrics.lastHourKey && metrics.lastHourKey !== state.lastRecordedHour) {
    newHistory = pushSample(history, metrics.lastHourOfWeek, metrics.requestsLastHour, config.maxSamples);
    lastRecordedHour = metrics.lastHourKey;
  }
  return { alerts, history: newHistory, lastRecordedHour };
}

// Cooldown / dedupe: send an alert only if it is newly active, its severity
// escalated, or the cooldown has elapsed; otherwise hold it. Returns the alerts
// to send now and the updated per-key state (last-sent time + last severity).
// Conditions absent from `alerts` are cleared from state, so they re-page if
// they recur after resolving.
export function dueAlerts(alerts, prev, now, cooldownMs) {
  const sentAt = {};
  const due = [];
  for (const a of alerts) {
    const last = prev[a.key];
    const lastSev = prev[`${a.key}:sev`];
    const escalated = lastSev === "warn" && a.severity === "critical";
    const cool = last === undefined || now - last >= cooldownMs;
    if (escalated || cool) {
      due.push(a);
      sentAt[a.key] = now;
    } else {
      sentAt[a.key] = last; // still active, keep the original send time
    }
    sentAt[`${a.key}:sev`] = a.severity;
  }
  return { due, sentAt };
}
