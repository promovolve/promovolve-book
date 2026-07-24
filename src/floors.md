# Floor Optimization

A floor price protects a publisher from selling attention below its worth —
set too low, second-price clearing grinds toward zero in thin competition;
set too high, fill rate — the share of slots that
actually serve an ad — collapses. Publishers shouldn't have to guess this
number, so Promovolve measures it.

## Sweep, don't learn

The `FloorSweepOptimizer` is deliberately *not* reinforcement learning — an
earlier RL approach (value estimates over discretized floor levels) was
built, evaluated, and dropped: with pacing and Thompson Sampling already
adapting around every floor change, credit assignment was hopeless, and the
agent mostly learned noise. What replaced it is controlled measurement:

1. **Sweep.** Generate candidate floors across the plausible range —
   bounded below by observed rejected bids, above by **99% of the
   second-highest approved bid**. Not the top bid: any floor between the
   second and top bid manufactures a monopoly (only the top bidder
   clears), and since each campaign fills at most one slot per page,
   pricing out the rest of the field forfeits their fill for a few
   percent more on one impression. A floor may price out the bottom of
   the field, never the top two; extraction above the second bid is
   second-price clearing's job, not the reserve's. Hold each candidate
   for a fixed number of auction ticks, measuring **served revenue** —
   actual post-pacing, post-selection earnings, not theoretical clearing
   prices. Revenue is the only honest objective; anything upstream of it
   can be gamed by the very systems the floor interacts with.
2. **Exploit.** Take the argmax — the floor that earned the most — and hold it for a longer exploitation
   period. Ties within tolerance resolve to the *higher* floor — the same
   revenue on fewer impressions, and more robust if the dominant bidder's
   value drifts up. The optimizer only fails open to the lowest floor when
   evidence is missing, and a minimum-impressions guard keeps a lucky
   low-traffic candidate from winning on a handful of data points.
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
- **A lone bidder pegs the floor to 99% of its bid.** With one approved
  bidder there is no second price and nothing to sweep; the floor snaps
  to just under the bid — the 1% headroom guarantees the bidder always
  clears its own floor — and instantly re-derives when the field changes
  (validated live in both directions, including pausing the top bidder
  mid-flight). And when there is no demand that can actually serve —
  zero approved bidders, *or* bidders whose every bid the floor has
  priced out — the floor collapses to the minimum immediately: demand
  that cannot serve is not demand, and a floor with nobody to price
  against is pure fill-rate damage.

- **Slot quality can only discount a floor, never raise it.** The floor a
  bid must actually beat is the category floor scaled by the slot's
  engagement prior, clamped at 1.0× — a weak slot may price below the
  category floor to attract fill, but a premium slot never surcharges
  above it. The invariant this preserves is the one every guardrail here
  serves: *the floor a bidder faces is never derived from their own bids
  plus a markup.* Each rule alone looked safe with a multiplier above it;
  composed, they once strangled a live category — so the invariant is now
  enforced at the layer auctions actually consume.

One honest caveat: in a perfectly homogeneous market — every bidder at the
same CPM — every floor below the common bid earns identical revenue, and the
optimizer settles anywhere on that plateau. That is correct behavior, and a
reminder of what this component is: not intelligence, just a well-designed
experiment that never stops running.
