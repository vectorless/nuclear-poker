extends SceneTree
## Headless AI-vs-AI playtest: checks invariants and prints outcome statistics.
## Run:  godot --headless --path . -s tests/sim.gd

func _total(g: NPGame) -> int:
	var n := g.deck.size() + g.out.size()
	for p in g.players:
		n += p.hand.size() + p.table.size()
	return n

func _init() -> void:
	var modes := ["slow", "fog", "fast"]
	var bios := ["off", "2000", "2035"]
	var sets := [["hawk", "dove", "opp"], ["hawk", "hawk", "wild"], ["dove", "dove", "opp"], ["wild", "opp", "dove"]]
	var fails := 0
	for mode in modes:
		for bio in bios:
			var st := {"games": 0, "turns": 0, "last": 0, "annih": 0, "cease": 0, "maxT": 0, "deaths": 0}
			var kinds := {"short": 0, "long": 0, "super": 0, "plague": 0, "counter": 0, "test": 0}
			for seed_i in range(1, 101):
				var personas: Array = sets[seed_i % sets.size()]
				var plist: Array = []
				for i in range(personas.size()):
					plist.append({"name": "AI%d" % i, "human": false, "persona": personas[i]})
				var g := NPGame.new()
				g.setup({"mode": mode, "bio": bio, "seed": seed_i * 7919, "players": plist})
				g.event.connect(func(t, d):
					if t == "attack":
						kinds[d.type] += 1
					elif t == "test":
						kinds["test"] += 1)
				var expected := _total(g)
				var guard := 0
				var err := ""
				while not g.over and guard < 5000:
					guard += 1
					if mode == "fast":
						for p in g.players:
							if p.alive and not g.over:
								g.ai_fast_tick(p)
					var s := g.step()
					if s == "prompt" or s == "human":
						err = "unexpected wait " + s
						break
					if _total(g) != expected:
						err = "card count drift %d vs %d" % [_total(g), expected]
						break
					for p in g.players:
						if p.tested:
							var n_tech := 0
							for c in p.table:
								if c.key in NPGame.TECH:
									n_tech += 1
							if n_tech != 4:
								err = "tested without 4 tech on table"
						if not p.alive and not p.hand.is_empty():
							err = "dead player has hand"
					if err != "":
						break
				if err == "" and not g.over:
					err = "did not terminate"
				if err != "":
					fails += 1
					print("FAIL ", mode, " ", bio, " seed ", seed_i, ": ", err)
					continue
				st.games += 1
				st.turns += g.turn_no
				st.maxT = maxi(st.maxT, g.turn_no)
				for p in g.players:
					if not p.alive:
						st.deaths += 1
				match g.result.kind:
					"last": st.last += 1
					"annihilation": st.annih += 1
					_: st.cease += 1
			print("%s %s games=%d avgTurns=%.1f max=%d last=%d annih=%d cease/stalemate=%d avgDeaths=%.2f tests=%d short=%d long=%d super=%d plague=%d counter=%d" % [
				mode.rpad(5), bio.rpad(5), st.games, float(st.turns) / maxf(1.0, st.games), st.maxT, st.last, st.annih, st.cease,
				float(st.deaths) / maxf(1.0, st.games), kinds.test, kinds.short, kinds.long, kinds.super, kinds.plague, kinds.counter])
	print("ALL OK" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)
