#!/usr/bin/env python3 -I
"""Wrap raw simulator screenshots in App Store marketing frames: a gradient, a headline and a
subtitle, with the screenshot in a rounded card that runs off the bottom edge.

    python3 -I tools/store-frames.py <raw-dir> <out-dir> iphone|ipad

<raw-dir> holds now.png, plan.png, log.png and stock.png (see tools/shot.sh). Needs Pillow.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

raw, out, kind = sys.argv[1:4]
SLIDES = {
    "now":   ("Never miss a dose.",     "Your schedule, front and centre. One tap logs it.", ((0, 150, 136), (46, 196, 160))),
    "plan":  ("Set up in seconds.",     "Pick a compound, set the schedule, and reminders follow.", ((14, 98, 130), (60, 170, 200))),
    "log":   ("Every dose on record.",  "The vial, the site and a note, by list or by month.", ((70, 60, 150), (0, 166, 150))),
    "stock": ("Know what is left.",     "Vials, water and when you will run out.", ((0, 110, 112), (30, 160, 120))),
}
LAYOUT = {  # canvas, headline px, subtitle px, headline y, card width, card top, corner radius
    "iphone": ((1320, 2868), 108, 46, 220, 1060, 640, 96),
    "ipad":   ((2752, 2064), 150, 62, 150, 2160, 470, 80),
}
canvas, hpx, spx, hy, cw, ctop, rad = LAYOUT[kind]
W, H = canvas

def font(px, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", px)
    f.set_variation_by_name(weight)
    return f

def gradient(c1, c2):
    n = int(max(W, H) * 1.6)
    mask = Image.linear_gradient("L").resize((n, n)).rotate(-35, resample=Image.BICUBIC)
    mask = mask.crop(((n - W) // 2, (n - H) // 2, (n - W) // 2 + W, (n - H) // 2 + H))
    return Image.composite(Image.new("RGB", (W, H), c2), Image.new("RGB", (W, H), c1), mask)

def centred(draw, text, y, f, fill):
    w = draw.textlength(text, font=f)
    draw.text(((W - w) / 2, y), text, font=f, fill=fill)

for name, (head, sub, (c1, c2)) in SLIDES.items():
    bg = gradient(c1, c2).convert("RGBA")
    d = ImageDraw.Draw(bg)
    centred(d, head, hy, font(hpx, "Bold"), (255, 255, 255, 255))
    centred(d, sub, hy + hpx * 1.25, font(spx, "Regular"), (255, 255, 255, 215))

    shot = Image.open(f"{raw}/{name}.png").convert("RGBA")
    ch = int(shot.height * cw / shot.width)
    shot = shot.resize((cw, ch), Image.LANCZOS)
    mask = Image.new("L", (cw * 2, ch * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, cw * 2 - 1, ch * 2 - 1), radius=rad * 2, fill=255)
    mask = mask.resize((cw, ch), Image.LANCZOS)
    x = (W - cw) // 2

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sm = Image.new("L", (W, H), 0)
    sm.paste(mask.point(lambda v: int(v * 0.45)), (x, ctop + 24))
    shadow.putalpha(sm.filter(ImageFilter.GaussianBlur(36)))
    bg = Image.alpha_composite(bg, shadow)
    bg.paste(shot, (x, ctop), mask)
    ImageDraw.Draw(bg).rounded_rectangle((x, ctop, x + cw, ctop + ch), radius=rad, outline=(255, 255, 255, 90), width=4)
    bg.convert("RGB").save(f"{out}/{name}.png", optimize=True)
    print(name)
