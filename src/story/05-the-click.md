# Chapter 5: The Click

The reader clicks on Takeshi's ryokan ad. Their browser follows the click URL:

```
GET /v1/click?pub=yuki-site&url=...&cid=ryokan-001&tok=a8f3...&rid=01HX...
```

This single click sets off a cascade of learning across the system.

## Click Validation

The TrackRoutes handler validates the click:

1. **HMAC verification**: The `tok` parameter is checked against a signature computed from the publisher's secret, the URL parameters, and the request ID. If anyone tampered with the URL — changed the creative ID, the campaign, or the CPM — the signature won't match. `403 Forbidden`.

2. **Freshness check**: The `b` parameter encodes a time bucket (1-minute granularity). If the click URL is more than 3 minutes old, it's rejected. This limits the replay window.

3. **Replay guard**: The canonical URL (including the unique request ID) is checked against a sharded bloom filter. If this exact click was already recorded, it's a duplicate. `409 Conflict`.

All three pass. The click is legitimate. `204 No Content` — acknowledged.

## Three Systems Learn from This Click

The `LearningEventLog` routes the click event to three different parts of the system, each learning at a different timescale.

### 1. TaxonomyRankerEntity — Category Ranking (Days)

The click event reaches the ranker for Travel on Yuki's site:

```
Before: Beta(12, 88)  — mean CTR: 12%
After:  Beta(13, 88)  — mean CTR: 12.9%
```

One more click in the numerator. The Travel category's score on Yuki's site ticks up slightly. Over weeks, this shapes which categories get prioritized in auctions for this site. A category that consistently gets clicks rises; one that doesn't fades.

The ranker uses a 7-day half-life decay — old impressions and clicks gradually lose weight. This means the ranking adapts to seasonal changes: Travel might dominate in autumn when people plan trips, while Food & Drink rises in December when people search for holiday dining.

### 2. AdServer — Creative Thompson Sampling (Minutes)

The click reaches Takeshi's creative stats on the AdServer:

```
Before: Beta(1, 1)   — uniform, no data
After:  Beta(2, 1)   — heavily skewed toward high CTR
```

This is one impression, one click — a 100% click rate. Obviously that won't last, but it gives Takeshi's creative a strong initial signal. The Beta distribution is now `Beta(2, 1)`, which samples high most of the time. For the next few impressions, this creative will be favored by Thompson Sampling.

After 20 more impressions and 1 more click, it'll be `Beta(3, 19)` — about 14% CTR. Still good, but more realistic. The distribution is narrowing toward the truth.

The stats use a 60-minute rolling window with 1-minute buckets. This creative's strong early performance will influence serving decisions for the next hour, then the data starts aging out and the system stays responsive to changes.

### 3. Dashboard Projection (Seconds)

The click is written to the tracking journal — a buffered Pekko Stream that batches events and writes them to PostgreSQL. Within a few seconds, Takeshi's advertiser dashboard updates:

```
Impressions: 1  |  Clicks: 1  |  CTR: 100%  |  Spend: $0.005
```

Obviously these numbers will normalize as more data comes in. But Takeshi can see that his campaign is live and getting engagement.

## The Compound Effect

This is one click. But notice what it touched:

| System | What it learned | Timescale | Effect |
|--------|----------------|-----------|--------|
| Category Ranker | Travel works on this site | Days-weeks | Travel ads get more auction weight |
| Creative Stats | This creative gets clicks | Minutes-hours | Thompson Sampling favors it; quality-adjusted clearing also lowers what Takeshi pays |
| Dashboard | Campaign is performing | Seconds | Advertiser sees results |

Each system learns at its own pace. Thompson Sampling reacts within minutes — the next reader might see a different ad mix because of this click. The category ranker reacts over weeks — Travel's weight on Yuki's site gradually increases.

There's no campaign-side bid optimizer adjusting Takeshi's price after the click. The auction handles that automatically: a higher sampled CTR means a lower clearing CPM under quality-adjusted second-price pricing. Takeshi gets *cheaper* impressions for making creatives readers actually click, with no agent in the loop.

## Meanwhile, the Other Creative

While Takeshi's ryokan ad got a click, the hiking gear ad has had 3 impressions and zero clicks. Its distribution is now `Beta(1, 4)` — mean CTR about 20%, but the distribution is starting to lean toward lower values.

Thompson Sampling will still occasionally select it — the `Beta(1, 4)` distribution can sample anywhere from 0 to 0.8, just with lower probability of sampling high. If it gets a click on its next impression, it recovers immediately: `Beta(2, 4)` is a much more competitive distribution.

If it continues to get no clicks, it fades out naturally. By the time it has 50 impressions and 0 clicks — `Beta(1, 51)` — its samples will almost always be near zero. It effectively stops being shown, without anyone making a decision to stop it.

This is the beauty of Thompson Sampling: bad creatives don't need to be manually paused. They extinguish themselves.

---

*Technical deep dives: [Beta-Bernoulli Model](../serving/beta-bernoulli.md) · [Scoring Formula](../serving/scoring-formula.md) · [Learning Mechanisms](../comparison/learning.md)*
