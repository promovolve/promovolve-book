# Chapter 7: A Week Later

Seven days have passed. Let's see what the system has learned.

## Takeshi's RL Agent Has a Strategy

On day 1, the agent's epsilon was 0.92 — nearly every action was random. By day 7, epsilon has decayed to about 0.15. The agent is now 85% exploitation, 15% exploration.

Its learned policy, visible in the Q-values:

**When budget is above 60% and it's before noon**: Bid aggressively (action 4: multiply by 1.2×). Morning traffic on Yuki's site has high CTR for travel content. Winning these impressions is worth paying more.

**When budget is below 30% with time remaining**: Pull back (action 0: multiply by 0.8×). Conserve what's left. Spreading thin across the afternoon produces more total clicks than burning out early.

**When CTR is high and spend rate is normal**: Hold (action 2: multiply by 1.0×). Things are working. Don't change what isn't broken.

**When overpacing (spend rate above 1.5×)**: Reduce immediately (action 0 or 1). The overspend penalty in the reward function trained this response. The agent learned that overpacing leads to negative rewards.

None of these rules were programmed. They emerged from the reward signal — clicks minus overspend penalty — and thousands of training steps on the replay buffer.

Meanwhile, the JR Rail Pass agent learned a different strategy. With a higher CPM ($8) and a larger budget, it can afford to bid aggressively in the morning and let pacing handle the afternoon. Its multiplier swings more widely: up to 1.4 in morning peaks, down to 0.7 in the evening. It learned that its high base CPM means it wins most auctions even at 0.7×.

Different campaigns, different budgets, different learned strategies. Each agent adapts to its own situation.

## Thompson Sampling Has Converged

After hundreds of impressions, the creative stats tell a clear story:

| Creative | Impressions | Clicks | Distribution | Mean CTR |
|----------|------------|--------|-------------|----------|
| Takeshi's Ryokan | 312 | 14 | Beta(15, 299) | 4.8% |
| JR Rail Pass | 287 | 8 | Beta(9, 280) | 3.1% |
| Hiking Gear Co | 89 | 1 | Beta(2, 89) | 2.2% |
| Pottery Workshop | 45 | 3 | Beta(4, 43) | 8.5% |

Takeshi's ryokan gets the most impressions — it has a proven CTR and a decent CPM. JR Rail Pass has a higher CPM but lower CTR; the scoring formula `sampledCTR × log(1 + CPM)` keeps them competitive but Takeshi's CTR advantage matters.

The pottery workshop is interesting. It has fewer impressions (it started later in the week) but its CTR is the highest — 8.5%. Its `Beta(4, 43)` distribution is still fairly wide, though. Thompson Sampling is giving it more exploration to confirm whether this high CTR is real or noise.

The hiking gear ad has mostly faded out. `Beta(2, 89)` samples near zero most of the time. It gets about 5% of impressions — just enough exploration to detect if something changes (new creative, seasonal shift). If the advertiser uploaded a better creative, the system would detect the improvement within hours.

Nobody made any of these allocation decisions. No one paused the hiking gear campaign or boosted the pottery workshop. The system found the right distribution through pure learning.

## The Category Ranker Has Opinions

The TaxonomyRankerEntity for Yuki's site has accumulated a week of data:

```
Travel:           Beta(45, 355)  — 11.3% CTR, tight distribution
Hiking/Camping:   Beta(8, 192)   — 4.0% CTR, fairly confident
East Asian Culture: Beta(5, 45)  — 10.0% CTR, still exploring
Food & Drink:     Beta(2, 28)    — 6.7% CTR, early data
```

Travel dominates — it gets the highest weight in most auctions. But East Asian Culture is a surprise performer. The pottery workshop (East Asian Culture category) is driving this. The ranker is giving East Asian Culture more auction weight, which means more bidding opportunities for advertisers in that category.

This creates a virtuous cycle: good category performance → more auction weight → more candidates → more data → better Thompson Sampling → better ads → higher CTR → higher category performance.

## Traffic Shapes Are Calibrated

The TrafficShapeTracker now has 7 days of hourly data for Yuki's site, blended with `dayAlpha = 0.2`:

```
Weekday profile:
  Hour  0-6:   1-2% each  (late night, minimal traffic)
  Hour  7:     4%          (morning commute)
  Hour  8-10: 10-12% each (peak reading time)
  Hour 11-13:  6-7% each  (lunch)
  Hour 14-17:  3-4% each  (afternoon lull)
  Hour 18-20:  7-9% each  (evening reading)
  Hour 21-23:  3-4% each  (winding down)
```

The PI controller uses this shape instead of a linear time fraction. At 10am, it knows 32% of daily traffic has typically passed (not 42% if you assumed linear). This means the pacing target at 10am is "have spent about 32% of budget" — not 42%. The result: budgets stretch correctly across the day's actual traffic pattern, not an imaginary uniform distribution.

## Pacing Has Self-Tuned

The PI controller has been adjusting itself:

- **Overpace multiplier**: Started at 2.0×. After detecting that Takeshi's campaign occasionally overpaced by 20% in the morning (the RL agent bidding up), it increased to 2.8×. This means the controller responds more aggressively to overspending — a correction learned from experience.

- **Spend ratio smoothing**: The adaptive EMA alpha settled at 0.25. The traffic on Yuki's site is moderately volatile (it spikes when she publishes a new article and posts to social media). The controller learned to smooth more than the default to avoid overreacting to these spikes.

## What Yuki Sees

Yuki checks her publisher dashboard:

```
This Week:
  Impressions served:  1,847
  Revenue:             $9.24
  Active advertisers:  4
  Top category:        Travel (58% of impressions)
  Approval queue:      2 new creatives pending review
```

The revenue isn't life-changing — it's a small blog. But the ads are relevant, the site is fast, and her readers haven't complained. She approves the two pending creatives (a Kyoto walking tour and a Japanese language school) and goes back to writing her next article.

## What Takeshi Sees

Takeshi checks his advertiser dashboard:

```
This Week:
  Impressions:  312
  Clicks:       14
  CTR:          4.5%
  Spend:        $1.56
  Avg CPC:      $0.11
```

Fourteen people clicked through to his ryokan's booking page from a travel blog — exactly the kind of reader he wanted to reach. His cost per click is $0.11. He didn't have to manage bids, adjust targeting, or learn a DSP interface. He uploaded a photo, set a budget, and the system did the rest.

He increases his daily budget to $30.

## The System Keeps Learning

Day 8 begins. Epsilon decays to 0.05 — the RL agent's floor. From now on, 95% of actions follow the learned policy, 5% continue to explore. The agent isn't done learning — it will adapt to seasonal changes, new competitors, and traffic shifts — but the wild random exploration of the first week is over.

The system has found its rhythm: a travel blog with relevant ads, a local ryokan reaching interested travelers, creative performance continuously optimized, budgets paced smoothly, all running on sub-millisecond serving with no user tracking.

This is what advertising looks like when you start with the content instead of the user.

---

*Technical deep dives: [RL Training Loop](../rl/training.md) · [State Space](../rl/state-space.md) · [Traffic Shape Learning](../pacing/traffic-shape.md) · [Key Innovations](../comparison/innovations.md)*
