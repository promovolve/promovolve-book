# Thompson Sampling from Scratch

You have three ads for a travel blog. You don't know which one readers prefer. How do you find out — without wasting thousands of impressions on the worst one?

This is the **multi-armed bandit** problem, and Thompson Sampling is Promovolve's answer. This chapter builds the intuition from zero.

## The Problem: Explore vs Exploit

Imagine you're in a casino with three slot machines. Each has a different (unknown) payout rate. You have 1,000 coins. How do you maximize your winnings?

- **Pure exploitation**: Play the first machine that pays out, stick with it forever. Problem: you might have gotten lucky. The other machines might be better.
- **Pure exploration**: Play all three equally, 333 times each. Problem: you're wasting coins on the worst machine long after you know it's bad.

The optimal strategy is somewhere in between: explore early to learn which machine is best, then gradually shift to exploiting the best one. This is the **explore-exploit trade-off**.

In Promovolve, the "slot machines" are ad creatives. The "payout" is whether the user clicks. The "coins" are impressions — each one costs the advertiser money and uses the publisher's ad slot. You want to show the best-performing creative most of the time, but you also need to try new or uncertain ones to learn if they're better.

## A Bad Solution: A/B Testing

The standard approach to "which creative is best?" is A/B testing: show each creative to an equal number of users, wait for statistical significance, then declare a winner and show it to everyone.

This works, but it's wasteful. If creative A has a 5% click rate and creative B has a 0.5% click rate, equal splitting means half your traffic sees the bad creative for the entire test duration. And when the test ends, you stop learning — if a new creative arrives, you need to start a new test.

What you really want is a system that:
1. Tries each creative a few times
2. Quickly figures out which ones are good
3. Shifts traffic toward the good ones
4. Never completely stops trying — in case a creative's performance changes

Thompson Sampling does all of this automatically.

## The Key Idea: Uncertainty as Exploration

Here's the core insight. Instead of tracking a single number ("creative A has a 5% click rate"), track your **uncertainty** about that number.

After 2 impressions and 1 click, you think creative A has about a 50% click rate — but you're not very sure. It could be anywhere from 10% to 90%.

After 200 impressions and 10 clicks, you think it has about a 5% click rate — and you're fairly confident. It's probably between 3% and 8%.

Thompson Sampling uses this uncertainty directly: **sample a random value from each creative's uncertainty distribution, then pick the creative with the highest sample.**

A creative you know little about has a wide distribution — sometimes it samples high, sometimes low. So it gets tried occasionally (exploration). A creative with lots of data has a narrow distribution centered on its true click rate. It samples consistently near its actual performance (exploitation).

Exploration happens naturally, proportional to uncertainty. No tuning parameters. No explicit explore/exploit switch.

## Beta Distributions: Modeling Click Rates

A click rate is a probability: a number between 0 and 1. The **Beta distribution** is the natural way to represent uncertainty about a probability.

A Beta distribution has two parameters: **α (alpha)** and **β (beta)**.

- **α** counts "successes" (clicks) plus a prior
- **β** counts "failures" (impressions without clicks) plus a prior

Starting from `Beta(1, 1)` — a uniform distribution, meaning "I have no idea, any click rate from 0% to 100% is equally possible" — each observation updates the distribution:

```
Start:       Beta(1, 1)         — uniform, total ignorance
1 click:     Beta(2, 1)         — probably high CTR, but uncertain
1 no-click:  Beta(2, 2)         — back toward 50%, still very uncertain
8 no-clicks: Beta(2, 10)        — probably low CTR (~17%), getting more sure
2 clicks:    Beta(4, 10)        — ~29%, narrowing
```

The **mean** of Beta(α, β) is `α / (α + β)`. But Thompson Sampling doesn't use the mean — it **samples** a random value from the distribution. That's what makes it work.

## A Worked Example

Three creatives cached for a travel blog ad slot. After some impressions:

| Creative | Impressions | Clicks | Distribution | Mean CTR |
|----------|------------|--------|-------------|----------|
| A (hotel ad) | 150 | 6 | Beta(7, 145) | 4.6% |
| B (tour ad) | 20 | 2 | Beta(3, 19) | 13.6% |
| C (new airline ad) | 0 | 0 | Beta(1, 1) | 50.0% |

A reader loads the page. Thompson Sampling draws one random sample from each:

```
A: sample from Beta(7, 145)  → 0.038  (probably near its true ~5%)
B: sample from Beta(3, 19)   → 0.091  (wide distribution, sampled somewhat high)
C: sample from Beta(1, 1)    → 0.647  (uniform distribution, sampled very high)
```

Creative C wins this round — not because we think it has a 65% click rate, but because we know nothing about it and the sample happened to be high. This is exploration.

If C turns out to have low CTR, after 20 impressions its distribution narrows (say, Beta(2, 19)) and it stops sampling high. If C actually has great CTR, its distribution stays high and it earns more impressions.

**The system converges on the truth without ever deciding to "start a test" or "end a test."**

## Scoring: Combining CTR with Bid Price

Click rate isn't the only thing that matters. The publisher also cares about revenue. A creative with 2% CTR at $8 CPM might be more valuable than one with 3% CTR at $2 CPM.

Promovolve's scoring formula balances both:

```
score = sampledCTR × CPM^α
```

(That's the teaching version. The full production score adds two more
engagement terms — a fold-rate posterior and a decaying newcomer bonus —
see [Thompson Sampling](./thompson-sampling.md); the shape of the
argument is identical.)

Why `CPM^α` instead of just `CPM`? The exponent α (publisher-tunable, default 0.5) compresses the CPM range so a creative has to perform well to win consistently — you can't just outbid everyone with a terrible ad.

Consider two creatives at the default α=0.5:
- A: $2 CPM, 4% CTR → score = 0.04 × √2 = 0.04 × 1.41 = 0.057
- B: $10 CPM, 1% CTR → score = 0.01 × √10 = 0.01 × 3.16 = 0.032

Creative A wins despite bidding 5× less. Bidding 5× more gives you only ~2.2× the CPM term — quality dominates.

The publisher chooses the exponent: α=0.3 (Discovery) tilts harder toward quality, α=0.7 (Revenue) tilts back toward higher bids. See [Scoring Formula](./scoring-formula.md) for the full dial.

This aligns publisher and advertiser incentives: the publisher gets revenue AND engaged readers, not just the highest bidder's money.

## Cold Start: What About Brand New Creatives?

When a creative has zero impressions, its distribution is `Beta(1, 1)` — uniform. It can sample anywhere from 0 to 1. This gives it a natural exploration boost, but it's random.

Promovolve structures the cold start with two mechanisms, both inside
the scoring function itself (no separate strategy switch):

**Zero impressions**: instead of sampling the uninformative uniform, the
creative scores from the **category score the auction assigned it** —
the Thompson-sampled CTR of its category on this kind of page — plus
small exploration noise (±0.15). A travel ad on a travel page starts
from a reasonable guess, not a coin flip.

**First 50 impressions**: an additive **newcomer bonus** (0.5, decaying
linearly to zero) keeps a fresh creative competitive against established
ones while its own posterior is still wide, so it accumulates real
evidence instead of being starved by an incumbent's tight distribution.

After that, the posteriors are informative enough that pure Thompson
Sampling drives selection. Both mechanisms live in
`ThompsonSampling.scoreCandidate()`.

## Time-Bucketed Statistics

Click rates change over time. An ad that performed well last week might be stale now. Promovolve uses a **60-minute rolling window** with **1-minute granularity**:

- Impressions and clicks are recorded in 1-minute buckets
- When scoring, only the last 60 buckets are counted
- Older data automatically falls off

This means:
- The system adapts within an hour if a creative's performance changes
- A creative that was good this morning but bad this afternoon gets corrected quickly
- The Beta distribution is always based on recent, relevant data

## Where Thompson Sampling Sits in the Pipeline

Thompson Sampling doesn't run on every request. It sits behind several gates:

```
Request arrives
  → Content recency check (is the page fresh enough?)
  → Frequency cap check (has this user seen this ad too many times?)
  → Rate tracking (record this request for pacing)
  → Pacing gate (PI controller: should we serve or skip?)
  → Thompson Sampling (which creative to show?)
  → Budget reservation (does the winning campaign have budget?)
  → Serve the ad
```

The pacing gate runs **before** Thompson Sampling. This is important: if the pacing controller decides to skip this request (to conserve budget), Thompson Sampling never runs. This prevents exploration from being wasted on throttled requests.

## Why Thompson Sampling Over Other Approaches

**vs Epsilon-Greedy** (ε-greedy): Show the best creative 90% of the time, random 10%. Simple, but the exploration rate is fixed and doesn't adapt. A creative you've shown 10,000 times still gets explored at the same rate as one you've shown 10 times. Thompson Sampling naturally explores uncertain creatives more.

**vs UCB (Upper Confidence Bound)**: Pick the creative with the highest `mean + confidence_bonus`. Deterministic — same state always picks the same creative. Thompson Sampling's randomness is a feature: two users loading the same page at the same time might see different creatives, which produces diverse data faster.

**vs A/B Testing**: Fixed allocation, fixed duration, manual setup. Thompson Sampling is continuous, adaptive, and automatic.

## From Theory to Code

| Concept | File | Key method |
|---------|------|-----------|
| Beta sampling (Marsaglia-Tsang) | `ThompsonSampling.scala` | `sampleBeta()` |
| Score = engagement × CPM^α | `ThompsonSampling.scala` | `cpmScore()` / `scoreCandidate()` |
| Cold start + newcomer bonus | `ThompsonSampling.scala` | `scoreCandidate()` |
| Time-bucketed creative stats | `Protocol.scala` | `CreativeStats` |
| Pacing gate before TS | `PacingStrategy.scala` / `AdServer.scala` | `shouldServe()`, then selection |

The next chapters cover each of these components in detail with exact formulas and configuration values.
