#!/usr/bin/env python3
"""Rebuild AppStore/assets/watch-ultra-framed.png.

Fixes two defects in the previous build:
- the face was pasted OVER the frame with near-square corners, leaving black
  corners visible outside the bezel/case curve;
- placement came from hand-measured percentages instead of the frame's actual
  screen opening.

Approach: flood-fill the transparent screen opening of the frame to get an
exact mask, clip the freshly rendered face to that mask, then composite the
frame on top.
"""
import os, subprocess, sys, tempfile
from collections import deque
from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
FRAME = os.path.join(HERE, "..", "website", "images", "watch-ultra-frame.png")
OUT = os.path.join(HERE, "assets", "watch-ultra-framed.png")
FACE_HTML = os.path.join(HERE, "make-watch-face.html")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SCRATCH = tempfile.mkdtemp()
TW, TH = 1800, 2561  # keep the existing asset dimensions (drop-in)

frame = Image.open(FRAME).convert("RGBA")
fw, fh = frame.size
alpha = frame.getchannel("A").load()

# Flood fill the screen opening from its center (alpha<128 = transparent-ish)
mask = Image.new("L", (fw, fh), 0)
mpx = mask.load()
seed = (fw * 47 // 100, fh // 2)  # screen sits slightly left of center (crown side right)
if alpha[seed] >= 128:
    sys.exit(f"seed {seed} not transparent, alpha={alpha[seed]}")
q = deque([seed])
mpx[seed] = 255
count = 0
while q:
    x, y = q.popleft()
    count += 1
    for nx, ny in ((x+1,y),(x-1,y),(x,y+1),(x,y-1)):
        if 0 <= nx < fw and 0 <= ny < fh and mpx[nx, ny] == 0 and alpha[nx, ny] < 128:
            mpx[nx, ny] = 255
            q.append((nx, ny))
bbox = mask.getbbox()
print(f"opening: {count} px, bbox {bbox}")
# Sanity: the opening must not leak to the (also transparent) outer background
if bbox[0] == 0 or bbox[1] == 0 or bbox[2] == fw or bbox[3] == fh:
    sys.exit("flood fill leaked to image edge - opening not sealed by bezel")

# Upscale frame and mask together
frame_big = frame.resize((TW, TH), Image.LANCZOS)
mask_big = mask.resize((TW, TH), Image.LANCZOS)
bb = mask_big.getbbox()
bx, by, bx2, by2 = bb
bw, bh = bx2 - bx, by2 - by
print(f"opening at {TW}x{TH}: x {bx}-{bx2}, y {by}-{by2} ({bw}x{bh})")

# Render the face at 2x the opening size (scale factor 2 keeps the window above
# headless Chrome's ~500px minimum, so vw units resolve correctly), then downsample.
face_png = os.path.join(SCRATCH, "face-render.png")
subprocess.run([
    CHROME, "--headless=new", f"--screenshot={face_png}",
    f"--window-size={bw*2},{bh*2}", "--hide-scrollbars",
    "--force-device-scale-factor=2", f"file://{FACE_HTML}",
], check=True, capture_output=True)
face = Image.open(face_png).convert("RGBA").resize((bw, bh), Image.LANCZOS)

# Face layer clipped to the exact opening, frame composited on top
layer = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
layer.paste(face, (bx, by))
layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask_big))
out = Image.alpha_composite(layer, frame_big)
out.save(OUT)
print("wrote", OUT, out.size)
