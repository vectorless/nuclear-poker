#!/usr/bin/env python3
"""Piles of charred bones for the powers destroyed by a nuclear attack, with Meshy's text-to-image API.

    python3 tools/meshy_bones.py                  # every missing pile (3)
    python3 tools/meshy_bones.py --force 2        # redo pile 2
    python3 tools/meshy_bones.py --process DIR    # cut out existing raw images DIR/bones_<n>.png instead

Each pile is painted on a green screen, which is keyed out: assets/ui/bones/pile_<n>.png, transparent,
trimmed and 320 px wide. When you are destroyed, the game drops one into your trade area and makes it smoulder.
Key lookup as in meshy_portraits.py. About 9 credits per pile. Grim, not gory: no blood.
"""
import os, sys, tempfile, time, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_portraits as M

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui", "bones")
N = 3
PROMPT = ("A small heap of charred human bones topped by a blackened grinning skull, the remains of a victim of a "
          "nuclear blast, ash-grey and scorched, a few embers glowing in the ashes at its base. Painted illustration in "
          "the style of a 1940s field manual, warm muted sepia and soot tones. Seen from the front and slightly above, "
          "centred, the whole heap in frame with space around it. On a solid flat pure bright green background "
          "(chroma key). No smoke, no shadow on the background, no blood, no text, no other objects.")


def cut_out(src, n):
    """Key out the green screen (and its spill on the edges), trim, scale to 320 px wide."""
    import numpy as np
    from PIL import Image, ImageFilter
    a = np.asarray(Image.open(src).convert("RGB")).astype(float)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = (g > 100) & (g > r * 1.25) & (g > b * 1.25)
    alpha = np.asarray(Image.fromarray(((~green) * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))
                       .filter(ImageFilter.GaussianBlur(1.0))).astype(float)
    a[..., 1] = np.minimum(g, np.maximum(r, b))      # no green fringe
    im = Image.fromarray(np.dstack([a, alpha]).clip(0, 255).astype(np.uint8), "RGBA")
    im = im.crop(im.getbbox())
    im = im.resize((320, int(320 * im.height / im.width)), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, "pile_%d.png" % n))


def main():
    args = sys.argv[1:]
    if "--process" in args:
        d = args[args.index("--process") + 1]
        for n in range(1, N + 1):
            src = os.path.join(d, "bones_%d.png" % n)
            if os.path.exists(src):
                cut_out(src, n)
                print("pile", n, "cut out")
        return
    key = M.find_key(args)
    force = "--force" in args
    if force:
        args.remove("--force")
    want = [int(x) for x in args] or list(range(1, N + 1))
    want = [n for n in want if force or not os.path.exists(os.path.join(OUT, "pile_%d.png" % n))]
    jobs = {n: M.req(key, "POST", M.API, {"ai_model": "nano-banana-pro", "prompt": PROMPT, "aspect_ratio": "1:1"})["result"]
            for n in want}
    for n, tid in jobs.items():
        while True:
            t = M.req(key, "GET", "%s/%s" % (M.API, tid))
            if t["status"] in ("SUCCEEDED", "FAILED", "CANCELED"):
                break
            time.sleep(4)
        if t["status"] != "SUCCEEDED" or not t.get("image_urls"):
            print("pile", n, "FAILED", t.get("task_error"))
            continue
        tmp = os.path.join(tempfile.gettempdir(), "meshy_bones_%d.dl" % n)      # download outside the project
        urllib.request.urlretrieve(t["image_urls"][0], tmp)
        cut_out(tmp, n)
        os.remove(tmp)
        print("pile", n, "ok", "credits", t.get("consumed_credits"), flush=True)
    print("done - reopen the project in Godot to import the piles")


if __name__ == "__main__":
    main()
