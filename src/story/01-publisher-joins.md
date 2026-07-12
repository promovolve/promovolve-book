# Chapter 1: A Publisher Joins

Yuki runs a travel blog from Kyoto. She writes about temples, hiking trails, seasonal festivals, and hidden restaurants. Her readers are people planning trips to Kansai — engaged, curious, spending real time on each article. She publishes two or three articles a week, each one carefully researched.

She wants to monetize her site without ruining it. No pop-ups. No auto-playing video ads. No "you looked at sneakers yesterday" retargeting that has nothing to do with her content. She wants ads that feel like they belong — a ryokan in Arashiyama, a hiking gear shop, a regional train pass.

She signs up with Promovolve and adds a small JavaScript snippet to her site. It creates two ad slots: a 300×250 rectangle in the sidebar and a 728×90 banner between article sections.

That's all she does on day one. The system takes over from here.

## The First Reader Arrives

Here's what *doesn't* happen: no crawler visits Yuki's site. No scheduled job wakes up at 2am to fetch her pages. Promovolve doesn't go looking for content — it waits for proof that someone actually reads it.

Late that night — 2:07am, because jet-lagged trip-planners keep strange hours — a reader opens Yuki's article "Autumn Foliage Hikes in Eastern Kyoto." Yuki's ad snippet asks Promovolve for an ad — and Promovolve has never seen this page before. Nothing is cached. Instead of shrugging, the ad tag does something quiet: it reads the page it's standing on. Right there in the reader's browser, it extracts the visible text — the article body, headings, captions — and notes the geometry of the two ad slots Yuki placed. Then it sends all of that up in a single POST to `/v1/classify-page`.

The server answers `202 Accepted` in a few milliseconds and gets out of the way — the reader's page load is never blocked, never slowed. Behind the scenes, the SiteEntity for Yuki's site takes over. If three readers land on the same new article at once, only one classification runs; the rest are absorbed. This is called single-flighting, and it means a traffic spike on a fresh page costs exactly one LLM call.

## The LLM Classifies the Content

The text the ad tag sent up goes to an LLM — by default, Google's Gemini Flash, chosen for cost (a fraction of a cent per call). The prompt asks the model to classify the content into IAB Content Taxonomy 3.0 categories, which is the ad industry's standard vocabulary for describing what a page is about.

For Yuki's article, the LLM returns:

```json
{
  "selected_taxonomy_ids": [
    {"id": "653", "confidence": 0.95},
    {"id": "665", "confidence": 0.85},
    {"id": "657", "confidence": 0.70}
  ]
}
```

Translated: Travel (653) with high confidence, Adventure Travel (665), and Asia Travel (657). The system now knows what this page is about — in a language that advertisers understand.

The result is persisted with a timestamp, and that timestamp matters: for the next 48 hours (Yuki's content-recency window — she can tune it), the page counts as fresh and won't be re-classified. One LLM call per page per window, not per reader.

If the LLM is down, the circuit breaker trips after 5 consecutive failures and stops trying for 30 seconds. The page just doesn't get classified this time — the single-flight slot is released, and the next reader's visit retries. No crash, no degradation of the serving path.

## Category Ranking: What Works on This Site?

The classification isn't the end of the story. Not all categories perform equally on Yuki's site. "Travel" ads might get a 4% click rate, while "Asia Travel" ads get 0.5%. Over time, the system learns this.

Each (category, site) pair has a `TaxonomyRankerEntity` — a tiny actor that maintains a Beta distribution of click-through performance for that category on that specific site. Early on, with no data, all categories start with `Beta(1, 1)` — total ignorance. As impressions and clicks accumulate, the distributions sharpen.

The ranker uses Thompson Sampling (the same algorithm used at serve time — more on that later) to assign weights to each category. Categories with strong proven performance get high weights. Categories with little data get variable weights — sometimes high (exploration), sometimes low.

The top 3 categories by weight are forwarded to the auction. For Yuki's site with some history, that might be Travel (high proven CTR), Adventure Travel (decent CTR), and a newer category like Food & Drink (uncertain, worth exploring).

## The Page Is Ready for Auction

At this point, Promovolve knows:
- **What the page is about**: Travel, Adventure Travel, Asia Travel (from the LLM)
- **Which categories perform well on this site**: Travel and Adventure Travel (from the ranker)
- **What ad slots are available**: 300×250 sidebar, 728×90 banner (from the ad tag)

The durable copy of this classification lives in the SiteEntity for Yuki's site; the `AuctioneerEntity` — an actor sharded by site ID — caches it in memory and remembers the last classification for each URL. The page is now ready for advertisers to bid on.

The reader who triggered all this never noticed. Her page loaded at full speed; the classification ran behind her page view, and the auction followed seconds later. She may have seen an empty slot — the first visitor to a brand-new page sometimes does. Every reader after her finds the auction's results already waiting in memory. And a page nobody ever opens is never classified at all, which is exactly right: it has no impressions to sell.

The next chapter: an advertiser discovers Yuki's site and wants to place an ad.

---

*Technical deep dives: [Page Classification](../auction/page-classification.md) · [Category Ranking](../auction/category-ranking.md) · [System Architecture](../architecture/overview.md)*
