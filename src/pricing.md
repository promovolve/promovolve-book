# What the Winner Pays

Promovolve is second-price at heart: the winner pays what was needed to win,
not what they offered. But the score that wins is \\( \text{engagement} \times \text{CPM}^{\alpha} \\), not
a bare bid — so the clearing price must be quality-adjusted too.

## Sample for allocation, price on means

Selection uses sampled (noisy) values on purpose; pricing must not. A price
that depended on a random draw would make identical impressions cost
different amounts. So the system **allocates on samples, prices on
posterior means**: after the winner is chosen, the runner-up's score is
recomputed from mean engagement rates, and the winner pays the minimum CPM
at which it *still would have won*:

\\[ \text{clearingCPM} = \left(\frac{\text{runnerUpScore}}{\text{winnerEngagement}}\right)^{1/\alpha} \\]

clamped between the slot's floor and the winner's own bid. Intuition: invert
the scoring formula and ask, "with your engagement rate, what's the cheapest
bid that still beats the next-best candidate?"

Two properties fall out:

- **Quality is a discount.** A creative readers engage with needs a lower
  CPM to hold its rank, so it *pays less* than a mediocre creative bidding
  identically. Advertisers improve their price by improving their ad.
- **Bidding is honest — where there is competition.** Raising your bid
  above what's needed doesn't raise your price (the runner-up sets it);
  lowering it only risks losing. Floors reinforce this rather than
  undermining it: in a competitive category the floor is capped below
  the second bid, so it can never wedge itself between you and the
  runner-up and become your price. There is no bid-shading strategy to
  compute (*shading*: bidding below your true value to dodge overpaying
  — the daily homework of first-price auctions), which is why Promovolve
  ships no campaign-side bid optimizer — the mechanism leaves nothing
  for one to do. The honest exception: a category *monopolist* pays
  ~99% of whatever they bid, because the floor tracks their bid (see
  [Floor Optimization](./floors.md)). That is first-price-like by
  design — full extraction where no runner-up exists to set a price —
  and it lasts exactly until a second bidder shows up.

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
  see [Floor Optimization](./floors.md) — which pegs the floor to 99% of
  a lone bidder's bid. Combined with this pricing rule, that is how "a
  monopolist pays what they offered" is actually implemented: no code
  charges the bid directly; the floor walks up to it and the no-runner-up
  path prices at the floor.)
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

## One currency in the books, any currency on screen

Everything above — bids, floors, clearing prices, the ledger — is
denominated in US dollars, and stays that way. Currency is one more place
where a system can quietly lie to itself: convert at write time and your
books inherit every exchange-rate wobble; convert per transaction and you
manufacture a second ledger with a precision the first one never had.
Promovolve does neither. The books know exactly one currency.

What *does* convert is the screen. Each user can pick a display currency
in their preferences, and read-only amounts — spend, budgets shown as
figures, earnings, wallet balances — render converted at a single daily
reference rate, uniformly, every converted figure marked with `≈` and
every page that converts carrying the rate and its date. Yesterday's
earnings will read slightly differently tomorrow; that is honest, because
the converted number was never a fact — it is what the dollar fact is
worth today.

Three things never convert, deliberately: input fields (a budget is
*entered* in dollars, with the converted figure shown beside it — nobody
should type ¥15,000 into a dollar box), auction pricing detail (floors
and CPMs are the marketplace's own arithmetic), and the operator's pages
(whoever runs the books reads the books). When a publisher is eventually
paid in their own currency, that conversion happens at the bank at payout
time and is recorded as what it actually was — a banking fact, not a
display estimate.
