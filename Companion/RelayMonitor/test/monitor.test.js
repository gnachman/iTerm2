// Pure analysis core for the relay monitor: cap-proximity, error-rate, and
// traffic-anomaly detection, plus the cooldown that keeps a sustained condition
// from re-paging every run. No I/O here; the worker shell feeds these fetched
// aggregate metrics (never per-request data) and sends what they return.

import { describe, it, expect } from "vitest";
import {
  median, pushSample, capAlerts, errorAlert, anomalyAlert, dueAlerts, analyze,
} from "../src/monitor.js";

const CONFIG = {
  requestCap: 100000, requestWarnFrac: 0.7, requestCritFrac: 0.9,
  errorRatio: 0.05, errorMinRequests: 100,
  spikeFactor: 3, dropFactor: 0.3, minBaseline: 50, minSamples: 14, maxSamples: 6,
};

describe("median", () => {
  it("handles odd and even counts and empty", () => {
    expect(median([3, 1, 2])).toBe(2);
    expect(median([4, 1, 2, 3])).toBe(2.5);
    expect(median([])).toBe(null);
  });
});

describe("pushSample", () => {
  it("appends per hour-of-week and bounds the history length", () => {
    let h = {};
    for (let i = 1; i <= 6; i++) h = pushSample(h, 5, i, 4);
    expect(h["5"]).toEqual([3, 4, 5, 6]); // kept the last 4
    expect(h["6"]).toBeUndefined();
  });
});

describe("capAlerts", () => {
  const meters = [{ key: "requests", label: "Requests", used: 0, cap: 100000, warnFrac: 0.7, critFrac: 0.9, unit: "" }];
  it("is silent below the warn fraction", () => {
    expect(capAlerts([{ ...meters[0], used: 50000 }])).toEqual([]);
  });
  it("warns past the warn fraction", () => {
    const a = capAlerts([{ ...meters[0], used: 75000 }]);
    expect(a).toHaveLength(1);
    expect(a[0].severity).toBe("warn");
    expect(a[0].key).toBe("cap:requests");
  });
  it("escalates to critical past the critical fraction", () => {
    expect(capAlerts([{ ...meters[0], used: 95000 }])[0].severity).toBe("critical");
  });
});

describe("errorAlert", () => {
  it("trips when the error ratio exceeds the threshold with enough volume", () => {
    const a = errorAlert({ requests: 1000, errors: 60, ratioThreshold: 0.05, minRequests: 100 });
    expect(a?.severity).toBe("warn");
    expect(a.key).toBe("errors");
  });
  it("stays silent on a tiny sample even at a high ratio", () => {
    expect(errorAlert({ requests: 5, errors: 4, ratioThreshold: 0.05, minRequests: 100 })).toBe(null);
  });
  it("stays silent under the ratio threshold", () => {
    expect(errorAlert({ requests: 1000, errors: 10, ratioThreshold: 0.05, minRequests: 100 })).toBe(null);
  });
});

describe("anomalyAlert", () => {
  const base = { key: "traffic", label: "Hourly requests", spikeFactor: 3, dropFactor: 0.3, minBaseline: 50, minSamples: 14 };
  const samples = Array(20).fill(100);
  it("flags a spike above the baseline", () => {
    const a = anomalyAlert({ ...base, current: 400, samples });
    expect(a?.key).toBe("anomaly:traffic");
    expect(a.body).toMatch(/spike/i);
  });
  it("flags a drop below the baseline", () => {
    expect(anomalyAlert({ ...base, current: 20, samples }).body).toMatch(/drop/i);
  });
  it("stays silent within normal range", () => {
    expect(anomalyAlert({ ...base, current: 130, samples })).toBe(null);
  });
  it("stays silent until enough history exists", () => {
    expect(anomalyAlert({ ...base, current: 999, samples: Array(5).fill(100) })).toBe(null);
  });
  it("stays silent when the baseline is too small to be meaningful", () => {
    expect(anomalyAlert({ ...base, current: 999, samples: Array(20).fill(1) })).toBe(null);
  });
});

describe("dueAlerts (cooldown)", () => {
  const A = { key: "errors", severity: "warn", title: "x", body: "y" };
  it("sends a newly-seen alert and records the time", () => {
    const { due, sentAt } = dueAlerts([A], {}, 1000, 60000);
    expect(due).toHaveLength(1);
    expect(sentAt.errors).toBe(1000);
  });
  it("suppresses the same alert within the cooldown", () => {
    const { due } = dueAlerts([A], { errors: 1000 }, 1000 + 30000, 60000);
    expect(due).toHaveLength(0);
  });
  it("re-sends after the cooldown elapses", () => {
    const { due } = dueAlerts([A], { errors: 1000 }, 1000 + 61000, 60000);
    expect(due).toHaveLength(1);
  });
  it("sends immediately when severity escalates, even within cooldown", () => {
    const crit = { ...A, severity: "critical" };
    const { due } = dueAlerts([crit], { errors: 1000, "errors:sev": "warn" }, 1000 + 1000, 60000);
    expect(due).toHaveLength(1);
  });
  it("clears state for conditions that are no longer alerting", () => {
    const { sentAt } = dueAlerts([], { errors: 1000 }, 5000, 60000);
    expect(sentAt.errors).toBeUndefined();
  });
});

describe("analyze", () => {
  const metrics = {
    requestsToday: 95000, requestsLastHour: 500, errorsLastHour: 1,
    lastHourOfWeek: 10, lastHourKey: "2026-06-15T10:00:00Z",
  };

  it("raises a cap alert and records the completed hour into history", () => {
    const { alerts, history, lastRecordedHour } = analyze(metrics, { history: {}, lastRecordedHour: null }, CONFIG);
    expect(alerts.some((a) => a.key === "cap:requests" && a.severity === "critical")).toBe(true);
    expect(history["10"]).toEqual([500]);
    expect(lastRecordedHour).toBe(metrics.lastHourKey);
  });

  it("does not double-record the same hour across sub-hourly runs", () => {
    const state = { history: { "10": [500] }, lastRecordedHour: metrics.lastHourKey };
    const { history } = analyze(metrics, state, CONFIG);
    expect(history["10"]).toEqual([500]); // unchanged
  });

  it("flags a spike using the prior weeks' baseline for that hour", () => {
    const state = { history: { "10": Array(16).fill(100) }, lastRecordedHour: "older" };
    const spiked = { ...metrics, requestsToday: 1000, requestsLastHour: 600 };
    const { alerts } = analyze(spiked, state, CONFIG);
    expect(alerts.some((a) => a.key === "anomaly:requests")).toBe(true);
  });
});
