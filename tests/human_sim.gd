extends SceneTree
## Drives the engine the way the UI does, with player 0 as a (random-policy) human.
## Run:  godot --headless --path . -s tests/human_sim.gd

func _init() -> void:
	var fails := 0
	for np in [3, 4, 5]:
		for bio in ["off", "2035"]:
			for seed_i in range(1, 61):
				var plist: Array = [{"name": "Me", "human": true}]
				var ids := ["hawk", "dove", "opp", "wild"]
				for i in range(np - 1):
					plist.append({"name": "AI%d" % i, "persona": ids[(seed_i + i) % 4]})
				var g := NPGame.new()
				g.setup({"mode": "classic", "bio": bio, "seed": seed_i * 31, "players": plist})
				var me: NPGame.Player = g.players[0]
				var guard := 0
				var err := ""
				while not g.over and guard < 4000:
					guard += 1
					var st := g.status()
					if st == "over":
						break
					if st == "prompt":
						var pr := g.prompt
						if str(pr.get("type", "")) == "trade":
							var hand: Array = pr.player.hand
							g.answer_trade(hand[g.rng.randi() % hand.size()].id if g.rng.randf() < 0.5 and not hand.is_empty() else -1)
						elif str(pr.get("type", "")) == "deal":
							g.answer_deal(g.rng.randf() < 0.6)
						elif str(pr.get("type", "")) == "threat":
							g.answer_threat(g.rng.randf() < 0.5)
						else:
							g.choose_counter(pr.options[0])
					elif st == "human":
						_human(g, me)
					else:
						g.step()
				if not g.over:
					err = "stuck: phase=%s turn=%d cur=%s queue=%s alive=%d deck=%d debts=%d" % [g.phase, g.turn_no, g.cur().name, str(g.war_queue), g.alive_list().size(), g.deck.size(), g.debts.size()]
				if err != "":
					fails += 1
					print("FAIL np=", np, " ", bio, " seed ", seed_i, ": ", err)
	print("HUMAN SIM ", "OK" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)

func _human(g: NPGame, me: NPGame.Player) -> void:
	var r := g.rng.randf()
	if g.rng.randf() < 0.04:
		g.disarm_caps(me)       # allowed at any time
	if g.phase == "honour":
		if r < 0.4 or me.hand.is_empty():
			g.renege(me)
		else:
			g.honour(me)
	elif g.phase == "play":
		if r < 0.3 and not me.hand.is_empty():
			var o: Array = g.others(me)
			g.trade_offer(me, me.hand[0].id, o[g.rng.randi() % o.size()].id)
			if g.phase == "play" and g.prompt.is_empty() and g.rng.randf() < 0.5:
				if not g.deck.is_empty():
					g.play_research(me)
				else:
					g.play_skip(me)
		elif not g.deck.is_empty():
			g.play_research(me)
		else:
			g.play_skip(me)
	elif g.phase == "war":
		var L := g.legal(me)
		if L.can_test and r < 0.7:
			g.war_declare(me, {"kind": "test"})
		elif not g.threat_targets(me).is_empty() and r < 0.5:
			var ts := g.threat_targets(me)
			g.war_declare(me, {"kind": "threat", "target": ts[g.rng.randi() % ts.size()]})
		elif not L.attacks.is_empty() and r < 0.8:
			var a: Dictionary = L.attacks[g.rng.randi() % L.attacks.size()]
			g.war_declare(me, {"kind": "attack", "type": a.type, "target": a.targets[0] if not a.targets.is_empty() else -1})
		else:
			g.war_declare(me, {"kind": "pass"})
