# The Magazine Format and the Dog-Ear

Promovolve serves exactly one kind of ad: an expandable magazine. The format
is not a stylistic preference — half the system's design depends on it.

## Collapsed and expanded

In the page, the creative is *collapsed*: a cover — image, headline, an
advertiser tag — occupying whatever rectangle the publisher provided. Tapped,
it expands into a full-screen overlay the reader swipes through like a small
magazine: a cover page, a story page, and a call-to-action page. Collapse it
and the page is exactly as it was.

The three-page narrative is fixed by design. It gives the LLM copywriter a
stable dramatic structure (hook, substance, ask), gives the designer a
stable layout target, and gives readers a consistent gesture vocabulary. The
renderer is a self-contained script that mounts the creative inside Shadow
DOM, so publisher CSS cannot leak in and the ad cannot leak out.

The event vocabulary follows the format. Opening the magazine fires the
**click** — in this format a click *is* the expand, a reader choosing to
spend attention rather than to leave the page. Tapping any page of the
spread navigates to the landing page (the **CTA** event). And a **fold** is
the dog-ear gesture below — bookmarking the ad — which is the strongest
signal of all: serve-time selection learns from clicks *and* folds, with
folds weighted double.

Folds cost the advertiser nothing. There is no cost-per-fold billing
anywhere in the system — a bookmark volunteered by the reader is not a
billable event.

## Fluid, not fixed-size

A creative is a *layout*, not a bitmap. The same creative renders into a
leaderboard, a rectangle, or a half-page rail; the renderer reads the slot's
geometry at mount time and reflows — container queries, not server-side
variants. Publishers offer whatever slot shapes suit their design;
advertisers maintain one creative instead of a matrix of sizes. This is what
lets a pilates studio with no design staff participate at all.

## The dog-ear

The corner of every folded creative can itself be folded down — a dog-ear,
the gesture readers already use on paper. A dog-eared ad is a bookmark:

- **It lives in the reader's browser.** The pin is stored in IndexedDB,
  keyed by slot, and presented back to the server with each ad request. The
  server signs fold state into a stateless token; it never stores who
  bookmarked what, because it never knows who anyone is.
- **It wins the slot.** At serve time, a valid pin bypasses the auction,
  scoring, pacing, and budget entirely: the bookmarked creative simply
  serves. On pages where the pinned slot doesn't exist, the pinned
  advertiser is *excluded* from the normal auction site-wide — the system
  must never burn a reader's saved ad as an ordinary impression, and must
  never chase the reader with the same advertiser's other creatives.
- **It is free and unlearned.** Pinned re-encounters are counted in their
  own `dogeared_*` counters and excluded from spend, from CTR learning, and
  from every optimization loop. A bookmark is the reader's choice; the
  moment the system monetizes or learns from it, it stops being one.
- **It heals itself.** If the advertiser leaves the site, the campaign ends,
  or the creative is revoked, the serve response tells the client which pins
  are stale, and the client deletes them from IndexedDB. A transient lookup
  failure never deletes a pin — only a confirmed "this creative is gone"
  does.

One consequence surprises people operating the system: if you dog-ear an ad
on your own site while testing, that advertiser stops appearing in normal
rotation for you. The system is working as designed — your browser asked it
to.
