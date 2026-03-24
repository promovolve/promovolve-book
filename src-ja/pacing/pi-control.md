# PI Control Loop

Promovolveは、適応的ゲイン、非対称応答、leaky integrator、振動検出を備えた**自己チューニングProportional-Integral (PI) controller**を使用しています。

## コアアルゴリズム（AdaptivePacing.scalaより）

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

## Spend Ratioの平滑化

生のspend ratioはノイズが多いため、システムはEMA平滑化を適用します：

```
smoothedSpendRatio = α × rawSpendRatio + (1 - α) × previousSmoothed
```

デフォルトの`SpendRatioSmoothingAlpha = 0.3`ですが、alpha自体が**自己チューニング**されます：

- 振動が検出された場合（stddev > 0.08）：alphaを`MinSmoothingAlpha`（0.1）に向けて減少 — より多くの減衰
- 安定している場合（stddev < 0.04）：alphaを`MaxSmoothingAlpha`（0.5）に向けて増加 — より応答性が高い

## 自己チューニングOverpace Multiplier

非対称ゲイン乗数は固定ではなく、時間とともに適応します：

```
Every 20 samples (and at least 500ms apart):
  if persistent overspend (avg spendRatio > 1.05):
      overpaceMultiplier *= OverspendBoostFactor (1.15)
      capped at MaxOverpaceGainMultiplier (5.0)
  elif well-paced (avg spendRatio < 1.02):
      overpaceMultiplier *= WellPacedDecayFactor (0.95)
      floored at MinOverpaceGainMultiplier (1.5)
```

これにより、過剰消化が繰り返し発生する場合はシステムがより積極的に補正するようになり、ペーシングが良好な場合は緩和されます。

## トラフィック変動による適応的ゲイン

PIゲインはリクエストレートの変動係数（CV）に応じてスケーリングされます：

| Volatility (CV) | Kp | Ki | Behavior |
|-----------------|----|----|----------|
| 0.0 (flat) | 0.3 | 0.2 | 均一なトラフィックに対する穏やかな補正 |
| 0.5 (typical) | 0.5 | 0.3 | 中程度の応答 |
| 1.0+ (spiky) | 1.0 | 0.6 | バースト的なトラフィックに対する積極的な補正 |

ゲインは、TrafficShapeTrackerから観測されたCVに基づいて、これらのポイント間で線形補間されます。

## Leaky Integrator

積分項は更新のたびに`IntegralDecayFactor = 0.995`で減衰します。これにより**windup**を防止します — 長時間のエラーが大きな積分を蓄積し、条件が変わったときにオーバーシュートすることを防ぎます。

積分はまた、安全境界として[-1.0, 1.0]にハードクランプされます。

## 日跨ぎ学習

日のロールオーバー時に、システムは予算が早期に消尽されたかどうかを確認します：

```scala
prepareForRollover(budgetExhausted, remainingFraction):
  if budgetExhausted && remainingFraction > EarlyExhaustionThreshold (0.05):
      overpaceMultiplier *= (1.0 + remainingFraction)
      // If exhausted with 30% of day remaining → boost by 1.3x
```

これは「もっと保守的であるべきだった」という教訓を翌日のペーシングに持ち越します。PI状態自体はリセットされますが、この学習は引き継がれます。
