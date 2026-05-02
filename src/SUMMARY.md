# Summary

[Why Promovolve?](./why-promovolve.md)

# The Story

- [A Publisher Joins](./story/01-publisher-joins.md)
- [An Advertiser Joins](./story/02-advertiser-joins.md)
- [The First Auction](./story/03-the-auction.md)
- [A Reader Arrives](./story/04-reader-arrives.md)
- [The Click](./story/05-the-click.md)
- [A Day in the Life](./story/06-the-day.md)
- [A Week Later](./story/07-week-later.md)

# How It Works

- [Technical Introduction](./introduction.md)
- [How Ad Tech Works (and Where Promovolve Diverges)](./comparison/from-scratch.md)

# The Ad Format

- [The Magazine Format](./format/overview.md)

# Deep Dives

## Architecture

- [System Architecture](./architecture/overview.md)
  - [Entity Hierarchy & Cluster Roles](./architecture/entity-hierarchy.md)
  - [Data Flow: Crawl vs Serve](./architecture/data-flow.md)

## The Auction System

- [Periodic Batch Auction](./auction/periodic-auction.md)
  - [Phase 1: Page Classification](./auction/page-classification.md)
  - [Phase 2: Category Ranking](./auction/category-ranking.md)
  - [Phase 3: Bid Collection](./auction/bid-collection.md)
  - [Phase 4: Candidate Shortlisting](./auction/candidate-shortlisting.md)
  - [Phase 5: ServeIndex Caching](./auction/serve-index-caching.md)
- [Re-Auction & Event Triggers](./auction/re-auction.md)
- [Why Multi-Candidate?](./auction/why-multi-candidate.md)

## Publisher Creative Approval

- [Publisher Creative Approval](./approval/overview.md)

## Serve-Time Selection

- [Thompson Sampling from Scratch](./serving/from-scratch.md)
- [Thompson Sampling (MAB)](./serving/thompson-sampling.md)
  - [Beta-Bernoulli Model](./serving/beta-bernoulli.md)
  - [Scoring Formula](./serving/scoring-formula.md)
  - [Cold Start Strategies](./serving/cold-start.md)
  - [Beta Distribution Sampling](./serving/beta-sampling.md)
- [Fair Candidate Selection](./serving/fair-selection.md)
  - [Per-Campaign Diversity](./serving/campaign-diversity.md)
  - [Frequency Capping](./serving/frequency-capping.md)

## Budget Pacing

- [Pacing Overview](./pacing/overview.md)
  - [Rate Tracking (EMA)](./pacing/rate-tracking.md)
  - [PI Control Loop](./pacing/pi-control.md)
  - [Traffic Shape Learning](./pacing/traffic-shape.md)
  - [Grace Periods & Hybrid Modes](./pacing/grace-periods.md)

## Distributed State

- [Distributed State from Scratch](./distributed/from-scratch.md)
- [ServeIndex & DData](./distributed/serve-index.md)
  - [Bucketed LWWMap Design](./distributed/bucketed-lwwmap.md)
  - [TTL Sweep & Expiration](./distributed/ttl-sweep.md)
  - [Write Consistency Levels](./distributed/consistency.md)

## Comparison with Traditional Ad Tech

- [Promovolve vs SSP/DSP/Exchange](./comparison/vs-traditional.md)
  - [Auction Timing: Periodic vs Realtime](./comparison/auction-timing.md)
  - [Winner Selection: MAB vs Highest Bid](./comparison/winner-selection.md)
  - [Learning Mechanisms](./comparison/learning.md)
  - [Key Innovations](./comparison/innovations.md)
