#!/usr/bin/env python3
"""Paint fresh illustrations for the cards with Meshy's text-to-image API.

    python3 tools/meshy_card_art.py --style poster testing    # one card in one style (a sample)
    python3 tools/meshy_card_art.py --style poster            # every card in that style
    python3 tools/meshy_card_art.py --style poster --force long
    python3 tools/ww2_cards.py --art poster                   # build the cards with those pictures
    python3 tools/meshy_card_art.py --map                     # the side-panel map's painted land and sea

Key lookup: --key-file PATH, else $MESHY_API_KEY, else .secrets/meshy (git-ignored), else ~/.secrets/meshy.
Output: assets/ww2/art/<style>/<card>.png, a wide picture (16:9). Only the picture comes from Meshy:
tools/ww2_cards.py sets it into the card's window and prints the title and rules itself, so the text
stays crisp. Each image costs Meshy credits (nano-banana-pro: about 9).
--map paints assets/ui/map_land.jpg and map_sea.jpg: the game draws its countries and sea with these
as textures (the shapes stay the game's own, so borders still follow the seating).
"""
import json, os, sys, tempfile, time, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ww2", "art")
API = "https://api.meshy.ai/openapi/v1/text-to-image"

COMMON = ("A single clear subject with a strong, simple silhouette that still reads when the picture is "
          "shown very small. Late-1940s atomic-age setting. Fictional: no flags, no national insignia or "
          "emblems, no real people. No text, no letters, no numbers, no watermark. Full-bleed wide landscape "
          "picture filling the whole frame edge to edge: no border, no letterbox bars, no picture-in-picture.")
STYLES = {
    "poster": "1940s wartime propaganda poster art: flat screen-printed gouache, a limited palette of olive drab, "
              "mustard yellow, brick red and cream, bold simplified shapes, dramatic diagonal composition, "
              "visible paper grain and slight print misregistration.",
    "woodcut": "Bold black-ink woodcut / linocut print on warm cream paper: heavy carved lines, strong "
               "black-and-white contrast with a single spot colour of dull red, rough hand-printed texture.",
    "painted": "Vintage 1950s magazine cover illustration, painted in gouache and oil: dramatic cinematic "
               "lighting, muted desaturated colours with warm highlights, confident painterly brushwork.",
    "blueprint": "Technical engineering cutaway drawing: fine white and pale-cyan line work on deep Prussian-blue "
                 "blueprint paper, cross-hatching, construction lines, abstract unreadable annotation marks.",
}
SUBJECTS = {
    "uranium": "A rough chunk of uranium ore resting in a lead specimen tray, faint eerie glow, a Geiger counter beside it.",
    "refinement": "A long row of tall enrichment centrifuge cylinders in a vast industrial hall, pipes overhead.",
    "warhead": "A fat 1940s atomic bomb casing with box fins, on a wheeled trolley in a dim hangar.",
    "testing": "An atomic test: a towering mushroom cloud rising over a flat desert, a lone steel observation tower in the foreground.",
    "short": "A four-engine heavy bomber seen from below as it opens its bomb bay doors, searchlights in the night sky.",
    "long": "A tall rocket lifting off from a launch gantry, a column of fire and billowing exhaust.",
    "counter": "A submarine surfacing in a stormy sea at night, a missile hatch open on its deck.",
    "super": "A war-room globe of the world ringed by arcing missile trajectories, a dark command bunker behind it.",
}


MAP_COMMON = ("Seen straight down from above, as painted for a vintage 1940s war-room campaign map in gouache: "
              "soft painterly brushwork, even flat lighting, the same density everywhere across the image, "
              "full-bleed: a flat texture filling the entire image edge to edge - not an object, not a sheet of "
              "paper or a painting lying on a table. No text, no labels, no grid, no borders, no compass, no frame.")
MAP = {
    "map_land": "Top-down painted terrain: rolling hills, scattered dark forests, patchwork farmland, thin winding "
                "rivers and low mountain ridges, in muted olive, ochre, sage and umber. No coastline and no sea.",
    "map_sea": "Flat top-down painted texture of open sea: deep, dark, muted teal-grey water with stylised hand-painted wave strokes and "
               "faint ripples, low contrast. No land, no ships, no islands.",
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


def opt(args, name, default):
    if name in args:
        i = args.index(name)
        v = args[i + 1]
        del args[i:i + 2]
        return v
    return default


def main():
    args = sys.argv[1:]
    key = find_key(args)
    style = opt(args, "--style", "poster")
    model = opt(args, "--model", "nano-banana-pro")
    force = "--force" in args
    if force:
        args.remove("--force")
    maps = "--map" in args
    if maps:
        args.remove("--map")
    if style not in STYLES:
        sys.exit("styles: " + ", ".join(STYLES))
    out = os.path.join(ROOT, "assets", "ui") if maps else os.path.join(OUT, style)
    os.makedirs(out, exist_ok=True)
    jobs = {}
    for name in args or list(MAP if maps else SUBJECTS):          # start them all, then collect
        path = os.path.join(out, name + (".jpg" if maps else ".png"))
        if os.path.exists(path) and not force:
            print(name, "exists")
            continue
        prompt = MAP[name] + " " + MAP_COMMON if maps else SUBJECTS[name] + " " + STYLES[style] + " " + COMMON
        body = {"ai_model": model, "prompt": prompt, "aspect_ratio": "16:9"}
        jobs[name] = req(key, "POST", API, body)["result"]
    from PIL import Image
    for name, tid in jobs.items():
        while True:
            t = req(key, "GET", "%s/%s" % (API, tid))
            if t["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
                break
            time.sleep(4)
        if t["status"] != "SUCCEEDED" or not t.get("image_urls"):
            print(name, "FAILED", t.get("task_error"), flush=True)
            continue
        tmp = os.path.join(tempfile.gettempdir(), "meshy_art_%s_%s.dl" % (style, name))      # outside the project
        urllib.request.urlretrieve(t["image_urls"][0], tmp)
        im = Image.open(tmp).convert("RGB")
        if maps:      # a texture for a small panel: 1024 wide is plenty, and a JPEG keeps the web build small
            im = im.resize((1024, round(im.height * 1024 / im.width)), Image.LANCZOS)
            im.save(os.path.join(out, name + ".jpg"), quality=86)
        else:
            im.thumbnail((1280, 1280), Image.LANCZOS)
            im.save(os.path.join(out, name + ".png"))
        os.remove(tmp)
        print(name, "ok", "credits", t.get("consumed_credits"), flush=True)
    print("done - reopen the project in Godot to import the map" if maps else
          "done - now: python3 tools/ww2_cards.py --art " + style)


if __name__ == "__main__":
    main()
