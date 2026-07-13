# From Landing Page to Creative

Most small advertisers have exactly one designed artifact: their landing
page. Promovolve treats it as the source of truth for the ad — the campaign
input is a URL, not a zip of banner assets.

## The pipeline

1. **Extraction.** A Playwright browser (the `LPWorker` pool, running on
   cluster nodes with the `crawler` role) loads the landing page and
   extracts its raw material: headline candidates, body copy, images, and a
   *brand kit* — dominant background color, text color, and a palette of up
   to six swatches ordered by how much painted area each covers. The brand
   kit is measured from the rendered DOM, not guessed by a model, so the ad
   inherits the landing page's actual look.

2. **Rewriting.** An LLM turns the extracted copy into the three-page
   magazine narrative — cover hook, story, call to action — under hard
   constraints: claims must be grounded in the landing page's own text, and
   verbatim-sensitive details (prices, phone numbers) are carried through
   unchanged rather than paraphrased.

3. **Rendering and verification.** The creative is rendered headlessly,
   uploaded to object storage (Cloudflare R2, served through the CDN), and
   then *verified* by a vision model: does the rendered result actually look
   like a coherent ad — text legible, image sensible, nothing overflowing?
   Failures go back around the loop instead of into the auction.

## Color is code, not model output

Text colors are never chosen by the LLM. A deterministic pipeline picks
them: luminance decides a dark-on-light or light-on-dark palette, every
combination is checked against the WCAG AA contrast ratio (4.5:1), and any
brand-kit color that fails contrast is replaced by a compliant fallback.
The prompt hard-codes the allowed hex values so the model cannot invent an
unreadable one. If a creative looks wrong, the bug is in the contrast
pipeline — a place you can set a breakpoint — not in a model's mood.

## The designer

Advertisers can hand-tune the generated creative in an in-browser designer.
Its editing model took several iterations to get honest, and the invariants
are worth stating because they define what a "creative" *is*:

- **One image per page, defined by the expanded view.** The image shown on
  page one of the full-screen spread *is* the page's image everywhere — the
  folded cover and every slot size derive from it. There is no per-size
  image pinning; replacing the image in the expanded view replaces it
  everywhere, always.
- **Text and color sync across sizes by default.** Each text field carries a
  per-size "synced across all sizes" setting. Unsynced, edits stay local to
  that slot size; re-ticking sync adopts the current text as the shared
  value. Headline, body, and page-background colors additionally sync
  across the three pages, each with its own toggle (page background defaults
  to synced).
- **Deletion is one-sourced.** Deleting a field from the expanded view
  removes it from every size that carries it — and the confirmation dialog
  counts exactly which sizes those are, rather than claiming "everywhere."

The folded and expanded views are two projections of one layout document, so
nothing the advertiser does can make the cover advertise a different product
than the magazine inside it.
