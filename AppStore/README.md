# App Store assets

Marketing screenshots for the App Store listing.

## `screenshots/` — final, upload-ready

Two sizes are provided; upload the set that matches the App Store Connect slot:

- `screenshots/*.png` — **1290 × 2796** (6.9" iPhone: 16 Pro Max etc.)
- `screenshots/6.7in/*.png` — **1284 × 2778** (6.7"/6.5" slot: 15/14 Pro Max,
  11 Pro Max). Use these if ASC rejects 1290×2796 with a dimension error.

The 6.7" set is a straight resize of the 6.9" set (same composition).

| File | Caption |
|------|---------|
| `01-home.png` | Built for your VO₂ max |
| `02-zones.png` | Always in the right zone |
| `03-watch.png` | Your Apple Watch, your coach |
| `04-history.png` | Watch your fitness climb |
| `05-summary.png` | Every interval, charted |

`01`, `02`, `04` are composed from live app captures. `03` features an **Apple
Watch Ultra** rather than a phone (see below). `05` is rendered from
`make-summary-screenshot.html` (headless Chrome, see below) — a hand-built
mockup of the real `PostWorkoutSummaryRedesignView`; keep the two visually
identical when either changes, same rule as the watch face.

## `watch-screenshots/` — Apple Watch slot (required)

Because the binary includes a watchOS app, App Store Connect requires at least
one Apple Watch screenshot. These are the raw watch screen (no device frame),
rendered to match the real `WatchTimerView` UI. Upload one that matches an
accepted size — **`watch-ultra3-422x514.png`** or `watch-ultra-410x502.png` are
the safe defaults.

| File | Size | Device |
|------|------|--------|
| `watch-ultra3-422x514.png` | 422×514 | Ultra 3 |
| `watch-ultra-410x502.png` | 410×502 | Ultra / Ultra 2 |
| `watch-series11-416x496.png` | 416×496 | Series 11 (46mm) |
| `watch-45mm-396x484.png` | 396×484 | Series 9 (45mm) |
| `watch-44mm-368x448.png` | 368×448 | Series 6 (44mm) |

## `assets/` — reusable source

- `watch-ultra-framed.png` (1800 × 2580, transparent) — the Apple Watch Ultra
  with the live N4x4 face composited into its screen. Reused to compose
  `03-watch.png`.

## Apple Watch frame provenance

The Ultra frame originated from a supplied render that was a flattened preview
(no real alpha). It was keyed into a transparent-screen PNG that lives at
`website/images/watch-ultra-frame.png` and is used on the website too. The
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

## Regenerating `05-summary.png`

```
cd AppStore
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --screenshot=screenshots/05-summary.png \
  --window-size=1290,2796 --hide-scrollbars --force-device-scale-factor=1 \
  "file://$(pwd)/make-summary-screenshot.html"
sips -z 2778 1284 screenshots/05-summary.png --out screenshots/6.7in/05-summary.png
```

The session/interval charts, stats, and palette hexes live in that HTML file.
If `PostWorkoutSummaryRedesignView` (SessionDetailViews.swift) is restyled,
restyle the mockup in the same change.
