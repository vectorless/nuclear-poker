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
	var g := game([tech + ["short", "long", "counter", "super"], ["short"], ["long"], ["counter"]])
	var me = g.players[0]
	g.do_test(me)
	check(g.is_superpower(me), "four Technologies tested + four Capabilities = Superpower")
	check(me.table.size() == 8 and me.hand.is_empty() and me.table.all(func(c): return c.pub), "and a Superpower's four Capabilities lie on the table for all to see")
	var at := g.attack_types(me)
	check(at.size() == 1 and at[0].type == "super" and at[0].targets.size() == 3, "a Superpower is offered one weapon only: the Superpower strike, at anyone")
	g.perform_attacks([{"p": me, "type": "super", "target": 1}])
	check(g.is_superpower(me) and me.table.size() == 8, "a Superpower strike spends nothing: every card stays, and so does the status")
	check(not g.attack_types(me).is_empty(), "and it can strike again the same turn")
	g.perform_attacks([{"p": me, "type": "super", "target": 2}])
	check(g.is_superpower(me) and g.alive_list().size() == 2, "again, and the table empties around it")
	# the last Capability arriving by a draw makes a Superpower on the spot
	g = game([tech + ["short", "long", "counter"], ["uranium"], ["uranium"], ["uranium"]])
	me = g.players[0]
	g.do_test(me)
	check(not g.is_superpower(me) and me.table.size() == 4 and me.hand.size() == 3, "tested with three Capabilities: not yet a Superpower, the Capabilities stay in hand")
	for i in range(g.deck.size()):
		if g.deck[i].key == "super":
			g.deck.append(g.deck.pop_at(i))
			break
	g.research(me)
	check(g.is_superpower(me) and me.table.size() == 8 and me.hand.is_empty(), "draw the fourth, and the whole arsenal goes on the table at once")
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
	# Hegemony: the only Superpower at a table where nobody else holds a Capability wins on the spot
	g = game([tech + ["short", "long", "counter", "super"], ["uranium", "short"], ["refinement"], ["warhead"]])
	me = g.players[0]
	g.do_test(me)
	g.check_over()
	check(not g.over, "a Superpower facing a power that still holds a Capability: the game goes on")
	g.kill([g.players[1]], {})
	g.settle()
	check(g.over and g.result.kind == "hegemony" and g.result.winner == 0 and g.result.survivors.size() == 3, "once no other power holds a Capability, the Superpower rules the world (%s)" % g.result.get("kind", "-"))
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
	# A forced trade, declared in the exchange window: the threatener puts up a card, the threatened
	# player picks one to give back, or refuses - and then the threatener declares again at once
	g = game([["uranium", "refinement"], tech + ["short", "long"], ["warhead", "short"], ["testing"]])
	var volkov: NPGame.Player = g.players[1]
	var you: NPGame.Player = g.players[0]
	g.do_test(volkov)
	g.phase = "war"
	g.war_queue = [1, 2]
	var offer: int = volkov.hand.filter(func(c): return c.key == "long")[0].id
	check(g.war_declare(volkov, {"kind": "demand", "target": 0, "offer": offer}) and g.prompt.get("type", "") == "demand", "in the exchange window, a power you could strike can be threatened into a trade")
	var give: int = you.hand[1].id
	g.answer_demand(give)
	check(volkov.hand.any(func(c): return c.id == give) and you.hand.any(func(c): return c.id == offer) and you.hand.size() == 2, "the cards swap: nothing is simply taken")
	check(g.war_queue[0] != 1 and g.war_queue.has(1) and not g.can_threaten(volkov), "given in to, the round of declarations starts again - and no second threat this turn")
	g.turn_no += 1
	g.phase = "war"
	g.war_queue = [1, 2]
	var offer2: int = volkov.hand.filter(func(c): return c.id == give)[0].id
	var mine: Array = you.hand.map(func(c): return c.id)
	g.war_declare(volkov, {"kind": "demand", "target": 0, "offer": offer2})
	g.answer_demand(-1)
	check(you.hand.map(func(c): return c.id) == mine and volkov.hand.any(func(c): return c.id == offer2) and g.prompt.is_empty(), "or they refuse, and both keep their cards")
	check(g.war_queue[0] == 1 and not g.attack_types(volkov).is_empty(), "refused, the threatener declares again at once and can strike")
	g.turn_no += 1
	g.phase = "war"
	g.war_queue = [1]
	g.war_declare(volkov, {"kind": "demand", "target": 0})
	check(g.prompt.is_empty() and you.hand.map(func(c): return c.id) == mine, "no trade without a card put up")
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
