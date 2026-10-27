#!/usr/bin/env python3
"""The link-preview picture for X/Twitter, Facebook, Slack, ... (Open Graph / Twitter card).

    python3 tools/social_card.py      ->  web/social.jpg (1200 x 630)

Built from the game's own art: the campaign-map table, the stencil title and a fan of painted cards.
The meta tags (export_presets.cfg, head_include) load it from the repo on GitHub (raw.githubusercontent.com),
so it is live as soon as it is pushed.
"""
import math, os
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1200, 630
INK = (239, 229, 200)
AMBER = (217, 167, 62)


def font(name, size):
    return ImageFont.truetype(os.path.join(ROOT, "fonts", name), size)


def trefoil(d, cx, cy, r):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=AMBER)
    for k in range(3):
        mid = -math.pi / 2 + k * 2 * math.pi / 3
        pts = [(cx, cy)]
        for i in range(13):
            a = mid - math.pi / 6 + (math.pi / 3) * i / 12
            pts.append((cx + math.cos(a) * r * 0.82, cy + math.sin(a) * r * 0.82))
        d.polygon(pts, fill=(28, 26, 18))
    d.ellipse([cx - r * 0.24, cy - r * 0.24, cx + r * 0.24, cy + r * 0.24], fill=AMBER)
    d.ellipse([cx - r * 0.15, cy - r * 0.15, cx + r * 0.15, cy + r * 0.15], fill=(28, 26, 18))


def main():
    bg = Image.open(os.path.join(ROOT, "assets", "ww2", "table.jpg")).convert("RGB")
    sc = max(W / bg.width, H / bg.height)
    bg = bg.resize((int(bg.width * sc) + 1, int(bg.height * sc) + 1), Image.LANCZOS).crop((0, 0, W, H))
    bg = ImageEnhance.Brightness(bg).enhance(0.55)
    img = bg.convert("RGBA")
    # a fan of painted cards on the right
    keys = ["testing", "short", "long", "super"]
    cw = 225
    for i, k in enumerate(keys):
        c = Image.open(os.path.join(ROOT, "assets", "ww2", k + ".png")).convert("RGBA")
        c = c.resize((cw, int(cw * c.height / c.width)), Image.LANCZOS)
        ang = 18 - i * 12
        shadow = Image.new("RGBA", c.size, (0, 0, 0, 0))
        shadow.putalpha(c.getchannel("A").point(lambda v: int(v * 0.55)))
        shadow = shadow.rotate(ang, expand=True, resample=Image.BICUBIC).filter(ImageFilter.GaussianBlur(8))
        r = c.rotate(ang, expand=True, resample=Image.BICUBIC)
        x = 700 + i * 110
        y = 140 + abs(i - 1.5) * 22
        img.alpha_composite(shadow, (int(x + 10), int(y + 14)))
        img.alpha_composite(r, (int(x), int(y)))
    d = ImageDraw.Draw(img)
    # hazard stripe along the top
    for x in range(-40, W + 40, 40):
        d.polygon([(x, 0), (x + 20, 0), (x + 4, 16), (x - 16, 16)], fill=AMBER)
    d.rectangle([0, 16, W, 18], fill=(20, 18, 12))
    trefoil(d, 120, 230, 62)
    d.text((205, 172), "NUCLEAR", font=font("StardosStencil-Bold.ttf", 92), fill=INK)
    d.text((205, 262), "POKER", font=font("StardosStencil-Bold.ttf", 92), fill=AMBER)
    d.text((62, 410), "A fun, scary teaching game", font=font("SpecialElite-Regular.ttf", 38), fill=INK)
    d.text((62, 460), "about nuclear deterrence.", font=font("SpecialElite-Regular.ttf", 38), fill=INK)
    d.text((62, 540), "Play free in your browser - you vs. 2-4 powers", font=font("CourierPrime-Bold.ttf", 26), fill=AMBER)
    os.makedirs(os.path.join(ROOT, "web"), exist_ok=True)
    out = os.path.join(ROOT, "web", "social.jpg")
    img.convert("RGB").save(out, quality=88)
    print("wrote", out)


if __name__ == "__main__":
    main()
