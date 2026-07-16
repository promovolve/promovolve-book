# A Page, a Reader, an Ad

Everything in this book happens in the few seconds this chapter describes.
Read it once for the shape; the rest of the book explains each step.

## A publisher signs up

Yuki runs a small travel site. She registers it with Promovolve, an operator
approves the site request, and she proves she controls the domain — a token
file at `/.well-known/promovolve.txt`, or a DNS TXT record if her host won't
serve files. From that moment, only pages on her verified host can request
ads under her site ID; anyone who copies her embed code onto another domain
gets a `403`.

She drops one script tag into her template. Her slots are just `div`s with
dimensions. There is nothing else to configure — no ad server UI, no line
items (the hand-negotiated delivery contracts of traditional ad servers),
no size negotiations.

## An advertiser signs up

Kenta owns a pilates studio. He has no design team and no creative agency —
he has a landing page. He gives Promovolve the URL, a daily budget, and a
CPM bid — the price he's willing to pay per thousand views of his ad. The platform's pipeline reads his landing page in a real browser,
extracts its images, copy, and colors, has an LLM rewrite the copy into a
three-page magazine narrative, renders it, and shows him the result. He
picks the categories his campaign should appear against — *Fitness*,
*Wellness* — and launches.

## A new article meets its first reader

Yuki publishes an article about a hot-spring town at 6 a.m. At 6:14, the
first reader arrives. The ad tag on the page asks for ads — and the server
has never seen this URL. It answers with empty slots and a hint: *send me
the text*. The tag extracts the article's text in the reader's own browser
and posts it up. An LLM classifies it — *Travel*, *Asia Travel* — and the
result is stored. That one reader saw no ads; every reader after them will.

Classification is good for 48 hours. If the article still has traffic after
that, the next visit re-sends the text and the clock resets. Pages nobody
reads simply fall out of the system.

## The auction runs — before anyone else arrives

With categories in hand, the site's auctioneer collects bids from every
campaign registered against *Travel* and its neighbors. Kenta's campaign
isn't a travel campaign, so it sits this one out; an airline and a luggage
brand bid. The auctioneer doesn't pick one winner. It orders all eligible
creatives — each campaign's best foot forward first — and caches the whole
pool next to the page. The real selection happens later, per impression.
Every five minutes, and whenever a campaign changes, the auction quietly
re-runs.

## A reader gets an ad

The second reader loads the page. The ad tag sends one request listing every
slot on the page. The server checks the host, checks the classification is
fresh, pulls the cached candidate pool from a local replica, and lets its
pacing controller decide whether this impression should even be spent — a
campaign's budget must last the whole day, not just the morning.

Then it samples. Each candidate's click and dog-ear history is a pair of Beta
distributions; each candidate draws a plausible engagement rate, multiplies
by a dampened function of its bid, and the highest draw wins the slot — one
campaign at most per page. The winner's budget is reserved, the price is set
by the runner-up rather than the winner's own bid, and the response carries
the creative and its tracking URLs.

## The reader answers back

The ad sits collapsed in the page, magazine-cover small. The reader taps; it
expands into a swipeable spread — cover, story, call to action. That expand
*is* the click in this format — the reader chose to open the magazine. If
the reader wants the ad back later, they fold its corner — a dog-ear, the
*fold* event, the strongest quality signal the system has — and their own
browser remembers it. Next time they meet that advertiser on any page of
the site, the bookmarked creative is served, free, with no auction and no
learning: the system refuses to bill or optimize a moment the reader chose.

If instead the reader ignores the ad, that's data too. Within an hour, the
sampling distributions have shifted; a creative nobody engages loses its
share of impressions to one readers actually open.

## The day ends

At midnight UTC, spend counters roll over, the pacing controller notes how
today went and adjusts its aggressiveness for tomorrow, and the site's
learned traffic shape absorbs today's rhythm — a 20% nudge toward what
actually happened. Settlement writes the day's ledger: gross spend, platform
margin, publisher earnings, one idempotent row per advertiser–campaign–site.

Nobody was tracked. Nothing about the reader left their browser except a
click. And every mechanism in this story is a chapter in this book.
