# Learning Mechanisms

Both traditional ad tech and Promovolve learn from feedback, but at different levels and timescales.

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

## Promovolve: Three-Layer Learning

### Layer 1: Thompson Sampling (Per-Request)

**What**: Which creative performs best for a given slot
**Timescale**: Every impression updates `CreativeStats` (1-minute buckets, 60-minute window)
**How**: Bayesian posterior update `Beta(clicks+1, impressions-clicks+1)`

```
Before impression: Beta(5, 95)  → mean 5%
User clicks:       Beta(6, 95)  → mean 5.9%
```

This is the fastest loop — sub-second feedback incorporated into the next serve decision.

### Layer 2: DQN Bid Optimization (Every 15 Minutes)

**What**: Optimal bid multiplier given budget, pacing, and performance
**Timescale**: 15-minute observation windows, convergence over ~8 days
**How**: Double DQN with 8-dim state, 5 actions, click reward - overspend penalty

```
State → Q-network → action → bidMultiplier adjustment
```

Medium timescale, learning competitive dynamics and pacing patterns.

### Layer 3: Category Ranking (Per Auction)

**What**: Which content categories are valuable for each site
**Timescale**: Updated every auction, 7-day half-life decay, 14-day max age
**How**: Thompson Sampling with `Beta(prior_α + clicks, prior_β + non_clicks)`

```
Category "sports" on site X:
  Prior: Beta(1, 1) → weight sampled ~0.5
  After data: Beta(15, 95) → weight sampled ~0.14
```

Slowest loop, learning site-level category affinities.

### Layer 4: Traffic Shape (Per Day)

**What**: Hourly traffic patterns (separate weekday/weekend)
**Timescale**: Daily rollover with `dayAlpha = 0.2` blend
**How**: 24-bucket EMA with `alpha = 0.1`

Adjusts pacing targets to match actual traffic distribution.

### Layer 5: PI Self-Tuning (Continuous)

**What**: Optimal aggressiveness for overpace correction
**Timescale**: Every 20 samples, min 500ms interval
**How**: Overpace multiplier adapts between 1.5x and 5.0x based on persistent overspend detection

## Comparison

| Dimension | Traditional RTB | Promovolve |
|-----------|----------------|------------|
| What's optimized | Bid price | Creative + bid + category + pacing |
| Exploration | None | Built-in (Thompson Sampling) |
| Learning layers | 1 (bid-level) | 5 (per-request through daily) |
| User targeting | Yes (profile) | No (content-based) |
| Privacy impact | High (tracking) | Low (no user profiles) |
| Cold start | Historical bid data | Bayesian priors + round-robin warmup |
| Adaptability | Real-time bids | RL converges over days, TS adapts per-request |
