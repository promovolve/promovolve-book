# The Designer and Banner Stack

The [magazine format](./overview.md) is a contract between two pieces of TypeScript code:

- The **designer** (`platform/creative-designer/`) — a page builder where advertisers compose creatives. Drag, resize, rotate; type copy; pick fonts and colors; fan out across IAB sizes.
- The **banner** (`platform/banner-component/`) — the runtime web component publishers embed. Renders the same data the designer produces.

The contract is a JSON shape: `BannerConfig` plus a `Pages` array. The designer writes it. The banner reads it. WYSIWYG isn't an aspiration — it's a constraint. If the same JSON renders differently in the two places, something is broken.

## What the designer is

The designer is a Vite-built TypeScript bundle served by the Go dashboard. It's not a separate app — it loads inline into a dashboard page when an advertiser clicks "Edit creative" or "Create from LP." The bundle weighs ~135 KB gzip and has no React, no framework. State management is a tiny in-house store with subscribers; the canvas is plain DOM elements positioned with absolute coordinates.

The structural pieces:

```
src/
├── modes.ts          ← canvas mode catalog (Expanded PC, Mobile, IAB sizes)
├── state.ts          ← functional state updates (immutable transitions)
├── store.ts          ← in-house pub/sub store
├── types.ts          ← shared with banner-component
├── render/
│   ├── canvas.ts     ← visible canvas + selection chrome
│   ├── overlay.ts    ← drag/resize/rotate handles
│   └── rulers.ts     ← page-aware ruler guides
├── ui/
│   ├── menu-bar.ts, toolbar.ts, sidebar.ts
│   ├── canvas-header.ts, canvas-foot.ts
│   ├── props-panel.ts, layers.ts, animation-panel.ts
│   ├── page-bg-panel.ts, banner-config-panel.ts
│   ├── size-matrix.ts ← multi-size fanout view
│   ├── save.ts        ← assemble + POST to /advertiser/creatives/save
│   └── …
└── interaction/      ← pointer/keyboard handlers
```

## Canvas modes

A creative isn't a single layout — it's a primary 16:9 "expanded" composition plus an optional set of IAB-sized variants (300×250, 728×90, 970×250, etc.). The `MODES` table in `modes.ts` lists all eleven:

```ts
{ key: "expanded", label: "Expanded PC (16:9)",     w: 1600, h: 900 }
{ key: "mobile",   label: "Expanded Mobile (9:16)", w: 540,  h: 960, sizeKey: "mobile-expanded" }
{ key: "300x250",  ...                                         sizeKey: "300x250" }
{ key: "728x90",   ...                                         sizeKey: "728x90" }
…etc.
```

The expanded mode is the master. Sized modes are *fanouts* — variants of the same content reflowed for that aspect ratio. The data model reflects this:

- Expanded mode mutations target `page.layout` (the master layout array).
- Sized mode mutations target `page.banners[sizeKey]` (the per-size fanout).

The size-matrix UI shows all sizes side-by-side as thumbnails so the author can spot mismatches and re-fan-out from the master. The [LP-to-creative pipeline](./lp-to-creative.md) seeds both expanded and mobile in stage 3 (the paired Gemini call); the author can then fan out to additional IAB sizes from the matrix.

Because the format is fluid (see [Fluid Creatives](./fluid-creatives.md)), most advertisers don't need every IAB size — the expanded master scales into many slots. Sized fanouts exist for cases where the master at, say, 300×250 needs a tighter composition than a straight scale would produce.

## The page model

A creative is a list of `Page` objects:

```ts
interface Page {
  headline?: string;
  sub?: string;
  body?: string;
  caption?: string;
  bg?: string;                   // page background color
  isCTA?: boolean;
  ctaUrl?: string;
  layout?: LayoutItem[];          // expanded layout
  banners?: Record<string, LayoutItem[]>; // per-IAB-size fanouts
  videoBg?: VideoBg;
}
```

Five page-level affordances the designer exposes:

- **Cover picker** (`★ Cover` toggle in `canvas-header.ts`). The author marks which page is the cover — the static frame readers see in the collapsed slot. Defaults to page 0; an author whose strongest hook is page 3 can promote it. Saved as `BannerConfig.coverPageIdx` and consumed by the banner runtime.
- **Page background color** (`page-bg-panel.ts`). Each page can have its own background. The expanded overlay derives its surrounding background from the cover page's bg via `color-mix` with luminance flip, so the overlay feels like the cover spread across the screen.
- **Video background** (`page-bg-panel.ts` + `state.setVideoBg`). Optional full-bleed video that plays under the layout in every mode. Authoring-rare; mostly used by big-brand creatives.
- **CTA flag.** Marking a page `isCTA: true` makes its `ctaUrl` clickable. Layout items can opt in individually with `ctaTarget=true`; if no items are marked, the whole page becomes the click target.
- **Page reordering** (drag in the page list). Pages are an ordered sequence; reordering shifts both the master `layout` and every `banners[*]` fanout in lockstep.

## Layout items

A layout is a flat array of items. Four types share `LayoutItemBase`:

```ts
{ type: "text",   text, fontSize, fontFamily, color, fontWeight, textAlign, … }
{ type: "image",  src, borderRadius, crop }
{ type: "rect",   fill, stroke }
{ type: "circle", radius, fill, stroke }
```

Every item carries position (`left`, `top` as percentages) and size (`width`, `height` as percentages). Rotation, opacity, and a designer-side flag set (`locked`, `hidden`, `_generated`) work on every type.

Coordinates are **percentages of the canvas**, not pixels. A text item at `left: 25, top: 40, width: 50` is centered horizontally and 40% from the top, regardless of whether the canvas is 1600×900 or 300×250. Combined with the [container-query interior sizing](./fluid-creatives.md) on the runtime banner, this is how a single creative renders the same composition at any actual pixel size.

## Animations

Each item can carry an `animationTo: MotionTarget`:

```ts
interface MotionTarget {
  left?, top?, rotation?, scale?, opacity?: number;
  duration?: number;
  delay?: number;
  easing?: string;  // "ease-out", "cubic-bezier(...)", etc.
}
```

The item starts at its base state (positioned per `left`/`top`, opacity per `opacity`, no rotation) and tweens to the `animationTo` target. Subsetting matters: only the fields present in `animationTo` animate. A common pattern is a fade-in entrance — base `opacity: 0`, animationTo `opacity: 1`.

Page-entrance choreography is the sum of every item's animation. The designer's `animation-panel.ts` exposes the per-item controls; preview plays the page through one cycle so the author can see the timing without reloading.

## Hand-authoring vs AI-authoring: the same schema

The [LP-to-creative pipeline](./lp-to-creative.md) emits `LayoutItem[]` arrays — the same schema the designer's hand-authoring writes. There's no separate "AI-generated layout" type. Generated items carry a designer-side `_generated: true` flag so the size-matrix can show "authored" vs "auto-layout" status pills, but any user edit on a generated item flips the whole size from generated to authored (and clears the flag).

Downstream, the runtime banner doesn't know or care which layouts came from a human and which from Gemini. The same `BannerConfig` flows into the same web component the same way.

## The contract with the runtime banner

The single most important file in the designer is `types.ts` — it re-exports the runtime banner's `BannerConfig`, `LayoutItem`, `Page`, `MotionTarget` types directly from `@promovolve/banner-component`:

```ts
export type {
  BannerConfig, Page, LayoutItem, TextItem, ImageItem, RectItem,
  CircleItem, MotionTarget, VideoBg, ExpandAnimation,
} from "@promovolve/banner-component";
```

There is no second copy of the types. If the runtime banner adds a field, the designer's TypeScript compiler sees it. If a designer surface needs a field the banner doesn't render, the type-check fails. WYSIWYG enforced by the type system.

`save.ts` assembles the current store state into a `BannerConfig` + `Pages[]`, builds a hidden form, and POSTs through `/advertiser/creatives/save` (Go dashboard) → `POST /v1/.../creatives` (Scala API). See [LP-to-Creative § Stage 4](./lp-to-creative.md#stage-4-save-designer--api).

## What the runtime banner does with it

The banner is `<expandable-magazine-banner>` — a Web Component, Shadow DOM, no framework dependencies. It reads `pages` and `config` attributes (JSON-encoded) and renders:

- A collapsed view from `pages[config.coverPageIdx]`, sized to the slot's aspect ratio.
- An expanded overlay built lazily on first tap, with all pages rendered in a swipeable carousel.
- The dog-ear corner (or not, depending on `data-can-fold`).
- The four lifecycle beacons (impression, click, CTA, fold).

Layout items render from the same coordinate system the designer wrote. Text uses container-query sizing (`cqh`/`cqmin`) so the same percentages produce proportionally-sized text at any container size. Images use `object-fit: cover` plus optional crops. Animations replay using the same `animationTo` payloads, transformed into CSS `@keyframes` at runtime.

The banner reading the designer's output should look identical to the designer's preview. When it doesn't, the bug is in one or the other — never in the wire format.

## Why no framework

The banner has to be lightweight (~14 KB gzip currently) because it's served from the Scala API origin on every first-time page view. Anything larger turns the publisher's slot into a load-time penalty.

The designer doesn't *need* a framework, but it could have one. The decision to skip React was driven by the same "no extra runtime dependency" rule applied to the dashboard as a whole — the dashboard is plain Go templates plus this designer bundle and a couple of small UI islands. A React-based designer would balloon the bundle and force the dashboard to ship a React runtime everywhere. Functional-immutable state + a tiny pub/sub store gives the designer everything it needs at a fraction of the size.

## Source of truth

- `platform/creative-designer/src/` — the designer
- `platform/creative-designer/src/modes.ts` — canvas mode catalog
- `platform/creative-designer/src/state.ts` — functional state updates
- `platform/creative-designer/src/render/canvas.ts` — primary render path
- `platform/creative-designer/src/ui/save.ts` — the save handoff
- `platform/banner-component/src/` — the runtime banner
- `platform/banner-component/src/types.ts` — the shared schema
- `platform/banner-component/src/banner.ts` — runtime render
- `platform/banner-component/README.md` — banner-side architecture and Playwright render flow
