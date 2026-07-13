# Against the Grain of Ad Tech

Promovolve diverges from conventional programmatic advertising on almost
every axis. This chapter is the honest scorecard — including what the
conventional stack does better.

## The differences

**Per-impression auctions → periodic auctions.** RTB gives every impression
its own auction under a ~100ms deadline, which forces every participant to
precompute everything and answer with a cache anyway. Promovolve moves the
auction off the hot path entirely: it runs at classification time and on
change events, and serving is a local cache read plus a Beta draw. The
trade: candidate pools can be minutes stale. Event-driven re-auctions with
a one-second debounce keep the staleness bound tight where it matters.

**User targeting → content targeting.** No cookies, no profiles, no
consent apparatus, because there is nothing to consent to. The trade is
real: no retargeting, no frequency-managed brand campaigns across sites, no
audience segments. Promovolve's bet is that page context — read by an LLM
rather than keyword-matched — recovers most of the relevance at none of the
privacy cost, and the dog-ear gives *readers* the retargeting control that
ad tech gives advertisers.

**Highest-bid-wins → sampled quality scores.** A traditional exchange never
learns whether the winner was any good. Promovolve's selection is a
learning system: engagement posteriors sharpen with every impression, new
creatives get exploration in proportion to their uncertainty, and the
formula (`engagement × CPM^α`) lets a well-made ad beat a well-funded one.

**Bid landscapes → nothing to optimize.** DSPs exist substantially to shade
bids. Quality-adjusted second pricing removes the incentive: your price is
set by the runner-up and discounted by your own engagement rate. Promovolve
ships no bid optimizer, and that absence is a feature of the mechanism, not
a missing roadmap item.

**Fixed IAB sizes → fluid creatives.** One layout reflows into any slot.
Small advertisers produce one creative from one landing page URL; the
pipeline (browser extraction → LLM copywriting → deterministic
contrast-checked styling → vision-model verification) replaces the design
team they don't have.

**Exchange-side yield tools → publisher-side everything.** Approval queues,
domain blocks, per-category measured floors — the controls sit with the
publisher, and the floor optimizer's objective is the publisher's served
revenue, measured, not modeled.

## What the conventional stack still does better

Honesty requires the other column. Programmatic ad tech delivers **scale
and liquidity** Promovolve does not: demand from thousands of buyers through
open exchange protocols, remnant fill for any inventory anywhere, and
cross-site campaign tooling (reach, frequency, brand-lift measurement) that
a content-targeted, single-platform system structurally cannot offer. RTB's
per-impression auction also prices *this reader now* — worth real money for
performance advertisers — where Promovolve deliberately prices only *this
page*.

Promovolve is not trying to beat the exchange at the exchange's game. It is
a different deal: for publishers who want curated, reader-respecting
monetization with controls they actually hold, and for advertisers — small
ones especially — who want their landing page turned into a magazine ad and
priced by an auction that doesn't require a quant team to enter honestly.

The system described in this book is small enough to read, honest enough to
audit, and open source so you can do both.
