# Counting Without Watching

An ad business has to count three things about readers: whether an ad was
really seen, how often one reader has seen it, and how many different
readers a campaign reached. Conventional ad tech answers all three the same
way — give every reader an ID and log what the ID does. Promovolve has no
reader ID, so each question needed its own answer. They share one shape:
**the reader's browser keeps the memory; the server keeps only counts.**

## What counts as an impression

Serving an ad is not the same as showing it. An ad below the fold, or
scrolled past in a blur, was delivered but never seen — and an advertiser
should not pay for it.

Promovolve follows the industry's display standard (the MRC viewable
impression guideline). An impression counts when:

- at least **50% of the ad's pixels** are on screen — 30% for large formats
  of 970×250 and up, as the standard allows;
- in a **visible tab**;
- for **one continuous second**.

Continuous, not cumulative: if the ad drops below the threshold, or the tab
goes to the background, the clock starts over. Two half-second glimpses do
not add up to a view. The one shortcut is a click — a reader who opens the
ad has plainly seen it, so the impression counts at once, ahead of the
click itself.

When the second is up, the ad reports back through a signed URL the server
minted at selection. The signature binds the campaign and the price, so a
report cannot be replayed, pointed at another campaign, or inflated. That
report is the impression: it is what bills the advertiser and what the
[Thompson Sampling](./serving.md) windows count. An ad that was served but
never viewed teaches nothing and is not billed.

## Frequency capping: the browser keeps count

An advertiser can cap a campaign: at most *N* impressions per hour, day, or
week. Showing the same reader the same ad a fortieth time wastes the
advertiser's money and the reader's patience.

The usual implementation is a server-side counter keyed by a reader ID.
Promovolve inverts it:

1. Every winning ad arrives with its campaign's cap — a count and a window.
2. When the impression becomes viewable, the ad tag writes one record into
   the browser's own storage, under the publisher's site.
3. Before the next request, the tag counts its records, and names the
   campaigns that have reached their cap. The server treats that list as a
   hard exclusion, the same way it treats a campaign already on the page.

The server never learns how many times this reader saw anything — only
"not these campaigns, this time". A dog-eared ad is exempt in both
directions: a reader who bookmarked an ad gets it back regardless of the
cap, and those re-encounters are not counted toward it.

One subtlety took a second pass. A capped campaign never wins, so the
browser never receives a newer copy of its cap — an advertiser who *removed*
a cap would wait out the old window before any capped browser noticed. So
the tag also asks, for each campaign it is holding back, whether the cap
still stands, and the server answers. Silence never lifts a cap: no answer
means keep excluding.

The limits are the limits of every cookieless cap, and the advertiser's
screen says so. The cap is **per browser, per site** — never per person, and
never across publishers. A phone and a laptop are two readers. Clearing site
data resets the count. A reader capped on one publisher starts from zero on
the next, because browser storage belongs to the site the reader is on.
Capping across sites would need exactly the cross-site identity this
platform exists to do without, so it is ruled out, not postponed.

## Reach: unique readers without an ID

*Reach* is the number of different readers who saw a campaign. It looks
like the one number that cannot be had without identity: to know two
impressions belong to different people, surely you must know who they are.

You do not. You only need each browser to answer one question: *when did
you last see this campaign here?*

On a campaign's first viewable impression of the day, the tag sends that
answer — a day number, or "never" — and then stores today as the new
answer. At most one report per campaign per day, and nothing in it but the
previous day. The server keeps a tally: for this campaign, on this site,
today, so many browsers last saw it one day ago, so many two days ago, so
many never.

From those tallies, unique browsers for any date range fall out by
addition. A browser's *first* visit inside a range is exactly the visit
whose previous sighting fell before the range began — every browser has
one, and only one:

\\[ \text{reach}(a \ldots b) = \sum_{d=a}^{b} \text{reports on day } d \text{ whose previous sighting was before day } a \\]

Take a browser that sees a campaign on days 1, 2, and 5. Its reports say
*never*, *one day ago*, *three days ago*. Ask for the reach of days 1–5:
only the first report qualifies, so it counts once. Ask for days 4–5: the
day-5 report says the last sighting was day 2, before the range, so it
counts once again. No range counts it twice, and no report says who it is.

This is the method Chrome's updater uses to count active installations
without identifying them. Promovolve borrows its guard as well: each report
carries a random value that the browser throws away after one use, so a
value arriving twice means copied browser storage — a cloned bot profile —
and is not counted. The counts are exact for ranges up to 91 days.

The honest edges, again stated in the report itself. Reach is per site: a
reader on two publishers is two browsers, so totals across sites are
labelled "up to". And a browser with no storage sends nothing at all — with
no memory there is no telling a new reader from a returning one, and the
report undercounts rather than guesses.

With reach in hand, an advertiser can read two numbers that impressions
alone hide: **frequency** (impressions per reader) and **cost per new
reader**. When the second one climbs, the report says why — a higher price,
more repeats per reader, or an audience that is running out of new people.
