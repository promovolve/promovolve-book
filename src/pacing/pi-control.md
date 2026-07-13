# PI Control Loop

Promovolve uses a **self-tuning Proportional-Integral (PI) controller** with fixed base gains (Kp = 0.5, Ki = 0.3) refined at runtime by self-tuning, asymmetric response, a leaky integrator, and oscillation detection.

## Core Algorithm (from AdaptivePacing.scala)

```
// 1. Hard stops
if remainingBudget ≤ 0: return 1.0
if remainingHours ≤ 0: return 1.0

// 2. Base throttle from target impressions per second
baseTargetImpsPerSec = (dailyBudget / dayDurationSec) / (avgCpm / 1000.0)

// 3. Apply traffic shape multiplier (if available)
if trafficShape exists:
    shapeMultiplier = trafficShape.relativeVolumeWithFeedforward(elapsed, feedforwardWindow)
    baseTargetImpsPerSec *= shapeMultiplier

baseThrottle = 1.0 - (baseTargetImpsPerSec / requestRate)

// 4. Compute error
error = 1.0 - spendRatio
// positive → under-spending, negative → over-spending

// 5. Asymmetric gains
if error < 0 (over-pacing):
    effectiveKp = kp × overpaceGainMultiplier    // default: kp × 2.0
    effectiveKi = ki × overpaceGainMultiplier
else:
    effectiveKp = kp
    effectiveKi = ki

// 6. Leaky integrator (anti-windup)
integralError *= IntegralDecayFactor    // 0.995 per update
integralError += error × dt
integralError = clamp(integralError, -1.0, 1.0)

// 7. PI adjustment
adjustment = effectiveKp × error + effectiveKi × integralError

// 8. Final throttle
finalThrottle = clamp(baseThrottle - adjustment, 0.0, MaxThrottleProb)
// MaxThrottleProb = 0.99 (1.0 reserved for hard-stop)
```

## Spend Ratio Smoothing

Raw spend ratio is noisy. The system applies EMA smoothing:

```
smoothedSpendRatio = α × rawSpendRatio + (1 - α) × previousSmoothed
```

Default `SpendRatioSmoothingAlpha = 0.3`, but the alpha itself is **self-tuned**:

- If oscillation detected (stddev > 0.08): decrease alpha toward `MinSmoothingAlpha` (0.1) — more dampening
- If stable (stddev < 0.04): increase alpha toward `MaxSmoothingAlpha` (0.5) — more responsive

## Self-Tuning Overpace Multiplier

The asymmetric gain multiplier is not fixed — it adapts over time:

```
Every 20 samples (and at least 500ms apart):
  if persistent overspend (avg spendRatio > 1.05):
      overpaceMultiplier *= OverspendBoostFactor (1.15)
      capped at MaxOverpaceGainMultiplier (5.0)
  elif well-paced (avg spendRatio < 1.02):
      overpaceMultiplier *= WellPacedDecayFactor (0.95)
      floored at MinOverpaceGainMultiplier (1.5)
```

This means the system becomes progressively more aggressive at correcting overspend if it keeps recurring, and relaxes when pacing is good.

## Leaky Integrator

The integral term decays by `IntegralDecayFactor = 0.995` on every update. This prevents **windup** — where a prolonged error accumulates a large integral that then overshoots when conditions change.

The integral is also hard-clamped to [-1.0, 1.0] as a safety bound.

## Cross-Day Learning

At day rollover, the system checks if the budget was exhausted too early:

```scala
prepareForRollover(budgetExhausted, remainingFraction):
  if budgetExhausted && remainingFraction > EarlyExhaustionThreshold (0.05):
      overpaceMultiplier *= (1.0 + remainingFraction)
      // If exhausted with 30% of day remaining → boost by 1.3x
```

This carries forward the lesson: "I should have been more conservative" into the next day's pacing, even though the PI state itself resets.
