#!/usr/bin/env python3
"""Compose the App Store "Apple Watch" screenshot (03-watch.png).

Places the pre-rendered framed Apple Watch Ultra (assets/watch-ultra-framed.png,
transparent) onto the family background with the caption. Repo-relative paths.

    python3 AppStore/make-watch-screenshot.py

Requires Pillow and macOS Helvetica Neue.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
WATCH = os.path.join(HERE, "assets", "watch-ultra-framed.png")
OUT = os.path.join(HERE, "screenshots", "03-watch.png")
W, H = 1290, 2796

canvas = Image.new("RGBA", (W, H), (10, 10, 12, 255))

# Warm amber glow behind the watch (matches the screenshot family)
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([W//2-540, 1520-450, W//2+540, 1520+450], fill=(255, 148, 0, 95))
canvas = Image.alpha_composite(canvas, glow.filter(ImageFilter.GaussianBlur(210)))

# Cool blue glow lower-right for balance
glow2 = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow2).ellipse([W-360, 1780, W+320, 2420], fill=(46, 133, 255, 60))
canvas = Image.alpha_composite(canvas, glow2.filter(ImageFilter.GaussianBlur(200)))

canvas = canvas.convert("RGB")
draw = ImageDraw.Draw(canvas)

FB = "/System/Library/Fonts/HelveticaNeue.ttc"
def font(sz, idx):
    try:
        return ImageFont.truetype(FB, sz, index=idx)
    except Exception:
        return ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", sz)

hf = font(78, 1)   # bold headline
sf = font(38, 0)   # regular subtitle

def ctext(y, txt, f, fill):
    draw.text((W//2, y), txt, font=f, fill=fill, anchor="mm")

ctext(178, "Your Apple Watch,", hf, (255, 255, 255))
ctext(272, "your coach.", hf, (255, 255, 255))
ctext(382, "Heart rate streams live from your wrist,", sf, (168, 168, 176))
ctext(432, "with real-time speed-up cues.", sf, (168, 168, 176))

w = Image.open(WATCH).convert("RGBA")
tw = 1040
th = int(w.height * tw / w.width)
w = w.resize((tw, th), Image.LANCZOS)
canvas.paste(w, ((W - tw) // 2, 1640 - th // 2), w)

canvas.save(OUT)
print("wrote", OUT)
