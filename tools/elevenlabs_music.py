#!/usr/bin/env python3
"""Generate the adaptive background music with ElevenLabs' music API.

    python3 tools/elevenlabs_music.py                 # every missing track (60 s each)
    python3 tools/elevenlabs_music.py --force crisis  # regenerate one
    python3 tools/elevenlabs_music.py --length 90000  # track length in ms
    python3 tools/elevenlabs_music.py --key-file PATH

Key lookup: --key-file, else $ELEVENLABS_API_KEY, else ~/.secrets/elevenlabs. Never commit the key.
Output: assets/music/<level>.mp3. The game plays all four in sync and cross-fades between them as the
tension rises (calm -> uneasy -> tense -> crisis), so they share one key, tempo and band.
"""
import json, os, sys, time, urllib.error, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "music")
API = "https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128"

PALETTE = ("1940s orchestral film score in the style of a WWII newsreel and Cold War thriller: string section, "
           "French horns, low brass, timpani, military snare drum, harp and celesta. Same orchestra, same key "
           "(D minor) and the same steady tempo of 84 BPM throughout. Warm vintage mono-era recording, slight "
           "tape hiss. Instrumental, no vocals, no choir, no modern synths. Seamlessly loopable, ending where it began.")
TRACKS = {
    "calm": "Uneasy calm before anything has happened: sparse, quiet, low sustained strings, a lonely celesta "
            "motif, soft harp, distant horn, almost no percussion. Diplomats around a table, polite but wary.",
    "uneasy": "The first nuclear test has happened: the same theme now carried by low strings with a slow pulsing "
              "timpani heartbeat, muted horns, a quiet ticking snare. Suspicion growing, nobody trusts anybody.",
    "tense": "Weapons are armed: driving ostinato in the cellos and basses, insistent military snare pattern, "
             "horn calls answering each other, rising string tremolo. Everyone has a finger on the button.",
    "crisis": "Full nuclear crisis: urgent and loud, pounding timpani and snare, brass blasting the main theme in "
              "fortissimo, frantic string runs, dissonant horn clusters, a relentless march. The world on the brink.",
}


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
    length = 60000
    if "--length" in args:
        i = args.index("--length")
        length = int(args[i + 1])
        del args[i:i + 2]
    names = args or list(TRACKS)
    os.makedirs(OUT, exist_ok=True)
    for name in names:
        path = os.path.join(OUT, name + ".mp3")
        if os.path.exists(path) and not force:
            print(name, "exists")
            continue
        body = json.dumps({"prompt": TRACKS[name] + " " + PALETTE, "music_length_ms": length,
                           "force_instrumental": True}).encode()
        for attempt in range(3):
            t0 = time.time()
            req = urllib.request.Request(API, data=body, headers={"xi-api-key": key, "Content-Type": "application/json"},
                                         method="POST")
            try:
                with urllib.request.urlopen(req, timeout=600) as r:
                    data = r.read()
                open(path, "wb").write(data)
                normalize(path, -18)
                print(name, "ok", len(data), "bytes", "%.0fs" % (time.time() - t0), flush=True)
                break
            except urllib.error.HTTPError as e:
                print(name, "HTTP", e.code, e.read()[:300], flush=True)
                if e.code in (400, 401, 402, 403, 422):
                    break
                time.sleep(10)
            except Exception as e:
                print(name, "error", e, flush=True)
                time.sleep(10)
    print("done - reopen the project in Godot to import the music", flush=True)


if __name__ == "__main__":
    main()
