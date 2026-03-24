# Traffic Shape Learning

Webトラフィックは日次パターンに従います。Promovolveは、24時間のバケットを持つ`TrafficShapeTracker`を使用して、平日と週末を別々に学習します。

## TrafficShapeTracker（ソースコードより）

```scala
class TrafficShapeTracker(
  bucketCount: Int = 24,        // hourly buckets
  alpha: Double = 0.1,          // EMA learning rate
  interpolateVolumes: Boolean = false  // sharp vs smooth peaks
)
```

### 平日/週末の分離プロファイル

```scala
private val weekdayShape: Array[Double] = Array.fill(24)(1.0)
private val weekendShape: Array[Double] = Array.fill(24)(1.0)
private val todayCount: Array[Long] = Array.fill(24)(0L)  // reset daily
```

アクティブなシェイプは、各日の開始時に`setDayType(isWeekend: Boolean)`で選択されます。

## 記録と学習

### リクエストごとの記録

```
recordRequest(bucket, time):
    todayCount[bucket] += 1
```

### バケット境界の変更時

トラフィックが新しい時間帯に移行するとき：

```
observation = requestsInBucket / max(1.0, emaBucketRequests)
shape[bucket] = α × observation + (1 - α) × shape[bucket]
emaBucketRequests = α × requestsInBucket + (1 - α) × emaBucketRequests
```

### 日のロールオーバーブレンディング

日の終わりに：

```
rolloverDay(dayAlpha = 0.2):
    todayNormalized[i] = todayCount[i] / avgCount
    shape[i] = 0.2 × todayNormalized[i] + 0.8 × shape[i]
    reset todayCount
```

0.2のブレンドレートは、プロファイルに大きな影響を与えるまでに約5日分のデータが必要であることを意味します。

## 期待消化額のためのCDF

トラフィックシェイプは、期待消化額の計算において線形時間割合を置き換える**累積分布関数**を提供します：

```
cumulativeFractionAtTime(elapsedSeconds):
    bucket = floor(elapsedSeconds / bucketDurationSec)
    fractionIntoBucket = (elapsedSeconds % bucketDurationSec) / bucketDurationSec

    prevCumulative = sum(shape[0..bucket-1])
    currentContribution = shape[bucket] × fractionIntoBucket

    return (prevCumulative + currentContribution) / sum(all buckets)
```

**Traffic shapeなし**：`expectedSpendFraction = elapsedTime / totalTime`（線形）
**Traffic shapeあり**：`expectedSpendFraction = cumulativeFractionAtTime(elapsed)`（シェイプ適用）

## Relative Volume（基本目標用）

基本目標インプレッション/秒は、現在の時間帯のrelative volumeでスケーリングされます：

```
relativeVolumeWithFeedforward(elapsedSeconds, feedforwardWindow):
    bucket = current hour
    currentVol = shape[bucket]
    nextVol = shape[(bucket + 1) % 24]

    if feedforwardWindow > 0 AND near end of bucket:
        // Smooth transition using ease-in-out curve
        blendFactor = position within feedforward window [0, 1]
        smoothBlend = blendFactor² × (3 - 2 × blendFactor)
        effectiveVol = currentVol + smoothBlend × (nextVol - currentVol)
    else:
        effectiveVol = currentVol

    avgVol = sum(all buckets) / 24
    return effectiveVol / avgVol
```

feedforwardウィンドウ（デフォルト：0.0 = 無効）により、システムは次の時間帯のトラフィックパターンを予測し、バケット境界の前に調整を開始できます。

## 変動性の測定

シェイプバケットの変動係数（CV = stddev / mean）は、PIゲインの自動チューニングに使用されます：
- 低CV → 均一なトラフィック → 穏やかなPIゲイン
- 高CV → バースト的なトラフィック → 積極的なPIゲイン

## サイトレベルの設定

サイトごとのトラフィックシェイプは`PacingConfig`で事前設定できます：

```scala
PacingConfig(
  weekdayShapeVolumes: Option[Vector[Double]],  // 24 hourly values
  weekendShapeVolumes: Option[Vector[Double]],
  dayDurationSeconds: Int = 86400,
  warmupMode: Boolean = false
)
```

`warmupMode = true`の場合、システムはトラフィックパターンを記録しますが広告は配信しません — 収益化を有効にする前に新しいサイトのトラフィックシェイプを学習するのに便利です。
