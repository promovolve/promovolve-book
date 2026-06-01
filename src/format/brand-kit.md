# Brand Kit: Matching the Landing Page

A Promovolve creative should look like it came *from* the landing page it
advertises — same background, same text colour, same accent, same typeface. The
**brand kit** is how that identity travels from the LP into the creative. The
[LP-to-Creative pipeline](./lp-to-creative.md) extracts the LP's visual
identity; this page is about how that identity is captured as a kit and applied
to the [designer's](./designer.md) layout.

The kit is a small, named structure (`platform/creative-designer/src/brand-kit.ts`):

```ts
interface BrandKit {
  name: string;                    // "From landing page"
  colors: { name: string; value: string }[];  // Background / Text / Accent / Brand (hex)
  fonts: string[];                 // [heading, body] e.g. "Montserrat Variable, sans-serif"
}
```

Two things ride it — **colours** and **fonts** — and they share the same front
half (analyse → seed kit → hand off → apply) but diverge at persistence:
**colours are values baked into `pages_json`**, while **fonts are artifacts
self-hosted in R2**.

## Colours

Extraction reads the LP's dominant colour, text colour, and palette; the editor
names them by role (`buildBrandKitFromLP`); the designer applies them to the
layout via `resolveLayoutColors`, **contrast-guarded** so a poorly-extracted
pairing can never ship illegible text.

```mermaid
sequenceDiagram
    actor Adv as Advertiser (browser)
    participant Ed as Editor<br/>(creative-editor.html)
    participant API as API<br/>(analyze-lp)
    participant Cr as Crawler<br/>(LPAnalyzer + lp-analyzer.js)
    participant Dz as Designer<br/>(creative-designer)
    participant DB as creative.pages_json
    participant Bn as Banner (viewer)

    Note over Adv,Cr: 1. Analyze the landing page
    Adv->>Ed: enter LP URL, "Analyze"
    Ed->>API: POST /v1/creatives/analyze-lp {url}
    API->>Cr: analyze LP
    Cr->>Cr: Playwright render →<br/>extractPalette(), dominant bg,<br/>text color (+ extractFonts)
    Cr-->>API: LPAnalysisResult{dominantColor,<br/>textColor, palette, fonts}
    API-->>Ed: {dominantColor, textColor, palette, fonts}

    Note over Ed: 2. Seed the brand kit (buildBrandKitFromLP)
    Ed->>Ed: _toHex → brandKitColors<br/>[Background=dominant, Text=textColor,<br/>Accent=palette0, Brand=palette1]

    Note over Adv,Dz: 3. Hand off to the designer
    Adv->>Ed: "Design"
    Ed->>Dz: window.__DESIGNER__.brandKitJson
    Dz->>Dz: loadBrandKit → kit

    Note over Dz: 4. Apply to the layout (resolveLayoutColors)
    Dz->>Dz: bg ← kit Background
    alt contrastRatio(Text, bg) ≥ WCAG AA (4.5)
        Dz->>Dz: text ← kit Text  (LP colour)
    else illegible pairing
        Dz->>Dz: text ← pickContrast(bg)  (legible fallback)
    end
    Dz->>Dz: accent ← kit Accent
    Dz->>Dz: defaultLayoutForPage / presets →<br/>items{color}; page.bg = Background
    Dz->>DB: save creative (pages_json)

    Note over Bn: 5. Serve & render
    Bn->>DB: fetch served creative
    Bn->>Bn: render items with color (directly from pages_json)
```

The `alt` fragment is the only subtlety: the LP's own text/background pairing is
legible by construction, but if extraction pairs poorly, the WCAG-AA guard
substitutes a readable colour rather than shipping invisible text. With no kit,
this is exactly the pre-kit behaviour — `pickContrast(page.bg)` + `page.accent`.

## Fonts

The font path shares steps 1–3, then adds two things colours don't need:
**publish-time self-hosting to R2** (Promovolve never calls Google at the
viewer's runtime) and a **FontFace registration** in the banner. CJK faces
(Noto Sans/Serif JP) take a per-creative `text=` subset; see the `alt` branch.

```mermaid
sequenceDiagram
    actor Adv as Advertiser (browser)
    participant Ed as Editor<br/>(creative-editor.html)
    participant Cr as Crawler<br/>(lp-analyzer.js extractFonts)
    participant API as API<br/>(CreativeProcessor / FontProvisioner)
    participant Dz as Designer<br/>(creative-designer)
    participant GF as Google Fonts (css2)
    participant R2 as R2 / CDN
    participant DB as creative.pages_json
    participant Bn as Banner (viewer)

    Note over Adv,Cr: 1. Extract faces from the LP
    Adv->>Ed: "Analyze"
    Ed->>API: POST /v1/creatives/analyze-lp {url}
    API->>Cr: analyze
    Cr->>Cr: getComputedStyle(h1/h2/p/body) →<br/>fold weight into name<br/>("Montserrat"@100 → "Montserrat Thin";<br/>"Noto Sans JP")
    Cr-->>API: fonts[]
    API-->>Ed: {fonts, …}

    Note over Ed: 2. Snap into the kit (_snapFont)
    Ed->>Ed: _systemBucket (Mincho→serif, Gothic→sans);<br/>allow-listed (incl. Noto JP)? →<br/>"Family, bucket" else just bucket<br/>→ brandKitFonts[0]=head, [1]=body
    Adv->>Ed: "Design"
    Ed->>Dz: window.__DESIGNER__.brandKitJson

    Note over Dz: 3. Apply to layout
    Dz->>Dz: loadBrandKit → kit;<br/>kitFont(kit,0/1) → item.fontFamily<br/>(collapsed layout + expanded masters)
    Dz->>DB: save creative (pages_json)

    Note over API,R2: 4. Provision at publish (self-host, once)
    API->>API: provisionFonts(pagesJson):<br/>fontsFromPagesJson → (family,weight);<br/>subsetTextFromPagesJson → text
    loop each (family, weight)
        API->>API: resolve → slug, weight, isCjk?
        alt already in R2 (fontExists slug+variant)
            API->>API: skip (dedup)
        else CJK (Noto JP)
            API->>API: variant = subsetKey(text)
            API->>GF: css2 family:wght@N & text=<chars>
            GF-->>API: subset woff2 (just those glyphs)
            API->>R2: store fonts/<slug>-<w>-<subsetKey>.woff2
        else latin
            API->>GF: css2 family:wght@N  (/* latin */ block)
            GF-->>API: latin woff2
            API->>R2: store fonts/<slug>-<w>-latin.woff2
        end
    end

    Note over Bn,R2: 5. Serve & render (no Google at runtime)
    Bn->>DB: fetch served creative (pages_json)
    Bn->>Bn: collectExpandedFonts(pages, origin):<br/>family → CATALOG slug;<br/>CJK → variant = subsetKey(collectSubsetText(pages))<br/>else latin → URL = origin/fonts/<slug>-<w>-<variant>.woff2
    Bn->>R2: GET the woff2
    R2-->>Bn: woff2 (immutable, long-cache)
    Bn->>Bn: new FontFace(family, url) → document.fonts.add<br/>(idle preload); render font-family:<stack>
    Note over Bn: 404 / not-allow-listed →<br/>system family after the comma (Mincho/serif/sans)
```

## Invariants worth remembering

- **The `subsetKey` contract.** For CJK, the woff2 filename depends on the
  creative's text, so the key is derived **twice** — by the API to name the
  stored file, and by the banner to build the URL — from the *same* FNV-1a over
  the LP text (`GoogleFontCatalog.subsetKey` ≡ `font-catalog.subsetKey`).
  `FontProvisionSpec` and `font-catalog.test.ts` assert identical fixtures so
  the two can't drift.
- **`text=` is CJK-only.** Latin fetches the `/* latin */` block once and dedups
  by `slug+weight` across every creative; CJK is a per-creative subset, so its
  key includes the content hash.
- **Privacy.** Google Fonts is contacted only at **publish** (server-side, step
  4), never at the **viewer's runtime** (step 5 reads only from R2/CDN).
- **Graceful fallback.** Any miss — non-allow-listed family, a licensed face, or
  a `subsetKey` mismatch — simply 404s and the CSS stack's system family takes
  over (`_systemBucket`: Mincho→serif, Gothic→sans, else sans/Georgia). Nothing
  ever renders invisibly.
- **Same scope as today's auto-layout.** Kit colours and fonts apply to the
  synthesized collapsed layout and the expanded masters; explicit IAB-size
  presets keep the system fallback. With no kit, behaviour is unchanged.

## Source of truth

- Kit + helpers: `platform/creative-designer/src/brand-kit.ts`
  (`kitFont`, `kitColor`), `color-contrast.ts` (`resolveLayoutColors`).
- Extraction: `modules/crawler/.../lp-analyzer.js`, `LPAnalyzer.scala`.
- Editor seeding: `platform/templates/advertiser/creative-editor.html`
  (`buildBrandKitFromLP`, `_snapFont`, `_systemBucket`).
- Self-hosting: `GoogleFontCatalog.scala`, `GoogleFontProvisioner.scala`,
  `CreativeProcessor.scala`; banner `font-catalog.ts`, `banner.ts`.
