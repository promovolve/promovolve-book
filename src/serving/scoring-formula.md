# Scoring Formula

At serve time, Thompson Sampling selects which creative to show. The score combines creative quality with advertiser bid:

```
score = sampledCTR × CPM^α
```

Where:
- **sampledCTR**: A random draw from the creative's Beta posterior — how likely a reader is to click
- **CPM**: The advertiser's maximum bid per thousand impressions
- **α**: The publisher's bid weight — how much money matters vs quality

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
| Sampled CTR | 0.038 | 0.025 |
| CPM^0.5 | 2.24 | 2.83 |
| **Score** | **0.085** | **0.071** |

Takeshi's ryokan wins despite bidding 38% less. Its 1.5x CTR advantage outweighs JR's 1.26x bid advantage (after sqrt compression).

If the publisher switched to Revenue (α=0.7):

| | Takeshi's Ryokan | JR Rail Pass |
|---|---|---|
| CPM^0.7 | 3.09 | 4.60 |
| **Score** | **0.118** | **0.115** |

Now it's nearly a coin flip — JR's money almost catches up. One more tick of α and JR would win.

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

When a creative has zero impressions, Thompson Sampling can't estimate CTR from clicks. Instead, it uses the category-level score from the TaxonomyRankerEntity as a prior:

```
sampledCTR = categoryScore + random(-0.15, +0.15)
score = sampledCTR × CPM^α
```

The ±0.15 noise ensures cold candidates still have variance for exploration. A new creative with a good category match will sometimes sample high enough to win, get impressions, and begin building its own track record.

## What the Advertiser Sees

The advertiser sees two CPM values on their dashboard:
- **Max CPM**: what they bid ($5.00)
- **eCPM**: what they actually pay on average (e.g., $3.41)

The gap between these is the quality discount. An advertiser with great creatives (high CTR) pays significantly less than their bid. An advertiser with poor creatives pays closer to their max. The system aligns incentives: make better ads, pay less.
