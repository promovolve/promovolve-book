# Per-Campaign Diversity

Promovolve ensures diversity through two mechanisms: the auction-time fair selection algorithm and serve-time aggregate pacing.

## Auction-Time Diversity

The candidate shortlisting algorithm (in AuctioneerEntity) guarantees per-campaign representation:

```
1. Group candidates by campaign
2. Pick best creative per campaign (by CPM)
3. If #campaigns ≥ #slots:
     Take top campaigns by CPM → one creative each
4. Else:
     Each campaign gets 1 slot (guaranteed)
     Fill remaining slots with next-best creatives
```

This means 3 campaigns competing for 3 slots each get exactly 1 slot, rather than a single high-CPM campaign filling all 3.

## Serve-Time Aggregate Pacing

The pacing gate operates on **aggregate** campaign metrics, not per-campaign:

```scala
PacingContext(
  dailyBudget = sum of all participating campaign budgets,
  todaySpend = sum of all campaign spends (including pending),
  avgCpm = CPM-weighted average across campaigns,
  competingCampaigns = count of campaigns with budget remaining,
  ...
)
```

### Why Aggregate?

Per-campaign pacing would allow a high-budget campaign to crowd out a low-budget one:
- Campaign A ($1000/day): barely paced, always serving
- Campaign B ($10/day): heavily paced, rarely serving

Aggregate pacing asks: "Given the **total** budget of all campaigns here, is the combined spend rate appropriate?" This naturally balances delivery.

## Thompson Sampling as Natural Diversifier

Thompson Sampling itself provides diversity without explicit constraints:

- Each creative has its own `Beta(clicks+1, impressions-clicks+1)` posterior
- Sampling from Beta naturally introduces variance — even a dominant creative samples low sometimes
- New creatives have wide distributions → high variance → get explored
- Per-creative independence means every creative gets its own learning trajectory

## Ad Product Blocklist

Publishers can configure per-site ad product category blocklists:

```scala
adProductBlocklist: Set[AdProductCategoryId]
```

Distributed via DData (`AdProductBlocklistKey`), this filter runs at auction time to exclude entire categories of ads (e.g., gambling, alcohol) from the publisher's inventory.

## Creative Deduplication

When merging new auction results with existing candidates:

```scala
mergedViews = (newCandidates ++ orphanedCreatives).distinctBy(_.creativeId)
```

This prevents the same creative from appearing multiple times, which would bias Thompson Sampling.
