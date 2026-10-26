extends SceneTree
## Headless AI-vs-AI playtest of the Classic game: checks invariants and prints outcome statistics.
## Run:  godot --headless --path . -s tests/sim.gd

func _total(g: NPGame) -> int:
	var n := g.deck.size() + g.out.size()
	for p in g.players:
		n += p.hand.size() + p.table.size() + p.trade.size()
	return n

func _init() -> void:
	var sets := [["hawk", "dove", "opp", "wild", "opp"], ["hawk", "hawk", "wild", "dove", "dove"], ["dove", "dove", "opp", "hawk", "wild"], ["wild", "opp", "dove", "wild", "hawk"]]
	var fails := 0
	for np in [3, 4, 5]:
		fails += _batch(np, sets)
	print("ALL OK" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)

func _batch(np: int, sets: Array) -> int:
	var fails := 0
	var st := {"games": 0, "turns": 0, "last": 0, "annih": 0, "cease": 0, "maxT": 0, "deaths": 0}
	var kinds := {"short": 0, "long": 0, "super": 0, "counter": 0, "test": 0}
	var trades := {"offers": 0, "honoured": 0, "reneged": 0, "threats": 0, "gave_in": 0, "refused": 0, "disarmed": 0, "grudge_hits": 0, "condemned": 0, "breaches": 0}
	for seed_i in range(1, 201):
		var personas: Array = sets[seed_i % sets.size()]
		var plist: Array = []
		for i in range(np):
			plist.append({"name": "AI%d" % i, "human": false, "persona": personas[i]})
		var g := NPGame.new()
		var fired := {}
		var extra_fires: Array = []
		var untested_disarms: Array = []
		g.setup({"seed": seed_i * 7919, "players": plist})
		g.event.connect(func(t, d):
			if t == "attack":
				kinds[d.type] += 1
				if d.type != "counter" and not g.is_superpower(d.attacker):
					var k := "%d:%d" % [d.attacker.id, g.turn_no]
					fired[k] = int(fired.get(k, 0)) + 1
					if fired[k] > 1:
						extra_fires.append(k)
				if d.target != null and g.grudge(d.attacker, d.target) > 0.2:
					trades.grudge_hits += 1
			elif t == "test":
				kinds["test"] += 1
			elif t == "log":
				if d.text.contains("has pledged"):
					trades.offers += 1
				elif d.text.contains("DELIVERS"):
					trades.honoured += 1
				elif d.text.contains("BREAKS the deal"):
					trades.reneged += 1
				elif d.text.contains(" threatens "):
					trades.threats += 1
				elif d.text.contains("gives in and returns"):
					trades.gave_in += 1
				elif d.text.contains("REFUSES"):
					trades.refused += 1
				elif d.text.contains("DISARMS"):
					trades.disarmed += 1
					for q in g.players:
						if d.text.begins_with(q.name + " DISARMS") and not q.tested:
							untested_disarms.append(q.name)
				elif d.text.contains("condemns"):
					trades.condemned += 1
				elif d.text.contains("breach of faith"):
					trades.breaches += 1)
		var expected := _total(g)
		var guard := 0
		var err := ""
		while not g.over and guard < 6000:
			guard += 1
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
				if not p.alive:
					for c in p.hand:
						if not c.pub:
							err = "dead player's hand not revealed"
			if err == "" and not extra_fires.is_empty():
				err = "fired twice in one turn without Superpower: " + str(extra_fires[0])
			if err == "" and not untested_disarms.is_empty():
				err = "disarmed before testing: " + str(untested_disarms[0])
			if err == "" and g.debts.size() > np * 2:
				err = "debts piling up: %d" % g.debts.size()
			if err != "":
				break
		if err == "" and not g.over:
			err = "did not terminate"
		if err != "":
			fails += 1
			print("FAIL n=", np, " seed ", seed_i, ": ", err)
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
	print("classic n=%d games=%d avgTurns=%.1f max=%d last=%d annih=%d cease/stalemate=%d avgDeaths=%.2f tests=%d short=%d long=%d super=%d counter=%d trades=%d honoured=%d reneged=%d threats=%d gave_in=%d refused=%d grudge_attacks=%d disarmed=%d condemned=%d breaches=%d" % [
		np, st.games, float(st.turns) / maxf(1.0, st.games), st.maxT, st.last, st.annih, st.cease,
		float(st.deaths) / maxf(1.0, st.games), kinds.test, kinds.short, kinds.long, kinds.super, kinds.counter,
		trades.offers, trades.honoured, trades.reneged, trades.threats, trades.gave_in, trades.refused, trades.grudge_hits, trades.disarmed, trades.condemned, trades.breaches])
	if st.games == 0:
		fails += 1      # nothing ran at all (e.g. the engine failed to compile)
	return fails
