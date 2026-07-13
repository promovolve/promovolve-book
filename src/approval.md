# The Publisher's Gate

A magazine editor decides which ads appear next to their writing. Promovolve
keeps that power with the publisher: **no creative serves on a site until
that site's publisher approves it**, and the publisher can change their mind
at any time.

## How creatives reach the queue

There is no submission form. When a campaign wins auctions on a site, its
unapproved creatives are queued for that site's approval automatically —
the auction *is* the submission. The publisher's dashboard shows each
pending creative exactly as readers would see it: the folded cover, and the
full expanded magazine, rendered live. The queue updates over server-sent
events as new candidates arrive.

Approval is per-creative, per-site. Approving a creative for one site says
nothing about any other.

## The publisher's verbs

- **Approve** — the creative may serve. It moves into the live pool
  immediately; no re-auction needed.
- **Reject / Flag** — the creative is blocked from *bidding* on this site.
  The block is a membership entry in a deletable filter (a cuckoo filter,
  replicated cluster-wide), so it's enforced at bid time, cheaply, on every
  auction. Unflagging deletes the entry and the creative may compete again.
  The block is reversible by design — "flagged" means *until unflagged*,
  not forever.
- **Revoke** — the strongest undo of an approval: the creative stops serving
  and returns to pending. It keeps bidding (that's how it re-enters the
  queue), but it cannot serve until re-approved. Any reader dog-ears
  pointing at it are reported stale and cleaned from readers' browsers.
- **Block a domain** — publishers can also block by landing-page domain,
  removing every creative that links there, from any advertiser.

## Trust, once earned

Reviewing every creative from an advertiser you've already vetted is
busywork, so a publisher can opt in to **auto-approval**, per site, off by
default. The reasoning behind its shape:

- **A manual approval is a statement of trust** — not just in one image,
  but in the campaign behind it and the brand it links to. So each manual
  approval records two *trust anchors* for the site: the campaign, and the
  landing page's registrable domain (`shop.acme.com` and `www.acme.com`
  are the same brand; two tenants of a shared hosting platform are not).
  With the toggle on, a new creative matching either anchor skips the
  queue and serves immediately, marked as auto-approved so the publisher
  can always audit what the feature did on their behalf.
- **Trust is consumed, never chained.** Auto-approvals mint no anchors of
  their own — otherwise one approval could snowball across an advertiser's
  whole portfolio via shared domains. Only a human clicking Approve widens
  trust.
- **A reject is evidence the inference failed.** Auto-approval is a bet
  that past approval predicts future approval; rejecting, flagging, or
  revoking any creative from a trusted campaign or domain settles that bet
  the other way and withdraws the anchors. Siblings return to the manual
  queue. Anchors can also be removed individually from the dashboard.
- **Off by default, deliberately.** Approved demand is what teaches floor
  prices, so widening what gets approved automatically changes a site's
  economics. That choice belongs to the publisher, not a default. For the
  same reason there is no retroactive grant: approvals made before the
  feature existed mint no anchors, because the rejections that would have
  balanced them were never recorded.

Turning the toggle off pauses auto-approval without deleting the trust
list; turning it back on restores it.

## The lifecycle rule that took a production incident to learn

Pausing a campaign and *deleting* its approvals are different acts, and
conflating them once wiped publishers' approval queues during a routine
deploy. The settled rule:

- An **explicit pause by the advertiser** revokes the campaign's approvals
  on the site — pausing is leaving; on resume, every creative starts over
  as pending. This is a product decision: a publisher who approved a
  campaign in March shouldn't discover it silently resumed in July.
  (Trust anchors are the publisher's own state and survive the pause — on
  a site that opted into auto-approval, resume re-approves on the next
  auction, because there the publisher *has* said they want exactly that.)
- **Everything else keeps approvals** — budget exhaustion, category
  re-registration churn during deploys, entity restarts, re-verification.
  None of these are the advertiser leaving, so none of them may touch the
  publisher's decisions.

Approval state, like everything reader- and publisher-facing in the system,
errs toward preservation: statuses are marked, not deleted, unless a human
explicitly chose otherwise.
