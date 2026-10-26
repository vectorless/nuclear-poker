#!/usr/bin/env python3
"""Generate the AI players' portraits with Meshy's text-to-image API.

    python3 tools/meshy_portraits.py                  # every missing portrait
    python3 tools/meshy_portraits.py --force hawk     # redo one
    python3 tools/meshy_portraits.py --model nano-banana-2

Key lookup: --key-file PATH, else $MESHY_API_KEY, else .secrets/meshy (in the project, git-ignored),
else ~/.secrets/meshy. Never commit the key. Output: assets/portraits/<persona>.png (square), plus
<persona>_head.png: a head-and-shoulders crop, toned down and vignetted into the panel colour, which the
game shows beside each AI's name (a stamped initial when it is missing). `--heads` redoes only the crops.
Style matches the cards: a 1940s field-manual / dossier photograph. Uniforms are inspired by different
world powers but carry no real flags, insignia or emblems, and depict no real person.
"""
import json, os, sys, time, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "portraits")
API = "https://api.meshy.ai/openapi/v1/text-to-image"

STYLE = ("Head-and-shoulders portrait photograph from a 1940s military intelligence dossier, as if pasted onto an "
         "aged field-manual page: black-and-white silver-gelatin print toned warm sepia, soft halftone grain, slight "
         "vignette, plain mottled studio backdrop, looking at the camera, serious. Fictional person. No flags, no "
         "national insignia, no real emblems, no text, no watermark.")
PEOPLE = {
    "hawk": "A stern, broad-shouldered general in his fifties, heavy 1940s Eastern European army greatcoat with "
            "shoulder boards, high-peaked officer's cap, rows of plain unmarked medal ribbons, cold eyes, clipped moustache.",
    "dove": "A thoughtful West African nuclear physicist and diplomat in her forties, 1940s tailored civilian suit "
            "with a laboratory coat over it, round wire spectacles, hair neatly pinned, calm and composed.",
    "opp": "A composed East Asian ambassador in his sixties, 1940s high-collared formal diplomatic tunic with "
           "plain brass buttons, silver hair combed back, a faint knowing smile, hands folded.",
    "wild": "A charismatic Latin American president in his forties, 1940s white dress military uniform with gold "
            "braid and an unmarked sash, slicked hair, thin moustache, a reckless confident grin.",
}


def find_key(args):
    if "--key-file" in args:
        i = args.index("--key-file")
        path = args[i + 1]
        del args[i:i + 2]
        return open(os.path.expanduser(path)).read().strip()
    if os.environ.get("MESHY_API_KEY"):
        return os.environ["MESHY_API_KEY"].strip()
    for p in (os.path.join(ROOT, ".secrets", "meshy"), os.path.expanduser("~/.secrets/meshy")):
        if os.path.exists(p):
            return open(p).read().strip()
    sys.exit("No Meshy key: use --key-file, $MESHY_API_KEY or .secrets/meshy")


def req(key, method, url, body=None):
    h = {"Authorization": "Bearer " + key, "Content-Type": "application/json"}
    for attempt in range(12):
        r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=h, method=method)
        try:
            with urllib.request.urlopen(r, timeout=120) as f:
                return json.load(f)
        except urllib.error.HTTPError as e:
            if e.code != 429 or attempt == 11:
                print("HTTP", e.code, e.read()[:300])
                raise
            time.sleep(float(e.headers.get("Retry-After") or 10))


# head crop per portrait, as fractions of the image: left, top, right, bottom
HEAD_BOX = {"hawk": (0.28, 0.10, 0.76, 0.58), "dove": (0.29, 0.13, 0.77, 0.61),
            "opp": (0.26, 0.12, 0.74, 0.60), "wild": (0.28, 0.12, 0.76, 0.60)}


def make_head(name):
    from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
    src = os.path.join(OUT, name + ".png")
    if not os.path.exists(src):
        return
    im = Image.open(src).convert("RGB")
    w, h = im.size
    b = HEAD_BOX.get(name, (0.26, 0.10, 0.74, 0.58))
    im = im.crop((int(b[0] * w), int(b[1] * h), int(b[2] * w), int(b[3] * h))).resize((256, 256), Image.LANCZOS)
    im = ImageEnhance.Color(ImageEnhance.Brightness(im).enhance(0.8)).enhance(0.75)
    mask = Image.new("L", (256, 256), 0)
    ImageDraw.Draw(mask).ellipse((34, 26, 222, 250), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(30)).point(lambda v: int(70 + 185 * v / 255))
    Image.composite(im, Image.new("RGB", (256, 256), (30, 32, 22)), mask).save(os.path.join(OUT, name + "_head.png"))


def main():
    args = sys.argv[1:]
    if "--heads" in args:
        for name in PEOPLE:
            make_head(name)
        print("heads done")
        return
    key = find_key(args)
    force = "--force" in args
    if force:
        args.remove("--force")
    model = "nano-banana-pro"
    if "--model" in args:
        i = args.index("--model")
        model = args[i + 1]
        del args[i:i + 2]
    os.makedirs(OUT, exist_ok=True)
    for name in args or list(PEOPLE):
        path = os.path.join(OUT, name + ".png")
        if os.path.exists(path) and not force:
            print(name, "exists")
            continue
        body = {"ai_model": model, "prompt": PEOPLE[name] + " " + STYLE, "aspect_ratio": "1:1"}
        tid = req(key, "POST", API, body)["result"]
        while True:
            time.sleep(4)
            t = req(key, "GET", "%s/%s" % (API, tid))
            if t["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
                break
        if t["status"] != "SUCCEEDED" or not t.get("image_urls"):
            print(name, "FAILED", t.get("task_error"))
            continue
        import tempfile
        tmp = os.path.join(tempfile.gettempdir(), "meshy_%s.dl" % name)      # download outside the project
        urllib.request.urlretrieve(t["image_urls"][0], tmp)
        from PIL import Image
        Image.open(tmp).convert("RGB").resize((512, 512), Image.LANCZOS).save(path)
        os.remove(tmp)
        make_head(name)
        print(name, "ok", "credits", t.get("consumed_credits"), flush=True)
    print("done - reopen the project in Godot to import the portraits")


if __name__ == "__main__":
    main()
