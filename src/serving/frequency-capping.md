# Frequency Capping

Frequency capping limits how many times a single user sees ads from the same advertiser, preventing ad fatigue.

## How It Works

### Per-User, Per-Creative Caps

Each campaign can specify a `frequencyCap: Option[Int]` — the maximum number of impressions per user for creatives from that campaign.

### Check Process

At serve time, before the pacing gate:

```scala
// 1. Filter candidates with frequency caps
val cappedCandidates = candidates.filter(_.frequencyCap.isDefined)

// 2. Group by advertiser
val byAdvertiser = cappedCandidates.groupBy(_.advertiserId)

// 3. Query each AdvertiserEntity for user impression counts
//    Timeout: 100ms, fail-open

// 4. Filter
filtered = candidates.filter { c =>
  c.frequencyCap match {
    case None      => true  // No cap, always eligible
    case Some(cap) =>
      val impressions = impressionCountsMap.getOrElse(c.creativeId, 0)
      impressions < cap
  }
}
```

### Fail-Open Semantics

If the AdvertiserEntity doesn't respond within **100ms**:

```
On timeout → include all candidates from that advertiser
```

**Why fail-open?** Frequency capping is a quality optimization. The alternative (fail-closed) would mean network issues cause no ads to show. It's better to occasionally over-serve than to block serving entirely.

## Pipeline Position

Frequency capping runs **after** content recency but **before** the pacing gate and Thompson Sampling:

```
Content recency → Frequency cap → Rate tracking → Pacing gate → Thompson Sampling
```

Running before TS ensures:
- TS never wastes exploration on capped candidates
- The filtered pool may be smaller but TS works correctly with any size ≥ 1
- If all candidates are capped, no ad is shown (NoCandidates)

## Interaction with Pacing

Frequency capping and pacing are independent filters. A candidate must pass both:

```
Candidates → Frequency Filter → Pacing Gate → Thompson Sampling
```

Running frequency cap first reduces the number of candidates the pacing gate needs to evaluate.
