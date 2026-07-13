# Pin-Honoring at Serve Time

The dog-ear gives readers a way to bookmark an ad they want to come back to. The bookmark lives in the reader's own browser; this chapter is about what the server does when the bookmark comes back.

For the reader-side protocol — `FoldToken`, IndexedDB pin storage, the `/v1/dogear-event` endpoint — see [The Dog-Ear](../format/dog-ear.md). This chapter assumes the bootstrap has already read its IDB and forwarded the pin to the server as part of the batch serve request.

## Where the pin slots into the pipeline

The serve pipeline runs in this order:

```
1. ServeIndex lookup          → fetch cached candidates (local DData replica)
2. Classification freshness           → drop if classification is older than 48h
3. Frequency cap               → drop creatives this user has seen too often
4. Pacing gate                 → probabilistic throttle by aggregate budget
5. Site-wide pin exclusion     → off-page pins remove campaigns from the pool
6. Pin-honor (per-slot)        → if the slot carries a pin and the pinned
                                  creative is still in the pool, bypass the
                                  rest of this list and serve the pin
7. Quality-adjusted auction    → score, pick, clear at second-price
8. Budget reservation          → reserve at clearing price
```

The pin-honor check is per-slot, inside `batchReserveWithRetry`'s assignment loop. Pinned slots are sorted to the front of the assignment so the pinned creative's campaign locks the page-cap state before any non-pinned slot picks. Larger slots within each group still come first — pinned big-slot before pinned small-slot, then unpinned big-slot, then unpinned small-slot.

A pinned slot whose creative is found in the pool **never sees the pacing throttle, the frequency cap, or the auction**. The reader chose this creative; the system honors that choice rather than relitigating it through gates designed for un-bookmarked ads.

## The honor path

When `slot.pin` is set and the pool contains a `CandidateView` with that `creativeId`:

```scala
Protocol.BatchSlotOutcome(
  slotId        = slot.slotId,
  winner        = Some(c),
  clearingPrice = CPM.zero,                              // free re-encounter
  requestId     = java.util.UUID.randomUUID().toString,
  dogear        = Some(DogearOutcome(honored = true)),
)
```

Three things happen — and three things explicitly don't:

- **Reservation skipped.** The pinned candidate is not passed to `batchReserveOne`. No round-trip to `CampaignEntity` or `AdvertiserEntity` for budget gating.
- **Clearing price is zero.** Folds are free engagement signals (see [Quality-Adjusted Pricing](../auction/quality-adjusted-pricing.md)). Pin re-encounters extend that — the reader's bookmark gets honored at no charge to the advertiser.
- **Pacing throttle skipped.** The pacing gate runs before pin-honor in the request lifecycle, but for the pinned slot specifically, no throttling decision applies — the slot bypasses budget reservation entirely, so pacing has nothing to gate.

The slot **does** still consume a campaign and a creative in the page-cap state:

```scala
used = used + c.campaignId.value
usedCreatives = usedCreatives + c.creativeId
```

This is deliberate. Without the consume, a non-pinned slot on the same page could pick another creative from the bookmarked campaign and you'd see two different ads for the same advertiser side-by-side. The pin is a "save for later" gesture; surfacing other creatives from that advertiser would feel like recommendation-engine stalking.

## Fallthrough: when the pin can't be honored

A pin can fail for two reasons:

**Transient miss.** The pinned creative is still approved on this site, but it isn't in this particular batch's pool — maybe the auction's eligibility filters happened to drop it (size mismatch with the slot, freshness window, etc.). The reader's bookmark is still valid; the client should keep the pin and re-honor on the next page.

**Truly removed.** The pinned creative has been revoked from approval — campaign paused, creative unassigned, advertiser removed. The bookmark is dead; the client should clean up its IDB entry.

The server distinguishes these with the `isApproved` predicate, which is supplied by the live `AdServer` actor from its `persistedApprovedIds` set:

```scala
def dogearFallthrough(
    slot: BatchSlotSpec,
    isApproved: CreativeId => Boolean,
): Option[DogearOutcome] =
  slot.pin match {
    case Some(cid) if !isApproved(cid) =>
      Some(DogearOutcome(honored = false, reason = Some("creative_removed")))
    case _ =>
      None
  }
```

Two outcome shapes the bootstrap acts on:

| Server response                                          | Bootstrap action                                                          |
|----------------------------------------------------------|---------------------------------------------------------------------------|
| `dogear = None`                                          | No pin or transient miss — keep the IDB entry, retry next page             |
| `dogear = Some(DogearOutcome(honored=true))`             | Pin served — render the bookmarked creative                                |
| `dogear = Some(DogearOutcome(honored=false, reason="creative_removed"))` | Bookmark is dead — delete the IDB entry                  |

The bootstrap's IDB cleanup happens in `bootstrap.ts`'s `displayImpl`: when the response carries `creative_removed`, the slot's pin row is deleted before the next render.

## The `isApproved` gate matters

The gate distinguishes "creative not in pool right now" from "creative is gone for good." Treating both as "remove the pin" would make pins unreliable — a creative that happened to fall out of one auction's eligibility would lose every reader's bookmark. Treating both as "keep the pin" would leave dead bookmarks in IDB forever.

The gate's source of truth is `persistedApprovedIds` — the AdServer's view of what's currently approved on this site. Pause a campaign, that campaign's creative IDs are removed from `persistedApprovedIds` immediately (see the `CampaignPaused` handler at line 1107 of `AdServer.scala`); the next pin attempt for one of those creatives gets `creative_removed` and the IDB cleans up.

## Site-wide pin exclusion

A pin on slot S₁ of page P is also a signal about other slots on page P, and other pages on the site:

**Same-page (page-cap consume).** Already covered: the pinned creative's campaign goes into `used` so other slots on the same page can't pick another creative from that advertiser.

**Off-page (site-wide block).** When the bootstrap submits a batch request, it sends along its full set of pins — including pins on slots that aren't on this page. The server resolves those off-page pins through `creativeRepo.get()` to find their `campaignId`, then passes both as exclusions to the batch:

```scala
BatchSelect(
  ...
  excludedCreatives = offPagePinCreatives,   // pinned somewhere else on this site
  excludedCampaigns = offPagePinCampaigns,   // their advertisers
)
```

`excludedCreatives` and `excludedCampaigns` seed the `usedCreatives` and `used` sets at the start of `batchReserveWithRetry`. So a creative the reader pinned on a *different page* can't appear as a normal-auction winner on *this page*, and neither can any other creative from that advertiser.

The reasoning is the same as the same-page case, scaled up: the dog-ear is a save-for-later, and showing other ads from that advertiser elsewhere on the site would dilute the bookmark's value.

## Tests as contract

`AdServerPinHonorSpec` pins the pin-honor semantics in eight cases:

1. Honor a pin when the creative is in the pool, bypassing reservation.
2. Fall through to auction with `creative_removed` when the pinned creative is no longer approved.
3. Leave `dogear = None` on a slot that carried no pin.
4. Honor a pin even when the pinned creative's CPM is below the site floor (pins aren't auction wins).
5. Honor a pin even when the pinned creative's campaign is in `pageBlocked` (soft cap doesn't apply to explicit reader choices).
6. Lock the pinned creative's campaign so other slots can't double up.
7. Lock the pinned `creativeId` so it can't be re-served at a different size on another slot.
8. Honor multiple pins independently in a single batch.

These tests are the authoritative description of what pin-honoring does. Future refactors can't silently regress without breaking them.

## Source of truth

- `modules/core/src/main/scala/promovolve/publisher/delivery/AdServer.scala` — `batchReserveWithRetry` (per-slot pin-honor inside the assignment loop), `dogearFallthrough` (the `isApproved` gate)
- `modules/core/src/main/scala/promovolve/publisher/delivery/Protocol.scala` — `BatchSlotSpec.pin`, `DogearOutcome`
- `modules/api/src/main/scala/promovolve/api/ServeRoutes.scala` — off-page pin resolution to `excludedCreatives` / `excludedCampaigns`
- `modules/core/src/test/scala/promovolve/publisher/delivery/AdServerPinHonorSpec.scala` — semantics frozen in tests
- `platform/banner-bootstrap/src/bootstrap.ts` — client-side IDB cleanup on `creative_removed`
