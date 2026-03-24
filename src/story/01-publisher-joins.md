# Chapter 1: A Publisher Joins

Yuki runs a travel blog from Kyoto. She writes about temples, hiking trails, seasonal festivals, and hidden restaurants. Her readers are people planning trips to Kansai — engaged, curious, spending real time on each article. She publishes two or three articles a week, each one carefully researched.

She wants to monetize her site without ruining it. No pop-ups. No auto-playing video ads. No "you looked at sneakers yesterday" retargeting that has nothing to do with her content. She wants ads that feel like they belong — a ryokan in Arashiyama, a hiking gear shop, a regional train pass.

She signs up with Promovolve and adds a small JavaScript snippet to her site. It creates two ad slots: a 300×250 rectangle in the sidebar and a 728×90 banner between article sections.

That's all she does on day one. The system takes over from here.

## The Crawler Wakes Up

At 2am, Promovolve's crawler visits Yuki's site. It's a Playwright-based headless browser — it renders JavaScript, scrolls the page, and extracts the visible text content. It also detects the ad slots Yuki placed and records their sizes and positions.

The crawler follows links from the homepage to recent articles, up to a configurable depth (default: 2 levels). For Yuki's blog, that means the homepage, the article listing page, and each individual article.

For each page, the crawler captures the visible text — the article body, headings, captions. This raw text is what the system will use to understand what the page is about.

## The LLM Classifies the Content

The crawler's text goes to an LLM — by default, Google's Gemini Flash, chosen for cost (a fraction of a cent per call). The prompt asks the model to classify the content into IAB Content Taxonomy 2.1 categories, which is the ad industry's standard vocabulary for describing what a page is about.

For Yuki's article "Autumn Foliage Hikes in Eastern Kyoto," the LLM returns:

```json
{
  "selected_taxonomy_ids": [
    {"id": "596", "confidence": 0.95},
    {"id": "564", "confidence": 0.85},
    {"id": "483", "confidence": 0.70}
  ]
}
```

Translated: Travel (596) with high confidence, Hiking/Camping (564), and East Asian Culture (483). The system now knows what this page is about — in a language that advertisers understand.

If the LLM is down, the circuit breaker trips after 5 consecutive failures and stops trying for 30 seconds. The page just doesn't get classified this crawl cycle. It'll be picked up next time. No crash, no degradation of the serving path.

## Category Ranking: What Works on This Site?

The classification isn't the end of the story. Not all categories perform equally on Yuki's site. "Travel" ads might get a 4% click rate, while "East Asian Culture" ads get 0.5%. Over time, the system learns this.

Each (category, site) pair has a `TaxonomyRankerEntity` — a tiny actor that maintains a Beta distribution of click-through performance for that category on that specific site. Early on, with no data, all categories start with `Beta(1, 1)` — total ignorance. As impressions and clicks accumulate, the distributions sharpen.

The ranker uses Thompson Sampling (the same algorithm used at serve time — more on that later) to assign weights to each category. Categories with strong proven performance get high weights. Categories with little data get variable weights — sometimes high (exploration), sometimes low.

The top 3 categories by weight are forwarded to the auction. For Yuki's site with some history, that might be Travel (high proven CTR), Hiking/Camping (decent CTR), and a newer category like Food & Drink (uncertain, worth exploring).

## The Page Is Ready for Auction

At this point, Promovolve knows:
- **What the page is about**: Travel, Hiking, East Asian Culture (from the LLM)
- **Which categories perform well on this site**: Travel and Hiking (from the ranker)
- **What ad slots are available**: 300×250 sidebar, 728×90 banner (from the crawler)

This information is stored in the `AuctioneerEntity` for Yuki's site — an actor sharded by site ID that remembers the last classification for each URL. The page is now ready for advertisers to bid on.

Nothing has happened on the user-facing side yet. No reader has been slowed down. No ad has been shown. The auction infrastructure was built in the background, on a schedule, while Yuki and her readers were asleep.

The next chapter: an advertiser discovers Yuki's site and wants to place an ad.

---

*Technical deep dives: [Page Classification](../auction/page-classification.md) · [Category Ranking](../auction/category-ranking.md) · [System Architecture](../architecture/overview.md)*
