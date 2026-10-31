#!/usr/bin/env python3
"""Generate the AI players' portraits with Meshy's text-to-image API.

    python3 tools/meshy_portraits.py                  # every missing portrait
    python3 tools/meshy_portraits.py --force hawk     # redo one
    python3 tools/meshy_portraits.py --model nano-banana-2

Key lookup: --key-file PATH, else $MESHY_API_KEY, else .secrets/meshy (in the project, git-ignored),
else ~/.secrets/meshy. Never commit the key. Output: assets/portraits/<persona>.png (square), plus
<persona>_head.png: a head-and-shoulders crop, toned down and vignetted into the panel colour, which the
game shows beside each AI's name (a stamped initial when it is missing). `--heads` redoes only the crops.
`--dead` turns each portrait into its skeleton (Meshy image-to-image, same uniform and pose):
<persona>_dead.png and <persona>_dead_head.png, shown in the seat of an eliminated power.
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
    "pacifist": "A composed Levantine foreign minister in her fifties, 1940s tailored dark wool suit over a high-necked "
                "blouse with a small plain brooch, dark hair pinned in a low chignon, calm steady eyes, a faint sadness.",
    "peacemaker": "A poised South Asian ambassador in her forties, 1940s silk sari worn with a tailored jacket, hair in "
                  "a neat bun, a measured, listening expression, hands clasped.",
    "schemer": "A courtly Javanese chancellor in his sixties, 1940s formal double-breasted suit with a batik-patterned "
               "cravat and a blangkon cloth headdress, silver moustache, a patient, amused, calculating half-smile.",
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
            "opp": (0.26, 0.12, 0.74, 0.60), "wild": (0.28, 0.12, 0.76, 0.60),
            # these two came out as a small print pasted on a dossier page: crop to the print's face
            "peacemaker": (0.33, 0.12, 0.63, 0.42), "schemer": (0.35, 0.11, 0.65, 0.41),
            "pacifist": (0.22, 0.08, 0.72, 0.58)}


DEAD_PROMPT = ("Turn this person into a skeleton: keep exactly the same uniform, hat, clothing, pose, framing, "
               "lighting, backdrop and the same aged sepia dossier-photograph style, but the head is a bare "
               "grinning human skull with empty eye sockets and any visible hands are bones. Grim, not gory: "
               "no blood, no flesh. No text, no watermark.")
I2I = "https://api.meshy.ai/openapi/v1/image-to-image"


def make_dead(key, name, model):
    """The eliminated version of a portrait: the same figure as a skeleton."""
    import base64
    src = os.path.join(OUT, name + ".png")
    uri = "data:image/png;base64," + base64.b64encode(open(src, "rb").read()).decode()
    body = {"ai_model": model, "prompt": DEAD_PROMPT, "reference_image_urls": [uri], "aspect_ratio": "1:1"}
    return req(key, "POST", I2I, body)["result"]


def make_head(name, suffix=""):
    from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
    src = os.path.join(OUT, name + suffix + ".png")
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
    Image.composite(im, Image.new("RGB", (256, 256), (30, 32, 22)), mask).save(os.path.join(OUT, name + suffix + "_head.png"))


def main():
    args = sys.argv[1:]
    if "--heads" in args:
        for name in [a for a in args if a != "--heads"] or PEOPLE:
            make_head(name)
            make_head(name, "_dead")
        print("heads done")
        return
    key = find_key(args)
    if "--dead" in args:
        args.remove("--dead")
        force = "--force" in args
        if force:
            args.remove("--force")
        import tempfile
        from PIL import Image
        jobs = {}
        for name in args or list(PEOPLE):
            if os.path.exists(os.path.join(OUT, name + "_dead.png")) and not force:
                print(name, "dead exists")
                continue
            jobs[name] = make_dead(key, name, "nano-banana-pro")
        for name, tid in jobs.items():
            while True:
                t = req(key, "GET", "%s/%s" % (I2I, tid))
                if t["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
                    break
                time.sleep(4)
            if t["status"] != "SUCCEEDED" or not t.get("image_urls"):
                print(name, "FAILED", t.get("task_error"))
                continue
            tmp = os.path.join(tempfile.gettempdir(), "meshy_dead_%s.dl" % name)
            urllib.request.urlretrieve(t["image_urls"][0], tmp)
            Image.open(tmp).convert("RGB").resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, name + "_dead.png"))
            os.remove(tmp)
            make_head(name, "_dead")
            print(name, "dead ok", "credits", t.get("consumed_credits"), flush=True)
        return
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
