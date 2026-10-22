# Nuclear Poker (Godot 4)

Browser-playable digital adaptation of **Nuclear Poker** — a simple teaching game about nuclear strategy.
You play against two AI powers. Slow / Fog / Fast WAR rules and the Biowar (2000 / 2035) expansion are included.

Game design: Vinay Gupta. Print-and-play v4.2 and card art: Jonathan Korman (miniver.itch.io/nuclear-poker),
drawing on card designs by Ian Willey. Unofficial adaptation; check with the creators before any public release.

## Run
Open the folder in Godot 4.4+ and press Play (main scene: `scripts/main.tscn`).

## Layout
- `scripts/engine.gd`  — rules + AI, no UI (class `NPGame`). A lobby server can run this headless.
- `scripts/main.gd`    — all UI, built in code.
- `tests/sim.gd`       — headless AI-vs-AI simulation (invariants + stats):
  `godot --headless --path . -s tests/sim.gd`
- Bot playthrough through the real UI (needs a display, e.g. xvfb):
  `godot --path . -- --autotest`

## Web / GitHub Pages
`export_presets.cfg` has a single-threaded Web preset, so it works on GitHub Pages without special headers.
`.github/workflows/pages.yml` runs the simulation, exports, and deploys on every push to `main`
(enable Settings → Pages → Source: GitHub Actions).
Manual export: `godot --headless --export-release "Web" build/web/index.html`.

Fonts: Oswald and Share Tech Mono (SIL OFL, see `fonts/`).

## prototype-js/
The original single-file HTML/JS prototype (engine, UI, tests, `build.py` -> `nuclear-poker.html`).
Kept for reference; Godot ignores this folder (`.gdignore`). The Godot version in the repo root is the one in development.
