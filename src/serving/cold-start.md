# Cold Start

New candidates enter the system with zero impressions. Promovolve handles
them with two mechanisms, both inside the scoring function itself — there
is no separate strategy switch, no forced warmup phase, and no
epsilon-greedy branch. Every request scores every candidate the same way;
what changes is where a cold candidate's numbers come from.

## Mechanism 1: The Cold Branch (zero impressions)

A candidate with no impression history can't sample a CTR posterior — its
`Beta(1, 1)` would be pure noise. Instead, the cold branch of
`scoreCandidate` substitutes the best signal available:

```
sampledCTR = max(0.001, categoryScore + random(-0.15, +0.15))
sampledFold = sampleBeta(1, 3)     // Beta(1,3), mean 0.25
```

The `categoryScore` is the Thompson-sampled CTR of the candidate's
*category* on this kind of page, assigned during the auction by the
TaxonomyRankerEntity — so a travel ad on a travel page starts from how
travel ads have performed on travel pages, not from a coin flip. The
±0.15 jitter keeps identical category scores from producing deterministic
selection, and the clamp keeps a low score minus jitter from going
negative.

The fold rate has no category-level prior, so it samples from a
`Beta(1, 3)` cold prior (mean 0.25). This matters more than it looks:
without a fold sample, a cold creative's engagement could never beat a
warm fold-rich one's `sampledCTR + 2.0 × foldRate` — the exploration
mechanism would silently fail for exactly the candidates that need it.
(A uniform `Beta(1, 1)` prior was tried first and over-rewarded cold
creatives — an expected `2.0 × 0.5 = 1.0` engagement head start.)

## Mechanism 2: Newcomer Bonus (first 50 impressions)

Cutting across cold and warm scoring is a **continuous additive bonus**
that tilts selection toward creatives with few impressions:

```
engagement = sampledCTR + FoldWeight × sampledFold + newcomerBonus(impressions)

newcomerBonus(n) = max(0, NewcomerBoost × (1 - n / NewcomerDecayImpressions))
```

With `NewcomerBoost = 0.5` and `NewcomerDecayImpressions = 50`, the curve is:

| Impressions | Bonus | Effect |
|---:|---:|---|
| 0  | +0.50 | Brand new — full boost |
| 10 | +0.40 | Early evidence accumulating, still strongly favored |
| 25 | +0.25 | Half-faded |
| 50 | 0.00  | Bonus exhausted — competing on its own posteriors |
| 100+ | 0.00 | No boost; warm creative |

This is a UCB (Upper Confidence Bound) flavored adjustment grafted onto
Thompson Sampling. Pure TS already over-prefers high-variance candidates,
but in practice the variance gain from a small impression count isn't
always enough to outpace a confident warm creative with established
stats. The decaying bonus closes that gap explicitly: brand new
creatives get a guaranteed exploration runway, and the boost fades
smoothly so the system isn't permanently subsidizing newcomers that
turned out to be poor performers.

## Why No Forced Warmup?

An earlier design sketched a round-robin warmup phase (every candidate
gets N impressions before TS takes over). It was never needed: the
category-score prior gives cold candidates a *sensible* starting score
rather than a random one, and the newcomer bonus guarantees the runway a
round-robin would have provided — without ever serving a plainly wrong
ad just because it's new. Selection stays a single argmax over
identically-shaped scores at every lifecycle stage.

## Key Constants

| Constant | Value | Location |
|----------|-------|----------|
| `NewcomerBoost` | 0.5 | ThompsonSampling.scala |
| `NewcomerDecayImpressions` | 50 | ThompsonSampling.scala |
| `FoldWeight` | 2.0 | ThompsonSampling.scala |
| Cold CTR noise range | ±0.15 | ThompsonSampling.scala |
| Cold CTR floor | 0.001 | ThompsonSampling.scala |
| Cold fold prior | `Beta(1, 3)` | ThompsonSampling.scala |
