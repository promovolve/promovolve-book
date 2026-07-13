# Floor Optimization

A floor price protects a publisher from selling attention below its worth —
set too low, second-price clearing grinds toward zero in thin competition;
set too high, fill rate collapses. Publishers shouldn't have to guess this
number, so Promovolve measures it.

## Sweep, don't learn

The `FloorSweepOptimizer` is deliberately *not* reinforcement learning — an
earlier RL approach (value estimates over discretized floor levels) was
built, evaluated, and dropped: with pacing and Thompson Sampling already
adapting around every floor change, credit assignment was hopeless, and the
agent mostly learned noise. What replaced it is controlled measurement:

1. **Sweep.** Generate candidate floors across the plausible range (bounded
   below by observed rejected bids, above by the best observed bid). Hold
   each candidate for a fixed number of auction ticks, measuring **served
   revenue** — actual post-pacing, post-selection earnings, not theoretical
   clearing prices. Revenue is the only honest objective; anything upstream
   of it can be gamed by the very systems the floor interacts with.
2. **Exploit.** Take the argmax and hold it for a longer exploitation
   period. Ties within tolerance resolve to the *lower* floor (fill rate is
   worth more than a cosmetic floor), and a minimum-impressions guard keeps
   a lucky low-traffic candidate from winning on three data points.
3. **Repeat.** Markets drift; the cycle re-runs continuously.

## Per-category floors

A single site-wide floor has a monopoly pathology: one rich category (say,
*Finance* demand at $12) sets a floor that locks out every other category's
demand entirely. Floors therefore run **per content category**, each
category sweeping independently; categories without enough data fall back to
the site-level floor. The pathological case that motivated this — a lone
high bidder pushing the site floor above everyone else — now prices one
category at $12 while *Travel* still clears at $3.

Two guardrails matter more than the sweep itself:

- **Only approved demand teaches floors.** Pending creatives bid (to reach
  the approval queue) but are invisible to the optimizer — otherwise an
  unapproved, possibly rejected campaign could inflate a floor that outlives
  it.
- **A lone bidder pegs the floor to its bid.** With one approved bidder
  there is no second price and nothing to sweep; the floor snaps to the bid
  (and instantly back down when the bidder leaves — validated live in both
  directions). And with *zero* approved demand the floor collapses to the
  minimum immediately: a floor with nobody to price against is pure
  fill-rate damage.

One honest caveat: in a perfectly homogeneous market — every bidder at the
same CPM — every floor below the common bid earns identical revenue, and the
optimizer settles anywhere on that plateau. That is correct behavior, and a
reminder of what this component is: not intelligence, just a well-designed
experiment that never stops running.
