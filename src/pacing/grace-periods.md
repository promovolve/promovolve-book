# Grace Periods & Hybrid Modes

PI control needs stable input signals. During startup and after periods of inactivity, signals are noisy or meaningless. Grace periods protect the controller during these transients.

## Grace Period: No Serving

During grace, the throttle probability is set to `MaxThrottleProb = 0.99` — effectively **no serving**. This is the opposite of what you might expect: rather than serving freely during warmup, Promovolve suppresses serving until it has enough data to pace correctly.

**Why suppress, not serve freely?** Free serving during startup could exhaust the budget before the PI controller activates. The 0.99 throttle (not 1.0) lets through ~1% of requests as "sensors" to build rate data.

## Grace Period Conditions

Grace is active until **both** conditions are met:

```
graceSeconds = max(MinGraceSeconds, DefaultGracePeriodFraction × dayDurationSeconds)
             = max(10.0, 0.01 × dayDurationSeconds)

graceRequests = MinGraceRequests = 10

Grace ends when:
  elapsedSeconds >= graceSeconds AND requestCount >= graceRequests
```

Additionally, the EMA needs `EmaStabilizationWindows = 3` windows of data to stabilize.

### Staleness Reset

If no requests arrive for a configurable period, grace re-enters:

```
staleThreshold = BaseStaleRateThresholdMs = 30,000ms
                 (scaled proportionally for simulated short days)
                 (min: MinStaleRateThresholdMs = 1,000ms)

if (nowMs - lastRequestMs) > staleThreshold:
    resetGracePeriod()
```

**Why?** After 30 seconds of silence, the EMA-smoothed rate has decayed and no longer represents current traffic. PI corrections with stale rate data would produce erratic throttle swings.

## Grace Period Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `DefaultGracePeriodFraction` | 0.01 (1% of day) | Base grace duration |
| `MinGraceSeconds` | 10.0 | Minimum grace regardless of day length |
| `MinGraceRequests` | 10 | Minimum requests before PI activates |
| `MaxGraceRequests` | 50 | (Not currently used as lower bound) |
| `EmaStabilizationWindows` | 3 | EMA warmup windows |
| `BaseStaleRateThresholdMs` | 30,000 | Staleness detection |
| `MinStaleRateThresholdMs` | 1,000 | Min staleness for short simulated days |
| `MaxThrottleProb` | 0.99 | Throttle during grace |

## Grace Period Timeline

```
Time    Event                       Mode           Throttle
00:00   Site pacing starts          Grace          0.99 (~1% through)
00:05   5 requests arrived          Grace (count)  0.99
00:10   10s elapsed, 10+ requests   Grace (EMA)    0.99
00:13   3 EMA windows stable        PI active      Computed
...
01:30   No requests for 35s         Stale reset    0.99
01:31   Requests resume             Grace          0.99
01:41   Grace conditions met        PI active      Computed
```

## Simulated Days

For testing and simulation, `dayDurationSeconds` can be set shorter than 86400 (e.g., 600 seconds for a 10-minute "day"). Grace periods, stale thresholds, and the RL observation interval all scale proportionally, ensuring the system behaves consistently regardless of the simulated time scale.
