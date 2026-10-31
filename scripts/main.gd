extends Control
## Nuclear Poker — Godot UI. Talks to NPGame (engine.gd). All controls are built in code.
## Original game: Vinay Gupta & Dan Carter (GNU FDL).

const C_BG := Color("#121309")
const C_BG2 := Color("#191a10")
const C_PANEL := Color("#22241ae6")
const C_PANEL2 := Color("#2b2d1f")
const C_LINE := Color("#57573a")
const C_INK := Color("#efe5c8")
const C_MUT := Color("#b0a684")
const C_AMBER := Color("#d9a73e")
const C_RED := Color("#b8432f")
const C_GREEN := Color("#a3b866")

const ORDER := ["uranium", "refinement", "warhead", "testing", "short", "long", "counter", "super"]
const AI_DELAY := 1.0              # seconds between AI steps (divided by `speed`)
const PERSONA_IDS := ["random", "hawk", "dove", "opp", "wild", "pacifist", "peacemaker", "schemer"]
const CARD_DESC := {
	"uranium": "Technology. Hold all four different Technologies to perform a Nuclear Test.",
	"refinement": "Technology. Hold all four different Technologies to perform a Nuclear Test.",
	"warhead": "Technology. Hold all four different Technologies to perform a Nuclear Test.",
	"testing": "Technology. Hold all four different Technologies to perform a Nuclear Test.",
	"short": "Needs a Nuclear Test. Attack: eliminate a player sitting immediately to your left or right. Destroyed when fired.",
	"long": "Needs Nuclear Test + Short-range. Attack: eliminate any one player. Destroyed when fired.",
	"counter": "Second Strike. Needs Nuclear Test + Short + Long. When you are eliminated, immediately eliminate one player.",
	"super": "Needs Nuclear Test + all 4 Capabilities. You are a Nuclear Superpower: strike any player, and strike more than once.",
}

var HEAD: Font
var ui_theme: Theme
var MONO: Font
var TEX := {}
var TEXB := {}      # burnt copies of the cards, for an eliminated player's revealed hand

var cfg := {"name": "You", "players": "3", "p1": "random", "p2": "random", "p3": "random", "p4": "random", "fullscreen": false}
var G: NPGame = null
var ME: NPGame.Player = null

# game flow state
var speed := 1.0                  # >1 only in the automated test
var paused := 0
var pump_token := 0
var end_shown := false
var mad_pic := -1      # which front-page photograph the MAD ending shows this game (MAD_PICS)
var muted := false
var ff := false
var fresh := {}
var log_shown := 0
var card_w := 100.0
var mini_w := 46.0
var btn := {}                     # live buttons by key (also used by the automated test)
var modal_btns: Array = []

# node refs
var menu_root: Control
var game_root: Control
var topbar: HBoxContainer
var board: VBoxContainer
var map_box: VBoxContainer
var logbox: RichTextLabel
var log_edition: Label      # the newspaper's dateline: which round we are in
var overlay: CanvasLayer
var modal_root: Control
var popup_root: Control
var fx_root: Control
var last_fx: Control = null      # the headline flash on screen, if any
var last_fx_ms := 0
var modal: Control = null
var modal_scroll: ScrollContainer = null
var modal_vbox: VBoxContainer = null
var modal_pause := false
var modal_sticky := false
var popup: Control = null
var me_zone: Control = null
var seat_zones := {}          # player id -> that seat's trade space (a drop target)
var board_scroll: ScrollContainer = null
var name_edit: LineEdit
var opp_btns: Array = []
var opp_lbls: Array = []
var players_opt: OptionButton
var sounds := {}
var ambience: AudioStreamPlayer = null
var drag_ghost: Control = null      # the picture that follows the pointer while dragging
var zoom: TextureRect = null      # enlarged copy of the card under the pointer
var zoom_last_key := ""           # the card it showed, and when it went (to re-show without a flicker)
var zoom_last_ms := 0
var betrayals := {}               # player id -> how many deals they have broken with you
var died_at := {}                 # player id -> Time.get_ticks_msec() of their death, for the bones' fall
var BONES: Array = []             # charred bone piles (assets/ui/bones/, tools/meshy_bones.py)
# touch screens (tablets, phones): taps are clicks, and touching stands in for hovering
var touch := false
var touch_at := Vector2.ZERO
var touch_ms := 0
var touch_seq := 0                # bumps on every touch change, cancelling a pending long-press
var zoom_frame := -1              # the frame a touch enlarged a card (Godot sends the emulated click first)
var touch_scroll: Control = null  # a self-scrolling text box the finger is dragging
var turn_overlay: Control = null  # "turn your device sideways" on a portrait screen
var debug_panel: Control = null      # F9: what the AI players know and think
var music: Array = []             # one player per tension level, all running in sync
var music_level := -1
var funeral: AudioStreamPlayer = null      # after a nuclear strike: a funeral march, over the music
var music_hold := 0
var music_on := true
const MUSIC_LEVELS := ["calm", "uneasy", "tense", "crisis"]
const MUSIC_DB := -9.0       # music sits under the effects

# ====================================================================== custom controls
class Trefoil extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color("#d9a73e"))
		for k in range(3):
			var mid := -PI / 2.0 + k * TAU / 3.0
			var pts := PackedVector2Array()
			for i in range(13):
				var a := mid - PI / 6.0 + (PI / 3.0) * i / 12.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.78)
			for i in range(12, -1, -1):
				var a2 := mid - PI / 6.0 + (PI / 3.0) * i / 12.0
				pts.append(c + Vector2(cos(a2), sin(a2)) * r * 0.26)
			draw_colored_polygon(pts, Color("#18190f"))
		draw_circle(c, r * 0.12, Color("#18190f"))

class Hazard extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#18190f"))
		var x := -size.y
		while x < size.x + size.y:
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + 12, size.y), Vector2(x + 12 + size.y, 0), Vector2(x + size.y, 0)]), Color("#d9a73e"))
			x += 24.0

class CardBack extends Control:
	static var tex: Texture2D
	func _draw() -> void:
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)

class HandCard extends Control:
	signal picked(cid: int, node: Control)
	var cid := 0
	var base_y := 0.0
	var fresh := false
	var can_drag := false
	var face: Control = null      # the visual; scaled on hover while the card's hit area stays put
	var preview: Callable
	var tex: Texture2D            # the card picture, for the copy that follows the pointer
	var tw: Tween
	var dragging := false
	static var touch := false      # set by the game while the player is using a touch screen
	static var hov_cid := -1       # the card that was lifted when the hand was last rebuilt, and when
	static var hov_ms := 0
	var press_ms := 0
	func _get_drag_data(at: Vector2) -> Variant:
		if not can_drag:
			return null
		# the card itself leaves the hand and travels with the pointer, held where it was grabbed
		var holder := Control.new()
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		t.size = size
		t.position = -at
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
		set_drag_preview(holder)
		dragging = true
		modulate.a = 0.0
		return {"cid": cid}
	func _notification(what: int) -> void:
		if what == NOTIFICATION_EXIT_TREE and z_index == 20:
			hov_cid = cid
			hov_ms = Time.get_ticks_msec()
		if what == NOTIFICATION_DRAG_END and dragging:
			dragging = false
			# dropped somewhere that took it: stay gone (the board is about to update); otherwise come back
			if not get_viewport().gui_is_drag_successful():
				modulate.a = 1.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): if not touch: _hover(true))
		mouse_exited.connect(func(): if not touch: _hover(false))
	func _hover(on: bool) -> void:
		if tw:
			tw.kill()
		z_index = 20 if on else 0
		if face == null:
			return
		if on and cid == hov_cid and Time.get_ticks_msec() - hov_ms < 400:
			# the same card under a still mouse after a rebuild: lift it at once, no second pop
			face.pivot_offset = Vector2(size.x / 2.0, size.y)
			face.position.y = -14.0
			face.scale = Vector2.ONE * 1.35
			return
		face.pivot_offset = Vector2(size.x / 2.0, size.y)      # grow up and out from the bottom edge
		tw = create_tween().set_parallel(true)
		tw.tween_property(face, "position:y", -14.0 if on else 0.0, 0.12)
		tw.tween_property(face, "scale", Vector2.ONE * (1.35 if on else 1.0), 0.12).set_trans(Tween.TRANS_SINE)
	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
			return
		if not touch:
			if not e.pressed:
				picked.emit(cid, self)
			return
		# touch: the finger lifts the card to show it; a quick tap opens its options, a long hold only looks
		if e.pressed:
			press_ms = Time.get_ticks_msec()
			_hover(true)
		else:
			_hover(false)
			if Time.get_ticks_msec() - press_ms < 450:
				picked.emit(cid, self)

class DragSrc extends Control:
	## A card that can be dragged onto a DropTarget. `preview` builds the card that follows the pointer.
	var cid := 0
	var preview: Callable
	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_DRAG
	func _get_drag_data(_at: Vector2) -> Variant:
		if preview.is_valid():
			set_drag_preview(preview.call())
		return {"cid": cid}

class DropTarget extends PanelContainer:
	## Accepts a dragged card when `accept` allows it. Only the target under the pointer lights up.
	var accept: Callable
	var on_drop: Callable
	var hot := false
	var _normal: StyleBox
	func _set_hot(on: bool) -> void:
		if on == hot:
			return
		hot = on
		if on:
			_normal = get_theme_stylebox("panel")
			var sb := (_normal.duplicate() if _normal is StyleBoxFlat else StyleBoxFlat.new()) as StyleBoxFlat
			sb.border_color = Color("#e9c977")
			sb.set_border_width_all(3)
			sb.bg_color = sb.bg_color.lightened(0.12)
			add_theme_stylebox_override("panel", sb)
		elif _normal != null:
			add_theme_stylebox_override("panel", _normal)
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = data is Dictionary and data.has("cid") and accept.is_valid() and accept.call(data)
		_set_hot(ok)
		return ok
	func _drop_data(_at: Vector2, data: Variant) -> void:
		_set_hot(false)
		on_drop.call_deferred(data)      # let the drag finish (and its preview go) before the board is rebuilt
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
			_set_hot(false)

class CardStrip extends Control:
	## A fixed-height row of cards that never wraps or grows: when there are too many
	## to fit, they overlap. Keeps panels the same size as cards come and go.
	var cw := 40.0
	var ch := 52.0
	var gap := 5.0
	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY:
			layout()
	func layout() -> void:
		custom_minimum_size.y = ch
		var kids: Array = get_children().filter(func(k): return k is Control)
		var n := kids.size()
		if n == 0:
			return
		var step := cw + gap
		if n > 1 and size.x > 0.0 and cw + (n - 1) * step > size.x:
			step = maxf(6.0, (size.x - cw) / float(n - 1))
		for i in range(n):
			var k: Control = kids[i]
			if k is Label:
				k.size = k.get_minimum_size()
				k.position = Vector2(i * step, (ch - k.size.y) / 2.0)
			else:
				k.position = Vector2(i * step, 0)
				k.size = Vector2(cw, ch)

class HandView extends Control:
	var cw := 100.0
	var ch := 130.0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			layout()
	func layout() -> void:
		custom_minimum_size.y = ch + 22.0
		var cards := get_children()
		var n := cards.size()
		if n == 0:
			return
		var avail := maxf(100.0, size.x - 40.0)
		var overlap := cw * 0.08
		if n > 1 and n * cw - (n - 1) * overlap > avail:
			overlap = (n * cw - avail) / (n - 1)
		overlap = minf(overlap, cw - 14.0)
		var total := n * cw - (n - 1) * overlap
		var x0 := maxf(0.0, (size.x - total) / 2.0)
		for i in range(n):
			var c: HandCard = cards[i]
			c.size = Vector2(cw, ch)
			c.base_y = 20.0
			c.position = Vector2(x0 + i * (cw - overlap), 20.0)
			if c.fresh:
				c.fresh = false
				c.position.y -= 50.0
				c.modulate.a = 0.0
				var t := c.create_tween().set_parallel(true)
				t.tween_property(c, "position:y", 20.0, 0.35)
				t.tween_property(c, "modulate:a", 1.0, 0.25)

class TableMap extends Control:
	# A small campaign map: one country per player, in turn order clockwise round the highlands at
	# the heart of a continent. Countries that share a border are neighbours (solid amber - Short
	# range reaches them); countries across the highlands are linked by a dashed line (Long range only).
	var seats: Array = []     # {name, alive, tested, turn, you, color}
	var links: Array = []     # [i, j, "short" | "long"]
	var font: Font
	const SEA := Color("#131915")
	# painted land and sea (tools/meshy_card_art.py --map), used as textures under the game's own shapes
	static var land_tex: Texture2D = null
	static var sea_tex: Texture2D = null
	func _ready() -> void:
		if land_tex == null and ResourceLoader.exists("res://assets/ui/map_land.jpg"):
			land_tex = load("res://assets/ui/map_land.jpg")
		if sea_tex == null and ResourceLoader.exists("res://assets/ui/map_sea.jpg"):
			sea_tex = load("res://assets/ui/map_sea.jpg")
	const LAND := Color("#4a4631")
	const COAST := Color("#cdbd8c")
	const INK := Color("#1c1a12")

	# ---- geometry: a continent with a rugged coast (peninsulas, bays, islands), unclaimed highlands
	# and a lake at its heart, and one country per player in a ring round the highlands. Countries
	# next to each other in turn order share a border; the others only meet across the highlands.
	var _norm := 0.0
	func _rx() -> float:
		return size.x * 0.5 - 9.0
	func _ry() -> float:
		return size.y * 0.5 - 6.0
	func _bump(a: float, at: float, w: float) -> float:
		var d := wrapf(a - at, -PI, PI)
		return exp(-(d / w) * (d / w))
	func _coast_f(a: float) -> float:
		return (1.0 + 0.08 * sin(2.0 * a + 0.6) + 0.07 * sin(3.0 * a + 2.2) + 0.05 * sin(5.0 * a + 0.4)
			+ 0.035 * sin(8.0 * a + 1.7) + 0.02 * sin(13.0 * a + 0.3) + 0.012 * sin(23.0 * a + 2.9)
			+ 0.17 * _bump(a, 0.35, 0.09) + 0.12 * _bump(a, 3.75, 0.08) + 0.08 * _bump(a, 5.0, 0.07)
			- 0.17 * _bump(a, 2.35, 0.07) - 0.12 * _bump(a, 5.45, 0.06) - 0.09 * _bump(a, 1.25, 0.05))
	func _outer(a: float) -> Vector2:
		if _norm == 0.0:
			for k in range(720):
				_norm = maxf(_norm, _coast_f(TAU * k / 720.0))
		var f := _coast_f(a) / _norm
		return size / 2.0 + Vector2(cos(a) * _rx() * f, sin(a) * _ry() * f)
	## The edge of the unclaimed highlands in the middle of the continent.
	func _inner(a: float) -> Vector2:
		var f := 1.0 + 0.12 * sin(3.0 * a + 0.9) + 0.08 * sin(5.0 * a + 2.0) + 0.05 * sin(11.0 * a + 0.2)
		return size / 2.0 + Vector2(cos(a) * _rx() * 0.27 * f, sin(a) * _ry() * 0.31 * f)
	func _lake(a: float) -> Vector2:
		var f := 1.0 + 0.2 * sin(2.0 * a + 1.0) + 0.1 * sin(4.0 * a + 0.3) + 0.05 * sin(7.0 * a)
		return size / 2.0 + Vector2(_rx() * 0.04, -_ry() * 0.05) + Vector2(cos(a) * _rx() * 0.1, sin(a) * _ry() * 0.11) * f
	## Borders do not run straight out from the middle: each leans and wanders on its way to the coast.
	func _lean(a: float) -> float:
		return 0.14 * sin(2.0 * a + 1.0)
	func _border(a: float) -> PackedVector2Array:
		var pa := _inner(a)
		var pb := _outer(a + _lean(a))
		var nrm := (pb - pa).orthogonal().normalized()
		var out := PackedVector2Array()
		for k in range(1, 12):
			var t := k / 12.0
			var wig := sin(t * PI * 3.0 + a * 5.0) * 3.5 + sin(t * PI * 7.0 + a * 2.0) * 1.5
			out.append(pa.lerp(pb, t) + nrm * wig * sin(t * PI))
		return out
	func _seat_angle(i: int, n: int) -> float:
		return PI / 2.0 + TAU * i / n
	func _capital(i: int, n: int) -> Vector2:
		var a := _seat_angle(i, n)
		return _inner(a).lerp(_outer(a + _lean(a)), 0.52)
	## A blob of land or water: centre, radii, a seed for its shape.
	func _blob(c: Vector2, r: Vector2, seed_v: float, pts := 28) -> PackedVector2Array:
		var out := PackedVector2Array()
		for k in range(pts):
			var a := TAU * k / pts
			var f := 1.0 + 0.25 * sin(2.0 * a + seed_v) + 0.12 * sin(5.0 * a + seed_v * 2.3)
			out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y) * f)
		return out

	func _draw() -> void:
		var n := seats.size()
		if n == 0:
			return
		var c := size / 2.0
		draw_rect(Rect2(Vector2.ZERO, size), SEA)
		if sea_tex != null:
			draw_texture_rect(sea_tex, Rect2(Vector2.ZERO, size), false, Color(0.72, 0.76, 0.74))
		# graticule over the ocean
		for k in range(1, 6):
			var x := size.x * k / 6.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.55, 0.6, 0.5, 0.07), 1.0)
		for k in range(1, 4):
			var y := size.y * k / 4.0
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.55, 0.6, 0.5, 0.07), 1.0)
		# old-map water lines echoing the coasts
		for r in [1.06, 1.12]:
			var ring := PackedVector2Array()
			for k in range(97):
				var a := TAU * k / 96.0
				ring.append(c + (_outer(a) - c) * r)
			draw_polyline(ring, Color(0.8, 0.74, 0.55, 0.16 if r < 1.1 else 0.08), 1.0, true)
		# offshore islands
		for isl in [[1.0, 1.16, 6.0, 4.0, 0.7], [4.35, 1.14, 7.0, 4.5, 2.1], [5.95, 1.15, 5.0, 3.5, 1.3], [2.75, 1.13, 4.0, 3.0, 3.3]]:
			var ac: Vector2 = c + (_outer(isl[0]) - c) * isl[1]
			ac = ac.clamp(Vector2(8, 8), size - Vector2(8, 8))
			var bl := _blob(ac, Vector2(isl[2], isl[3]), isl[4])
			_land(bl, Color(0.8, 0.78, 0.7))
			draw_polyline(bl + PackedVector2Array([bl[0]]), COAST, 1.2, true)
		# countries
		var steps := 40
		for i in range(n):
			var s: Dictionary = seats[i]
			var a0 := _seat_angle(i, n) - PI / n
			var a1 := _seat_angle(i, n) + PI / n
			var poly := PackedVector2Array([_inner(a0)])
			poly.append_array(_border(a0))
			var o0 := a0 + _lean(a0)
			var o1 := a1 + _lean(a1)
			for k in range(steps + 1):
				poly.append(_outer(lerpf(o0, o1, float(k) / steps)))
			var b1 := _border(a1)
			b1.reverse()
			poly.append_array(b1)
			for k in range(steps + 1):
				poly.append(_inner(lerpf(a1, a0, float(k) / steps)))
			var fill: Color = LAND.lerp(s.color, 0.26)
			if not s.alive:
				fill = Color("#2a2820")
			elif s.turn:
				fill = fill.lightened(0.18)
			if land_tex != null:
				# the painting, washed with the owner's colour (scorched grey once destroyed)
				var tint: Color = Color(0.92, 0.9, 0.84).lerp(s.color, 0.46)
				if not s.alive:
					tint = Color(0.36, 0.34, 0.3)
				elif s.turn:
					tint = tint.lightened(0.22)
				_land(poly, tint)
			else:
				draw_colored_polygon(poly, fill)
			if not s.alive:
				_scorch(i, n)
			# a river from the highlands to the sea, through the middle of the country
			var am := _seat_angle(i, n) + 0.22 * TAU / n
			var rs := _inner(am)
			var re := _outer(am + _lean(am))
			var rv := PackedVector2Array()
			var rn := (re - rs).orthogonal().normalized()
			for k in range(13):
				var t := k / 12.0
				rv.append(rs.lerp(re, t) + rn * sin(t * PI * 2.5 + i) * 4.0 * sin(t * PI))
			draw_polyline(rv, Color(0.42, 0.55, 0.55, 0.75), 1.3, true)
		# the unclaimed highlands in the middle, with their lake
		var core := PackedVector2Array()
		var lake := PackedVector2Array()
		for k in range(96):
			core.append(_inner(TAU * k / 96.0))
			lake.append(_lake(TAU * k / 96.0))
		_land(core, Color(0.55, 0.54, 0.5))      # unclaimed: no owner's colour, a shade darker
		var rng := RandomNumberGenerator.new()
		rng.seed = 1947
		for k in range(26):      # mountain marks, as on an old map
			var aa := rng.randf() * TAU
			var t := 0.15 + 0.75 * rng.randf()
			var lp := _lake(aa)
			var mp := lp.lerp(_inner(aa), t)
			if mp.distance_to(lp) < 6.0 or mp.distance_to(_inner(aa)) < 5.0:
				continue
			var h := 3.0 + 2.0 * rng.randf()
			draw_polyline(PackedVector2Array([mp + Vector2(-h, h * 0.6), mp + Vector2(0, -h * 0.7), mp + Vector2(h, h * 0.6)]), Color(0.1, 0.08, 0.05, 0.75), 1.3, true)
			draw_line(mp + Vector2(0, -h * 0.7), mp + Vector2(h * 0.45, h * 0.1), Color(0.95, 0.9, 0.75, 0.5), 1.0, true)
		if sea_tex != null:
			var luv := PackedVector2Array()
			for q in lake:
				luv.append(q / size)
			draw_colored_polygon(lake, Color(0.8, 0.85, 0.85), luv, sea_tex)
		else:
			draw_colored_polygon(lake, SEA)
		draw_polyline(lake + PackedVector2Array([lake[0]]), COAST, 1.3, true)
		draw_colored_polygon(_blob(_lake(0.0).lerp(size / 2.0 + Vector2(_rx() * 0.04, -_ry() * 0.05), 0.55), Vector2(3.0, 2.0), 2.0, 16), Color(0.55, 0.52, 0.42))
		# borders (dashed), round the highlands and out to the coast
		for i in range(n):
			var a := _seat_angle(i, n) - PI / n
			var bd := PackedVector2Array([_inner(a)])
			bd.append_array(_border(a))
			bd.append(_outer(a + _lean(a)))
			for k in range(bd.size() - 1):
				if k % 2 == 0:
					draw_line(bd[k], bd[k + 1], Color(0.06, 0.05, 0.03, 0.85), 1.4, true)
		for k in range(0, core.size(), 2):
			draw_line(core[k], core[(k + 1) % core.size()], Color(0.06, 0.05, 0.03, 0.6), 1.1, true)
		# the coastline, with a little relief inside it
		var oc := PackedVector2Array()
		for k in range(361):
			oc.append(_outer(TAU * k / 360.0))
		draw_polyline(oc, COAST, 1.6, true)
		var oc2 := PackedVector2Array()
		for q in oc:
			oc2.append(c + (q - c) * 0.94)
		draw_polyline(oc2, Color(0.05, 0.04, 0.02, 0.16), 1.0, true)
		# ranges
		var pts: Array = []
		for i in range(n):
			pts.append(_capital(i, n))
		for l in links:
			var p1: Vector2 = pts[l[0]]
			var p2: Vector2 = pts[l[1]]
			if l[2] == "short":
				draw_line(p1, p2, Color(0.85, 0.65, 0.24, 0.9), 2.5, true)
			else:
				draw_dashed_line(p1, p2, Color(0.7, 0.66, 0.52, 0.75), 1.6, 5.0, true, true)
		# capitals and names
		for i in range(n):
			var s: Dictionary = seats[i]
			var p: Vector2 = pts[i]
			if s.alive:
				if s.turn:
					draw_circle(p, 12.0, Color(0.95, 0.69, 0.2, 0.35))
				draw_circle(p, 6.5, INK)
				draw_circle(p, 5.0, s.color)
				if s.you:
					draw_arc(p, 9.0, 0.0, TAU, 24, Color("#a3b866"), 1.8, true)
				if s.tested:
					_test_mark(p + Vector2(12.0, -11.0))
			else:
				var r := 5.0
				draw_line(p + Vector2(-r, -r), p + Vector2(r, r), Color("#d0604a"), 2.5, true)
				draw_line(p + Vector2(-r, r), p + Vector2(r, -r), Color("#d0604a"), 2.5, true)
			var txt: String = s.name
			var fs := 12
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var lp := Vector2(p.x - w / 2.0, p.y + 20.0)
			lp.x = clampf(lp.x, 3.0, size.x - w - 3.0)
			draw_string_outline(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.07, 0.06, 0.04, 0.85))
			draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#f2e8cb") if s.alive else Color("#8d876d"))

	## A patch of land: the painted terrain, washed with a colour.
	func _land(poly: PackedVector2Array, tint: Color) -> void:
		if land_tex == null:
			draw_colored_polygon(poly, LAND * tint)
			return
		var uvs := PackedVector2Array()
		for q in poly:
			uvs.append(q / size)
		draw_colored_polygon(poly, tint, uvs, land_tex)

	## A tested country carries a small mushroom cloud beside its capital.
	func _test_mark(p: Vector2) -> void:
		var y := Color("#e9c977")
		draw_line(p + Vector2(0, 1), p + Vector2(0, 6), y, 2.0, true)
		draw_circle(p + Vector2(-2.2, 0), 2.6, y)
		draw_circle(p + Vector2(2.2, 0), 2.6, y)
		draw_circle(p + Vector2(0, -1.6), 2.8, y)
		draw_line(p + Vector2(-3.5, 6.5), p + Vector2(3.5, 6.5), y, 1.5, true)

	## A destroyed country: grey ground pocked with craters.
	func _scorch(i: int, n: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (i + 1)
		var a := _seat_angle(i, n)
		for k in range(7):
			var aa := a + (rng.randf() - 0.5) * TAU / n * 0.7
			var p := _inner(aa).lerp(_outer(aa + _lean(aa)), 0.2 + 0.6 * rng.randf())
			var r := 1.5 + 3.0 * rng.randf()
			draw_circle(p, r, Color(0.08, 0.07, 0.05, 0.8))
			draw_arc(p, r + 0.8, PI, TAU, 8, Color(0.6, 0.55, 0.42, 0.35), 1.0, true)

# ====================================================================== touch
## Tablets and phones. Godot turns taps and drags into mouse clicks and drags, so buttons, card
## menus and drag-to-trade already work; what a mouse does by hovering is done here by touching:
## hold a hand card to see it large (a quick tap opens its options), tap a small card to enlarge it
## until the next touch, hold anything with a hint (a button, a portrait) to read it.
func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if not touch:
			_set_touch(true)
		if e.index != 0:
			return
		touch_seq += 1
		if e.pressed:
			if zoom_frame != Engine.get_process_frames():
				_zoom_hide()      # a card enlarged by an earlier tap goes away at the next touch
			_touch_pass(modal_root)      # windows opened since: let a finger scroll them too
			_touch_pass(popup_root)
			touch_at = e.position
			touch_ms = Time.get_ticks_msec()
			touch_scroll = _scroll_text_at(e.position)
			_touch_hold(touch_seq)
		else:
			touch_scroll = null
			if Time.get_ticks_msec() - touch_ms > 450:
				_zoom_hide()      # held to peek: let go and it goes; a quick tap leaves it up
	elif e is InputEventScreenDrag and e.index == 0:
		if e.position.distance_to(touch_at) > 14.0:
			touch_seq += 1      # moving: not a long-press
			_zoom_hide()
		if touch_scroll != null and is_instance_valid(touch_scroll):
			var sb: VScrollBar = touch_scroll.get_v_scroll_bar()
			sb.value -= e.relative.y
	elif touch and e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION and e.relative.length() > 0.0:
		_set_touch(false)      # a real mouse on a touch laptop: hovering works again

func _set_touch(on: bool) -> void:
	touch = on
	HandCard.touch = on
	if on:
		_zoom_hide()
		_reset_hand_hover()
		for root in [board, menu_root, modal_root]:
			if root != null:
				_touch_pass(root)

## Panels and text let a dragging finger through to the scroll area behind them; hand cards,
## draggable cards and buttons keep their touches.
func _touch_pass(n: Node) -> void:
	if n == null:
		return
	for ch in n.get_children():
		if ch is Control and not (ch is BaseButton or ch is HandCard or ch is DragSrc or ch is LineEdit or ch is ScrollBar) \
				and ch.mouse_filter == Control.MOUSE_FILTER_STOP and ch != logbox:
			ch.mouse_filter = Control.MOUSE_FILTER_PASS
		_touch_pass(ch)

## A text box that scrolls itself (the newspaper log) under the finger, if any.
func _scroll_text_at(pos: Vector2) -> RichTextLabel:
	if logbox != null and logbox.is_visible_in_tree() and logbox.get_global_rect().has_point(pos):
		return logbox
	return null

## Long-press: after a moment without moving, show the hint of whatever is under the finger.
func _touch_hold(seq: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if seq != touch_seq or get_viewport().gui_is_dragging() or zoom != null:
		return
	var tip := _hint_at(touch_at)
	if tip != "":
		_toast(tip)

func _hint_at(pos: Vector2) -> String:
	var best := ""
	for root in [self, overlay]:
		for n in root.find_children("*", "Control", true, false):
			var c := n as Control
			if c.tooltip_text != "" and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.is_visible_in_tree() \
					and c.get_global_rect().has_point(pos):
				best = c.tooltip_text      # later in the tree draws on top
	return best

## Phones held upright: the table needs a landscape screen, so ask for the device to be turned.
func _check_orientation(sz := Vector2.ZERO) -> void:
	if sz == Vector2.ZERO:
		sz = get_viewport_rect().size
	var upright := sz.y > sz.x * 1.1 and (touch or DisplayServer.is_touchscreen_available() or sz != get_viewport_rect().size)
	if upright and turn_overlay == null:
		turn_overlay = ColorRect.new()
		(turn_overlay as ColorRect).color = Color(0.07, 0.07, 0.05, 0.97)
		turn_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		turn_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		var cc := CenterContainer.new()
		cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		turn_overlay.add_child(cc)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 24)
		cc.add_child(vb)
		var tr := Trefoil.new()
		tr.custom_minimum_size = Vector2(160, 160)
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
		var l := _lbl("TURN YOUR DEVICE SIDEWAYS", 64, C_INK, HEAD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		var l2 := _lbl("The table needs a landscape screen.", 40, C_MUT, MONO)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l2)
		var ly := CanvasLayer.new()
		ly.layer = 50
		ly.add_child(turn_overlay)
		add_child(ly)
	elif not upright and turn_overlay != null:
		turn_overlay.get_parent().queue_free()
		turn_overlay = null

# ====================================================================== style helpers
func _sb(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 10, pad := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s

func _lbl(text: String, fsize := 15, color := C_INK, font: Font = null, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _rtl(bb: String, fsize := 15, color := C_INK) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", fsize)
	r.add_theme_font_size_override("bold_font_size", fsize)
	r.add_theme_font_size_override("italics_font_size", fsize)
	r.add_theme_color_override("default_color", color)
	r.text = bb
	return r

## A button that stretches to share the width of its row, at a fixed height.
func _big(b: Button, h: float) -> Button:
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = h
	return b

func _btn(text: String, kind := "default", fsize := 16) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", HEAD)
	b.add_theme_font_size_override("font_size", fsize)
	var bg := C_PANEL2
	var bd := C_LINE
	var fg := C_INK
	var hbd := C_AMBER
	var hbg := Color("#2b2c1e")
	match kind:
		"primary":
			bg = C_AMBER
			bd = C_AMBER
			fg = Color("#17120a")
			hbg = Color("#ffc552")
		"danger":
			bg = Color("#3a1613")
			bd = Color("#7d2a24")
			fg = Color("#ffb4ac")
			hbd = C_RED
			hbg = Color("#4b1a16")
	var padh := 16 if fsize > 13 else 10
	var padv := 8 if fsize > 13 else 5
	for state in ["normal", "hover", "pressed", "disabled"]:
		var s := _sb(bg, bd, 1, 9)
		s.content_margin_left = padh
		s.content_margin_right = padh
		s.content_margin_top = padv
		s.content_margin_bottom = padv
		if state == "hover":
			s.bg_color = hbg
			s.border_color = hbd
		elif state == "pressed":
			s.bg_color = bg.darkened(0.15)
			s.border_color = hbd
		elif state == "disabled":
			s.bg_color = Color(bg, 0.35)
			s.border_color = Color(bd, 0.35)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.35))
	return b

func _chip(text: String, hot := false) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(C_PANEL2, Color("#6a5420") if hot else C_LINE, 1, 99, 0))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 2)
	m.add_theme_constant_override("margin_bottom", 2)
	m.add_child(_lbl(text, 13, C_AMBER if hot else C_MUT, MONO))
	pc.add_child(m)
	return pc

func _badge(text: String, fg: Color, bg: Color, bd: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var s := _sb(bg, bd, 1, 5)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", s)
	pc.add_child(_lbl(text, 12, fg, MONO))
	return pc

func _box(parent: Control, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(C_PANEL, C_LINE, 1, 12, 16))
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	if title != "":
		vb.add_child(_lbl(title.to_upper(), 16, C_AMBER, HEAD))
	parent.add_child(pc)
	return vb

func _tex(key: String, w: float, burnt := false) -> TextureRect:
	var t := TextureRect.new()
	t.texture = TEXB.get(key, TEX[key]) if burnt else TEX[key]
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.custom_minimum_size = Vector2(w, w * 430.0 / 330.0)
	t.tooltip_text = NPGame.INFO[key].name
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	if w < 100.0:
		t.mouse_entered.connect(_zoom_show.bind(t, key))
		t.mouse_exited.connect(func(): if not touch: _zoom_hide())
		t.tree_exiting.connect(_zoom_hide)
		t.gui_input.connect(func(e):
			if touch and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_zoom_show(t, key, true))
	return t

## Hovering a small card shows it large beside the pointer (on a touch screen: touching it).
func _zoom_show(src: Control, key: String, by_touch := false) -> void:
	if touch and not by_touch:
		return      # the emulated pointer "hovers" wherever a finger last was - ignore that
	_zoom_hide()
	zoom_frame = Engine.get_process_frames() if by_touch else -1
	if not is_instance_valid(src) or not src.is_visible_in_tree() or get_viewport().gui_is_dragging():
		return
	var zw := 210.0
	var zh := zw * 430.0 / 330.0
	zoom = TextureRect.new()
	zoom.texture = (src as TextureRect).texture if src is TextureRect else TEX[key]
	zoom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	zoom.stretch_mode = TextureRect.STRETCH_SCALE
	zoom.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	zoom.size = Vector2(zw, zh)
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := src.get_global_rect()
	var vp := get_viewport_rect().size
	var x := r.end.x + 12.0
	if x + zw > vp.x - 8.0:
		x = r.position.x - zw - 12.0
	var y := clampf(r.get_center().y - zh / 2.0, 8.0, vp.y - zh - 8.0)
	zoom.position = Vector2(maxf(8.0, x), y)
	fx_root.add_child(zoom)
	var again: bool = key == zoom_last_key and Time.get_ticks_msec() - zoom_last_ms < 400
	zoom_last_key = key
	if again:
		return      # the same card again straight after a rebuild: no fade, no flicker
	zoom.modulate.a = 0.0
	zoom.create_tween().tween_property(zoom, "modulate:a", 1.0, 0.1)

func _zoom_hide() -> void:
	if zoom != null and is_instance_valid(zoom):
		zoom_last_ms = Time.get_ticks_msec()
		zoom.queue_free()
	zoom = null

func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

## An AI's dossier photograph (assets/portraits/<persona>.png from tools/meshy_portraits.py),
## in a photo-paper frame; a stamped initial until the portrait exists.
func _portrait(p: NPGame.Player, s: float) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(s, s)
	var tex := _portrait_tex(p)
	# a thin rule in the player's colour round a photo toned down to sit in the dark panel
	frame.add_theme_stylebox_override("panel", _sb(Color("#1e2016") if tex != null else Color("#c9bb93"), _persona_color(p).darkened(0.15), 1, 3, 1))
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not p.alive and not ResourceLoader.exists(_portrait_path(p, true)):
			t.modulate = Color(0.6, 0.55, 0.5)      # no skeleton for this one: just fade the photo
		frame.add_child(t)
	else:
		var l := _lbl(p.name.split(" ")[-1].left(1), int(s * 0.55), Color("#2b241a"), HEAD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(l)
	frame.tooltip_text = p.name
	return frame

## An AI's head-shot for its seat (assets/portraits/<persona>_head.png; <persona>_dead_head.png, its
## skeleton, once it is eliminated), or null.
func _portrait_tex(p: NPGame.Player) -> Texture2D:
	if p.human:
		return null
	if not p.alive and ResourceLoader.exists(_portrait_path(p, true)):
		return load(_portrait_path(p, true))      # eliminated: their skeleton, in the same uniform
	var path := _portrait_path(p, false)
	return load(path) if ResourceLoader.exists(path) else null

func _portrait_path(p: NPGame.Player, dead: bool) -> String:
	return "res://assets/portraits/%s%s_head.png" % [str(p.persona.get("id", "")), "_dead" if dead else ""]

func _persona_color(p: NPGame.Player) -> Color:
	return Color(p.persona.color) if not p.persona.is_empty() else C_GREEN

# ====================================================================== boot
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# WWII look: stencil headings, typewriter text, field-manual cards on an old campaign map.
	HEAD = load("res://fonts/StardosStencil-Bold.ttf")
	MONO = load("res://fonts/SpecialElite-Regular.ttf")
	var th := Theme.new()
	th.default_font = load("res://fonts/CourierPrime-Regular.ttf")
	th.set_font("bold_font", "RichTextLabel", load("res://fonts/CourierPrime-Bold.ttf"))
	theme = th
	ui_theme = th
	for k in ORDER:
		TEX[k] = load("res://assets/ww2/%s.png" % k)
		if ResourceLoader.exists("res://assets/ww2/burnt/%s.png" % k):
			TEXB[k] = load("res://assets/ww2/burnt/%s.png" % k)
	for i in range(1, 7):
		if ResourceLoader.exists("res://assets/ui/bones/pile_%d.png" % i):
			BONES.append(load("res://assets/ui/bones/pile_%d.png" % i))
	CardBack.tex = load("res://assets/ww2/back.png")
	_load_cfg()
	# (never for the test and screenshot modes: they capture a fixed-size window)
	if bool(cfg.fullscreen) and not OS.has_feature("web") and DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().is_empty():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_build_sounds()
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var map := TextureRect.new()
	map.texture = load("res://assets/ww2/table.jpg")
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map)
	menu_root = _build_menu()
	add_child(menu_root)
	game_root = _build_shell()
	game_root.visible = false
	add_child(game_root)
	overlay = CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	for nm in ["modal_root", "popup_root", "fx_root"]:
		var c := Control.new()
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.theme = ui_theme      # the overlay is a CanvasLayer, so it does not inherit our theme
		overlay.add_child(c)
		set(nm, c)
	get_viewport().size_changed.connect(_on_resize)
	if DisplayServer.is_touchscreen_available():
		_set_touch(true)      # until a real mouse moves
	_check_orientation()
	if "--readme-shot" in OS.get_cmdline_user_args():
		_readme_shot.call_deferred()
	elif "--touchtest" in OS.get_cmdline_user_args():
		_touchtest.call_deferred()
	elif "--autotest" in OS.get_cmdline_user_args():
		_autotest.call_deferred()
	elif "--shots" in OS.get_cmdline_user_args():
		_shots.call_deferred()
	elif "--madshots" in OS.get_cmdline_user_args():
		_madshots.call_deferred()
	elif "--personashots" in OS.get_cmdline_user_args():
		_personashots.call_deferred()
	elif "--supershots" in OS.get_cmdline_user_args():
		_supershots.call_deferred()
	elif "--dragtest" in OS.get_cmdline_user_args():
		_dragtest.call_deferred()

func _load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://nuclear_poker.cfg") == OK:
		for k in cfg.keys():
			cfg[k] = cf.get_value("s", k, cfg[k])
		muted = bool(cf.get_value("s", "muted", false))
	cfg.players = str(cfg.players) if str(cfg.players) in ["3", "4", "5"] else "3"

func _save_cfg() -> void:
	var cf := ConfigFile.new()
	for k in cfg.keys():
		cf.set_value("s", k, cfg[k])
	cf.set_value("s", "muted", muted)
	cf.save("user://nuclear_poker.cfg")

# ====================================================================== sound (procedural)
func _make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var dur: float = {"test": 1.0, "attack": 0.8, "death": 1.3, "click": 0.12}[kind]
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in range(n):
		var u := float(i) / n
		var f := 520.0
		var gain := 0.06
		var shape := "tri"
		match kind:
			"test":
				f = 110.0 * pow(28.0 / 110.0, u)
				gain = 0.22
				shape = "saw"
			"attack":
				f = 1000.0 * pow(160.0 / 1000.0, u / 0.875)
				gain = 0.12
				shape = "sq"
			"death":
				f = 160.0 * pow(40.0 / 160.0, u / 0.92)
				gain = 0.3
				shape = "sin"
		phase += f / rate
		var ph := fposmod(phase, 1.0)
		var w := 0.0
		match shape:
			"saw": w = 2.0 * ph - 1.0
			"sq": w = 1.0 if ph < 0.5 else -1.0
			"sin": w = sin(TAU * ph)
			_: w = 4.0 * absf(ph - 0.5) - 1.0
		var amp := gain * pow(0.001 / gain, u)
		data.encode_s16(i * 2, int(clampf(w * amp, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s

## Sound effects: assets/sfx/<name>.mp3 (made by tools/elevenlabs_sfx.py) when present,
## otherwise a synthesised fallback for the core four. Missing sounds are simply silent.
const SFX_NAMES := ["draw", "click", "your_turn", "trade_offer", "trade_counter", "deal", "broken", "threat",
	"test", "attack", "death", "disarm", "standdown", "game_over", "screams"]
const SFX_VOL := {}      # the files are loudness-levelled by the generator; per-sound trims go here

func _build_sounds() -> void:
	for k in SFX_NAMES:
		var path := "res://assets/sfx/%s.mp3" % k
		var stream: AudioStream = null
		if ResourceLoader.exists(path):
			stream = load(path)
		elif k in ["test", "attack", "death", "click"]:
			stream = _make_sound(k)
		if stream == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = float(SFX_VOL.get(k, -2.0))
		add_child(p)
		sounds[k] = p
	_build_music()
	if ResourceLoader.exists("res://assets/music/funeral.mp3"):
		funeral = AudioStreamPlayer.new()
		funeral.stream = load("res://assets/music/funeral.mp3")
		add_child(funeral)
		funeral.finished.connect(func():
			music_level = -1      # the march is over: bring the right music layer back in
			_music_update())
	if ResourceLoader.exists("res://assets/sfx/ambience.mp3"):
		var amb: AudioStream = load("res://assets/sfx/ambience.mp3")
		if amb is AudioStreamMP3:
			amb.loop = true
		ambience = AudioStreamPlayer.new()
		ambience.stream = amb
		ambience.volume_db = -4.0
		add_child(ambience)

## Adaptive music: four layers (calm, uneasy, tense, crisis) generated by tools/elevenlabs_music.py
## play together in sync; only the one matching the current tension is audible, with cross-fades.
func _build_music() -> void:
	for lv in MUSIC_LEVELS:
		var path := "res://assets/music/%s.mp3" % lv
		if not ResourceLoader.exists(path):
			music.clear()
			return      # all four are needed for the cross-fades to line up
		var st: AudioStream = load(path)
		if st is AudioStreamMP3:
			st.loop = true
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.volume_db = -80.0
		add_child(p)
		music.append(p)

## How tense is the table? 0 calm, 1 someone has tested, 2 someone could strike now
## (or a threat is in the air), 3 blood has been spilt with weapons still armed, or a Superpower exists.
func _tension() -> int:
	if G == null:
		return 0
	var lv := 0
	var dead := G.players.size() - G.alive_list().size()
	for p in G.alive_list():
		if p.tested:
			lv = maxi(lv, 1)
		if not G.attack_types(p, true).is_empty():
			lv = maxi(lv, 2)
			if dead > 0 or (p.tested and G.has_all_caps(p)):
				lv = 3
	if not G.last_threat.is_empty():
		for pid in G.last_threat:
			if int(G.last_threat[pid]) >= G.turn_no - 3:
				lv = maxi(lv, 2)
	return lv

func _music_update() -> void:
	if music.is_empty() or DisplayServer.get_name() == "headless":
		return
	var playing: bool = G != null and game_root.visible and music_on and not muted
	if not playing:
		for p in music:
			p.stop()
		if funeral != null:
			funeral.stop()
		music_level = -1
		return
	if funeral != null and funeral.playing:
		return      # the funeral march has the floor; the layers come back when it ends
	if not music[0].playing:
		for p in music:
			p.volume_db = -80.0
			p.play()
		music_level = -1
	var lv := _tension() if not G.over else 0
	# tension rises at once but eases off slowly (about a round later), so the music doesn't flicker
	if not G.over and music_level >= 0 and lv < music_level:
		if G.turn_no < music_hold:
			return
		lv = music_level - 1
	if lv == music_level:
		return
	if lv > music_level:
		music_hold = G.turn_no + G.alive_list().size() + 1
	music_level = lv
	if "--trace-music" in OS.get_cmdline_user_args():
		print("MUSIC level ", lv, " turn ", G.turn_no)
	for i in range(music.size()):
		var tw := create_tween()
		tw.tween_property(music[i], "volume_db", MUSIC_DB if i == lv else -80.0, 3.0 if i == lv else 4.0).set_trans(Tween.TRANS_SINE)

## The war-room ambience runs during a game, when sound is on.
func _ambience(on: bool) -> void:
	if ambience == null or DisplayServer.get_name() == "headless":
		return
	if on and not muted:
		if not ambience.playing:
			ambience.play()
	else:
		ambience.stop()

## A nuclear strike has killed: screams as the blast dies away, then a dark, throbbing funeral march
## that takes over from the music for a while. Strikes in quick succession share one march.
func _lament() -> void:
	if muted or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(1.2).timeout
	snd("screams")
	if funeral == null or funeral.playing or not music_on:
		return
	await get_tree().create_timer(4.0).timeout
	if muted or funeral.playing or G == null or not game_root.visible:
		return
	for p in music:
		create_tween().tween_property(p, "volume_db", -80.0, 2.0)
	funeral.volume_db = -30.0
	funeral.play()
	create_tween().tween_property(funeral, "volume_db", MUSIC_DB + 2.0, 2.5).set_trans(Tween.TRANS_SINE)

func snd(kind: String) -> void:
	if muted or not sounds.has(kind) or DisplayServer.get_name() == "headless":
		return
	sounds[kind].play()

# ====================================================================== menu
func _build_menu() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var outer := VBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	root.add_child(outer)
	var hz := Hazard.new()
	hz.custom_minimum_size = Vector2(0, 10)
	outer.add_child(hz)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(center)
	var wrap := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		wrap.add_theme_constant_override("margin_" + side, 24)
	center.add_child(wrap)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 920
	col.add_theme_constant_override("separation", 10)
	wrap.add_child(col)

	var logo := HBoxContainer.new()
	logo.add_theme_constant_override("separation", 16)
	var tre := Trefoil.new()
	tre.custom_minimum_size = Vector2(64, 64)
	logo.add_child(tre)
	logo.add_child(_lbl("NUCLEAR", 58, C_INK, HEAD))
	logo.add_child(_lbl("POKER", 58, C_AMBER, HEAD))
	col.add_child(logo)
	col.add_child(_lbl("a fun, scary teaching game  ·  you vs. two to four powers", 14, C_MUT, MONO))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	col.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 14)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	cols.add_child(left)
	cols.add_child(right)

	var b1 := _box(left, "Classic rules")
	b1.add_child(_lbl("Adapted from the original rules. Each turn you draw a card OR offer a trade - and a trading partner may deceive you. Anyone can Test or Attack, in order of play around the table.", 14, C_MUT, null, true))

	var b3 := _box(right, "The table")
	b3.add_child(_lbl("PLAYERS AT THE TABLE", 12, C_MUT, MONO))
	players_opt = OptionButton.new()
	players_opt.focus_mode = Control.FOCUS_NONE
	# the list just says "N players"; the closed box spells out who is playing
	for n in [3, 4, 5]:
		players_opt.add_item("%d players" % n)
	for st0 in ["normal", "hover", "pressed"]:
		players_opt.add_theme_stylebox_override(st0, _sb(C_PANEL2, C_LINE, 1, 8, 9))
	players_opt.select(int(cfg.players) - 3)
	_players_label()
	players_opt.item_selected.connect(func(i):
		cfg.players = str(i + 3)
		_players_label()
		_refresh_opts())
	b3.add_child(players_opt)
	b3.add_child(_lbl("YOUR CALLSIGN", 12, C_MUT, MONO))
	name_edit = LineEdit.new()
	name_edit.text = str(cfg.name)
	name_edit.max_length = 18
	name_edit.add_theme_stylebox_override("normal", _sb(C_PANEL2, C_LINE, 1, 8, 9))
	name_edit.add_theme_stylebox_override("focus", _sb(C_PANEL2, C_AMBER, 1, 8, 9))
	b3.add_child(name_edit)
	opp_btns.clear()
	opp_lbls.clear()
	# opponents in a 2 x 2 grid, so even a 5-player table fits without scrolling
	var og := GridContainer.new()
	og.columns = 2
	og.add_theme_constant_override("h_separation", 10)
	og.add_theme_constant_override("v_separation", 8)
	b3.add_child(og)
	for i in range(4):
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(_lbl("OPPONENT %d" % (i + 1), 12, C_MUT, MONO))
		opp_lbls.append(cell)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.clip_text = true
		ob.add_item("Random")
		ob.add_theme_constant_override("icon_max_width", 28)
		ob.get_popup().add_theme_constant_override("icon_max_width", 32)
		for pid in PERSONA_IDS.slice(1):
			var pe: Dictionary = NPGame.PERSONAS[pid]
			var hp := "res://assets/portraits/%s_head.png" % pid
			if ResourceLoader.exists(hp):
				ob.add_icon_item(load(hp), pe.name)
			else:
				ob.add_item(pe.name)
		for st in ["normal", "hover", "pressed"]:
			ob.add_theme_stylebox_override(st, _sb(C_PANEL2, C_LINE, 1, 8, 9))
		ob.select(maxi(0, PERSONA_IDS.find(cfg["p%d" % (i + 1)])))
		cell.add_child(ob)
		og.add_child(cell)
		opp_btns.append(ob)
	# one row per card type: the four Technologies, then the four Capabilities
	var strip := GridContainer.new()
	strip.columns = 4
	strip.add_theme_constant_override("h_separation", 8)
	strip.add_theme_constant_override("v_separation", 8)
	for k in NPGame.TECH + NPGame.CAPS:
		strip.add_child(_tex(k, 64))
	b1.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var begin := _btn("Begin", "primary", 22)
	begin.pressed.connect(_on_begin)
	row.add_child(begin)
	var how := _btn("How to play")
	how.pressed.connect(_rules_modal)
	row.add_child(how)
	var fsm := _btn(_fs_label())
	fsm.pressed.connect(_toggle_fullscreen)
	row.add_child(fsm)
	btn["fs_menu"] = fsm
	left.add_child(row)
	btn["begin"] = begin
	var cred := _rtl("Original game by [b]Vinay Gupta[/b] ([url=https://twitter.com/leashless]@leashless[/url], [url=mailto:VinayGupta@butteredsidedown.co.uk]VinayGupta@butteredsidedown.co.uk[/url]) & [b]Dan Carter[/b] ([url=https://files.howtolivewiki.com/nuclear_poker_card_game_proliferation.pdf]original rules, PDF[/url]), GNU FDL licensed. Unofficial digital adaptation. \"The only winning move is not to play.\"", 12, C_MUT)
	cred.meta_clicked.connect(func(m): OS.shell_open(str(m)))
	right.add_child(cred)
	_refresh_opts()
	return root

func _players_label() -> void:
	var n := players_opt.selected + 3
	players_opt.text = "%d players - you and %s powers" % [n, ["two", "three", "four"][n - 3]]

func _refresh_opts() -> void:
	var n_ai := int(cfg.players) - 1
	for i in range(opp_btns.size()):
		opp_btns[i].visible = i < n_ai
		opp_lbls[i].visible = i < n_ai

func _on_begin() -> void:
	cfg.name = name_edit.text.strip_edges().left(18) if name_edit.text.strip_edges() != "" else "You"
	cfg.p1 = PERSONA_IDS[opp_btns[0].selected]
	cfg.p2 = PERSONA_IDS[opp_btns[1].selected]
	cfg.p3 = PERSONA_IDS[opp_btns[2].selected]
	cfg.p4 = PERSONA_IDS[opp_btns[3].selected]
	cfg.players = str(players_opt.selected + 3)
	_save_cfg()
	_start_game()

# ====================================================================== game shell
func _build_shell() -> Control:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	var tb := PanelContainer.new()
	var tbs := _sb(C_BG2, C_LINE, 0, 0, 8)
	tbs.border_width_bottom = 1
	tbs.content_margin_left = 14
	tbs.content_margin_right = 14
	tb.add_theme_stylebox_override("panel", tbs)
	topbar = HBoxContainer.new()
	topbar.add_theme_constant_override("separation", 10)
	tb.add_child(topbar)
	root.add_child(tb)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 0)
	root.add_child(main)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(sc)
	board_scroll = sc
	var mg := MarginContainer.new()
	mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + side, 12)
	sc.add_child(mg)
	board = VBoxContainer.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.add_theme_constant_override("separation", 10)
	mg.add_child(board)
	var side := PanelContainer.new()
	var ss := _sb(C_BG2, C_LINE, 0, 0, 12)
	ss.border_width_left = 1
	side.add_theme_stylebox_override("panel", ss)
	side.custom_minimum_size.x = 340
	main.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	side.add_child(sv)
	map_box = VBoxContainer.new()
	sv.add_child(map_box)
	sv.add_child(HSeparator.new())
	# The log is the front page of a 1940s newspaper: masthead, dateline, and the news in a column
	# of dark ink on tiled newsprint.
	var ink := Color("#1f1b14")
	var sheet := PanelContainer.new()
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tx := StyleBoxTexture.new()
	tx.texture = load("res://assets/ui/newsprint.png")
	tx.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	tx.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	tx.set_content_margin_all(10)
	tx.content_margin_top = 6
	sheet.add_theme_stylebox_override("panel", tx)
	sv.add_child(sheet)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	sheet.add_child(col)
	var mast := _lbl("The Atomic Herald", 30, ink, load("res://fonts/UnifrakturCook-Bold.woff2"))
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(mast)
	col.add_child(_rule(ink, 2.0))
	var dl := HBoxContainer.new()
	var paper_font: Font = load("res://fonts/OldStandard-Regular.woff2")
	dl.add_child(_lbl("LATE EDITION", 11, ink, paper_font))
	dl.add_child(_spacer())
	log_edition = _lbl("ROUND 1", 11, ink, paper_font)
	dl.add_child(log_edition)
	dl.add_child(_spacer())
	dl.add_child(_lbl("ONE CENT", 11, ink, paper_font))
	col.add_child(dl)
	col.add_child(_rule(ink, 1.0))
	col.add_child(_rule(ink, 1.0, 2))
	logbox = RichTextLabel.new()
	logbox.bbcode_enabled = true
	logbox.scroll_following = true
	logbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	logbox.custom_minimum_size.y = 120
	logbox.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	logbox.add_theme_font_override("normal_font", paper_font)
	logbox.add_theme_font_override("bold_font", load("res://fonts/OldStandard-Bold.woff2"))
	logbox.add_theme_font_override("italics_font", load("res://fonts/OldStandard-Italic.woff2"))
	logbox.add_theme_font_size_override("normal_font_size", 15)
	logbox.add_theme_font_size_override("bold_font_size", 15)
	logbox.add_theme_font_size_override("italics_font_size", 15)
	logbox.add_theme_constant_override("line_separation", 1)
	logbox.add_theme_constant_override("paragraph_separation", 7)
	logbox.add_theme_color_override("default_color", ink)
	var clear := StyleBoxEmpty.new()
	clear.content_margin_top = 4
	clear.content_margin_bottom = 12      # room under the last line, so it is never cut off
	logbox.add_theme_stylebox_override("normal", clear)
	logbox.add_theme_stylebox_override("focus", clear)
	col.add_child(logbox)
	return root

## A printed rule across a newspaper column.
func _rule(c: Color, h: float, gap := 0) -> Control:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size.y = h
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if gap > 0:
		var mc := MarginContainer.new()
		mc.add_theme_constant_override("margin_top", -gap)
		mc.add_child(r)
		return mc
	return r


# ====================================================================== start / events
func _start_game() -> void:
	var ids := PERSONA_IDS.slice(1)
	var n_ai := clampi(int(cfg.players) - 1, 2, 4)
	var picks: Array = []
	for i in range(n_ai):
		picks.append(str(cfg["p%d" % (i + 1)]))
	for i in range(n_ai):
		if picks[i] == "random":
			var pool: Array = ids.filter(func(x): return not picks.has(x))
			if pool.is_empty():
				pool = ids
			picks[i] = pool[randi() % pool.size()]
	var plist: Array = [{"name": cfg.name, "human": true}]
	var seen := {}
	for pid in picks:
		var nm: String = NPGame.PERSONAS[pid].name
		var k := int(seen.get(pid, 0))
		seen[pid] = k + 1
		if k > 0:
			nm += " " + ["", "II", "III", "IV"][mini(k, 3)]
		plist.append({"name": nm, "persona": pid})
	G = NPGame.new()
	G.setup({"players": plist})
	ME = G.players[0]
	end_shown = false
	mad_pic = -1
	betrayals.clear()
	died_at.clear()
	ff = false
	fresh.clear()
	paused = 0
	log_shown = 0
	logbox.clear()
	_close_modal(true)
	_close_popup()
	G.event.connect(_on_event)
	menu_root.visible = false
	game_root.visible = true
	_ambience(true)
	G.log_msg("Game on - Classic rules, %d players. %s goes first." % [G.players.size(), G.cur().name], "sys")
	_pump()

func _on_event(t: String, d: Dictionary) -> void:
	match t:
		"test":
			_fx("Nuclear Test", "test")
			snd("test")
		"superpower":
			_fx("Nuclear Superpower", "test")
			snd("test")
			_toast(("You are" if d.p == ME else d.p.name + " is") + " a Nuclear Superpower: all four Capabilities on the table.")
		"attack":
			_fx("Launch Detected", "attack")
			snd("attack")
		"death":
			died_at[d.p.id] = Time.get_ticks_msec()
			_fx("You are eliminated" if d.p == ME else d.p.name + " eliminated", "death")
			snd("death")
			_shake()
			if d.get("by", null) != null:
				_lament()
		"threat":
			snd("threat")
			_toast("%s threatens %s!" % [d.from.name, d.to.name])
		"disarm_all":
			snd("disarm")
		"demand_paid":
			if d.to == ME:
				fresh[d.c.id] = true
				_toast("%s gives in: you trade your %s for their %s." % [d.from.name, NPGame.INFO[d.offer.key].name, NPGame.INFO[d.c.key].name])
			elif d.from == ME:
				fresh[d.offer.id] = true
		"draw":
			if d.p == ME:
				fresh[d.c.id] = true
				snd("draw")
		"trade_offer":
			snd("trade_offer")
		"trade_counter":
			snd("trade_counter")
		"give":
			snd("deal")
		"renege":
			snd("broken")      # the sound and the newspaper's red headline tell it; nothing pops up
			if d.to == ME:
				betrayals[d.p.id] = int(betrayals.get(d.p.id, 0)) + 1
		"turn":
			if d.p == ME:
				snd("your_turn")
		"over":
			_ambience(false)
			snd("standdown" if d.kind in ["ceasefire", "stalemate", "mad", "hegemony"] else "game_over")

# ====================================================================== driver
func _pump() -> void:
	pump_token += 1
	var tok := pump_token
	if G == null:
		return
	var st := G.status()
	_render()
	if st == "over":
		_finish()
		return
	if st == "prompt":
		if str(G.prompt.get("type", "")) == "trade":
			pass      # answered in place: in the trade areas on the board
		elif str(G.prompt.get("type", "")) == "threat":
			_threat_modal()
		elif str(G.prompt.get("type", "")) == "demand":
			_demand_modal()
		elif str(G.prompt.get("type", "")) == "ceasefire":
			_ceasefire_modal()
		else:
			_counter_modal()
		return
	if st == "human":
		_on_human_turn(tok)
		return
	var delay: float = ((AI_DELAY + _reading_time()) if ME.alive else (0.04 if ff else 0.26)) / speed
	await get_tree().create_timer(delay).timeout
	if tok != pump_token or G == null:
		return
	if paused > 0:
		_pump()
		return
	G.step()
	_pump()

func _on_human_turn(tok: int) -> void:
	if G.phase == "play":
		var L := G.legal(ME)
		if not L.can_research and ME.hand.is_empty():
			await get_tree().create_timer(0.7 / speed).timeout
			if tok == pump_token and G != null and G.cur() == ME and G.phase == "play":
				G.play_skip(ME)
				_pump()

func _fs_on() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _fs_label() -> String:
	return "Windowed" if _fs_on() else "Fullscreen"

func _toggle_fullscreen() -> void:
	var on := not _fs_on()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if on and OS.has_feature("web"):
		JavaScriptBridge.eval("try { screen.orientation.lock('landscape').catch(function(){}); } catch (e) {}", true)
	cfg.fullscreen = on
	_save_cfg()
	_refresh_fs_buttons()

func _refresh_fs_buttons() -> void:
	if btn.has("fs_menu") and is_instance_valid(btn.fs_menu):
		btn.fs_menu.text = _fs_label().to_upper()
	if G != null and game_root.visible:
		_render_top()

func _on_resize() -> void:
	_check_orientation()
	_refresh_fs_buttons()
	if G != null and game_root.visible:
		_render()

# ====================================================================== render
func _render() -> void:
	if G == null:
		return
	_zoom_hide()
	_render_board()      # first: it resets the button registry
	_render_top()
	_render_side()
	if touch:
		_touch_pass(board)
	else:
		_refresh_hover.call_deferred()

## The board is rebuilt whenever the game moves on, so the card under a still mouse is a new one
## that has not been told it is hovered. Nudge the pointer (a zero-length move) so it is.
func _refresh_hover() -> void:
	if touch or get_viewport().gui_is_dragging() or DisplayServer.get_name() == "headless":
		return
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_mouse_position()
	ev.global_position = ev.position
	ev.button_mask = Input.get_mouse_button_mask()
	get_viewport().push_input(ev)
	_music_update()
	if debug_panel != null:
		_build_debug()

func _render_top() -> void:
	_clear(topbar)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 6)
	brand.add_child(_lbl("NUCLEAR", 22, C_INK, HEAD))
	brand.add_child(_lbl("POKER", 22, C_AMBER, HEAD))
	topbar.add_child(brand)
	topbar.add_child(_chip("Classic", true))
	topbar.add_child(_chip("%d players" % G.players.size()))
	topbar.add_child(_chip("Round %d" % G.round_no))
	topbar.add_child(_chip("Deck %d" % G.deck.size()))
	topbar.add_child(_spacer())
	if G.can_disarm(ME):      # only a nuclear power (tested) holding Capabilities
		var db := _btn("Disarm", "default", 13)
		db.tooltip_text = "Return all your Capability cards to the deck - allowed at any time."
		db.pressed.connect(_disarm_modal)
		topbar.add_child(db)
		btn["disarm"] = db
	var cf := _btn("Propose stand-down", "default", 13)
	cf.disabled = G.over or not ME.alive
	if not cf.disabled and not G.can_propose_ceasefire(ME):
		cf.disabled = true
		cf.tooltip_text = "Refused - you can ask again after a full round, or once something changes."
	cf.pressed.connect(_act_ceasefire)
	topbar.add_child(cf)
	var ru := _btn("Rules", "default", 13)
	ru.pressed.connect(_rules_modal)
	topbar.add_child(ru)
	var fsb := _btn(_fs_label(), "default", 13)
	fsb.pressed.connect(_toggle_fullscreen)
	topbar.add_child(fsb)
	var so := _btn("Sound: off" if muted else "Sound: on", "default", 13)
	so.pressed.connect(func():
		muted = not muted
		_save_cfg()
		_ambience(G != null and not G.over)
		_music_update()
		_render_top())
	topbar.add_child(so)
	var me := _btn("Menu", "default", 13)
	me.pressed.connect(_act_menu)
	topbar.add_child(me)

func _render_board() -> void:
	_clear(board)
	btn.clear()
	seat_zones.clear()
	var vw := get_viewport_rect().size.x
	card_w = clampf(vw * 0.062, 72.0, 112.0)
	mini_w = clampf(vw * (0.031 if G.players.size() < 5 else 0.027), 32.0, 56.0)
	var opps := HBoxContainer.new()
	opps.add_theme_constant_override("separation", 12)
	for i in range(1, G.players.size()):
		opps.add_child(_seat(G.players[i]))
	board.add_child(opps)
	board.add_child(_center_band())
	board.add_child(_me_panel())

func _zone(label: String, items: Array, empty_text: String) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.add_child(_lbl(label.to_upper(), 11, C_MUT, MONO))
	vb.add_child(_strip(items, mini_w, empty_text))
	return vb

func _strip(items: Array, w: float, empty_text := "") -> CardStrip:
	var st := CardStrip.new()
	st.cw = w
	st.ch = w * 430.0 / 330.0
	st.custom_minimum_size.y = st.ch
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		st.add_child(it)
	if items.is_empty() and empty_text != "":
		st.add_child(_lbl(empty_text, 12, C_MUT, MONO))
	st.layout.call_deferred()
	return st

## The trade area of a seat. Trade cards are face down: only their owner sees them.
func _answering() -> bool:
	return G != null and str(G.prompt.get("type", "")) == "trade" and G.prompt.player == ME

func _answer_trade(cid: int) -> void:
	if _answering():
		G.answer_trade(cid)
		_after_human()

## The trade cards to show in p's trade space: [{c, label, tip}].
func _trade_items_for(p: NPGame.Player) -> Array:
	var pr := G.prompt
	var ptype := str(pr.get("type", ""))
	var res: Array = []
	var nm := func(x: NPGame.Player) -> String: return "YOU" if x == ME else x.name.to_upper()
	for q in G.players:
		for c in q.trade:
			var to: NPGame.Player = q
			var label := ""
			var tip := "In a trade."
			var seen := false
			if ptype == "trade" and int(c.id) == int(pr.card_id):
				to = pr.player
				label = "OFFER FROM " + nm.call(q)
				tip = "Offered by %s. Answer with a card of your own, or decline." % q.name
				seen = to == ME      # you may look at a card offered to you
			else:
				for d in G.debts:
					if int(d.pledge) == int(c.id):
						to = G.players[d.from]
						label = "PLEDGE FROM " + nm.call(q)
						tip = "Owed by %s - delivered on their next turn, or the deal is broken." % q.name
			if to == p:
				# face down: you see only your own cards; everyone else's are backs until they arrive
				res.append({"c": c, "label": label, "tip": tip, "mine": q == ME, "seen": seen})
	return res

## What is left of you once you are destroyed by a nuclear attack: a smouldering pile of charred bones
## in your trade area. Just after the death it drops in and settles in a burst of embers; then it smoulders on.
func _bones(p: NPGame.Player, w: float) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(Color("#140f0be6"), Color("#4a2a1a"), 1, 8, 6))
	pc.custom_minimum_size.y = w * 430.0 / 330.0 + 36.0      # as tall as a trade area, so seats line up
	pc.clip_contents = true
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(box)
	if BONES.is_empty():
		return pc
	var pile := TextureRect.new()
	pile.texture = BONES[p.id % BONES.size()]
	pile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pile.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.tooltip_text = "%s - destroyed" % p.name
	box.add_child(pile)
	var smoke := _smoulder(false)
	var embers := _smoulder(true)
	box.add_child(smoke)
	box.add_child(embers)
	box.resized.connect(func():
		pile.pivot_offset = Vector2(box.size.x / 2.0, box.size.y)
		smoke.position = Vector2(box.size.x / 2.0, box.size.y * 0.55)
		embers.position = Vector2(box.size.x / 2.0, box.size.y * 0.8)
		smoke.emission_rect_extents = Vector2(box.size.x * 0.2, 4)
		embers.emission_rect_extents = Vector2(box.size.x * 0.3, 3))
	# the embers in the ashes glow and fade, on and on
	var glow := pile.create_tween().set_loops()
	glow.tween_property(pile, "modulate", Color(1.18, 1.0, 0.86), 0.9 + randf() * 0.5).set_trans(Tween.TRANS_SINE)
	glow.tween_property(pile, "modulate", Color(0.92, 0.9, 0.88), 1.1 + randf() * 0.5).set_trans(Tween.TRANS_SINE)
	var age := Time.get_ticks_msec() - int(died_at.get(p.id, -100000))
	if age < 1500:      # just destroyed: the pile falls into place
		pile.scale = Vector2(0.4, 0.4)
		pile.position.y = -40.0
		pile.self_modulate.a = 0.0
		var tw := pile.create_tween().set_parallel(true)
		tw.tween_property(pile, "self_modulate:a", 1.0, 0.25)
		tw.tween_property(pile, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(pile, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		embers.amount = 40
		embers.explosiveness = 0.6
	return pc

## Smoke curling up from a bone pile (`sparks` false) or embers spitting out of it (true).
func _smoulder(sparks: bool) -> CPUParticles2D:
	var e := CPUParticles2D.new()
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	e.direction = Vector2(0, -1)
	e.gravity = Vector2(0, -6 if not sparks else 30)
	var g := Gradient.new()
	if sparks:
		e.amount = 14
		e.lifetime = 1.4
		e.spread = 50.0
		e.initial_velocity_min = 12.0
		e.initial_velocity_max = 40.0
		e.scale_amount_min = 1.5
		e.scale_amount_max = 3.0
		g.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
		g.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
	else:
		e.amount = 10
		e.lifetime = 3.2
		e.preprocess = 3.2      # already smoking when the seat is redrawn
		e.spread = 14.0
		e.initial_velocity_min = 8.0
		e.initial_velocity_max = 16.0
		var dot := GradientTexture2D.new()
		dot.fill = GradientTexture2D.FILL_RADIAL
		dot.fill_from = Vector2(0.5, 0.5)
		dot.fill_to = Vector2(1.0, 0.5)
		dot.width = 32
		dot.height = 32
		var dg := Gradient.new()
		dg.set_color(0, Color(1, 1, 1, 0.55))
		dg.set_color(1, Color(1, 1, 1, 0.0))
		dot.gradient = dg
		e.texture = dot
		e.scale_amount_min = 0.5
		e.scale_amount_max = 1.1
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.4))
		grow.add_point(Vector2(1, 1.6))
		e.scale_amount_curve = grow
		g.set_color(0, Color(0.55, 0.52, 0.48, 0.5))
		g.set_color(1, Color(0.4, 0.38, 0.36, 0.0))
	e.color_ramp = g
	return e

func _trade_zone(p: NPGame.Player, w: float) -> Control:
	# Drop a card here: on another player's trade space to offer it to them,
	# on your own to answer an offer made to you.
	var pc := DropTarget.new()
	if p == ME:
		pc.accept = func(_d): return _answering()
		pc.on_drop = func(d): _answer_trade(int(d.cid))
		me_zone = pc
	else:
		pc.accept = func(_d): return _can_offer() and p.alive
		pc.on_drop = func(d): _drop_offer(p, d)
		seat_zones[p.id] = pc
	pc.add_theme_stylebox_override("panel", _sb(Color("#1d1e13e6"), Color("#6e6743"), 1, 8, 6))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	pc.add_child(vb)
	var pr := G.prompt
	var mine: bool = p == ME and not pr.is_empty() and pr.player == ME
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	hdr.custom_minimum_size.y = 30 if p == ME else 14      # same height with or without buttons
	hdr.add_child(_lbl("TRADE AREA", 11, Color("#ddcc98"), MONO))
	hdr.add_child(_spacer())
	vb.add_child(hdr)
	# Every card in play in a trade is shown in the trade space of the player it is meant FOR,
	# under the name of the player it comes from: an offer in the target's space, an answer in the
	# offerer's space, a pledged card in the space of the player it is owed to.
	# Fixed-size slots, so the area never grows or shrinks as cards come and go.
	var iw := maxf(w, 104.0)
	var ch := w * 430.0 / 330.0
	var slots: Array = []
	for it in _trade_items_for(p):
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(iw, ch + 16)
		var cap := _lbl(it.label, 10, C_AMBER, MONO)
		cap.clip_text = true
		cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cap.size = Vector2(iw, 14)
		cap.tooltip_text = it.label
		slot.add_child(cap)
		var cp := PanelContainer.new()
		cp.position = Vector2(0, 16)
		cp.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), Color("#ddcc98"), 2, 5, 0))
		if it.mine:
			var tx := _tex(it.c.key, w)
			tx.tooltip_text = "Your %s - only you can see it. %s" % [NPGame.INFO[it.c.key].name, it.tip]
			tx.modulate = Color(1, 1, 1, 0.8)
			cp.add_child(tx)
		elif it.get("seen", false):
			var tx2 := _tex(it.c.key, w)
			tx2.tooltip_text = "%s - shown to you only. %s" % [NPGame.INFO[it.c.key].name, it.tip]
			cp.add_child(tx2)
		else:
			var bk := CardBack.new()
			bk.custom_minimum_size = Vector2(w, w * 430.0 / 330.0)
			bk.tooltip_text = "You will see it when it arrives. " + it.tip
			cp.add_child(bk)
		slot.add_child(cp)
		slots.append(slot)
	var hint := "drag a card here to answer" if (mine and str(pr.get("type", "")) == "trade") else "no offer"
	var st := _strip(slots, iw, hint if slots.is_empty() else "")
	st.ch = ch + 16
	st.custom_minimum_size.y = ch + 16
	st.gap = 8.0
	vb.add_child(st)
	if mine and str(pr.get("type", "")) == "trade":
		var no := _btn("Decline", "default", 13)
		no.tooltip_text = "Decline %s's offer - or drag a card from your hand in here to answer it." % pr.from.name
		no.pressed.connect(_answer_trade.bind(-1))
		hdr.add_child(no)
		btn["trade_no"] = no
		var hook := Button.new()      # test hook: lets the UI bot answer without a real drag
		hook.visible = false
		hook.pressed.connect(func():
			for c in ME.hand:
				_answer_trade(c.id)
				return
			_answer_trade(-1))
		vb.add_child(hook)
		btn["trade_counter"] = hook
	_pass_through(pc)
	return pc

func _mini_pub(key: String, burnt := false) -> Control:
	if burnt:
		return _tex(key, mini_w, true)      # the burnt card's own ragged edge is its frame
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), C_AMBER, 2, 5, 0))
	pc.add_child(_tex(key, mini_w))
	return pc

func _seat(p: NPGame.Player) -> Control:
	var turn: bool = G.turn == p.id and not G.over and p.alive
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _sb(C_PANEL, C_AMBER if turn else C_LINE, 2 if turn else 1, 12, 10))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	pc.add_child(vb)
	var hd := HFlowContainer.new()
	hd.add_theme_constant_override("h_separation", 8)
	hd.add_theme_constant_override("v_separation", 3)
	var five := G.players.size() >= 5
	hd.add_child(_lbl(p.name.to_upper(), 15 if five else 20, C_INK, HEAD))
	if betrayals.has(p.id):      # a standing reminder: this power cheated you
		var nb := int(betrayals[p.id])
		hd.add_child(_badge("BROKE %s WITH YOU" % ("A DEAL" if nb == 1 else "%d DEALS" % nb), Color("#ffd9d2"), Color("#5a1a12"), Color("#c0392b")))
	if p.alive:
		for d in G.debts:
			if d.to == p.id:
				hd.add_child(_badge("OWES %s A CARD" % ("YOU" if d.from == ME.id else G.players[d.from].name.to_upper()), Color("#ddcc98"), Color("#2a2716"), Color("#6e6743")))
	if G.is_superpower(p):
		hd.add_child(_badge("SUPERPOWER", Color("#ffe08a"), Color("#3a1a0a"), Color("#a5541c")))
	elif p.tested:
		hd.add_child(_badge("TESTED", Color("#e9c977"), Color("#33290f"), Color("#7a5d18")))
	if not p.alive:
		hd.add_child(_badge(("killed by " + G.players[p.eliminated_by].name) if p.eliminated_by >= 0 else "eliminated", C_MUT, C_PANEL2, C_LINE))
	# Fixed-height header (name + badges), clipped, so every seat's cards line up and never move.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_portrait(p, 52.0 if G.players.size() < 5 else 46.0))
	var hold := Control.new()
	hold.clip_contents = true
	hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold.custom_minimum_size.y = 52 if G.players.size() < 5 else 46
	hd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hold.add_child(hd)
	row.add_child(hold)
	vb.add_child(row)
	var hand_items: Array = []
	var unk := 0
	for c in p.hand:
		if c.pub:
			hand_items.append(_mini_pub(c.key, not p.alive))      # a destroyed power's hand lies burnt and singed
		else:
			unk += 1
	var backs: Array = []
	for i in range(unk):
		var cb := CardBack.new()
		cb.custom_minimum_size = Vector2(mini_w, mini_w * 430.0 / 330.0)
		backs.append(cb)
	vb.add_child(_zone("Hand · %d card%s" % [p.hand.size(), "" if p.hand.size() == 1 else "s"], backs + hand_items, "(empty)"))
	var tbl: Array = []
	for c in p.table:
		tbl.append(_tex(c.key, mini_w, not p.alive))
	vb.add_child(_zone("On the table", tbl, "nothing yet"))
	vb.add_child(_trade_zone(p, mini_w))
	if not p.alive:
		pc.modulate = Color(0.8, 0.78, 0.74)      # dimmed, but their revealed hand stays readable
	_pass_through(pc)
	return pc

## Extra seconds to leave the banner up so a long move can be read: about 30 characters a second
## beyond the first 40, at most 3 more seconds.
func _reading_time() -> float:
	if G == null or G.log_entries.is_empty():
		return 0.0
	var n: int = str(G.log_entries.back().text).length()
	return clampf((n - 40) / 30.0, 0.0, 3.0)

## While the AIs play, the banner reports the move just made (the latest line of the event log)
## instead of a generic "thinking...".
## The log is written in the third person ("Volkov offers Okafor a card"). When your callsign is
## "You", put your own lines into the second person: "You answer", "your next turn", "offers you".
func _you(t: String) -> String:
	if ME == null or ME.name != "You":
		return t
	var rx := RegEx.create_from_string("\\bYou's\\b")
	t = rx.sub(t, "your", true)
	t = RegEx.create_from_string("(^|[.!?] )your\\b").sub(t, "$1Your", true)
	var verb := RegEx.create_from_string("\\bYou ([A-Za-z]+)\\b")
	var out := ""
	var at := 0
	for mt in verb.search_all(t):
		var w := mt.get_string(1)
		var low := w.to_lower()
		var fixed := w
		if low == "has":
			fixed = "have"
		elif low == "is":
			fixed = "are"
		elif low == "was":
			fixed = "were"
		elif low.ends_with("ches") or low.ends_with("shes") or low.ends_with("sses") or low.ends_with("xes"):
			fixed = w.left(w.length() - 2)
		elif low.ends_with("s") and not low.ends_with("ss") and low.length() > 3:
			fixed = w.left(w.length() - 1)
		if w == w.to_upper() and w.length() > 1:
			fixed = fixed.to_upper()
		out += t.substr(at, mt.get_start(1) - at) + fixed
		at = mt.get_end(1)
	t = out + t.substr(at)
	if t.begins_with("You "):      # the rest of a sentence about you
		for pair in [[" of their own", " of your own"], ["(draws a card)", "(draw a card)"], [" and keeps ", " and keep "], ["- returns ", "- return "], [" in and returns ", " in and return "]]:
			t = t.replace(pair[0], pair[1])
	# "offers You a card" -> "offers you a card" (not at the start of a sentence)
	return RegEx.create_from_string("([a-z,] )You\\b").sub(t, "$1you", true)

func _last_play() -> String:
	if G.log_entries.is_empty():
		return ""
	var e: Dictionary = G.log_entries.back()
	var col: String = {"attack": "#e0644e", "death": "#e0644e", "test": "#e9c977"}.get(e.tone, "#efe5c8")
	return "[color=%s]%s[/color]" % [col, _you(str(e.text)).replace("[", "(")]

func _banner() -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := ""
	var tone := "n"
	if G.over:
		text = "[b]The game is over.[/b] This is the final board."
	elif not ME.alive:
		text = "You were eliminated. The game continues without you..."
		tone = "dead"
	else:
		var wa := _war_peek()
		var pt := str(G.prompt.get("type", ""))
		if pt == "trade" and G.prompt.player == ME:
			text = "[b][color=#f2b134]%s offers you %s.[/color][/b] Drag one of your cards into your trade area to answer - or decline." % [G.prompt.from.name, NPGame.INFO[str(G.prompt.card_key)].name if G.prompt.has("card_key") else "a card"]
			tone = "you"
		elif G.phase == "honour":
			if G.cur() == ME and not G._debts_of(ME).is_empty():
				text = "[b][color=#f2b134]A trade is due.[/color][/b] You pledged a card to %s. Deliver it - or break the deal." % G.players[G._debts_of(ME)[0].from].name
				tone = "you"
			else:
				text = _last_play()
		elif G.phase == "play":
			if G.cur() == ME:
				text = ""      # just the Research button (and drag-to-trade); How to play explains the rest
				tone = "you"
			else:
				text = _last_play()
		elif wa == ME.id:
			text = "[b][color=#f2b134]Exchange window.[/color][/b] Declare a Nuclear Test, an Attack or a Threat - or stand down."
			tone = "you"
		elif wa >= 0:
			text = _last_play()
		else:
			text = _last_play()
	var bg := C_PANEL2
	var bd := C_LINE
	if tone == "you":
		bg = Color("#241f12")
		bd = C_AMBER
	elif tone == "dead":
		bg = Color("#2a1311")
		bd = Color("#7d2a24")
	var s := _sb(bg, bd, 1, 10, 10)
	pc.add_theme_stylebox_override("panel", s)
	pc.custom_minimum_size.y = 124      # fixed: text + a row of buttons, so the board below never jumps
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	var r := _rtl("[center]%s[/center]" % text, 16)
	r.visible = text != ""
	hb.add_child(r)
	if not ME.alive and not G.over:
		var sk := _btn("Skip to end", "default", 13)
		sk.pressed.connect(func():
			ff = true
			_pump())
		hb.add_child(sk)
	# The buttons for what you can do right now sit under the banner, so they never scroll out of view.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(hb)
	col.add_child(_action_bar())
	pc.add_child(col)
	return pc

func _center_band() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var pile := HBoxContainer.new()
	pile.add_theme_constant_override("separation", 12)
	var st := Control.new()
	var bw := mini_w * 1.2
	var bh := bw * 430.0 / 330.0
	st.custom_minimum_size = Vector2(bw + 8, bh + 8)
	for i in range(3):
		var cb := CardBack.new()
		cb.size = Vector2(bw, bh)
		cb.position = Vector2(8 - i * 4, 8 - i * 4)
		st.add_child(cb)
	pile.add_child(st)
	for pair in [["Draw pile", G.deck.size()], ["Set aside", G.out.size()]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(_lbl(pair[0], 12, C_MUT, MONO))
		v.add_child(_lbl(str(pair[1]), 24, C_INK, HEAD))
		pile.add_child(v)
	hb.add_child(pile)
	hb.add_child(_banner())
	return hb

func _war_peek() -> int:
	if G.phase == "war" and not G.war_queue.is_empty():
		return int(G.war_queue[0])
	return -1

func _short_name(p: NPGame.Player) -> String:
	if p.human:
		return p.name.left(7)
	var parts := p.name.split(" ")
	parts.remove_at(0)
	return " ".join(parts).left(7)

## Where everyone sits - solid amber = neighbours (Short range), dashed = across (Long range only).
func _map_panel() -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(C_PANEL2, C_LINE, 1, 10, 8))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pc.add_child(vb)
	vb.add_child(_lbl("THE MAP  -  turns go clockwise", 12, C_MUT, MONO))
	var tm := TableMap.new()
	tm.font = MONO
	tm.custom_minimum_size = Vector2(296, 186)
	var al := G.alive_list()
	for p in G.players:
		tm.seats.append({"name": _short_name(p), "alive": p.alive, "tested": p.tested, "turn": G.turn == p.id and not G.over,
			"you": p == ME, "color": C_GREEN if p == ME else _persona_color(p)})
	var short_pairs := {}
	for p in al:
		for q in G.neighbors_of(p):
			var a := mini(p.id, q.id)
			var b := maxi(p.id, q.id)
			short_pairs["%d-%d" % [a, b]] = true
			if not tm.links.has([a, b, "short"]):
				tm.links.append([a, b, "short"])
	for i in range(al.size()):
		for j in range(i + 1, al.size()):
			var a2: int = al[i].id
			var b2: int = al[j].id
			if not short_pairs.has("%d-%d" % [a2, b2]):
				tm.links.append([a2, b2, "long"])
	vb.add_child(tm)
	return pc

func _me_panel() -> Control:
	var myturn: bool = not G.over and ME.alive and ((G.cur() == ME and G.phase != "war") or _war_peek() == ME.id)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(C_PANEL, C_AMBER if myturn else C_LINE, 2 if myturn else 1, 12, 12))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	var hd := HBoxContainer.new()
	hd.add_theme_constant_override("separation", 8)
	hd.custom_minimum_size.y = 30
	hd.add_child(_lbl(ME.name.to_upper(), 20, C_INK, HEAD))
	if ME.name.strip_edges().to_lower() != "you":      # a custom callsign still gets the "You" tag
		hd.add_child(_lbl("You", 12, C_GREEN, MONO))
	if G.is_superpower(ME):
		hd.add_child(_badge("SUPERPOWER", Color("#ffe08a"), Color("#3a1a0a"), Color("#a5541c")))
	elif ME.tested:
		hd.add_child(_badge("TESTED", Color("#e9c977"), Color("#33290f"), Color("#7a5d18")))
	if not ME.alive:
		hd.add_child(_badge("eliminated", C_MUT, C_PANEL2, C_LINE))
	if ME.alive:
		for d in G.debts:
			if d.to == ME.id:
				hd.add_child(_badge("YOU OWE %s A CARD" % G.players[d.from].name.to_upper(), Color("#ddcc98"), Color("#2a2716"), Color("#6e6743")))
			elif d.from == ME.id:
				hd.add_child(_badge("%s OWES YOU A CARD" % G.players[d.to].name.to_upper(), Color("#ddcc98"), Color("#2a2716"), Color("#6e6743")))
	hd.add_child(_spacer())
	vb.add_child(hd)
	# cards on the left, the trade area beside them (saves vertical space)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	# Your cards on the table: a fixed 4 x 2 grid (4 Technologies + up to 4 Capabilities), empty or not.
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", 3)
	tb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tb.add_child(_lbl("ON THE TABLE", 11, C_MUT, MONO))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var gw := 40.0
	for i in range(8):
		if i < ME.table.size():
			grid.add_child(_tex(ME.table[i].key, gw, not ME.alive))
		else:
			var ph := PanelContainer.new()
			ph.custom_minimum_size = Vector2(gw, gw * 430.0 / 330.0)
			ph.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), Color("#34341f"), 1, 4, 0))
			grid.add_child(ph)
	tb.add_child(grid)
	row.add_child(tb)
	var tz := _trade_zone(ME, mini_w * 1.35)
	tz.custom_minimum_size.x = 250
	tz.size_flags_horizontal = Control.SIZE_SHRINK_END
	tz.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tz)
	vb.add_child(row)
	var hv := HandView.new()
	hv.cw = card_w
	hv.ch = card_w * 430.0 / 330.0
	hv.custom_minimum_size = Vector2(0, hv.ch + 22)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hand: Array = ME.hand.duplicate()
	hand.sort_custom(func(a, b):
		var ia := ORDER.find(a.key)
		var ib := ORDER.find(b.key)
		return ia < ib if ia != ib else a.id < b.id)
	for c in hand:
		var hc := HandCard.new()
		hc.cid = c.id
		hc.fresh = fresh.has(c.id)
		hc.custom_minimum_size = Vector2(hv.cw, hv.ch)
		# the picture lives in `face`, which grows on hover; the card's own (hit) area never changes,
		# so the edges of the neighbouring cards stay hoverable
		var face := Control.new()
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hc.add_child(face)
		hc.face = face
		var t := _tex(c.key, hv.cw, not ME.alive)      # destroyed: your hand lies burnt to a crisp
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.tooltip_text = ""
		face.add_child(t)
		hc.can_drag = _can_offer() or _answering()
		hc.preview = _drag_preview.bind(c.key)
		hc.tex = TEX[c.key]
		hc.picked.connect(_card_menu)
		hv.add_child(hc)
	left.add_child(hv)
	hv.layout.call_deferred()
	fresh.clear()
	return pc

func _action_bar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	if G.over:
		var ob := HFlowContainer.new()
		ob.alignment = FlowContainer.ALIGNMENT_CENTER
		ob.add_theme_constant_override("h_separation", 10)
		var rs := _btn("Show results", "primary")
		rs.pressed.connect(_end_modal)
		ob.add_child(rs)
		var pa := _btn("Play again")
		pa.pressed.connect(func():
			_close_modal(true)
			_start_game())
		ob.add_child(pa)
		wrap.add_child(ob)
		return wrap
	var bar := HFlowContainer.new()
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("h_separation", 10)
	bar.add_theme_constant_override("v_separation", 8)
	wrap.add_child(bar)
	if not ME.alive:
		bar.add_child(_lbl("Spectating.", 13, C_MUT))
		return wrap
	_classic_actions(bar)
	return wrap

func _classic_actions(bar: HFlowContainer) -> void:
	var L := G.legal(ME)
	if str(G.prompt.get("type", "")) == "trade":
		return      # answered in your trade area; the banner says so
	if G.phase == "honour" and G.cur() == ME and not G._debts_of(ME).is_empty():
		var dd: Dictionary = G._debts_of(ME)[0]
		var cr: NPGame.Player = G.players[dd.from]
		var pl = G._trade_card(ME, int(dd.pledge))
		var dv := _big(_btn("Deliver %s" % (NPGame.INFO[pl.key].name if pl != null else "the card"), "primary", 18), 56.0)
		dv.tooltip_text = "Give the pledged card to %s, as promised." % cr.name
		dv.pressed.connect(func():
			G.honour(ME)
			_after_human())
		bar.add_child(dv)
		btn["deliver"] = dv
		var rb := _big(_btn("Break the deal", "danger", 18), 56.0)
		rb.tooltip_text = "Keep the card. %s has already given you theirs - and will remember." % cr.name
		rb.pressed.connect(func():
			G.renege(ME)
			_after_human())
		bar.add_child(rb)
		btn["renege"] = rb
	elif G.phase == "play" and G.cur() == ME:
		var rb2 := _big(_btn("Research", "primary", 30), 76.0)      # your turn's main action fills the box
		rb2.disabled = not L.can_research
		rb2.pressed.connect(_act_research)
		bar.add_child(rb2)
		btn["research"] = rb2
		if not L.can_research:
			bar.add_child(_lbl("The deck is empty - offer a trade, or skip.", 13, C_MUT))
		if not L.can_research:
			var sk := _btn("Skip turn")
			sk.pressed.connect(func():
				G.play_skip(ME)
				_after_human())
			bar.add_child(sk)
			btn["skip"] = sk
	elif G.phase == "war" and _war_peek() == ME.id:
		var sd := _big(_btn("Stand down", "default", 18), 56.0)
		sd.pressed.connect(func():
			G.war_declare(ME, {"kind": "pass"})
			_after_human())
		bar.add_child(sd)
		btn["stand"] = sd
		var tb := _big(_btn("Nuclear Test", "default", 18), 56.0)
		tb.disabled = not L.can_test
		tb.pressed.connect(_act_test)
		bar.add_child(tb)
		btn["test"] = tb
		var ab := _big(_btn("Attack...", "danger", 18), 56.0)
		ab.disabled = L.attacks.is_empty()
		ab.pressed.connect(_attack_modal)
		bar.add_child(ab)
		btn["attack"] = ab
		if L.can_threaten:      # only once you have tested and can reach someone, once a turn
			var thb := _big(_btn("Threaten...", "danger", 18), 56.0)
			thb.tooltip_text = "Your declaration for this window. Refused, you may strike at once."
			thb.pressed.connect(_threaten_modal)
			bar.add_child(thb)
			btn["threaten"] = thb


func _render_side() -> void:
	_clear(map_box)
	map_box.add_child(_map_panel())
	if log_edition != null:
		log_edition.text = "ROUND %d" % G.round_no
	# ink colours for paper: red for attacks and deaths, dark brass for tests, faded for quiet lines
	var tones := {"attack": "#9a2414", "death": "#7a1408", "test": "#6b4c00", "broken": "#9a2414", "reveal": "#5a3d1e", "quiet": "#7d7357", "sys": "#3f4a12"}
	var added := false
	while log_shown < G.log_entries.size():
		var e: Dictionary = G.log_entries[log_shown]
		log_shown += 1
		var txt: String = _you(str(e.text)).replace("[", "(")
		if e.tone in ["attack", "death", "test", "broken"]:
			txt = "[b]%s[/b]" % txt
		logbox.append_text("[color=%s]%s[/color]\n" % [tones.get(e.tone, "#2b241a"), txt])
		added = true
	if added:
		_scroll_log.call_deferred()

## Keep the newest line fully in view (wrapped lines are measured after layout, so do it deferred).
func _scroll_log() -> void:
	if logbox == null:
		return
	for i in range(2):      # wrapped lines are measured over the next frame or two
		await get_tree().process_frame
		if logbox == null:
			return
		logbox.scroll_to_line(maxi(0, logbox.get_line_count() - 1))
		var sb := logbox.get_v_scroll_bar()
		sb.value = sb.max_value

# ====================================================================== actions
func _after_human() -> void:
	_close_popup()
	_pump()

func _act_research() -> void:
	if G.play_research(ME):
		snd("click")
		_after_human()

func _act_test() -> void:
	G.war_declare(ME, {"kind": "test"})
	_after_human()

func _act_launch(type: String, tid: int) -> void:
	_close_modal()
	G.war_declare(ME, {"kind": "attack", "type": type, "target": tid})
	_after_human()

func _act_counter(tid: int) -> void:
	_close_modal(true)
	G.choose_counter(tid)
	_after_human()

func _act_ceasefire() -> void:
	var r := G.propose_ceasefire(ME)
	if r.get("blocked", false):
		_toast("They have just refused. Ask again after a full round - or once something changes.")
		return
	if r.refuses.is_empty():
		_toast("Everyone agrees to stop.")
	else:
		var names: Array = r.refuses.map(func(p): return p.name)
		_toast("%s refuse%s to stand down." % [" & ".join(names), "s" if names.size() == 1 else ""])
	_pump()

func _act_menu() -> void:
	if G == null or G.over:
		_to_menu()
		return
	var vb := _open_modal("Abandon this game?", false, false, true)
	vb.add_child(_lbl("You will return to the menu.", 15, C_MUT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var y := _btn("Abandon", "danger")
	y.pressed.connect(func():
		_close_modal(true)
		_to_menu())
	var n := _btn("Keep playing")
	n.pressed.connect(_close_modal)
	row.add_child(y)
	row.add_child(n)
	vb.add_child(row)

func _to_menu() -> void:
	pump_token += 1
	if debug_panel != null:
		_toggle_debug()
	_ambience(false)
	_music_update.call_deferred()
	_close_modal(true)
	_close_popup()
	G = null
	game_root.visible = false
	menu_root.visible = true

# ---- drag and drop
func _can_offer() -> bool:
	return G != null and not G.over and ME.alive and G.cur() == ME and G.phase == "play" and G.prompt.is_empty() and ME.trade.is_empty()

func _drag_preview(key: String) -> Control:
	var t := _tex(key, 92)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate.a = 0.9
	t.position = Vector2(-46, -60)
	var holder := Control.new()
	holder.add_child(t)
	drag_ghost = holder
	return holder

## Belt and braces: whatever happens to the drag, no picture of the card is left behind.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_zoom_hide()
	elif what == NOTIFICATION_DRAG_END:
		_zoom_hide()
		if drag_ghost != null and is_instance_valid(drag_ghost):
			drag_ghost.queue_free()
		drag_ghost = null
		_reset_hand_hover.call_deferred()

## Put every hand card back to its resting size and place.
func _reset_hand_hover() -> void:
	if board == null:
		return
	for n in board.find_children("*", "", true, false):
		if n is HandCard:
			n._hover(false)

## Letting go of a dragged card on a player's seat offers it to them.
func _drop_offer(p: NPGame.Player, data: Dictionary) -> void:
	if not _can_offer() or p == ME or not p.alive:
		return
	_close_popup()
	var res := G.trade_offer(ME, int(data.cid), p.id)
	if res == "declined":
		_toast("No deal with %s." % p.name)
	_after_human()

## Controls inside a drop target must not swallow the drop: let mouse events pass up to it.
func _pass_through(n: Node) -> void:
	for ch in n.get_children():
		if ch is Control and not (ch is BaseButton) and ch.mouse_filter == Control.MOUSE_FILTER_STOP:
			ch.mouse_filter = Control.MOUSE_FILTER_PASS
		_pass_through(ch)

# ---- card popup
func _card_menu(cid: int, node: Control) -> void:
	_close_popup()
	var c = null
	for x in ME.hand:
		if x.id == cid:
			c = x
	if c == null:
		return
	popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_popup())
	popup.add_child(catcher)
	var pn := PanelContainer.new()
	pn.add_theme_stylebox_override("panel", _sb(Color("#17180e"), C_AMBER, 1, 10, 10))
	pn.custom_minimum_size.x = 250
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	pn.add_child(vb)
	vb.add_child(_lbl(NPGame.INFO[c.key].name.to_upper(), 18, C_AMBER, HEAD))
	# wrapped text gets a fixed width up front, so the box is measured right first time
	# (a wrapping label with no width yet measures as one tall column and stretches the box)
	for txt in [CARD_DESC[c.key], "Drag this card onto a player's trade area to offer it in a trade." if _can_offer() else "Nothing to do with this card right now."]:
		var l := _lbl(txt, 12, C_MUT, null, true)
		l.custom_minimum_size.x = 230
		vb.add_child(l)
	pn.modulate.a = 0.0      # hidden until it has its final size and place
	popup.add_child(pn)
	popup_root.add_child(popup)
	for i in range(2):
		await get_tree().process_frame
		if popup == null or not is_instance_valid(pn):
			return
		pn.reset_size()
	var r := node.get_global_rect()
	var vp := get_viewport_rect().size
	pn.position = Vector2(clampf(r.get_center().x - pn.size.x / 2.0, 8.0, vp.x - pn.size.x - 8.0), maxf(8.0, r.position.y - pn.size.y - 10.0))
	pn.modulate.a = 1.0

func _close_popup() -> void:
	if popup != null:
		popup.queue_free()
		popup = null

# ====================================================================== modals
func _open_modal(title: String, red := false, sticky := false, pause := false) -> VBoxContainer:
	_close_modal(true)
	modal_btns.clear()
	modal_sticky = sticky
	modal_pause = pause
	if pause:
		paused += 1
	var vp := get_viewport_rect().size
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = Color(0.012, 0.02, 0.03, 0.74)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not modal_sticky:
			_close_modal())
	modal.add_child(scrim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(cc)
	var pn := PanelContainer.new()
	pn.add_theme_stylebox_override("panel", _sb(C_PANEL, C_LINE, 1, 14, 20))
	pn.custom_minimum_size.x = clampf(vp.x - 40.0, 300.0, 760.0)
	cc.add_child(pn)
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pn.add_child(modal_scroll)
	modal_vbox = VBoxContainer.new()
	modal_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_vbox.add_theme_constant_override("separation", 10)
	modal_scroll.add_child(modal_vbox)
	var hd := HBoxContainer.new()
	var tl := _lbl(title.to_upper(), 28, C_RED if red else C_INK, HEAD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hd.add_child(tl)
	modal_vbox.add_child(hd)
	modal_root.add_child(modal)
	_fit_modal.call_deferred()
	return modal_vbox

func _fit_modal() -> void:
	for i in range(3):
		await get_tree().process_frame
		if modal_scroll == null or not is_instance_valid(modal_scroll):
			return
		var h := modal_vbox.get_combined_minimum_size().y
		modal_scroll.custom_minimum_size.y = minf(h, get_viewport_rect().size.y * 0.84 - 40.0)

func _close_modal(silent := false) -> void:
	if modal != null:
		modal.queue_free()
		modal = null
		modal_scroll = null
		modal_vbox = null
		if modal_pause:
			paused = maxi(0, paused - 1)
		modal_pause = false
	modal_btns.clear()

func _close_btn(vb: VBoxContainer, text := "Close") -> void:
	var hd: HBoxContainer = vb.get_child(0)
	var b := _btn(text, "default", 13)
	b.pressed.connect(_close_modal)
	hd.add_child(b)

func _atk_panel(vb: VBoxContainer, title: String, desc: String) -> HFlowContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(C_PANEL2, C_LINE, 1, 10, 12))
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	pc.add_child(iv)
	iv.add_child(_lbl(title.to_upper(), 17, C_INK, HEAD))
	iv.add_child(_lbl(desc, 13, C_MUT, null, true))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 8)
	fl.add_theme_constant_override("v_separation", 8)
	iv.add_child(fl)
	vb.add_child(pc)
	return fl

func _attack_list(vb: VBoxContainer, L: Dictionary) -> void:
	var info := {
		"short": ["Short-range strike", "Eliminates a player sitting immediately to your left or right. Your Short-range card is destroyed."],
		"long": ["Long-range strike", "Eliminates any one player. Your Long-range card is destroyed (Short-range stays)."],
		"super": ["Superpower strike", "Eliminates any one player. Costs nothing - a Superpower can strike again and again."]}
	for a in L.attacks:
		var fl := _atk_panel(vb, info[a.type][0], info[a.type][1])
		for tid in a.targets:
			var rel := ""
			if a.type == "long" or a.type == "super":
				rel = " (next to you)" if G.neighbors_of(ME).has(G.players[tid]) else " (across the table)"
			var tb := _btn("Target: " + G.players[tid].name + rel, "danger")
			tb.pressed.connect(_act_launch.bind(a.type, tid))
			fl.add_child(tb)
			modal_btns.append({"kind": "launch", "type": a.type, "button": tb})

func _attack_modal() -> void:
	var L := G.legal(ME)
	if L.attacks.is_empty():
		_toast("No attacks available.")
		return
	var vb := _open_modal("Choose your attack", true, false, true)
	_close_btn(vb, "Cancel")
	vb.add_child(_lbl("This cannot be undone.", 15, C_MUT))
	_attack_list(vb, L)

## You are being threatened: give up every Capability card, or refuse.
func _threat_modal() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human or modal != null:
		return
	var held := G.caps_held(ME)
	var vb := _open_modal("You are threatened", true, true, false)
	var txt := "[b]%s[/b] threatens you: return [b]all your Capability cards[/b] to the deck, or else." % pr.from.name
	var reach := []
	for av in G.attack_types(pr.from):
		if av.targets.has(ME.id):
			reach.append(av.type)
	if not reach.is_empty():
		txt += "\n\nThey [b]can[/b] strike you (%s)." % ", ".join(reach.map(func(r): return {"short": "Short range", "long": "Long range", "super": "Superpower"}[r]))
	if held.is_empty():
		txt += "\n\nYou hold no Capability cards, so you have nothing to give up."
	else:
		txt += "\n\nYou hold: %s. If you refuse, nothing happens automatically - but they may attack." % ", ".join(held.map(func(c): return NPGame.INFO[c.key].name))
	vb.add_child(_rtl(txt, 15, Color("#ddd3b4")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var y := _btn("Give in - disarm", "danger")
	y.disabled = held.is_empty()
	y.pressed.connect(func():
		_close_modal(true)
		G.answer_threat(true)
		_after_human())
	var n := _btn("Refuse", "primary")
	n.pressed.connect(func():
		_close_modal(true)
		G.answer_threat(false)
		_after_human())
	row.add_child(y)
	row.add_child(n)
	vb.add_child(row)
	modal_btns.append({"kind": "threat_yes", "button": y})
	modal_btns.append({"kind": "threat_no", "button": n})

## Pick whom to threaten (only players you could actually attack).
func _threaten_modal() -> void:
	var ids := G.threat_targets(ME)
	if ids.is_empty():
		_toast("You cannot reach anyone - a threat needs a credible attack.")
		return
	var vb := _open_modal("Threaten", true, false, true)
	_close_btn(vb, "Cancel")
	vb.add_child(_rtl("Only players you could attack can be threatened, once a turn. They may give in or refuse - if they refuse, you declare again at once: strike, or stand down.", 15, Color("#ddd3b4")))
	var kinds := [
		["demand", "Force a trade", "You put up a card of yours; they must give you one of theirs in return - a frightened power may give you the one it thinks you need most."],
		["threat", "Disarm", "They return ALL their Capability cards to the deck."],
	]
	for k in kinds:
		if k[0] == "demand" and ME.hand.is_empty():
			continue
		var fl := _atk_panel(vb, k[1], k[2])
		for tid in ids:
			var who: NPGame.Player = G.players[tid]
			if k[0] == "demand" and who.hand.is_empty():
				continue
			var rel := " (next to you)" if G.neighbors_of(ME).has(who) else " (across the table)"
			var b := _btn("Threaten " + who.name + rel, "danger")
			var kind: String = k[0]
			b.pressed.connect(func():
				if kind == "demand":
					_force_trade_modal(tid)
					return
				_close_modal()
				G.war_declare(ME, {"kind": kind, "target": tid})
				_after_human())
			fl.add_child(b)
			modal_btns.append({"kind": "threaten", "button": b})

## A row of the cards in your hand, each with a button that passes its id to `chosen`.
func _hand_picker(vb: VBoxContainer, label: String, kind: String, chosen: Callable) -> void:
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 10)
	fl.add_theme_constant_override("v_separation", 10)
	var hand: Array = ME.hand.duplicate()
	hand.sort_custom(func(a, b): return ORDER.find(a.key) < ORDER.find(b.key))
	for c in hand:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.add_child(_tex(c.key, 76))
		var g := _btn(label, "default", 13)
		var cid: int = c.id
		g.pressed.connect(func(): chosen.call(cid))
		cell.add_child(g)
		fl.add_child(cell)
		modal_btns.append({"kind": kind, "button": g})
	vb.add_child(fl)

## You force a trade on a player: choose the card you put up.
func _force_trade_modal(tid: int) -> void:
	var vb := _open_modal("Force a trade", true, false, true)
	_close_btn(vb, "Cancel")
	vb.add_child(_rtl("Which card do you put up? [b]%s[/b] sees it, then gives you a card of their choice in return - or refuses, and you keep it." % G.players[tid].name, 15, Color("#ddd3b4")))
	_hand_picker(vb, "Offer", "threaten", func(cid):
		_close_modal()
		G.war_declare(ME, {"kind": "demand", "target": tid, "offer": cid})
		_after_human())

## You are threatened with a forced trade: choose the card you give back - or refuse.
func _demand_modal() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human or modal != null:
		return
	var vb := _open_modal("You are threatened", true, true, false)
	var offered: Dictionary = {}
	for c in pr.from.hand:
		if c.id == int(pr.offer):
			offered = c
	var txt := "[b]%s[/b] threatens you: [b]trade[/b] - take their [b]%s[/b] and give them a card of your choice, or else." % [pr.from.name, NPGame.INFO[offered.key].name]
	var reach := []
	for av in G.attack_types(pr.from):
		if av.targets.has(ME.id):
			reach.append(av.type)
	if not reach.is_empty():
		txt += "\n\nThey [b]can[/b] strike you (%s)." % ", ".join(reach.map(func(r): return {"short": "Short range", "long": "Long range", "super": "Superpower"}[r]))
	txt += "\n\nPick the card to give them (only the two of you will know what changed hands), or refuse and you both keep your cards. If you refuse, nothing happens automatically - but they may attack."
	vb.add_child(_rtl(txt, 15, Color("#ddd3b4")))
	vb.add_child(_tex(offered.key, 96))
	_hand_picker(vb, "Give", "demand_give", func(cid):
		_close_modal(true)
		G.answer_demand(cid)
		_after_human())
	var n := _btn("Refuse", "primary")
	n.pressed.connect(func():
		_close_modal(true)
		G.answer_demand(-1)
		_after_human())
	vb.add_child(n)
	modal_btns.append({"kind": "demand_no", "button": n})

## Voluntary disarmament, available at any time once you have tested.
func _disarm_modal() -> void:
	var held := G.caps_held(ME)
	if not G.can_disarm(ME):
		return
	var vb := _open_modal("Disarm?", true, false, true)
	vb.add_child(_rtl("Return [b]all your Capability cards[/b] (%s) to the deck. Your Technologies stay on the table. You will be unable to attack or retaliate until you collect Capabilities again." % ", ".join(held.map(func(c): return NPGame.INFO[c.key].name)), 15, Color("#ddd3b4")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var y := _btn("Disarm", "danger")
	y.pressed.connect(func():
		_close_modal()
		if not G.disarm_caps(ME):
			_toast("Answer the decision in front of you first, then you can disarm.")
		_after_human())
	var n := _btn("Keep my weapons")
	n.pressed.connect(_close_modal)
	row.add_child(y)
	row.add_child(n)
	vb.add_child(row)
	modal_btns.append({"kind": "disarm_yes", "button": y})

## An AI power proposes a stand-down and the others agree: the last word is yours.
func _ceasefire_modal() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human or modal != null:
		return
	var vb := _open_modal("Stand-down proposed", false, true, false)
	var names: Array = G.others(ME).filter(func(x): return x != pr.from).map(func(x): return x.name)
	var txt := "[b]%s[/b] proposes that everyone stops here." % pr.from.name
	if not names.is_empty():
		txt += " %s agree%s." % [" and ".join(names), "s" if names.size() == 1 else ""]
	txt += "\n\nAgree, and the game ends with everyone still at the table alive. Refuse, and it goes on - they can ask again after a full round, or once something changes."
	vb.add_child(_rtl(txt, 15, Color("#ddd3b4")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var y := _btn("Agree - stand down", "primary")
	y.pressed.connect(func():
		_close_modal(true)
		G.answer_ceasefire(true)
		_after_human())
	var n := _btn("Refuse", "danger")
	n.pressed.connect(func():
		_close_modal(true)
		G.answer_ceasefire(false)
		_after_human())
	row.add_child(y)
	row.add_child(n)
	vb.add_child(row)
	modal_btns.append({"kind": "cease_yes", "button": y})
	modal_btns.append({"kind": "cease_no", "button": n})

func _counter_modal() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human or modal != null:
		return
	var vb := _open_modal("Counter-strike!", true, true, false)
	var by_txt := (" by [b]%s[/b]" % pr.by.name) if pr.by != null else ""
	vb.add_child(_rtl("You have been eliminated%s - but your Counter-strike fires. Choose who goes down with you." % by_txt, 15, Color("#ddd3b4")))
	var fl := _atk_panel(vb, "Choose a target", "")
	for id in pr.options:
		var b := _btn("Target: " + G.players[id].name, "danger")
		b.pressed.connect(_act_counter.bind(id))
		fl.add_child(b)
		modal_btns.append({"kind": "counter", "button": b})

func _rules_modal() -> void:
	var vb := _open_modal("How to play", false, false, G != null)
	_close_btn(vb, "Close")
	_rules_classic(vb)

func _rules_h(vb: VBoxContainer, text: String) -> void:
	vb.add_child(_lbl(text.to_upper(), 18, C_AMBER, HEAD))

func _rules_p(vb: VBoxContainer, bb: String) -> void:
	vb.add_child(_rtl(bb, 15, Color("#ddd3b4")))

## A row of card pictures with an optional one-line caption under each.
func _card_row(vb: VBoxContainer, keys: Array, notes: Array) -> void:
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 12)
	fl.add_theme_constant_override("v_separation", 10)
	for i in range(keys.size()):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		col.add_child(_tex(keys[i], 104))
		if str(notes[i]) != "":
			var l := _lbl(str(notes[i]), 12, C_MUT, null, true)
			l.custom_minimum_size.x = 104
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(l)
		fl.add_child(col)
	vb.add_child(fl)

func _rules_classic(vb: VBoxContainer) -> void:
	_rules_p(vb, "Nuclear Poker teaches the logic of nuclear deterrence. There is [b]no victory rule[/b]: the game ends when one power is left standing, when nobody is left, when everyone agrees to stand down, when every power left is a Superpower - [b]Mutually Assured Destruction[/b], and all win - when one Superpower faces powers that hold no Capability at all - [b]hegemony[/b], and it wins - or in a [b]stalemate[/b], when the draw pile is empty and three full rounds pass without anyone testing, striking, trading or disarming. If you are eliminated, the other powers play on without you until the game ends.")
	_rules_h(vb, "Goal")
	_rules_p(vb, "You are a country trying to become a [b]Nuclear Superpower[/b]. First [b]test a nuclear weapon[/b] with the four Technology cards, then collect the four Capability cards.")
	_rules_h(vb, "Technology cards - the Nuclear Test")
	_rules_p(vb, "Collect all four different Technologies, then put them on the table in the exchange window to show you have tested a warhead. You only need to do this once. You cannot attack before you have tested.")
	_card_row(vb, ["uranium", "refinement", "warhead", "testing"], ["", "", "", ""])
	_rules_h(vb, "Capability cards - your weapons")
	_card_row(vb, ["short", "long", "counter", "super"], [
		"Short range: hit a player on your left or right. Destroyed when fired",
		"Long range: hit anyone (needs Short range). Destroyed when fired",
		"Counter-strike: when you are eliminated, take one player with you (needs Short + Long)",
		"Superpower: hold all four Capabilities + a test, and strike again and again"])
	_rules_h(vb, "Set up")
	_rules_p(vb, "One set of these 8 cards per player, plus one extra set: [b]3 players = 32 cards, 4 players = 40, 5 players = 48[/b]. Everyone is dealt 3 cards and the rest is the draw pile.")
	_rules_h(vb, "Your turn: one move - draw or trade")
	_rules_p(vb, "- [b]Research[/b]: draw a card from the draw pile.\n- [b]Trade[/b]: drag a card from your hand onto another player's [b]trade area[/b] to offer it.\n- If the draw pile is empty you can only trade, or skip your turn.")
	_rules_h(vb, "Trading - and you can be cheated")
	_rules_p(vb, "- The player you offer a card to [b]sees it[/b] before deciding; nobody else does. The card they answer with stays [b]face down[/b] until it arrives in your hand - and the rest of the table never sees what changed hands.\n- The player you offer to either [b]declines[/b] or [b]answers[/b] with a face-down card of their own. Your offer was your acceptance: if they answer, the deal is done.\n- Your card goes to them [b]at once[/b]. Theirs is only a [b]pledge[/b]: it reaches you on [i]their[/i] next turn, when they choose to [b]deliver[/b] it - or [b]break the deal[/b] and keep it.\n- When someone offers you a trade, drag one of your cards into [i]your own[/i] trade area to answer, or press Decline.\n- An offer is your move for the turn, whether it is answered or declined.\n- The other powers [b]remember[/b]. Break deals and they trust you less, trade with you less, refuse your stand-downs and are quicker to threaten or attack you. Deal honestly, again and again - and above all give partners cards they actually need - and they come to see you as an [b]ally[/b].")
	_rules_h(vb, "Nuclear exchanges")
	_rules_p(vb, "Anyone can test or attack [b]out of turn[/b], declared in [b]order of play[/b]. After every turn, starting with the player who just moved and going clockwise, each player may make a Nuclear Test, attack, threaten - or stand down. After a test or an elimination the round of declarations starts again. You are only asked when you have something to declare.")
	_rules_h(vb, "Attacking")
	_rules_p(vb, "- [b]Short range[/b]: eliminate a player sitting immediately to your left or right.\n- [b]Long range[/b]: eliminate anyone at the table.\n- [b]Counter-strike[/b]: when you are eliminated you immediately eliminate one player of your choice.\n- [b]One weapon per turn[/b]: unless you are a Superpower, you can fire only one attack card in each turn's exchange window.\n- [b]Firing a weapon destroys it[/b]: a Short-range attack uses up your Short-range card, a Long-range attack your Long-range card (Short range stays). Spent weapons go to the set-aside pile. A [b]Superpower[/b] strikes for free, as often as it likes - its Superpower strike reaches anyone, so it is the only weapon it is offered.\n- An attack puts the Capability cards it needs on the table for all to see.\n- The moment a power becomes a [b]Superpower[/b] - tested, with all four Capabilities - its Capabilities go on the table beside its Technologies, for all to see.\n- An eliminated player's hand is turned face up and stays on show in their seat.")
	_rules_h(vb, "Threats and disarming")
	_rules_p(vb, "- [b]Threaten...[/b] (in the exchange window, as your declaration; once a turn): name a player you could attack and make one of two demands. [b]Force a trade[/b]: you put up a card of yours; they see it and give you a card of their choice in return, and the two swap at once, face down. [b]Disarm[/b]: they return [b]all their Capability cards[/b] to the deck. Either way they may refuse, and nothing changes hands. If they refuse, you declare again at once: strike, or stand down. If they give in, the round of declarations starts again.\n- [b]Disarm[/b] (top bar): once you have made your [b]Nuclear Test[/b], at [b]any time[/b], on or off your turn, return all your Capability cards to the deck. The other powers may disarm too once they have tested.")
	_rules_h(vb, "Standing down")
	_rules_p(vb, "[b]Propose stand-down[/b] (top bar) ends the game peacefully - but only if every other power agrees. Each weighs its position: can it strike, is it under threat, are you armed, how close is it to a full arsenal, does it trust you. Once refused, you can ask again after a full round, or as soon as something changes on the table.")
	_rules_h(vb, "Mutually Assured Destruction")
	_rules_p(vb, "The moment [b]every power still in the game is a Superpower[/b] - holding [b]all eight cards[/b]: the four Technologies tested on the table and all four Capabilities - the game ends in Mutually Assured Destruction: each can destroy all the others, so none will - and [b]all survivors win[/b].")
	_rules_h(vb, "The table map")
	_rules_p(vb, "The map in the side panel shows one country per player, in turn order clockwise round the unclaimed highlands at the heart of the continent. Countries that share a border are neighbours - a [b]solid amber[/b] line joins them and Short range reaches them. A [b]dashed[/b] line crosses the highlands to the countries further away - only Long range reaches them. A small mushroom cloud marks a country that has tested. With 3 players everyone is a neighbour. When someone is eliminated the gap closes, and the players either side of them become neighbours.")
	_rules_h(vb, "The powers")
	_rules_p(vb, "Each AI power has a character of its own - hawks, deterrers, opportunists, pacifists, peacemakers, schemers - and plays to it: how readily it trades, keeps its word, threatens, strikes or stands down. Which is which, you find out at the table. Some think three levels deep: what they believe, what they think the others think of them, and how each move will be read before they make it. Press [b]F9[/b] to watch them think - but that is cheating.")

# ====================================================================== end
func _finish() -> void:
	if end_shown:
		return
	end_shown = true
	await get_tree().create_timer(1.1 / speed).timeout
	if G != null and G.over:
		_end_modal()

func _end_modal() -> void:
	var r := G.result
	if r.kind == "mad":
		_mad_modal()
		return
	var alive: Array = r.survivors.map(func(i): return G.players[i])
	var title := ""
	var sub := ""
	var good := false
	if r.kind == "annihilation":
		title = "Mutual annihilation"
		sub = "Nobody is left. Nobody wins."
	elif r.kind == "last":
		var w: NPGame.Player = alive[0]
		good = w == ME
		title = "You are the last one standing" if good else "%s is the last power standing" % w.name
		sub = "You survived. Look at what it cost." if good else "The rest of the table is gone."
	elif r.kind == "stalemate":
		title = "Stalemate"
		sub = "The draw pile ran dry and nobody could - or would - move again. %d of %d powers survive." % [alive.size(), G.players.size()]
		good = ME.alive
	elif r.kind == "hegemony":
		var w: NPGame.Player = G.players[int(r.winner)]
		good = w == ME
		title = "You rule the world" if good else "%s rules the world" % w.name
		sub = "The only Superpower at a table where no one else holds a Capability. Nobody can stand against %s - and nobody had to die." % ("you" if good else w.name)
	elif alive.size() == G.players.size():
		title = "Deterrence held"
		sub = "Nobody died. That is the only winning move."
		good = true
	else:
		title = "Stand-down"
		sub = "%d of %d powers survive." % [alive.size(), G.players.size()]
	var vb := _open_modal(title, not good, false, false)
	_close_btn(vb, "X")      # close to look at the final board; "Show results" brings this back
	vb.add_child(_lbl("%s  (%d round%s)" % [sub, G.round_no, "" if G.round_no == 1 else "s"], 15, C_MUT, null, true))
	for p in G.players:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _sb(C_PANEL2, Color("#5d6d36") if p.alive else Color("#6a2a25"), 1, 8, 10))
		var hb := HBoxContainer.new()
		var who := "%s%s - %s" % [p.name, " (you)" if p == ME else "", "survived" if p.alive else ("eliminated" + ((" by " + G.players[p.eliminated_by].name) if p.eliminated_by >= 0 else ""))]
		hb.add_child(_lbl(who, 15, C_INK if p.alive else Color("#e7b0aa"), null, true))
		hb.add_child(_lbl("%s%d kill%s" % ["tested · " if p.tested else "", p.kills, "" if p.kills == 1 else "s"], 12, C_MUT, MONO))
		pc.add_child(hb)
		vb.add_child(pc)
	vb.add_child(_lbl("\"The only winning move is not to play.\"", 14, C_AMBER, MONO))
	_end_buttons(vb)

func _end_buttons(vb: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var again := _btn("Play again", "primary")
	again.pressed.connect(func():
		_close_modal(true)
		_start_game())
	var chg := _btn("Change settings")
	chg.pressed.connect(func():
		_close_modal(true)
		_to_menu())
	row.add_child(again)
	row.add_child(chg)
	vb.add_child(row)
	modal_btns.append({"kind": "again", "button": again})

## Mutually Assured Destruction: a special edition of The Atomic Herald. The photograph
## (assets/ui/mad/<pic>.jpg, from tools/meshy_mad.py) is picked at random, once per game.
const MAD_PICS := [
	{"pic": "warroom", "sub": "Every power can destroy all the others - so none will. All win.", "cap": "Each with a hand on the button. Nobody presses."},
	{"pic": "standoff", "sub": "Everyone aims. Nobody fires. All win.", "cap": "Each man covers another. Nobody dares to fire first."},
	{"pic": "silos", "sub": "Armed to the teeth, and perfectly still. All win.", "cap": "Ready to fly at a moment's notice. The moment never comes."},
	{"pic": "clock", "sub": "One minute to midnight - and the hands have stopped. All win.", "cap": "The city sleeps beneath the searchlights."},
	{"pic": "hands", "sub": "Nobody blinks. All win.", "cap": "Four hands, four buttons. Not one of them moves."},
	{"pic": "scales", "sub": "The scales are level. All win - as long as nobody breathes.", "cap": "Held in perfect balance: enough to end the world, many times over."},
	{"pic": "banquet", "sub": "The powers toast a peace that rests on the end of the world. All win.", "cap": "A toast to the balance of terror."},
]

func _mad_modal() -> void:
	if mad_pic < 0:
		mad_pic = randi() % MAD_PICS.size()
	var m: Dictionary = MAD_PICS[mad_pic]
	var ink := Color("#1f1b14")
	var paper_font: Font = load("res://fonts/OldStandard-Regular.woff2")
	var bold_font: Font = load("res://fonts/OldStandard-Bold.woff2")
	var ital_font: Font = load("res://fonts/OldStandard-Italic.woff2")
	var vb := _open_modal("", false, false, false)
	_close_btn(vb, "X")      # close to look at the final board; "Show results" brings this back
	var pn: PanelContainer = modal_scroll.get_parent()
	var tx := StyleBoxTexture.new()
	tx.texture = load("res://assets/ui/newsprint.png")
	tx.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	tx.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	tx.set_content_margin_all(22)
	pn.add_theme_stylebox_override("panel", tx)
	vb.add_theme_constant_override("separation", 6)
	var centred := func(text: String, size: int, font: Font, wrap := false) -> Label:
		var l := _lbl(text, size, ink, font, wrap)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		return l
	centred.call("The Atomic Herald", 44, load("res://fonts/UnifrakturCook-Bold.woff2"))
	vb.add_child(_rule(ink, 3.0))
	var dl := HBoxContainer.new()
	dl.add_child(_lbl("SPECIAL EDITION", 12, ink, paper_font))
	dl.add_child(_spacer())
	dl.add_child(_lbl("ROUND %d" % G.round_no, 12, ink, paper_font))
	dl.add_child(_spacer())
	dl.add_child(_lbl("ONE CENT", 12, ink, paper_font))
	vb.add_child(dl)
	vb.add_child(_rule(ink, 1.0))
	vb.add_child(_rule(ink, 1.0, 2))
	centred.call("BALANCE OF TERROR", 54 if pn.custom_minimum_size.x > 600.0 else 34, HEAD)
	centred.call(str(m.sub), 18, ital_font, true)
	var pic := TextureRect.new()
	pic.texture = load("res://assets/ui/mad/%s.jpg" % m.pic)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tsz: Vector2 = pic.texture.get_size()
	pic.custom_minimum_size.y = minf((pn.custom_minimum_size.x - 44.0) * tsz.y / tsz.x, get_viewport_rect().size.y * 0.34)
	vb.add_child(pic)
	centred.call(str(m.cap), 13, ital_font, true)
	vb.add_child(_rule(ink, 2.0))
	# the victors: every power still at the table
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	for p in G.players:
		if not p.alive:
			continue
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var ph := _portrait(p, 84)
		ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(ph)
		for t in [[p.name + (" (you)" if p == ME and p.name != "You" else ""), 15, bold_font], ["SUPERPOWER", 11, paper_font]]:
			var l := _lbl(t[0], t[1], ink, t[2])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(l)
		row.add_child(cell)
	vb.add_child(row)
	var fallen: Array = []
	for p in G.players:
		if not p.alive:
			fallen.append(p.name + ((", eliminated by " + G.players[p.eliminated_by].name) if p.eliminated_by >= 0 else ""))
	if not fallen.is_empty():
		centred.call("Not at the table: %s." % "; ".join(fallen), 13, paper_font, true)
	centred.call("\"The only winning move is not to play.\"", 15, MONO)
	_end_buttons(vb)

# ====================================================================== effects
func _fx(text: String, kind: String) -> void:
	var col: Color = {"test": Color("#ffe08a"), "attack": Color("#ff7a70"), "death": Color("#ff4a40")}[kind]
	# Two headlines in the same instant (a Nuclear Test that makes a Superpower): the later one replaces
	# the earlier, instead of the two printing over each other.
	if is_instance_valid(last_fx) and Time.get_ticks_msec() - last_fx_ms < 400:
		last_fx.queue_free()
	var root := Control.new()
	last_fx = root
	last_fx_ms = Time.get_ticks_msec()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flash := ColorRect.new()
	flash.color = Color(col, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _lbl(text.to_upper(), 72, col, HEAD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0
	cc.add_child(l)
	root.add_child(cc)
	fx_root.add_child(root)
	l.pivot_offset = l.get_minimum_size() / 2.0
	l.scale = Vector2(0.6, 0.6)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(flash, "color:a", 0.32, 0.18)
	tw.tween_property(flash, "color:a", 0.0, 1.2).set_delay(0.18)
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_property(l, "scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(1.0)
	tw.chain().tween_callback(root.queue_free)

func _shake() -> void:
	if game_root == null or not game_root.visible:
		return
	var tw := create_tween()
	for i in range(6):
		tw.tween_property(game_root, "position:x", (8.0 if i % 2 == 0 else -8.0) * (1.0 - i / 6.0), 0.05)
	tw.tween_property(game_root, "position:x", 0.0, 0.05)

func _toast(msg: String) -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(C_BG2, C_AMBER, 1, 99, 10))
	pc.add_child(_lbl(msg, 14))
	fx_root.add_child(pc)
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	pc.position = Vector2((vp.x - pc.size.x) / 2.0, vp.y - 70.0)
	var tw := pc.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(pc, "modulate:a", 0.0, 0.4)
	tw.tween_callback(pc.queue_free)

func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var enter: bool = e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER
		if e.keycode == KEY_F11 or (enter and e.alt_pressed) or (e.keycode == KEY_F and (e.meta_pressed or e.ctrl_pressed)):
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F9:
		_toggle_debug()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and debug_panel != null:
		_toggle_debug()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if popup != null:
			_close_popup()
		elif modal != null and not modal_sticky:
			_close_modal()

# ====================================================================== debug view (F9)
func _toggle_debug() -> void:
	if debug_panel != null:
		debug_panel.queue_free()
		debug_panel = null
		return
	if G == null or not game_root.visible:
		return
	debug_panel = PanelContainer.new()
	debug_panel.add_theme_stylebox_override("panel", _sb(Color("#0d0e08f2"), C_AMBER, 2, 10, 12))
	debug_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	debug_panel.offset_left = 16
	debug_panel.offset_top = 52
	debug_panel.offset_right = -16
	debug_panel.offset_bottom = -16
	debug_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_root.add_child(debug_panel)
	_build_debug()

func _pct(v: float) -> String:
	return "%d%%" % int(round(clampf(v, 0.0, 1.0) * 100.0))

func _build_debug() -> void:
	if debug_panel == null or G == null:
		return
	for c in debug_panel.get_children():
		c.queue_free()
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	debug_panel.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	sc.add_child(vb)
	var hd := HBoxContainer.new()
	hd.add_child(_lbl("DEBUG - THE OTHER PLAYERS' VIEW", 20, C_AMBER, HEAD))
	hd.add_child(_spacer())
	hd.add_child(_lbl("F9 or Esc to close  ·  updates live  ·  hidden information!", 12, C_MUT, MONO))
	vb.add_child(hd)
	vb.add_child(_lbl("Threat = how likely the AI thinks that player can eliminate it soon (from what it has seen). Trust starts at 60%: above it is goodwill (ally), below it a grudge. Stand-down = its current leaning if that player proposed (yes above 0.50). Trade = rough willingness to answer that player's offer. Thinking characters also show: Sees me = how far it reckons that player trusts it (from the public record); Intent = how inclined it foresees that player is to strike it (fires above 0.35); Agrees = whether it expects that player to accept its stand-down.", 12, C_MUT, null, true))
	for p in G.players:
		if p.human:
			continue
		var dv: Dictionary = G.debug_view(p)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _sb(C_PANEL2, C_LINE, 1, 8, 10))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		pc.add_child(col)
		var pe: Dictionary = dv.persona
		var top := HFlowContainer.new()
		top.add_theme_constant_override("h_separation", 12)
		top.add_child(_lbl(str(dv.name).to_upper() + ("" if p.alive else "  (eliminated)"), 18, C_INK, HEAD))
		top.add_child(_lbl("%s · aggression %s · fear %s · caution %s · trading %s · honesty %s" % [pe.title, _pct(pe.aggr), _pct(pe.fear), _pct(pe.caution), _pct(pe.trade), _pct(pe.honest)], 12, _persona_color(p), MONO))
		var state := "can TEST now" if dv.can_test else ("armed: " + ", ".join(dv.attacks) if not dv.attacks.is_empty() else "cannot strike")
		top.add_child(_lbl(state, 12, C_AMBER if (dv.can_test or not dv.attacks.is_empty()) else C_MUT, MONO))
		col.add_child(top)
		if G.deep(p):
			var mind := "thinks: peril to me %s · a test now would provoke %s · wants a stand-down %s · chief rival %s · alliance %s · peace %s" % [
				_pct(dv.peril), ("+" + _pct(dv.provocation)) if dv.can_test else "-", _pct(dv.wants_peace), dv.rival, _pct(G.pv(p, "ally")), _pct(G.pv(p, "peace"))]
			col.add_child(_lbl(mind, 12, C_AMBER, MONO, true))
		var hand := HBoxContainer.new()
		hand.add_theme_constant_override("separation", 4)
		hand.add_child(_lbl("HAND ", 11, C_MUT, MONO))
		for k in dv.hand:
			hand.add_child(_tex(k, 34))
		if dv.hand.is_empty():
			hand.add_child(_lbl("(empty)", 12, C_MUT, MONO))
		col.add_child(hand)
		var grid := GridContainer.new()
		var deep := G.deep(p)
		grid.columns = 11 if deep else 8
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 2)
		for h in ["LOOKING AT", "THREAT", "TESTED?", "CAPS (est)", "TRUST", "", "STAND-DOWN", "TRADE"] + (["SEES ME", "INTENT", "AGREES"] if deep else []):
			grid.add_child(_lbl(h, 11, C_MUT, MONO))
		for r in dv.rows:
			var nm: String = ("YOU" if r.human else r.name) + ("" if r.alive else " (dead)")
			grid.add_child(_lbl(nm, 13, C_INK if r.alive else C_MUT, MONO))
			grid.add_child(_lbl(_pct(r.threat), 13, Color("#e0644e") if r.threat > 0.5 else C_INK, MONO))
			grid.add_child(_lbl(_pct(r.ready), 13, C_INK, MONO))
			grid.add_child(_lbl("%.1f / 4" % r.caps, 13, C_INK, MONO))
			grid.add_child(_lbl(_pct(r.trust), 13, C_INK, MONO))
			var rel := "ally" if r.warmth > 0.15 else ("grudge" if r.grudge > 0.15 else "")
			grid.add_child(_lbl(rel, 13, C_GREEN if rel == "ally" else Color("#e0644e"), MONO))
			grid.add_child(_lbl(("%.2f %s" % [r.standdown, "yes" if r.standdown > 0.5 else "no"]) if r.alive else "-", 13, C_INK, MONO))
			grid.add_child(_lbl(_pct(r.trade) if r.alive else "-", 13, C_INK, MONO))
			if deep:
				grid.add_child(_lbl(_pct(r.sees_me), 13, C_INK, MONO))
				grid.add_child(_lbl(("%.2f" % r.intent) if r.intent > -5.0 else "-", 13, Color("#e0644e") if r.intent > 0.35 else C_INK, MONO))
				grid.add_child(_lbl(("yes" if r.agrees > 0.5 else "no") if (r.alive and not r.human) else "-", 13, C_INK, MONO))
		col.add_child(grid)
		vb.add_child(pc)
	var dk := HFlowContainer.new()
	dk.add_theme_constant_override("h_separation", 4)
	dk.add_child(_lbl("DRAW PILE (next card first)  ", 11, C_MUT, MONO))
	var deck: Array = G.deck.duplicate()
	deck.reverse()
	for c in deck.slice(0, 12):
		dk.add_child(_tex(c.key, 28))
	if G.deck.size() > 12:
		dk.add_child(_lbl(" +%d more" % (G.deck.size() - 12), 11, C_MUT, MONO))
	vb.add_child(dk)

# ====================================================================== automated test (--autotest)
func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)

## Presses a real button inside the card popup whose label starts with `prefix`.
func _popup_press(prefix: String) -> bool:
	if popup == null:
		return false
	for b in popup.find_children("*", "Button", true, false):
		if b.text.begins_with(prefix) and not b.disabled:
			b.pressed.emit()
			return true
	return false

func hcz_all() -> Array:
	return board.find_children("*", "", true, false).filter(func(n): return n is HandCard)

func _first_hand_card() -> HandCard:
	for n in board.find_children("*", "Control", true, false):
		if n is HandCard:
			return n
	return null

func _autotest() -> void:
	speed = 40.0
	var out_dir := "/tmp/gshots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	await _shot(out_dir + "/menu.png")
	var runs := ["3", "4", "5", "3", "4"]      # player counts
	var bad := 0
	for ua in OS.get_cmdline_user_args():
		if ua.begins_with("--run="):
			runs = [runs[int(ua.substr(6))]]
	for run in runs:
		cfg.players = run
		_start_game()
		var acts := {"research": 0, "offer": 0, "trade_counter": 0, "trade_no": 0, "honour": 0, "renege": 0, "test": 0, "attack": 0, "stand": 0, "counter": 0, "skip": 0, "declined": 0, "threat": 0, "threat_yes": 0, "threat_no": 0, "disarm": 0}
		var iter := 0
		var shot_taken := false
		while iter < 6000:
			iter += 1
			if "--trace" in OS.get_cmdline_user_args() and G != null:
				print("T ", iter, " t", G.turn_no, " ", G.phase, " cur=", G.cur().name, " popup=", popup != null, " modal=", modal != null, " paused=", paused, " q=", G.war_queue, " prompt=", G.prompt.get("type", "-"), " btns=", btn.keys())
			if iter % 500 == 0 and G != null:
				print("  ..iter ", iter, " turn ", G.turn_no, " phase ", G.phase, " cur ", G.cur().name, " alive ", G.alive_list().size(), " deck ", G.deck.size(), " modal ", modal != null, " prompt ", G.prompt.get("type", "-"), " debts ", G.debts.size(), " paused ", paused, " meAlive ", ME.alive, " queue ", G.war_queue, " counterq ", G.counter_q.size(), " over ", G.over)
			await get_tree().create_timer(0.02).timeout
			if G == null or G.over and modal != null and not modal_btns.is_empty() and modal_btns[0].kind == "again":
				break
			var handled := false
			for mb in modal_btns:
				if not is_instance_valid(mb.button) or mb.button.disabled:
					continue
				if mb.kind == "cease_yes" or mb.kind == "cease_no":
					var cw := "cease_yes" if randf() < 0.3 else "cease_no"
					for mbc in modal_btns:
						if mbc.kind == cw:
							mbc.button.pressed.emit()
							break
					handled = true
					break
				if mb.kind == "counter":
					mb.button.pressed.emit()
					acts.counter += 1
					handled = true
					break
				if mb.kind == "trade_counter" or mb.kind == "trade_no":
					var want := "trade_counter" if randf() < 0.55 else "trade_no"
					for mb2 in modal_btns:
						if mb2.kind == want:
							mb2.button.pressed.emit()
							acts[want] += 1
							break
					handled = true
					break
					break
				if mb.kind == "threat_yes" or mb.kind == "threat_no":
					var tw := "threat_yes" if randf() < 0.5 else "threat_no"
					for mb3 in modal_btns:
						if mb3.kind == tw and not mb3.button.disabled:
							mb3.button.pressed.emit()
							acts[tw] += 1
							break
					for mb4 in modal_btns:
						if mb4.kind == "threat_no":
							mb4.button.pressed.emit()
							break
					handled = true
					break
				if mb.kind == "demand_give" or mb.kind == "demand_no":
					var opts: Array = modal_btns.filter(func(x): return x.kind == "demand_give") if randf() < 0.5 else []
					if opts.is_empty():
						opts = modal_btns.filter(func(x): return x.kind == "demand_no")
					opts[randi() % opts.size()].button.pressed.emit()
					acts["threat_no" if opts[0].kind == "demand_no" else "threat_yes"] += 1
					handled = true
					break
				if mb.kind == "threaten":
					mb.button.pressed.emit()
					acts.threat += 1
					handled = true
					break
				if mb.kind == "disarm_yes":
					mb.button.pressed.emit()
					acts.disarm += 1
					handled = true
					break
				if mb.kind == "launch" and randf() < 0.9:
					mb.button.pressed.emit()
					acts.attack += 1
					handled = true
					break
			if handled or modal != null:
				continue
			if popup != null:
				_close_popup()
			if not ME.alive or G.over:
				continue
			var ptype := str(G.prompt.get("type", ""))
			if ptype == "trade" and G.prompt.player == ME:
				if btn.has("trade_no"):
					var tk := "trade_counter" if randf() < 0.55 else "trade_no"
					btn[tk].pressed.emit()
					acts[tk] += 1
				continue
			if G.turn_no > 120 and iter % 150 == 0:
				_act_ceasefire()      # a long standoff: ask the table to stand down
				continue
			# deliver a pledged card, or break the deal
			if btn.has("renege") and is_instance_valid(btn.renege):
				if randf() < 0.4:
					btn.renege.pressed.emit()
					acts.renege += 1
				else:
					btn.deliver.pressed.emit()
					acts.honour += 1
				continue
			# voluntary disarmament, any time
			if btn.has("disarm") and is_instance_valid(btn.disarm) and not btn.disarm.disabled and randf() < 0.03:
				btn.disarm.pressed.emit()
				continue
			# exchange window
			if btn.has("stand") and is_instance_valid(btn.stand):
				if btn.has("threaten") and is_instance_valid(btn.threaten) and randf() < 0.3:
					btn.threaten.pressed.emit()
					continue
				if btn.has("attack") and not btn.attack.disabled:
					btn.attack.pressed.emit()
					await get_tree().process_frame
					for mb in modal_btns:
						if mb.kind == "launch":
							mb.button.pressed.emit()
							acts.attack += 1
							break
					continue
				if btn.has("test") and not btn.test.disabled:
					btn.test.pressed.emit()
					acts.test += 1
					continue
				btn.stand.pressed.emit()
				acts.stand += 1
				continue
			# my play turn
			if btn.has("skip") and is_instance_valid(btn.skip) and (ME.hand.is_empty() or randf() < 0.5):
				btn.skip.pressed.emit()
				acts.skip += 1
				continue
			if btn.has("research") and is_instance_valid(btn.research):
				if not shot_taken and iter > 40 and G.turn_no > 4:
					shot_taken = true
					await _shot("%s/classic-%sp-board.png" % [out_dir, run])
				if randf() < 0.3 and not ME.hand.is_empty():
					var hc := _first_hand_card()
					if hc != null:
						var before := G.log_entries.size()
						hc.picked.emit(hc.cid, hc)
						await get_tree().process_frame
						await get_tree().process_frame
						_close_popup()
						var others := G.others(ME)
						if _can_offer() and not others.is_empty():
							_drop_offer(others[randi() % others.size()], {"cid": hc.cid})
							acts.offer += 1
						continue
				if not btn.research.disabled:
					btn.research.pressed.emit()
					acts.research += 1
		var title := "(no end)"
		if G != null and G.over:
			await get_tree().create_timer(0.3).timeout
			title = G.result.kind
			await _shot("%s/classic-%sp-end.png" % [out_dir, run])
		else:
			bad += 1
		print("RUN ", run, " iters=", iter, " acts=", acts, " result=", title, " turns=", G.turn_no if G != null else -1)
		_close_modal(true)
	print("AUTOTEST DONE bad=", bad)
	get_tree().quit(1 if bad > 0 else 0)

# ====================================================================== staged screenshots (--shots)
func _stage_take(key: String):
	var pools: Array = [G.deck]
	for p in G.players:
		pools.append(p.hand)
	for arr in pools:
		for i in range(arr.size()):
			if arr[i].key == key:
				return arr.pop_at(i)
	return null

func _stage(np: String, mine: Array, tested: bool) -> void:
	cfg.players = np
	cfg.p1 = "hawk"
	cfg.p2 = "dove"
	cfg.p3 = "wild"
	cfg.p4 = "opp"
	_start_game()
	speed = 1.0
	pump_token += 1
	for k in mine:
		var c = _stage_take(k)
		if c != null:
			ME.hand.append(c)
	if tested:
		G.do_test(ME)
	var h: NPGame.Player = G.players[1]
	for k in NPGame.TECH:
		var c2 = _stage_take(k)
		if c2 != null:
			c2.pub = true
			h.table.append(c2)
	h.tested = true
	var sh = _stage_take("short")
	if sh != null:
		sh.pub = true
		h.hand.append(sh)
	G.turn = 0
	G.phase = "play"
	G.war_queue = []
	G.debts = []
	G.log_entries.clear()
	log_shown = 0
	logbox.clear()
	G.log_msg("Staged position for screenshots.", "sys")
	_render()
	await get_tree().create_timer(0.5).timeout

## Drives the real mouse path: press on a hand card, move, release over a seat (and over the trade-answer zone).
func _mouse(pos: Vector2, pressed := false, button := false, motion := false, held := false) -> void:
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.position = pos
		mm.global_position = pos
		mm.relative = Vector2(8, 0)
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
		Input.parse_input_event(mm)
	if button:
		var mb := InputEventMouseButton.new()
		mb.position = pos
		mb.global_position = pos
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(mb)

var drag_src_hidden := false
var drag_lit := -1      # drag test: how many drop targets were lit just before release

func _drag(from: Vector2, to: Vector2) -> void:
	_mouse(from, false, false, true)
	await get_tree().process_frame
	_mouse(from, true, true)
	await get_tree().process_frame
	for i in range(1, 11):
		_mouse(from.lerp(to, i / 10.0), false, false, true, true)
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	drag_lit = 0
	drag_src_hidden = false
	for n in get_tree().root.find_children("*", "", true, false):
		if n is HandCard and n.dragging and n.modulate.a == 0.0:
			drag_src_hidden = true
	for n in get_tree().root.find_children("*", "", true, false):
		if n is DropTarget and n.hot:
			drag_lit += 1
	if "--dragtest" in OS.get_cmdline_user_args():
		await _shot("/tmp/gshots2/drag-hover.png")
	_mouse(to, false, true)
	await get_tree().create_timer(0.3).timeout

func _dragtest() -> void:
	await get_tree().process_frame
	var fails := 0
	await _stage("4", ["uranium", "refinement", "warhead", "testing", "short", "long"], false)
	G.turn = 0
	G.phase = "play"
	_render()
	await get_tree().create_timer(0.4).timeout
	var seat1: Control = seat_zones.get(1, null)
	var hc := _first_hand_card()
	print("DRAGTEST seat=", seat1 != null, " card=", hc != null, " can_drag=", hc.can_drag if hc else null)
	var before := ME.trade.size()
	var log_before := G.log_entries.size()
	var hand_before := ME.hand.size()
	var hr := hc.get_global_rect()
	await _drag(Vector2(hr.position.x + hr.size.x / 2.0, minf(hr.position.y + 30.0, 705.0)), seat1.get_global_rect().get_center())
	await _shot("/tmp/gshots2/drag-after.png")
	var strays := 0
	for root in [fx_root, popup_root]:
		for n in root.find_children("*", "TextureRect", true, false):
			strays += 1
	var ghost_left: bool = drag_ghost != null and is_instance_valid(drag_ghost) and drag_ghost.is_inside_tree()
	print("DRAGTEST leftovers: overlay textures=", strays, " ghost=", ghost_left, " dragging=", get_viewport().gui_is_dragging())
	if strays > 0 or ghost_left or get_viewport().gui_is_dragging():
		fails += 1
		print("DRAGTEST FAIL: something was left behind after the drop")
	if not drag_src_hidden:
		fails += 1
		print("DRAGTEST FAIL: the card stayed in the hand while being dragged")
	if drag_lit != 1:
		fails += 1
		print("DRAGTEST FAIL: %d targets lit while hovering one trade space" % drag_lit)
	print("DRAGTEST offer: trade ", before, "->", ME.trade.size(), " hand ", hand_before, "->", ME.hand.size(), " prompt=", G.prompt.get("type", "-"), " modal=", modal != null, " toast/declined ok")
	if G.log_entries.size() == log_before:
		fails += 1
		print("DRAGTEST FAIL: nothing happened")
	# trade modal: drop a card in the answer zone
	await _stage("4", ["uranium", "short", "warhead"], false)
	G.turn = 1
	var offered = G.players[1].hand.pop_back()
	offered.pub = true
	G.players[1].trade.append(offered)
	G.prompt = {"type": "trade", "player": ME, "from": G.players[1], "card_id": offered.id, "card_key": offered.key}
	_render()
	await get_tree().create_timer(0.5).timeout
	board_scroll.scroll_vertical = 10000      # hand in view
	await get_tree().create_timer(0.3).timeout
	var src := _first_hand_card()
	var sr := src.get_global_rect()
	await _drag(Vector2(sr.position.x + sr.size.x / 2.0, minf(sr.position.y + 30.0, 705.0)), me_zone.get_global_rect().get_center())
	print("DRAGTEST answer: prompt=", G.prompt.get("type", "-"), " deal done=", G.debts.size() > 0)
	if G.prompt.get("type", "-") == "trade":
		fails += 1
		print("DRAGTEST FAIL: modal drop did nothing")
	# a drag that is let go over nothing puts the card back in the hand
	await _stage("4", ["uranium", "short", "warhead"], false)
	G.turn = 0
	G.phase = "play"
	_render()
	await get_tree().create_timer(0.4).timeout
	board_scroll.scroll_vertical = 10000
	await get_tree().create_timer(0.2).timeout
	var hc3 := _first_hand_card()
	var n_before := ME.hand.size()
	var r3 := hc3.get_global_rect()
	await _drag(Vector2(r3.position.x + 20, minf(r3.position.y + 30, 705)), Vector2(1100, 600))
	await get_tree().create_timer(0.2).timeout
	var back := 0
	for n in board.find_children("*", "", true, false):
		if n is HandCard and n.modulate.a == 1.0:
			back += 1
	print("DRAGTEST cancel: hand ", n_before, "->", ME.hand.size(), " visible cards ", back)
	if ME.hand.size() != n_before or back != ME.hand.size():
		fails += 1
		print("DRAGTEST FAIL: a cancelled drag did not put the card back")
	# hovering survives the board being rebuilt (as it is when the turn moves on)
	await _stage("4", ["uranium", "short", "warhead"], false)
	G.turn = 0
	G.phase = "play"
	_render()
	await get_tree().create_timer(0.3).timeout
	board_scroll.scroll_vertical = 10000
	await get_tree().create_timer(0.2).timeout
	var hh := _first_hand_card()
	var hcid := hh.cid
	var hp2 := hh.get_global_rect().position + Vector2(10, 40)
	Input.warp_mouse(hp2)      # the real pointer: a rebuilt board looks for it there
	_mouse(hp2, false, false, true)
	await get_tree().create_timer(0.3).timeout
	_render()      # the turn changes: everything is rebuilt under the still mouse
	for i in range(4):
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	var lifted := false
	for n in board.find_children("*", "", true, false):
		if n is HandCard and n.cid == hcid and n.z_index == 20 and n.face != null and n.face.scale.x > 1.3:
			lifted = true
	print("DRAGTEST hover kept after a rebuild: ", lifted)
	if not lifted:
		fails += 1
		print("DRAGTEST FAIL: the hovered card dropped when the board was rebuilt")
	print("DRAGTEST DONE fails=", fails)
	get_tree().quit(fails)

## --touchtest: the same game driven by a finger (screen touches, turned into mouse events by Godot).
func _touch(pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	Input.parse_input_event(t)

func _touch_drag(from: Vector2, to: Vector2, hold := 0.0) -> void:
	_touch(from, true)
	await get_tree().process_frame
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
	for i in range(1, 13):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from.lerp(to, i / 12.0)
		d.relative = (to - from) / 12.0
		Input.parse_input_event(d)
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	_touch(to, false)
	await get_tree().create_timer(0.3).timeout

func _touchtest() -> void:
	await get_tree().process_frame
	var fails := 0
	var say := func(ok: bool, what: String):
		print("TOUCHTEST ", "ok   " if ok else "FAIL ", what)
		return 0 if ok else 1
	# menu: tap a small card - it stays enlarged; the next touch puts it away
	var small: Control = null
	for n in menu_root.find_children("*", "TextureRect", true, false):
		if n.custom_minimum_size.x == 64.0:
			small = n
			break
	var c0 := small.get_global_rect().get_center()
	_touch(Vector2(1200, 700), true)      # the first touch tells the game a finger is in use
	await get_tree().process_frame
	_touch(Vector2(1200, 700), false)
	await get_tree().process_frame
	_touch(c0, true)
	await get_tree().process_frame
	_touch(c0, false)
	await get_tree().create_timer(0.2).timeout
	fails += say.call(touch and zoom != null, "tap on a small card enlarges it")
	_touch(Vector2(1200, 700), true)
	await get_tree().process_frame
	_touch(Vector2(1200, 700), false)
	await get_tree().create_timer(0.2).timeout
	fails += say.call(zoom == null, "the next tap puts it away")
	# the emulated pointer resting on a card must not enlarge it by "hovering"
	var mm := InputEventMouseMotion.new()
	mm.device = InputEvent.DEVICE_ID_EMULATION
	mm.position = c0
	mm.relative = Vector2(1, 0)
	Input.parse_input_event(mm)
	await get_tree().create_timer(0.2).timeout
	fails += say.call(zoom == null, "no hover zoom from a finger")
	# game: hold a hand card to see it, tap it for its options
	await _stage("4", ["uranium", "refinement", "warhead", "testing", "short", "long"], false)
	G.turn = 0
	G.phase = "play"
	_render()
	await get_tree().create_timer(0.4).timeout
	board_scroll.scroll_vertical = 10000
	await get_tree().create_timer(0.2).timeout
	var hc := _first_hand_card()
	var hp := hc.get_global_rect().get_center() + Vector2(-hc.size.x * 0.3, 0)
	_touch(hp, true)
	await get_tree().create_timer(0.7).timeout
	var lifted := hc.face != null and hc.face.scale.x > 1.1
	_touch(hp, false)
	await get_tree().create_timer(0.3).timeout
	fails += say.call(lifted, "holding a hand card lifts it")
	fails += say.call(popup == null and hc.face.scale.x < 1.1, "letting go of a hold puts it back, no menu")
	_touch(hp, true)
	await get_tree().process_frame
	_touch(hp, false)
	await get_tree().create_timer(0.3).timeout
	fails += say.call(popup != null, "a quick tap opens the card's options")
	_touch(Vector2(1200, 60), true)
	await get_tree().process_frame
	_touch(Vector2(1200, 60), false)
	await get_tree().create_timer(0.3).timeout
	fails += say.call(popup == null, "tapping away closes them")
	# drag a card from the hand onto a player's trade area
	var seat1: Control = seat_zones.get(1, null)
	var log_before := G.log_entries.size()
	var hand_before := ME.hand.size()
	hc = _first_hand_card()
	var hr := hc.get_global_rect()
	await _touch_drag(Vector2(hr.position.x + hr.size.x * 0.3, minf(hr.position.y + 30.0, 705.0)), seat1.get_global_rect().get_center())
	await get_tree().create_timer(0.3).timeout
	# the AI may turn the offer down (the card then comes back) - either way the offer was made
	var offered := false
	for i in range(log_before, G.log_entries.size()):
		if str(G.log_entries[i].text).begins_with(ME.name + " offers"):
			offered = true
	fails += say.call(offered, "dragging a card to a seat offers it (hand %d->%d)" % [hand_before, ME.hand.size()])
	fails += say.call(not get_viewport().gui_is_dragging(), "drag finished")
	# hold a portrait: its hint appears
	await _stage("4", ["uranium", "short"], false)
	G.turn = 0
	G.phase = "play"
	_render()
	board_scroll.scroll_vertical = 0
	await get_tree().create_timer(0.4).timeout
	var frame: Control = null
	for n in board.find_children("*", "PanelContainer", true, false):
		if n.tooltip_text == G.players[1].name:
			frame = n
			break
	var fp := frame.get_global_rect().get_center()
	_touch(fp, true)
	await get_tree().create_timer(0.8).timeout
	_touch(fp, false)
	await get_tree().create_timer(0.1).timeout
	var shown := false
	for n in fx_root.find_children("*", "Label", true, false):
		if n.text == G.players[1].name:
			shown = true
	fails += say.call(shown, "holding a portrait shows its hint")      # (an older toast may be fading out meanwhile)
	await _shot("/tmp/gshots2/touch-hint.png")
	# a real mouse brings hovering back
	var real := InputEventMouseMotion.new()
	real.device = 0
	real.position = Vector2(640, 300)
	real.relative = Vector2(3, 0)
	Input.parse_input_event(real)
	await get_tree().process_frame
	fails += say.call(not touch and not HandCard.touch, "a real mouse switches hovering back on")
	# upright phone: ask for landscape
	_check_orientation(Vector2(720, 1500))
	await get_tree().process_frame
	fails += say.call(turn_overlay != null, "portrait screen asks to turn the device")
	await _shot("/tmp/gshots2/touch-portrait.png")
	_check_orientation(Vector2(1280, 720))
	fails += say.call(turn_overlay == null, "landscape again removes it")
	print("TOUCHTEST DONE fails=", fails)
	get_tree().quit(fails)

## --readme-shot: a real game, played for a while (you research, pass and keep your deals), then a
## screenshot of the board on your turn, for the README: /tmp/gshots2/readme.png
func _readme_shot() -> void:
	await get_tree().process_frame
	cfg.players = "5"
	cfg.name = "You"
	for i in range(4):
		cfg["p%d" % (i + 1)] = ["hawk", "dove", "wild", "opp"][i]
	for attempt in range(40):
		_start_game()
		pump_token += 1      # we drive the game ourselves, without the AI pacing
		var guard := 0
		while not G.over and guard < 3000:
			guard += 1
			var st := G.status()
			if st == "prompt":
				var pr := G.prompt
				if str(pr.get("type", "")) == "trade":
					G.answer_trade(ME.hand[0].id if not ME.hand.is_empty() else -1)
				elif str(pr.get("type", "")) == "threat":
					G.answer_threat(false)
				elif str(pr.get("type", "")) == "demand":
					G.answer_demand(-1)
				elif str(pr.get("type", "")) == "ceasefire":
					G.answer_ceasefire(false)
				else:
					G.choose_counter(pr.options[0])
			elif st == "human":
				var tested := G.players.filter(func(q): return q.tested).size()
				var trades := G.debts.size()
				if G.phase == "play" and G.cur() == ME and G.turn_no >= 18 and tested >= 1 and ME.alive and G.deck.size() >= 3 and G.alive_list().size() == 4:
					_render()
					board_scroll.scroll_vertical = 0
					await get_tree().create_timer(1.0).timeout
					for fx in fx_root.get_children():      # no half-finished "NUCLEAR TEST" flash in the picture
						fx.queue_free()
					await get_tree().create_timer(0.3).timeout
					await _shot("/tmp/gshots2/readme.png")
					print("README SHOT turn ", G.turn_no, " attempt ", attempt)
					get_tree().quit(0)
					return
				if G.phase == "honour":
					G.honour(ME)
				elif G.phase == "play":
					if not G.play_research(ME):
						G.play_skip(ME)
				else:
					G.war_declare(ME, {"kind": "pass"})
			else:
				G.step()
	print("README SHOT: no suitable position found")
	get_tree().quit(1)

var scroll_to_me := func():
	board_scroll.scroll_vertical = 0

## The new characters: the menu list, a table with them, the F9 view and a stand-down proposal.
func _personashots() -> void:
	var d := "/tmp/gshots2"
	DirAccess.make_dir_recursive_absolute(d)
	await get_tree().process_frame
	opp_btns[0].show_popup()
	await get_tree().create_timer(0.4).timeout
	await _shot(d + "/13-menu-characters.png")
	opp_btns[0].get_popup().hide()
	cfg.players = "5"
	cfg.p1 = "pacifist"
	cfg.p2 = "peacemaker"
	cfg.p3 = "schemer"
	cfg.p4 = "hawk"
	_start_game()
	speed = 1.0
	pump_token += 1
	await get_tree().create_timer(0.6).timeout
	await _shot(d + "/13-table.png")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F9
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.6).timeout
	await _shot(d + "/13-debug.png")
	Input.parse_input_event(ev)
	await get_tree().create_timer(0.3).timeout
	G.prompt = {"type": "ceasefire", "player": ME, "from": G.players[1]}
	_ceasefire_modal()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/13-ceasefire.png")
	print("PERSONA SHOTS DONE")
	get_tree().quit(0)

## The Mutually Assured Destruction front page, once with each of its photographs.
## Two Superpowers at the table - you and the hawk - with every Capability on show.
func _supershots() -> void:
	var d := "/tmp/gshots2"
	DirAccess.make_dir_recursive_absolute(d)
	await _stage("4", NPGame.TECH + ["short", "long", "counter", "super"], true)
	var h: NPGame.Player = G.players[1]
	for k in ["long", "counter", "super"]:
		var c = _stage_take(k)
		if c != null:
			h.hand.append(c)
	G.check_over()
	_render()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/14-superpower-flash.png")
	await get_tree().create_timer(3.0).timeout      # the flash and the toast gone: the plain board
	await _shot(d + "/14-superpower.png")
	print("SUPER SHOTS DONE")
	get_tree().quit(0)

func _madshots() -> void:
	var d := "/tmp/gshots2"
	DirAccess.make_dir_recursive_absolute(d)
	# a destroyed power: burnt hand, its bones falling into its trade area, then smouldering
	await _stage("4", ["uranium", "short", "warhead"], false)
	G.kill([G.players[2]], {G.players[2].id: G.players[1]})
	G.settle()
	_render()
	await get_tree().create_timer(0.25).timeout
	await _shot(d + "/12-bones-falling.png")
	await get_tree().create_timer(2.5).timeout
	await _shot(d + "/12-bones.png")
	# and you: your own hand burnt, your bones in your trade area
	G.kill([ME], {ME.id: G.players[1]})
	G.settle()
	_render()
	await get_tree().create_timer(2.5).timeout
	await _shot(d + "/12-bones-you.png")
	await _stage("5", ["uranium", "short", "warhead"], false)
	G.kill([G.players[3]], {G.players[3].id: G.players[1]})
	G.settle()
	G.end_game("mad")
	for i in range(MAD_PICS.size()):
		mad_pic = i
		_end_modal()
		await get_tree().create_timer(0.6).timeout
		await _shot(d + "/11-mad-%s.png" % MAD_PICS[i].pic)
		if i == 0:
			modal_scroll.scroll_vertical = 2000
			await get_tree().create_timer(0.3).timeout
			await _shot(d + "/11-mad-bottom.png")
	print("MAD SHOTS DONE")
	get_tree().quit(0)

func _shots() -> void:
	var d := "/tmp/gshots2"
	DirAccess.make_dir_recursive_absolute(d)
	await get_tree().process_frame
	await _shot(d + "/0-menu.png")
	players_opt.show_popup()
	await get_tree().create_timer(0.3).timeout
	await _shot(d + "/0b-menu-players.png")
	players_opt.get_popup().hide()
	players_opt.select(2)
	players_opt.item_selected.emit(2)
	await get_tree().create_timer(0.2).timeout
	opp_btns[0].select(1)
	opp_btns[0].show_popup()
	await get_tree().create_timer(0.3).timeout
	await _shot(d + "/0c-menu-opponents.png")
	opp_btns[0].get_popup().hide()
	opp_btns[0].select(0)
	await get_tree().create_timer(0.2).timeout
	print("PLAYERS label: ", players_opt.text)
	players_opt.select(0)
	players_opt.item_selected.emit(0)
	await _stage("4", ["uranium", "refinement", "warhead", "testing", "short", "long"], false)
	await _shot(d + "/1-board4.png")
	# hover: a small table card shows large; a hand card grows
	var small: Control = null
	for n in board.find_children("*", "TextureRect", true, false):
		if n.custom_minimum_size.x < 60.0 and n.is_visible_in_tree() and n.get_global_rect().position.y > 200:
			small = n
			break
	if small != null:
		_mouse(small.get_global_rect().get_center(), false, false, true)
		await get_tree().create_timer(0.3).timeout
		await _shot(d + "/1h-hover-small.png")
	var hcz := _first_hand_card()
	if hcz != null:
		var hr2 := hcz.get_global_rect()
		_mouse(Vector2(hr2.position.x + 20, minf(hr2.position.y + 30, 705)), false, false, true)
		await get_tree().create_timer(0.3).timeout
		await _shot(d + "/1i-hover-hand.png")
		# move onto the visible edge of each neighbour in turn: each must take over the hover
		var cards: Array = hcz.get_parent().get_children()
		var ok_edges := 0
		for i in range(1, cards.size()):
			var cr: Rect2 = cards[i].get_global_rect()
			_mouse(Vector2(cr.position.x + 10, minf(cr.position.y + 40, 705)), false, false, true)
			await get_tree().create_timer(0.15).timeout
			var prev: Rect2 = cards[i - 1].get_global_rect()
			_mouse(Vector2(prev.position.x + 6, minf(prev.position.y + 40, 705)), false, false, true)
			await get_tree().create_timer(0.15).timeout
			if cards[i - 1].z_index == 20 and cards[i].z_index == 0:
				ok_edges += 1
		print("HOVER EDGES ok ", ok_edges, " / ", cards.size() - 1)
		await _shot(d + "/1j-hover-edge.png")
		_mouse(Vector2(640, 20), false, false, true)
		await get_tree().create_timer(0.2).timeout
	_toggle_debug()
	await get_tree().create_timer(0.3).timeout
	await _shot(d + "/8-debug.png")
	_toggle_debug()
	await _stage("5", ["uranium", "refinement", "short", "long"], false)
	await _shot(d + "/1c-board5.png")
	await _stage("4", ["uranium", "refinement", "warhead", "testing", "short", "long"], false)
	var hc := _first_hand_card()
	if hc != null:
		_card_menu(hc.cid, hc)
		await get_tree().create_timer(0.4).timeout
		await _shot(d + "/2-offer-popup.png")
		_close_popup()
		# every card's popup should be the same compact size
		var sizes: Array = []
		for n2 in hcz_all():
			_card_menu(n2.cid, n2)
			await get_tree().create_timer(0.1).timeout
			var pnl: Control = popup.get_child(1)
			sizes.append(pnl.size)
			_close_popup()
		print("POPUP sizes ", sizes)
	await _stage("3", ["uranium", "refinement", "warhead", "testing", "short", "long", "counter"], false)
	await _shot(d + "/3-board3.png")
	G.do_test(ME)
	G.phase = "war"
	G._rebuild_war_queue(0)
	_render()
	await get_tree().create_timer(0.4).timeout
	await _shot(d + "/4-war.png")
	_attack_modal()
	await get_tree().create_timer(0.6).timeout
	await _shot(d + "/5-attack.png")
	_close_modal(true)
	# an AI offers me a card (face down) and I pick a card to offer back
	await _stage("4", ["uranium", "short", "warhead"], false)
	G.turn = 1
	var offered = G.players[1].hand.pop_back()
	offered.pub = true
	G.players[1].trade.append(offered)
	G.prompt = {"type": "trade", "player": ME, "from": G.players[1], "card_id": offered.id, "card_key": offered.key}
	_render()
	await get_tree().create_timer(0.5).timeout
	scroll_to_me.call()
	await get_tree().create_timer(0.3).timeout
	await _shot(d + "/6-trade-offer.png")
	G.players[1].hand.append(G.players[1].trade.pop_back())
	G.prompt = {}
	G.turn = 0
	G.phase = "play"
	# a pledge waiting to be delivered
	G.prompt = {}
	var pledge = ME.hand.pop_back()
	pledge.pub = true
	ME.trade.append(pledge)
	var pl2 = G.players[3].hand.pop_back()
	pl2.pub = true
	G.players[3].trade.append(G.players[3].hand.pop_back())
	G.players[3].trade[0].pub = true
	G.debts = [{"from": 3, "to": 0, "got": 0, "pledge": pledge.id}, {"from": 2, "to": 3, "got": 0, "pledge": G.players[3].trade[0].id}]
	G.turn = 0
	G.phase = "honour"
	_render()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/7-honour.png")
	betrayals[1] = 1
	_render()
	await get_tree().create_timer(0.4).timeout
	await _shot(d + "/7d-betrayed.png")
	betrayals.clear()
	died_at.clear()
	# a threat against me, my own threat menu, and the disarm confirmation
	G.debts = []
	G.turn = 1
	G.phase = "war"
	G.prompt = {"type": "threat", "player": ME, "from": G.players[1]}
	_render()
	_threat_modal()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/7a-threat.png")
	_close_modal(true)
	G.prompt = {}
	G.do_test(ME)
	G.turn = 0
	G.phase = "war"
	G._rebuild_war_queue(0)
	_render()
	_threaten_modal()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/7b-threaten.png")
	_close_modal(true)
	_disarm_modal()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/7c-disarm.png")
	_close_modal(true)
	_rules_modal()
	await get_tree().create_timer(0.6).timeout
	await _shot(d + "/8-rules.png")
	modal_scroll.scroll_vertical = 650
	await get_tree().create_timer(0.3).timeout
	await _shot(d + "/9-rules-2.png")
	modal_scroll.scroll_vertical = 1500
	await get_tree().create_timer(0.3).timeout
	await _shot(d + "/9-rules-3.png")
	# an eliminated player keeps their revealed hand on show
	await _stage("4", ["uranium", "short", "warhead"], false)
	G.kill([G.players[2]], {})
	G.settle()
	_render()
	await get_tree().create_timer(1.6).timeout
	await _shot(d + "/9-eliminated.png")
	# while an AI plays, the banner states its move
	await _stage("4", ["uranium", "short", "warhead"], false)
	G.turn = 1
	G.phase = "play"
	G.trade_offer(G.players[1], G.players[1].hand[0].id, 2)
	_render()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/10-ai-move.png")
	print("SHOTS DONE")
	get_tree().quit(0)
