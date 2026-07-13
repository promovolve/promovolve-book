# Serve Time: Thompson Sampling

The auction cached a pool of candidates. Now a reader is here, and the
system must pick — quickly, per impression, for every slot on the page at
once. This is where Promovolve learns.

## One request per page

The ad tag sends a single batch request listing every slot. The site's
`AdServer` entity checks, in order: the requesting host is the site's
verified host (`403` otherwise); the page's classification is inside the
freshness window (`204` otherwise); reader dog-ears are honored first (a
valid pin takes its slot and skips everything below); and the pacing gate —
see [Budget Pacing](./pacing.md) — decides whether this impression should be
spent at all.

What remains is selection over the candidate pool.

## Score by sampling, not by averages

Each creative carries a rolling 60-minute window of impressions, clicks, and
folds, bucketed by minute. From it, two Beta distributions:

```
sampledCTR  ~ Beta(clicks + 1,  impressions − clicks + 1)
sampledFold ~ Beta(folds + 1,   impressions − folds  + 1)
```

Every request, every candidate **draws** from its distributions — it does
not use its mean. The score:

```
engagement = sampledCTR + 2.0 × sampledFold + newcomerBonus
score      = engagement × CPM^α
```

Sampling is the whole trick (this is Thompson Sampling). A creative with
1,000 impressions draws values tightly around its true rate; a creative with
9 impressions draws wildly. Uncertain creatives therefore *sometimes* draw
high and win — exploration — in exact proportion to how uncertain they are.
No exploration schedule, no epsilon, no phases: confidence itself allocates
the experiments, and as data accumulates the draws narrow and the best
creative simply wins most often.

Clicks here are magazine-opens — in this format the click *is* the expand.
Folds are dog-ears, weighted 2× because a reader bookmarking the ad is a
stronger signal than one merely opening it.

The exponent **α** is the publisher's one tuning knob (`bidWeight`): 0.5 by
default, so a $10 bid beats a $1 bid by ~3.2×, not 10× — price matters, but
a creative readers engage with can beat a richer one that they ignore.
Publishers wanting discovery set 0.3; wanting revenue, 0.7.

## Cold start, inside the same formula

New creatives get two helps, both expressed as scores — there is no separate
cold-start code path, round-robin, or forced serving:

- **Zero impressions:** the CTR draw is replaced by the creative's category
  affinity score (how well its category matched the page at auction time)
  plus uniform noise of ±0.15, and the fold draw comes from a `Beta(1, 3)`
  prior. A relevance-informed guess instead of a coin flip.
- **First 50 impressions:** an additive newcomer bonus starting at +0.5 and
  decaying linearly to zero — a guaranteed runway against confident
  incumbents, gone by the time the creative has real data.

Selection stays a single argmax at every lifecycle stage.

## Filling the page

Slots are assigned greedily, largest first, each taking the remaining
candidate with the highest sampled score — under two hard rules: a creative
appears at most once per page, and **a campaign appears at most once per
page**. A page plastered with one advertiser is bad for the reader, the
publisher, and the advertiser; the constraint is enforced at assignment
time, where it can't be gamed.

The winner's budget is reserved before the response is sent, and the
impression is recorded server-side at selection — billing does not depend on
a tracking pixel surviving the reader's browser. Clicks (expands), folds
(dog-ears), and CTA events arrive later through tracking endpoints and
update the Beta windows.
Dog-eared re-encounters update none of this: they live in separate counters,
excluded from learning, spend, and reporting's primary metrics.
