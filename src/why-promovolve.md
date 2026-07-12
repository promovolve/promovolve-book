# Why Promovolve?

## The Problem: Programmatic Advertising Wasn't Built for Publishers

The modern programmatic advertising stack — SSPs, DSPs, exchanges, DMPs — was designed to solve a problem for large advertisers: how to reach the right user across millions of websites in real time. It succeeded spectacularly at that. But in doing so, it created a system that works against the interests of most publishers.

### Publishers lost control of their own inventory

When a user visits a publisher's site, the ad decision happens somewhere else entirely. The publisher's SSP fires a bid request to an exchange, which broadcasts it to dozens of DSPs, which consult their user profiles, run their bidding algorithms, and return a response — all within 100 milliseconds. The publisher never sees the bids. They never choose which ad runs. They receive a creative URL and a clearing price, and they serve it.

This architecture optimizes for advertiser reach, not publisher value. The publisher's content — the reason the user is there — is reduced to a signal in someone else's targeting model. A carefully researched article about travel in Kyoto and a clickbait slideshow about celebrity gossip are, to the exchange, just two different URLs carrying a user with a cookie.

### Ads became something people hate

Nobody hates ads in a travel magazine. But people install ad blockers, pay for premium subscriptions to avoid ads, and describe web advertising as the worst part of the internet. What changed?

The difference isn't the existence of ads — it's what they became. A magazine ad for hiking boots next to a trail guide feels natural. A web ad for the shoes you looked at yesterday, following you to an unrelated news article, feels invasive. The first is a recommendation in context. The second is surveillance.

Traditional ad tech targets **users**, not content. A user who visited a car dealership website yesterday gets retargeted with car ads on every site they visit today — a cooking blog, a news site, a forum. The publisher's content is irrelevant. The ad is chasing the user. The result is an experience that feels wrong to everyone involved: readers feel stalked, publishers lose control of what appears on their pages, and advertisers pay to annoy people in the wrong context.

This isn't a privacy problem to be solved with consent banners and cookie policies. It's a design problem. Web advertising chose to target people instead of content, and in doing so, it turned ads from something readers could tolerate — even appreciate — into something they actively resist.

### Small and medium publishers are left behind

The programmatic stack has enormous fixed costs. Integrating with an SSP requires technical sophistication. Meeting exchange quality thresholds requires minimum traffic volumes. The revenue share stacks up: the exchange takes a cut, the SSP takes a cut, the DSP takes a cut, the DMP takes a cut. Each intermediary skims from the transaction, and the publisher receives whatever is left.

For niche publishers — a Japanese travel blog, a specialized cooking site, a local news outlet — the economics don't work. Their traffic is too small for exchanges to care about. Their content is too specific for broad behavioral targeting. Their readers are too privacy-conscious for invasive tracking. These publishers either accept pennies from bottom-tier ad networks, plaster their sites with low-quality ads, or give up on monetization entirely.

### The latency tax

Real-time bidding imposes a latency floor on every page load. The browser must wait for the ad request, the exchange round-trip, and the creative download before the ad slot renders. On a fast site, the ads are the slowest thing on the page. Header bidding — the industry's attempt to improve publisher yield — made this worse by running multiple auctions sequentially or in parallel, each adding network round-trips.

Users notice. Ad-blocker adoption correlates directly with page load degradation caused by ad tech. Publishers who care about user experience are penalized for participating in the system that's supposed to monetize that experience.

## The Opportunity: What Magazines Got Right

Pick up any well-produced magazine — a travel magazine, a cooking publication, an architecture journal. Look at the ads. They're relevant. A travel magazine shows ads for airlines, luggage, and hotels. A cooking magazine shows kitchen equipment, specialty ingredients, and culinary schools. The ads feel like they belong there. They complement the content instead of interrupting it.

And people actually looked at them. When ads weren't cluttered, when they weren't fighting for attention with pop-ups and auto-playing videos, when there were just a few well-placed ads that matched what you were reading — you noticed them. Sometimes you tore out a page and kept it. The ads had value because they were relevant, restrained, and respectful of the reader's attention.

Nobody found these ads creepy. Nobody wondered how the magazine knew they were interested in travel. The answer was obvious: you bought a travel magazine. The content was the signal.

This model worked for over a century. Advertisers paid a premium for placement in publications whose readers matched their audience. Publishers curated which ads appeared, maintaining quality and relevance. Readers accepted ads as part of the experience — sometimes even valued them — because the ads were for things they actually cared about, presented in a way that respected the editorial context.

Then the internet threw it all away.

Instead of matching ads to content, the web advertising industry decided to match ads to users. Instead of asking "what is this person reading?" it asks "who is this person and what have they done?" The content of the page became irrelevant. The reader became a target. And the entire experience — for publishers, readers, and even most advertisers — got worse.

**Promovolve is an attempt to get back what magazines had.** Relevant ads, matched to content, with no tracking, no surveillance, and no degradation of the reading experience.

### Why now?

Content-based advertising isn't a new idea, but doing it automatically at web scale was impractical until recently. Classifying page content into advertising categories required either manual curation (expensive) or primitive keyword matching (inaccurate).

LLMs changed this. A single API call to Gemini Flash costs a fraction of a cent and returns IAB Content Taxonomy categories with confidence scores — accurately classifying a page about hiking in the Japanese Alps into Travel, Outdoor Recreation, and Asia destinations. This wasn't economically viable five years ago. It is now.

## What Promovolve Does Differently

Most ad-tech projects keep the same ad format — a fixed-size IAB rectangle delivered through real-time bidding — and try to fix the parts around it: better targeting, faster auctions, friendlier consent flows. Promovolve takes a different bet. It changes the format itself, then rebuilds the rest of the stack to fit.

### The ad isn't a rectangle. It's a magazine spread.

A Promovolve creative isn't a static banner. It's a small magazine — a sequence of pages a reader can expand into a full-screen overlay, swipe through, and collapse again. The collapsed view sits unobtrusively in the publisher's slot like a magazine ad on a page. Tapped, it opens into editorial-style content: cover, story pages, a call to action.

This is closer to how print advertising worked. The reader chooses to engage. The advertiser gets attention when it's wanted, not interruption when it isn't. And because the format is a container — not a fixed pixel size — a single creative can render in any slot the publisher offers.

### Readers can dog-ear an ad

Pick up a magazine, fold the corner of an interesting page, come back to it later. Promovolve gives readers the same affordance for ads. A reader who finds a creative interesting can fold its corner — a literal dog-ear — and the next time they land on a page where that advertiser is eligible, the ad they bookmarked is the one they see. The pin lives in the reader's browser, not in a server-side profile.

Nothing in traditional ad tech does this. Bookmarks are something you do for content you care about, and ads have never been treated as content readers might want to keep. The dog-ear is a bet that some ads are worth coming back to, and that letting readers say so out loud is a better signal than retargeting them with the same creative for the next thirty days.

### Creatives flow to fit the slot

Traditional creatives are pinned to IAB pixel dimensions: 300×250, 728×90, 970×250. Mismatched slots get letterboxing, scaling artifacts, or no fill at all. Promovolve creatives are fluid — the same content reflows to fit whatever rectangle the publisher provides. Advertisers upload a landing page or a structured creative once; Promovolve's pipeline (Playwright extraction, Gemini rewriting, the in-house designer) renders it into the slot's geometry on demand.

### Auctions happen before users arrive

Traditional systems run an auction on every page load because they need to evaluate the user in real time. Promovolve doesn't need to — the content doesn't change between page loads. So the auction runs when a page is first classified (on demand, via the ad tag itself) and re-runs event-driven as campaigns and budgets change, and the results are cached in a replicated in-memory index. When a user arrives, the ad is already chosen. Serve latency drops from 50–200ms to under 1ms.

### Multiple candidates, not a single winner

Instead of picking one winner per auction, Promovolve shortlists multiple candidates per ad slot and caches them all. At serve time, Thompson Sampling selects among them, balancing exploration (trying new creatives to learn their click-through rate) against exploitation (serving the creative that performs best). The system continuously learns which ads work best on which content, without A/B test infrastructure or manual optimization.

### Quality-adjusted auctions reward good creatives

Bidding the highest CPM doesn't automatically win the slot. Promovolve scores each candidate as `sampled_CTR × CPM^α`, where α is a publisher-tunable weight. A creative that earns clicks can outscore a higher-bidding one that doesn't, and the publisher controls how heavily quality counts versus price. Pricing is quality-adjusted too: an exploiting winner pays the minimum bid that would still have won given its CTR, not its own bid — so there's no incentive to shade.

### Publisher-side learning, not advertiser-side bid wars

Promovolve has no campaign-side reinforcement learning agent. With second-price quality-adjusted auctions, bid shading is counterproductive — there's nothing for an RL agent to learn that the auction mechanism doesn't already enforce. The reinforcement learning that does exist runs on the publisher side: a per-site agent tunes the floor CPM upward when bid spread suggests the market can bear it, and downward when fill suffers. The publisher's revenue improves; advertisers see honest second-price clearing.

### Budget pacing adapts to reality

A PI controller with self-tuning gains, traffic shape learning, and oscillation detection smooths budget delivery across the day. It learns that traffic peaks at 10am and dips at 3pm, that weekends have a different shape than weekdays, and adjusts automatically. Publishers see steady ad delivery instead of budgets that exhaust by noon and leave empty slots all afternoon.

### No user tracking — because it's not needed

Promovolve stores no user profiles, sets no tracking cookies, and collects no cross-site identifiers. Targeting is based entirely on the content of the page being viewed. This isn't a sacrifice for privacy compliance — it's a consequence of the design. When you match ads to content, there's nothing about the user you need to know. The content tells you everything. Even the dog-ear lives in the reader's own browser; the server only learns "someone saved this creative," never who.

## Who Promovolve Is For

### Publishers

Promovolve is for publishers who:

- **Own their relationship with readers** and won't compromise it with invasive tracking
- **Create quality content** in specific verticals where content-based targeting is naturally strong
- **Want sub-millisecond ad serving** that doesn't degrade their site performance
- **Prefer simplicity** over the operational complexity of SSP/exchange integrations
- **Need fair economics** without the intermediary tax of the programmatic supply chain

### Advertisers — from local businesses to global brands

The traditional programmatic stack has a minimum viable scale. Setting up DSP campaigns, managing bid strategies, and meeting exchange minimums requires budgets and expertise that exclude most businesses. The vast majority of businesses in the world — the local restaurant, the neighborhood bookshop, the regional tour operator, the community event organizer — cannot participate.

Promovolve lowers the bar to zero. An advertiser is anyone with an image and a landing page. That could be:

- A **local hiking gear shop** placing an ad on a regional outdoor recreation blog
- A **community festival** announcing dates on a local news site
- A **cooking class** promoting on a food blog in their city
- A **small hotel in Kyoto** reaching readers of a travel article about their neighborhood
- A **global brand** running a campaign across a network of niche publishers

There's no DSP to integrate with. No bid strategy to configure manually — the second-price auction handles price discovery, and quality-adjusted scoring rewards creatives readers actually engage with. No user profiles to buy. Just: "here's my ad, here's my budget, here's what my product is." The advertiser gives a landing page, and the system reads it and suggests which content categories match (IAB Content Taxonomy 3.0) — a set the advertiser can fine-tune but never has to build from scratch. The system handles the rest.

This is how magazine advertising worked. A local restaurant could buy a quarter-page in a neighborhood magazine. The scale matched the business. Promovolve brings that accessibility to the web.

### Advertising Agencies

Advertising agencies don't own publisher platforms — they manage campaigns on behalf of their clients and place ads across publishers' sites. In the traditional programmatic world, this means agencies must navigate a maze of DSP contracts, exchange seat IDs, and platform-specific bid management tools, each taking a cut along the way.

With Promovolve, agencies can own the ad-serving infrastructure itself. An agency can run its own Promovolve instance, build a network of publisher relationships, and manage all of their clients' campaigns through a system they control end-to-end. No DSP middleman. No exchange fees. No dependency on someone else's platform. The agency becomes the platform.

The auction is second-price and quality-adjusted, so there's nothing to bid-optimize against. Agencies spend their time on strategy and creative — picking the publications, choosing the placements, managing client budgets — instead of feeding a bid-management tool. It's closer to the magazine ad sales model agencies grew up with, except now the agency owns the technology that makes it all work.

## How This Book Is Organized

The rest of this book documents every algorithmic detail, derived from the source code:

- **Architecture** — Pekko cluster topology, entity hierarchy, and data flow
- **Auction** — The five phases of the periodic batch auction, plus quality-adjusted scoring and pricing
- **Serving** — Thompson Sampling, cold start, fair selection, and dog-ear pin-honoring at serve time
- **Pacing** — PI control, self-tuning, traffic shape learning
- **Distributed State** — ServeIndex replication and consistency
- **Comparison** — Point-by-point mapping against traditional SSP/DSP/exchange patterns

Each chapter is self-contained. All formulas, thresholds, and constants come directly from the Scala source.
