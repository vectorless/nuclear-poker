#!/usr/bin/env python3
"""Generate the WWII-style card faces, card back and table texture for Nuclear Poker.

    python3 tools/ww2_cards.py            (run from the project folder; needs Pillow + numpy)
    python3 tools/ww2_cards.py --art poster   use the painted pictures in assets/ww2/art/poster/
                                              (from tools/meshy_card_art.py) instead of the ink icons
    python3 tools/ww2_cards.py --art painted --burnt   also the burnt copies shown for eliminated players
                                              (assets/ww2/burnt/, from the burn marks in assets/ww2/art/burn/)
    python3 tools/ww2_cards.py --only-burnt   only the burnt copies, from the cards as they are

Reads the icon shapes from the print-and-play card art in assets/*.png and redraws every card as a
1940s field-manual / dossier card: aged paper, olive-drab header, stencil title, typewriter rules text
and a rubber stamp. Output goes to assets/ww2/. Deterministic (fixed random seed).
"""
import math, os, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets")
OUT = os.path.join(ROOT, "assets", "ww2")
FONTS = os.path.join(ROOT, "fonts")
W, H = 660, 860
S = W / 330.0

PAPER = (228, 214, 176)
INK = (43, 36, 26)
OLIVE = (75, 83, 32)
KHAKI = (120, 100, 62)
STAMP_RED = (163, 40, 30)

TECH = ["uranium", "refinement", "warhead", "testing"]
CARDS = {
    "uranium":    ("URANIUM", "TECHNOLOGY", None, "NUCLEAR TEST", ["Reveal all four", "Technology cards"], None),
    "refinement": ("REFINEMENT", "TECHNOLOGY", None, "NUCLEAR TEST", ["Reveal all four", "Technology cards"], None),
    "warhead":    ("WARHEAD", "TECHNOLOGY", None, "NUCLEAR TEST", ["Reveal all four", "Technology cards"], None),
    "testing":    ("TESTING", "TECHNOLOGY", None, "NUCLEAR TEST", ["Reveal all four", "Technology cards"], None),
    "short":      ("SHORT RANGE", "CAPABILITY", "Requires: Nuclear Test", "ATTACK", ["Eliminate one", "neighbouring player"], "SPENT WHEN FIRED"),
    "long":       ("LONG RANGE", "CAPABILITY", "Requires: Test + Short range", "ATTACK", ["Eliminate any", "one player"], "SPENT WHEN FIRED"),
    "counter":    ("COUNTER-STRIKE", "CAPABILITY", "Requires: Test + Short + Long", "SECOND STRIKE", ["When you are eliminated,", "eliminate one player"], None),
    "super":      ("SUPERPOWER", "CAPABILITY", "Requires: Test + all 4 Capabilities", "SUPERPOWER", ["Strike any player,", "again and again"], None),
}


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


STENCIL = lambda s: font("StardosStencil-Bold.ttf", s)
TYPE = lambda s: font("SpecialElite-Regular.ttf", s)
TYPEB = lambda s: font("CourierPrime-Bold.ttf", s)


def noise(w, h, scale, rng):
    """Smooth value noise in 0..1 (blurred random field)."""
    small = Image.fromarray((rng.random((max(2, h // scale), max(2, w // scale))) * 255).astype(np.uint8))
    return np.asarray(small.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(scale / 3))) / 255.0


def paper(w, h, rng, base=PAPER, burn=0.35):
    grain = rng.normal(0, 1, (h, w)) * 7
    blotch = (noise(w, h, 90, rng) - 0.5) * 34 + (noise(w, h, 25, rng) - 0.5) * 12
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.maximum(np.abs(xx - w / 2) / (w / 2), np.abs(yy - h / 2) / (h / 2))
    edge = np.clip((d - 0.78) / 0.22, 0, 1) ** 1.6 * burn
    arr = np.zeros((h, w, 3))
    for i in range(3):
        arr[..., i] = (base[i] + grain + blotch) * (1 - edge) + 60 * edge
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], r, fill=255)
    return m


def rough(mask, rng, amount=0.55):
    """Rough up a stamp/ink mask so it looks pressed by hand."""
    a = np.asarray(mask).astype(float) / 255.0
    n = noise(mask.width, mask.height, 6, rng)
    a = a * np.clip((n - (0.5 - amount / 2)) / amount * 1.6, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))


def icon_mask(key):
    im = Image.open(os.path.join(SRC, key + ".png")).convert("RGBA")
    a = np.asarray(im).astype(int)
    g = a[..., :3].mean(-1)
    tech = key in TECH
    y0, y1 = (60, 290) if tech else (60, 300)
    m = np.zeros(g.shape, bool)
    reg = (g[y0:y1, 20:310] > 235) if tech else (g[y0:y1, 20:310] < 200)
    m[y0:y1, 20:310] = reg & (a[y0:y1, 20:310, 3] > 200)
    # keep only the picture: stop at the first clear gap of rows below it (the old card text follows)
    rows = m.any(1)
    start = int(np.argmax(rows))
    gap, end = 0, start
    for y in range(start, m.shape[0]):
        if rows[y]:
            gap, end = 0, y
        else:
            gap += 1
            if gap >= 8:
                break
    m[end + 1:] = False
    ys, xs = np.nonzero(m)
    crop = Image.fromarray((m * 255).astype(np.uint8)).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return crop


def centered(draw, y, text, f, fill):
    w = draw.textlength(text, font=f)
    draw.text(((W - w) / 2, y), text, font=f, fill=fill)


def stamp(text, rng, color=STAMP_RED, size=44, angle=-14):
    f = STENCIL(size)
    tw = int(ImageDraw.Draw(Image.new("L", (1, 1))).textlength(text, font=f))
    pad = 18
    m = Image.new("L", (tw + pad * 2, size + pad * 2), 0)
    d = ImageDraw.Draw(m)
    d.rectangle([3, 3, m.width - 4, m.height - 4], outline=255, width=5)
    d.text((pad, pad - 4), text, font=f, fill=255)
    m = rough(m, rng, 0.5).rotate(angle, expand=True, resample=Image.BICUBIC)
    col = Image.new("RGB", m.size, color)
    return col, m.point(lambda v: int(v * 0.82))


ART = None      # a style folder under assets/ww2/art/, or None for the ink icons
ART_BOX = (52, 200, W - 52, 508)      # the picture window: left, top, right, bottom


def trim_bars(im):
    """Cut away flat dark or light bars round a picture (letterboxing the image model sometimes adds)."""
    a = np.asarray(im).astype(float).mean(-1)
    def flat(line):
        return line.std() < 8.0 and (line.mean() < 40 or line.mean() > 200)
    t, b, l, r = 0, a.shape[0], 0, a.shape[1]
    while t < b - 10 and flat(a[t, l:r]):
        t += 1
    while b > t + 10 and flat(a[b - 1, l:r]):
        b -= 1
    while l < r - 10 and flat(a[t:b, l]):
        l += 1
    while r > l + 10 and flat(a[t:b, r - 1]):
        r -= 1
    return im.crop((l, t, r, b))


def art_window(card, key, rng):
    """Set a painted picture into the card like a printed plate: cropped to the window, a touch of the
    paper's grain through it, a thin ink frame. Returns False when there is no picture for this card."""
    path = os.path.join(OUT, "art", ART, key + ".png") if ART else None
    if not path or not os.path.exists(path):
        return False
    x0, y0, x1, y1 = ART_BOX
    bw, bh = x1 - x0, y1 - y0
    im = trim_bars(Image.open(path).convert("RGB"))
    sc = max(bw / im.width, bh / im.height)
    im = im.resize((int(im.width * sc + 0.5), int(im.height * sc + 0.5)), Image.LANCZOS)
    ox, oy = (im.width - bw) // 2, (im.height - bh) // 2
    im = im.crop((ox, oy, ox + bw, oy + bh))
    grain = card.crop((x0, y0, x1, y1)).convert("RGB")
    a = np.asarray(im).astype(float)
    g = np.asarray(grain).astype(float) / np.array(PAPER, float)
    a = a * (0.9 + 0.1 * g)      # printed on the same paper
    card.paste(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), (x0, y0))
    d = ImageDraw.Draw(card)
    d.rectangle([x0, y0, x1 - 1, y1 - 1], outline=INK, width=3)
    return True


def _icon(card, ic, rng):
    box_w, box_h = 380, 290
    sc = min(box_w / ic.width, box_h / ic.height)
    ic = ic.resize((max(1, int(ic.width * sc)), max(1, int(ic.height * sc))), Image.LANCZOS)
    n = noise(ic.width, ic.height, 5, rng)
    ic = Image.fromarray((np.asarray(ic) * (0.72 + 0.28 * n)).astype(np.uint8))      # worn ink
    inkc = Image.new("RGB", ic.size, INK)
    card.paste(inkc, ((W - ic.width) // 2, 215 + (box_h - ic.height) // 2), ic)


def make_card(key, idx):
    rng = np.random.default_rng(1945 + idx)
    prng = random.Random(1945 + idx)
    title, kind, req, rule, lines, note = CARDS[key]
    tech = key in TECH
    card = paper(W, H, rng)
    d = ImageDraw.Draw(card)
    # double rule border
    d.rectangle([20, 20, W - 21, H - 21], outline=INK, width=4)
    d.rectangle([32, 32, W - 33, H - 33], outline=INK, width=1)
    # header band
    band = OLIVE if not tech else KHAKI
    d.rectangle([32, 32, W - 33, 150], fill=band)
    # left-aligned title, so it stays readable when cards overlap in a hand
    size = 70
    while d.textlength(title, font=STENCIL(size)) > W - 110 and size > 40:
        size -= 2
    d.text((52, 46 + (70 - size) // 2), title, font=STENCIL(size), fill=PAPER)
    d.text((54, 160), kind, font=TYPE(30), fill=INK)
    if art_window(card, key, rng):
        ic = None
    else:
        ic = icon_mask(key)
    if ic is not None:
        _icon(card, ic, rng)
    # rules text
    y = 525
    if req:
        centered(d, y, req, TYPE(27), INK)
        y += 44
    d.line([120, y + 4, W - 120, y + 4], fill=INK, width=2)
    y += 18
    centered(d, y, rule, TYPEB(40), INK)
    y += 52
    for ln in lines:
        centered(d, y, ln, TYPE(32), INK)
        y += 40
    if note:
        centered(d, y + 6, note, TYPEB(26), STAMP_RED)
    # footer
    d.text((50, H - 70), "FORM NP-45", font=TYPE(22), fill=INK)
    d.text((50, H - 46), "No. %02d/08" % (idx + 1), font=TYPE(18), fill=INK)
    card.putalpha(rounded_mask(W, H, 26))
    return card


def make_back():
    rng = np.random.default_rng(7)
    card = paper(W, H, rng, base=(70, 76, 34), burn=0.5)
    d = ImageDraw.Draw(card)
    d.rectangle([20, 20, W - 21, H - 21], outline=(200, 186, 140), width=4)
    d.rectangle([34, 34, W - 35, H - 35], outline=(200, 186, 140), width=1)
    # canvas weave
    for x in range(40, W - 40, 10):
        d.line([x, 40, x, H - 40], fill=(64, 70, 30), width=1)
    for y in range(40, H - 40, 10):
        d.line([40, y, W - 40, y], fill=(64, 70, 30), width=1)
    # trefoil in a ring
    cx, cy, r = W / 2, H / 2 - 20, 170
    mk = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mk)
    md.ellipse([cx - r, cy - r, cx + r, cy + r], outline=255, width=10)
    for k in range(3):
        a0 = -90 + k * 120 - 30
        md.pieslice([cx - r + 30, cy - r + 30, cx + r - 30, cy + r - 30], a0, a0 + 60, fill=255)
    md.ellipse([cx - 52, cy - 52, cx + 52, cy + 52], fill=0)
    md.ellipse([cx - 32, cy - 32, cx + 32, cy + 32], fill=255)
    mk = Image.fromarray((np.asarray(mk) * (0.75 + 0.25 * noise(W, H, 5, rng))).astype(np.uint8))      # worn paint
    card.paste(Image.new("RGB", (W, H), (208, 190, 130)), (0, 0), mk.point(lambda v: int(v * 0.85)))
    f = STENCIL(64)
    for txt, y in [("NUCLEAR", 70), ("POKER", H - 150)]:
        w = d.textlength(txt, font=f)
        d.text(((W - w) / 2, y), txt, font=f, fill=(214, 198, 146))
    card.putalpha(rounded_mask(W, H, 26))
    return card


def make_table():
    """Board background: an old campaign map on canvas."""
    w, h = 1920, 1080
    rng = np.random.default_rng(3)
    img = paper(w, h, rng, base=(46, 49, 30), burn=0.55)
    d = ImageDraw.Draw(img)
    for x in range(0, w, 120):
        d.line([x, 0, x, h], fill=(58, 62, 38), width=1)
    for y in range(0, h, 120):
        d.line([0, y, w, y], fill=(58, 62, 38), width=1)
    f = TYPE(18)
    for i, x in enumerate(range(0, w, 120)):
        d.text((x + 6, 6), chr(65 + i % 26), font=f, fill=(78, 82, 52))
    for j, y in enumerate(range(0, h, 120)):
        d.text((6, y + 6), str(j + 1), font=f, fill=(78, 82, 52))
    # faint contour lines
    n = noise(w, h, 260, rng)
    for lv in np.linspace(0.3, 0.7, 7):
        band = (np.abs(n - lv) < 0.004)
        ys, xs = np.nonzero(band)
        for yy, xx in zip(ys[::3], xs[::3]):
            img.putpixel((int(xx), int(yy)), (66, 70, 44))
    return img


def burn_card(card, burn, flip=False):
    """Scorch a finished card with a photographed burn (a burnt sheet on a green screen): the green -
    burnt away - becomes transparent, the sheet's browns and blacks are multiplied into the card."""
    b = np.asarray(burn.convert("RGB")).astype(float)
    r, g, bl = b[..., 0], b[..., 1], b[..., 2]
    green = (g > 120) & (g - np.maximum(r, bl) > 25)      # also a pale, washed-out green screen
    ys, xs = np.nonzero(~green)
    im = burn.convert("RGB").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    im = im.resize(card.size, Image.LANCZOS)
    b = np.asarray(im).astype(float)
    r, g, bl = b[..., 0], b[..., 1], b[..., 2]
    gone = ((g > 120) & (g - np.maximum(r, bl) > 25)).astype(float)
    b[..., 1] = np.minimum(g, np.maximum(r, bl))      # take the green spill off the charred rim
    white = np.percentile(b[gone < 0.5].reshape(-1, 3), 92, axis=0)
    tone = np.clip(b / white, 0.0, 1.0)
    c = np.asarray(card.convert("RGBA")).astype(float)
    c[..., :3] *= tone
    keep = np.asarray(Image.fromarray(((1.0 - gone) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(float) / 255.0
    c[..., 3] *= keep
    out = Image.fromarray(np.clip(c, 0, 255).astype(np.uint8), "RGBA")
    return out.resize((W // 2, H // 2), Image.LANCZOS)      # only ever shown small


def make_burnt():
    src = os.path.join(OUT, "art", "burn")
    burns = [Image.open(os.path.join(src, f)) for f in sorted(os.listdir(src)) if f.endswith(".png")] if os.path.isdir(src) else []
    if not burns:
        print("no burn marks in", src, "- run tools/meshy_card_art.py --burn")
        return
    dst = os.path.join(OUT, "burnt")
    os.makedirs(dst, exist_ok=True)
    for i, k in enumerate(CARDS):
        card = Image.open(os.path.join(OUT, k + ".png"))
        burn_card(card, burns[i % len(burns)], flip=(i // len(burns)) % 2 == 1).save(os.path.join(dst, k + ".png"))
    print("wrote", dst)


def main():
    global ART
    import sys
    if "--art" in sys.argv:
        ART = sys.argv[sys.argv.index("--art") + 1]
    if "--only-burnt" in sys.argv:      # just redo the burnt copies from the finished cards
        make_burnt()
        return
    os.makedirs(OUT, exist_ok=True)
    for i, k in enumerate(CARDS):
        make_card(k, i).save(os.path.join(OUT, k + ".png"))
    make_back().save(os.path.join(OUT, "back.png"))
    make_table().convert("RGB").save(os.path.join(OUT, "table.jpg"), quality=86)
    print("wrote", OUT)
    if "--burnt" in sys.argv:
        make_burnt()


if __name__ == "__main__":
    main()
