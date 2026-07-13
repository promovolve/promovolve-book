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

Production constructs every tracker with `interpolateVolumes = true`, so
the pacing rate multiplier ramps across hour boundaries instead of
stepping at each one; the sharp default exists for tests.

### Separate Weekday/Weekend Profiles

```scala
private val weekdayShape: Array[Double] = Array.fill(24)(1.0)
private val weekendShape: Array[Double] = Array.fill(24)(1.0)
private val todayCount: Array[Long] = Array.fill(24)(0L)  // reset daily
```

The active shape is selected via `setDayType(isWeekend: Boolean)` at the start of each day.

## Recording & Learning

Every arriving ad request is recorded — the shape measures **demand
opportunities** (requests), not impressions or spend:

```
recordRequest(bucket, time):
    todayCount[bucket] += 1
```

### Bootstrap: first day only

A brand-new tracker (no snapshot, no rollover yet) also applies a
per-bucket EMA as each hour completes, so pacing gets rough shape
awareness within the very first day:

```
observation = requestsInBucket / max(1.0, emaBucketRequests)
shape[bucket] = α × observation + (1 - α) × shape[bucket]
emaBucketRequests = α × requestsInBucket + (1 - α) × emaBucketRequests
```

This bootstrap mode switches off permanently at the first day rollover
(or when a persisted shape is restored). From then on, **a learned shape
changes only at the daily blend below** — snapshots, restores, and
restarts never mutate it mid-day.

### Day Rollover Blending

At end of day:

```
rolloverDay(dayAlpha = 0.2):
    todayNormalized[i] = todayCount[i] / avgCount
    shape[i] = 0.2 × todayNormalized[i] + 0.8 × shape[i]
    reset todayCount
```

The 0.2 blend rate means about 5 days of data to significantly influence the profile. The weekday and weekend shapes each blend on their own days, and **both persist to Postgres and restore on restart** — snapshots are written hourly, at each rollover, and on shutdown, so learned patterns survive deploys.

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

## Learn-Only, By Design

Shapes are **never configured by hand** — there is deliberately no
import API or UI. A hand-authored shape encodes intuition rather than
measurement, and a wrong shape paces worse than the flat one (flat
degrades to exactly linear pacing). The tracker is the only writer; the
learned shapes are visible on the publisher's Floor Decisions page as
two hourly bar rows (weekday and weekend) and exported read-only via
the site stats endpoint.

The one related knob is `PacingConfig.warmupMode`: when `true`, the
system records traffic patterns but does not serve ads — useful for
learning the traffic shape of a new site before enabling monetization.
Exiting warmup is a manual decision.
