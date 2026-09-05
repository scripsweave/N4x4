#!/usr/bin/env python3
"""Build the App Store *Apple Watch* screenshot set from real Simulator captures.

Apple's watch slots take the raw screen only — no device frame, no caption
text — so this script does exactly three things: fits each capture to the
accepted slot size (letterboxing on black where the aspect differs by a hair),
strips the alpha channel, and writes one numbered set per slot.

    python3 AppStore/make-watch-store-set.py <raw-dir>

<raw-dir> holds `<device>-<state>.png` captures from `simctl io screenshot`
with the app launched via `-demoState <state>` (see AGENTS.md):
  ultra3-*.png  422×514  (Apple Watch Ultra 3 simulator)  → 410×502 slot
  s11-46-*.png  416×496  (Series 11 46 mm)                → 416×496 and 396×484 slots
  se-44-*.png   368×448  (SE 44 mm)                       → 368×448 slot

Requires Pillow.
"""
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "watch-screenshots")
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "raw-watch")

# Upload order: the workout face first (it's what the listing leads with).
SHOTS = [("01-workout", "local"), ("02-home", "offline"),
         ("03-controls", "controls"), ("04-complete", "localComplete")]

# slot folder → (source device prefix, target size)
SLOTS = {
    "ultra-410x502":    ("ultra3", (410, 502)),   # Ultra / Ultra 2 / Ultra 3 — the required upload
    "series11-416x496": ("s11-46", (416, 496)),   # Series 10 / 11
    "45mm-396x484":     ("s11-46", (396, 484)),   # Series 7–9
    "44mm-368x448":     ("se-44",  (368, 448)),   # Series 4–6 / SE
}

def fit_on_black(img, size):
    """Scale to fit inside `size`, centre on pure black, no alpha."""
    tw, th = size
    img = img.convert("RGB")
    scale = min(tw / img.width, th / img.height)
    w, h = round(img.width * scale), round(img.height * scale)
    img = img.resize((w, h), Image.LANCZOS)
    canvas = Image.new("RGB", (tw, th), (0, 0, 0))
    canvas.paste(img, ((tw - w) // 2, (th - h) // 2))
    return canvas

for folder, (device, size) in SLOTS.items():
    dest = os.path.join(OUT, folder)
    os.makedirs(dest, exist_ok=True)
    for name, state in SHOTS:
        src = os.path.join(RAW, f"{device}-{state}.png")
        if not os.path.exists(src):
            sys.exit(f"missing capture {src}")
        out = fit_on_black(Image.open(src), size)
        path = os.path.join(dest, f"{name}.png")
        out.save(path, optimize=True)
        print(f"{path}  {out.size[0]}x{out.size[1]}  mode={out.mode}")
