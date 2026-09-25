# App Store assets

Marketing screenshots for the App Store listing.

For releasing an uploaded Xcode Cloud build, see [App Store submissions](SUBMISSIONS.md).

## `screenshots/` — final, upload-ready

Two sizes are provided; upload the set that matches the App Store Connect slot:

- `screenshots/*.png` — **1290 × 2796** (6.9" iPhone: 16 Pro Max etc.)
- `screenshots/6.7in/*.png` — **1284 × 2778** (6.7"/6.5" slot: 15/14 Pro Max,
  11 Pro Max). Use these if ASC rejects 1290×2796 with a dimension error.

The 6.7" set is a straight resize of the 6.9" set (same composition).

**Alpha-channel caveat:** Apple's spec forbids alpha channels in screenshots,
and the composed cards `01/02/04` currently carry one (both sizes; the Chrome-
rendered cards and all watch shots are clean). These renders haven't been
through an upload yet — if ASC rejects with a transparency error, flatten with
`magick in.png -alpha off out.png` (or Pillow `convert("RGB")`).

| File | Caption |
|------|---------|
| `01-home.png` | Built for your VO₂ max |
| `02-zones.png` | Always in the right zone |
| `03-watch.png` | Your Apple Watch, your coach |
| `04-history.png` | Watch your fitness climb |
| `05-summary.png` | Every interval, charted |
| `06-heart-rate.png` | Any heart rate monitor |

`01`, `02`, `04` are composed from live app captures. `03` features an **Apple
Watch Ultra** rather than a phone (see below). `05` is rendered from
`make-summary-screenshot.html` (headless Chrome, see below) — a hand-built
mockup of the real `PostWorkoutSummaryRedesignView`; keep the two visually
identical when either changes, same rule as the watch face. `06` is rendered
from `make-hr-sources-screenshot.html` (same Chrome invocation, output
`06-heart-rate.png`) — Apple Watch (our own framed asset with the live face),
AirPods Pro 3, and a Garmin Forerunner 965 on the family background.

## Phone frame (v4.7)

Every phone card wears an **iPhone 16 Pro-style frame**: titanium rim
(vertical gradient), black bezel, Dynamic Island, side buttons. The old thin
white outline read as a generic Android. The frame lives in CSS in
`make-summary-screenshot.html` (bottom-cropped variant); the composed cards
`01/02/04` get the full-body variant painted on by `make-iphone-frame.py`
(Pillow) — run it after refreshing any of those captures; it also writes the
6.7" resizes. Keep the two geometries visually identical.

## Device-image provenance (`assets/`, added for `06`)

- `airpods-pro-3.png` — Apple's own store product image
  (`store.storeimages.cdn-apple.com` … `airpods-pro-3-hero-select-202509`,
  `fmt=png-alpha`), trimmed. Showing Apple products to indicate compatibility
  is standard App Store practice.
- `garmin-forerunner-965.png` — Garmin's product image
  (`res.garmin.com/en/products/010-02809-10/v/cf-xl.png`), white background
  keyed to alpha. Third-party product depiction for compatibility claims —
  if Garmin ever objects, swap for a generic strap render.
- `watch-ultra-framed.png` — ours (see frame provenance below); its composited
  screen corners were rounded in 4.7 to follow the case curve.

## `watch-screenshots/` — Apple Watch slots (required)

Because the binary includes a watchOS app, App Store Connect requires at least
one Apple Watch screenshot. **Apple's watch slots take the raw screen only —
no device frame and no caption/marketing text** (that lives on the phone card
`03-watch.png` instead). Since 5.0 these are real Simulator captures of the
shipped UI, not HTML mockups, so the listing can't drift from the app.

One numbered set per slot; upload the **`ultra-410x502/`** set (per Apple's
specifications, checked 2026-07-22, 410×502 is the accepted size for Ultra
1/2/3 — the Ultra 3's physical 422×514 is not an upload size). The other
folders exist for the optional per-size slots.

| Folder | Size | ASC slot |
|--------|------|----------|
| `ultra-410x502/` | 410×502 | Ultra / Ultra 2 / Ultra 3 — **upload this one** |
| `series11-416x496/` | 416×496 | Series 10 / 11 |
| `45mm-396x484/` | 396×484 | Series 7–9 |
| `44mm-368x448/` | 368×448 | Series 4–6 / SE |

| File | Shows |
|------|-------|
| `01-workout.png` | Work interval: countdown ring, in-zone HR, IN ZONE cue (Watch-led) |
| `02-home.png` | Home: streak, START ring, plan bar, "No iPhone · runs on Watch" |
| `03-controls.png` | Controls page: timeline, PAUSE / SKIP / END |
| `04-complete.png` | Watch-led completion with sync status |

Regenerate: capture each demo state on the Ultra 3, Series 11 46 mm and SE
44 mm simulators, then fit them to the slots (letterboxed on black where the
aspect differs by a hair; alpha stripped):

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
BID=Jan-van-Rensburg.N4x4.watchkitapp
# for each <device>:<udid> in ultra3 / s11-46 / se-44, and each state in
# local controls offline localComplete:
xcrun simctl launch <udid> $BID -demoState <state>; sleep 4
xcrun simctl io <udid> screenshot AppStore/raw-watch/<device>-<state>.png
python3 AppStore/make-watch-store-set.py        # reads AppStore/raw-watch/ by default
```

The simulator clock shows the real time; Apple does not require 9:41 on
watch screenshots.

## Regenerating the framed watch (`assets/watch-ultra-framed.png`)

```
python3 AppStore/make-framed-watch.py AppStore/raw-watch/ultra3-local.png   # real capture (5.0+)
python3 AppStore/make-framed-watch.py                        # legacy: HTML face
```

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

## Regenerating `03-watch.png`

```
python3 AppStore/make-framed-watch.py AppStore/raw-watch/ultra3-local.png   # only if the face changed
python3 AppStore/make-watch-screenshot.py
sips -z 2778 1284 AppStore/screenshots/03-watch.png \
  --out AppStore/screenshots/6.7in/03-watch.png
```

`make-watch-screenshot.py` composites `assets/watch-ultra-framed.png` onto the
family background (near-black `#0A0A0C` + amber/blue glow) with the caption.
`make-framed-watch.py` rebuilds that asset: it flood-fills the transparent
screen opening of `../website/images/watch-ultra-frame.png` to get an exact
mask, renders `make-watch-face.html` (the button-less face) at 2× (see the
headless-Chrome clamp note above), clips the face to the mask, and composites
the frame on top — so the face can never poke past the bezel and needs no
hand-measured cutout percentages. The face must match `make-watch-screen.html`.
`06-heart-rate.png` embeds the same framed asset, so re-render it too after a
face change.

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
