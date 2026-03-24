# Rate Tracking (EMA)

Accurate rate measurement is the foundation of the pacing system. Promovolve uses a synchronous **Exponential Moving Average (EMA)** with a 1-second sliding window.

## TrafficObserver

From `pacing/TrafficObserver.scala`:

```scala
class TrafficObserver(
  rateWindowMs: Long = 1000,    // 1-second window
  rateEmaAlpha: Double = 0.3     // EMA smoothing factor
)
```

### Recording (Synchronous)

Called on every Select request, **before** any async operations:

```scala
recordRequest(nowMs):
  if windowStartMs == 0: windowStartMs = nowMs

  requestsInWindow += 1
  windowElapsed = nowMs - windowStartMs

  if windowElapsed >= rateWindowMs:   // window closed
    windowSec = windowElapsed / 1000.0
    instantRate = requestsInWindow / windowSec
    smoothedRate = α × instantRate + (1 - α) × smoothedRate

    windowStartMs = nowMs
    requestsInWindow = 0

  return smoothedRate
```

## EMA Behavior

With α = 0.3:

```
Window 1: instant=100, smoothed = 0.3×100 + 0.7×0   = 30
Window 2: instant=120, smoothed = 0.3×120 + 0.7×30  = 57
Window 3: instant=110, smoothed = 0.3×110 + 0.7×57  = 73
Window 4: instant=105, smoothed = 0.3×105 + 0.7×73  = 83
Window 5: instant=100, smoothed = 0.3×100 + 0.7×83  = 88
```

Converges within ~5 windows. Spikes are dampened:

```
Window 6: instant=500, smoothed = 0.3×500 + 0.7×88  = 212  (spike dampened)
Window 7: instant=100, smoothed = 0.3×100 + 0.7×212 = 178  (recovering)
```

## Why Synchronous?

The rate tracking call is synchronous and runs on the same thread handling the serve request. This ensures:
- Every request is counted exactly once
- No race conditions from async updates
- Rate is always current when the pacing gate runs

## Stabilization

The grace period requires `EmaStabilizationWindows = 3` windows of data before the EMA is considered stable. During these initial windows, the grace period remains active to prevent PI corrections based on noisy rate estimates.

## Usage in PI Control

The smoothed rate feeds into the base throttle calculation:

```
baseTargetImpsPerSec = (dailyBudget / dayDurationSeconds) / (avgCpm / 1000.0)
baseThrottle = 1.0 - (baseTargetImpsPerSec / requestRate)
```

Where `requestRate` is the EMA-smoothed rate from TrafficObserver.
