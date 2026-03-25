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

## Reinforcement Learning

- [Reinforcement Learning from Scratch](./rl/from-scratch.md)
- [DQN Agent Overview](./rl/overview.md)
  - [State Space](./rl/state-space.md)
  - [Action Space](./rl/action-space.md)
  - [Reward Function](./rl/reward-function.md)
  - [Double DQN Architecture](./rl/double-dqn.md)
  - [Training Loop & Hyperparameters](./rl/training.md)

## Distributed State

- [Distributed State from Scratch](./distributed/from-scratch.md)
- [ServeIndex & DData](./distributed/serve-index.md)
  - [Bucketed LWWMap Design](./distributed/bucketed-lwwmap.md)
  - [TTL Sweep & Expiration](./distributed/ttl-sweep.md)
  - [Write Consistency Levels](./distributed/consistency.md)

## Learning RL Through Ad Bidding

- [Learning Reinforcement Learning Through Ad Bidding](./rl-tutorial/index.md)
  - [The Problem: Why Bid Optimization Needs RL](./rl-tutorial/01-the-problem.md)
  - [RL Fundamentals: Agent, Environment, Reward](./rl-tutorial/02-fundamentals.md)
  - [Building a Neural Network From Scratch](./rl-tutorial/03-neural-network.md)
  - [From Q-Tables to Deep Q-Networks](./rl-tutorial/04-dqn.md)
  - [Experience Replay: Learning From the Past](./rl-tutorial/05-replay-buffer.md)
  - [Double DQN: Fixing Overestimation](./rl-tutorial/06-double-dqn.md)
  - [Putting It Together: The BidOptimizationAgent](./rl-tutorial/07-full-agent.md)
  - [Training in Production](./rl-tutorial/08-production.md)

## Comparison with Traditional Ad Tech

- [Promovolve vs SSP/DSP/Exchange](./comparison/vs-traditional.md)
  - [Auction Timing: Periodic vs Realtime](./comparison/auction-timing.md)
  - [Winner Selection: MAB vs Highest Bid](./comparison/winner-selection.md)
  - [Price Discovery & First-Price Model](./comparison/price-discovery.md)
  - [Learning Mechanisms](./comparison/learning.md)
  - [Key Innovations](./comparison/innovations.md)
