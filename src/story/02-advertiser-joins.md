# Chapter 2: An Advertiser Joins

Takeshi runs a small ryokan in Hakone. It's a family business — 8 rooms, a natural hot spring, views of the mountains. His guests are mostly travelers who found him through word of mouth or travel blogs. He wants to reach more of those readers.

He's tried Google Ads. The interface was overwhelming. Keywords, bid strategies, quality scores, ad groups, campaign types — he spent more time learning the system than running the business. And the ads followed people around the internet: someone who Googled "Hakone ryokan" once would see his ad on cooking websites and news portals. That felt wrong.

With Promovolve, Takeshi enters his ryokan's landing page URL, sets a daily budget of $20, a maximum CPM of $5, and selects his ad product category: Travel. The system pulls his landing page through Playwright, lets Gemini rewrite the copy into a few story-style pages, and the in-house designer renders an expandable magazine creative — cover, two interior pages with photos and rates, a final page with a "Reserve" call to action. Takeshi previews it once, approves the layout, and submits.

That's it. No keywords. No audience targeting. No bid strategy to configure. No locked-in pixel dimensions either — the same creative will reflow into whatever slot a publisher offers. Promovolve automatically figures out which *content* categories match his product — articles about destinations, hiking, cultural tourism — using the official IAB mapping between ad product and content taxonomies. His ad will appear next to those articles, the exact context where someone would be interested in a ryokan.

## What Happens Behind the Scenes

When Takeshi creates his campaign, several things happen in the cluster:

**A CampaignEntity is born.** An actor, sharded by advertiser ID and campaign ID, springs to life. It holds Takeshi's campaign state: max CPM ($5), daily budget ($20), creative assignments, status (active), pacing buckets, and a Bloom-filter-backed spend ledger. There's no bid optimizer or learning agent inside — quality-adjusted second-price clearing at serve time means the campaign always bids its honest CPM, and the auction extracts the right price.

**The creative is stored.** The rendered magazine creative — pages, layout metadata, image references — is persisted to the creative repository. Each rendered image is uploaded to R2 (Cloudflare's S3-compatible storage), hashed by SHA-256 for deduplication, and recorded with its dimensions and MIME type. Takeshi's landing page URL stays attached to the campaign so the call-to-action page can deep-link there.

**Categories are derived.** Takeshi chose "Travel" as his ad product category (IAB Ad Product Taxonomy 2.0). The system calls `ContentToAdProductMapping.getContentForAdProduct()` to derive the matching content categories (IAB Content Taxonomy 2.1) — a set of numeric IDs representing destinations, outdoor recreation, cultural tourism, and other content topics that match a travel product. If no direct mapping exists, it walks up the taxonomy's parent chain until it finds one. Takeshi doesn't need to know any of this — he just said "Travel."

**The CampaignDirectory is notified.** A cluster singleton maintains a reverse index: category → set of campaigns. It registers Takeshi's campaign under each of its derived content categories, then fans out the update to `CategoryBidderEntity` shards via `CampaignDistributor` (8 workers). Now, whenever a page is classified into one of those categories, the auction knows to ask Takeshi's campaign for a bid.

## Publisher Approval

Here's something that doesn't exist in traditional programmatic advertising: the publisher gets to say no.

Before Takeshi's ryokan ad can appear on Yuki's travel blog, Yuki reviews it. She sees the creative, the landing page, and the advertiser's information in her publisher dashboard. She can:

- **Approve** — the creative enters the ServeIndex and can be shown to readers
- **Reject** — the creative is removed and the next candidate moves up
- **Flag** — mark for review later

This approval workflow is why Promovolve runs multi-candidate auctions. If the auction only picked one winner and the publisher rejected it, the slot would be empty. With multiple candidates, rejecting one just promotes the next.

Yuki approves the ryokan ad. It fits her site perfectly.

## Ready to Bid

Takeshi's campaign is now in the system:
- Magazine creative rendered and approved for Yuki's site
- Ad product category: Travel (content categories derived automatically)
- Budget: $20/day, max CPM: $5
- No bid optimizer to configure — the auction handles price discovery

The next time the AuctioneerEntity for Yuki's site runs an auction — either from a fresh crawl or the 5-minute re-auction timer — Takeshi's campaign will be among the bidders.

But Takeshi isn't the only advertiser. A regional JR rail pass campaign is also targeting Travel with a $8 CPM. A hiking gear company targets Hiking/Camping at $4 CPM. A new cooking class in Kyoto targets Food & Drink at $3 CPM.

How does the system decide who gets which slot? That's the auction.

---

*Technical deep dives: [Entity Hierarchy](../architecture/entity-hierarchy.md) · [Bid Collection](../auction/bid-collection.md) · [Candidate Shortlisting](../auction/candidate-shortlisting.md)*
