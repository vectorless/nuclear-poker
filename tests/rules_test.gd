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
	# the draw pile is empty and the last two powers can neither test, strike nor usefully trade
	g = game([["uranium"], ["uranium", "uranium"], ["refinement", "refinement"], []])
	g.kill([g.players[0], g.players[3]], {})
	g.out.append_array(g.deck)
	g.deck.clear()
	g.turn = 1
	g.phase = "play"
	var steps := 0
	while not g.over and steps < 2000:
		g.step()
		steps += 1
	check(g.over and g.result.kind == "stalemate" and g.turn_no < 30, "two powers with nothing left to do end in a stalemate (turn %d, %s)" % [g.turn_no, g.result.get("kind", "-")])
	# Mutually Assured Destruction: only when every power left is a Superpower; then all win
	var full := tech + ["short", "long", "counter", "super"]
	g = game([full, full, ["uranium"], []])
	g.do_test(g.players[0])
	g.do_test(g.players[1])
	g.check_over()
	check(not g.over, "no MAD while a power left is not a Superpower")
	g.kill([g.players[2], g.players[3]], {})
	g.settle()
	check(g.over and g.result.kind == "mad" and g.result.survivors.size() == 2, "the moment every power left is a Superpower: MAD, and both survivors win (%s)" % g.result.get("kind", "-"))
	# A forced trade: the threatener puts up a card, the threatened player picks one to give back, or refuses
	g = game([["uranium", "refinement"], tech + ["short", "long"], ["warhead", "short"], ["testing"]])
	var volkov: NPGame.Player = g.players[1]
	var you: NPGame.Player = g.players[0]
	g.do_test(volkov)
	g.turn = 1
	g.phase = "play"
	var offer: int = volkov.hand.filter(func(c): return c.key == "long")[0].id
	check(g.play_threat(volkov, {"kind": "demand", "target": 0, "offer": offer}) and g.prompt.get("type", "") == "demand", "a power you could strike can be threatened into a trade")
	var give: int = you.hand[1].id
	g.answer_demand(give)
	check(volkov.hand.any(func(c): return c.id == give) and you.hand.any(func(c): return c.id == offer) and you.hand.size() == 2, "the cards swap: nothing is simply taken")
	check(g.phase == "war" and g.war_queue[0] == 1, "a threat is the move: the exchange window follows, threatener first")
	check(not g.play_threat(volkov, {"kind": "demand", "target": 0, "offer": offer}), "and there is no second threat this turn")
	g.phase = "play"
	var offer2: int = volkov.hand.filter(func(c): return c.id == give)[0].id
	var mine: Array = you.hand.map(func(c): return c.id)
	g.play_threat(volkov, {"kind": "demand", "target": 0, "offer": offer2})
	g.answer_demand(-1)
	check(you.hand.map(func(c): return c.id) == mine and volkov.hand.any(func(c): return c.id == offer2) and g.prompt.is_empty(), "or they refuse, and both keep their cards")
	check(g.war_queue.has(1), "after a refusal the threatener can still strike in that window")
	g.phase = "play"
	check(not g.play_threat(volkov, {"kind": "demand", "target": 0}) and g.prompt.is_empty() and you.hand.map(func(c): return c.id) == mine, "no trade without a card put up")
	# a frightened AI gives back the card it thinks the threatener needs; Volkov has tested, so not a Technology
	var okafor: NPGame.Player = g.players[2]
	okafor.persona = okafor.persona.duplicate()
	okafor.persona.fear = 1.0
	var gave_short := 0
	for i in range(40):
		var id := g.ai_answer_demand(okafor, volkov, offer2)
		if id >= 0 and okafor.hand.filter(func(c): return c.id == id)[0].key == "short":
			gave_short += 1
	check(gave_short >= 20, "a frightened power gives back the card the threatener wants (Short range %d of 40)" % gave_short)
	print("RULES TEST ", "ALL OK" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)
