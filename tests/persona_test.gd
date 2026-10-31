extends SceneTree
## The three thinking characters: what they believe, what they think the others think of them, and
## how they read a move before making it. Run:  godot --headless --path . -s tests/persona_test.gd

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func game(personas: Array, hands: Array, seed_i := 3) -> NPGame:
	var g := NPGame.new()
	var plist: Array = [{"name": "You", "human": true}]
	for i in range(personas.size()):
		plist.append({"name": NPGame.PERSONAS[personas[i]].name, "persona": personas[i]})
	g.setup({"seed": seed_i, "players": plist})
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
	var arsenal := tech + ["short", "long", "counter", "super"]

	# ---- level 2: reputation. A broken deal is public; a favour in a trade is private.
	var g := game(["hawk", "pacifist", "schemer"], [["uranium"], ["uranium"], ["uranium"], ["uranium"]])
	var hawk: NPGame.Player = g.players[1]
	var pac: NPGame.Player = g.players[2]
	var sch: NPGame.Player = g.players[3]
	g._deal_outcome(hawk, pac, false)
	check(g.est_trust(sch, pac, hawk) < 0.3 and g.est_trust(sch, sch, hawk) < NPGame.TRUST_START, "everyone can see a broken deal cost the Hawk the table's trust")
	g._favour(pac, sch, {"key": "warhead"})
	check(g.est_trust(sch, pac, sch) > NPGame.TRUST_START and g.est_trust(hawk, pac, sch) == NPGame.TRUST_START, "a favour between two partners is known to them, not to the third")
	check(absf(g.est_trust(pac, pac, sch) - g.trust_of(pac, sch)) < 0.001, "and a partner's estimate of how it is seen matches the hidden truth")

	# ---- level 3: foresight. A tested, armed hawk with a grudge is a danger; the pacifist can see it coming.
	g = game(["hawk", "pacifist", "peacemaker"], [["uranium"], tech + ["short", "long"], ["refinement"], ["warhead"]])
	hawk = g.players[1]
	pac = g.players[2]
	var pm: NPGame.Player = g.players[3]
	check(g.peril(pac, pac) < 0.05, "an untested hawk is no immediate peril")
	g.do_test(hawk)
	for c in hawk.hand:
		c.pub = true      # Short and Long range shown
	g._deal_outcome(pac, hawk, false)      # the pacifist cheated the hawk once
	check(g.foresee_attack(pac, hawk, pac) > 0.35 and g.peril(pac, pac) > 0.4, "a tested, armed hawk with a grudge: the pacifist foresees the strike (intent %.2f)" % g.foresee_attack(pac, hawk, pac))
	check(g.foresee_attack(pm, hawk, pac) > g.foresee_attack(pm, hawk, pm), "and the peacemaker can tell the hawk has it in for the pacifist, not for her")

	# ---- the pacifist never builds the bomb and never fires
	g = game(["pacifist", "hawk", "wild"], [["uranium"], arsenal, ["short"], ["short"]])
	pac = g.players[1]
	var tests := 0
	for i in range(30):
		if g.ai_war_choice(pac).kind == "test":
			tests += 1
	check(tests == 0, "the pacifist never performs a Nuclear Test (0 of 30)")
	g.do_test(pac)
	var fires := 0
	for i in range(30):
		if g.ai_war_choice(pac).kind == "attack":
			fires += 1
	check(fires == 0, "even armed to the teeth, she never fires first (0 of 30)")

	# ---- the peacemaker reads provocation: she delays a test that would provoke, and tests when a strike is coming anyway
	g = game(["peacemaker", "hawk", "dove"], [["uranium"], tech + ["counter"], ["uranium"], ["uranium"]])
	pm = g.players[1]
	hawk = g.players[2]
	check(g.provocation(pm, "test") < 0.1, "with an unarmed table, a test provokes nobody")
	var t0 := 0
	for i in range(30):
		if g.ai_war_choice(pm).kind == "test":
			t0 += 1
	g = game(["peacemaker", "hawk", "dove"], [["uranium"], tech + ["counter"], tech + ["short", "long"], ["uranium"]])
	pm = g.players[1]
	hawk = g.players[2]
	g.do_test(hawk)
	for k in ["short", "long"]:
		for c in hawk.hand:
			if c.key == k:
				c.pub = true
	var t1 := 0
	for i in range(30):
		if g.ai_war_choice(pm).kind == "test":
			t1 += 1
	check(t1 > t0, "a hawk already armed next door: she goes nuclear to deter (tests %d of 30, vs %d with nobody armed)" % [t1, t0])

	# ---- arming: the peacemaker will not hand a weapon to a power inclined to use it; the schemer arms its rival's enemy
	g = game(["peacemaker", "hawk", "dove"], [["uranium"], ["short", "uranium"], tech, ["uranium"]])
	pm = g.players[1]
	hawk = g.players[2]
	var dove: NPGame.Player = g.players[3]
	g.do_test(hawk)
	var short_c: Dictionary = pm.hand[0]
	var to_hawk := g.deal_score(pm, hawk, short_c, g.belief(pm))
	var to_dove := g.deal_score(pm, dove, short_c, g.belief(pm))
	check(to_hawk < to_dove, "the peacemaker would sooner give Short range to the dove than to a tested hawk (%.2f vs %.2f)" % [to_hawk, to_dove])

	# ---- the schemer keeps faith with a dangerous creditor and breaks it with its rival once it can strike
	g = game(["schemer", "hawk", "dove"], [["uranium"], tech + ["short"], tech + ["short", "long"], ["uranium"]])
	sch = g.players[1]
	hawk = g.players[2]
	g.do_test(hawk)
	for c in hawk.hand:
		c.pub = true
	check(g.rival(sch) == hawk, "the schemer's rival is the armed hawk beside it")
	g.do_test(sch)
	var sh: Dictionary = sch.hand.filter(func(c): return c.key == "short")[0]
	g.turn = 1
	g.phase = "play"
	# a deal pending with the hawk: the schemer owes him a card
	g.debts.append({"from": hawk.id, "to": sch.id, "got": -1, "pledge": sh.id})
	sch.trade.append(sh)
	sch.hand.erase(sh)
	g.phase = "honour"
	var broke := 0
	for i in range(40):
		var g2 := game(["schemer", "hawk", "dove"], [["uranium"], tech + ["short"], tech + ["short", "long"], ["uranium"]], 100 + i)
		var s2: NPGame.Player = g2.players[1]
		var h2: NPGame.Player = g2.players[2]
		g2.do_test(h2)
		for c in h2.hand:
			c.pub = true
		g2.do_test(s2)
		var sh2: Dictionary = s2.hand.filter(func(c): return c.key == "short")[0]
		g2.turn = 1
		g2.debts.append({"from": h2.id, "to": s2.id, "got": -1, "pledge": sh2.id})
		s2.trade.append(sh2)
		s2.hand.erase(sh2)
		g2.phase = "honour"
		g2.ai_honour(s2)
		if g2.log_entries.back().text.contains("BREAKS"):
			broke += 1
	check(broke >= 20, "able to strike, the schemer breaks its deal with its rival (%d of 40)" % broke)

	# ---- stand-downs: a peace-lover proposes one when it can foresee agreement; the table may ask you
	g = game(["pacifist", "dove", "peacemaker"], [["uranium"], ["uranium"], tech, ["uranium"]])
	pac = g.players[1]
	var quiet := false
	for i in range(30):
		g.ceasefire_block.clear()
		quiet = quiet or g.ai_maybe_propose(pac)
	check(not quiet, "nobody has gone nuclear: nothing to stand down from, so she does not ask")
	g.do_test(g.players[2])
	g.turn = 1
	g.phase = "play"
	var asked := false
	for i in range(60):
		g.ceasefire_block.clear()
		if g.ai_maybe_propose(pac):
			asked = true
			break
	check(asked and g.prompt.get("type", "") == "ceasefire", "with a peaceful table, the pacifist proposes to stand down - and you are asked")
	g.answer_ceasefire(false)
	check(not g.over and not g.can_propose_ceasefire(pac), "refuse, and the game goes on; she cannot ask again at once")
	g.ceasefire_block.clear()
	g.ai_maybe_propose(pac) if g.prompt.is_empty() else null
	for i in range(60):
		if not g.prompt.is_empty():
			break
		g.ai_maybe_propose(pac)
	g.answer_ceasefire(true)
	check(g.over and g.result.kind == "ceasefire", "agree, and everyone stands down")

	print("PERSONA TEST ", "ALL OK" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)
