#!/usr/bin/env python3
"""The front-page photographs for the Mutually Assured Destruction ending, with Meshy's text-to-image API.

    python3 tools/meshy_mad.py                    # every missing picture
    python3 tools/meshy_mad.py --force hands      # redo one
    python3 tools/meshy_mad.py --process DIR      # tone existing raw images DIR/<name>.png instead

The game's MAD end screen is a special edition of The Atomic Herald ("BALANCE OF TERROR") and shows one of
these at random: assets/ui/mad/<name>.jpg, cropped, 1200 px wide and toned to the newsprint's ink.
Key lookup as in meshy_portraits.py (--key-file, $MESHY_API_KEY, .secrets/meshy, ~/.secrets/meshy).
About 9 credits per picture. Fictional people only: no real flags, insignia or emblems.
"""
import os, sys, tempfile, time, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_portraits as M

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "mad")
PHOTO = ("Black-and-white silver-gelatin press photograph toned warm sepia, heavy halftone grain, aged newspaper "
         "front-page photo from the late 1940s. Fictional people. No flags, no national insignia, no real emblems, "
         "no text, no lettering, no watermark.")
PROMPTS = {
    "warroom": "A great round table in a dim underground war room. Four generals and statesmen of different fictional "
               "nations sit around it, each with one hand resting beside a large launch button, all staring at one "
               "another, nobody pressing. A huge blank wall map behind them. Silent, unbearably tense. ",
    "standoff": "Four statesmen in formal 1940s uniforms and suits stand in a circle in an empty marble hall, each "
                "calmly aiming a revolver at the man opposite, nobody firing. Seen from above. Still, formal, absurd. ",
    "silos": "Dawn over a frozen plain: a long row of open missile silos, the tall rockets standing ready and pointed "
             "at the sky, a few tiny soldiers watching. Nothing moves. Vast, quiet, ominous. ",
    "clock": "A towering old clock on a ruined city tower, its hands stopped at one minute to midnight, an intact city "
             "beneath it at dusk, searchlights crossing the sky. Ominous, still. ",
    "hands": "Close-up from above of the edge of a round war-room table: four hands of four different men, in military "
             "cuffs and civilian suit sleeves, each hovering a finger's width above its own large launch button, "
             "nobody pressing. Harsh overhead lamp light, deep shadows. ",
    "scales": "An enormous old brass balance scale in a dim war room, perfectly level: on each pan a stack of "
              "missiles and warheads. Generals and statesmen of different fictional nations stand around it in "
              "silence, watching that it does not tip. ",
    "banquet": "A formal state banquet: statesmen and generals of different fictional nations raise their glasses in a "
               "toast around a long candlelit table; beside every place setting sits a large launch button. Polished, "
               "uneasy smiles. ",
}


def tone(src, name):
    """Crop the worn edges, scale to 1200 px and print it in the newsprint's dark ink."""
    from PIL import Image, ImageOps
    im = Image.open(src).convert("L")
    w, h = im.size
    im = im.crop((int(w * 0.05), int(h * 0.05), int(w * 0.95), int(h * 0.95)))
    im = im.resize((1200, int(1200 * im.height / im.width)), Image.LANCZOS)
    im = ImageOps.colorize(im, (31, 27, 20), (236, 226, 200))
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name + ".jpg"), quality=85)


def main():
    args = sys.argv[1:]
    if "--process" in args:
        i = args.index("--process")
        d = args[i + 1]
        for name in PROMPTS:
            for src in (os.path.join(d, name + ".png"), os.path.join(d, "mad_" + name + ".png")):
                if os.path.exists(src):
                    tone(src, name)
                    print(name, "toned")
                    break
        return
    key = M.find_key(args)
    force = "--force" in args
    if force:
        args.remove("--force")
    names = [n for n in (args or PROMPTS) if force or not os.path.exists(os.path.join(OUT, n + ".jpg"))]
    jobs = {n: M.req(key, "POST", M.API, {"ai_model": "nano-banana-pro", "prompt": PROMPTS[n] + PHOTO,
                                           "aspect_ratio": "16:9"})["result"] for n in names}
    for name, tid in jobs.items():
        while True:
            t = M.req(key, "GET", "%s/%s" % (M.API, tid))
            if t["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
                break
            time.sleep(4)
        if t["status"] != "SUCCEEDED" or not t.get("image_urls"):
            print(name, "FAILED", t.get("task_error"))
            continue
        tmp = os.path.join(tempfile.gettempdir(), "meshy_mad_%s.dl" % name)      # download outside the project
        urllib.request.urlretrieve(t["image_urls"][0], tmp)
        tone(tmp, name)
        os.remove(tmp)
        print(name, "ok", "credits", t.get("consumed_credits"), flush=True)
    print("done - reopen the project in Godot to import the pictures")


if __name__ == "__main__":
    main()
