# Rate Tracking (EMA)

正確なレート測定はペーシングシステムの基盤です。Promovolveは、1秒のスライディングウィンドウを持つ同期的な**Exponential Moving Average (EMA)**を使用しています。

## TrafficObserver

`pacing/TrafficObserver.scala`より：

```scala
class TrafficObserver(
  rateWindowMs: Long = 1000,    // 1-second window
  rateEmaAlpha: Double = 0.3     // EMA smoothing factor
)
```

### 記録（同期的）

すべてのSelectリクエストに対して、非同期処理の**前に**呼び出されます：

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

## EMAの挙動

α = 0.3の場合：

```
Window 1: instant=100, smoothed = 0.3×100 + 0.7×0   = 30
Window 2: instant=120, smoothed = 0.3×120 + 0.7×30  = 57
Window 3: instant=110, smoothed = 0.3×110 + 0.7×57  = 73
Window 4: instant=105, smoothed = 0.3×105 + 0.7×73  = 83
Window 5: instant=100, smoothed = 0.3×100 + 0.7×83  = 88
```

約5ウィンドウ以内に収束します。スパイクは減衰されます：

```
Window 6: instant=500, smoothed = 0.3×500 + 0.7×88  = 212  (spike dampened)
Window 7: instant=100, smoothed = 0.3×100 + 0.7×212 = 178  (recovering)
```

## なぜ同期的なのか？

レートトラッキングの呼び出しは同期的で、配信リクエストを処理するのと同じスレッド上で実行されます。これにより以下が保証されます：
- すべてのリクエストが正確に1回カウントされる
- 非同期更新による競合状態が発生しない
- ペーシングゲートの実行時にレートが常に最新である

## 安定化

Grace periodは、EMAが安定したとみなされるまでに`EmaStabilizationWindows = 3`ウィンドウ分のデータを必要とします。これらの初期ウィンドウの間、ノイズの多いレート推定に基づくPI補正を防ぐためにgrace periodがアクティブのまま維持されます。

## PI controlでの使用

平滑化されたレートは基本スロットル計算に入力されます：

```
baseTargetImpsPerSec = (dailyBudget / dayDurationSeconds) / (avgCpm / 1000.0)
baseThrottle = 1.0 - (baseTargetImpsPerSec / requestRate)
```

ここで`requestRate`はTrafficObserverからのEMA平滑化レートです。
