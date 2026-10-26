#!/usr/bin/env python3
"""Generate the game's sound effects with ElevenLabs' sound-generation API.

    python3 tools/elevenlabs_sfx.py                    # every missing sound
    python3 tools/elevenlabs_sfx.py --force test death # regenerate these
    python3 tools/elevenlabs_sfx.py --key-file PATH    # where the API key lives

Key lookup: --key-file, else $ELEVENLABS_API_KEY, else ~/.secrets/elevenlabs. Never commit the key.
Output: assets/sfx/<name>.mp3. The game plays a file when it exists and falls back to its built-in
synthesised sounds otherwise. Edit the prompts below and re-run with --force to change a sound.
"""
import json, os, sys, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sfx")
API = "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128"
NO = " No music, no voices, no speech."

# name: (prompt, seconds, loop)
SFX = {
    "draw": ("A single paper playing card slid quickly off a deck onto a wooden table, crisp and close.", 0.8, False),
    "click": ("One mechanical typewriter key strike, crisp metallic clack, close microphone.", 0.5, False),
    "your_turn": ("A 1940s teleprinter bell: one clear small bell ding followed by a short mechanical carriage clunk.", 1.2, False),
    "trade_offer": ("A telegraph operator tapping a short burst of Morse code on a brass key, 1940s radio room.", 1.6, False),
    "trade_counter": ("A quick burst of a manual typewriter typing a few words, then the carriage return bell.", 1.6, False),
    "deal": ("A rubber stamp pressed firmly onto paper on a wooden desk, a solid thump, then papers shuffled together.", 1.4, False),
    "broken": ("A sheet of thick paper torn sharply in half, then a short ominous low brass stab.", 1.6, False),
    "threat": ("Crackling 1940s shortwave radio static with a distorted warning tone pulsing three times.", 2.2, False),
    "test": ("A distant atomic bomb test in the desert: a deep low boom followed by long rolling thunder that slowly fades.", 4.0, False),
    "attack": ("A World War Two air raid siren winding up and wailing briefly, then a rocket launch roar.", 3.5, False),
    "death": ("A massive explosion with a heavy shockwave, debris falling, then a low rumble fading out.", 3.0, False),
    "disarm": ("Heavy metal ammunition crates set down on a concrete floor, chains rattling, a lock clicking shut.", 2.0, False),
    "standdown": ("Distant church bells ringing slowly in a quiet town after war, peaceful, birds faintly.", 4.0, False),
    "game_over": ("A lone distant bugle holding one long mournful note over wind, fading away.", 4.0, False),
    "ambience": ("WWII underground war room ambience: distant teleprinters clattering, faint ventilation hum, "
                 "occasional muffled radio crackle, very calm and low. Seamless loop.", 20.0, True),
}


# target loudness (LUFS) per sound; everything else -18
LEVEL = {"click": -24, "draw": -24, "deal": -21, "your_turn": -21, "trade_offer": -21, "trade_counter": -21,
         "attack": -16, "death": -16, "test": -16, "ambience": -30}

def normalize(path, lufs):
    """Level the file to a target loudness with ffmpeg (if installed), so sounds sit together."""
    import shutil, subprocess
    if not shutil.which("ffmpeg"):
        return
    tmp = path + ".norm.mp3"
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-af",
                        "loudnorm=I=%s:TP=-1.5:LRA=11" % lufs, "-ar", "44100", "-b:a", "128k", tmp])
    if r.returncode == 0:
        os.replace(tmp, path)


def find_key(args):
    if "--key-file" in args:
        i = args.index("--key-file")
        path = args[i + 1]
        del args[i:i + 2]
        return open(os.path.expanduser(path)).read().strip()
    if os.environ.get("ELEVENLABS_API_KEY"):
        return os.environ["ELEVENLABS_API_KEY"].strip()
    return open(os.path.expanduser("~/.secrets/elevenlabs")).read().strip()


def main():
    args = sys.argv[1:]
    key = find_key(args)
    force = "--force" in args
    if force:
        args.remove("--force")
    names = args or list(SFX)
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        text, dur, loop = SFX[name]
        path = os.path.join(OUT, name + ".mp3")
        if os.path.exists(path) and not force:
            continue
        body = {"text": text + NO, "duration_seconds": dur, "prompt_influence": 0.55}
        if loop:
            body["loop"] = True
        req = urllib.request.Request(API, data=json.dumps(body).encode(),
                                     headers={"xi-api-key": key, "Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                open(path, "wb").write(r.read())
            normalize(path, LEVEL.get(name, -18))
            print(name, "ok", flush=True)
        except urllib.error.HTTPError as e:
            print(name, "HTTP", e.code, e.read()[:300], flush=True)
    print("done", flush=True)


if __name__ == "__main__":
    main()
