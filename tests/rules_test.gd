extends SceneTree
## Rules from the How to play text that are not covered by the trade test or the simulation.
## Run:  godot --headless --path . -s tests/rules_test.gd

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func game(hands: Array) -> NPGame:
	var g := NPGame.new()
	g.setup({"seed": 3, "players": [{"name": "You", "human": true}, {"name": "Volkov", "persona": "hawk"},
		{"name": "Okafor", "persona": "dove"}, {"name": "Lin", "persona": "opp"}]})
	for p in g.players:
		g.deck.append_array(p.hand)
		p.hand.clear()
	for i in range(hands.size()):
		for k in hands[i]:
			for j in range(g.deck.size()):
				if g.deck[j].key == k:
					g.players[i].hand.append(g.deck.pop_at(j))
					break
	return g

func _init() -> void:
	var tech := ["uranium", "refinement", "warhead", "testing"]
	# a Superpower strikes for free - with any of its weapons - and again in the same turn
	var g := game([tech + ["short", "long", "counter", "super"], ["uranium"], ["uranium"], ["uranium"]])
	var me = g.players[0]
	g.do_test(me)
	check(g.is_superpower(me), "four Technologies tested + four Capabilities = Superpower")
	g.perform_attacks([{"p": me, "type": "short", "target": 1}])
	check(g.is_superpower(me) and g.holds(me, "short"), "a Superpower firing Short range keeps the card (and its status)")
	check(not g.attack_types(me).is_empty(), "and can strike again the same turn")
	g.perform_attacks([{"p": me, "type": "long", "target": 2}])
	check(g.is_superpower(me) and g.holds(me, "long"), "Long range too")
	# anyone else: one weapon per turn, and firing destroys it
	g = game([tech + ["short", "long"], ["uranium"], ["uranium"], ["uranium"]])
	me = g.players[0]
	g.do_test(me)
	g.perform_attacks([{"p": me, "type": "long", "target": 2}])
	check(not g.holds(me, "long") and g.holds(me, "short"), "Long range is spent when fired; Short range stays")
	check(g.attack_types(me).is_empty(), "one weapon per turn")
	# no attack before a test; disarming needs the test too
	g = game([["short", "long", "uranium"], ["uranium"], ["uranium"], ["uranium"]])
	me = g.players[0]
	check(g.attack_types(me).is_empty() and not g.can_disarm(me), "untested: no attacks, no disarming")
	print("RULES TEST ", "ALL OK" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)
