# Quality-Adjusted Pricing

The auction's scoring rule and its pricing rule are two halves of the same mechanism. The score decides who wins; the price decides what they pay. This chapter is about the second half.

For the score itself — `score = sampledCTR × CPM^α` and the publisher's α dial — see [Scoring Formula](../serving/scoring-formula.md). This chapter assumes you know the score and asks: given that score, what does the winner actually pay?

## The clearing formula

When a slot has at least two eligible candidates, the winner pays the smallest CPM at which their score still beats the runner-up's score:

```
clearingCpm = (bestLoserScore / sampledCTR_winner) ^ (1/α)
```

Clamped to `[siteFloor, winner.cpm]` — never below the publisher's floor, never above what the campaign actually bid.

This is the inverse of the score formula. Substitute `clearingCpm` back into `score = sampledCTR × CPM^α` and you get exactly `bestLoserScore` — a tie. One cent more, the winner still beats the runner-up. So `clearingCpm` is the *minimum bid that would have still won*.

## A worked example

Default `α = 0.5` (sqrt). Two candidates competing for one slot:

```
Winner:     bid $5.00, sampled CTR 4.0%
Runner-up:  bid $4.00, sampled CTR 2.5%

Winner score:    0.04 × √5    = 0.0894     ← higher, wins
Runner score:    0.025 × √4   = 0.0500
```

What does the winner pay?

```
clearingCpm = (0.0500 / 0.04) ^ (1 / 0.5)
            = 1.25 ^ 2
            = $1.5625
```

The winner bid $5.00 but pays $1.5625. Sanity check: at $1.5625 the winner's score would be `0.04 × √1.5625 = 0.04 × 1.25 = 0.05` — exactly the runner-up's. Anything above $1.5625, the winner still wins. Anything below, they lose.

The 69% discount from bid to clearing is the **quality discount**: the winner's CTR was 1.6× the runner-up's, and the auction translated that quality gap into a price gap. A campaign that earns clicks pays less per impression than one that merely outbid the field.

## Edge cases

**No runner-up.** If only one candidate is eligible for a slot (after the per-campaign dedup, the size match, and the floor filter), there's nothing to clear against. The winner pays the site's floor:

```
bestLoserScore = 0  →  clearing = siteFloor
```

This matches the per-slot Solo path's semantics. A bidder alone in a slot pays the publisher's reserve, not their bid.

**Zero CTR.** If the winner's sampled CTR is zero (degenerate cold-start sampling), the formula divides by zero. Falls back to floor.

**Non-positive α.** Defensive — if `α ≤ 0` the formula is undefined. Falls back to floor.

**Pathologically high runner-up.** If the formula produces a clearing above the winner's bid (a runner-up so strong that the winner barely won), clamps to the winner's bid. Campaigns never owe more than their max CPM.

**Pathologically low.** If the formula produces a clearing below the publisher's floor (a runner-up so weak that the math collapses), clamps to the floor.

The fallback rule across all degenerate cases is the same: **charge floor**. That's the safest default — never overcharge, always respect the publisher's reserve.

## Why this makes campaign-side bid optimization pointless

In a first-price auction (winner pays their bid), advertisers have to *shade* their bid: bid below their true value to capture surplus. Bid too high and you overpay; bid too low and you lose the auction. There's a sweet spot, and the sweet spot depends on what competitors are doing. So a sophisticated DSP runs a bid optimizer — typically reinforcement learning — to find the right shading factor.

In Promovolve's auction, the price is set by the runner-up, not by the winner's bid. So bidding higher than your true value can't make you pay more (the runner-up doesn't move when you do). And bidding below your true value can only cost you — if you'd have won at honest value but lost at the shaded value, you lost an impression that was profitable for nothing.

The dominant strategy reduces to: **bid your true value**. The auction extracts the rest.

This is why Promovolve has no campaign-side reinforcement-learning agent. A previous version had per-campaign DQN agents tuning bid multipliers; they were removed because there was nothing for them to learn. The auction mechanism handles what the agent was trying to handle.

## Family resemblance: GSP, not VCG

Single-slot Promovolve auctions are equivalent to Vickrey/VCG: winner pays the smallest bid that beats the runner-up given their CTR. Truthful bidding is the dominant strategy.

Multi-slot Promovolve auctions are **Generalized Second-Price (GSP)** with quality scoring — the same mechanism class historic Google AdWords used. Each slot independently clears against its own per-slot runner-up. This is *not* VCG: a true VCG implementation would compute the externality the winner imposes on the entire allocation by re-running the assignment with the winner removed, and price each slot at that marginal welfare difference. Promovolve doesn't do that — it just looks at the second-best score in each slot's eligible set.

The difference matters when claiming game-theoretic properties:

- **Single slot**: provably truthful (Vickrey).
- **Multi-slot**: approximately truthful (GSP). Pathological coordinated-lying scenarios exist in theory but require collusion among multiple bidders, and the equilibrium is "close enough to truthful" in practice that nobody bothers gaming it. Microsoft Bing tried switching AdWords-style auctions from GSP to true VCG in 2007 and rolled back — VCG's marginal-welfare math is too sensitive to noisy CTR estimates and the pricing was hard to explain to advertisers.

The book chapters that say "honest bidding is the dominant strategy" are accurate for single slots and a fair approximation for multi-slot batches. They don't claim VCG.

## Pinned re-encounters bypass clearing

A slot that carries a dog-ear pin and finds the pinned creative still in the auction pool **bypasses pricing entirely**:

```
clearingPrice = CPM.zero
```

The pin is a reader's bookmark; the re-encounter is a free engagement signal, not a billable serve. No CPM clearing runs, no budget reservation, no pacing throttle. See [Pin-Honoring at Serve Time](../serving/pin-honoring.md) for how the pin path slots into the broader pipeline.

## Implementation

The pricing formula lives in one place:

```scala
ThompsonSampling.qualityAdjustedClearing(
    winnerSampledCtr: Double,
    winnerBid: CPM,
    bestLoserScore: Double,
    alpha: Double,
    siteFloor: CPM,
): CPM
```

Pure function, no actor state. Used by:

- `AdServer.pickBestForSlot` — computes clearing at pick time against the slot's per-slot runner-up
- `AdServer.batchAssign` — same logic for the legacy/test entry point
- `AdServer.batchReserveWithRetry` — threads the clearing price through reservation, `BatchSlotOutcome.clearingPrice`, and the pending-spend delta. Reservation reserves at clearing, not at bid; pending-spend tracks clearing, not bid.

The formula contract is pinned by `QualityAdjustedClearingSpec` — no-runner-up → floor, zero CTR → floor, α≤0 → floor, α=0.5/0.7 numeric correctness, clamp up to bid, clamp down to floor. Future refactors can't silently regress to first-price clearing without breaking those tests.

## Source of truth

- `modules/core/src/main/scala/promovolve/publisher/delivery/ThompsonSampling.scala` — `qualityAdjustedClearing`, `cpmScore`, `scoreCandidate`
- `modules/core/src/main/scala/promovolve/publisher/delivery/AdServer.scala` — `batchAssign`, `pickBestForSlot`, `batchReserveWithRetry`
- `modules/core/src/test/scala/promovolve/publisher/delivery/QualityAdjustedClearingSpec.scala` — formula contract
