# App Store assets

Marketing screenshots for the App Store listing.

## `screenshots/` — final, upload-ready

All exactly **1290 × 2796** (6.9" iPhone — the required size; also accepted for
the 6.5"/6.7" slots).

| File | Caption |
|------|---------|
| `01-home.png` | Built for your VO₂ max |
| `02-zones.png` | Always in the right zone |
| `03-watch.png` | Your Apple Watch, your coach |
| `04-history.png` | Watch your fitness climb |

`01`, `02`, `04` are composed from live app captures. `03` features an **Apple
Watch Ultra** rather than a phone (see below).

## `assets/` — reusable source

- `watch-ultra-framed.png` (1800 × 2580, transparent) — the Apple Watch Ultra
  with the live N4x4 face composited into its screen. Reused to compose
  `03-watch.png`.

## Apple Watch frame provenance

The Ultra frame originated from a supplied render that was a flattened preview
(no real alpha). It was keyed into a transparent-screen PNG that lives at
`website-v2/images/watch-ultra-frame.png` and is used on the website too. The
live face is the same one rendered on the site, so **the advertised watch and
the real app UI match** — keep them in sync (see
`docs/SESSION-HANDOFF-2026-07-09.md`).

Screen cutout in that frame: left 12.1 %, top 21.7 %, width 70.0 %, height 59.3 %.

## Regenerating `03-watch.png`

```
python3 AppStore/make-watch-screenshot.py
```

It composites `assets/watch-ultra-framed.png` onto the family background
(near-black `#0A0A0C` + amber/blue glow) with the caption, and writes
`screenshots/03-watch.png`. To change the watch face itself, re-render
`assets/watch-ultra-framed.png` from the site's frame + face (headless Chrome,
transparent background) — see the handoff doc.

Requires Pillow (`pip install pillow`) and macOS Helvetica Neue.
