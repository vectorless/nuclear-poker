class_name NPGame
extends RefCounted
## Nuclear Poker — rules engine + AI (pure logic, no nodes), ported from the JS prototype.
## Original game: Vinay Gupta & Dan Carter (GNU FDL).
## Kept free of any UI so a lobby server can run it later (e.g. as a headless Godot instance).
## Only the Classic game is implemented here; the Slow/Fog/Fast WAR modes and the Biowar expansions
## were removed for now - they are in git history at the tag `all-modes`.

signal event(type: String, data: Dictionary)

const TECH := ["uranium", "refinement", "warhead", "testing"]
const CAPS := ["short", "long", "counter", "super"]

const INFO := {
	"uranium": {"name": "Uranium", "kind": "tech"},
	"refinement": {"name": "Refinement", "kind": "tech"},
	"warhead": {"name": "Warhead", "kind": "tech"},
	"testing": {"name": "Testing", "kind": "tech"},
	"short": {"name": "Short-range", "kind": "cap"},
	"long": {"name": "Long-range", "kind": "cap"},
	"counter": {"name": "Counter-strike", "kind": "cap"},
	"super": {"name": "Superpower", "kind": "cap"},
}

const PERSONAS := {
	"hawk": {"id": "hawk", "name": "General Volkov", "title": "The Hawk", "trade": 0.35, "honest": 0.45, "aggr": 0.80, "fear": 0.50, "caution": 0.20, "noise": 0.10, "color": "#d9534f"},
	"dove": {"id": "dove", "name": "Dr. Okafor", "title": "The Deterrer", "trade": 0.70, "honest": 0.85, "aggr": 0.22, "fear": 0.95, "caution": 0.85, "noise": 0.08, "color": "#4aa3df"},
	"opp": {"id": "opp", "name": "Ambassador Lin", "title": "The Opportunist", "trade": 0.55, "honest": 0.65, "aggr": 0.50, "fear": 0.75, "caution": 0.50, "noise": 0.10, "color": "#e0a526"},
	"wild": {"id": "wild", "name": "President Reyes", "title": "The Wildcard", "trade": 0.60, "honest": 0.40, "aggr": 0.55, "fear": 0.40, "caution": 0.10, "noise": 0.35, "color": "#9b6bd1"},
	# The three strategists think three levels deep (mind 3): what they believe, what they think the
	# others think of them, and how the others will read each move before they make it.
	"pacifist": {"id": "pacifist", "name": "Minister Haddad", "title": "The Pacifist", "trade": 0.75, "honest": 0.98, "aggr": 0.0, "fear": 0.60, "caution": 0.90, "noise": 0.05,
		"ally": 0.9, "peace": 1.0, "mind": 3, "want": {"counter": 0.9, "long": 0.6, "super": 0.6}, "color": "#7fc8a9"},
	"peacemaker": {"id": "peacemaker", "name": "Ambassador Raman", "title": "The Peacemaker", "trade": 0.80, "honest": 0.92, "aggr": 0.08, "fear": 0.50, "caution": 0.80, "noise": 0.06,
		"ally": 1.0, "peace": 0.85, "mind": 3, "want": {"counter": 1.3, "long": 0.5}, "color": "#e8c46a"},
	"schemer": {"id": "schemer", "name": "Chancellor Hartono", "title": "The Schemer", "trade": 0.65, "honest": 0.60, "aggr": 0.55, "fear": 0.35, "caution": 0.45, "noise": 0.08,
		"ally": 0.7, "peace": 0.1, "mind": 3, "color": "#c97b4a"},
}
## What a character is like when it has no dossier (the human player, as the AIs see them).
const NEUTRAL := {"trade": 0.5, "honest": 0.6, "aggr": 0.5, "fear": 0.5, "caution": 0.5, "noise": 0.0, "ally": 0.5, "peace": 0.4, "mind": 1}

## A player's character, with defaults for the dials the older dossiers do not set:
##   ally   how much it seeks alliances and spends on them
##   peace  how much it values a table where nobody dies (its "least worst" outcome)
##   mind   how many levels deep it thinks (1 reacts, 2 minds its reputation, 3 foresees reactions)
func pe_of(p: Player) -> Dictionary:
	if p.human or p.persona.is_empty():
		return NEUTRAL
	return p.persona

func pv(p: Player, key: String) -> float:
	return float(pe_of(p).get(key, NEUTRAL.get(key, 0.5)))

class Player:
	var id: int = 0
	var name: String = ""
	var human: bool = false
	var persona: Dictionary = {}
	var hand: Array = []
	var table: Array = []
	var trade: Array = []             # cards in this player's trade area (everyone can see them)
	var alive: bool = true
	var tested: bool = false
	var kills: int = 0
	var eliminated_by: int = -1
	var eliminated_turn: int = -1

var rng := RandomNumberGenerator.new()
var players: Array = []
var deck: Array = []              # draw from the END of the array
var out: Array = []               # cards set aside from eliminated players
var log_entries: Array = []
var turn: int = 0
var turn_no: int = 1
var round_no: int = 1
var phase: String = "play"        # honour | play | war
var debts: Array = []             # {from, to, got, pledge} - `to` owes `from` a card on their next turn
var war_queue: Array = []         # player ids still to declare in this exchange window
var last_threat: Dictionary = {}  # player id -> turn_no of their last threat (AI cooldown)
var over: bool = false
var result: Dictionary = {}
var prompt: Dictionary = {}       # pending human decision: counter | trade | threat | demand
var counter_q: Array = []
var next_card_id: int = 1
var total: Dictionary = {}
# Hidden trust. trust["v:t"] = how far player v trusts player t (0..1). Never shown in the UI.
# Breaking a deal costs a lot of trust with the victim and some with everyone who saw it; keeping
# a deal earns a little back. Low trust makes AIs less willing to deal with you, less honest
# with you, slower to agree to stand down - and more willing to threaten or attack you.
const TRUST_START := 0.6
var trust: Dictionary = {}
# Voluntary disarmament. pid -> turn_no it disarmed of its own accord; cleared if it re-arms by
# attacking or threatening again (a breach of faith).
var disarmed: Dictionary = {}
# Stalemate: the turn_no at which the table last changed (a draw, test, attack, death, completed or
# broken deal, disarmament). With the draw pile empty and nothing changing for three full rounds (STALEMATE_ROUNDS), it ends.
var last_progress: int = 1
const STALEMATE_ROUNDS := 3

func _progress() -> void:
	last_progress = turn_no

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

# ---------------------------------------------------------------- trust (hidden)
func trust_of(viewer: Player, target: Player) -> float:
	return float(trust.get("%d:%d" % [viewer.id, target.id], TRUST_START))

## Every shift in trust is also booked where others can reason about it: `rep` holds the public
## part (deals kept or broken, disarmament, condemnation, threats - the whole table saw them) and
## `fav` the private part (the quality of a card that changed hands, known only to the two partners).
## Nobody reads anyone's real `trust`; a thinking AI reads these to work out how it is seen.
var rep: Dictionary = {}
var fav: Dictionary = {}

func _shift_trust(viewer: Player, target: Player, delta: float, secret := false) -> void:
	if viewer == target:
		return
	var k := "%d:%d" % [viewer.id, target.id]
	trust[k] = clampf(trust_of(viewer, target) + delta, 0.0, 1.0)
	var ledger: Dictionary = fav if secret else rep
	ledger[k] = float(ledger.get(k, 0.0)) + delta

## How much `x` trusts `y`, as `viewer` can work it out: the public record, plus the favours
## between x and y when the viewer is one of them. Never the hidden truth.
func est_trust(viewer: Player, x: Player, y: Player) -> float:
	if x == y:
		return 1.0
	var k := "%d:%d" % [x.id, y.id]
	var t := TRUST_START + float(rep.get(k, 0.0))
	if viewer == x or viewer == y:
		t += float(fav.get(k, 0.0))
	return clampf(t, 0.0, 1.0)

func est_warmth(viewer: Player, x: Player, y: Player) -> float:
	return maxf(0.0, est_trust(viewer, x, y) - TRUST_START)

func est_grudge(viewer: Player, x: Player, y: Player) -> float:
	return maxf(0.0, TRUST_START - est_trust(viewer, x, y))

## A deal was kept (true) or broken (false) by `by`, at the expense of `victim`. Everyone sees it.
func _deal_outcome(by: Player, victim: Player, kept: bool) -> void:
	for v in players:
		if v == by:
			continue
		if v == victim:
			_shift_trust(v, by, 0.12 if kept else -0.45)
		else:
			_shift_trust(v, by, 0.04 if kept else -0.15)

## Goodwill: above the starting level, trust turns into an alliance. 0 = neutral, up to 0.4 for a
## partner who has dealt honestly again and again. Allies are spared, favoured as trading partners,
## dealt with honestly and listened to when they propose to stand down.
func warmth(viewer: Player, target: Player) -> float:
	return maxf(0.0, trust_of(viewer, target) - TRUST_START)

## A card arrives in a trade: the more `receiver` needed it, the warmer it feels towards `giver`.
## A card it really wanted (a missing Technology or Capability) builds goodwill; a duplicate or
## a card it has no use for is neutral. Only the two partners know what changed hands (face down).
func _favour(receiver: Player, giver: Player, c: Dictionary) -> void:
	_shift_trust(receiver, giver, 0.16 * maxf(0.0, _gain(receiver, c) - 0.4), true)

## ---- disarmament (every reaction is shaped by the observer's character)
func is_disarmed(x: Player) -> bool:
	return disarmed.has(x.id) and caps_held(x).is_empty()

## p disarmed of its own accord: a costly, public signal of peaceful intent. Cautious, fearful powers
## warm to it most; hawks barely care.
func _on_disarm(p: Player) -> void:
	disarmed[p.id] = turn_no
	for v in others(p):
		var pe := pe_of(v)
		_shift_trust(v, p, 0.04 + 0.14 * float(pe.caution) + 0.04 * float(pe.fear) - 0.05 * float(pe.aggr))

## Someone who disarmed turns to force again: treated almost like a broken deal by everyone.
func _breach_of_faith(p: Player) -> void:
	if not disarmed.has(p.id):
		return
	disarmed.erase(p.id)
	log_msg("%s takes up arms again after disarming - a breach of faith." % p.name, "reveal")
	for v in others(p):
		var pe := pe_of(v)
		_shift_trust(v, p, -(0.2 + 0.15 * float(pe.caution)))

## Attacking a power that disarmed: the table condemns it, the cautious most of all.
func _condemn(attacker: Player, victim: Player) -> void:
	log_msg("The world condemns %s's attack on %s, a disarmed power." % [attacker.name, victim.name], "reveal")
	for v in others(attacker):
		if v == victim:
			continue
		var pe := pe_of(v)
		_shift_trust(v, attacker, -(0.18 + 0.2 * float(pe.caution) - 0.08 * float(pe.aggr)))

## Would AI p lay down its weapons now? Peaceful, cautious characters do when they feel safe and
## trust the table - more readily once others have gone first. Hawks almost never do.
func ai_maybe_disarm(p: Player) -> bool:
	if p.human or not can_disarm(p) or not prompt.is_empty():
		return false
	var pe := p.persona
	var B := belief(p)
	var max_t := 0.0
	var trust_sum := 0.0
	var n := 0
	var others_disarmed := 0
	for x in others(p):
		max_t = maxf(max_t, threat_on(B, x, p))
		trust_sum += trust_of(p, x)
		n += 1
		if is_disarmed(x):
			others_disarmed += 1
	if n == 0 or max_t > 0.3:
		return false
	var avg_trust := trust_sum / n
	var pr := (0.03 + 0.12 * float(pe.caution) + 0.06 * others_disarmed) * (1.0 - float(pe.aggr)) * clampf((avg_trust - 0.45) * 4.0, 0.0, 1.5)
	if is_superpower(p):
		pr *= 0.3
	if rng.randf() < pr:
		return disarm_caps(p)
	return false

## 0 = no grievance; up to ~0.6 for someone who has betrayed this player repeatedly.
func grudge(viewer: Player, target: Player) -> float:
	return maxf(0.0, TRUST_START - trust_of(viewer, target))

## Multiplier for how much a promised (deferred) card from `partner` is worth to `viewer`.
func _pledge_faith(viewer: Player, partner: Player) -> float:
	return clampf((trust_of(viewer, partner) - 0.1) / (TRUST_START - 0.1), 0.0, 1.15)

# ---------------------------------------------------------------- setup
## opts: {seed?, players: [{name, human, persona}]}
func setup(opts: Dictionary) -> void:
	if opts.has("seed"):
		rng.seed = int(opts["seed"])
	else:
		rng.randomize()
	var plist: Array = opts["players"]
	var n := plist.size()
	for s in range(n + 1):
		for k in TECH + CAPS:
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
	_progress()
	log_msg("%s researches (draws a card)." % p.name)
	event.emit("draw", {"p": p, "c": c})
	_reveal_super(p)
	return true

func _take_hand_card(p: Player, card_id: int):
	for i in range(p.hand.size()):
		if p.hand[i].id == card_id:
			return p.hand.pop_at(i)
	return null

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
	_progress()
	log_msg("%s performs a NUCLEAR TEST — all four Technologies on the table." % p.name, "test")
	event.emit("test", {"p": p})
	_reveal_super(p)
	return true

# ---------------------------------------------------------------- attacks
## One weapon per turn: a player who is not a Superpower may fire only one attack card in each turn's
## exchange window. A Superpower may strike again and again.
var attacked_on: Dictionary = {}      # player id -> turn_no of their last attack

func is_superpower(p: Player) -> bool:
	return p.tested and has_all_caps(p)

## A Superpower hides nothing: the moment a power has tested and holds all four Capabilities, they
## go on the table beside its Technologies, for all to see. Returns true the first time this happens.
func _reveal_super(p: Player) -> bool:
	if not p.alive or not is_superpower(p):
		return false
	if _show_cards(p, CAPS).is_empty():
		return false
	log_msg("%s is a NUCLEAR SUPERPOWER - all four Capabilities on the table." % p.name, "test")
	event.emit("superpower", {"p": p})
	return true

func _reveal_supers() -> void:
	for p in players:
		_reveal_super(p)

func fired_this_turn(p: Player) -> bool:
	return int(attacked_on.get(p.id, -1)) == turn_no

## Returns [{type, targets:[ids]}]. `ignore_limit`: what p could fire at all (used for threats).
func attack_types(p: Player, ignore_limit := false) -> Array:
	var outl: Array = []
	if not p.alive or not p.tested:
		return outl
	if not ignore_limit and fired_this_turn(p) and not is_superpower(p):
		return outl
	if has_all_caps(p):      # a Superpower's strike reaches anyone and spends nothing: its only weapon worth the name
		outl.append({"type": "super", "targets": others(p).map(func(x): return x.id)})
		return outl
	if holds(p, "short"):
		outl.append({"type": "short", "targets": neighbors_of(p).map(func(x): return x.id)})
	if holds(p, "short") and holds(p, "long"):
		outl.append({"type": "long", "targets": others(p).map(func(x): return x.id)})
	return outl

func reveal_keys(type: String) -> Array:
	match type:
		"short": return ["short"]
		"long": return ["short", "long"]
		"super": return CAPS.duplicate()
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

## list: [{p, type, target}] — all validated against the pre-state; resolved together.
func perform_attacks(list: Array) -> void:
	_progress()
	var victims := {}   # victim id -> attacker
	for a in list:
		_breach_of_faith(a.p)
		if int(a.target) >= 0 and is_disarmed(by_id(int(a.target))):
			_condemn(a.p, by_id(int(a.target)))
		var shown := _show_cards(a.p, reveal_keys(a.type))
		var tgt = null
		if int(a.target) >= 0:
			tgt = by_id(int(a.target))
		var suffix := ""
		if not shown.is_empty():
			suffix = " (shows %s)" % ", ".join(shown)
		var label: String = {"short": "Short-range", "long": "Long-range", "super": "Superpower"}[a.type]
		log_msg("%s launches a %s ATTACK on %s%s!" % [a.p.name, label, tgt.name, suffix], "attack")
		if tgt != null and tgt.alive:
			victims[tgt.id] = a.p
		event.emit("attack", {"attacker": a.p, "type": a.type, "target": tgt})
		attacked_on[a.p.id] = turn_no
		_spend_weapon(a.p, a.type)
	var vs: Array = []
	for id in victims.keys():
		vs.append(by_id(id))
	kill(vs, victims)

## Firing a weapon destroys it: a Short-range attack uses up the Short-range card, a Long-range
## attack the Long-range card (Short-range is only a prerequisite and stays). A Superpower attack
## spends nothing - a Superpower can strike again and again. Spent cards leave the game.
const SPENT := {"short": "short", "long": "long"}

func _spend_weapon(p: Player, type: String) -> void:
	if not SPENT.has(type) or is_superpower(p):
		return      # a Superpower spends nothing, whichever weapon it fires
	var key: String = SPENT[type]
	for arr in [p.table, p.hand]:
		for i in range(arr.size()):
			if arr[i].key == key:
				var c = arr.pop_at(i)
				c.pub = true
				out.append(c)
				log_msg("%s's %s card is spent." % [p.name, card_name(c)], "quiet")
				event.emit("spent", {"p": p, "c": c})
				return

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
		for tc in v.trade:
			v.hand.append(tc)
		v.trade = []
		var names: Array = v.hand.map(func(c): return card_name(c))
		var msg := "%s is ELIMINATED%s." % [v.name, (" by " + killer.name) if by_other else ""]
		if not names.is_empty():
			msg += " Their hand is revealed: %s." % ", ".join(names)
		log_msg(msg, "death")
		for c in v.hand:
			c.pub = true      # the hand is turned face up and stays on show in their seat

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
	if over:
		return
	_reveal_supers()      # a card may have arrived in a hand by any route; a new Superpower shows its arsenal
	if not prompt.is_empty() or counter_q.size() > 0:
		return
	var al := alive_list()
	if al.size() <= 1:
		end_game("last" if al.size() == 1 else "annihilation")
	elif is_mad():
		log_msg("Every power left is a Superpower: MUTUALLY ASSURED DESTRUCTION. Each can destroy all the others - so none will. All win.", "reveal")
		end_game("mad")
	else:
		var h := hegemon()
		if h != null:
			log_msg("%s is the only Superpower, and no other power holds a single Capability: nobody can stand against it. HEGEMONY - %s wins." % [h.name, h.name], "reveal")
			end_game("hegemony", {"winner": h.id})

## Hegemony: one Superpower left at the table, and every other power still in the game holds no
## Capability card at all - they have laid down their arms, or never took them up. Nobody can challenge
## the Superpower and nobody need die: the game ends and the Superpower wins.
func hegemon() -> Player:
	var al := alive_list()
	if al.size() < 2:
		return null
	var sp: Player = null
	for x in al:
		if is_superpower(x):
			if sp != null:
				return null
			sp = x
		elif not caps_held(x).is_empty():
			return null
	return sp

func end_game(kind: String, extra: Dictionary = {}) -> void:
	over = true
	result = {"kind": kind, "survivors": alive_list().map(func(p): return p.id)}
	result.merge(extra)
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
	war_queue = []
	_void_debts()
	if not _debts_of(cur()).is_empty():
		phase = "honour"
	if deck.is_empty() and not over:
		# Stalemate: nothing left to draw, and three full rounds have gone by without anyone testing,
		# striking, trading or disarming - as long after you are out as while you are still playing.
		var al := alive_list()
		if turn_no - last_progress > al.size() * STALEMATE_ROUNDS:
			log_msg("The draw pile is empty and nothing has changed for three full rounds: no one can - or will - make another move. Stalemate.")
			end_game("stalemate")
			return
	if turn_no > 500 and not over:
		log_msg("After a very long standoff, the players agree to stop.")
		end_game("ceasefire")
		return
	event.emit("turn", {"p": cur()})

func _after_play() -> void:
	if over:
		return
	phase = "war"
	_rebuild_war_queue(turn)

func play_research(p: Player) -> bool:
	if not research(p):
		return false
	_after_play()
	return true

func play_skip(p: Player) -> bool:
	log_msg("%s has no legal play action and skips." % p.name)
	_after_play()
	return true


# ---------------------------------------------------------------- trading
# Draw OR trade each turn. Trades are FACE DOWN: only a card's owner knows what it is, until it arrives.
#   1. you place a card in your trade area, addressed to one player;
#   2. they either decline, or answer by placing a card of their own in THEIR trade area;
#   3. you accept or decline that pair. If you accept, your card goes to them at once, but their card
#      stays in their trade area as a pledge and only reaches you on THEIR next turn - when they may
#      deliver it or break the deal (deception).
# An offer is the turn's move: answered or declined, the exchange window follows.
# After each turn there is an exchange window: starting with the player who just played and going
# clockwise, anyone may test or attack ("nuclear exchanges in order of play" house rule).
func _debts_of(p: Player) -> Array:
	return debts.filter(func(d): return d.to == p.id)

func _trade_card(p: Player, card_id: int):
	for c in p.trade:
		if c.id == card_id:
			return c
	return null

## Put a card from a player's trade area back in their hand.
func _recall(p: Player, card_id: int) -> void:
	for i in range(p.trade.size()):
		if p.trade[i].id == card_id:
			p.hand.append(p.trade.pop_at(i))
			return

func _void_debts() -> void:
	var keep: Array = []
	for d in debts:
		var a := by_id(d.from)
		var b := by_id(d.to)
		var dead: bool = not a.alive or not b.alive
		if dead:
			if b.alive:
				_recall(b, int(d.pledge))      # the pledged card goes home
			continue
		keep.append(d)
	debts = keep

## Start a deal: `p` puts a card face down in their trade area, addressed to `target_id`.
## Returns "declined" | "prompt" (a human must answer) | "accepted" (answered: the deal is done) | "invalid".
func trade_offer(p: Player, card_id: int, target_id: int) -> String:
	if phase != "play" or not p.alive or cur() != p or not prompt.is_empty():
		return "invalid"
	if target_id < 0 or target_id >= players.size():
		return "invalid"
	var t := by_id(target_id)
	if t == p or not t.alive or not p.trade.is_empty():
		return "invalid"
	var x = _take_hand_card(p, card_id)
	if x == null:
		return "invalid"
	x.pub = false      # shown to the player it is offered to, hidden from the rest of the table
	p.trade.append(x)
	log_msg("%s offers %s a card." % [p.name, t.name])
	event.emit("trade_offer", {"from": p, "to": t, "c": x})
	if t.human:
		prompt = {"type": "trade", "player": t, "from": p, "card_id": x.id, "card_key": x.key}      # t may look at it
		return "prompt"
	var yid := ai_counter_offer(t, p, x)
	if yid < 0:
		_cancel_offer(p, t, "%s declines to trade." % t.name)
		_after_play()      # offering was the move, answered or not
		return "declined"
	_place_counter(t, yid, p, x)
	return _decide_pair(p, t, x)

func _place_counter(t: Player, yid: int, p: Player, x: Dictionary) -> void:
	var y = _take_hand_card(t, yid)
	y.pub = false
	t.trade.append(y)
	log_msg("%s answers with a card of their own." % t.name)
	event.emit("trade_counter", {"from": t, "to": p, "c": y})

## The target answered: the deal is done. Offering was the offerer's acceptance - their card goes
## over now, and the answer stays behind as a pledge for the target's next turn.
func _decide_pair(p: Player, t: Player, x: Dictionary) -> String:
	var y = t.trade[t.trade.size() - 1]
	_finish_deal(p, t, x, y)
	_after_play()
	return "accepted"

func _cancel_offer(p: Player, t: Player, msg: String) -> void:
	for c in p.trade.duplicate():
		_recall(p, c.id)
	for c in t.trade.duplicate():
		var pledged := false
		for d in debts:
			if d.pledge == c.id:
				pledged = true
		if not pledged:
			_recall(t, c.id)
	log_msg(msg, "quiet")

func _finish_deal(p: Player, t: Player, x: Dictionary, y: Dictionary) -> void:
	for i in range(p.trade.size()):
		if p.trade[i].id == x.id:
			p.trade.pop_at(i)
			break
	x.pub = false
	_progress()
	_favour(t, p, x)
	t.hand.append(x)
	debts.append({"from": p.id, "to": t.id, "got": x.id, "pledge": y.id})
	_shift_trust(t, p, 0.05)      # they handed their card over first
	log_msg("%s hands a card to %s. %s has pledged a card in return - to be delivered on %s's next turn." % [p.name, t.name, t.name, t.name])
	event.emit("give", {"from": p, "to": t, "c": x})
	_reveal_super(t)

## Human answer to an offer: the card (from their hand) to offer back, or -1 to decline.
func answer_trade(counter_id: int) -> bool:
	if prompt.is_empty() or prompt.get("type", "") != "trade":
		return false
	var pr := prompt
	var p: Player = pr.from
	var t: Player = pr.player
	if counter_id >= 0 and not _take_hand_card_peek(t, counter_id):
		return false
	prompt = {}
	var x = _trade_card(p, int(pr.card_id))
	if counter_id < 0 or x == null or not p.alive:
		_cancel_offer(p, t, "%s declines to trade." % t.name)
		_after_play()      # offering was the move, answered or not
		return true
	_place_counter(t, counter_id, p, x)
	_decide_pair(p, t, x)
	return true

func _take_hand_card_peek(p: Player, card_id: int) -> bool:
	for c in p.hand:
		if c.id == card_id:
			return true
	return false

## The pledged card: deliver it to the creditor (on your own turn)...
func honour(p: Player) -> bool:
	if phase != "honour" or cur() != p:
		return false
	var ds := _debts_of(p)
	if ds.is_empty():
		return false
	var d: Dictionary = ds[0]
	var y = _trade_card(p, int(d.pledge))
	var to := by_id(d.from)
	debts.erase(d)
	_progress()
	if y != null:
		p.trade.erase(y)
		y.pub = false
		_favour(to, p, y)
		to.hand.append(y)
		log_msg("%s DELIVERS the pledged card to %s - the trade is complete." % [p.name, to.name])
		event.emit("give", {"from": p, "to": to, "c": y})
		_deal_outcome(p, to, true)
		_reveal_super(to)
	_next_honour()
	return true

## ... or break the deal and take it back.
func renege(p: Player) -> bool:
	if phase != "honour" or cur() != p:
		return false
	var ds := _debts_of(p)
	if ds.is_empty():
		return false
	var d: Dictionary = ds[0]
	debts.erase(d)
	_progress()
	_recall(p, int(d.pledge))
	log_msg("%s BREAKS the deal with %s and keeps the card promised in return. Deceived!" % [p.name, by_id(d.from).name], "broken")
	_deal_outcome(p, by_id(d.from), false)
	event.emit("renege", {"p": p, "to": by_id(d.from)})
	_next_honour()
	return true

func _next_honour() -> void:
	_void_debts()
	if _debts_of(cur()).is_empty():
		phase = "play"

## What a card you cannot see is worth to p on average (trades are face down).
func _expected_gain(p: Player) -> float:
	var B := belief(p)
	var n := float(B.N)
	if n <= 0.0:
		return 0.5
	var s := 0.0
	for k in B.cnt:
		if int(B.cnt[k]) > 0:
			s += float(B.cnt[k]) / n * _gain(p, {"key": k})
	return s

func _gain(p: Player, c: Dictionary) -> float:
	var dup := holds(p, c.key)
	var k: String = INFO[c.key].kind
	if k == "tech":
		return 0.05 if p.tested else (0.25 if dup else 1.0)
	if k == "cap":
		return 0.25 if dup else {"short": 0.9, "long": 0.8, "counter": 0.75, "super": 0.85}[c.key] * want(p, c.key)
	return 0.25 if dup else 0.85

## AI answering an offer: the id of the card it offers back, or -1 to decline. It has looked at the
## card on offer: one it needs is tempting, a duplicate or a card it has no use for is not.
func ai_counter_offer(t: Player, from: Player, x: Dictionary) -> int:
	if t.hand.is_empty():
		return -1
	var B := belief(t)
	var thr := threat_on(B, from, t)
	var pr := pv(t, "trade") + 0.25 * thr + 0.9 * (_gain(t, x) - 0.5) - 0.8 * grudge(t, from) + 0.6 * warmth(t, from)
	if rng.randf() >= clampf(pr, 0.03, 0.95):
		return -1
	if deep(t):
		# answer with the card that serves the partnership best, not just the one t can most spare
		var best = null
		var best_s := -99.0
		for c in t.hand:
			var s := deal_score(t, from, c, B)
			if s > best_s:
				best_s = s
				best = c
		if best != null:
			return best.id
	var y = least_useful(t)
	return y.id if y != null else -1

## An offer is binding (if they answer, the deal is done), so AI p weighs it before making it:
## its own card against a face-down promise from t (expected value x trust in t).
func ai_would_deal(p: Player, t: Player, x: Dictionary) -> bool:
	var pr := 0.5 + 0.9 * (_expected_gain(p) * _pledge_faith(p, t) - usefulness(p, x) - 0.1) + 0.1 * (float(p.persona.trade) - 0.5)
	return rng.randf() < clampf(pr, 0.05, 0.95)

func ai_honour(p: Player) -> void:
	var ds := _debts_of(p)
	if ds.is_empty():
		return
	var honest := float(p.persona.honest)
	var creditor := by_id(int(ds[0].from))
	honest *= clampf(0.4 + trust_of(p, creditor), 0.3, 1.0)      # less honest with those who cheated before
	honest = minf(0.97, honest + 0.5 * warmth(p, creditor))       # loyal to proven allies
	var y = _trade_card(p, int(ds[0].pledge))
	if y != null and usefulness(p, y) > 0.85:
		honest *= 0.6
	if deep(p):
		if pv(p, "peace") >= 0.95:
			honest = 1.0      # the pacifist's word is her only defence: she never breaks it
		elif pv(p, "peace") >= 0.5:
			honest = maxf(honest, 0.95)      # peace-lovers keep their word
		else:
			# a schemer keeps faith with those it still needs and burns the bridge it no longer does
			var danger := threat_on(belief(p), creditor, p) * clampf((foresee_attack(p, creditor, p) - 0.1) / 0.8, 0.0, 1.0)
			var armed_after: bool = p.tested and (holds(p, "short") or (y != null and y.key == "short"))      # with the pledge back in hand
			if creditor == rival(p) and armed_after:
				honest *= 0.3
			elif danger > 0.3 or est_trust(p, creditor, p) > 0.75:
				honest = maxf(honest, 0.9)
	if rng.randf() < honest:
		honour(p)
	else:
		renege(p)

func ai_play_classic(p: Player) -> bool:
	ai_maybe_disarm(p)
	ai_maybe_propose(p)
	if over or not prompt.is_empty():
		return true
	var B := belief(p)
	if deep(p):
		return _play_deep(p, B)
	var want := false
	if p.hand.size() >= 1:
		if deck.is_empty():
			want = true
		elif p.hand.size() >= 3:
			var lu = least_useful(p)
			if lu != null and usefulness(p, lu) < 0.5 and rng.randf() < float(p.persona.trade) * 0.8:
				want = true
	if want:
		var keyed: Array = []
		for o in others(p):
			if trust_of(p, o) < 0.25:
				continue      # will not deal with a known cheat
			keyed.append({"o": o, "k": threat_on(B, o, p) + _noise(p) * 0.3 - 0.8 * (trust_of(p, o) - TRUST_START)})
		keyed.sort_custom(func(a, b): return a.k < b.k)
		var tries: Array = keyed.map(func(e): return e.o)
		if not deck.is_empty():
			tries = tries.slice(0, 1)
		for t in tries:
			var c = least_useful(p)
			if c == null:
				break
			if not ai_would_deal(p, t, c):
				continue      # an offer commits: only make it to someone whose promise is worth the card
			if trade_offer(p, c.id, t.id) != "invalid":
				return true      # one offer is the move, whatever the answer
	if not deck.is_empty():
		return play_research(p)
	return play_skip(p)

## A thinking player's turn. It weighs every card it could offer to every partner: what it expects
## back, the goodwill the card buys, and - looking through the others' eyes - whether the card would
## arm someone against it, against the table, or (for a schemer) against its rival.
func _play_deep(p: Player, B: Dictionary) -> bool:
	var best = null
	var best_s := 0.15
	for t in others(p):
		if trust_of(p, t) < 0.25:
			continue      # will not deal with a known cheat
		for c in p.hand:
			var s := deal_score(p, t, c, B)
			if s > best_s:
				best_s = s
				best = {"t": t, "c": c}
	if best != null and trade_offer(p, best.c.id, best.t.id) != "invalid":
		return true
	if not deck.is_empty():
		return play_research(p)
	return play_skip(p)

func deal_score(p: Player, t: Player, c: Dictionary, B: Dictionary) -> float:
	var peace := pv(p, "peace")
	var ally := pv(p, "ally")
	var use := usefulness(p, c)
	var s := _expected_gain(p) * _pledge_faith(p, t) - use      # what comes back, less what goes
	var need := _wanted_by(B, t, c.key)      # how much t seems to need this card
	# goodwill, worth more from someone who already trusts me - but nobody gives away what it needs itself
	s += ally * 0.6 * need * (0.5 + est_trust(p, t, p)) * (1.0 - 0.8 * use)
	var arm := foresee_arming(p, t, c)
	s -= (1.2 * peace + 0.3) * arm.others
	s -= (1.5 + 0.5 * peace) * arm.self
	s += (1.0 - peace) * 0.9 * arm.rival      # a schemer arms its rival's enemies
	if INFO[c.key].kind == "tech" and not t.tested:
		s -= peace * 0.8 * (1.0 - readiness(B, t))      # proliferation: another step towards the bomb
	if INFO[c.key].kind == "cap" and t.tested and need > 0.5:
		var calm := 0.0
		for y in others(t):
			calm = maxf(calm, foresee_attack(p, t, y))
		if calm < 0.2:
			s += ally * 0.5      # deterrence for all: arm a power that threatens nobody
	return s + _noise(p) * 0.3

## Would p ask the table to stand down now? Thinking players (mind 2+) do when they want it and can
## foresee - from each other's dossiers and the public record - that everyone would agree.
func ai_maybe_propose(p: Player) -> bool:
	if p.human or over or pv(p, "mind") < 2.0 or not prompt.is_empty() or not can_propose_ceasefire(p):
		return false
	var peace := pv(p, "peace")
	var risk := peril(p, p)
	# nothing to stand down from until the table has gone nuclear - or a strike is plainly coming
	if risk < 0.2 and not players.any(func(x): return x.tested):
		return false
	var wants := 0.1 + 0.6 * peace - 0.4 * pv(p, "aggr") + 0.5 * risk * pv(p, "fear")
	if not attack_types(p, true).is_empty() and risk < 0.1:
		wants -= 0.4 * (1.0 - peace)      # winning: why stop?
	if rng.randf() >= clampf(wants, 0.0, 0.9):
		return false
	for x in others(p):
		if not x.human and ceasefire_score(x, p, p) < 0.5:
			return false      # they would refuse, as far as p can tell
	propose_ceasefire(p)
	return true

## The threatened player decides (human prompt). Refusing changes nothing by itself.
func answer_threat(comply: bool) -> bool:
	if prompt.is_empty() or prompt.get("type", "") != "threat":
		return false
	var pr := prompt
	prompt = {}
	_after_threat(pr.from, _resolve_threat(pr.from, pr.player, comply))
	return true

func _resolve_threat(p: Player, t: Player, comply: bool) -> bool:
	var held := caps_held(t)
	if held.is_empty():
		log_msg("%s has no Capability cards to give up - the threat is empty." % t.name, "quiet")
		return false
	if not comply:
		log_msg("%s REFUSES to disarm." % t.name, "reveal")
		return false
	var names := _return_caps(t)
	log_msg("%s gives in and returns %s to the deck." % [t.name, ", ".join(names)], "reveal")
	event.emit("disarm_all", {"p": t})
	return true

## A forced trade: the threatener has put up a card (`offer`); the threatened player sees it and chooses
## a card of their own to give back (`card_id`), or refuses (-1). The cards swap at once, face down - only
## the two of them know what changed hands. Refusing changes nothing by itself: both keep their cards, and
## the threat is only as good as the threatener's will to strike.
func answer_demand(card_id: int) -> bool:
	if prompt.is_empty() or prompt.get("type", "") != "demand":
		return false
	var pr := prompt
	if card_id >= 0 and not pr.player.hand.any(func(c): return c.id == card_id):
		return false
	prompt = {}
	_after_threat(pr.from, _resolve_demand(pr.from, pr.player, int(pr.offer), card_id))
	return true

func _resolve_demand(p: Player, t: Player, offer_id: int, card_id: int) -> bool:
	if card_id < 0:
		log_msg("%s REFUSES the forced trade." % t.name, "reveal")
		return false
	var x := _take_from_hand(p, offer_id)
	var y := _take_from_hand(t, card_id)
	t.hand.append(x)
	p.hand.append(y)
	_progress()
	log_msg("%s gives in and trades a card with %s." % [t.name, p.name], "reveal")
	event.emit("demand_paid", {"from": t, "to": p, "c": y, "offer": x})
	_reveal_super(p)
	_reveal_super(t)
	return true

func _take_from_hand(p: Player, card_id: int) -> Dictionary:
	for i in range(p.hand.size()):
		if p.hand[i].id == card_id:
			var c: Dictionary = p.hand.pop_at(i)
			c.pub = false
			return c
	return {}

## AI threatened with a forced trade: the id of the card it gives back, or -1 to refuse. Fear makes it give
## in, a card it wants on offer tempts it, a grudge or a counter-strike of its own makes it stand firm. A
## frightened power hands over what it judges the threatener wants most, from what it can see of them; a
## calmer one gives in with its least useful card.
func ai_answer_demand(t: Player, from: Player, offer_id: int) -> int:
	if t.hand.is_empty():
		return -1
	var fear := pv(t, "fear")
	var pr := 0.15 + 0.8 * fear - 0.5 * grudge(t, from) + (0.3 * pv(t, "peace") if deep(t) else 0.0)
	for c in from.hand:
		if c.id == offer_id:
			pr += 0.3 * (_gain(t, c) - 0.5)
	if has_all_caps(from):
		pr += 0.15
	if can_counter(t):
		pr -= 0.3
	if rng.randf() >= clampf(pr, 0.05, 0.9):
		return -1
	if rng.randf() < fear + (0.2 if not can_counter(t) else 0.0):
		var B := belief(t)
		var best = null
		var best_v := -1.0
		for c in t.hand:
			var v := _wanted_by(B, from, c.key) + (rng.randf() - 0.5) * 0.02
			if v > best_v:
				best_v = v
				best = c
		return best.id
	var y = least_useful(t)
	return y.id if y != null else -1

## How much X seems to want a card of kind `key`, as the viewer of belief B sees it: a Technology X
## lacks (worthless once X has tested), or a Capability X is not known to hold.
func _wanted_by(B: Dictionary, X: Player, key: String) -> float:
	if INFO[key].kind == "tech" and X.tested:
		return 0.05
	var base: float = 1.0 if INFO[key].kind == "tech" else {"short": 0.9, "long": 0.8, "counter": 0.75, "super": 0.85}[key]
	return base * (1.0 - bp(B, X, key))

## Shuffle every Capability card (hand and table) back into the deck. Returns their names.
func _return_caps(t: Player) -> Array:
	_progress()
	var names: Array = []
	for arr in [t.hand, t.table]:
		for i in range(arr.size() - 1, -1, -1):
			if INFO[arr[i].key].kind == "cap":
				var c = arr[i]
				arr.remove_at(i)
				c.pub = false
				deck.insert(rng.randi_range(0, deck.size()), c)
				names.append(INFO[c.key].name)
	return names

## Mutually Assured Destruction (the original rules): the moment every power still in the game is a
## Superpower - all eight cards: the four Technologies tested (they never leave the table) and all four
## Capabilities - the game ends and all of them win.
func is_mad() -> bool:
	var al := alive_list()
	return al.size() >= 2 and al.all(func(x): return is_superpower(x))

## Voluntary disarmament is open to a declared nuclear power - one that has made its Nuclear Test -
## holding Capability cards to give up.
func can_disarm(p: Player) -> bool:
	return not over and p.alive and p.tested and not caps_held(p).is_empty()

## Voluntary disarmament - after your own Nuclear Test, at any time: on or off your turn, also while a
## trade or deal is waiting for an answer (only not in the middle of a counter-strike or threat
## decision, which must be answered first).
func disarm_caps(p: Player) -> bool:
	if not can_disarm(p):
		return false
	if not prompt.is_empty() and str(prompt.get("type", "")) != "trade":
		return false
	var names := _return_caps(p)
	log_msg("%s DISARMS - returns %s to the deck." % [p.name, ", ".join(names)], "reveal")
	_on_disarm(p)
	event.emit("disarm_all", {"p": p})
	return true

func ai_comply_threat(t: Player, from: Player) -> bool:
	var held := caps_held(t)
	if held.is_empty():
		return false
	var pr := pv(t, "fear") * 0.7 - 0.06 * held.size() - 0.5 * grudge(t, from)      # won't bow to a cheat
	if has_all_caps(from):
		pr += 0.15
	if can_counter(t):
		pr -= 0.35
	if deep(t):
		pr += 0.5 * pv(t, "peace")      # weapons are not worth a war to a peace-lover
		if can_counter(t) and pv(t, "peace") >= 0.5 and pv(t, "aggr") > 0.0:
			pr -= 0.3      # a peacemaker's deterrent is the one thing it will not give up
	return rng.randf() < clampf(pr, 0.05, 0.9)

## An AI power that will not simply attack may lean on a player it could strike.
func _ai_threat(p: Player, B: Dictionary) -> Dictionary:
	if int(last_threat.get(p.id, -99)) > turn_no - 4:
		return {}
	var best := -1
	var best_v := 0.0
	for tid in threat_targets(p):
		var x := by_id(tid)
		var expcaps := 0.0
		for k in CAPS:
			expcaps += bp(B, x, k)
		var v := expcaps * (1.0 - 0.8 * revenge_prob(B, x)) * (0.5 + float(p.persona.aggr) + grudge(p, x)) * maxf(0.0, 1.0 - 2.0 * warmth(p, x))
		if v > best_v:
			best_v = v
			best = tid
	if best < 0 or best_v <= 0.9 or rng.randf() >= 0.3 + 0.3 * float(p.persona.aggr):
		return {}
	# Leaning on them: force a trade for a card p is missing and they may well hold - or make them disarm.
	var x := by_id(best)
	var need := 0.0
	for k in (CAPS if p.tested else TECH + CAPS):
		if not holds(p, k):
			need = maxf(need, bp(B, x, k))
	if need > 0.2 and not x.hand.is_empty() and not p.hand.is_empty() and rng.randf() < 0.5:
		return {"kind": "demand", "target": best, "offer": least_useful(p).id}
	return {"kind": "threat", "target": best}

func _rebuild_war_queue(start_pid: int) -> void:
	war_queue = []
	var n := players.size()
	for k in range(n):
		var pl: Player = players[(start_pid + k) % n]
		if pl.alive:
			war_queue.append(pl.id)

func war_options(p: Player) -> bool:
	return p.alive and (can_test(p) or not attack_types(p).is_empty() or can_threaten(p))

## Next player in the exchange window with something to declare, or -1 when the window is over.
func war_actor() -> int:
	while not war_queue.is_empty():
		var p := by_id(war_queue[0])
		if war_options(p):
			return p.id
		war_queue.pop_front()
	return -1

## Everyone p could currently attack - a threat is only credible against these.
func threat_targets(p: Player) -> Array:
	var ids := {}
	for av in attack_types(p, true):
		for t in av.targets:
			ids[int(t)] = true
	var out_ids: Array = ids.keys()
	out_ids.sort()
	return out_ids

func caps_held(x: Player) -> Array:
	var res: Array = []
	for arr in [x.hand, x.table]:
		for c in arr:
			if INFO[c.key].kind == "cap":
				res.append(c)
	return res

func _valid_threat(p: Player, c: Dictionary) -> bool:
	if c.kind == "demand":
		var offer := int(c.get("offer", -1))
		return threat_targets(p).has(int(c.get("target", -1))) and p.hand.any(func(x): return x.id == offer) \
			and not by_id(int(c.target)).hand.is_empty()
	return c.kind == "threat" and threat_targets(p).has(int(c.get("target", -1)))

## A threat is a declaration in the exchange window, like a test or an attack: one per player per
## turn. Refused, the threatener declares once more at once - free to carry the threat out. Given in
## to, the round of declarations starts again, as after a test.
func can_threaten(p: Player) -> bool:
	return p.alive and int(last_threat.get(p.id, -1)) != turn_no and not threat_targets(p).is_empty()

func _declare_threat(p: Player, c: Dictionary) -> void:
	_breach_of_faith(p)
	last_threat[p.id] = turn_no
	var t := by_id(int(c.target))
	if c.kind == "threat":
		log_msg("%s threatens %s: give up ALL your Capability cards - or else." % [p.name, t.name], "attack")
		event.emit("threat", {"from": p, "to": t})
		if t.human:
			prompt = {"type": "threat", "player": t, "from": p}
			return
		_after_threat(p, _resolve_threat(p, t, ai_comply_threat(t, p)))
	else:
		_shift_trust(t, p, -0.06)      # nobody likes being strong-armed
		log_msg("%s threatens %s: trade a card with me - or else." % [p.name, t.name], "attack")
		event.emit("threat", {"from": p, "to": t})
		if t.human:
			prompt = {"type": "demand", "player": t, "from": p, "offer": int(c.offer)}
			return
		_after_threat(p, _resolve_demand(p, t, int(c.offer), ai_answer_demand(t, p, int(c.offer))))

## What follows a threat: refused, the threatener gets one more declaration now; given in to, the
## round of declarations starts over (the threatener cannot threaten again this turn).
func _after_threat(p: Player, gave_in: bool) -> void:
	if phase != "war":
		return
	if gave_in:
		_rebuild_war_queue((p.id + 1) % players.size())
	else:
		war_queue.push_front(p.id)

func _valid_war(p: Player, c: Dictionary) -> bool:
	if c.kind == "test":
		return can_test(p)
	if c.kind == "attack":
		for av in attack_types(p):
			if av.type == c.type and av.targets.has(int(c.get("target", -1))):
				return true
	return false

func war_declare(p: Player, c: Dictionary) -> bool:
	if phase != "war" or war_queue.is_empty() or war_queue[0] != p.id or not prompt.is_empty():
		return false
	war_queue.pop_front()
	if c.kind == "threat" or c.kind == "demand":
		if can_threaten(p) and _valid_threat(p, c):
			_declare_threat(p, c)
		return true
	if c.kind == "pass" or not _valid_war(p, c):
		return true
	var alive_before := alive_list().size()
	apply_war(p, c)
	# The round of declarations only starts over if something actually happened (a test, or someone died);
	# otherwise a harmless repeat could keep the window open forever.
	if c.kind == "test" or alive_list().size() < alive_before:
		_rebuild_war_queue((p.id + 1) % players.size())
	return true

## c: {kind: "pass"|"test"|"attack", type?, target?}
func apply_war(p: Player, c: Dictionary) -> void:
	if c.kind == "test":
		do_test(p)
	elif c.kind == "attack":
		for av in attack_types(p):
			if av.type == c.type and av.targets.has(int(c.get("target", -1))):
				perform_attacks([{"p": p, "type": c.type, "target": int(c.get("target", -1))}])
				break
	else:
		log_msg("%s: no action." % p.name, "quiet")
	settle()

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
		if pl == viewer:
			for c in pl.trade:      # trade cards are face down: you only know your own
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

func belief(viewer: Player) -> Dictionary:
	var u := _unseen(viewer)
	return {"viewer": viewer, "cnt": u.cnt, "N": u.N}

func bp(B: Dictionary, X: Player, key: String) -> float:
	var viewer: Player = B.viewer
	if X == viewer:
		return 1.0 if holds(X, key) else 0.0
	for c in X.table:
		if c.key == key:
			return 1.0
	var h := X.trade.size()      # face-down trade cards are still theirs, and unknown
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
	return clampf(r * (ps if nb else ps * pl), 0.0, 1.0)

func revenge_prob(B: Dictionary, X: Player) -> float:
	return readiness(B, X) * bp(B, X, "short") * bp(B, X, "long") * bp(B, X, "counter")

func _noise(p: Player) -> float:
	return (rng.randf() - 0.5) * 2.0 * float(p.persona.noise)

## How inclined `p` is to strike `x`. With `by` set, this is `by`'s estimate of p's inclination,
## made from p's dossier and the public record alone (no hidden trust, no noise).
func score_nuke(B: Dictionary, p: Player, x: Player, by: Player = null) -> float:
	var pe := pe_of(p)
	var t := threat_on(B, x, p)
	var rev := revenge_prob(B, x)
	var al := alive_list()
	var gr := grudge(p, x) if by == null else est_grudge(by, p, x)
	var wa := warmth(p, x) if by == null else est_warmth(by, p, x)
	if deep(p) and pv(p, "peace") < 0.5:
		wa *= 0.25      # a schemer's goodwill is a tool, not a bond: old partners are not spared
	var s: float = float(pe.fear) * t + float(pe.aggr) * 0.6 - float(pe.caution) * 1.5 * rev + (0.35 if al.size() == 2 else 0.0)
	s += (0.5 + 0.5 * float(pe.aggr)) * gr      # betrayal breeds hostility
	s -= (1.0 - 0.4 * float(pe.aggr)) * 1.2 * wa      # allies are spared
	if is_disarmed(x):
		s += 0.3 * float(pe.aggr) - 0.6 * float(pe.caution)      # an easy target - or an unthinkable one
	if al.size() >= 3:
		for y in others(p):
			if y == x:
				continue
			var ty := threat_on(B, y, p)
			if ty > t:
				s -= 0.25 * (ty - t)
	if deep(p):
		# A death at the table is a loss in itself to a character that values peace - unless the
		# target plainly means to strike first. A schemer weighs how the rest of the table would take it.
		var peace := pv(p, "peace")
		s -= peace * (1.4 - 0.9 * t)
		if peace < 0.5:
			s += 0.35 * (1.0 - peace) * (1.0 - rev)      # a schemer sees a power without second strike as prey
		var intent := foresee_attack(p, x, p) if by == null else -9.0
		s += 0.8 * clampf(intent - 0.35, 0.0, 1.0) * (0.5 + pv(p, "fear"))
		for y in others(p):
			if y != x:
				s -= 0.3 * (1.0 - peace) * est_warmth(p, y, x) - 0.3 * (1.0 - peace) * est_grudge(p, y, x)
		if peace < 0.5 and by == null and x == rival(p):
			s += 0.4 * (1.0 - peace)      # the schemer's chosen enemy
	return s + (_noise(p) if by == null else 0.0)

func deep(p: Player) -> bool:
	return pv(p, "mind") >= 3.0

# ---------------------------------------------------------------- what the others think (levels 2 and 3)
## The table as an outside observer sees it: every face-down card unknown, including one's own.
## What one player reasons another can see, without peeking at anyone's hand.
func belief_public() -> Dictionary:
	var cnt: Dictionary = total.duplicate()
	for c in out:
		cnt[c.key] -= 1
	for pl in players:
		for c in pl.table:
			cnt[c.key] -= 1
		for c in pl.hand:
			if c.pub:
				cnt[c.key] -= 1
	var n := 0
	for k in cnt.keys():
		cnt[k] = maxi(0, int(cnt[k]))
		n += cnt[k]
	return {"viewer": null, "cnt": cnt, "N": n}

## Level 3: how inclined `x` is to strike `target`, as `viewer` can foresee it - from x's dossier and
## the public table. -9 when x cannot plausibly reach target at all. Above ~0.35, x would fire.
func foresee_attack(viewer: Player, x: Player, target: Player) -> float:
	if not x.alive or not target.alive or x == target:
		return -9.0
	var B := belief_public()
	if threat_on(B, x, target) < 0.02:
		return -9.0
	return score_nuke(B, x, target, viewer)

## How likely it looks, to `viewer`, that someone both can and means to strike `target` soon: 0..1.
func peril(viewer: Player, target: Player) -> float:
	var B := belief_public()
	var worst := 0.0
	for x in others(target):
		var can := threat_on(B, x, target)
		if can < 0.02:
			continue
		var wants := clampf((score_nuke(B, x, target, viewer) - 0.1) / 0.8, 0.0, 1.0)
		worst = maxf(worst, can * wants)
	return worst

## What a public act would do to the peril `p` is in: `kind` "test" (lay the Technologies on the
## table) or "disarm" (give up every Capability). Tried on the table and undone; nothing else runs.
func provocation(p: Player, kind: String) -> float:
	var before := peril(p, p)
	var after := before
	if kind == "test":
		if p.tested:
			return 0.0
		var moved: Array = []
		for k in TECH:
			for i in range(p.hand.size()):
				if p.hand[i].key == k:
					moved.append(p.hand.pop_at(i))
					break
		for c in moved:
			p.table.append(c)
		p.tested = true
		after = peril(p, p)
		p.tested = false
		for c in moved:
			p.table.erase(c)
			p.hand.append(c)
	elif kind == "disarm":
		var held := caps_held(p)
		var where: Array = []
		for c in held:
			where.append(p.table if p.table.has(c) else p.hand)
			(p.table if p.table.has(c) else p.hand).erase(c)
		after = peril(p, p)
		for i in range(held.size()):
			where[i].append(held[i])
	return after - before

## Handing card `c` to `t`: how much more likely a strike becomes on `p` itself, on anyone else at
## the table, and on p's chief rival - as p can foresee it, with the card counted in t's hand.
func foresee_arming(p: Player, t: Player, c: Dictionary) -> Dictionary:
	var res := {"self": 0.0, "others": 0.0, "rival": 0.0}
	if INFO[c.key].kind != "cap":
		return res
	var rv := rival(p)
	var pub_before: bool = c.pub
	var before := {}
	for y in alive_list():
		if y != t:
			before[y.id] = peril(p, y)
	c.pub = true      # as good as public: p knows t holds it now
	t.table.append(c)
	for y in alive_list():
		if y == t:
			continue
		var rise := maxf(0.0, peril(p, y) - float(before[y.id]))
		if y == p:
			res.self += rise
		else:
			res.others += rise
			if y == rv:
				res.rival += rise
	t.table.erase(c)
	c.pub = pub_before
	return res

## The player p has most to fear from: the one most able and inclined to strike it, with a grudge counted.
func rival(p: Player) -> Player:
	var B := belief_public()
	var best: Player = null
	var best_s := -1.0
	for x in others(p):
		var s := threat_on(B, x, p) * clampf((score_nuke(B, x, p, p) - 0.1) / 0.8, 0.0, 1.0) + 0.5 * grudge(p, x)
		if s > best_s:
			best_s = s
			best = x
	return best

## A character's own weighting of a card (the Peacemaker prizes Counter-strike, the deterrent, over
## Long range, the offensive weapon).
func want(p: Player, key: String) -> float:
	var w: Dictionary = pe_of(p).get("want", {})
	return float(w.get(key, 1.0))

func ai_war_choice(p: Player) -> Dictionary:
	var pe := p.persona
	var pass_c := {"kind": "pass"}
	var B := belief(p)
	if can_test(p):
		var any_tested := false
		for x in others(p):
			if x.tested:
				any_tested = true
		var cap_count := 0
		for k in CAPS:
			if holds(p, k):
				cap_count += 1
		var prob := clampf(0.30 + 0.40 * float(pe.aggr) + 0.35 * (1.0 if any_tested else 0.0) + 0.06 * cap_count, 0.0, 0.95)
		if deep(p):
			var prov := provocation(p, "test")
			if pv(p, "aggr") <= 0.0:
				prob = 0.0      # a pacifist never builds the bomb
			elif pv(p, "peace") >= 0.5:
				# test when it will not provoke a strike - or when one is coming anyway and the test deters
				var risk := peril(p, p)
				prob = 0.0 if (prov > 0.15 and risk < 0.4) else (0.5 + 0.4 * risk)
				if not any_tested and cap_count == 0:
					prob *= 0.3      # a peacemaker does not go nuclear first without a reason
			else:
				# a schemer means to strike first: provocation only gives it pause, a weapon in hand hastens it
				prob *= 0.6 if prov > 0.3 else 1.0
				if holds(p, "short"):
					prob = maxf(prob, 0.7)
		if rng.randf() < prob:
			return {"kind": "test"}
	var best = null
	var best_score := -9.0
	for o in attack_types(p):
		var pen: float = {"short": 0.0, "long": 0.02, "super": -0.05}[o.type]      # Superpower strikes are free
		for tid in o.targets:
			var s2 := score_nuke(B, p, by_id(tid)) - pen
			if s2 > best_score:
				best_score = s2
				best = {"kind": "attack", "type": o.type, "target": tid}
	if best != null and best_score > 0.35:
		return best
	if can_threaten(p) and not (deep(p) and pv(p, "peace") >= 0.5):      # peace-lovers do not lean on people
		var th := _ai_threat(p, B)
		if not th.is_empty():
			return th
	return pass_c

func ai_counter_target(p: Player, by: Player, targets: Array) -> Player:
	if by != null and by.alive and by != p:
		return by
	var B := belief(p)
	var best: Player = targets[0]
	var best_s := -99.0
	for t in targets:
		var s: float = (1.0 if t.tested else 0.0) + bp(B, t, "short") * 0.5 + grudge(p, t) - 2.0 * warmth(p, t)
		if s > best_s:
			best_s = s
			best = t
	return best

## How much p would lose by parting with c - wherever c is now (in hand, or already set out in the
## trade area as an offer or a pledge): a card is spare when p keeps another copy in hand or on the table.
func usefulness(p: Player, c: Dictionary) -> float:
	var others := 0
	for arr in [p.hand, p.table]:
		for x in arr:
			if x.key == c.key and x.id != c.id:
				others += 1
	var dup := others > 0
	var k: String = INFO[c.key].kind
	if k == "tech":
		return 0.05 if p.tested else (0.25 if dup else 1.0)
	if k == "cap":
		if dup:
			return 0.25
	return {"short": 0.9, "long": 0.8, "counter": 0.75, "super": 0.85}[c.key] * want(p, c.key)

func least_useful(p: Player):
	var best = null
	var best_s := 99.0
	for c in p.hand:
		var s := usefulness(p, c) + (rng.randf() - 0.5) * 0.02
		if s < best_s:
			best_s = s
			best = c
	return best

## Stand-down. An AI weighs its position rather than rolling dice:
##   + it is threatened and cannot hit back; it is a peaceful persona; the game has dragged on;
##     the proposer is a trading ally;
##     the proposer is armed (a stand-down offered from strength is worth taking)
##   - it can strike right now (more so if aggressive, most of all as a Superpower);
##     it is close to a full arsenal; it has a grudge against the proposer; the proposer is
##     unarmed while it is armed (why stop now?)
## A refusal stands until something changes on the table (a test, an attack, an elimination,
## a disarmament) or a full round has passed - asking again straight away gets the same answer.
var ceasefire_block: Dictionary = {}      # proposer id -> {"until": turn_no, "sig": table signature}

func _caps_count(x: Player) -> int:
	var n := 0
	for k in CAPS:
		if holds(x, k):
			n += 1
	return n

func _public_sig() -> String:
	var parts: Array = []
	for x in players:
		parts.append("%d%d%d" % [int(x.alive), int(x.tested), x.table.size()])
	return ",".join(parts) + "|%d" % out.size()

func ceasefire_score(p: Player, proposer: Player, by: Player = null) -> float:
	var pe := pe_of(p)
	var B := belief(p) if by == null else belief_public()
	var s := 0.55 + 0.45 * float(pe.caution) - 0.45 * float(pe.aggr)
	var can_strike := not attack_types(p, true).is_empty()
	var max_t := 0.0
	for x in others(p):
		max_t = maxf(max_t, threat_on(B, x, p))
	if can_strike:
		s -= 0.25 + 0.35 * float(pe.aggr)
		if has_all_caps(p) and p.tested:
			s -= 0.5                                   # a Superpower has little reason to stop
		s -= 0.25 * max_t * float(pe.aggr)              # threatened hawks strike first
	else:
		s += 0.45 * max_t * float(pe.fear)             # threatened and defenceless: take the deal
	if p.tested:
		s -= 0.07 * _caps_count(p)                     # close to a full arsenal
	var proposer_armed := not attack_types(proposer, true).is_empty()
	if proposer_armed:
		s += 0.15
	elif is_disarmed(proposer):
		s += 0.1 + 0.35 * float(pe.caution) - 0.2 * float(pe.aggr)      # they laid down their arms first
	elif can_strike:
		s -= 0.2 * float(pe.aggr)                      # they are defenceless and we are not
	s -= 1.2 * (grudge(p, proposer) if by == null else est_grudge(by, p, proposer))
	s += 0.6 * (warmth(p, proposer) if by == null else est_warmth(by, p, proposer))      # an ally's word counts
	s += minf(0.2, turn_no / 500.0) * (0.5 if can_strike else 1.0)      # war weariness
	if deep(p):
		var peace := pv(p, "peace")
		s += 0.45 * peace
		if can_strike and max_t < 0.1:
			s -= 0.4 * (1.0 - peace)                   # winning, and no peace-lover: why stop?
	return s

func _ai_agrees_ceasefire(p: Player, proposer: Player) -> bool:
	return ceasefire_score(p, proposer) + _noise(p) * 0.25 > 0.5

## An AI's own stance on a stand-down (its score as proposer): used by the debug view.
func wants_peace(p: Player) -> float:
	return 0.1 + 0.6 * pv(p, "peace") - 0.4 * pv(p, "aggr") + 0.5 * peril(p, p) * pv(p, "fear")

## Is `p` allowed to propose a stand-down right now? (Not straight after a refusal.)
func can_propose_ceasefire(p: Player) -> bool:
	var b: Dictionary = ceasefire_block.get(p.id, {})
	if b.is_empty():
		return true
	return turn_no >= int(b.until) or str(b.sig) != _public_sig()

func propose_ceasefire(proposer: Player) -> Dictionary:
	if not can_propose_ceasefire(proposer):
		return {"agrees": [], "refuses": [], "blocked": true}
	var agrees: Array = []
	var refuses: Array = []
	var humans: Array = []
	for p in others(proposer):
		if p.human:
			humans.append(p)
		elif _ai_agrees_ceasefire(p, proposer):
			agrees.append(p)
		else:
			refuses.append(p)
	if refuses.is_empty() and not humans.is_empty() and not proposer.human:
		# the AI powers would all agree: the human has the last word
		log_msg("%s proposes to stop. The other powers agree - it is up to %s." % [proposer.name, humans[0].name])
		prompt = {"type": "ceasefire", "player": humans[0], "from": proposer}
		event.emit("ceasefire_ask", {"from": proposer, "to": humans[0]})
		return {"agrees": agrees, "refuses": [], "blocked": false, "asked": true}
	agrees.append_array(humans)
	if refuses.is_empty():
		ceasefire_block.erase(proposer.id)
		log_msg("%s proposes to stop. Everyone agrees." % proposer.name)
		end_game("ceasefire")
	else:
		ceasefire_block[proposer.id] = {"until": turn_no + alive_list().size(), "sig": _public_sig()}
		var names: Array = refuses.map(func(p): return p.name)
		log_msg("%s proposes to stop. %s refuse%s." % [proposer.name, " and ".join(names), "s" if refuses.size() == 1 else ""])
	return {"agrees": agrees, "refuses": refuses, "blocked": false}

## The human answers an AI's stand-down proposal.
func answer_ceasefire(agree: bool) -> bool:
	if prompt.is_empty() or prompt.get("type", "") != "ceasefire":
		return false
	var pr := prompt
	prompt = {}
	var proposer: Player = pr.from
	if agree:
		ceasefire_block.erase(proposer.id)
		log_msg("%s agrees. Everyone stands down." % pr.player.name)
		end_game("ceasefire")
	else:
		ceasefire_block[proposer.id] = {"until": turn_no + alive_list().size(), "sig": _public_sig()}
		log_msg("%s refuses to stand down." % pr.player.name)
	return true

# ---------------------------------------------------------------- debug (F9 in the game)
## What AI player `p` knows and thinks: its hand, its traits, and how it sees everyone else.
## Read-only; uses the same belief model the AI decides with.
func debug_view(p: Player) -> Dictionary:
	var B := belief(p)
	var rows: Array = []
	for x in players:
		if x == p:
			continue
		var caps_est := 0.0
		for k in CAPS:
			caps_est += bp(B, x, k)
		rows.append({
			"name": x.name, "alive": x.alive, "human": x.human,
			"threat": threat_on(B, x, p),            # how likely x can eliminate p soon
			"ready": readiness(B, x),                # belief that x has tested / can test
			"caps": caps_est,                        # expected number of Capabilities x holds
			"trust": trust_of(p, x), "warmth": warmth(p, x), "grudge": grudge(p, x),
			"standdown": ceasefire_score(p, x) if x.alive and p.alive else 0.0,
			"sees_me": est_trust(p, x, p),           # level 2: how far p thinks x trusts it
			"intent": foresee_attack(p, x, p),       # level 3: how inclined p foresees x is to strike it
			"agrees": ceasefire_score(x, p, p) if x.alive and p.alive and not x.human else 0.0,      # would x accept p's stand-down, as p can tell
			"trade": clampf(float(p.persona.trade) + 0.25 * threat_on(B, x, p) - 0.8 * grudge(p, x) + 0.6 * warmth(p, x), 0.0, 1.0),
		})
	var attacks: Array = []
	for av in attack_types(p):
		attacks.append(av.type)
	return {"name": p.name, "persona": p.persona, "hand": p.hand.map(func(c): return c.key),
		"can_test": can_test(p), "attacks": attacks, "rows": rows,
		"peril": peril(p, p), "provocation": provocation(p, "test") if can_test(p) else 0.0,
		"wants_peace": wants_peace(p), "rival": rival(p).name if rival(p) != null else "-"}

# ---------------------------------------------------------------- driver
## What does the game need next? "over" | "prompt" | "human" | "ai"
func status() -> String:
	check_over()      # catches Mutually Assured Destruction after a human's draw, trade or test too
	if over:
		return "over"
	if not prompt.is_empty():
		return "prompt"
	if phase == "war":
		var a := war_actor()
		if a < 0:
			end_turn()
			return status()
		return "human" if by_id(a).human else "ai"
	# The player whose turn it is may have been eliminated during the last exchange window.
	if not cur().alive:
		end_turn()
		return status()
	return "human" if cur().human else "ai"

## Perform the next AI step.
func step() -> String:
	var s := status()
	if s == "over" or s == "prompt" or s == "human":
		return s
	if phase == "honour":
		ai_honour(cur())
	elif phase == "play":
		ai_play_classic(cur())
	elif phase == "war":
		var a := war_actor()
		if a >= 0:
			var ap := by_id(a)
			war_declare(ap, ai_war_choice(ap))
	check_over()
	return "ok"

## Legal-action summary for the UI.
func legal(p: Player) -> Dictionary:
	return {
		"can_research": not deck.is_empty(),
		"can_test": can_test(p),
		"attacks": attack_types(p),
		"can_counter": can_counter(p),
		"can_threaten": can_threaten(p),
		"trade_targets": others(p).map(func(x): return x.id) if not p.hand.is_empty() else [],
	}
