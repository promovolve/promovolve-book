# Why Promovolve?

Digital advertising did not have to become what it became. The magazine era
had already proven a different model: ads chosen to fit the publication,
placed by people who cared about the page they appeared on, tolerated — often
enjoyed — by readers because they belonged there. A travel magazine carried
airline ads. A cooking magazine carried knife ads. Nobody was tracked.

The *programmatic* era — ads bought and sold by machines, in auctions run
inside the milliseconds a page takes to load — traded that away for bidding
over user profiles. The result is familiar: consent banners, ad blockers, fraud,
clickbait inventory, and an arms race of bid optimizers playing each other
instead of serving anyone. Publishers get a shrinking share of spend routed
through a chain of intermediaries. Advertisers get impressions on pages they
would never have chosen. Readers get followed around the internet by a pair
of shoes.

Promovolve is an attempt to rebuild the magazine model with modern
infrastructure. Its commitments, in order:

**Target the page, not the person.** An LLM reads the page a reader is
actually looking at and classifies it into content categories. Campaigns
target categories. There are no cookies, no user profiles, no device
fingerprints, and nothing to consent to — the system never learns who the
reader is.

**Let the reader steer.** A Promovolve ad is a small magazine: it sits
folded in the page, and expands into a full-screen spread only when tapped.
Readers can fold a corner — a *dog-ear* — to bookmark an ad they want back.
The bookmark lives in their own browser. Re-encounters with a bookmarked ad
are free for the advertiser and invisible to the learning system: a
remembered ad is a gift, not a billable event.

**Make honesty the best bid.** The auction is second-price and
quality-adjusted, so shading a bid never helps and a creative readers
actually engage with beats one that merely pays more. Promovolve ships no
campaign-side bid optimizer because the mechanism leaves nothing to
optimize.

**Give the publisher the controls.** Every creative passes through the
publisher's approval queue before it can serve on their site. Floors are
optimized on the publisher's behalf, per content category, by measuring
served revenue — not by an exchange with its own agenda.

**Show the work.** The platform is open source, and this book explains how
it actually operates — including the parts that are deliberately simple and
the ideas that were tried and dropped. Where the text names a class, the
class exists; where a mechanism was removed, the book says so.

The next chapter defines the trade itself — publisher, advertiser,
impression, auction — from zero, for readers who have never bought or sold
an ad; skip it if you have. The chapters after it tell the story once,
quickly, through the eyes of a page and a reader — and then take each
mechanism apart: the ad format, the
creative pipeline, classification, the auction, approval, serve-time
selection, pricing, pacing, floors, and the cluster underneath it all. The
last chapter measures the design against conventional ad tech, difference by
difference.
