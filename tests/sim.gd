extends SceneTree
## Headless AI-vs-AI playtest: checks invariants and prints outcome statistics.
## Run:  godot --headless --path . -s tests/sim.gd
## Env-free filters via user args:  -- classic   (only that mode)

func _total(g: NPGame) -> int:
	var n := g.deck.size() + g.out.size()
	for p in g.players:
		n += p.hand.size() + p.table.size()
	return n

func _init() -> void:
	var modes := ["classic", "slow", "fog", "fast"]
	var only := OS.get_cmdline_user_args()
	if not only.is_empty():
		modes = Array(only).filter(func(m): return m in ["classic", "slow", "fog", "fast"])
	var counts := [3, 4]
	var bios := ["off", "2000", "2035"]
	var sets := [["hawk", "dove", "opp", "wild"], ["hawk", "hawk", "wild", "dove"], ["dove", "dove", "opp", "hawk"], ["wild", "opp", "dove", "wild"]]
	var fails := 0
	for mode in modes:
		for np in counts:
			for bio in bios:
				fails += _batch(mode, np, bio, sets)
	print("ALL OK" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)

func _batch(mode: String, np: int, bio: String, sets: Array) -> int:
	var fails := 0
	var st := {"games": 0, "turns": 0, "last": 0, "annih": 0, "cease": 0, "maxT": 0, "deaths": 0}
	var kinds := {"short": 0, "long": 0, "super": 0, "plague": 0, "counter": 0, "test": 0}
	var trades := {"offers": 0, "honoured": 0, "reneged": 0, "threats": 0, "gave_in": 0, "refused": 0, "disarmed": 0}
	for seed_i in range(1, 101):
		var personas: Array = sets[seed_i % sets.size()]
		var plist: Array = []
		for i in range(np):
			plist.append({"name": "AI%d" % i, "human": false, "persona": personas[i]})
		var g := NPGame.new()
		g.setup({"mode": mode, "bio": bio, "seed": seed_i * 7919, "players": plist})
		g.event.connect(func(t, d):
			if t == "attack":
				kinds[d.type] += 1
			elif t == "test":
				kinds["test"] += 1
			elif t == "log":
				if d.text.contains("owes one back"):
					trades.offers += 1
				elif d.text.contains("completes the trade"):
					trades.honoured += 1
				elif d.text.contains("does NOT complete"):
					trades.reneged += 1
				elif d.text.contains(" threatens "):
					trades.threats += 1
				elif d.text.contains("gives in and returns"):
					trades.gave_in += 1
				elif d.text.contains("REFUSES"):
					trades.refused += 1
				elif d.text.contains("DISARMS"):
					trades.disarmed += 1)
		var expected := _total(g)
		var guard := 0
		var err := ""
		while not g.over and guard < 6000:
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
			if err == "" and mode == "classic" and g.debts.size() > np * 2:
				err = "debts piling up: %d" % g.debts.size()
			if err != "":
				break
		if err == "" and not g.over:
			err = "did not terminate"
		if err != "":
			fails += 1
			print("FAIL ", mode, " n=", np, " ", bio, " seed ", seed_i, ": ", err)
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
	var extra := ""
	if mode == "classic":
		extra = " trades=%d honoured=%d reneged=%d threats=%d gave_in=%d refused=%d" % [trades.offers, trades.honoured, trades.reneged, trades.threats, trades.gave_in, trades.refused]
	print("%s n=%d %s games=%d avgTurns=%.1f max=%d last=%d annih=%d cease/stalemate=%d avgDeaths=%.2f tests=%d short=%d long=%d super=%d plague=%d counter=%d%s" % [
		mode.rpad(7), np, bio.rpad(5), st.games, float(st.turns) / maxf(1.0, st.games), st.maxT, st.last, st.annih, st.cease,
		float(st.deaths) / maxf(1.0, st.games), kinds.test, kinds.short, kinds.long, kinds.super, kinds.plague, kinds.counter, extra])
	return fails
