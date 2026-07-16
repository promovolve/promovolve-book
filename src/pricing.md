# What the Winner Pays

Promovolve is second-price at heart: the winner pays what was needed to win,
not what they offered. But the score that wins is `engagement × CPM^α`, not
a bare bid — so the clearing price must be quality-adjusted too.

## Sample for allocation, price on means

Selection uses sampled (noisy) values on purpose; pricing must not. A price
that depended on a random draw would make identical impressions cost
different amounts. So the system **allocates on samples, prices on
posterior means**: after the winner is chosen, the runner-up's score is
recomputed from mean engagement rates, and the winner pays the minimum CPM
at which it *still would have won*:

```
clearingCPM = (runnerUpScore / winnerEngagement)^(1/α)
```

clamped between the slot's floor and the winner's own bid. Intuition: invert
the scoring formula and ask, "with your engagement rate, what's the cheapest
bid that still beats the next-best candidate?"

Two properties fall out:

- **Quality is a discount.** A creative readers engage with needs a lower
  CPM to hold its rank, so it *pays less* than a mediocre creative bidding
  identically. Advertisers improve their price by improving their ad.
- **Bidding is honest.** Raising your bid above what's needed doesn't raise
  your price (the runner-up sets it); lowering it only risks losing. There
  is no bid-shading strategy to compute (*shading*: bidding below your true
  value to dodge overpaying — the daily homework of first-price auctions),
  which is why Promovolve ships no campaign-side bid optimizer — the
  mechanism leaves nothing for one to do.

The runner-up is taken from the winner's own content category, so the price
reflects real competition for *this kind of page*, not an accidental
cross-category comparison.

## Edge cases

- **Exploration usually prices at the floor.** A zero-history winner is
  priced by the same mean formula, using its cold-prior engagement — the
  category affinity, the fold prior, and the newcomer bonus. Because the
  bonus inflates its engagement, the inverted price typically clamps down
  to the floor; a cold winner facing a strong same-category runner-up can
  still clear above it.
- **No runner-up → floor.** A lone candidate pays the floor. (What stops
  floors from collapsing in a one-bidder market is the floor optimizer —
  see [Floor Optimization](./floors.md) — which pegs the floor to a lone
  bidder's bid.)
- **Pinned re-encounters are free.** A dog-eared creative serving to the
  reader who bookmarked it clears at zero. The reader's memory is not
  inventory.

## Spend is recorded at the clearing price

Budget reservation, pacing, and the ledger all use the cleared price, not
the bid. A campaign bidding $8 into thin competition might spend $2.10 per
thousand — its budget lasts proportionally longer, and the advertiser's
reports show the price they actually paid. Every spend event flows through
buffered, deduplicated, at-least-once recording into a double-entry ledger
in micro-dollars (millionths of a dollar — integer arithmetic, so the books
never accumulate rounding drift); settlement splits gross into platform margin (a percentage set in basis
points — hundredths of a percent — that can change on a dated schedule) and
publisher earnings, one idempotent row
per advertiser–campaign–site–day.
