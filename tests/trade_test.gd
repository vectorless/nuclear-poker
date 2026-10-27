extends SceneTree
## Trading, rule by rule: the face-down offer / answer / pledge / deliver-or-break cycle, what a refusal
## costs, what happens to a pledge when someone dies, and how trades move trust.
## Run:  godot --headless --path . -s tests/trade_test.gd

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok    " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1

func _total(g: NPGame) -> int:
	var n := g.deck.size() + g.out.size()
	for p in g.players:
		n += p.hand.size() + p.table.size() + p.trade.size()
	return n

## A 4-player game (you + three AIs) where each hand is exactly `hands[i]` (card keys).
func game(hands: Array, seed_v := 1) -> NPGame:
	var g := NPGame.new()
	g.setup({"seed": seed_v, "players": [{"name": "You", "human": true}, {"name": "Volkov", "persona": "hawk"},
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
	g.turn = 0
	g.phase = "play"
	return g

func card(p, key: String):
	for c in p.hand:
		if c.key == key:
			return c
	return null

func logs_since(g: NPGame, n: int) -> String:
	var s := ""
	for i in range(n, g.log_entries.size()):
		s += str(g.log_entries[i].text) + "\n"
	return s

## Keep asking until the AI answers (it may decline; a refusal never costs the turn).
func offer_until_answered(g: NPGame, from, key: String, to_id: int) -> String:
	for i in range(200):
		var res := g.trade_offer(from, card(from, key).id, to_id)
		if res != "declined":
			return res
	return "never answered"

func _init() -> void:
	var cards_in_play := 0

	# ---- 1. you offer; a refusal costs nothing
	var g := game([["uranium", "short", "warhead"], ["refinement", "long", "uranium"], ["testing"], ["counter"]])
	cards_in_play = _total(g)
	var me = g.players[0]
	var vol = g.players[1]
	var n0 := g.log_entries.size()
	var declined := 0
	var res := ""
	var x = card(me, "short")
	var trust_before := g.trust_of(vol, me)
	for i in range(200):
		res = g.trade_offer(me, card(me, "short").id, 1)
		if res != "declined":
			break
		declined += 1
		check(me.hand.size() == 3 and me.trade.is_empty() and g.phase == "play" and g.cur() == me, "a refusal returns the card and keeps your turn") if declined == 1 else null
	check(res == "accepted" and g.prompt.is_empty(), "when Volkov answers, the deal is done - your offer was your acceptance (after %d refusals)" % declined)
	check(not logs_since(g, n0).to_lower().contains("short range") and not logs_since(g, n0).to_lower().contains("uranium"), "the log never names a traded card")
	var y = vol.trade[vol.trade.size() - 1]
	check(not x.pub and not y.pub, "both cards stay face down")
	check(me.hand.size() == 2 and vol.hand.size() == 3, "your card has gone to Volkov; his answer waits in his trade area")
	check(vol.hand.has(x) and not me.trade.has(x), "your card is handed over at once")
	check(vol.trade.has(y) and not me.hand.has(y), "their card stays behind as a pledge")
	check(g.debts.size() == 1 and g.debts[0].from == 0 and g.debts[0].to == 1 and g.debts[0].pledge == y.id, "the debt is recorded (Volkov owes you)")
	check(g.phase == "war", "a completed trade is your turn's action")
	check(g.trust_of(vol, me) > trust_before, "Volkov trusts you a little more: you handed over first")
	check(_total(g) == cards_in_play, "no card created or lost")
	# a pledged card is committed: it does not count towards Volkov's own test or weapons
	check(not g.holds(vol, y.key) or card(vol, y.key) != null, "a pledged card is not counted as held")
	# Volkov's next turn opens with the honour phase
	g.end_turn()
	check(g.cur() == vol and g.phase == "honour", "the pledger's next turn starts with deliver-or-break")
	check(g.trade_offer(vol, vol.hand[0].id, 0) == "invalid", "no trading until the pledge is settled")
	var t_me := g.trust_of(me, vol)
	var t_dove := g.trust_of(g.players[2], vol)
	g.honour(vol)
	check(me.hand.has(y) and not vol.trade.has(y) and not y.pub, "delivering puts the pledged card in your hand, still face down to the table")
	check(g.debts.is_empty() and g.phase == "play", "the debt is settled and Volkov plays on")
	check(g.trust_of(me, vol) > t_me and g.trust_of(g.players[2], vol) > t_dove, "keeping a deal raises trust (most with the partner)")
	check(_total(g) == cards_in_play, "no card created or lost")

	# ---- 2. breaking the deal
	g = game([["uranium", "short"], ["refinement", "long"], ["testing"], ["counter"]], 2)
	me = g.players[0]
	vol = g.players[1]
	res = offer_until_answered(g, me, "short", 1)
	y = vol.trade[vol.trade.size() - 1]
	g.end_turn()
	var tv := g.trust_of(me, vol)
	var tw := g.trust_of(g.players[3], vol)
	n0 = g.log_entries.size()
	g.renege(vol)
	check(vol.hand.has(y) and not me.hand.has(y), "breaking the deal keeps the pledged card")
	check(logs_since(g, n0).contains("BREAKS") and not logs_since(g, n0).to_lower().contains(str(NPGame.INFO[y.key].name).to_lower()), "the betrayal is public, the card is not")
	check(g.trust_of(me, vol) < tv - 0.3 and g.trust_of(g.players[3], vol) < tw - 0.1, "breaking a deal costs trust: heavily with the victim, less with everyone else")

	# ---- 3. you answer an offer: drag a card in, or decline
	g = game([["uranium", "short"], ["refinement", "long", "warhead"], ["testing"], ["counter"]], 3)
	me = g.players[0]
	vol = g.players[1]
	g.turn = 1
	var r3 := g.trade_offer(vol, card(vol, "warhead").id, 0)
	check(r3 == "prompt" and g.prompt.type == "trade" and g.prompt.player == me and g.prompt.get("card_key", "") == "warhead", "an offer to you shows you the card and asks you to answer")
	g.answer_trade(-1)
	check(vol.hand.size() == 3 and vol.trade.is_empty() and g.prompt.is_empty() and g.cur() == vol and g.phase == "play", "declining sends the card home; Volkov's turn goes on")
	var r3b := ""
	g.phase = "play"
	r3b = g.trade_offer(vol, card(vol, "warhead").id, 0)
	g.answer_trade(card(me, "uranium").id)
	check(g.debts.size() == 1 and g.debts[0].to == 0, "answering Volkov's offer closes the deal: you owe him the card")
	check(me.trade.size() == 1 and me.trade[0].key == "uranium" and vol.hand.any(func(c): return c.key == "warhead") == false, "your answer waits in your trade area; his card is already in your hand") if g.debts.size() > 0 else null
	check(card(me, "warhead") != null, "you received the Warhead")

	# ---- 4. a pledge when someone dies
	g = game([["uranium", "short"], ["refinement", "long"], ["testing"], ["counter"]], 4)
	me = g.players[0]
	vol = g.players[1]
	offer_until_answered(g, me, "short", 1)
	y = vol.trade[vol.trade.size() - 1]
	g.kill([me], {})      # the creditor dies before delivery
	g.end_turn()
	check(g.debts.is_empty() and vol.hand.has(y) and g.phase == "play", "creditor gone: the pledge goes back to the pledger, no honour phase")
	g = game([["uranium", "short"], ["refinement", "long"], ["testing"], ["counter"]], 5)
	me = g.players[0]
	vol = g.players[1]
	offer_until_answered(g, me, "short", 1)
	y = vol.trade[vol.trade.size() - 1]
	g.kill([vol], {})      # the pledger dies
	g.end_turn()
	check(g.debts.is_empty() and vol.hand.has(y) and y.pub and not me.hand.has(y), "pledger gone: the pledge is revealed with their hand; the creditor gets nothing")

	# ---- 5. trust from what arrives: a needed card warms, a duplicate is neutral
	g = game([["uranium"], ["uranium", "refinement"], ["testing"], ["counter"]], 6)
	me = g.players[0]
	vol = g.players[1]
	var t0 := g.trust_of(vol, me)
	g._favour(vol, me, {"key": "uranium"})
	check(absf(g.trust_of(vol, me) - t0) < 0.001, "a duplicate is neutral")
	g._favour(vol, me, {"key": "warhead"})
	check(g.trust_of(vol, me) > t0 + 0.05, "a card it needs builds goodwill")

	# ---- 6. invalid moves
	g = game([["uranium", "short"], ["refinement"], ["testing"], ["counter"]], 7)
	me = g.players[0]
	check(g.trade_offer(me, card(me, "short").id, 0) == "invalid", "you cannot trade with yourself")
	g.players[2].alive = false
	check(g.trade_offer(me, card(me, "short").id, 2) == "invalid", "nor with an eliminated player")
	g.players[2].alive = true
	g.turn = 1
	check(g.trade_offer(me, card(me, "short").id, 1) == "invalid", "nor out of turn")
	g.turn = 0
	g.phase = "war"
	check(g.trade_offer(me, card(me, "short").id, 1) == "invalid", "nor in the exchange window")

	# ---- 7. the AI judges a card it would give away as if it still held it
	# Volkov holds two Uraniums. Giving one away costs him nothing; he should weigh it as a duplicate.
	g = game([["warhead"], ["uranium", "uranium", "refinement"], ["testing"], ["counter"]], 8)
	vol = g.players[1]
	var u = card(vol, "uranium")
	var in_hand := g.usefulness(vol, u)
	vol.hand.erase(u)
	vol.trade.append(u)
	var in_trade := g.usefulness(vol, u)
	check(absf(in_hand - in_trade) < 0.001, "a duplicate in the trade area is still a duplicate (hand %.2f, trade area %.2f)" % [in_hand, in_trade])
	# honesty: pledging a spare card should not tempt a cheat more than pledging a vital one
	var kept_dup := 0
	var kept_vital := 0
	for s in range(400):
		for vital in [false, true]:
			var g2 := game([["warhead"], ["uranium", "uranium" if not vital else "short", "refinement"], ["testing"], ["counter"]], 100 + s)
			var v2 = g2.players[1]
			var pl = v2.hand[0] if not vital else card(v2, "short")
			v2.hand.erase(pl)
			v2.trade.append(pl)
			g2.debts = [{"from": 0, "to": 1, "got": -1, "pledge": pl.id}]
			g2.turn = 1
			g2.phase = "honour"
			g2.ai_honour(v2)
			if g2.players[0].hand.has(pl):
				if vital:
					kept_vital += 1
				else:
					kept_dup += 1
	print("      honour rate: spare card %d%%, card it needs %d%%" % [kept_dup / 4, kept_vital / 4])
	check(kept_dup > kept_vital, "a power keeps its word more readily over a card it can spare")

	# ---- 8. the player offered a card sees it: a needed card tempts, a duplicate does not
	var yes_need := 0
	var yes_dup := 0
	for s in range(300):
		var g3 := game([["warhead", "uranium"], ["uranium", "short", "long"], ["testing"], ["counter"]], 500 + s)
		var a3 = g3.players[0]
		var b3 = g3.players[1]
		if g3.ai_counter_offer(b3, a3, card(a3, "warhead")) >= 0:
			yes_need += 1
		if g3.ai_counter_offer(b3, a3, card(a3, "uranium")) >= 0:
			yes_dup += 1
	print("      Volkov answers: an offer of a card he needs %d%%, a duplicate %d%%" % [yes_need / 3, yes_dup / 3])
	check(yes_need > yes_dup + 30, "an AI looks at the card offered and wants the one it needs")

	print("TRADE TEST ", "ALL OK" if fails == 0 else "%d FAILURES" % fails)
	quit(1 if fails > 0 else 0)
