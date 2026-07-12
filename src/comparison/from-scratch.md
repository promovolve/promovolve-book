# How Ad Tech Works (and Where Promovolve Diverges)

If you've never worked in ad tech, the alphabet soup of SSPs, DSPs, DMPs, and RTB can be impenetrable. This chapter explains the traditional programmatic advertising stack from the ground up, then shows how Promovolve makes different choices at each layer.

## The Simplest Version: A Magazine

Before the internet, advertising was straightforward.

A magazine about cooking has readers who care about cooking. A kitchen equipment company wants to reach people who care about cooking. The magazine's ad sales team calls the kitchen equipment company and says: "We'll put your ad on page 47, next to our article about French sauces, for $5,000." They shake hands. Done.

Three participants. One transaction. Everyone understands what they're getting:
- The **advertiser** gets their ad in front of relevant readers
- The **publisher** gets paid for their audience's attention
- The **reader** sees an ad that relates to what they're already reading

This is **direct sales**. It works beautifully when the publisher and advertiser know each other. It doesn't scale to millions of websites and millions of advertisers who have never met.

## The Internet Problem: Too Many Strangers

A small travel blog in Kyoto has readers who love Japanese travel. A ryokan in Hakone would love to reach those readers. But the blog owner doesn't know the ryokan exists, and the ryokan owner doesn't know the blog exists. Neither has a sales team.

Multiply this by millions of websites and millions of businesses. The **matching problem** — connecting the right ad to the right page — is too large for humans to solve one deal at a time.

The ad tech industry's answer was to automate the matching with machines. But the system they built optimized for a particular set of goals, and those goals don't serve everyone.

## The Traditional Stack: Who Does What

### The Publisher's Side: SSP (Supply-Side Platform)

The publisher (our Kyoto travel blog) signs up with an SSP — companies like Google Ad Manager, Magnite, or PubMatic. The SSP provides a piece of JavaScript that goes on every page. When a reader loads the page, this script calls the SSP: "I have an ad slot, 300x250 pixels, on this URL. Who wants it?"

The SSP's job is to get the highest price for this impression. It does this by offering it to exchanges and DSPs.

### The Advertiser's Side: DSP (Demand-Side Platform)

The ryokan in Hakone signs up with a DSP — companies like The Trade Desk, DV360, or Amazon DSP. The ryokan uploads its ad creative, sets a budget ($50/day), defines a target audience ("people interested in travel to Japan"), and sets a maximum bid ($3 CPM).

The DSP's job is to find the right impressions to buy and bid the right price. It does this by listening for bid requests from exchanges and deciding, in real time, whether this particular impression is worth bidding on.

### The Middle: The Ad Exchange

The exchange (Google AdX, OpenX, etc.) sits between SSPs and DSPs. When the SSP says "I have an impression," the exchange broadcasts it to every connected DSP: "Who wants this? You have 100 milliseconds to decide."

Each DSP evaluates the impression:
- Does this page match the advertiser's targeting criteria?
- How much is this user worth, based on their profile?
- What's the right bid price?

The DSPs that want it send back bids. The exchange picks the highest bidder. The winning DSP's ad is served.

### The Invisible Layer: DMP (Data Management Platform)

How does the DSP know "how much this user is worth"? It consults user profiles — built from cookies, device IDs, and cross-site tracking data aggregated by DMPs. These profiles say things like: "This user visited car dealership websites last week" or "This user is 25-34, lives in Tokyo, and recently searched for flights."

This is where the magazine model breaks down completely. The DSP isn't asking "what is this person reading?" It's asking "who is this person?" The travel blog's content about Kyoto temples is irrelevant. The ad is targeting the user, not the page.

## What Goes Wrong

This system works — in the narrow sense that money flows and ads get served. But it has structural problems.

### The publisher becomes a commodity

In this model, the publisher's content doesn't matter. What matters is the user sitting on the page and the cookie in their browser. A thoughtfully researched article about Kyoto architecture and a hastily assembled listicle about "10 things in Japan" are, to the exchange, interchangeable: they carry the same user with the same cookie.

Publishers who invest in quality content get paid the same as those who don't. The incentive is to maximize page views, not quality — because the ad system doesn't value quality.

### The user experience degrades

Each ad slot triggers a cascade of network requests. The SSP calls the exchange. The exchange calls multiple DSPs. Each DSP calls its DMP. The responses flow back. On a page with five ad slots, this happens five times in parallel. Header bidding (the publisher's attempt to get better prices) adds another round. The result: ad-related requests often take longer than the page content itself.

And the ads themselves: because they target users, not content, they feel random and intrusive. You read about temple architecture, you see an ad for the shoes you browsed last night. The disconnect is jarring.

### Small players can't participate

This infrastructure has minimum viable scale. SSPs have traffic minimums. DSPs require campaign management expertise. The exchange's auction mechanics favor large bidders with sophisticated real-time bidding algorithms. The ryokan in Hakone and the Kyoto travel blog — the exact pair that should be connected — can't afford to play.

## How Promovolve Rethinks Each Layer

Promovolve doesn't try to improve the traditional stack. It replaces the fundamental assumptions.

### Instead of targeting users → target content

The entire SSP/DSP/DMP chain exists because the system decided to target users. Remove that decision, and most of the machinery becomes unnecessary.

Promovolve classifies page content using an LLM into IAB Content Taxonomy 3.0 categories: "This article is about Travel Locations, Adventure Travel, Asia Travel." Meanwhile, an advertiser hands over a landing page, and the same LLM reads it and suggests which content categories that product belongs next to — no manual configuration, though the advertiser can fine-tune the set. The match happens between content and product, not content and user. No user profile needed. No DMP. No cookies.

This is the magazine model, automated. The technology that makes it work at scale — cheap, accurate LLM classification — didn't exist five years ago.

### Instead of real-time auctions → periodic batch auctions

Traditional auctions run on every page load because they need to evaluate the user in real time. Promovolve doesn't need to — the content doesn't change between page loads.

The auction runs when a page is first classified — triggered on demand by its first visitor, via the ad tag — and re-runs every 5 minutes plus on campaign events. Multiple candidates per slot are cached in a replicated in-memory store (Pekko DData). When a user loads the page, the ad is already there. No network round-trip, no exchange, no 100ms wait.

Serve latency drops from 50-200ms to under 1ms.

### Instead of a single winner → multiple candidates with exploration

A traditional auction picks one winner: the highest bidder. That's it. If a new advertiser with a potentially better creative enters, they lose to the established high bidder and never get a chance to prove themselves.

Promovolve caches multiple candidates and uses Thompson Sampling to choose at serve time. A new creative with no track record gets explored — shown to some users to learn its click-through rate. If it performs well, it earns more impressions. If not, it fades out naturally. No A/B test configuration needed. The system learns automatically.

### Instead of DSP bid algorithms → quality-adjusted second-price clearing

In the traditional stack, each DSP runs sophisticated bid optimization across all its campaigns. The ryokan in Hakone doesn't have a DSP; it can't participate.

Promovolve replaces the bid optimizer with the auction mechanism itself. The ryokan sets a maximum CPM and a daily budget. At serve time, candidates are scored as `sampledCTR × CPM^α` and the winner pays the minimum CPM that still beats the runner-up given its CTR — a quality-adjusted second-price clearing. There's no upside to bid shading and nothing to optimize against, so Promovolve runs no campaign-side RL agent at all. A creative that earns clicks pays less than one that merely outbid; honest bids are the dominant strategy.

No DSP integration. No bid management expertise. The auction handles it.

### Instead of per-impression database writes → buffered spend tracking

Traditional systems write to a database on every impression to track spend. At scale, this becomes a bottleneck.

Promovolve buffers spend events in the campaign actor (flush every 500ms or 20 events), deduplicates with a Bloom filter, and persists atomically. This reduces database writes dramatically while maintaining correctness through idempotency guarantees.

### Instead of intermediary fees → direct connection

In the traditional stack, money passes through multiple intermediaries: DSP, exchange, SSP. Each takes a percentage.

Promovolve connects advertisers and publishers directly. The advertiser's budget goes to the publisher, minus the platform's single fee. There's no exchange, no DSP, no DMP taking a cut.

## What Promovolve Gives Up

These trade-offs are real and worth understanding:

**No cross-publisher reach.** A DSP campaign can target users across thousands of websites simultaneously. Promovolve works per-publisher (or per-publisher-network). An advertiser who wants broad reach across unrelated sites needs the traditional stack.

**No user-level targeting.** If an advertiser specifically wants to reach "women aged 25-34 in Tokyo who recently searched for hotels," Promovolve can't help. It can reach "readers of content about hotels in Tokyo," which may overlap significantly, but it's a different kind of targeting.

**No real-time price discovery on every impression.** Traditional exchanges run a fresh competitive auction on every page load and reveal a market-clearing price for that exact moment. Promovolve runs the auction once per classification (and on a 5-minute re-auction tick), so the clearing price reflects the market over a window, not the millisecond. The auction itself is competitive — quality-adjusted second-price clearing extracts honest bids — but it's batch, not realtime.

**Stale auction results.** Traditional RTB reflects the state of the world right now. Promovolve's cached candidates can be up to 5 minutes old (the re-auction interval). A campaign that paused 2 minutes ago might still be served until the next re-auction.

**No user retargeting.** The "you looked at shoes, now see shoe ads everywhere" pattern is impossible in Promovolve. For some, this is a feature.

## When Promovolve Makes Sense

Promovolve is the right choice when:

- The publisher's **content is the value proposition**, not access to trackable users
- Advertisers want **contextual relevance** — their ad next to related content
- **Page performance** matters — sub-millisecond serving vs. 200ms ad waterfalls
- The publisher wants **control** over what appears on their site (approval workflow)
- **Privacy** is a genuine concern, not just a compliance checkbox
- Participants include **small advertisers** — local businesses, community announcements — who can't access the programmatic stack

It's the wrong choice when:

- The advertiser needs **cross-publisher user retargeting**
- **Market-clearing price discovery** is important for the business model
- The publisher's value is **user data**, not content quality

The next chapters examine each of these differences in technical detail.
