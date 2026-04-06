# The Problem: Why Floor Price Optimization Needs RL

Imagine you run a popular blog about travel in Japan. Advertisers want to show their ads on your site. You need to set a **floor price** — the minimum bid an advertiser must offer to compete for your ad slots. Set it right, and you maximize your revenue. Set it wrong, and you either leave money on the table or drive away advertisers.

How hard can it be?

## The naive approach: pick a number and leave it

The simplest strategy is to set a fixed floor — say, $1.00 CPM — and never change it.

The problem is that your advertiser market is not static. This week, five travel companies are bidding between $3 and $10 for your inventory. Your $1.00 floor is doing nothing — everyone clears it easily. You're selling premium travel content for pennies above the floor when the market would support $3+.

Next month, two of those advertisers pause their campaigns. Now you have three bidders between $2 and $5. Your floor is still fine — but if you'd set it at $4 based on last week's market, you'd be rejecting 2 out of 3 advertisers and halving your fill rate.

A static floor fails because the market is not static.

## The rule-based approach: manually adjust based on metrics

You could try writing rules:

- "If fill rate drops below 50%, lower the floor by 10%."
- "If all bids are more than 3x the floor, raise it."

This works better than a static floor, but you quickly run into problems:

1. **The thresholds are arbitrary.** Why 50% fill rate? Why 3x? Different sites with different advertiser mixes will need different numbers.

2. **The market changes.** A big brand launches a campaign on Tuesday that wasn't there on Monday. Your rules are now leaving money on the table.

3. **Interactions are complex.** Raising the floor rejects some bidders, which changes the competitive dynamics among remaining bidders, which changes clearing prices, which changes revenue. Rules that handle one dimension well often fail when multiple dimensions interact.

4. **Budget effects are delayed.** A high floor causes advertisers to spend their budgets faster (solo winners pay floor price). This doesn't show up immediately — the effect cascades over hours. Rules can't anticipate this.

## The environment is non-stationary

This is the deeper issue. The advertiser marketplace is a living system:

- **Campaigns start and stop.** New advertisers enter, existing ones exhaust budgets or pause.
- **Bids change.** An advertiser raises their CPM after seeing good CTR on your site.
- **Content changes.** Different articles attract different ad categories. A sports article has different bidders than a food article.
- **Your own actions change the environment.** If you raise the floor and reject a bidder, the remaining bidders face less competition — their clearing prices drop, even though your floor went up.

No static set of rules can keep up. What you need is a system that *adapts* — one that observes the results of its pricing decisions and adjusts continuously.

## The key insight: learn from experience

Here is the core idea behind using reinforcement learning for this problem:

> The agent does not know the optimal floor price in advance. It must learn from experience by observing the results of its own actions.

What if we had a system that, every 15 minutes, looked at how the site is performing — what's the fill rate, how much revenue came in, are budgets draining too fast — and then adjusted the floor price? Not by following a fixed rule, but by choosing the adjustment that its accumulated experience suggests will maximize revenue?

That is exactly what Promovolve's `FloorCpmOptimizationAgent` does.

## Two speeds: auction and optimization

A real-time ad serving system has to respond to requests in milliseconds. You cannot run a neural network for every serve request. Instead, Promovolve splits the work:

```
AuctioneerEntity (fast path, per-auction):
  - Uses current floor to filter bids
  - Runs auction with qualifying bidders
  - Caches results for serve-time

FloorCpmOptimizationAgent (slow path, every 15 minutes):
  - Observes: fill rate, revenue, bidder count, budget exhaustion
  - Outputs: new floor CPM
  - Trains DQN on accumulated experience
```

The **AuctioneerEntity** uses the floor as a simple filter — any bid below the floor is rejected. This is fast and deterministic.

The **FloorCpmOptimizationAgent** runs on the slow path. Every 15 minutes, it wakes up, looks at the site's auction metrics from the last window, and decides how to adjust the floor. It also uses this experience to train a neural network so that future decisions improve.

## The floor adjustment: small, safe steps

The RL agent's output is remarkably simple: a multiplier applied to the current floor price.

| Multiplier | Effect | Meaning |
|:---:|:---:|:---|
| 0.90 | Floor drops 10% | Let more bidders in — fill rate was too low |
| 1.00 | Floor stays the same | Current level is working |
| 1.10 | Floor rises 10% | Filter out low bidders — market can support more |

The adjustment is capped at ±10% per observation. This means the agent can never make drastic changes. It takes multiple observations to make a large move, giving the agent time to see the effect of each step.

The floor is also clamped:
- **Never below** the publisher's minimum (set in the dashboard)
- **Never above** 80% of the highest observed bid (always keeps at least one bidder competitive)

These guardrails keep the agent from doing anything catastrophic.

## What is ahead

In the next chapter, we will formalize this setup using the language of reinforcement learning: states, actions, rewards, and episodes. You will see exactly how Promovolve encodes the site's market situation into numbers the agent can reason about, and how the reward function encourages the behavior we want — maximizing publisher revenue while maintaining healthy fill rates and sustainable advertiser budgets.
