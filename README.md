# Nuclear Poker (Godot 4)

![A five-player game: Ambassador Lin has just struck President Reyes - his seat shows a skeleton and his cards lie burnt, the map marks his country, and The Atomic Herald reports the attack](docs/screenshot.png)

Browser-playable digital adaptation of **Nuclear Poker** — a simple teaching game about nuclear strategy.
You play the **Classic** rules sheet against two to four AI powers (3-5 players), trading cards (your partner sees what you offer; their card comes back face down, on their next turn - if they keep the deal).
The Slow / Fog / Fast WAR modes and the Biowar (2000 / 2035) expansions were removed for now so the game can be built one
mode at a time; they are in git history at the tag `all-modes`.

Original game: Vinay Gupta and Dan Carter (GNU FDL licensed). The card art is new,
painted for this version. Unofficial adaptation; the rules are adapted from the original sheet for play against AI powers.

## Play
In the browser: https://vectorless.github.io/nuclear-poker/

## Run
Open the folder in Godot 4.6+ and press Play (main scene: `scripts/main.tscn`).

## Debug
Seven AI characters: the Hawk, the Deterrer, the Opportunist, the Wildcard, and three who think three levels deep -
the Pacifist, the Peacemaker and the Schemer (what they believe, what they think the others think of them, and how a
move will be read before they make it; `scripts/engine.gd`, "what the others think"). `tests/persona_test.gd` checks them.
Press **F9** in a game to see what each AI holds and thinks: hand, persona, how threatened it feels by
each player, its estimates of their arsenals, trust/alliances, stand-down leaning, and the draw pile.

## Web / GitHub Pages
`.github/workflows/pages.yml` runs the simulation, exports, and deploys on every push to `main`.
Manual export: `godot --headless --export-release "Web" build/web/index.html`.
