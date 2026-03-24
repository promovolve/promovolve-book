# Traffic Shape Learning

Web traffic follows daily patterns. Promovolve learns these patterns separately for weekdays and weekends using a `TrafficShapeTracker` with 24 hourly buckets.

## TrafficShapeTracker (from source)

```scala
class TrafficShapeTracker(
  bucketCount: Int = 24,        // hourly buckets
  alpha: Double = 0.1,          // EMA learning rate
  interpolateVolumes: Boolean = false  // sharp vs smooth peaks
)
```

### Separate Weekday/Weekend Profiles

```scala
private val weekdayShape: Array[Double] = Array.fill(24)(1.0)
private val weekendShape: Array[Double] = Array.fill(24)(1.0)
private val todayCount: Array[Long] = Array.fill(24)(0L)  // reset daily
```

The active shape is selected via `setDayType(isWeekend: Boolean)` at the start of each day.

## Recording & Learning

### Per-Request Recording

```
recordRequest(bucket, time):
    todayCount[bucket] += 1
```

### On Bucket Boundary Change

When traffic moves to a new hour:

```
observation = requestsInBucket / max(1.0, emaBucketRequests)
shape[bucket] = α × observation + (1 - α) × shape[bucket]
emaBucketRequests = α × requestsInBucket + (1 - α) × emaBucketRequests
```

### Day Rollover Blending

At end of day:

```
rolloverDay(dayAlpha = 0.2):
    todayNormalized[i] = todayCount[i] / avgCount
    shape[i] = 0.2 × todayNormalized[i] + 0.8 × shape[i]
    reset todayCount
```

The 0.2 blend rate means about 5 days of data to significantly influence the profile.

## CDF for Expected Spend

The traffic shape provides a **cumulative distribution function** that replaces the linear time fraction in expected spend calculations:

```
cumulativeFractionAtTime(elapsedSeconds):
    bucket = floor(elapsedSeconds / bucketDurationSec)
    fractionIntoBucket = (elapsedSeconds % bucketDurationSec) / bucketDurationSec

    prevCumulative = sum(shape[0..bucket-1])
    currentContribution = shape[bucket] × fractionIntoBucket

    return (prevCumulative + currentContribution) / sum(all buckets)
```

**Without traffic shape**: `expectedSpendFraction = elapsedTime / totalTime` (linear)
**With traffic shape**: `expectedSpendFraction = cumulativeFractionAtTime(elapsed)` (shaped)

## Relative Volume (for Base Target)

The base target impressions-per-second is scaled by the current hour's relative volume:

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

The feedforward window (default: 0.0 = disabled) allows the system to anticipate the next hour's traffic pattern and begin adjusting before the bucket boundary.

## Volatility Measurement

The coefficient of variation (CV = stddev / mean) of the shape buckets is used to auto-tune PI gains:
- Low CV → uniform traffic → gentle PI gains
- High CV → spiky traffic → aggressive PI gains

## Site-Level Configuration

Per-site traffic shapes can be pre-configured via `PacingConfig`:

```scala
PacingConfig(
  weekdayShapeVolumes: Option[Vector[Double]],  // 24 hourly values
  weekendShapeVolumes: Option[Vector[Double]],
  dayDurationSeconds: Int = 86400,
  warmupMode: Boolean = false
)
```

When `warmupMode = true`, the system records traffic patterns but does not serve ads — useful for learning the traffic shape of a new site before enabling monetization.
