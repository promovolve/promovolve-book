# Chapter 3: The First Auction

It's 2:07am. The crawler has just finished classifying Yuki's latest article — "Autumn Foliage Hikes in Eastern Kyoto." The AuctioneerEntity for Yuki's site receives the classification: Travel (0.95), Hiking/Camping (0.85), East Asian Culture (0.70).

Three ad slots need filling. Four campaigns are in the system. The auction begins.

## Phase 1: Category Ranking

The AuctioneerEntity asks the TaxonomyRankerEntity for each category: "What's your weight for this site?"

Each ranker samples from its Beta distribution — Thompson Sampling at the category level:

| Category | Distribution | Sample | Rank |
|----------|-------------|--------|------|
| Travel | Beta(12, 88) — proven performer | 0.14 | 1st |
| Hiking/Camping | Beta(3, 47) — decent, some data | 0.08 | 2nd |
| East Asian Culture | Beta(1, 1) — brand new, no data | 0.61 | 3rd (exploration!) |

East Asian Culture ranks 3rd despite having no data — the uniform `Beta(1, 1)` distribution sampled high. This is exploration: the system will try this category to learn if it works on Yuki's site. Most of the time, the established categories win. Occasionally, a new one gets a chance.

The top 3 categories advance to bidding.

## Phase 2: Bid Collection

For each ranked category, the AuctioneerEntity asks the `CategoryBidderEntity`: "Who wants to bid on Travel for this site?"

The CategoryBidderEntity fans out to all campaigns registered for that category. Each CampaignEntity evaluates whether it should bid:

**Takeshi's Ryokan** (Travel, Hiking): Budget remaining? Yes ($20). Campaign active? Yes. Creative approved for this site? Yes. Bid: `$5.00 × 1.0 (RL multiplier) = $5.00 CPM`.

**JR Rail Pass** (Travel): Budget remaining? Yes. Bid: `$8.00 × 1.0 = $8.00 CPM`.

**Hiking Gear Co** (Hiking): Budget remaining? Yes. Bid: `$4.00 × 1.0 = $4.00 CPM`.

**Kyoto Cooking Class** (Food & Drink): This campaign isn't registered for Travel, Hiking, or East Asian Culture. It doesn't bid.

Three bids collected. All above the floor price ($0.50). All pass eligibility: active status, positive budget, creative size matches at least one slot.

## Phase 3: Fair Candidate Selection

Now the system has to assign candidates to slots. This is where Promovolve diverges from traditional auctions.

A traditional auction would give all three slots to JR Rail Pass — they bid highest. But that's terrible for everyone: the publisher shows the same ad three times (bad UX), the other advertisers never get a chance (no exploration), and the system never learns if Takeshi's ryokan ad might actually get more clicks.

Promovolve uses **fair selection**: each campaign gets one slot before any campaign gets a second.

```
Slot 1 (banner):  JR Rail Pass     — $8.00 CPM (highest bidder, first pick)
Slot 2 (sidebar): Takeshi's Ryokan — $5.00 CPM (second highest, one slot each first)
Slot 3 (sidebar): Hiking Gear Co   — $4.00 CPM (third)
```

Each slot gets multiple candidates (not just one), ordered by CPM but guaranteed to include at least one creative from each bidding campaign. This candidate list is what gets cached for serve-time selection.

## Phase 4: Caching in the ServeIndex

The auction results are written to the ServeIndex — a replicated in-memory store backed by Pekko's Distributed Data (DData).

Each slot gets an entry:

```
Key: "yuki-site|banner-top|bucket-12"
Value: [
  {creative: jrpass-ad, cpm: 8.00, campaign: jrpass, advertiser: jr-west, ...},
  {creative: ryokan-ad, cpm: 5.00, campaign: takeshi, advertiser: takeshi, ...}
]

Key: "yuki-site|sidebar-1|bucket-7"
Value: [
  {creative: ryokan-ad, cpm: 5.00, campaign: takeshi, advertiser: takeshi, ...},
  {creative: hiking-boots, cpm: 4.00, campaign: hikegear, advertiser: hikegear-co, ...}
]
```

The write is `WriteLocal` — it completes instantly on the node running the AuctioneerEntity. Within 2 seconds, gossip propagates the data to every other node in the cluster. Every API node now has these candidates in local memory.

The candidates have a TTL of 120 minutes. If no re-auction refreshes them, they expire and the slot goes empty. But re-auctions run every 5 minutes, so in practice candidates are always fresh.

## What Just Happened

In about 4 seconds of background processing:

1. An LLM classified the page content into advertising categories
2. Thompson Sampling ranked those categories by historical performance on this site
3. Eligible campaigns placed bids based on their max CPM and RL multiplier
4. Fair selection ensured each campaign got representation
5. Multiple candidates per slot were cached in replicated memory across the cluster

No reader was involved. No page load was delayed. The entire auction happened in the background, and the results are sitting in memory, waiting.

Now a reader arrives.

---

*Technical deep dives: [Periodic Batch Auction](../auction/periodic-auction.md) · [Why Multi-Candidate?](../auction/why-multi-candidate.md) · [ServeIndex Caching](../auction/serve-index-caching.md)*
