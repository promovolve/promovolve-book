# Learning Mechanisms

Both traditional ad tech and Promovolve learn from feedback, but at different levels and timescales. The fundamental difference: traditional RTB learns about **users**, Promovolve learns about **content** and **creatives**.

## Traditional: RTB Feedback Loops

### DSP-Side
- **Bid values**: Learn from win/loss notifications what impressions are worth
- **Audience targeting**: Learn from conversions which user segments are valuable
- Learning happens at the **bid level**, not the creative level

### Exchange-Side
- **Floor prices**: Learn from bid distributions to set minimum acceptable bids

### Limitations
- No exploration: only learns from wins, never discovers if alternative creatives would perform better
- User-dependent: requires cookies, profiles, cross-site tracking

## Promovolve: Five-Layer Learning

Promovolve does not run any campaign-side bid optimizer. With quality-adjusted second-price clearing (see [Winner Selection](./winner-selection.md)), bid shading is counterproductive — the auction mechanism already extracts honest bids. The learning that does happen runs on the publisher and content sides.

### Layer 1: Thompson Sampling (Per-Request)

**What**: Which creative performs best for a given slot
**Timescale**: Every impression updates `CreativeStats` (1-minute buckets, 60-minute window)
**How**: Bayesian posterior update `Beta(clicks+1, impressions-clicks+1)`

```
Before impression: Beta(5, 95)  → mean 5%
User clicks:       Beta(6, 95)  → mean 5.9%
```

This is the fastest loop — sub-second feedback incorporated into the next serve decision.

### Layer 2: Publisher-Side Floor CPM RL (Per-Site, Slow)

**What**: The minimum CPM the publisher will accept on a given site
**Timescale**: Adjustments evaluated against rolling served revenue
**How**: A sweep optimizer tests candidate floors for a measurement window each, compares real served revenue, and keeps the best — re-sweeping continuously so the floor tracks demand up and snaps down when demand leaves

The agent is **gated**: it only activates when bid spread is wide enough that floor adjustments can plausibly change outcomes. In a homogeneous market where every bidder offers the same CPM, the agent stays put — moving the floor would just collapse fill without raising revenue.

There is no RL agent anywhere in the system — this layer is deliberately measurement, not learning. It runs on behalf of the publisher; advertisers see honest second-price clearing regardless of what the floor does.

### Layer 3: Category Ranking (Per Auction)

**What**: Which content categories are valuable for each site
**Timescale**: Updated every auction, 7-day half-life decay, 14-day max age
**How**: Thompson Sampling with `Beta(prior_α + clicks, prior_β + non_clicks)`

```
Category "sports" on site X:
  Prior: Beta(1, 1) → weight sampled ~0.5
  After data: Beta(15, 95) → weight sampled ~0.14
```

Slow loop, learning site-level category affinities.

### Layer 4: Traffic Shape (Per Day)

**What**: Hourly traffic patterns (separate weekday/weekend)
**Timescale**: Daily rollover with `dayAlpha = 0.2` blend
**How**: 24-bucket EMA with `alpha = 0.1`

Adjusts pacing targets to match actual traffic distribution.

### Layer 5: PI Self-Tuning (Continuous)

**What**: Optimal aggressiveness for overpace correction
**Timescale**: Every 20 samples, min 500ms interval
**How**: Overpace multiplier adapts between 1.5× and 5.0× based on persistent overspend detection

## Reader-Driven Signals (Not Learning, But Adjacent)

Promovolve also accepts an explicit signal from the reader: the **dog-ear**. When a reader folds the corner of a creative, the pin lives in their browser and re-encounters of that advertiser surface the bookmarked creative. This isn't a learning loop in the statistical sense — it's a direct reader vote, more reliable than any inferred preference. See [Why Promovolve?](../why-promovolve.md#readers-can-dog-ear-an-ad).

## Comparison

| Dimension | Traditional RTB | Promovolve |
|-----------|----------------|------------|
| What's optimized | Bid price | Creative + category + pacing + floor |
| Exploration | None | Built-in (Thompson Sampling) |
| Learning layers | 1 (bid-level) | 5 (per-request through publisher-side floor sweep) |
| User targeting | Yes (profile) | No (content-based) |
| Reader signal | None | Dog-ear pin (explicit bookmark) |
| Privacy impact | High (tracking) | Low (no user profiles) |
| Cold start | Historical bid data | Bayesian priors + round-robin warmup |
| Adaptability | Real-time bids | TS adapts per-request; floor sweep converges over days |
