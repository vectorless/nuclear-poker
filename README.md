# Nuclear Poker (Godot 4)

Browser-playable digital adaptation of **Nuclear Poker** — a simple teaching game about nuclear strategy.
You play the **Classic** rules sheet against two to four AI powers (3-5 players), with face-up trading and deals that can be broken.
The Slow / Fog / Fast WAR modes and the Biowar (2000 / 2035) expansions were removed for now so the game can be built one
mode at a time; they are in git history at the tag `all-modes`. (The Labs / Plague card art is still in `assets/`.)

Game design: Vinay Gupta. Print-and-play v4.2 and card art: Jonathan Korman (miniver.itch.io/nuclear-poker),
drawing on card designs by Ian Willey. Unofficial adaptation; check with the creators before any public release.

## Run
Open the folder in Godot 4.4+ and press Play (main scene: `scripts/main.tscn`).

## Layout
- `scripts/engine.gd`  — rules + AI, no UI (class `NPGame`). A lobby server can run this headless.
- `scripts/main.gd`    — all UI, built in code.
- `tests/sim.gd`       — headless AI-vs-AI simulation, 3/4/5 players (invariants + stats):
  `godot --headless --path . -s tests/sim.gd`
- Bot playthrough through the real UI (needs a display, e.g. xvfb):
  `godot --path . -- --autotest`  ·  real mouse drag test: `-- --dragtest`  ·  staged screenshots: `-- --shots`
- `tests/human_sim.gd` — engine-level driver with a random-policy human player.

## Web / GitHub Pages
`export_presets.cfg` has a single-threaded Web preset, so it works on GitHub Pages without special headers.
`.github/workflows/pages.yml` runs the simulation, exports, and deploys on every push to `main`
(enable Settings → Pages → Source: GitHub Actions).
Manual export: `godot --headless --export-release "Web" build/web/index.html`.

Fonts: Oswald and Share Tech Mono (SIL OFL, see `fonts/`).
