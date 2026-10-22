class_name NPGame
extends RefCounted
## Nuclear Poker — rules engine + AI (pure logic, no nodes), ported from the JS prototype.
## Game design: Vinay Gupta. Print-and-play v4.2: Jonathan Korman. Card designs inspired by Ian Willey.
## Kept free of any UI so a lobby server can run it later (e.g. as a headless Godot instance).

signal event(type: String, data: Dictionary)

const TECH := ["uranium", "refinement", "warhead", "testing"]
const CAPS := ["short", "long", "counter", "super"]
const BIO := ["labs", "plague"]

const INFO := {
	"uranium": {"name": "Uranium", "kind": "tech"},
	"refinement": {"name": "Refinement", "kind": "tech"},
	"warhead": {"name": "Warhead", "kind": "tech"},
	"testing": {"name": "Testing", "kind": "tech"},
	"short": {"name": "Short-range", "kind": "cap"},
	"long": {"name": "Long-range", "kind": "cap"},
	"counter": {"name": "Counter-strike", "kind": "cap"},
	"super": {"name": "Superpower", "kind": "cap"},
	"labs": {"name": "Labs", "kind": "bio"},
	"plague": {"name": "Plague", "kind": "bio"},
}

const PERSONAS := {
	"hawk": {"id": "hawk", "name": "General Volkov", "title": "The Hawk", "aggr": 0.80, "fear": 0.50, "caution": 0.20, "gift": 0.04, "reveal": 0.04, "noise": 0.10, "react": [0.9, 2.4], "color": "#d9534f"},
	"dove": {"id": "dove", "name": "Dr. Okafor", "title": "The Deterrer", "aggr": 0.22, "fear": 0.95, "caution": 0.85, "gift": 0.10, "reveal": 0.55, "noise": 0.08, "react": [1.6, 3.6], "color": "#4aa3df"},
	"opp": {"id": "opp", "name": "Ambassador Lin", "title": "The Opportunist", "aggr": 0.50, "fear": 0.75, "caution": 0.50, "gift": 0.10, "reveal": 0.20, "noise": 0.10, "react": [1.2, 3.0], "color": "#e0a526"},
	"wild": {"id": "wild", "name": "President Reyes", "title": "The Wildcard", "aggr": 0.55, "fear": 0.40, "caution": 0.10, "gift": 0.22, "reveal": 0.30, "noise": 0.35, "react": [0.8, 3.4], "color": "#9b6bd1"},
}

class Player:
	var id: int = 0
	var name: String = ""
	var human: bool = false
	var persona: Dictionary = {}
	var hand: Array = []
	var table: Array = []
	var alive: bool = true
	var tested: bool = false
	var kills: int = 0
	var eliminated_by: int = -1
	var eliminated_turn: int = -1

var rng := RandomNumberGenerator.new()
var mode: String = "slow"          # slow | fog | fast
var bio: String = "off"           # off | 2000 | 2035
var players: Array = []
var deck: Array = []              # draw from the END of the array
var out: Array = []               # cards set aside from eliminated players
var log_entries: Array = []
var turn: int = 0
var turn_no: int = 1
var round_no: int = 1
var phase: String = "play"        # play | war | fog
var int_checked: bool = false
var over: bool = false
var result: Dictionary = {}
var fog_active: bool = false
var fog_choices: Dictionary = {}
var prompt: Dictionary = {}       # pending human decision (counter-strike target)
var counter_q: Array = []
var next_card_id: int = 1
var total: Dictionary = {}
var plagued: bool = false

# ---------------------------------------------------------------- helpers
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

func _mk(key: String) -> Dictionary:
	var c := {"id": next_card_id, "key": key, "pub": false}
	next_card_id += 1
	return c

func by_id(id: int) -> Player:
	return players[id]

func alive_list() -> Array:
	return players.filter(func(x): return x.alive)

func others(p: Player) -> Array:
	return players.filter(func(x): return x.alive and x != p)

func cur() -> Player:
	return players[turn]

func holds(p: Player, key: String) -> bool:
	for c in p.hand:
		if c.key == key:
			return true
	for c in p.table:
		if c.key == key:
			return true
	return false

func has_all_caps(p: Player) -> bool:
	for k in CAPS:
		if not holds(p, k):
			return false
	return true

func card_name(c: Dictionary) -> String:
	return INFO[c.key].name

func neighbors_of(p: Player) -> Array:
	var al := alive_list()
	if al.size() < 2:
		return []
	var i := al.find(p)
	if i < 0:
		return []
	var a = al[(i + 1) % al.size()]
	var b = al[(i - 1 + al.size()) % al.size()]
	if a == b:
		return [a]
	return [a, b]

func log_msg(text: String, tone: String = "info") -> void:
	var e := {"n": turn_no, "text": text, "tone": tone}
	log_entries.append(e)
	event.emit("log", e)

# ---------------------------------------------------------------- setup
## opts: {mode, bio, seed?, players: [{name, human, persona}]}
func setup(opts: Dictionary) -> void:
	if opts.has("seed"):
		rng.seed = int(opts["seed"])
	else:
		rng.randomize()
	mode = opts.get("mode", "slow")
	bio = opts.get("bio", "off")
	var plist: Array = opts["players"]
	var n := plist.size()
	for s in range(n + 1):
		for k in TECH + CAPS:
			deck.append(_mk(k))
		if bio != "off":
			for k in BIO:
				deck.append(_mk(k))
	for c in deck:
		total[c.key] = int(total.get(c.key, 0)) + 1
	_shuffle(deck)
	for i in range(n):
		var pp: Dictionary = plist[i]
		var pl := Player.new()
		pl.id = i
		pl.name = pp.get("name", "P%d" % i)
		pl.human = bool(pp.get("human", false))
		if not pl.human:
			pl.persona = PERSONAS.get(pp.get("persona", "opp"), PERSONAS["opp"])
		players.append(pl)
	for r in range(3):
		for p in players:
			p.hand.append(deck.pop_back())
	turn = rng.randi_range(0, n - 1)

# ---------------------------------------------------------------- basic actions
func research(p: Player) -> bool:
	if deck.is_empty():
		return false
	var c = deck.pop_back()
	c.pub = false
	p.hand.append(c)
	log_msg("%s researches (draws a card)." % p.name)
	event.emit("draw", {"p": p, "c": c})
	return true

func _take_hand_card(p: Player, card_id: int):
	for i in range(p.hand.size()):
		if p.hand[i].id == card_id:
			return p.hand.pop_at(i)
	return null

func proliferate(p: Player, card_id: int, target_id: int) -> bool:
	var t := by_id(target_id)
	if t == null or not t.alive or t == p:
		return false
	var c = _take_hand_card(p, card_id)
	if c == null:
		return false
	c.pub = false
	t.hand.append(c)
	log_msg("%s gives a card to %s (Proliferation)." % [p.name, t.name])
	event.emit("give", {"from": p, "to": t, "c": c})
	return true

func disarm(p: Player, card_id: int) -> bool:
	var c = _take_hand_card(p, card_id)
	if c == null:
		return false
	c.pub = false
	deck.insert(rng.randi_range(0, deck.size()), c)
	log_msg("%s returns a card to the deck (Disarmament)." % p.name)
	event.emit("disarm", {"p": p, "c": c})
	return true

func reveal(p: Player, card_id: int) -> bool:
	for c in p.hand:
		if c.id == card_id:
			if c.pub:
				return false
			c.pub = true
			log_msg("%s reveals a %s card from their hand." % [p.name, card_name(c)], "reveal")
			event.emit("reveal", {"p": p, "c": c})
			return true
	return false

func can_test(p: Player) -> bool:
	if not p.alive or p.tested:
		return false
	for k in TECH:
		var found := false
		for c in p.hand:
			if c.key == k:
				found = true
				break
		if not found:
			return false
	return true

func do_test(p: Player) -> bool:
	if not can_test(p):
		return false
	for k in TECH:
		for i in range(p.hand.size()):
			if p.hand[i].key == k:
				var c = p.hand.pop_at(i)
				c.pub = true
				p.table.append(c)
				break
	p.tested = true
	log_msg("%s performs a NUCLEAR TEST — all four Technologies on the table." % p.name, "test")
	event.emit("test", {"p": p})
	return true

# ---------------------------------------------------------------- attacks
## Returns [{type, targets:[ids]}]. `interrupt` = acting out of turn.
func attack_types(p: Player, interrupt: bool = false) -> Array:
	var outl: Array = []
	if not p.alive:
		return outl
	var allow := func(t: String) -> bool:
		return (not interrupt) or mode == "fast" or t == "super"
	var nuc := p.tested
	if nuc and holds(p, "short") and allow.call("short"):
		outl.append({"type": "short", "targets": neighbors_of(p).map(func(x): return x.id)})
	if nuc and holds(p, "short") and holds(p, "long") and allow.call("long"):
		outl.append({"type": "long", "targets": others(p).map(func(x): return x.id)})
	if nuc and has_all_caps(p) and allow.call("super"):
		outl.append({"type": "super", "targets": others(p).map(func(x): return x.id)})
	if bio != "off" and holds(p, "labs") and holds(p, "plague") \
			and (bio == "2035" or (p.tested and has_all_caps(p))) and allow.call("plague"):
		outl.append({"type": "plague", "targets": []})
	return outl

func reveal_keys(type: String) -> Array:
	match type:
		"short": return ["short"]
		"long": return ["short", "long"]
		"super": return CAPS.duplicate()
		"plague": return (CAPS + BIO) if bio == "2000" else BIO.duplicate()
	return []

func _show_cards(p: Player, keys: Array) -> Array:
	var shown: Array = []
	for k in keys:
		var on_table := false
		for c in p.table:
			if c.key == k:
				on_table = true
				break
		if on_table:
			continue
		for i in range(p.hand.size()):
			if p.hand[i].key == k:
				var c = p.hand.pop_at(i)
				c.pub = true
				p.table.append(c)
				shown.append(INFO[k].name)
				break
	return shown

## list: [{p, type, target(int or -1)}] — all validated against the pre-state; resolved together.
func perform_attacks(list: Array) -> void:
	var victims := {}   # victim id -> attacker
	for a in list:
		var shown := _show_cards(a.p, reveal_keys(a.type))
		var tgt = null
		if int(a.target) >= 0:
			tgt = by_id(int(a.target))
		var suffix := ""
		if not shown.is_empty():
			suffix = " (shows %s)" % ", ".join(shown)
		if a.type == "plague":
			log_msg("%s unleashes PLAGUE%s!" % [a.p.name, suffix], "attack")
			for x in others(a.p):
				if not holds(x, "labs"):
					victims[x.id] = a.p
			plagued = true   # everyone still alive afterwards must hold Labs
		else:
			var label: String = {"short": "Short-range", "long": "Long-range", "super": "Superpower"}[a.type]
			log_msg("%s launches a %s ATTACK on %s%s!" % [a.p.name, label, tgt.name, suffix], "attack")
			if tgt != null and tgt.alive:
				victims[tgt.id] = a.p
		event.emit("attack", {"attacker": a.p, "type": a.type, "target": tgt})
	var vs: Array = []
	for id in victims.keys():
		vs.append(by_id(id))
	kill(vs, victims)

func can_counter(p: Player) -> bool:
	return p.tested and holds(p, "short") and holds(p, "long") and holds(p, "counter")

func kill(victims: Array, by_map: Dictionary) -> void:
	var vs := victims.filter(func(v): return v.alive)
	for v in vs:
		var cap := can_counter(v)
		v.alive = false
		var killer = by_map.get(v.id, null)
		v.eliminated_by = killer.id if killer != null else -1
		v.eliminated_turn = turn_no
		var by_other: bool = killer != null and killer != v
		if by_other:
			killer.kills += 1
		var names: Array = v.hand.map(func(c): return card_name(c))
		var msg := "%s is ELIMINATED%s." % [v.name, (" by " + killer.name) if by_other else ""]
		if not names.is_empty():
			msg += " Their hand is revealed: %s." % ", ".join(names)
		log_msg(msg, "death")
		for c in v.hand:
			c.pub = true
			out.append(c)
		v.hand = []
		event.emit("death", {"p": v, "by": killer})
		if cap:
			counter_q.append({"p": v, "by": killer})

func settle() -> void:
	while counter_q.size() > 0 and prompt.is_empty():
		var q = counter_q.pop_front()
		var targets := alive_list()
		if targets.is_empty():
			continue
		if q.p.human:
			prompt = {"type": "counter", "player": q.p, "options": targets.map(func(t): return t.id), "by": q.by}
			break
		do_counter(q.p, ai_counter_target(q.p, q.by, targets))
	check_over()

func do_counter(p: Player, target: Player) -> void:
	log_msg("%s's COUNTER-STRIKE fires from beyond the grave at %s!" % [p.name, target.name], "attack")
	event.emit("attack", {"attacker": p, "type": "counter", "target": target})
	kill([target], {target.id: p})

func choose_counter(target_id: int) -> bool:
	if prompt.is_empty() or prompt.type != "counter" or not prompt.options.has(target_id):
		return false
	var pl: Player = prompt.player
	prompt = {}
	do_counter(pl, by_id(target_id))
	settle()
	return true

func check_over() -> void:
	if over or not prompt.is_empty() or counter_q.size() > 0:
		return
	var al := alive_list()
	if al.size() <= 1:
		end_game("last" if al.size() == 1 else "annihilation")

func end_game(kind: String) -> void:
	over = true
	result = {"kind": kind, "survivors": alive_list().map(func(p): return p.id)}
	event.emit("over", result)

# ---------------------------------------------------------------- turn flow
func end_turn() -> void:
	if over:
		return
	var n := players.size()
	var i := turn
	while true:
		i = (i + 1) % n
		if players[i].alive:
			break
	if i <= turn:
		round_no += 1
	turn = i
	turn_no += 1
	phase = "play"
	int_checked = false
	fog_active = false
	fog_choices = {}
	if turn_no > 500 and not over:
		log_msg("After a very long standoff, the players agree to stop.")
		end_game("ceasefire")
		return
	event.emit("turn", {"p": cur()})

func _after_play() -> void:
	if over:
		return
	if mode == "slow":
		phase = "war"
	elif mode == "fog":
		begin_fog()
	else:
		end_turn()

func play_research(p: Player) -> bool:
	if not research(p):
		return false
	_after_play()
	return true

func play_give(p: Player, card_id: int, target_id: int) -> bool:
	if not proliferate(p, card_id, target_id):
		return false
	_after_play()
	return true

func play_disarm(p: Player, card_id: int) -> bool:
	if not disarm(p, card_id):
		return false
	_after_play()
	return true

func play_skip(p: Player) -> bool:
	log_msg("%s has no legal play action and skips." % p.name)
	_after_play()
	return true

## c: {kind: "pass"|"test"|"attack", type?, target?}
func apply_war(p: Player, c: Dictionary) -> void:
	if c.kind == "test":
		do_test(p)
	elif c.kind == "attack":
		for av in attack_types(p, false):
			if av.type == c.type and (c.type == "plague" or av.targets.has(int(c.get("target", -1)))):
				perform_attacks([{"p": p, "type": c.type, "target": int(c.get("target", -1))}])
				break
	else:
		log_msg("%s: no action." % p.name, "quiet")
	settle()

func human_war(c: Dictionary) -> bool:
	if phase != "war":
		return false
	apply_war(cur(), c)
	if not over and prompt.is_empty():
		end_turn()
	return true

## Out-of-turn test/attack (Fast mode, or Superpower in Slow/Fog) and Fast-mode instant actions.
func instant(p: Player, c: Dictionary, interrupt: bool = true) -> bool:
	if over or not p.alive or not prompt.is_empty():
		return false
	if c.kind == "test":
		if not do_test(p):
			return false
		settle()
		return true
	if c.kind == "attack":
		for av in attack_types(p, interrupt):
			if av.type == c.type and (c.type == "plague" or av.targets.has(int(c.get("target", -1)))):
				perform_attacks([{"p": p, "type": c.type, "target": int(c.get("target", -1))}])
				settle()
				return true
	return false

func run_interrupts() -> bool:
	var acted := false
	if mode == "fast":
		return false
	for p in alive_list():
		if p.human or over:
			continue
		if attack_types(p, true).is_empty():
			continue
		var c := ai_war_choice(p, true)
		if c.kind == "attack":
			if instant(p, c, true):
				acted = true
	return acted

# ---- fog of war
func begin_fog() -> void:
	phase = "fog"
	fog_active = true
	fog_choices = {}
	for p in players:
		if p.alive and not p.human:
			fog_choices[p.id] = ai_war_choice(p, false)
	for p in players:
		if p.alive and p.human:
			if not can_test(p) and attack_types(p, false).is_empty():
				fog_choices[p.id] = {"kind": "pass"}
	event.emit("fog", {})

func submit_fog(pid: int, choice: Dictionary) -> bool:
	if phase != "fog" or not fog_active:
		return false
	fog_choices[pid] = choice
	return true

func fog_pending() -> Array:
	if phase != "fog" or not fog_active:
		return []
	return players.filter(func(p): return p.alive and not fog_choices.has(p.id))

func describe_choice(c: Dictionary) -> String:
	if c.kind == "test":
		return "Nuclear Test"
	if c.kind == "attack":
		if c.type == "plague":
			return "PLAGUE attack"
		var t := by_id(int(c.target))
		return "Attack on %s" % t.name
	return "no action"

func resolve_fog() -> void:
	var orders: Array = []
	for p in players:
		if p.alive:
			orders.append({"p": p, "c": fog_choices.get(p.id, {"kind": "pass"})})
	log_msg("— FOG LIFTS: orders revealed —", "fog")
	for o in orders:
		log_msg("%s: %s" % [o.p.name, describe_choice(o.c)], "fog")
	# Validate everything against the state at the start of the round.
	var tests: Array = []
	for o in orders:
		if o.c.kind == "test" and can_test(o.p):
			tests.append(o)
	var atks: Array = []
	for o in orders:
		if o.c.kind != "attack":
			continue
		var ok := false
		for av in attack_types(o.p, false):
			if av.type == o.c.type and (o.c.type == "plague" or av.targets.has(int(o.c.target))):
				ok = true
				break
		if ok:
			atks.append({"p": o.p, "type": o.c.type, "target": int(o.c.get("target", -1))})
		else:
			log_msg("%s's attack fizzles — they lacked what it takes." % o.p.name, "quiet")
	for o in tests:
		do_test(o.p)
	if not atks.is_empty():
		perform_attacks(atks)
	fog_active = false
	fog_choices = {}
	settle()
	if not over and prompt.is_empty():
		end_turn()

# ---------------------------------------------------------------- AI
func _unseen(viewer: Player) -> Dictionary:
	var cnt: Dictionary = total.duplicate()
	for c in viewer.hand:
		cnt[c.key] -= 1
	for c in out:
		cnt[c.key] -= 1
	for pl in players:
		for c in pl.table:
			cnt[c.key] -= 1
		if pl != viewer:
			for c in pl.hand:
				if c.pub:
					cnt[c.key] -= 1
	var n := 0
	for k in cnt.keys():
		cnt[k] = maxi(0, int(cnt[k]))
		n += cnt[k]
	return {"cnt": cnt, "N": n}

func _p_hold(m: int, n: int, h: int) -> float:
	if m <= 0 or h <= 0 or n <= 0:
		return 0.0
	if h >= n:
		return 1.0
	var q := 1.0
	for i in range(h):
		q *= maxf(0.0, float(n - m - i)) / float(n - i)
	return 1.0 - q

## Only a Fast-mode Superpower holder may examine hands.
func _perfect(viewer: Player) -> bool:
	return mode == "fast" and viewer.tested and has_all_caps(viewer)

func belief(viewer: Player) -> Dictionary:
	var u := _unseen(viewer)
	return {"viewer": viewer, "cnt": u.cnt, "N": u.N}

func bp(B: Dictionary, X: Player, key: String) -> float:
	var viewer: Player = B.viewer
	if X == viewer or _perfect(viewer):
		return 1.0 if holds(X, key) else 0.0
	if key == "labs" and plagued and X.alive:
		return 1.0
	for c in X.table:
		if c.key == key:
			return 1.0
	var h := 0
	for c in X.hand:
		if c.key == key and c.pub:
			return 1.0
		if not c.pub:
			h += 1
	return _p_hold(int(B.cnt.get(key, 0)), int(B.N), h)

func readiness(B: Dictionary, X: Player) -> float:
	if X.tested:
		return 1.0
	var all := 1.0
	for k in TECH:
		all *= bp(B, X, k)
	return all * 0.5

## How likely X can eliminate `target` imminently.
func threat_on(B: Dictionary, X: Player, target: Player) -> float:
	if not X.alive or X == target:
		return 0.0
	var r := readiness(B, X)
	var nb := neighbors_of(X).has(target)
	var ps := bp(B, X, "short")
	var pl := bp(B, X, "long")
	var nuc := r * (ps if nb else ps * pl)
	var plag := 0.0
	if bio != "off":
		var base := bp(B, X, "labs") * bp(B, X, "plague")
		var gate := 1.0
		if bio == "2000":
			gate = r * ps * pl * bp(B, X, "counter") * bp(B, X, "super")
		plag = base * gate * (1.0 - bp(B, target, "labs"))
	return clampf(1.0 - (1.0 - nuc) * (1.0 - plag), 0.0, 1.0)

func revenge_prob(B: Dictionary, X: Player) -> float:
	return readiness(B, X) * bp(B, X, "short") * bp(B, X, "long") * bp(B, X, "counter")

func _noise(p: Player) -> float:
	return (rng.randf() - 0.5) * 2.0 * float(p.persona.noise)

func score_nuke(B: Dictionary, p: Player, x: Player) -> float:
	var pe := p.persona
	var t := threat_on(B, x, p)
	var rev := revenge_prob(B, x)
	var al := alive_list()
	var s: float = float(pe.fear) * t + float(pe.aggr) * 0.6 - float(pe.caution) * 1.5 * rev + (0.35 if al.size() == 2 else 0.0)
	if al.size() >= 3:
		for y in others(p):
			if y == x:
				continue
			var ty := threat_on(B, y, p)
			if ty > t:
				s -= 0.25 * (ty - t)
	return s + _noise(p)

func score_plague(B: Dictionary, p: Player) -> float:
	var pe := p.persona
	var os := others(p)
	if os.is_empty():
		return -9.0
	var exp := 0.0
	var rev := 0.0
	var max_t := 0.0
	for x in os:
		var die := 1.0 - bp(B, x, "labs")
		exp += die
		rev += die * revenge_prob(B, x)
		max_t = maxf(max_t, threat_on(B, x, p))
	var frac := exp / os.size()
	return 0.9 * frac + 0.3 * float(pe.aggr) + 0.3 * float(pe.fear) * max_t - 1.2 * float(pe.caution) * minf(1.0, rev) - 0.3 + _noise(p)

func ai_war_choice(p: Player, interrupt: bool = false) -> Dictionary:
	var pe := p.persona
	var pass_c := {"kind": "pass"}
	var B := belief(p)
	if not interrupt and can_test(p):
		var any_tested := false
		for x in others(p):
			if x.tested:
				any_tested = true
		var cap_count := 0
		for k in CAPS:
			if holds(p, k):
				cap_count += 1
		var prob := clampf(0.30 + 0.40 * float(pe.aggr) + 0.35 * (1.0 if any_tested else 0.0) + 0.06 * cap_count, 0.0, 0.95)
		if rng.randf() < prob:
			return {"kind": "test"}
	var best = null
	var best_score := -9.0
	for o in attack_types(p, interrupt):
		if o.type == "plague":
			var s := score_plague(B, p) - 0.02
			if s > best_score:
				best_score = s
				best = {"kind": "attack", "type": "plague", "target": -1}
			continue
		var pen := 0.0 if o.type == "short" else (0.01 if o.type == "long" else 0.02)
		for tid in o.targets:
			var s2 := score_nuke(B, p, by_id(tid)) - pen
			if s2 > best_score:
				best_score = s2
				best = {"kind": "attack", "type": o.type, "target": tid}
	if best != null and best_score > 0.35:
		return best
	return pass_c

func ai_counter_target(p: Player, by: Player, targets: Array) -> Player:
	if by != null and by.alive and by != p:
		return by
	var B := belief(p)
	var best: Player = targets[0]
	var best_s := -99.0
	for t in targets:
		var s: float = (1.0 if t.tested else 0.0) + bp(B, t, "short") * 0.5
		if s > best_s:
			best_s = s
			best = t
	return best

func usefulness(p: Player, c: Dictionary) -> float:
	var n := 0
	for x in p.hand:
		if x.key == c.key:
			n += 1
	for x in p.table:
		if x.key == c.key:
			n += 1
	var dup := n > 1
	var k: String = INFO[c.key].kind
	if k == "tech":
		return 0.05 if p.tested else (0.25 if dup else 1.0)
	if k == "cap":
		if dup:
			return 0.25
		return {"short": 0.9, "long": 0.8, "counter": 0.75, "super": 0.85}[c.key]
	return 0.25 if dup else 0.85

func least_useful(p: Player):
	var best = null
	var best_s := 99.0
	for c in p.hand:
		var s := usefulness(p, c) + (rng.randf() - 0.5) * 0.02
		if s < best_s:
			best_s = s
			best = c
	return best

func maybe_reveal(p: Player) -> void:
	var pe := p.persona
	var any_tested := false
	for x in others(p):
		if x.tested:
			any_tested = true
	var cands: Array = p.hand.filter(func(c): return not c.pub and INFO[c.key].kind == "cap")
	if cands.is_empty() or not p.tested:
		return
	if rng.randf() < float(pe.reveal) * (1.0 if any_tested else 0.3):
		var order := ["super", "counter", "long", "short"]
		cands.sort_custom(func(a, b): return order.find(a.key) < order.find(b.key))
		reveal(p, cands[0].id)

func ai_play(p: Player) -> bool:
	var pe := p.persona
	maybe_reveal(p)
	var r := rng.randf()
	var B := belief(p)
	if p.hand.size() >= 7 and r < 0.7:
		var c = least_useful(p)
		if c != null:
			return play_disarm(p, c.id)
	if p.hand.size() >= 2 and r < float(pe.gift):
		var c2 = least_useful(p)
		var weakest: Player = null
		var wt := 99.0
		for o in others(p):
			var t := threat_on(B, o, p)
			if t < wt:
				wt = t
				weakest = o
		if c2 != null and weakest != null and usefulness(p, c2) < 0.5:
			return play_give(p, c2.id, weakest.id)
	if not deck.is_empty():
		return play_research(p)
	var c3 = least_useful(p)
	if c3 != null:
		return play_disarm(p, c3.id)
	return play_skip(p)

## Fast mode: an AI looks at the table and may Test/Attack right now.
func ai_fast_tick(p: Player) -> bool:
	if mode != "fast" or over or not prompt.is_empty() or not p.alive or p.human:
		return false
	var c := ai_war_choice(p, false)
	if c.kind == "pass":
		return false
	return instant(p, c, false)

func _ai_agrees_ceasefire(p: Player) -> bool:
	var B := belief(p)
	var opts := attack_types(p, false)
	if not opts.is_empty() and float(p.persona.aggr) > 0.45 and rng.randf() < 0.7:
		return false
	var max_t := 0.0
	for x in others(p):
		max_t = maxf(max_t, threat_on(B, x, p))
	if max_t > 0.55 and not opts.is_empty():
		return false
	return rng.randf() < 0.9

func propose_ceasefire(proposer: Player) -> Dictionary:
	var agrees: Array = []
	var refuses: Array = []
	for p in others(proposer):
		if p.human:
			agrees.append(p)
		elif _ai_agrees_ceasefire(p):
			agrees.append(p)
		else:
			refuses.append(p)
	if refuses.is_empty():
		log_msg("%s proposes to stop. Everyone agrees." % proposer.name)
		end_game("ceasefire")
	else:
		var names: Array = refuses.map(func(p): return p.name)
		log_msg("%s proposes to stop. %s refuse%s." % [proposer.name, " and ".join(names), "s" if refuses.size() == 1 else ""])
	return {"agrees": agrees, "refuses": refuses}

# ---------------------------------------------------------------- driver
## What does the game need next? "over" | "prompt" | "human" | "ai"
func status() -> String:
	if over:
		return "over"
	if not prompt.is_empty():
		return "prompt"
	# The player whose turn it is may have been eliminated mid-turn (interrupt, Fast attack, Plague).
	if phase != "fog" and not cur().alive:
		end_turn()
		return status()
	if phase == "play" and not int_checked:
		int_checked = true
		if run_interrupts():
			check_over()
			return status()   # re-evaluate: someone (maybe the current player) may now be dead
	if phase == "fog":
		for p in fog_pending():
			if p.human:
				return "human"
		return "ai"
	return "human" if cur().human else "ai"

## Perform the next AI step.
func step() -> String:
	var s := status()
	if s == "over" or s == "prompt" or s == "human":
		return s
	if phase == "play":
		var p := cur()
		if p.human:
			return "human"
		ai_play(p)
	elif phase == "war":
		var p2 := cur()
		apply_war(p2, ai_war_choice(p2, false))
		if not over and prompt.is_empty():
			end_turn()
	elif phase == "fog":
		resolve_fog()
	check_over()
	return "ok"

## Legal-action summary for the UI.
func legal(p: Player, interrupt: bool = false) -> Dictionary:
	return {
		"can_research": not deck.is_empty(),
		"can_test": can_test(p),
		"attacks": attack_types(p, interrupt),
		"can_peek": mode == "fast" and p.alive and p.tested and has_all_caps(p),
		"can_counter": can_counter(p),
	}
