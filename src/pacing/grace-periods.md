# Grace Periods & Hybrid Modes

PI control needs a stable input signal. During startup and after periods of inactivity, the arrival-rate estimate is noisy or meaningless. The grace period protects the *controller* during these transients — **without refusing to serve**.

## Grace Period: Serve, but Don't Trust the Integral Yet

During grace, Promovolve has not yet accumulated enough closely-spaced requests to trust its arrival-rate estimate for full PI control. But it still **serves**. Pacing is a brake, not a gate: at startup spend is ~zero and the campaign is maximally *behind* pace, so serving is the safe direction.

The throttle during grace is `baseThrottle` — the **rate cap** that holds impressions/sec at the paced target:

```
evenTargetImpsPerSec = (dailyBudget / dayDurationSeconds) / (cpm / 1000)
baseTargetImpsPerSec = evenTargetImpsPerSec × trafficShapeMultiplier

baseThrottle = if (arrivalRate > baseTargetImpsPerSec)
                 1 - (baseTargetImpsPerSec / arrivalRate)   // cap a flood to the paced rate
               else
                 0.0                                          // sparse traffic → serve freely
```

This is proportional to arrival rate:

- **Sparse / cold site** (rate below the paced target): `baseThrottle ≈ 0` → serve freely. No cold-start cliff.
- **Flood** (rate ≫ target): `baseThrottle → ~1` → throttled down to the paced rate, so a burst cannot exhaust the budget before the PI loop warms up.

What grace withholds is only the **PI integral**: error is not accumulated until grace completes, so the controller starts correcting from clean data rather than from transient startup noise.

> **History.** Earlier, grace returned `MaxThrottleProb = 0.99` — effectively *no* serving — to guard against cold-start budget burn. That guard was redundant with `baseThrottle` (which already caps a flood) and QPS-blind: it did nothing useful on a low-traffic site while imposing the full cost — a publisher with sparse organic traffic showed **no ads at all** until it happened to accumulate enough closely-spaced requests to exit grace. Grace now serves at `baseThrottle` instead.

## Grace Period Conditions

Grace ends when **both** conditions are met:

```
dayScale      = dayDurationSeconds / 86400
graceSeconds  = max(1.0, MinGraceSeconds × dayScale)   // 10s on a real day; floors at 1s for short sim-days

graceRequests = clamp(arrivalRate × graceSeconds, MinGraceRequests, MaxGraceRequests)  // when traffic-shape data exists
              = max(5, MinGraceRequests × dayScale)                                     // fallback with no shape data

Grace ends when:
  elapsedSeconds >= graceSeconds AND requestCount >= graceRequests
```

`requestCount` is cumulative per site (it is not reset on rollover), so on a real calendar day the request gate is effectively a **one-time cold-start condition**: once a site has served ~10+ requests it is satisfied for good, and only the time gate (`graceSeconds`) re-arms briefly at each day rollover. Because grace now serves at `baseThrottle`, that re-arming is invisible to delivery.

### Staleness Reset

If no requests arrive for a while, the EMA-smoothed rate has decayed and stale accumulated error would cause erratic corrections. After a gap, Promovolve **resets the PI integral** — but keeps serving:

```
staleThreshold = max(MinStaleRateThresholdMs, BaseStaleRateThresholdMs × dayScale)
               = max(1000ms, 30000ms × dayScale)

if (nowMs - lastRequestMs) > staleThreshold:
    integralError = 0; smoothedSpendRatio = None   // reset, then fall through to normal PI
```

This does **not** re-enter "no serving" — staleness only clears stale controller state. The gap doesn't mean the data is bad, just old.

## Grace Period Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `DefaultGracePeriodFraction` | 0.01 | Legacy fraction-of-day grace base (superseded by the `dayScale` formula above) |
| `MinGraceSeconds` | 10.0 | Grace duration on a real day (scaled down for short sim-days, floor 1s) |
| `MinGraceRequests` | 10 | Lower bound on the request gate before PI activates |
| `MaxGraceRequests` | 50 | Upper bound on the dynamic request gate (high-traffic sites) |
| `EmaStabilizationWindows` | 3 | EMA warmup windows (rate smoothing) |
| `BaseStaleRateThresholdMs` | 30,000 | Staleness detection (real day) |
| `MinStaleRateThresholdMs` | 1,000 | Minimum staleness threshold for short simulated days |
| `MaxThrottleProb` | 0.99 | Ceiling for *computed* throttle (true hard stops use 1.0); **no longer used for grace** |

## Grace Period Timeline (real 24h day)

```
Time    Event                       Mode           Throttle
00:00   Site pacing starts          Grace          baseThrottle (≈0 when sparse, rate-cap under load)
00:05   5 requests arrived          Grace (count)  baseThrottle
00:10   10s elapsed, 10+ requests   PI active      Computed (PI integral now engages)
...
01:30   No requests for 35s         Stale reset    integral cleared, keeps serving
01:31   Requests resume             PI active      Computed
```

## Simulated Days

For testing, `dayDurationSeconds` can be set far shorter than 86400 (e.g. 300s for a 5-minute "day"). Grace duration, stale thresholds, and the observation interval all scale by `dayScale = dayDurationSeconds / 86400`, so behavior stays consistent across time scales.

Because grace now serves at `baseThrottle`, short simulated days no longer hit the cold-start cliff where frequent rollovers re-armed a *no-serving* grace faster than sparse traffic could satisfy it. (Previously, a short sim-day driven by only a few requests per "day" could sit at `0.99` throttle indefinitely — the symptom that looked like a permanent hard stop.)
