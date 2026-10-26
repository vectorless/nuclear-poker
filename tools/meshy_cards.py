#!/usr/bin/env python3
"""Optional: repaint the WWII cards with Meshy's image-to-image API, for richer illustrated art.

    python3 tools/meshy_cards.py              # all cards + back + table   (~10 images)
    python3 tools/meshy_cards.py short long   # just these
    python3 tools/meshy_cards.py --model nano-banana-2

Run it on your own machine: the API key is read from ~/.secrets/meshy (never commit it).
Input is the procedural art from tools/ww2_cards.py (assets/ww2/*.png), used as the reference image,
so layout, titles and rules text stay where they are. Results replace assets/ww2/<name>.png; the
procedural originals are kept in assets/ww2/procedural/ so you can switch back
(or just re-run tools/ww2_cards.py). Each image costs Meshy credits (nano-banana-pro: 9).
"""
import base64, json, os, shutil, sys, time, urllib.error, urllib.request

API = "https://api.meshy.ai/openapi/v1/image-to-image"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "ww2")
KEEP = os.path.join(ART, "procedural")

STYLE = ("1940s Second World War style: a printed field-manual / military dossier card on aged, slightly "
         "stained off-white paper, olive-drab and khaki ink, letterpress texture, subtle halftone shading. "
         "No flags, insignia, swastikas or real nations' emblems. Keep the exact layout, the header band, "
         "every word of text and its position unchanged and perfectly legible.")
PROMPTS = {
    "uranium": "Redraw the radiation trefoil as a detailed engraved illustration of a uranium ore sample beside the trefoil.",
    "refinement": "Redraw the rods as an engraved illustration of uranium enrichment centrifuge cylinders.",
    "warhead": "Redraw the cone as an engraved technical drawing of a 1940s bomb nose cone.",
    "testing": "Redraw the mushroom cloud as a dramatic engraved illustration of an atomic test cloud over a desert.",
    "short": "Redraw the bomb as a detailed 1940s aerial bomb, technical-drawing style.",
    "long": "Redraw the missile as a detailed 1940s long-range rocket, technical-drawing style.",
    "counter": "Redraw the submarine as a detailed 1940s submarine, technical-drawing style.",
    "super": "Redraw the globe as an engraved world globe with latitude lines.",
    "back": "Card back: keep the olive canvas, stencil words and the trefoil in a ring; add a fine woven canvas texture.",
}
TABLE_PROMPT = ("A worn 1940s military campaign map spread on a dark olive canvas table, faint grid squares and "
                "contour lines, coffee stains, no labels or real places, very dark and low-contrast so cards on top stay readable.")


def key():
    return open(os.path.expanduser("~/.secrets/meshy")).read().strip()


def req(method, url, body=None):
    h = {"Authorization": "Bearer " + key(), "Content-Type": "application/json"}
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


def data_uri(path):
    mt = "image/jpeg" if path.endswith(".jpg") else "image/png"
    return "data:%s;base64,%s" % (mt, base64.b64encode(open(path, "rb").read()).decode())


def run(name, src, prompt, model, aspect):
    body = {"ai_model": model, "prompt": prompt, "reference_image_urls": [data_uri(src)], "aspect_ratio": aspect}
    tid = req("POST", API, body)["result"]
    while True:
        time.sleep(4)
        t = req("GET", "%s/%s" % (API, tid))
        if t["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
            break
    if t["status"] != "SUCCEEDED" or not t.get("image_urls"):
        print("FAILED", name, t.get("task_error"))
        return None
    tmp = os.path.join(ART, name + ".meshy.dl")
    urllib.request.urlretrieve(t["image_urls"][0], tmp)
    print("ok", name, "credits", t.get("consumed_credits"))
    return tmp


def main():
    args = sys.argv[1:]
    model = "nano-banana-pro"
    if "--model" in args:
        i = args.index("--model")
        model = args[i + 1]
        del args[i:i + 2]
    names = args or list(PROMPTS) + ["table"]
    from PIL import Image
    os.makedirs(KEEP, exist_ok=True)
    for n in names:
        is_table = n == "table"
        fn = "table.jpg" if is_table else n + ".png"
        src = os.path.join(ART, fn)
        if not os.path.exists(os.path.join(KEEP, fn)):
            shutil.copy(src, os.path.join(KEEP, fn))
        ref = os.path.join(KEEP, fn)          # always start from the procedural original
        prompt = TABLE_PROMPT if is_table else STYLE + " " + PROMPTS[n]
        out = run(n, ref, prompt, model, "16:9" if is_table else "3:4")
        if out is None:
            continue
        im = Image.open(out).convert("RGBA" if not is_table else "RGB")
        orig = Image.open(ref)
        im = im.resize(orig.size, Image.LANCZOS)
        if not is_table:
            im.putalpha(orig.getchannel("A"))   # keep the rounded corners
            im.save(src)
        else:
            im.save(src, quality=86)
        os.remove(out)
    print("done - reopen the project in Godot to re-import the textures")


if __name__ == "__main__":
    main()
