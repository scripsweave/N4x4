#!/usr/bin/env python3
"""Redraw the phone frame on composed App Store screenshots (01, 02, 04).

The originals used a thin white outline with a modest corner radius — it read
as a generic Android. This paints an iPhone 16 Pro-style frame over it:
titanium rim (vertical gradient), black bezel, side buttons. Geometry matches
the CSS frame in make-summary-screenshot.html / make-hr-sources-screenshot.html
exactly, so every phone card in the set shares one silhouette.

The new frame is wider than the old outline in every direction, so the old
frame is fully covered; running the script twice is a no-op visually.

Usage:  python3 make-iphone-frame.py [file ...]
        (defaults to screenshots/01-home.png 02-zones.png 04-history.png,
         and refreshes the 6.7in resizes)
Requires Pillow.
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).parent
DEFAULTS = ["01-home.png", "02-zones.png", "04-history.png"]

# Frame geometry at 1290×2796. The legacy composed cards (01/02/04) all drew
# their old thin outline on the box (143, 600)–(1147, 2782); the new frame is
# sized so its bezel fully covers that line on every edge. These cards show
# the ENTIRE phone (unlike the bottom-cropped HTML cards), so all four corners
# are rounded. Rim/bezel proportions match the HTML generators.
OUTER = (105, 562, 1185, 2795)    # titanium rim outer edge
BEZEL = (115, 572, 1175, 2785)    # rim inset 10
WINDOW = (148, 605, 1142, 2742)   # screen window (old content shows through)
R_OUTER, R_BEZEL, R_WINDOW = 182, 172, 140
RIM_TOP, RIM_MID, RIM_BOT = (0x5B, 0x5C, 0x62), (0x37, 0x38, 0x3D), (0x1D, 0x1E, 0x22)
BUTTONS = [  # (side, top, height) — offsets from the rim's top edge
    ("left", 380, 92), ("left", 545, 152), ("left", 730, 152), ("right", 590, 250),
]


def rounded_mask(size, box, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def vertical_gradient(size, y0, y1, stops):
    """Gradient image over [y0, y1] through the given color stops."""
    img = Image.new("RGBA", size)
    px = img.load()
    n = len(stops) - 1
    for y in range(size[1]):
        t = min(1.0, max(0.0, (y - y0) / max(1, (y1 - y0))))
        seg = min(n - 1, int(t * n))
        f = t * n - seg
        c = tuple(round(stops[seg][i] + (stops[seg + 1][i] - stops[seg][i]) * f) for i in range(3))
        for x in range(size[0]):
            px[x, y] = c + (255,)
    return img


OLD_BOX, OLD_R = (143, 600, 1147, 2782), 150   # legacy thin-outline frame


def frame(path: Path):
    im = Image.open(path).convert("RGBA")
    size = im.size
    x0, y0, x1, y1 = OUTER

    draw = ImageDraw.Draw(im)

    # Erase the legacy outline first — its corner radius differs from the new
    # frame's, so covering by overlap alone leaves crescents at the corners.
    draw.rounded_rectangle((OLD_BOX[0] - 3, OLD_BOX[1] - 3, OLD_BOX[2] + 3, OLD_BOX[3] + 3),
                           radius=OLD_R + 3, outline=(10, 10, 12, 255), width=16)
    # The old bottom corners used a different (larger) curve than OLD_R; the
    # region below the tab bar is empty card background, so blank it outright.
    draw.rectangle((96, 2725, 340, size[1]), fill=(10, 10, 12, 255))
    draw.rectangle((950, 2725, 1194, size[1]), fill=(10, 10, 12, 255))

    # Side buttons (under the rim, sticking out past its edge).
    for side, top, height in BUTTONS:
        bx = (x0 - 9, x0 + 2) if side == "left" else (x1 - 2, x1 + 9)
        draw.rounded_rectangle((bx[0], y0 + top, bx[1], y0 + top + height),
                               radius=5, fill=(0x3C, 0x3D, 0x42, 255))

    # Titanium rim: gradient masked to the ring between outer edge and bezel.
    ring = rounded_mask(size, OUTER, R_OUTER)
    inner = rounded_mask(size, BEZEL, R_BEZEL)
    ring.paste(0, mask=inner)
    grad = vertical_gradient(size, y0, y1, [RIM_TOP, RIM_MID, RIM_MID, RIM_BOT])
    im.paste(grad, mask=ring)

    # Black bezel: band between the rim's inner edge and the screen window.
    bezel = rounded_mask(size, BEZEL, R_BEZEL)
    screen = rounded_mask(size, WINDOW, R_WINDOW)
    bezel.paste(0, mask=screen)
    im.paste((0, 0, 0, 255), mask=bezel)

    im.save(path)
    small = im.resize((1284, 2778), Image.LANCZOS)
    small.save(path.parent / "6.7in" / path.name)
    print(f"framed {path.name} (+6.7in)")


if __name__ == "__main__":
    names = sys.argv[1:] or DEFAULTS
    for name in names:
        frame(HERE / "screenshots" / name)
