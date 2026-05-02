# The Dog-Ear

Pick up a magazine, fold the corner of an interesting page, come back to it later. Promovolve gives readers the same affordance for ads. The bookmark is reader-driven, lives in the reader's own browser, and survives without any server-side profile of the reader.

This chapter covers the reader-side protocol. The server-side counterpart — how the pin is honored when the reader returns — is in [Pin-Honoring at Serve Time](../serving/pin-honoring.md).

## The mechanic

The reader expands an ad, swipes through its pages, and decides they want to remember it. Tapping the small folded-corner control sets the pin. The corner of the creative visibly clips, both in the expanded view and (on collapse) in the publisher's slot. The next time the reader lands on a page where that advertiser is eligible, the bookmarked creative is the one served.

A second tap unfolds the corner. The pin is removed.

```
┌─────────────────────┐         ┌─────────────────────┐
│ unfolded            │   tap   │ folded            ◢ │
│ (cover full)        │ ──────> │ (corner clipped)    │
└─────────────────────┘  fold   └─────────────────────┘
                                          │
                                       reload
                                          ▼
                          ┌─────────────────────┐
                          │ folded; same        │
                          │ creative re-served  │
                          └─────────────────────┘
```

The folded corner is rendered with a CSS `clip-path` polygon on the banner, and a separate `<div>` styled as the flap behind it (`6cqmin` square, drop-shadowed). Same Shadow DOM machinery as the rest of the [magazine format](./overview.md).

## Why pin storage lives in the reader's browser

Traditional retargeting works by writing a cookie or device-graph entry on the advertiser's behalf, then matching that identifier on every subsequent ad request across the web. The reader's interest is captured by a third party, in a system the reader can't inspect.

Promovolve inverts that. The pin lives in the reader's IndexedDB, under the publisher's origin, scoped to a `pins` store keyed by `slotId`:

```ts
{ slotId, creativeId, page, foldedAt, expiresAt }
```

No personal identifier. No cross-origin storage. No sync. The server learns "someone with that browser folded that creative on that slot," and only when the bootstrap chooses to surface the pin in a serve request. The reader can clear it by clearing site data — same gesture as removing any browser bookmark.

The IDB schema lives in `platform/banner-bootstrap/src/dogear-storage.ts`. The TTL is 7 days by default; the server can suggest a longer expiry (e.g., the campaign's `endAt`) and the client takes the minimum, capped at 90 days hard so abandoned rows don't pile up indefinitely.

## The FoldToken protocol

The fold has to be *authenticated* against a real serve. Otherwise anyone could POST `/v1/dogear-event` with arbitrary `(slotId, creativeId)` and pin a creative they never saw. The `FoldToken` is the credential.

When the server picks a winner for a slot and the campaign opted into dog-ear, it mints a token and ships it to the client as `data-fold-token` on the banner element:

```
<base64url(payload)>.<base64url(hmac)>

payload  = pub | url | slot | cid | ver | bucket | camp | adv | nonce
hmac     = HMAC-SHA256(canonical || camp | adv | nonce, publisher_secret)
```

The token is **stateless**. The server doesn't store it; it just signs it. When the client redeems the token by POSTing to `/v1/dogear-event`, the server reverses the steps:

1. Split on `.`; base64-decode the payload; parse fields.
2. Verify the slot and creative match what the client claims.
3. Recompute the HMAC with the publisher's secret; compare in constant time.
4. Check freshness: bucket within 30 minutes of now.

If any step fails, the reason is one of `bad_format | bad_payload | slot_mismatch | creative_mismatch | bad_signature | stale` and the server returns `403 Forbidden`. The full implementation is `modules/core/src/main/scala/promovolve/common/FoldToken.scala`.

A few design choices worth pointing out:

- **30-minute freshness window**, vs the 3-minute window for `/v1/imp` and `/v1/click`. A reader expanding a creative might browse the pages, decide, fold — that takes longer than the impression beacon is willing to wait. 30 minutes is the upper bound on "the reader is still on this serve."
- **Camp/adv ride inside the signed payload.** The fold endpoint records the engagement against the right campaign without a serve-time lookup.
- **Stateless** is deliberate. There's no fold-token table to maintain, no expiration sweep, no replay-protection cache (idempotency lives downstream — see below). HMAC + freshness is enough.

## `POST /v1/dogear-event`

The endpoint takes a JSON body for both fold and unfold:

```json
{
  "pub":         "yuki-site",
  "url":         "https://yukiblog.jp/autumn-hikes",
  "creativeId":  "ryokan-magazine-001",
  "slotId":      "sidebar-1",
  "event":       "fold",
  "foldToken":   "eyJ…<payload>…fA.k7Lz…<hmac>…",
  "page":        2
}
```

`event` is `"fold"` or `"unfold"`. `foldToken` is required for fold, ignored for unfold. `page` is the page index the reader was on when they folded — saved into IDB so the re-encounter opens at the same page.

**Fold path:**
1. Verify the token (HMAC + freshness + slot/cid match).
2. Compute `requestId` = 16-char hex hash of the full token. Same hash function the spend Bloom filter uses, so the journal idempotency layer dedups consistent replays.
3. Write a `TrackEvent` to the tracking journal via `EventLog.logFold`. The dashboard projection counts folds.
4. Return `204 No Content`.

**Unfold path:**
1. No token — the reader can always remove their own pin.
2. Write a telemetry-only `TrackEvent` via `EventLog.logUnfold`.
3. Return `204`.

The unfold journal entry exists for the **pin retention metric** the dashboard projection computes: `(folds − unfolds) / folds`. Advertisers see how often readers actually come back versus folded then changed their minds.

## Server-side: engagement signal, not billing

Folds are **free**. There is no per-fold CPM, no per-fold budget, no separate fold spend ledger:

```scala
// LearningEventLog.logFold (excerpt)
// Folds are an engagement signal, not a billing event.
```

The server writes the journal entry (so the dashboard can show fold counts and pin retention rate), but no spend is reserved, no auction price is charged. The original impression that produced the fold token already cleared at the [quality-adjusted second price](../auction/quality-adjusted-pricing.md); the fold itself is a free signal layered on top.

This is a pricing decision, not just a billing accident. Charging per fold would punish advertisers whose creatives readers want to remember — exactly the wrong incentive.

## The re-encounter

The reader visits another page (or reloads the same one). The bootstrap runs:

1. **Read IDB.** Open the `promovolve-dogear` database, scan the `pins` store, drop any rows past `expiresAt`.
2. **Submit pins with the batch request.** For every slot on the new page, look up the IDB row by `slotId`. Slot-on-page pins go into `req.pins[]` as `(slotId, creativeId)`. Slot-not-on-this-page pins also go into the request — the server uses them for the [site-wide pin exclusion](../serving/pin-honoring.md#site-wide-pin-exclusion).
3. **Server picks the winner.** [Pin-Honoring at Serve Time](../serving/pin-honoring.md) describes the path: pinned slots bypass the auction, clear at zero, emit `DogearOutcome(honored=true)`.
4. **Bootstrap renders.** When the response carries `dogear.honored=true`, the bootstrap renders the bookmarked creative, sets `data-pinned-page` to the page index from IDB so the banner opens at the same page the reader folded, and adds `?dogeared=1` to the impression URL so the dashboard can split dogeared from organic impressions.

A re-encountered creative still fires its impression beacon (the publisher's slot was filled, regardless of how it got chosen). It still fires its click beacon if the reader expands it again. The CTA still works.

The whole flow takes one IDB read on the client, no extra server round-trip, and slots into the same `BatchSelect` the bootstrap was already going to send.

## Revoke: when a creative is no longer eligible

Pins outlive auctions. A reader who folds an ad today might come back next month, by which time the campaign could have been paused, the creative unassigned, or the advertiser deleted. The system has to distinguish "your pin is fine, just not in this batch" from "your pin is dead, clean it up."

**Pause path.** When `CampaignEntity` receives `CampaignPaused`, the AdServer's `persistedApprovedIds` set has the campaign's creative IDs removed. Next time a reader's pin is for one of those creatives, the server's `dogearFallthrough(slot, isApproved)` returns `Some(DogearOutcome(honored=false, reason="creative_removed"))`.

**Bootstrap cleanup.** The bootstrap's `displayImpl` reads the `creative_removed` reason and deletes the IDB row before the next render. The pin is gone; the slot runs a normal auction.

The full mechanism is documented in the pin-honoring chapter. The key thing for this chapter is: the bookmark protocol terminates cleanly. A revoked creative doesn't leave dead IDB rows; an active-but-not-in-this-batch creative doesn't lose its pin.

## What this replaces

Retargeting, basically — but reader-driven instead of advertiser-driven.

| Traditional retargeting                                 | Dog-ear pin                                              |
|---------------------------------------------------------|----------------------------------------------------------|
| Advertiser drops a tracking pixel; server logs the visit | Reader explicitly folds the ad's corner                  |
| Identifier joined across sites via DSP/DMP              | IDB row scoped to the publisher's origin                  |
| Reader can't see or edit their own profile              | Reader can clear it like any browser data                  |
| Bid premium for "high-intent" retargeting impressions   | Re-encounter is free for the advertiser, free for the reader |
| Server-side privacy compliance burden                    | No personal data crosses the wire — no compliance burden  |

The premise is that an *explicit* reader vote is a stronger signal than any inferred preference. A reader who folds your ad has told you, by a deliberate gesture, that they want to come back to it. That's worth more than a probabilistic match against their browsing history — and it costs nothing to honor.

## Source of truth

- `modules/core/src/main/scala/promovolve/common/FoldToken.scala` — token mint + verify
- `modules/api/src/main/scala/promovolve/api/TrackRoutes.scala` — `/v1/dogear-event` handler
- `modules/api/src/main/scala/promovolve/api/ServeRoutes.scala` — `foldTokenFor`, mints token at serve time
- `modules/api/src/main/scala/promovolve/api/LearningEventLog.scala` — `logFold` / `logUnfold`
- `modules/core/src/main/scala/promovolve/publisher/delivery/AdServer.scala` — pin-honor + `dogearFallthrough` (see [Pin-Honoring](../serving/pin-honoring.md))
- `platform/banner-bootstrap/src/dogear-storage.ts` — IDB schema and TTL math
- `platform/banner-bootstrap/src/bootstrap.ts` — pin submission, re-encounter, revoke cleanup
- `platform/banner-component/src/banner.ts` — fold/unfold UI events
