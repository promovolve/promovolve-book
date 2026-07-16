# How a Page Gets Ads

Promovolve targets content, so before a page can carry ads, the system has
to know what the page is about. The interesting decision is *when* that
happens: not on a crawl schedule, but the first time a reader shows up.

## On-demand, reader-triggered

There is no crawler walking publisher sites. (One existed early on; it spent
its nightly budget re-reading pages nobody visited, and was deleted. The
`crawler` cluster role survives only as the host for landing-page analysis
workers.) Instead:

1. The ad tag requests ads for a URL the server has never classified. The
   response carries empty slots and a freshness token of zero — *send text*.
2. The tag extracts the page's readable text in the browser (bounded at
   8,000 characters) and posts it to `/v1/classify-page`, which answers
   `202 Accepted` immediately. Classification never blocks serving.
3. The site's entity classifies the text with an LLM (Gemini, currently
   `gemini-2.5-flash`) into **IAB Content Taxonomy 3.0** categories — the
   top three, with confidence scores. Campaigns register their demand —
   the categories they want to buy — against the same taxonomy, so matching
   is a direct category lookup with ancestor
   expansion (a page about *Baseball* matches a campaign targeting
   *Sports*); there is no intermediate mapping layer.

The page that triggers classification gets no ads; every subsequent reader
does. Pages classify exactly when readers prove they exist, and LLM cost is
bounded by distinct fresh URLs, not by traffic: a **single-flight** guard in
the site entity collapses a story's burst of first visitors into one
classification call.

## Freshness, not publish dates

A classification is valid for the site's **classification freshness window**
— 48 hours by default. This is a TTL on the *classification*, not a check on
the article's publication date; nothing in the system reads publish dates at
all.

Every serve response carries `reclassifyInMs`, the token that drives the
loop. While positive, the ad tag sends nothing. When it lapses, the next
visit re-submits the text, and a fresh classification opens a fresh window.
The consequences:

- **Evergreen content keeps serving.** A three-year-old article with live
  readers re-classifies every 48 hours forever.
- **Dead pages expire.** A page whose traffic stops falls out of every cache
  — the auctioneer prunes classifications past the window every five
  minutes. State is bounded by what readers actually visit.
- **Content drift is caught.** An edited article gets re-read within a
  window.

## Built to survive restarts and outages

Classifications are persisted in the site's durable entity and replayed to
the auction layer three ways: on entity recovery, when a fresh auctioneer
announces itself (a restarted auctioneer starts with an empty page cache and
must be re-taught), and on a five-minute refresh tick. The replay is
idempotent — a same-or-older timestamp is ignored — so the paths can overlap
harmlessly. A cluster restart therefore heals itself: within moments the
auctioneers relearn every fresh page and re-run their auctions.

The LLM call itself is wrapped in a circuit breaker (five consecutive
failures open it for thirty seconds) and a token-bucket rate limiter sized
to the API tier. A failed classification just releases the single-flight
slot; the next reader retries. The serving path never waits on a model.
