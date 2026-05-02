# The Magazine Format

Most things called "ad units" are rectangles. Promovolve's are magazine spreads.

The collapsed view sits in the publisher's slot like a magazine ad on a page — a single cover frame, often a hero image with a headline. Tapped, it expands into a full-screen overlay the reader can swipe through: cover, story pages, a call-to-action page. Tapped close, it folds back. If the reader wants to remember it, they can dog-ear the corner; the next time the same advertiser is eligible, the bookmarked creative is the one they see.

That whole flow runs as a single Web Component — `<expandable-magazine-banner>` — embedded in the publisher's page. The component is the canonical surface; the rest of this section explains what flows through it.

## From banner to spread

The reading experience has four distinct states, each with a clean transition:

| State        | What the reader sees                                     |
|--------------|----------------------------------------------------------|
| Collapsed    | Cover page rendered into the slot, sized to the slot     |
| Expanded     | Full-screen overlay; cover plus interior pages, swipeable |
| CTA page     | Final page of the spread; tapping fires the CTA event    |
| Folded       | Collapsed view with the corner clipped — pin is set      |

Expansion is opt-in. A reader who isn't interested taps past the slot and never sees more than the cover; the impression is recorded but no further bytes are loaded. A reader who taps in chooses, in that moment, to spend attention on the ad. The advertiser pays for the cover impression; the engaged time is a bonus, not something the reader can be tricked into.

This is closer to magazine reading than to web advertising. A magazine reader flips past most ads. A few catch their eye and they pause. Promovolve makes that explicit.

## Why expandable, not video or popup

Three formats compete for the "more than a banner" slot. Each makes a different bet about reader patience:

- **Auto-play video** assumes the reader will tolerate motion in their peripheral vision and will eventually look at it. Many readers don't, and adopt blockers when forced.
- **Popup / interstitial** assumes the reader will tolerate having their reading interrupted. Most don't, and the experience trains them to dismiss without reading.
- **Expandable magazine** assumes the reader has zero patience, and so it does nothing the reader didn't ask for. The cover is the entire above-the-fold cost; everything else is opt-in.

The third bet is harder for advertisers — it concedes that a reader who isn't curious gets a single quiet impression and nothing more. But it's the only one of the three that doesn't degrade with each new generation of ad-blocker.

## Anatomy of a creative

A creative is an ordered list of `Page` objects plus a top-level `BannerConfig`. The page schema is permissive — it carries headline, sub, body, caption, optional hero image, optional video background, page-level background color, and a list of layout items the designer positioned by hand or auto-layout generated.

```ts
interface Page {
  headline?: string;
  sub?: string;
  body?: string;
  caption?: string;
  img?: string;
  bg?: string;        // page background color
  isCTA?: boolean;
  ctaUrl?: string;
  ctaLabel?: string;
  layout?: LayoutItem[];
  videoBg?: VideoBg;
  // …
}
```

A few page-level details matter for the format:

- **Cover page is author-chosen.** `BannerConfig.coverPageIdx` selects which page renders in the collapsed slot. Default is page 0, but an author whose strongest hook is page 3 can promote it. The designer's "★ Cover" toggle drives this directly.
- **Page background is a color, not an image.** The overlay derives its surrounding background from the cover page's `bg` (using `color-mix` with luminance flip) so the expanded view feels like the cover spread into the whole screen, not a popup pasted on top.
- **CTA pages are special.** A page with `isCTA=true` becomes clickable. Layout items can opt in individually with `ctaTarget=true`; if no items are marked, the whole page is the click target as a fallback. Tapping fires a `cta-click` custom event the bootstrap listens for.

Component shapes (`text`, `image`, `rect`, `circle`) carry their own positioning, animation targets, and content references. Animation is per-item and per-target: an item can fade, translate, scale, or rotate from a base state to a `MotionTarget`, with configurable duration, delay, and easing.

## The web component contract

The publisher embeds `expandable-magazine-banner.js` once per page. The bootstrap script then writes a `<expandable-magazine-banner>` element into each ad slot with the attributes the runtime needs.

The observed attributes are the public contract:

| Attribute                | Meaning                                                                                  |
|--------------------------|------------------------------------------------------------------------------------------|
| `pages`                  | JSON-encoded array of `Page` objects — the spread itself                                 |
| `config`                 | JSON-encoded `BannerConfig` — font, expand effect, cover index, etc.                     |
| `width`, `height`        | Authored dimensions; used as the *aspect ratio*, not as a fixed size (see [Fluid Creatives](./fluid-creatives.md)) |
| `collapsed-page-index`   | Designer / preview override of `coverPageIdx`                                            |
| `mode`                   | `"edit"` for designer canvas, otherwise production                                       |
| `imp-url`                | Signed impression beacon URL — fired when ≥50% of the slot is in viewport                |
| `click-url`              | Signed click beacon URL — fired once per mount on first expansion                        |
| `landing-url`            | Fallback CTA URL when `page.ctaUrl` is empty                                             |
| `data-can-fold`          | `"false"` opts a serve out of the dog-ear corner                                         |
| `data-fold-token`        | HMAC-signed `FoldToken` the bootstrap redeems via `/v1/dogear-event` when the reader folds |

Everything inside the element is rendered into Shadow DOM. The publisher's CSS can't leak in; the banner's CSS can't leak out. The page-level styles the publisher cares about — slot width, slot aspect ratio — apply through the host element's `width` and `aspect-ratio` properties (the [Fluid Creatives](./fluid-creatives.md) chapter covers the responsive sizing pattern).

## Lifecycle: impression, click, CTA, fold

Each of the four engagement events is a different commitment from the reader, and each has a different beacon endpoint.

### Impression — `/v1/imp`

Fires when the slot becomes viewable: an `IntersectionObserver` watches the host element with a 50% visibility threshold, and the impression beacon goes out the first time that threshold is crossed. The `_impressionFired` flag prevents re-fire when the slot scrolls out and back in.

```
IntersectionObserver(threshold=0.5) → first crossing → GET imp-url (1×1 pixel)
```

This is the billable event. CPM clearing happens server-side based on the auction outcome the bootstrap already received in the serve response.

### Click — `/v1/click`

Fires the first time the reader expands the banner — tapping the collapsed slot. "Click" here is the historical name; functionally it's the *expansion* signal. The `_clickFired` flag makes it one-shot per mount: a reader who expands, closes, and re-expands doesn't get a 409 from the server's idempotency check.

### CTA click — `/v1/cta`

Fires when the reader taps the call-to-action on the CTA page. The page or marked layout items dispatch a `cta-click` custom event; the bootstrap listens, fires the CTA beacon, and opens `page.ctaUrl` (or `landing-url` as fallback) in a new window.

The three-tier model — impression (viewable) → click (expanded) → CTA (engaged) — gives publishers and advertisers a real funnel instead of the binary "served or not" signal traditional banners produce.

### Fold — `/v1/dogear-event`

Fires when the reader folds the corner of the creative. The bootstrap redeems the `data-fold-token` it received with the serve, the server verifies the HMAC and freshness, and the creative becomes a pin in the reader's IndexedDB. Folds are free engagement signals — no CPM clearing, no budget reservation. See [The Dog-Ear](./dog-ear.md) for the full protocol.

## What makes the format work

The magazine format is the surface, not the substance. Three other pieces make the surface viable in production:

- [**Fluid creatives**](./fluid-creatives.md) — the same creative renders into a 300×250 sidebar and a 375px phone slot, with no separate variants. Aspect-ratio sizing on the host plus container queries inside the Shadow DOM.
- [**The LP-to-creative pipeline**](./lp-to-creative.md) — small advertisers don't have to design anything. They enter a landing page URL, and Playwright + Gemini + the in-house designer produce a magazine creative.
- [**The dog-ear**](./dog-ear.md) — the reader's bookmark, stored in their own browser, that turns the magazine metaphor into actual behavior the reader can act on.

The auction and serving chapters (linked below) describe how creatives reach a slot in the first place. This chapter describes what they look like once they get there.
