# Technical Introduction

This chapter provides a concise technical overview of Promovolve's architecture and algorithms. For the motivation behind these design choices, see [Why Promovolve?](./why-promovolve.md).

## The Six Key Mechanisms

### 1. Periodic Batch Auction

Auctions happen when content is first classified (on-demand classification + 5-minute re-auctions), not on every page load. An LLM classifies page content into IAB categories, TaxonomyRankerEntity ranks categories by site-specific performance, and CategoryBidderEntity collects bids from eligible campaigns. Results are cached in DData.

### 2. Multi-Candidate Caching

Instead of a single auction winner, multiple candidates per ad slot are shortlisted with per-campaign diversity guarantees and stored in the ServeIndex (replicated in-memory via DData). This enables exploration at serve time without re-running the auction.

### 3. Thompson Sampling at Serve Time

When a user loads a page, Thompson Sampling selects among cached candidates:

```
score = sampledCTR × CPM^α
```

CTR is sampled from a Beta-Bernoulli posterior using time-bucketed statistics (1-minute granularity, 60-minute rolling window). The exponent α (`bidWeight`) is publisher-configurable — α=0.3 (Discovery) lets quality dominate so small advertisers compete; α=0.5 (Balanced) is `sqrt(CPM)`, the default; α=0.7 (Revenue) tilts back toward higher bids. CTR is the multiplicative factor: a creative that users actually click beats one that merely bids high.

### 4. Quality-Adjusted Second-Price Pricing

The exploiting winner doesn't pay its own bid. It pays the minimum CPM that would have kept it ahead of the next-best candidate given its sampled CTR — a quality-adjusted second price. There's no upside to bid shading, so Promovolve runs no campaign-side bid optimizer. Pinned re-encounters (see §6) bypass pricing entirely; cold-start serves clear at the publisher's floor.

### 5. Self-Tuning PI Pacing

A PI controller with adaptive gains, traffic shape learning (separate weekday/weekend 24-hour profiles), oscillation detection, and leaky integrator anti-windup smooths budget delivery. It learns that traffic peaks at 10am and dips at 3pm, and adjusts automatically. A separate publisher-side RL agent tunes the floor CPM upward when bid spread suggests the market can bear it, and downward when fill suffers.

### 6. The Magazine Format and the Dog-Ear

A Promovolve creative is an expandable, multi-page magazine spread, not a static rectangle. The collapsed view sits in the publisher's slot; tapped, it opens into a full-screen overlay the reader can swipe through. Readers can fold the corner of a creative they want to remember — a literal **dog-ear** — and the next time they land on a page where that advertiser is eligible, the bookmarked creative is the one they see. The pin lives in the reader's browser (IndexedDB), signed by a stateless `FoldToken`; the server never stores who folded what. Pinned slots bypass auction reservation and pacing throttle, treating the pin as a free re-encounter rather than a billable serve.

## The Result

Sub-millisecond ad serving. Continuous learning at four layers (per-request Thompson Sampling, per-auction category ranking, daily traffic shapes, continuous PI tuning) plus publisher-side floor RL. Reader-controlled bookmarks instead of advertiser-controlled retargeting. Graceful degradation when budgets exhaust. No user tracking. Publisher approval over every creative.

## Navigating This Book

- **[Architecture](./architecture/overview.md)** — Pekko cluster topology, entity hierarchy, data flow
- **[Auction](./auction/periodic-auction.md)** — The five phases of the periodic batch auction
- **[Serving](./serving/thompson-sampling.md)** — Thompson Sampling, cold start, fair selection, pin-honoring
- **[Pacing](./pacing/overview.md)** — PI control, self-tuning, traffic shape learning
- **[Distributed State](./distributed/serve-index.md)** — ServeIndex replication and consistency
- **[Comparison](./comparison/vs-traditional.md)** — Point-by-point mapping against traditional ad tech

Each chapter is self-contained. All formulas, thresholds, and constants come from the Scala source code.
