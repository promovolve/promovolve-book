# Floor Optimization

Every ad slot on a publisher's site can sell for somewhere between zero
and "whatever the highest-paying advertiser would have paid." Where in
that range it actually clears depends on a single number the publisher
sets: the **floor price** — the minimum bid the auction will accept.

This chapter is about how Promovolve sets that number automatically, so the
publisher doesn't have to guess.

---

## Imagine you run a flower stall

Three customers walk up. They each have a flower in mind and a number
in their head: the most they'd pay.

- Customer A: would pay up to **$2**
- Customer B: would pay up to **$6**
- Customer C: would pay up to **$10**

You're running a quiet auction. You can either:

1. **Sell to whoever walks up first** at whatever they offer. Customer A
   gets the flower for $2.
2. **Take the highest offer.** Customer C wins, pays $10.
3. **Take the highest offer, charge them just enough to beat the
   second-place bid.** Customer C wins, pays a little over $6.

Promovolve's auction works like option 3 — winners pay roughly what they'd
have had to pay to beat the next-best offer. It's called *second-price*,
and it has a nice property: bidders are incentivized to bid honestly.
Customer C bids $10 because there's no penalty for it; they only pay $6.

Now the publisher's question: **should you set a minimum bid?**

---

## Why a minimum matters

Same three customers. Now you say: "I won't sell for less than $5."

- Customer A ($2 max) — excluded.
- Customer B ($6 max) — in the auction.
- Customer C ($10 max) — in the auction.

Customer C wins. Pays $6.something (just enough to beat B's $6). You made
slightly more than the no-minimum case. The minimum did nothing because
the *second-best* bidder (B at $6) was already higher than your minimum.

Try a higher minimum: $7.

- Only Customer C qualifies.
- Customer C wins. Pays $7 (the minimum sets the price now, since there's
  no second bidder above it).
- You made $7 instead of $6. **More money per sale.**

Try $11.

- Nobody qualifies.
- The flower sits there. You made $0.

There's a sweet spot. It's whatever minimum still lets at least one bidder
in *while* extracting more from them. Set the minimum too low and you
leave money on the table. Set it too high and the sale doesn't happen.

The hard part: **you don't know what Customer A, B, or C would pay.**
They're not going to tell you. You only see what they actually bid, in
auctions you actually run.

---

## The mechanism, in one sentence

A second-price auction clears at `max(floor, second-highest bid)`.
Three cases follow from that one formula, and the whole point of sweep
is to find the publisher's position on this curve.

**Case A — floor below the natural second-bid:**

```
floor = $4, bids = $6, $9
winner  = $9 bidder
pays    = max($4, $6) = $6   ← floor does nothing; second-bid sets the price
```

The floor changes nothing. Raising it here doesn't add a penny. You
only lose bidders who couldn't have changed the outcome anyway.

**Case B — floor above the natural second-bid (but below the winner's max):**

```
floor = $7, bids = $6, $9
winner  = $9 bidder
pays    = max($7, $6) = $7   ← floor REPLACES the second-bid; publisher captures the gap
```

The publisher just earned **$1 extra per impression** that they would
have left on the table at the lower floor. The $6 bidder is still
"there" in the sense that they bid, but their bid no longer matters for
clearing — the floor took over the price-setting role. This is the
zone where raising the floor actually pays.

**Case C — floor above the winner's max:**

```
floor = $10, bids = $6, $9
nobody clears.
slot empty. revenue = $0.
```

Too aggressive. The top bidder is now excluded too. The slot empties.
Zero revenue, no impression served.

Plotted against floor, the publisher's revenue looks like this:

```
revenue
    ▲
    │           ╱──╲
    │      ╱───      ╲
    │ ────             ╲
    │                    ╲___
    └────────────────────────► floor
    A         B           C
    ↑         ↑           ↑
    floor     floor binds  floor too high
    doesn't   on some      everyone
    bind      auctions     excluded
```

- **Flat in A** because the clearing price comes from the second-bid,
  not the floor.
- **Rising in B** as the floor binds more and more auctions, capturing
  the gap between floor and old second-bid.
- **Cliff in C** as the top bidder gets excluded too.

So sweep is doing one specific thing: **finding a floor that's higher
than the natural second-price but still below the winner's max** — the
top of the curve. Every dollar above the old second-bid is money the
publisher couldn't have seen without raising the floor. Every dollar
above the winner's max is a slot lost. The optimum is the highest
floor that still leaves at least the top bidder above it.

Below the natural second-price, the floor changes nothing. Above it,
the floor extracts the gap. That's the whole game. Everything else in
this chapter is mechanics for finding that exact point automatically,
per site, while the bidder mix keeps shifting.

---

## The publisher's dilemma

A real publisher faces the same setup, except:

- Customers (advertisers) come and go.
- Each ad slot might draw a different mix of bidders.
- The "right" minimum changes from day to day, and slot to slot.
- You're running thousands of auctions per minute — there's no time to
  hand-pick a minimum for each one.

So the question becomes: **how do we figure out the right minimum,
automatically, without asking the bidders what they'd pay?**

---

## The simple idea behind sweep

Stop guessing. Just *try*.

1. Pick a few candidate minimum prices to test. Say $1, $2, $3, … up to $10.
2. Use each candidate as your minimum for a short window — say five
   minutes.
3. During that window, count how much money you actually made.
4. Whichever minimum made the most money, use that one going forward.
5. Every now and then, repeat the whole experiment — the market might
   have changed.

That's it. The whole optimizer is one paragraph.

We call it **sweep** because the system sweeps through the candidate prices
in order, like a spotlight scanning across them. There's no clever theory,
no learning algorithm, no statistical model. Just trying each price and
measuring the result.

---

## Why this works

It works because the publisher *can* measure the answer. Unlike asking
"what would Customer B have paid?", asking "did we make more money at a $5
minimum or a $7 minimum?" has a direct answer — count the dollars.

The auction itself tells the truth: bidders either show up and clear the
minimum, or they don't. Whoever wins, pays a real amount. The publisher
counts those amounts. After ten candidate prices and a few minutes each,
the publisher has ten little experiments and picks the best one.

There's no missing information. No model that might be wrong. No
assumptions about advertiser behavior that need to hold. The optimizer's
output is the same as what a careful person with a spreadsheet would have
concluded.

---

## What changes when there are many slots

A real publisher has dozens of ad slots on dozens of pages. They're not all
equally valuable: a banner at the top of an article page is worth more
than the same banner stuck in the footer.

It would be wasteful to set the same minimum across all of them. The
top-of-article banner can support a $5 minimum; the footer might need to
stay at $1 to attract any bidders at all.

Promovolve handles this with **per-slot quality scores**. When the system
first visits the publisher's pages, it notices things like:

- Is this slot above the fold (visible without scrolling)?
- How much of the slot is visible when the page loads?
- Is it in the article body, the sidebar, the header, the footer?
- How much real text is around it?

It bundles these signals into a single score between 0 and 1: a number
that says "this slot is high-quality" or "this slot is lower-quality."
The site-level minimum is then *multiplied* by a number in the range 0.5
to 1.5 depending on that score.

So if the publisher's site minimum is $5:

- A premium header slot (score 0.92) effectively asks for $5 × 1.42 = **$7.10**.
- A footer slot (score 0.16) effectively asks for $5 × 0.66 = **$3.30**.

The publisher doesn't have to set a different minimum for every slot. They
set one site-level minimum, the system adjusts it per slot.

## Per-category floors

The same sweep also runs **per demand category**, and those floors are the
ones targeted advertisers actually pay against — the site-wide sweep is
the fallback for categories that don't have their own floor yet. Two
rules keep them honest:

- **Only approved demand teaches floors.** A pending creative (not yet
  approved by the publisher) bids and can win its way into the approval
  queue, but its bids never move a floor. When a category's approved
  demand drops to zero, its floor collapses to the minimum immediately
  instead of draining over a sweep cycle.
- **A single approved bidder pegs the floor to their bid.** With one
  advertiser there is nothing to measure — their bid *is* the
  revenue-optimal reserve — so the floor follows it directly, and the
  sweep takes over only when a second bidder appears.

Publishers can watch all of this on the Floor Decisions page: the live
per-category floors, the sweep's evidence table, and the learned traffic
shapes driving pacing.

---

## What changes over time

Advertisers come and go. A retailer's holiday campaign ends; a new
sneaker brand shows up; an existing advertiser raises their maximum bid
because their last quarter was strong.

If the publisher set the minimum at $5 in October and forgets about it,
by December the market might support $7 — but the publisher would still
be earning the old rate.

Sweep handles this by **running the experiment again, periodically**.
Every full cycle through the candidate prices (about 4 minutes in the
default test setup; ~25 minutes in a production-paced day), the
optimizer rediscovers the current best minimum. If the market shifted,
the new winner reflects the shift within one cycle.

There's no human intervention required. The publisher sees their floor
gradually move with the market.

---

## How the publisher sees this in their dashboard

A publisher running Promovolve doesn't need to know any of the above. They
look at three things on their dashboard and the optimizer's behavior is
visible at a glance.

### The Sites page — current optimized floor

On each site row, two numbers sit next to each other:

```
Optimized: $5.00  ▲ +$0.50    Starting floor: $3.00
```

The big green number is what the optimizer chose for the most-recent
cycle. The arrow shows how it moved since the previous cycle (▲ green if
it went up, ▼ orange if down, = gray if unchanged). The small grey
"Starting floor" is the manual value the publisher set; in sweep mode it
acts only as a startup default — the optimizer overrides it within
seconds.

If a publisher just wants to know "what am I charging right now?", that
green number is the answer.

### The "Optimized floor over time" chart

Clicking through to the site's Floor Decisions page reveals a chart
titled *Optimized floor over time*. Each dot is one completed cycle's
pick. The dots are connected by a line so the publisher can see the
trajectory at a glance.

Three patterns to look for:

- **Flat horizontal line** — every cycle picked roughly the same number.
  The market is calm; the optimizer is confident.
- **Zig-zag in a narrow band** — picks vary but only by a dollar or two.
  This usually means several candidate floors produce similar revenue
  (a flat-revenue zone), and the optimizer is correctly reporting that
  the exact pick doesn't matter much.
- **Trend up or down** — the optimized floor is drifting. Almost always
  this means the bidder mix is shifting: a new high-bidder showed up, or
  an existing bidder raised their max. The chart traces the shift.

The chart sits above the per-cycle evidence table, and every dot
persists across cluster restarts — the history is real, not just
in-memory.

### The stability badge

Above the chart sits a small coloured badge that interprets the recent
history so the publisher doesn't have to read shapes:

| Badge | Meaning |
|---|---|
| 🟢 **Stable optimum** | Last 3+ cycles all within $0.50 of each other |
| 🔵 **Converging** | Two consecutive cycles agree |
| 🟡 **Mildly variable** | Picks bounce within a few dollars; expected when revenue is flat across low floors |
| 🟠 **Highly variable** | Picks span a wide range; usually a sign the market is volatile or traffic is too thin to measure cleanly |
| ⚪ **Insufficient data** | Fewer than two completed cycles yet |

A publisher reading their dashboard sees the badge first ("Stable
optimum" = peace of mind) and only digs into the chart shape if the
badge says something more interesting.

### The per-cycle evidence

Below the chart, a table shows what the optimizer measured this cycle
candidate-by-candidate, and how each candidate's revenue compares to the
previous cycle. An example row looks like:

| Floor | This cycle | Imps | Last cycle | Δ | Relative |
|---|---|---|---|---|---|
| $5.00 | $0.29 | 60 | $0.25 | +$0.04 | █████████████████ |
| $6.00 | $0.18 | 35 | $0.20 | -$0.02 | ██████████ |
| $7.00 | $0.04 | 6 | $0.03 | +$0.01 | ██ |

The Δ column shows whether each candidate is earning more or less than
it did last cycle — useful for spotting which floors are gaining and
which are losing as the market moves. The "Relative" column is a
horizontal bar showing each candidate's revenue as a fraction of the
cycle's winner. If the bars are roughly equal, the optimizer's pick is
barely beating its runners-up (flat zone); if one bar dominates, the
pick is decisive.

A publisher who wants to understand *why* a particular floor was chosen
reads this table. Everyone else can ignore it.

### How to read the dollar relationships

The relationship between floor price and revenue at that floor is the
publisher's actual question, and the table is showing it experimentally.
Two opposing forces are at work in every row:

- **As floor rises**, the per-impression clearing price tends to **rise**
  — either because the floor sets the clearing price directly, or
  because excluding the lower bidders pushes the second-price up.
- **As floor rises**, the impression count tends to **fall** — some
  bidders no longer clear, and on premium slots the per-slot quality
  multiplier pushes the effective floor even higher.

Total revenue is the product. The right floor is wherever that product
peaks.

Walking through a real cycle's data:

| Floor | Revenue | Imps | per-imp CPM |
|---|---|---|---|
| $1.00 | $0.2050 | 39 | $5.26 |
| $2.00 | $0.1660 | 27 | $6.15 |
| $3.00 | $0.0540 |  8 | $6.75 |

Both forces are visible: CPM rises ($5.26 → $6.15 → $6.75) but
impressions drop sharply (39 → 27 → 8). For this market, the volume
loss outweighs the price gain — total revenue declines as the floor
rises. The optimizer would pick the lowest of these three.

That's not always the answer. Different markets show different shapes,
and the column reveals which one the publisher is in:

| Shape across the rows | What it means | What sweep does |
|---|---|---|
| Numbers roughly flat | Floor isn't binding; clearing price unchanged | Picks the lowest (max volume) |
| Numbers rising with floor | Floor is binding; extracting more per imp | Keeps raising until... |
| Numbers peak then drop | ...the inflection is found | Picks the peak |
| Numbers cliff to zero | Floor crossed the top bidder; slot goes empty | Backs off |

A publisher reading this table doesn't need to do any math — the
optimizer's pick is the row with the highest dollar value. But seeing
the *shape* tells the publisher something the headline number can't:
**how sensitive their revenue is to the floor choice.** A flat shape
means the choice doesn't matter much (and the publisher should focus on
attracting more bidders instead). A sharply peaked shape means the
choice matters a lot and the optimizer is earning its keep.

### What's not shown (deliberately)

The dashboard doesn't expose the optimizer's internal mechanics — the
phase names (Sweep / Exploit / Init), the per-tick floor changes, the
cursor position. Those exist as a separate diagnostic page for engineers
debugging the system. The publisher view is just **what was decided** and
**how to read whether that's normal or a sign of change**.

---

## Does this actually help the publisher make more money?

Yes — and the simplest way to see it is with a worked example.

Imagine your flower stall now has five regular customers, each with a
private maximum they'd pay:

- Anna: $5
- Bob: $6
- Carol: $7
- Dave: $8
- Eve: $9

The auction is second-price: whoever bids highest wins, but pays the
second-highest. When all five show up, Eve wins and pays $8 (Dave's
bid).

Now you set different minimums and watch what happens:

| Minimum | Who's in the auction | Eve wins, pays | Revenue per sale |
|---|---|---|---|
| $3.40 | All five | $8 (Dave's bid is the second-highest) | **$8** |
| $4.50 | All five still | $8 | $8 |
| $5.60 | Bob through Eve (four) | $8 (Dave still in, his bid still highest under Eve) | $8 |
| $6.70 | Carol through Eve (three) | $8 | $8 |
| $8.50 | Dave and Eve only | $8.50 (floor sets the price now) | $8.50 |
| $9.50 | Eve might not even bid | nothing | $0 |

Two observations:

**Below ~$8**, every minimum extracts the same $8 per sale (the
second-price). Whether you set $0.10 or $5.60, Eve pays Dave's $8.

**Above ~$8**, the floor starts binding — it sets the price directly,
but each step up excludes a bidder. At $8.50 you make $0.50 more per
sale but you've lost Carol and below; at $9.50 you might lose Eve too
and the slot empties.

What sweep figures out, by trying each minimum and counting real
dollars over a short window:

- The price-per-sale is roughly flat across low minimums
- The volume of sales drops sharply once you start excluding bidders
- The total revenue (price × volume) peaks at the highest minimum that
  doesn't lose anyone — in this example, somewhere around $3-$4

That's what we observed in actual testing. With five advertisers bidding
**$5/$6/$7/$8/$9** held static against a real publisher site, sweep's
picks clustered in the **$3 – $5** range across multiple cycles — the
zone that keeps all five bidders in the auction while letting the
second-price mechanism extract its maximum.

In a follow-up run where four of the bidders raised their max prices
whenever they were excluded (simulating "responsive bidders" — what
happens when advertisers compete to win silent slots), sweep's argmax
**drifted upward in lockstep**, climbing from ~$3 to ~$7 over half an
hour as the underlying bid distribution rose. The chart traced the
shift dot-by-dot; no human intervention needed.

**Versus setting the minimum by hand:**

A publisher who sets the floor at, say, $5 and forgets about it would
lose some traffic when per-slot quality multipliers push the effective
floor above $5 for premium slots. A publisher who sets it at $1 to be
safe misses the small additional revenue from low-CPM-bidder wins.
Sweep, in either case, ends up at a value that's at least as good as
the human pick — and adapts when the bidder mix changes next week.

In the bigger picture: sweep doesn't manufacture revenue out of
nothing. It extracts the maximum the current market is willing to pay,
continuously. The gain over a static manual floor is small in any one
day; the gain over a year is substantial because the market changes
constantly and sweep tracks it.

---

## What sweep doesn't try to do

A few things sweep *intentionally* doesn't tackle, because they need
different solutions:

**It can't bring in new advertisers.** If no one is bidding on your site
at any price, the minimum doesn't matter. Sweep finds the best price
*among the bidders you already have*. Growing the demand pool is a
business problem, not an optimization one.

**It doesn't read the future.** Sweep picks the price that worked best
*last cycle*. If raising the floor would have caused a critical
advertiser to leave next month, sweep wouldn't know. It's good at
short-term optimization, blind to long-term consequences.

**It needs traffic.** The way sweep measures "what made the most money"
is by counting actual dollars from actual impressions. On a brand-new
site with five impressions a day, the measurements are too small to be
trustworthy. Sweep works best on sites with at least a few impressions
per minute on the slots being measured.

**It doesn't try to be clever about which bidder wins.** That's a
separate part of the system (the "auction"). Sweep only adjusts the
minimum threshold; once a bidder clears it, the existing auction picks
who wins.

---

## The minimum is one knob

Sweep automates the *floor*. But a publisher's revenue also depends on:

- **Which advertisers are even allowed to bid** (the publisher's approval
  queue and blocklist).
- **Which ad slots are exposed at all** (the publisher's page layout and
  the slots the ad tag discovers on the live page).
- **What happens when no one bids** (does the slot stay empty or fall
  back to a generic "filler" auction?).
- **How aggressively the auction prefers high-bidding creatives over
  high-CTR creatives** (a knob called *bid weight* or *ad priority*).

Sweep takes the publisher's choices on those other knobs as given and
optimizes the one knob it's responsible for. The publisher's revenue
isn't just sweep; it's sweep plus everything else they choose to do.

---

## Where to go next

If you want to see the optimizer running against a real test setup —
five advertisers bidding $2 through $10, watching the floor settle —
the [test report](../../../scripts/rl-test/SWEEP_TEST.md) walks through
a session start to finish, including the per-candidate revenue tables
and the empirical evidence behind the wide-cluster vs tight-cluster
conclusions in this chapter.
