# Scoring Formula

At serve time, Thompson Sampling selects which creative to show. The score combines two engagement posteriors with the advertiser bid:

```
engagement = sampledCTR + FoldWeight × sampledFold + newcomerBonus(impressions)
score      = engagement × CPM^α
```

Where:
- **sampledCTR**: A random draw from the click-rate Beta posterior — how likely a reader is to click
- **sampledFold**: A random draw from the fold-rate Beta posterior — how likely a reader is to bookmark (dog-ear) the creative for later
- **FoldWeight = 2.0**: Folds are rarer than clicks but signal stronger intent, so they're weighted twice as much per unit rate
- **newcomerBonus**: An additive boost for creatives that haven't yet built up their own posterior; decays linearly with impressions
- **CPM**: The advertiser's maximum bid per thousand impressions
- **α**: The publisher's bid weight — how much money matters vs quality

## Why Two Posteriors?

A click is the cheapest unit of attention — fingers slip, headlines mislead, sometimes you click and immediately regret it. A **fold** (dog-ear bookmark) requires the reader to deliberately tap the corner of an expanded creative because they want to come back to it later. That's a much stronger signal of intent.

Tracking both gives the auction a fuller picture: a creative with a 5% CTR and a 30% fold rate is signaling *much* more value to the publisher's audience than a creative with the same CTR and a 1% fold rate. The combiner weights folds at 2× CTR's contribution per unit rate, so a high fold rate moves the score noticeably even when click rates are similar.

Both posteriors live in the same `CreativeStats` bucket structure (1-minute buckets, 60-minute window) and update together on the same fold/click/impression beacons. See [Beta-Bernoulli Model](./beta-bernoulli.md) for the conjugate-prior math that lets them share the framework.

## The Publisher's Dial

The exponent α is the publisher's single most important control. It determines who wins when quality and money disagree:

| Setting | α | Effect |
|---------|---|--------|
| Discovery | 0.3 | Quality dominates. A $2 ad with great CTR beats a $5 ad with mediocre CTR. Grows the advertiser base. |
| Balanced | 0.5 | Equal weight. Score = CTR × √CPM. The default. |
| Revenue | 0.7 | Money dominates. Higher bids win more often. Maximizes short-term revenue. |

A small publisher with few advertisers wants Discovery — keep everyone competitive, let quality creatives win, attract more advertisers. A high-traffic news site wants Revenue — extract maximum value from each impression.

## Why Not log(1 + CPM)?

An earlier version used `log(1 + CPM)` to compress bid differences. This compressed too aggressively:

```
log:  $10 bid / $1 bid → only 3.5x score advantage
sqrt: $10 bid / $1 bid → 3.2x advantage
linear: $10 bid / $1 bid → 10x advantage
```

With `log`, a $5 bid barely beat a $1 bid. A small CTR advantage could overcome a 5x bid difference. This was too publisher-friendly — advertisers who bid more saw little benefit.

The configurable `CPM^α` lets the publisher choose their tradeoff. At α=0.5 (sqrt), a 10x bid advantage becomes a 3.2x score advantage — meaningful but not overwhelming. Quality still matters.

## Numerical Example

Two campaigns compete for a travel article slot. The publisher uses Balanced (α=0.5):

| | Takeshi's Ryokan | JR Rail Pass |
|---|---|---|
| Max CPM | $5.00 | $8.00 |
| True CTR | ~4% | ~2% |
| True Fold rate | ~12% | ~3% |
| Sampled CTR | 0.038 | 0.025 |
| Sampled Fold rate | 0.115 | 0.028 |
| Engagement (CTR + 2×Fold) | 0.268 | 0.081 |
| CPM^0.5 | 2.24 | 2.83 |
| **Score** | **0.600** | **0.229** |

Takeshi's ryokan wins decisively. The fold signal is doing most of the work — readers who saw both creatives bookmarked Takeshi's nearly 4× more often, and `FoldWeight = 2.0` projects that into a meaningful score gap. Without the fold posterior, the scores would have been much closer (0.085 vs 0.071, the original CTR-only example), and a small bid bump could have flipped the outcome.

This is the point of the fold signal: it lets the auction reward creatives that earn deeper engagement, not just curiosity clicks.

## Quality-Adjusted Pricing

The winner doesn't pay their max CPM. They pay the **minimum bid that would still win** given their CTR:

```
payment = (bestLoserScore / winnerCTR) ^ (1/α)
```

In the example above (Balanced, α=0.5):
- Ryokan wins with score 0.085
- JR's losing score: 0.071
- Ryokan pays: (0.071 / 0.038)² = $3.49

Takeshi bid $5.00 but pays $3.49. The quality discount saved 30%. This is the system rewarding good creative work — higher CTR means lower effective cost.

During exploration (cold start, warmup, impression share guarantee), the winner pays the publisher's floor price. You shouldn't pay market rates for an impression that was given to you for learning purposes.

## Cold Start Variant

When a creative has zero impressions, neither posterior has data. The system substitutes priors so cold candidates still produce a meaningful score:

```
sampledCTR  = categoryScore + random(-0.15, +0.15)   // page-classifier prior
sampledFold = sampleBeta(1, 1)                        // uniform [0,1] cold prior
engagement  = sampledCTR + 2.0 × sampledFold + NewcomerBoost
score       = engagement × CPM^α
```

The ±0.15 CTR noise ensures cold candidates have variance for exploration. The fold-rate prior is `Beta(1, 1)` — uniform over [0, 1] — which gives proper Thompson exploration on the fold dimension instead of pinning it to zero (an earlier bug where cold creatives could never win against warm fold-rich ones).

The **newcomer bonus** is a UCB-style additive boost — full strength at impressions=0, decaying linearly to zero by the 50th impression. It guarantees newcomers get exposure even when warm creatives have built up confident posteriors. See [Cold Start Strategies](./cold-start.md) for the decay curve.

## What the Advertiser Sees

The advertiser sees two CPM values on their dashboard:
- **Max CPM**: what they bid ($5.00)
- **eCPM**: what they actually pay on average (e.g., $3.41)

The gap between these is the quality discount. An advertiser with great creatives (high CTR) pays significantly less than their bid. An advertiser with poor creatives pays closer to their max. The system aligns incentives: make better ads, pay less.
