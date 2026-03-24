# Re-Auction & Event Triggers

Between crawl cycles, the system keeps the ServeIndex fresh through periodic and event-driven re-auctions.

## Periodic Re-Auction

AuctioneerEntity runs a full re-auction every **5 minutes** (`promovolve.auction.reauction-interval`, env: `REAUCTION_INTERVAL`) for all pages within the 48-hour content recency window.

## Event-Driven Re-Auction

### Campaign-Level Events (Targeted)

These trigger re-auction only for pages where the affected campaign participated (using the `participatingCampaigns` map):

| Event | ServeIndex Action | Re-Auction Scope |
|-------|-------------------|-----------------|
| `CampaignBudgetExhausted` | Refresh TTL (keep entry) | Participating pages |
| `CampaignBudgetReset` | Refresh TTL | Participating pages |
| `CampaignPaused` | **Remove** from ServeIndex | Participating pages |
| `CampaignAdProductChanged` | **Remove** from ServeIndex | Participating pages |
| `CpmUpdated` | Update CPM in ServeIndex | Participating pages |
| `CreativeStatusChanged(isActive=false)` | **Remove creative** | Participating pages |

### Advertiser-Level Events (Full Site)

These affect all campaigns under an advertiser:

| Event | ServeIndex Action | Re-Auction Scope |
|-------|-------------------|-----------------|
| `AdvertiserBudgetExhausted` | Refresh TTL (keep entry) | All recent pages on site |
| `AdvertiserBudgetReset` | Refresh TTL | All recent pages on site |
| `AdvertiserSuspended` | **Remove** from ServeIndex | All recent pages on site |

## Budget Exhaustion: Keep, Don't Remove

When a campaign or advertiser budget is exhausted, creatives are **not removed** from ServeIndex. Instead:

1. **TTL is refreshed** to `dayDurationSeconds × 1.1 × 1000ms` (extends past next budget reset)
2. The serve-time **pacing gate** checks budget before serving
3. If budget is exhausted, the candidate is skipped and Thompson Sampling selects another
4. When budget resets (next day), the creative resumes serving without re-auction

**Why?** Budget exhaustion is temporary — budgets reset daily. Removing and re-inserting entries would:
- Create unnecessary DData churn (WriteMajority removes are expensive)
- Lose the creative's approval status
- Require a full re-auction to restore the entry

## Permanent Removal

Only these events warrant actual removal from ServeIndex:
- Creative paused/deactivated
- Campaign paused
- Campaign ad product category changed (may violate publisher blocklist)
- Advertiser suspended

These use `WriteMajority` consistency with up to 5 retries and 200ms initial backoff.

## Content Cleanup

Every 5 minutes, AuctioneerEntity prunes classifications older than 48 hours from its internal `Map[URL, Classification]`, ensuring stale content naturally ages out.

## Published Events

Re-auction and budget events are published as domain events (extending `CborSerializable`) for cross-entity coordination:

- `SpendUpdate`: Published every ~500ms or 20 events from CampaignEntity, includes `dailyBudget`, `todaySpend`, `dayStart`
- `PendingCreativesQueued`: Triggers SSE notifications for publisher approval workflow
