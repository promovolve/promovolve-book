# State Space

The floor CPM agent observes a **7-dimensional state vector** computed from the 15-minute observation window.

| Dim | Feature | Normalization | What it tells the agent |
|-----|---------|---------------|------------------------|
| 0 | currentFloor / maxObservedCPM | Cap at 2.0 | Is the floor high or low relative to the market? |
| 1 | fillRate | Raw 0–1 | Are auctions producing winners? |
| 2 | avgWinningCPM / currentFloor | Cap at 5.0 | How far above the floor are winners bidding? |
| 3 | avgBidderCount / 10 | Cap at 2.0 | How competitive is the market? |
| 4 | servedRevenue / baseline | Cap at 3.0 | Actual post-pacing revenue signal |
| 5 | rejectionRate | Raw 0–1 | How many bids is the floor killing? |
| 6 | budgetExhaustionRate | Raw 0–1 | Are budgets draining too fast? |

## Key Design Decisions

**Post-pacing revenue (dim 4):** The revenue signal comes from actual served impressions tracked by `LearningEventLog`, not from auction-time clearing prices. This prevents the agent from being fooled by high auction prices that never translate to served revenue because pacing throttles the impressions.

**Budget exhaustion (dim 6):** A high floor drains budgets faster (solo winners pay floor price). This dimension gives the agent early warning before revenue drops to zero from exhausted budgets.

**Normalization:** All dimensions are capped to prevent extreme values from dominating the neural network. The caps are generous enough that normal operating ranges stay within the linear region.

## Baseline for Revenue

Revenue per auction (dim 4) is normalized by `currentFloor / 1000` — the revenue from one impression at floor price. This makes the signal independent of the absolute floor level:
- Normalized revenue = 1.0 means "earning exactly floor price per auction"
- Normalized revenue > 1.0 means "competition is pushing clearing prices above floor"
- Normalized revenue < 1.0 means "not even filling at floor price"
