# Fluid Creatives

A Promovolve creative is authored once and renders into any rectangle the publisher offers. Same creative, 300×250 sidebar on desktop, 375px-wide phone slot, 970×90 leaderboard — proportions preserved, no separate variants. This chapter explains how that works and why it's not just "responsive design" applied to ads.

## The IAB matrix problem

Traditional programmatic ads ship as pixel-locked IAB units: 300×250, 728×90, 970×250, 160×600, 336×280, 320×50. A campaign that wants to run across every reasonable inventory size has to produce all of them — a creative-production matrix the small-business advertiser doesn't have the resources for.

The mobile gap makes it worse. A reader landing on a publisher's mobile site has slots that don't match any desktop IAB size. Publishers either hide the slots or serve a separately-produced mobile creative. The advertiser maintains a parallel mobile pipeline; the small-business advertiser produces nothing and gets no fill.

Fluid creatives close both gaps in one shot. There is no matrix. There is no "mobile variant." There's the creative.

## Aspect ratio over pixel size

The trick is that the creative is authored at an *aspect ratio*, not a fixed pixel size. The host element's CSS sizes itself by aspect ratio rather than by absolute width and height:

```css
.design-box {
  container-type: size;
  aspect-ratio: ${w}/${h};
  width: 100%;
  max-width: 100%;
  max-height: 100%;
  position: relative;
  overflow: hidden;
}
```

`width: 100%; max-width: 100%` tells the box to expand into whatever space the publisher's slot gives it. `aspect-ratio` keeps the height proportional. On a 300px-wide slot the box renders at 300×250; on a 200px-wide phone slot it renders at 200×167 with the same proportions.

`container-type: size` is what makes everything inside the box scale with it (next section).

## Container queries: cqh and cqmin

Fixed-pixel typography breaks under fluid sizing. A 16px headline that looks right at 300×250 looks oversized at 200×167 and undersized at 728×90. CSS container queries solve this.

The banner's interior dimensions all use container-relative units:

- `cqh` — 1% of the container's height
- `cqw` — 1% of the container's width
- `cqmin` — 1% of `min(width, height)`
- `cqmax` — 1% of `max(width, height)`

So a headline sized at `8cqh` is always 8% of the container's height, regardless of how big or small the container is. The dog-ear flap is `6cqmin` square — 6% of the smaller dimension. Page navigation uses `12cqmin` on desktop and `7cqmin` on mobile (the cover-page picker tightens up at small sizes so it doesn't dominate the slot).

The result: every text size, every padding, every icon, every animation distance scales with the container. A creative authored at 300×250 retains its visual hierarchy at 200×167 or 728×90 — proportionally smaller text, proportionally narrower padding, but the same composition.

No `px` inside the design-box. That's the rule the designer enforces and the runtime preserves.

## The publisher slot

The other half of the contract is the slot the publisher renders into. The reference pattern lives in `modules/examples/publisher-site-ja/index.html`:

```css
.ad-slot {
  width: 100%;
  margin: 16px auto;
}
.ad-slot[data-ad-width="728"][data-ad-height="90"]   { max-width: 728px; aspect-ratio: 728/90;  }
.ad-slot[data-ad-width="970"][data-ad-height="90"]   { max-width: 970px; aspect-ratio: 970/90;  }
.ad-slot[data-ad-width="300"][data-ad-height="250"]  { max-width: 300px; aspect-ratio: 300/250; }
.ad-slot[data-ad-width="336"][data-ad-height="280"]  { max-width: 336px; aspect-ratio: 336/280; }
.ad-slot[data-ad-width="160"][data-ad-height="600"]  { max-width: 160px; aspect-ratio: 160/600; }
.ad-slot[data-ad-width="320"][data-ad-height="50"]   { max-width: 320px; aspect-ratio: 320/50;  }
```

Attribute selectors keyed off `data-ad-width` and `data-ad-height` apply the right `max-width` and `aspect-ratio` per slot. The slot fills its parent's width up to the authored maximum, then preserves the aspect ratio. On a 1100px-wide desktop layout, a 300×250 slot renders at 300×250. On a 375px-wide phone, it renders at 300×250 if the column is wide enough, or scales down proportionally if it isn't.

A `@media (max-width: 768px)` rule stacks the sidebar below the main content for phone layouts. Slot sizing inside the sidebar still works — same `aspect-ratio` rules apply.

Combined: publisher slot is fluid (responsive), creative is fluid (aspect-ratio + container-queries), and the two compose. A 300×250 creative in a 200px-wide slot fills the slot at 200×167 with everything proportional.

## What this isn't

It's not "responsive web design" in the sense of the page reflowing into a single column on mobile. The creative's composition doesn't reflow — text doesn't wrap into a different column count, images don't crop differently, layout items don't rearrange. The whole creative scales like a vector image, just smaller.

That distinction matters because it preserves the *design intent*. A creative laid out elegantly at 300×250 stays elegant at 200×167. A reflow-style "responsive" creative would have to pick a new layout for each breakpoint, which is exactly the multi-variant production problem fluid creatives solve in the first place.

It's also not pixel-perfect at every size. A creative authored at 728×90 (a wide leaderboard) looks ridiculous in a 300×250 sidebar — too short for that aspect ratio. Fluid creatives scale to fit, but they don't reshape; an authored aspect ratio that's wildly mismatched to the slot still looks bad. The IAB-mode lock in the [designer](./designer.md) is one tool advertisers use to commit to a specific aspect ratio; the LP-to-creative pipeline ([LP-to-Creative](./lp-to-creative.md)) is the other, generating per-aspect-ratio variants when the source LP supports it.

## Authoring discipline

The "fluid everywhere" property is fragile. It requires that *nothing* inside the design-box uses a fixed pixel size — one stray `font-size: 14px` and the creative breaks at small slots. The discipline is enforced in three places:

- **The runtime banner.** `banner.ts` uses `cqmin` / `cqh` / `cqw` for every interior dimension. No `px` literals on layout-driven properties.
- **The designer.** The creative editor's canvas exposes the authored dimensions to the user, but the values written into the saved creative are aspect-ratio-relative. The designer enforces this; users can't accidentally write a fixed-pixel layout.
- **The reference publisher site.** The pattern at `modules/examples/publisher-site-ja/index.html` is the canonical responsive-slot recipe. Anyone integrating with Promovolve can copy that block directly.

When adding new editor surfaces or new component types, the rule is "container queries inside, `aspect-ratio` + `max-width` outside." Don't regress to hardcoded pixels.

## Why this matters for the product story

Fluid creatives close the gap that excludes most advertisers from programmatic. The local restaurant doesn't run a 300×250 / 728×90 / 970×250 / 160×600 / 336×280 / 320×50 production pipeline — they have one ad. The mid-market brand doesn't maintain a parallel mobile creative team — they have one ad. The agency doesn't bill two production rounds — they bill one.

It also makes the [LP-to-Creative pipeline](./lp-to-creative.md) economically viable. If the pipeline had to generate seven IAB-sized variants per landing page, the cost-per-creative would balloon. Generating one fluid creative cuts that to a single Playwright + Gemini + designer pass.

And it composes cleanly with the [magazine format](./overview.md). Expanding into a full-screen overlay isn't a separate creative; it's the same creative rendered at the viewport's aspect ratio. Container queries handle the resize automatically.

## Source of truth

- `platform/banner-component/src/banner.ts` — host sizing (`aspect-ratio`, `container-type: size`), interior dimensions in `cqmin` / `cqh`
- `platform/banner-component/src/render-overlay.ts` — overlay sizing
- `platform/creative-designer/src/render/canvas.ts` — designer enforces the model
- `modules/examples/publisher-site-ja/index.html` — canonical responsive-slot pattern
