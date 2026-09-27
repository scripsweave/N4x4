#!/usr/bin/env python3
"""Replace a marketing card's phone screen with a real Simulator capture.

Usage: python3 AppStore/make-phone-capture.py 02-zones.png path/to/capture.png
Keeps the existing headline and frame, refreshes the 6.7-inch size, and strips
alpha. Requires Pillow. The phone frame geometry comes from make-iphone-frame.
"""
import importlib.util
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('phone_frame', HERE / 'make-iphone-frame.py')
frame = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frame)

name, source = sys.argv[1:]
if name not in frame.DEFAULTS:
    sys.exit('Choose 01-home.png, 02-zones.png or 04-history.png')
path = HERE / 'screenshots' / name
card = Image.open(path).convert('RGB')
x0, y0, x1, y1 = frame.WINDOW
size = (x1 - x0, y1 - y0)
screen = ImageOps.fit(Image.open(source).convert('RGB'), size, method=Image.Resampling.LANCZOS)
mask = Image.new('L', size)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0]-1, size[1]-1), radius=frame.R_WINDOW, fill=255)
card.paste(screen, (x0, y0), mask)
# Simulator screenshots omit the physical camera cutout; restore the frame's island.
island = (int(card.width / 2 - 156), y0 + 30, int(card.width / 2 + 156), y0 + 110)
ImageDraw.Draw(card).rounded_rectangle(island, radius=40, fill='black')
card.save(path)
card.resize((1284, 2778), Image.Resampling.LANCZOS).save(path.parent / '6.7in' / name)
print(f'{name}: refreshed from {source}')
