# Reinforcement Learning in Promovolve

Promovolve uses reinforcement learning for one specific purpose: **publisher-side floor CPM optimization**. The RL agent adjusts the minimum bid price on each publisher's site to maximize the publisher's revenue.

## Why RL for the Floor, Not for Bidding?

An earlier design considered RL for campaign bid optimization — an agent per campaign that would learn to shade bids. This was abandoned because Promovolve's quality-adjusted auction makes truthful bidding optimal. The clearing price is computed from competition and creative quality, not from the raw bid. Bid shading is counterproductive: if you lower your bid, you lower your score and lose impressions, but you don't save money (you'd have paid the quality-adjusted clearing price anyway).

The floor CPM is different. There's no dominant strategy for setting it. The optimal floor depends on the current market — how many advertisers are bidding, what they're willing to pay, their budget levels, their creative quality. This changes constantly. A static floor either leaves money on the table (too low) or drives away advertisers (too high). This makes it a natural fit for RL: discover the right level through experimentation.

## How the Agent Works

Each publisher site has its own floor CPM agent. The agent lives inside the SiteEntity and runs on a 15-minute observation cycle.

### The Observation

Every 15 minutes, the agent collects metrics from the past window:

| Signal | Source | What it tells the agent |
|--------|--------|------------------------|
| Fill rate | AuctioneerEntity | Are auctions producing winners? |
| Bidder count | AuctioneerEntity | How competitive is the market? |
| Avg winning CPM | AuctioneerEntity | What are winners paying? |
| Rejection rate | AuctioneerEntity | How many bids is the floor killing? |
| Served revenue | LearningEventLog | What's the actual money earned? (post-pacing) |
| Budget exhaustion | AdServer | Are budgets draining too fast? |

The agent encodes these into a 7-dimensional state vector, normalized to [0, 2] range.

### The Decision

The agent picks one of 7 actions: multiply the current floor by 0.90, 0.95, 0.98, 1.00, 1.02, 1.05, or 1.10. Small steps — the floor never jumps by more than 10% in a single observation.

The new floor is clamped to a range:
- **Lower bound**: the publisher's minimum floor (set in the dashboard — "never sell my inventory for less than $X")
- **Upper bound**: 80% of the highest observed bid (prevents the agent from pricing out all advertisers)

### The Reward

The agent's reward signal is actual served revenue, not auction-time estimates:

```
reward = normalizedRevenue × fillRate
       − budgetExhaustionPenalty
       − volatilityPenalty
```

Why served revenue, not auction revenue? Because the pacing controller throttles impressions between auction and serve. A high floor might produce great auction clearing prices, but if pacing throttles 80% of serves because budgets are draining too fast, the publisher's actual revenue is a fraction of what the auction promised. The agent needs the real signal.

The budget exhaustion penalty provides an early warning. When the agent raises the floor, solo winners pay the floor as their clearing price. Higher floor → higher per-impression revenue → faster budget drain → budget exhaustion → zero revenue. The penalty catches this before revenue drops to zero.

### When It Activates

The agent only runs when the market justifies optimization:

- **Diverse bids**: highest/lowest CPM ratio > 1.5x, OR bids are being rejected by the floor
- **Homogeneous market**: all bidders at the same CPM → agent sleeps (nothing to optimize)

This keeps the replay buffer clean. The agent only trains on market conditions where its actions matter.

## What the Agent Learns

Over hundreds of observations, the agent discovers the revenue-maximizing floor for the current market:

**Floor too low** → every campaign qualifies, but clearing prices are low. The floor isn't doing any work.

**Floor too high** → campaigns get rejected, fill rate drops, remaining campaigns have no competition (solo winners pay floor), budgets drain fast.

**Sweet spot** → enough competition for healthy clearing prices, bottom-tier bids filtered out, budgets last through the day.

In a market with bids at $2, $4, $6, $8, $10: the agent might settle around $3–4. This filters out the $2 bidder (who wasn't adding much competition) while keeping 4 campaigns actively competing. The quality-adjusted pricing among those 4 produces higher clearing prices than having all 5 compete with the $2 bidder dragging down the average.

## The Algorithm

The agent uses **Double DQN** (Deep Q-Network):

- **Q-network**: 7 inputs → 64 → 32 → 7 outputs (one Q-value per action)
- **Target network**: copy of Q-network, synced every 50 training steps
- **Replay buffer**: 5,000 transitions, sampled in mini-batches of 4
- **Exploration**: ε-greedy, starting at 0.8 and decaying to 0.05

Is DQN overkill for a 7-dimensional state with 7 actions? Probably. A simpler hill-climbing approach might work nearly as well. But the DQN infrastructure was already built for the (now-removed) campaign bid optimization, and it works reliably. The computational cost is negligible — one forward pass through a tiny network every 15 minutes.

## Persistence

The DQN weights are serialized in the SiteEntity's durable state. When the server restarts, the agent restores its learned weights and continues from where it left off. No retraining needed.

## Publisher Controls

The publisher controls two boundaries:

- **Minimum floor** (required on site creation): "never go below $X"
- **Ad selection priority** (Discovery/Balanced/Revenue): controls the scoring exponent α

The RL agent operates within these boundaries. It cannot override the publisher's minimum floor or change the ad priority. The publisher sets the rails; the agent optimizes within them.

---

*Technical deep dives: [State Space](./state-space.md) · [Action Space](./action-space.md) · [Reward Function](./reward-function.md) · [Double DQN](./double-dqn.md)*
