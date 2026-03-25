# The Problem: Why Bid Optimization Needs RL

Imagine you are running an online ad campaign. You have a daily budget of $100, a maximum CPM (cost per thousand impressions) of $5, and a full day to spend that budget wisely. Your goal is simple: get as many clicks as possible without blowing through the money too early or leaving it unspent at the end of the day.

How hard can it be?

## The naive approach: bid the same amount all day

The simplest strategy is to bid the same amount on every auction throughout the day. Set your CPM to, say, $3 and let it ride.

The problem is that web traffic is not uniform. At 10am, when office workers are browsing news sites, traffic surges. There are more impressions available but also more competing advertisers, which drives up prices. Your $3 bid might win almost nothing during this peak because others are bidding $4 or $5.

Then at 3am, the audience shrinks but so does the competition. Cheap inventory is available at $1 CPM, but you are still bidding $3 --- overpaying for impressions you could have won for less.

A flat bidding strategy fails because the market is not flat.

## The rule-based approach: manually adjust throughout the day

You could try writing rules:

- "If we've spent more than half the budget before noon, reduce the bid by 20%."
- "If traffic is low and we're under-spending, increase the bid by 10%."

This works better than the naive approach, but you quickly run into problems:

1. **The thresholds are arbitrary.** Why 20% and not 15%? Why noon and not 1pm? You picked these numbers by intuition, and different campaigns will need different ones.

2. **The market changes.** A new competitor launches a campaign on Tuesday that was not there on Monday. Your carefully tuned rules are now wrong.

3. **Interactions are complex.** Raising your bid affects your win rate, which affects your spend rate, which triggers your spend-pacing rule, which lowers your bid, which drops your win rate. Rule-based systems tend to oscillate or get stuck.

4. **There are too many variables.** Budget remaining, time remaining, current win rate, click-through rate, cost per click, impression volume --- these all interact in non-obvious ways. Writing rules that handle every combination correctly is a combinatorial nightmare.

## The environment is non-stationary

This is the deeper issue. The advertising marketplace is not a static puzzle you solve once. It is a living system:

- **Traffic patterns shift.** A viral news story drives a spike of readers to a publisher site. A holiday changes user behavior.
- **Competitors enter and leave.** Another advertiser launches a campaign targeting the same audience, driving prices up. An hour later, they exhaust their budget and disappear, and prices drop.
- **Content changes.** The topics on a publisher's site affect what ads perform well. A sports article attracts different clicks than a finance article.
- **Your own actions change the environment.** If you bid more aggressively, you win more auctions, which depletes your budget faster, which means you need to bid less aggressively later.

No static set of rules can keep up. What you need is a system that *adapts* --- one that observes its own performance and adjusts its strategy continuously.

## The key insight: learn from experience

Here is the core idea behind using reinforcement learning for this problem:

> The agent does not know the optimal bidding strategy in advance. It must learn from experience by observing the results of its own actions.

What if we had a system that, every 15 minutes, looked at how the campaign is doing --- how fast it is spending, whether it is getting clicks, what the win rate looks like --- and then adjusted the bid amount? Not by following a fixed rule, but by choosing the adjustment that its accumulated experience suggests will lead to the best outcome over the rest of the day?

That is exactly what Promovolve's `BidOptimizationAgent` does.

## Two speeds: fast path and slow path

A real-time bidding system has to respond to ad requests in milliseconds. You cannot run a neural network inference for every single bid. Instead, Promovolve splits the work into two layers:

```
CampaignEntity (fast path, per-request):
  - Eligibility checks (canBid)
  - Budget reservation (TryReserve)
  - Bid response: maxCpm * bidMultiplier

BidOptimizationAgent (slow path, every 15 minutes):
  - Observes: spend, clicks, impressions, win rate, time/budget remaining
  - Outputs: new bidMultiplier
  - Trains DQN on accumulated experience
```

The **CampaignEntity** handles every incoming ad request. It runs on the fast path --- simple arithmetic, no ML involved. For each request, it checks whether the campaign is eligible to bid, reserves budget, and responds with a bid price. That bid price is just `maxCpm * bidMultiplier`.

The **BidOptimizationAgent** runs on the slow path. Every 15 minutes, it wakes up, looks at the campaign's performance metrics from the last window, and decides how to adjust the `bidMultiplier`. It also uses this experience to train a neural network so that future decisions improve.

This separation is critical. The fast path is lightweight and deterministic --- it just multiplies two numbers. All the learning and adaptation happens offline, on a 15-minute cadence.

## The bidMultiplier: one number to rule them all

The RL agent's output is remarkably simple: a single number called the **bidMultiplier**.

The campaign already has a `maxCpm` set by the advertiser (say, $5). The bidMultiplier scales that value:

| bidMultiplier | Effective CPM | Meaning |
|:---:|:---:|:---|
| 0.5 | $2.50 | Bid conservatively --- save budget for later |
| 1.0 | $5.00 | Bid at the full max --- default starting point |
| 1.4 | $7.00 | Bid aggressively --- win auctions now |
| 2.0 | $10.00 | Maximum aggression --- ceiling |

The multiplier is clamped between 0.5 and 2.0. This means the agent can never bid more than double or less than half the advertiser's max CPM. These guardrails keep the agent from doing anything catastrophic.

Why a multiplier instead of an absolute bid amount? Because different campaigns have different base CPMs. A multiplier of 0.8 means "bid 20% less than the max" regardless of whether the max is $2 or $20. The agent learns a *strategy* (when to be aggressive, when to conserve) that transfers across campaigns.

## What is ahead

In the next chapter, we will formalize this setup using the language of reinforcement learning: states, actions, rewards, and episodes. You will see exactly how Promovolve encodes the campaign's situation into numbers the agent can reason about, and how the reward function encourages the behavior we want --- maximizing clicks while pacing the budget smoothly through the day.
