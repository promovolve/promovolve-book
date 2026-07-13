# Winner Selection: MAB vs Highest Bid

Traditional exchanges pick a single winner — the highest bidder — and move on. Promovolve takes a fundamentally different approach: it shortlists multiple candidates at auction time, then uses Thompson Sampling at serve time to learn which creative actually performs best.

## Traditional: Highest Bid Wins

In a standard ad exchange, winner selection is simple:

```
Bids received:    $8.00,  $5.50,  $3.20
Winner:           $8.00
Price paid:       $5.51   (second-price: winner pays $0.01 above second bid)
```

The logic is purely financial: whoever is willing to pay the most gets the impression. The creative's quality, relevance to the page, or likelihood of being clicked plays no role in the decision.

### Why this is a problem

**CTR is invisible.** A campaign bidding $8 CPM with a 0.5% click-through rate beats a campaign bidding $3 CPM with a 5% CTR. The publisher serves a worse ad and makes less money per click. The advertiser with the better creative loses despite offering more value to readers.

**There is no learning mechanism.** The exchange doesn't track whether the winning creative gets clicked. It doesn't know if the $8 bid was worth it. Each auction is independent — the system never gets smarter.

**The winner's curse.** In a competitive auction, the highest bidder is statistically the one who overestimated the impression's value the most. Sophisticated DSPs account for this; small advertisers don't, and overpay.

**New entrants can't compete.** A new advertiser with a potentially excellent creative but a conservative bid never wins, never gets impressions, and therefore never has a chance to prove itself. The system has no exploration — only exploitation of whoever bids highest today.

## Promovolve: A Two-Phase Selection System

Promovolve splits winner selection into two phases: **fair shortlisting** at auction time (when content is classified on-demand) and **adaptive selection** at serve time (when a user arrives). This separation is the key design difference.

### Phase 1: Auction-Time Fair Shortlisting

Instead of picking a single winner, the AuctioneerEntity shortlists multiple candidates per ad slot with a per-campaign diversity guarantee:

```
3 campaigns, 3 slots → each campaign gets exactly 1 slot
2 campaigns, 3 slots → each gets 1, fill the 3rd with the best remaining creative
4 campaigns, 3 slots → top 3 by CPM each get 1 slot
```

The algorithm:
1. Sort all candidates by CPM descending, with **pre-approved creatives preferred** as a tiebreaker (publishers can approve creatives before they enter the auction — approved creatives win ties over unapproved ones)
2. Group by campaign, pick the best creative per campaign
3. If there are more campaigns than slots, the top campaigns by CPM each get one slot
4. If there are fewer campaigns than slots, every campaign is guaranteed representation, and remaining slots are filled with next-best creatives

**Why this matters:** In a traditional exchange, a single high-budget campaign can monopolize every impression. Promovolve's diversity guarantee ensures that every participating campaign gets representation in the candidate pool, giving Thompson Sampling a diverse set to learn from.

### Phase 2: Serve-Time Thompson Sampling

When a user loads a page, Thompson Sampling selects among the shortlisted candidates. The scoring formula:

```
score = sampledCTR × CPM^α
```

Where `sampledCTR` is drawn from a Beta distribution based on observed performance over a 60-minute rolling window:

```
sampledCTR ~ Beta(clicks + 1, impressions - clicks + 1)
```

The exponent **α (`bidWeight`) is publisher-configurable** and controls how aggressively price competes with quality:

| α    | Profile     | Effect                                         |
|------|-------------|------------------------------------------------|
| 0.3  | Discovery   | Quality dominates; small advertisers compete   |
| 0.5  | Balanced    | `sqrt(CPM)` — the default                     |
| 0.7  | Revenue     | Higher bids win more often                     |

At α=0.5 a $10 CPM is only ~3.2× better than a $1 CPM (not 10×). CTR is the multiplicative factor: a creative that readers actually click beats one that merely bids high.

### A worked example

Three campaigns competing for the same slot at the default α=0.5. Campaign C is brand new with no data:

```
Campaign A: $5.00 CPM, 150 impressions, 5 clicks
  Beta(6, 146) → sample: 0.032
  score = 0.032 × √5.00 = 0.0716

Campaign B: $4.20 CPM, 22 impressions, 3 clicks
  Beta(4, 20) → sample: 0.091
  score = 0.091 × √4.20 = 0.1865

Campaign C: $3.80 CPM, 0 impressions, 0 clicks
  Beta(1, 1) → sample: 0.647  (uniform — could be anything)
  score = 0.647 × √3.80 = 1.261  ← wins (exploration)
```

Campaign C wins this request despite having the lowest CPM and no track record. This is **exploration** — the system gives the new creative a chance to prove itself. Over the next few dozen impressions, if C's true CTR turns out to be low, its Beta distribution narrows and it stops winning. If C turns out to be genuinely good, it earns a stable share of impressions.

### Pricing: quality-adjusted second-price

The exploiting winner doesn't pay its own bid. The selector records the next-best loser's score, then computes the **minimum CPM at which the winner's score still beats that runner-up given its sampled CTR**:

```
clearingCPM = (bestLoserScore / sampledCTR_winner) ^ (1/α)
```

Clamped to the site floor and to the winner's actual bid. A creative that earns a high sampled CTR therefore pays less than one that merely outbid; a creative bidding well above the runner-up gets the price compressed back toward what would have actually been needed to win. There is no upside to bid shading, so Promovolve runs no campaign-side bid optimizer at all.

Cold-start serves clear at the floor. Pinned re-encounters (see below) bypass clearing entirely — they're free.

A traditional exchange would never serve Campaign C. It would never get data. It would never have a chance.

### Cold start: getting new creatives off the ground

Thompson Sampling needs data to work, so Promovolve gives new creatives
two structured helps — both inside the scoring function, with no
separate strategy switch:

| Condition | Mechanism | Behavior |
|-----------|----------|----------|
| Candidate has 0 impressions | **Cold branch** | Score from `categoryScore ± 0.15 noise` (the auction's content-relevance signal) plus a `Beta(1,3)` fold-rate prior — a sensible starting score instead of a coin flip |
| First 50 impressions | **Newcomer bonus** | An additive +0.5 engagement bonus decaying linearly to zero, guaranteeing an exploration runway against confident incumbents |
| Beyond that | **Standard** | Full Thompson Sampling on the creative's own posteriors |

Both mechanisms produce identically-shaped scores, so selection stays a
single argmax at every lifecycle stage — no phase transitions, no forced
round-robin serving a plainly wrong ad just because it's new.

### The full selection pipeline

Thompson Sampling doesn't run in isolation. It's one step in a pipeline, and its position in that pipeline is deliberate:

```
1. ServeIndex lookup     → fetch cached candidates from local DData replica
2. Pin-honor check       → if the slot carries a dog-ear pin and the pinned
                           creative is still in the pool, bypass everything
                           below and serve the pin (free re-encounter)
3. Content recency       → drop candidates whose classification is stale
                           (> 48h since the page was last classified)
4. Frequency cap         → drop candidates the user has seen too many times
5. Pacing gate           → probabilistic throttle based on aggregate budget utilization
6. Thompson Sampling     → score and select among remaining candidates
7. Budget reservation    → reserve spend with the selected campaign
```

**Why pin-honoring runs first:** A dog-ear is the reader saying "I want to come back to this ad." Subjecting the pin to pacing gates or frequency caps would let throttling discard a bookmark the reader explicitly asked for. Pinned slots also skip CPM reservation — the re-encounter is treated as a free engagement signal, not a billable serve.

**Why pacing runs before Thompson Sampling:** If pacing ran after selection, Thompson Sampling would pick a creative, then pacing would sometimes throw it away. That wastes an exploration opportunity — we showed nothing, we learned nothing. By putting the pacing gate first, every request that makes it to Thompson Sampling produces a served impression and useful data.

### Budget reservation and graceful fallback

After Thompson Sampling selects a winner, the system attempts to reserve the spend:

```
1. Reserve spend with CampaignEntity
2. Verify budget status with AdvertiserEntity
3. On failure (budget exhausted) → try the next-best candidate by Thompson score
4. All candidates exhausted → return NoCandidates (HTTP 204)
```

In a traditional exchange, if the winner can't pay, the auction fails and the slot goes unfilled (or a low-quality fallback ad appears). Promovolve's multi-candidate model means there's always a next-best option waiting — graceful degradation without re-running the auction.

## Side-by-Side Comparison

| Dimension | Traditional (Highest Bid) | Promovolve (Thompson Sampling) |
|-----------|--------------------------|-------------------------------|
| **Selection criterion** | Price only | `sampledCTR × CPM^α` (α publisher-tunable) |
| **Number of candidates** | 1 winner | Multiple shortlisted per slot |
| **Pricing** | Second-price on bids | Quality-adjusted second-price — winner pays the minimum CPM that still beats the runner-up given its CTR |
| **Reader agency** | None — readers can't influence what they see | Dog-ear pins: readers bookmark ads they want to revisit |
| **Learning** | None — each auction is independent | Continuous — every impression updates the Beta posterior |
| **New creative discovery** | Impossible without outbidding the incumbent | Built-in via exploration; a decaying newcomer bonus guarantees brand-new creatives a runway |
| **Cold start** | New advertiser must bid high to win | Round-robin warmup guarantees initial data collection |
| **Failure handling** | Slot goes unfilled | Fall through to next-best candidate |
| **Publisher alignment** | Optimizes for advertiser spend | Optimizes for reader engagement (CTR), weighted by spend via α |
| **Short-term revenue** | Higher (always picks highest bid) | Sometimes lower (explores lower-CPM creatives) |
| **Long-term revenue** | Stagnant (no learning) | Higher (discovers high-CTR creatives that earn more clicks) |
| **Advertiser ROI** | Favors large budgets | Favors creative quality — a good ad at $3 CPM can beat a bad ad at $8 CPM |
