# Technical Introduction

This chapter provides a concise technical overview of Promovolve's architecture and algorithms. For the motivation behind these design choices, see [Why Promovolve?](./why-promovolve.md).

## The Five Key Mechanisms

### 1. Periodic Batch Auction

Auctions happen when content is published or updated (scheduled crawl + 5-minute re-auctions), not on every page load. An LLM classifies page content into IAB categories, TaxonomyRankerEntity ranks categories by site-specific performance, and CategoryBidderEntity collects bids from eligible campaigns. Results are cached in DData.

### 2. Multi-Candidate Caching

Instead of a single auction winner, multiple candidates per ad slot are shortlisted with per-campaign diversity guarantees and stored in the ServeIndex (replicated in-memory via DData). This enables exploration at serve time without re-running the auction.

### 3. Thompson Sampling at Serve Time

When a user loads a page, Thompson Sampling selects among cached candidates:

```
score = sampledCTR × log(1 + CPM)
```

CTR is sampled from a Beta-Bernoulli posterior using time-bucketed statistics (1-minute granularity, 60-minute rolling window). The `log(1 + CPM)` term ensures higher bids have an advantage but CTR dominates — a creative that users actually click beats one that merely bids high.

### 4. Double DQN Bid Optimization

Each campaign runs a per-campaign reinforcement learning agent (8→64→64→5 neural network) that observes performance every 15 minutes and adjusts a bid multiplier. The agent learns to balance click maximization against budget pacing over multi-day episodes.

### 5. Self-Tuning PI Pacing

A PI controller with adaptive gains, traffic shape learning (separate weekday/weekend 24-hour profiles), oscillation detection, and leaky integrator anti-windup smooths budget delivery. It learns that traffic peaks at 10am and dips at 3pm, and adjusts automatically.

## The Result

Sub-millisecond ad serving. Continuous learning at five layers (per-request Thompson Sampling, 15-minute RL, per-auction category ranking, daily traffic shapes, continuous PI tuning). Graceful degradation when budgets exhaust. No user tracking. Publisher approval over every creative.

## Navigating This Book

- **[Architecture](./architecture/overview.md)** — Pekko cluster topology, entity hierarchy, data flow
- **[Auction](./auction/periodic-auction.md)** — The five phases of the periodic batch auction
- **[Serving](./serving/thompson-sampling.md)** — Thompson Sampling, cold start, fair selection
- **[Pacing](./pacing/overview.md)** — PI control, self-tuning, traffic shape learning
- **[RL](./rl/overview.md)** — DQN state space, reward function, training loop
- **[Distributed State](./distributed/serve-index.md)** — ServeIndex replication and consistency
- **[Comparison](./comparison/vs-traditional.md)** — Point-by-point mapping against traditional ad tech

Each chapter is self-contained. All formulas, thresholds, and constants come from the Scala source code.
