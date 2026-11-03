class_name PortraitUI
extends Control
## The phone layout: the same game on an upright screen, built to the mobile design.
## Three bands - the other powers, the table, you - and one verb: drag a card where it goes.
## Everything you might want to know on demand lives in a bottom sheet. The landscape and desktop
## layout in main.gd is untouched; main.gd shows this instead whenever the screen is taller than wide.

var M                      # main.gd: fonts, card pictures, the engine hooks and the sound
var MainS: Script          # main.gd's script, for its inner classes (HandCard, CardBack, TableMap)

const C_BG := Color("#121309")
const C_PANEL := Color("#22241ae6")
const C_PANEL2 := Color("#2b2d1f")
const C_LINE := Color("#57573a")
const C_INK := Color("#efe5c8")
const C_MUT := Color("#b0a684")
const C_AMBER := Color("#d9a73e")
const C_RED := Color("#b8432f")
const C_RED_FILL := Color("#8f3324")
const C_GREEN := Color("#a3b866")
const C_CHIP := Color("#40461e")
const C_CHIP_BD := Color("#a69b65")
const C_PAPER := Color("#d9d2be")
const INK := Color("#1f1b14")
const INK_SUB := Color("#5a523f")
const INK_RED := Color("#8a2b1c")
const INK_BRASS := Color("#6b4e0e")
const CARD_R := 430.0 / 330.0      # the art is 660 x 860: every card keeps 33:43
const ICON_W := 20.0
const TABLE_W := 44.0
const HAND_W := 108.0
const ZOOM_W := 258.0
const PILE_W := 88.0
const ORDER := ["uranium", "refinement", "warhead", "testing", "short", "long", "counter", "super"]

var G: NPGame = null
var ME: NPGame.Player = null
var fonts := {}
var menu_view: Control = null
var board_view: Control = null
var seats := {}                    # player id -> seat panel
var targets: Array = []            # every drop target on the board: [{node, accept}]
var dimmed: Array = []             # what a drag or a sheet has dimmed
var sheet: Control = null
var sheet_sticky := false
var hand_view: Control = null
var newsprint: Texture2D = null
var top_pad := 16.0
var bot_pad := 16.0

# ====================================================================== pieces
## A panel that takes a dropped card when `accept` allows it, and opens something when tapped.
class Target extends PanelContainer:
	var accept: Callable
	var on_drop: Callable
	var tap: Callable
	var press_at := Vector2.ZERO
	var pressed := false
	func _can_drop_data(_at: Vector2, d: Variant) -> bool:
		return d is Dictionary and d.has("cid") and accept.is_valid() and accept.call(d)
	func _drop_data(_at: Vector2, d: Variant) -> void:
		on_drop.call_deferred(d)
	func _gui_input(e: InputEvent) -> void:
		if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
			return
		if e.pressed:
			pressed = true
			press_at = e.position
		elif pressed:
			pressed = false
			if tap.is_valid() and e.position.distance_to(press_at) < 12.0 and not get_viewport().gui_is_dragging():
				tap.call()

## A card on your table that can be dragged onto a seat (the Superpower strike).
class TableDrag extends Control:
	var data := {}
	var preview: Callable
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _get_drag_data(_at: Vector2) -> Variant:
		if data.is_empty():
			return null
		if preview.is_valid():
			set_drag_preview(preview.call())
		return data

## A stamp beside a portrait: disarmed, an offer pending with you, a pledge owed to you.
class Glyph extends Control:
	var kind := ""
	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, size.x / 2.0, Color("#121309eb"))
		var ring := Color("#b0a684") if kind == "disarmed" else Color("#d9a73e")
		draw_arc(c, size.x / 2.0 - 0.5, 0.0, TAU, 32, ring, 1.0, true)
		var s := size.x / 20.0      # the icons are drawn on a 12 px grid inside a 20 px disc
		var o := c - Vector2(6, 6) * s
		var pt := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
		match kind:
			"disarmed":
				var m := Color("#b0a684")
				draw_polyline(PackedVector2Array([pt.call(6, 1), pt.call(8, 4), pt.call(8, 8.5), pt.call(4, 8.5), pt.call(4, 4), pt.call(6, 1)]), m, 1.2 * s, true)
				draw_line(pt.call(4, 8.5), pt.call(3, 11), m, 1.2 * s, true)
				draw_line(pt.call(8, 8.5), pt.call(9, 11), m, 1.2 * s, true)
				draw_line(pt.call(1.5, 10.5), pt.call(10.5, 1.5), Color("#b8432f"), 1.6 * s, true)
			"offer":
				var a := Color("#d9a73e")
				draw_rect(Rect2(pt.call(1.5, 1), Vector2(6, 8) * s), a, false, 1.2 * s)
				draw_line(pt.call(9, 4.5), pt.call(9, 11), a, 1.2 * s, true)
				draw_polyline(PackedVector2Array([pt.call(7, 9), pt.call(9, 11), pt.call(11, 9)]), a, 1.2 * s, true)
			"pledge":
				var a2 := Color("#d9a73e")
				for k in range(4):      # a dashed card
					var y0 := 1.5 + k * 2.4
					draw_line(pt.call(1.5, y0), pt.call(1.5, y0 + 1.4), a2, 1.2 * s, true)
					draw_line(pt.call(8, y0), pt.call(8, y0 + 1.4), a2, 1.2 * s, true)
				for k in range(3):
					var x0 := 1.5 + k * 2.4
					draw_line(pt.call(x0, 1.5), pt.call(x0 + 1.4, 1.5), a2, 1.2 * s, true)
					draw_line(pt.call(x0, 10.5), pt.call(x0 + 1.4, 10.5), a2, 1.2 * s, true)
				draw_circle(pt.call(9, 9), 2.6 * s, Color("#121309"))
				draw_arc(pt.call(9, 9), 2.6 * s, 0.0, TAU, 20, a2, 1.1 * s, true)
				draw_line(pt.call(9, 7.6), pt.call(9, 9), a2, 1.0 * s, true)
				draw_line(pt.call(9, 9), pt.call(10.1, 9.8), a2, 1.0 * s, true)

## The hand: a spread from the left, each card showing a sliver, the last one whole. Never scrolls.
class Spread extends Control:
	var cw := 108.0
	var ch := 140.0
	var max_sliver := 116.0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			layout()
	func layout() -> void:
		var cards := get_children()
		var n := cards.size()
		if n == 0:
			return
		var sliver := max_sliver
		if n > 1:
			sliver = minf(max_sliver, (size.x - cw) / float(n - 1))
		for i in range(n):
			var c: Control = cards[i]
			c.size = Vector2(cw, ch)
			c.position = Vector2(i * sliver, 0)
			if "base_y" in c:
				c.base_y = 0.0
			if "fresh" in c and c.fresh:      # a drawn card drops in from the pile
				c.fresh = false
				c.position.y = -40.0
				c.modulate.a = 0.0
				var t := c.create_tween().set_parallel(true)
				t.tween_property(c, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				t.tween_property(c, "modulate:a", 1.0, 0.25)

# ====================================================================== boot
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MainS = M.get_script()
	fonts = {
		"head": M.HEAD, "mono": M.MONO,
		"body": load("res://fonts/CourierPrime-Regular.ttf"), "bold": load("res://fonts/CourierPrime-Bold.ttf"),
		"paper": load("res://fonts/OldStandard-Regular.woff2"), "paperb": load("res://fonts/OldStandard-Bold.woff2"),
		"paperi": load("res://fonts/OldStandard-Italic.woff2"), "mast": load("res://fonts/UnifrakturCook-Bold.woff2"),
	}
	newsprint = load("res://assets/ui/newsprint.png")
	if OS.has_feature("mobile"):      # a notch or a home bar: keep clear of them on a native build
		var sa := DisplayServer.get_display_safe_area()
		var ss := DisplayServer.screen_get_size()
		var k := get_viewport_rect().size.x / maxf(1.0, float(ss.x))
		top_pad = 8.0 + sa.position.y * k
		bot_pad = 12.0 + (ss.y - sa.end.y) * k

## Rebuilt whenever the game moves on; the menu when there is no game.
func render() -> void:
	G = M.G
	ME = M.ME
	if G == null:
		if board_view != null:
			board_view.queue_free()
			board_view = null
		if menu_view == null:
			menu_view = _build_menu()
			add_child(menu_view)
		return
	if menu_view != null:
		menu_view.queue_free()
		menu_view = null
	var old := board_view
	board_view = _build_board()
	add_child(board_view)
	if old != null:
		old.queue_free()
	M.fresh.clear()

func close_all() -> void:
	close_sheet()

# ====================================================================== style helpers
func _sb(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 8, pad := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s

## The glow of a legal drop target: a 2 px amber ring and a 12 px halo. The same on every target.
func _glow_sb(base: StyleBoxFlat) -> StyleBoxFlat:
	var s := base.duplicate() as StyleBoxFlat
	s.border_color = C_AMBER
	s.set_border_width_all(2)
	s.shadow_size = 12
	s.shadow_color = Color(C_AMBER, 0.55)
	s.shadow_offset = Vector2.ZERO
	return s

func _lbl(text: String, fsize: int, color: Color, font: Font = null, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font if font != null else fonts.body)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

## Stardos Stencil, capitals, spaced: seat names, sheet titles, counts.
func _head(text: String, fsize: int, color := C_INK) -> Label:
	var l := _lbl(text.to_upper(), fsize, color, fonts.head)
	return l

## Special Elite small capitals: subtitles and captions.
func _small(text: String, color := C_MUT, fsize := 11) -> Label:
	return _lbl(text.to_upper(), fsize, color, fonts.mono)

func _rtl(bb: String, fsize := 15, color := C_INK, font: Font = null, bold: Font = null) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", font if font != null else fonts.body)
	r.add_theme_font_override("bold_font", bold if bold != null else fonts.bold)
	r.add_theme_font_size_override("normal_font_size", fsize)
	r.add_theme_font_size_override("bold_font_size", fsize)
	r.add_theme_font_size_override("italics_font_size", fsize)
	r.add_theme_color_override("default_color", color)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bb
	return r

## A card picture at a width, in the art's proportion. No hover, no hint: a tap does the talking.
func _card(key: String, w: float, burnt := false) -> TextureRect:
	var t := TextureRect.new()
	t.texture = M.TEXB.get(key, M.TEX[key]) if burnt else M.TEX[key]
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.custom_minimum_size = Vector2(w, w * CARD_R)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _back(w: float) -> Control:
	var cb = MainS.CardBack.new()
	cb.custom_minimum_size = Vector2(w, w * CARD_R)
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cb

## A card picture that opens its zoom sheet when tapped.
func _tap_card(key: String, w: float, on_tap: Callable, burnt := false) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, w * CARD_R)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var t := _card(key, w, burnt)
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(t)
	b.pressed.connect(on_tap)
	b.mouse_filter = Control.MOUSE_FILTER_PASS      # a card dropped on it reaches the area behind
	return b

func _portrait_tex(p: NPGame.Player) -> Texture2D:
	return M._portrait_tex(p)

func _photo(p: NPGame.Player, s: float, radius := 4) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(s, s)
	pc.add_theme_stylebox_override("panel", _sb(Color("#1e2016"), Color(0, 0, 0, 0), 0, radius, 0))
	pc.clip_contents = true
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := _portrait_tex(p)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(t)
	else:
		var l := _head(p.name.split(" ")[-1].left(1), int(s * 0.5), C_MUT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pc.add_child(l)
	return pc

## A 52-tall button in one of the sheet's five voices: primary, danger, caution, neutral, quiet (and green).
func _pbtn(text: String, kind := "neutral", pill := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 52
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not pill else Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", fonts.bold)
	b.add_theme_font_size_override("font_size", 15)
	var bg := C_PANEL2
	var bd := C_LINE
	var fg := C_INK
	match kind:
		"primary":
			bg = C_AMBER
			bd = Color("#a87d22")
			fg = Color("#17120a")
		"danger":
			bg = C_RED_FILL
			bd = C_RED
		"caution":
			bd = C_AMBER
			fg = C_AMBER
		"green":
			bd = C_GREEN
			fg = C_GREEN
		"quiet":
			bg = Color(0, 0, 0, 0)
			fg = C_MUT
		"paper":
			bg = Color(0, 0, 0, 0)
			bd = Color(INK, 0.4)
			fg = INK
	for st in ["normal", "hover", "pressed", "disabled"]:
		var s := _sb(bg, bd, 1, 26 if pill else 8)
		s.content_margin_left = 24 if pill else 16
		s.content_margin_right = 24 if pill else 16
		if st == "pressed":
			s.bg_color = bg.lightened(0.1) if bg.a > 0.0 else Color(C_INK, 0.08)
		elif st == "disabled":
			s.bg_color = Color(bg, bg.a * 0.35)
			s.border_color = Color(bd, 0.35)
		if pill:
			s.shadow_size = 16
			s.shadow_color = Color(0, 0, 0, 0.5)
			s.shadow_offset = Vector2(0, 6)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.35))
	return b

func _vbox(sep: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func _hbox(sep: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

func _rule(c: Color, h: float) -> Control:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size.y = h
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _paper_sb(pad_h := 10, pad_v := 10) -> StyleBoxTexture:
	var tx := StyleBoxTexture.new()
	tx.texture = newsprint
	tx.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	tx.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	tx.content_margin_left = pad_h
	tx.content_margin_right = pad_h
	tx.content_margin_top = pad_v
	tx.content_margin_bottom = pad_v
	return tx

## Inside a tappable panel, nothing but a button takes the touch: the panel gets the tap and the drop.
func _ignore(n: Node) -> void:
	for ch in n.get_children():
		if ch is Control and not (ch is BaseButton) and not (ch is TableDrag):
			ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore(ch)

# ====================================================================== state
func _war_me() -> bool:
	return G.phase == "war" and not G.war_queue.is_empty() and int(G.war_queue[0]) == ME.id and G.prompt.is_empty()

func _my_turn() -> bool:
	return not G.over and ME.alive and G.cur() == ME and G.phase == "play" and G.prompt.is_empty()

func _answering() -> bool:
	return M._answering()

func _can_offer() -> bool:
	return M._can_offer()

func _can_research() -> bool:
	return _my_turn() and not G.deck.is_empty()

func _can_test() -> bool:
	return not G.over and ME.alive and G.prompt.is_empty() and G.can_test(ME) and (_war_me() or G.can_strike_now(ME))

## A card of yours, in hand or on the table.
func _my_card(cid: int) -> Dictionary:
	for arr in [ME.hand, ME.table]:
		for c in arr:
			if c.id == cid:
				return c
	return {}

## The weapon a dragged card fires, or "".
func _weapon_of(c: Dictionary) -> String:
	if c.is_empty():
		return ""
	if c.key == "super" and G.is_superpower(ME):
		return "super"
	if (c.key == "short" or c.key == "long") and ME.hand.has(c):
		return c.key
	return ""

func _strike_ok(type: String, p: NPGame.Player) -> bool:
	if type == "" or not (_war_me() or G.can_strike_now(ME)):
		return false
	for av in G.attack_types(ME):
		if av.type == type and av.targets.has(p.id):
			return true
	return false

func _any_strike() -> bool:
	return (_war_me() or G.can_strike_now(ME)) and not G.attack_types(ME).is_empty()

func _reaches_me(p: NPGame.Player) -> bool:
	for av in G.attack_types(p, true):
		if av.targets.has(ME.id):
			return true
	return false

## A weapon that can fire goes only where it can strike (the strike sheet still offers the trade);
## any other card goes to any power you can trade with.
func _seat_accept(d: Dictionary, p: NPGame.Player) -> bool:
	var c := _my_card(int(d.cid))
	if c.is_empty() or not p.alive:
		return false
	var w := _weapon_of(c)
	if w != "" and _armed(w):
		return _strike_ok(w, p)
	return _can_offer() and ME.hand.has(c)

## Could this weapon fire at someone right now?
func _armed(w: String) -> bool:
	for q in G.players:
		if q != ME and _strike_ok(w, q):
			return true
	return false

func _seat_drop(d: Dictionary, p: NPGame.Player) -> void:
	var c := _my_card(int(d.cid))
	if c.is_empty():
		return
	var w := _weapon_of(c)
	if _strike_ok(w, p):
		strike_sheet(p, c, w)
	elif _can_offer() and ME.hand.has(c):
		M._drop_offer(p, d)

# ====================================================================== the board
func _build_board() -> Control:
	seats.clear()
	targets.clear()
	dimmed.clear()
	var vp := get_viewport_rect().size
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bands := _vbox(0)
	bands.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bands)
	var h1 := top_pad + 128.0 + 8.0
	var h2 := 224.0 if vp.y >= 820.0 else maxf(150.0, vp.y * 0.26)
	bands.add_child(_band_seats(h1))
	bands.add_child(_band_table(h2))
	bands.add_child(_band_me())
	return root

## Band one: the other powers, in turn order, every seat the same height.
func _band_seats(h: float) -> Control:
	var mc := MarginContainer.new()
	mc.custom_minimum_size.y = h
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_top", int(top_pad))
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 16)
	mc.add_theme_constant_override("margin_bottom", 8)
	var row := _hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(row)
	var n := G.players.size() - 1
	var w := minf(150.0, (get_viewport_rect().size.x - 32.0 - 8.0 * (n - 1)) / float(n))
	for i in range(1, G.players.size()):
		row.add_child(_seat(G.players[i], w))
	return mc

func _seat(p: NPGame.Player, w: float) -> Control:
	var turn: bool = G.turn == p.id and not G.over and p.alive and G.phase != "war"
	var pc := Target.new()
	pc.custom_minimum_size = Vector2(w, 128)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var base := _sb(C_PANEL, C_LINE, 1, 8, 0)
	base.content_margin_left = 6
	base.content_margin_right = 6
	base.content_margin_top = 8
	base.content_margin_bottom = 8
	if turn:
		base.border_color = C_AMBER
		base.set_border_width_all(2)
	pc.add_theme_stylebox_override("panel", base)
	pc.set_meta("base", base)
	pc.accept = _seat_accept.bind(p)
	pc.on_drop = _seat_drop.bind(p)
	pc.tap = player_sheet.bind(p)
	var vb := _vbox(0)
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	pc.add_child(vb)
	# the portrait, with the hand count on a card back at its corner and a stamp for its state
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(56, 56)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ph := _photo(p, 56)
	holder.add_child(ph)
	if p.alive:
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _sb(C_CHIP, C_CHIP_BD, 1, 3, 0))
		chip.position = Vector2(56 - 22 + 8, 56 - 28 + 8)
		chip.custom_minimum_size = Vector2(22, 28)
		var cl := _head(str(p.hand.size()), 13)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(cl)
		holder.add_child(chip)
	var glyph := _state_glyph(p)
	if glyph != "":
		var g := Glyph.new()
		g.kind = glyph
		g.size = Vector2(20, 20)
		g.position = Vector2(-7, 56 - 20 + 7)
		holder.add_child(g)
	vb.add_child(holder)
	var nm := _head(p.name.split(" ")[-1], 12, C_INK if p.alive else C_MUT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var nmc := MarginContainer.new()
	nmc.add_theme_constant_override("margin_top", 8)
	nmc.add_child(nm)
	vb.add_child(nmc)
	# their cards as a fan: the hand face down, then what the table can see - the table, and a
	# destroyed power's hand. The fan overlaps to fit the seat.
	var fan := Spread.new()
	fan.cw = ICON_W
	fan.ch = ICON_W * CARD_R
	fan.max_sliver = ICON_W + 2
	for c in p.hand:
		if not c.pub:
			fan.add_child(_back(ICON_W))
	for c in p.table:
		fan.add_child(_card(c.key, ICON_W, not p.alive))
	for c in p.hand:
		if c.pub:
			fan.add_child(_card(c.key, ICON_W, not p.alive))
	var n := fan.get_child_count()
	if n > 0:
		var avail := w - 12
		fan.custom_minimum_size = Vector2(minf(avail, n * (ICON_W + 2) - 2), fan.ch)
		fan.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var flc := MarginContainer.new()
		flc.add_theme_constant_override("margin_top", 6)
		flc.add_child(fan)
		vb.add_child(flc)
	_ignore(pc)
	pc.clip_contents = true
	seats[p.id] = pc
	targets.append({"node": pc, "accept": pc.accept})
	return pc

func _state_glyph(p: NPGame.Player) -> String:
	if not p.alive:
		return ""
	var pr := G.prompt
	if str(pr.get("type", "")) == "trade" and ((pr.from == p and pr.player == ME) or (pr.from == ME and pr.player == p)):
		return "offer"
	for d in G.debts:
		if int(d.to) == p.id and int(d.from) == ME.id:
			return "pledge"
	if G.is_disarmed(p):
		return "disarmed"
	return ""

## Band two: the draw pile (tap it to research), the cards set aside, and the folded paper.
func _band_table(h: float) -> Control:
	var mc := MarginContainer.new()
	mc.custom_minimum_size.y = h
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 16)
	var row := _hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(row)
	var pile := Target.new()
	var pile_sb := _sb(C_CHIP, C_LINE, 1, 6, 0)
	pile.add_theme_stylebox_override("panel", _glow_sb(pile_sb) if _can_research() else pile_sb)
	pile.custom_minimum_size = Vector2(PILE_W, PILE_W * CARD_R)
	pile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pile.tap = func():
		if _can_research():
			M._act_research()
	var pile_in := Control.new()
	pile_in.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pile.add_child(pile_in)
	var bk := _back(PILE_W - 2)
	bk.position = Vector2(1, 1)
	bk.size = Vector2(PILE_W - 2, (PILE_W - 2) * CARD_R)
	pile_in.add_child(bk)
	pile_in.add_child(_count_chip(str(G.deck.size()), 15, Vector2(PILE_W - 5, PILE_W * CARD_R - 5)))
	row.add_child(pile)
	if not G.out.is_empty():
		var st := Control.new()
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st.set_meta("dimmable", true)
		var k := mini(3, G.out.size())
		st.custom_minimum_size = Vector2(40 + 4 * (k - 1), 52 + 4 * (k - 1))
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in range(k):
			var b := _back(40)
			b.position = Vector2(4 * i, 4 * (k - 1 - i))
			b.size = Vector2(40, 52)
			st.add_child(b)
		st.add_child(_count_chip(str(G.out.size()), 11, Vector2(st.custom_minimum_size.x + 4, st.custom_minimum_size.y + 4)))
		row.add_child(st)
	row.add_child(_folded_paper())
	return mc

## A count on a dark chip, its bottom-right corner at `br`.
func _count_chip(text: String, fsize: int, br: Vector2) -> Control:
	var chip := PanelContainer.new()
	var s := _sb(Color("#121309e0"), C_LINE, 1, 4, 0)
	s.content_margin_left = 6
	s.content_margin_right = 6
	chip.add_theme_stylebox_override("panel", s)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _head(text, fsize)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(l)
	chip.custom_minimum_size = Vector2(22, fsize + 9)
	chip.ready.connect(func():
		chip.reset_size()
		chip.position = br - chip.size)
	return chip

## The latest line of the paper, in its ink colour.
func _headline() -> Dictionary:
	if G.log_entries.is_empty():
		return {"text": "", "color": INK}
	var e: Dictionary = G.log_entries.back()
	var col := INK
	if e.tone in ["attack", "death", "broken"]:
		col = INK_RED
	elif e.tone == "test":
		col = INK_BRASS
	return {"text": M._you(str(e.text)), "color": col}

func _folded_paper() -> Control:
	var pc := Target.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.custom_minimum_size.y = 115
	var tx := _paper_sb(10, 8)
	pc.add_theme_stylebox_override("panel", tx)
	pc.tap = paper_sheet
	var vb := _vbox(3)
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	pc.add_child(vb)
	var mast := _lbl("The Atomic Herald", 20, INK, fonts.mast)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mast.clip_text = true
	vb.add_child(mast)
	vb.add_child(_rule(INK, 2))
	var dl := _lbl("LATE EDITION · ROUND %d" % G.round_no, 10, INK, fonts.paper)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	vb.add_child(_rule(INK, 1))
	var hl := _headline()
	var hd := _lbl(str(hl.text), 14, hl.color, fonts.paperb, true)
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hd.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hd.max_lines_visible = 2
	hd.custom_minimum_size.x = 120
	var hdc := MarginContainer.new()
	hdc.add_theme_constant_override("margin_top", 3)
	hdc.add_child(hd)
	vb.add_child(hdc)
	pc.clip_contents = true
	_ignore(pc)
	return pc

## Band three: you. The menu button, your table and trade area while they hold a card, the one
## button of the moment, and the hand along the bottom.
func _band_me() -> Control:
	var root := Control.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var menu := Button.new()
	menu.focus_mode = Control.FOCUS_NONE
	menu.custom_minimum_size = Vector2(44, 44)
	for st in ["normal", "hover", "pressed"]:
		menu.add_theme_stylebox_override(st, _sb(C_PANEL2 if st != "pressed" else C_PANEL2.lightened(0.1), C_LINE, 1, 8, 0))
	menu.pressed.connect(menu_sheet)
	var dots := Control.new()
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dots.draw.connect(func():
		for k in range(3):
			dots.draw_circle(Vector2(11 + k * 11, 22), 2.5, C_INK))
	menu.add_child(dots)
	menu.position = Vector2(get_viewport_rect().size.x - 16 - 44, 8)
	menu.set_meta("dimmable", true)
	root.add_child(menu)
	var col := _vbox(12)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	col.anchor_top = 0.0
	col.offset_left = 16
	col.offset_right = -16
	col.offset_top = 8
	col.offset_bottom = -bot_pad
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(col)
	var tr := _table_row()
	if tr != null:
		col.add_child(tr)
	var tz := _trade_area()
	if tz != null:
		col.add_child(tz)
	var pill := _moment_button()
	if pill != null:
		var pr := _hbox(0)
		pr.alignment = BoxContainer.ALIGNMENT_CENTER
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pr.set_meta("dimmable", true)
		pr.add_child(pill)
		col.add_child(pr)
	col.add_child(_hand())
	return root

## Your table: the Technologies after your test, the Capabilities once you are a Superpower.
## Before the test it appears only when you can test - glowing: drop a Technology on it.
func _table_row() -> Control:
	var can_test := _can_test()
	if ME.table.is_empty() and not can_test:
		return null
	var pc := Target.new()
	var base := _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 0)
	base.content_margin_left = 4
	base.content_margin_right = 4
	base.content_margin_top = 4
	base.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", _glow_sb(_sb(C_PANEL, C_LINE, 1, 6, 4)) if can_test else base)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pc.accept = func(d):
		var c := _my_card(int(d.cid))
		return can_test and not c.is_empty() and NPGame.INFO[c.key].kind == "tech"
	pc.on_drop = func(_d): M._act_test()
	pc.tap = func():
		if _can_test():
			test_sheet()
	var row := _hbox(4)
	pc.add_child(row)
	var w := TABLE_W if ME.table.size() <= 6 else 40.0
	for c in ME.table:
		if c.key == "super" and _any_strike() and G.is_superpower(ME):
			var td := TableDrag.new()
			td.custom_minimum_size = Vector2(w, w * CARD_R)
			td.data = {"cid": c.id}
			td.preview = _drag_preview.bind(c.key)
			var t := _card(c.key, w)
			td.add_child(t)
			var ring := PanelContainer.new()
			ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ring.add_theme_stylebox_override("panel", _glow_sb(_sb(Color(0, 0, 0, 0), C_AMBER, 2, 3, 0)))
			td.add_child(ring)
			row.add_child(td)
		else:
			row.add_child(_card(c.key, w, not ME.alive))
	if ME.table.is_empty():
		for i in range(4):
			var ph := PanelContainer.new()
			ph.custom_minimum_size = Vector2(w, w * CARD_R)
			ph.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), Color("#6a6440"), 1, 3, 0))
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(ph)
	targets.append({"node": pc, "accept": pc.accept})
	return pc

## Your trade area: an offer made to you (glowing: drop a card on it to answer, tap it to look and
## decline), a card owed to you, and your own pledge or open offer. Only while there is one.
func _trade_area() -> Control:
	var items: Array = []
	for it in M._trade_items_for(ME):
		if not it.mine:
			items.append(it)
	for c in ME.trade:
		var other: NPGame.Player = null
		var pr := G.prompt
		if str(pr.get("type", "")) == "trade" and int(pr.card_id) == int(c.id):
			other = pr.player
		for d in G.debts:
			if int(d.pledge) == int(c.id):
				other = G.players[d.from]
		items.append({"c": c, "mine": true, "seen": true, "other": other, "label": "pledge"})
	if items.is_empty():
		return null
	var pc := Target.new()
	var answering := _answering()
	var base := _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 0)
	pc.add_theme_stylebox_override("panel", base)
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pc.accept = func(d): return _answering() and ME.hand.any(func(x): return x.id == int(d.cid))
	pc.on_drop = func(d): M._answer_trade(int(d.cid))
	var row := _hbox(10)
	pc.add_child(row)
	for it in items:
		var c: Dictionary = it.c
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(HAND_W, HAND_W * CARD_R)
		var frame := PanelContainer.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var fsb := _sb(C_CHIP, C_LINE, 1, 6, 0)
		var is_offer: bool = not it.mine and answering and str(G.prompt.get("type", "")) == "trade" and int(G.prompt.card_id) == int(c.id)
		frame.add_theme_stylebox_override("panel", _glow_sb(fsb) if is_offer else fsb)
		cell.add_child(frame)
		var face: Control
		if it.get("seen", false) or it.mine:
			face = _tap_card(c.key, HAND_W - 2, zoom_sheet.bind(c, "offer" if is_offer else ("mine" if it.mine else "")))
			if it.mine:
				face.modulate.a = 0.8
		else:
			face = _back(HAND_W - 2)
		face.position = Vector2(1, 1)
		cell.add_child(face)
		var other: NPGame.Player = it.get("other", null)
		if not it.mine:
			for q in G.players:
				if q.trade.has(c):
					other = q
		if other != null:
			var badge := _photo(other, 24, 12)
			badge.add_theme_stylebox_override("panel", _sb(Color("#1e2016"), C_CHIP_BD, 1, 12, 0))
			badge.position = Vector2(-6, -6)
			cell.add_child(badge)
		row.add_child(cell)
	_ignore(pc)      # the frames and badges must not swallow the drop
	targets.append({"node": pc, "accept": pc.accept})
	return pc

## The one button of the moment, above the hand: Stand down in the exchange window; Deliver when a
## pledge is due; Skip when the pile is empty and you have nothing to trade; Skip to the end once
## you are out. Nothing else announces the moment.
func _moment_button() -> Control:
	if G.over:
		var b0 := _pbtn("Show results", "primary", true)
		b0.pressed.connect(end_page)
		return b0
	if not ME.alive:
		var b1 := _pbtn("Skip to the end", "quiet", true)
		b1.pressed.connect(func():
			M.ff = true
			M._pump())
		return b1
	if not G.prompt.is_empty():
		return null
	if _war_me():
		var sd := _pbtn("Stand down", "green", true)
		sd.pressed.connect(func():
			G.war_declare(ME, {"kind": "pass"})
			M._after_human())
		return sd
	if G.phase == "honour" and G.cur() == ME and not G._debts_of(ME).is_empty():
		var dv := _pbtn("A card is due", "primary", true)
		dv.pressed.connect(honour_sheet)
		return dv
	if _my_turn() and G.deck.is_empty():
		var sk := _pbtn("Skip turn", "quiet", true)
		sk.pressed.connect(func():
			G.play_skip(ME)
			M._after_human())
		return sk
	return null

func _hand() -> Control:
	var hv := Spread.new()
	hv.custom_minimum_size = Vector2(0, HAND_W * CARD_R)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_view = hv
	var hand: Array = ME.hand.duplicate()
	hand.sort_custom(func(a, b):
		var ia := ORDER.find(a.key)
		var ib := ORDER.find(b.key)
		return ia < ib if ia != ib else a.id < b.id)
	var can_drag := ME.alive and not G.over and (_can_offer() or _answering() or _any_strike() or _can_test())
	for c in hand:
		var hc = MainS.HandCard.new()
		hc.cid = c.id
		hc.fresh = M.fresh.has(c.id)
		hc.custom_minimum_size = Vector2(HAND_W, HAND_W * CARD_R)
		var face := Control.new()
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hc.add_child(face)
		hc.face = face
		var t := _card(c.key, HAND_W, not ME.alive)
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.add_child(t)
		var sh := PanelContainer.new()      # the card's resting shadow, under the picture
		sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ssb := _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 5, 0)
		ssb.shadow_size = 8
		ssb.shadow_color = Color(0, 0, 0, 0.5)
		ssb.shadow_offset = Vector2(-3, 0)
		sh.add_theme_stylebox_override("panel", ssb)
		face.add_child(sh)
		face.move_child(sh, 0)
		hc.can_drag = can_drag
		hc.tex = M.TEX[c.key]
		hc.preview = _drag_preview.bind(c.key)
		hc.picked.connect(func(cid, _node): zoom_sheet(_my_card(cid), "hand"))
		hv.add_child(hc)
	hv.layout.call_deferred()
	return hv

## The lifted card: a copy at 1.15 with a deep shadow, held where it was grabbed.
func _drag_preview(key: String) -> Control:
	var holder := Control.new()
	var w := HAND_W * 1.15
	var t := _card(key, w)
	t.size = Vector2(w, w * CARD_R)
	t.position = -t.size / 2.0
	var sh := PanelContainer.new()
	sh.position = t.position
	sh.size = t.size
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ssb := _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 0)
	ssb.shadow_size = 28
	ssb.shadow_color = Color(0, 0, 0, 0.6)
	ssb.shadow_offset = Vector2(0, 14)
	sh.add_theme_stylebox_override("panel", ssb)
	holder.add_child(sh)
	holder.add_child(t)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return holder

# ---- while a card is in the air: every legal target glows, everything else dims
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN and visible and board_view != null:
		var d = get_viewport().gui_get_drag_data()
		if not (d is Dictionary and d.has("cid")):
			return
		var lit: Array = []
		for t in targets:
			var node: Control = t.node
			if not is_instance_valid(node):
				continue
			if t.accept.is_valid() and t.accept.call(d):
				var base: StyleBox = node.get_theme_stylebox("panel")
				node.set_meta("rest", base)
				node.add_theme_stylebox_override("panel", _glow_sb(base if base is StyleBoxFlat else _sb(C_PANEL, C_LINE, 1, 8, 0)))
				lit.append(node)
		_dim_except(lit)
	elif what == NOTIFICATION_DRAG_END and board_view != null:
		for t in targets:
			var node: Control = t.node
			if is_instance_valid(node) and node.has_meta("rest"):
				node.add_theme_stylebox_override("panel", node.get_meta("rest"))
				node.remove_meta("rest")
		_undim()

## Dim everything on the board but `keep`: every panel, the rest of the hand (the card in the air
## is a copy of one that is hidden), the buttons. 40%, the same as behind a sheet.
func _dim_except(keep: Array) -> void:
	_undim()
	for n in board_view.find_children("*", "Control", true, false):
		var c := n as Control
		if keep.has(c):
			continue
		var top: bool = c is Target or c.get_parent() == hand_view or c.has_meta("dimmable")
		if not top or _inside_panel(c):
			continue
		if "dragging" in c and c.dragging:
			continue      # the card being dragged stays hidden
		c.modulate = Color(1, 1, 1, 0.4)
		dimmed.append(c)

## Inside a panel or a hand card that dims as a whole (so it must not dim twice).
func _inside_panel(c: Control) -> bool:
	var p := c.get_parent()
	while p != null and p != board_view:
		if p is Target or p.get_parent() == hand_view:
			return true
		p = p.get_parent()
	return false

func _undim() -> void:
	for c in dimmed:
		if is_instance_valid(c):
			c.modulate = Color(1, 1, 1, 1)
	dimmed.clear()

# ====================================================================== sheets
## A bottom sheet: full width to 480, centred above that; a handle, a title, its body. One frame
## for every confirmation and detail view. `sticky`: a decision the game is waiting for - the scrim
## does not close it.
func sheet_open(title: String, sub := "", sticky := false, paper := false) -> VBoxContainer:
	close_sheet()
	sheet_sticky = sticky
	var vp := get_viewport_rect().size
	sheet = Control.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scrim := ColorRect.new()
	scrim.color = Color(C_BG, 0.6)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not sheet_sticky:
			close_sheet())
	sheet.add_child(scrim)
	var slide := Control.new()
	slide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(slide)
	var pn := PanelContainer.new()
	var w := minf(vp.x, 480.0)
	pn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pn.offset_left = (vp.x - w) / 2.0
	pn.offset_right = -(vp.x - w) / 2.0
	pn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if paper:
		pn.add_theme_stylebox_override("panel", _paper_sb(16, 12))
	else:
		var s := _sb(C_PANEL, C_LINE, 0, 16, 0)
		s.border_width_top = 1
		s.corner_radius_bottom_left = 0
		s.corner_radius_bottom_right = 0
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 8
		s.content_margin_bottom = bot_pad + 34
		s.shadow_size = 24
		s.shadow_color = Color(0, 0, 0, 0.5)
		s.shadow_offset = Vector2(0, -8)
		pn.add_theme_stylebox_override("panel", s)
	slide.add_child(pn)
	var col := _vbox(0)
	pn.add_child(col)
	var handle := ColorRect.new()
	handle.color = Color(INK, 0.35) if paper else C_LINE
	handle.custom_minimum_size = Vector2(36, 4)
	handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(handle)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_top", 14)
	col.add_child(hm)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hm.add_child(sc)
	var body := _vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	if title != "":
		var tv := _vbox(2)
		tv.add_child(_head(title, 22, INK if paper else C_INK))
		if sub != "":
			tv.add_child(_small(sub, INK_SUB if paper else C_MUT))
		var tm := MarginContainer.new()
		tm.add_theme_constant_override("margin_bottom", 8)
		tm.add_child(tv)
		body.add_child(tm)
	M.modal_root.add_child(sheet)
	slide.position.y = 60.0
	slide.modulate.a = 0.0
	var tw := slide.create_tween().set_parallel(true)
	tw.tween_property(slide, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(slide, "modulate:a", 1.0, 0.15)
	_fit_sheet(sc, body)
	_dim_board(true)
	return body

func _fit_sheet(sc: ScrollContainer, body: VBoxContainer) -> void:
	for i in range(3):
		await get_tree().process_frame
		if sc == null or not is_instance_valid(sc) or not is_instance_valid(body):
			return
		var h := body.get_combined_minimum_size().y
		sc.custom_minimum_size.y = minf(h, get_viewport_rect().size.y * 0.78 - 60.0)

func close_sheet() -> void:
	if sheet != null and is_instance_valid(sheet):
		sheet.queue_free()
	sheet = null
	sheet_sticky = false
	_dim_board(false)

func _dim_board(on: bool) -> void:
	if board_view != null and is_instance_valid(board_view):
		board_view.modulate = Color(1, 1, 1, 0.4 if on else 1.0)

func _sheet_buttons(body: VBoxContainer) -> VBoxContainer:
	var bb := _vbox(8)
	bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(bb)
	return bb

## The card at zoom size with its name and what it does. From the hand, or from an offer made to
## you (with Decline), or your own card in a trade.
func zoom_sheet(c: Dictionary, where := "") -> void:
	if c.is_empty():
		return
	var info: Dictionary = NPGame.INFO[c.key]
	var body := sheet_open("", "")
	var pic := _card(c.key, ZOOM_W, not ME.alive)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sh := PanelContainer.new()
	sh.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ssb := _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10, 0)
	ssb.shadow_size = 32
	ssb.shadow_color = Color(0, 0, 0, 0.6)
	ssb.shadow_offset = Vector2(0, 12)
	sh.add_theme_stylebox_override("panel", ssb)
	sh.add_child(pic)
	body.add_child(sh)
	var nm := _head(info.name, 22)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nmc := MarginContainer.new()
	nmc.add_theme_constant_override("margin_top", 12)
	nmc.add_child(nm)
	body.add_child(nmc)
	var desc := _lbl(str(M.CARD_DESC[c.key]), 15, C_INK, fonts.body, true)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(desc)
	var hint := ""
	if where == "offer":
		var pr := G.prompt
		hint = "%s offers you this card. Drop one of yours on it to answer - the deal is done at once, and you deliver yours on your next turn. Or decline." % pr.from.name
	elif where == "mine":
		var pr2 := G.prompt
		if str(pr2.get("type", "")) == "trade" and int(pr2.card_id) == int(c.id):
			hint = "Your offer to %s. Only they can see it." % pr2.player.name
		else:
			hint = "Pledged in a trade: you deliver it on your next turn - or break the deal."
	elif where == "hand":
		var can: Array = []
		if _can_offer():
			can.append("drop it on a power to offer it in a trade")
		if _answering():
			can.append("drop it on the offer to answer")
		var w := _weapon_of(c)
		if w != "" and _any_strike():
			can.append("drop it on a power to strike")
		if _can_test() and info.kind == "tech":
			can.append("drop it on your table to test")
		if not can.is_empty():
			hint = "; ".join(can) + "."
			hint = hint[0].to_upper() + hint.substr(1)
	if hint != "":
		var hl := _lbl(hint, 13, C_MUT, fonts.body, true)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var hc := MarginContainer.new()
		hc.add_theme_constant_override("margin_top", 8)
		hc.add_child(hl)
		body.add_child(hc)
	if where == "offer":
		var bb := _sheet_buttons(body)
		var no := _pbtn("Decline the offer", "quiet")
		no.pressed.connect(func():
			close_sheet()
			M._answer_trade(-1))
		bb.add_child(no)

## A weapon dropped on a power: strike, or - in the exchange window - threaten instead.
func strike_sheet(p: NPGame.Player, c: Dictionary, w: String) -> void:
	var body := sheet_open(p.name, _player_sub(p))
	var row := _hbox(12)
	row.add_child(_card(c.key, TABLE_W))
	var txt: String = {"short": "A Short-range strike on your neighbour. The card burns with them.",
		"long": "A Long-range strike. The card burns with them.",
		"super": "A Superpower strike. It costs you nothing, and you may strike again."}[w]
	row.add_child(_lbl(txt, 13, C_MUT, fonts.body, true))
	body.add_child(row)
	var bb := _sheet_buttons(body)
	var sb := _pbtn("Strike with %s" % NPGame.INFO[w].name, "danger")
	sb.pressed.connect(func():
		close_sheet()
		M._declare({"kind": "attack", "type": w, "target": p.id}))
	bb.add_child(sb)
	if _war_me() and G.can_threaten(ME) and G.threat_targets(ME).has(p.id):
		if not ME.hand.is_empty() and not p.hand.is_empty():
			var tt := _pbtn("Threaten: trade with me", "caution")
			tt.pressed.connect(func(): pick_card_sheet(p))
			bb.add_child(tt)
		var td := _pbtn("Threaten: disarm", "caution")
		td.pressed.connect(func():
			close_sheet()
			G.war_declare(ME, {"kind": "threat", "target": p.id})
			M._after_human())
		bb.add_child(td)
	if _can_offer() and ME.hand.has(c):
		var of := _pbtn("Offer it in a trade instead", "neutral")
		of.pressed.connect(func():
			close_sheet()
			M._drop_offer(p, {"cid": c.id}))
		bb.add_child(of)
	var cancel := _pbtn("Cancel", "quiet")
	cancel.pressed.connect(close_sheet)
	bb.add_child(cancel)

## A forced trade: the card you put up. They give one back of their choice, or refuse.
func pick_card_sheet(p: NPGame.Player) -> void:
	var body := sheet_open("Force a trade", "Which card do you put up?")
	body.add_child(_lbl("%s sees it, then gives you a card of their choice in return - or refuses, and you keep it." % p.name, 13, C_MUT, fonts.body, true))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 8)
	fl.add_theme_constant_override("v_separation", 8)
	var hand: Array = ME.hand.duplicate()
	hand.sort_custom(func(a, b): return ORDER.find(a.key) < ORDER.find(b.key))
	for c in hand:
		var cid: int = c.id
		fl.add_child(_tap_card(c.key, 80, func():
			close_sheet()
			G.war_declare(ME, {"kind": "demand", "target": p.id, "offer": cid})
			M._after_human()))
	body.add_child(fl)
	var bb := _sheet_buttons(body)
	var cancel := _pbtn("Cancel", "quiet")
	cancel.pressed.connect(close_sheet)
	bb.add_child(cancel)

func test_sheet() -> void:
	var body := sheet_open("Nuclear Test", "Once per game")
	body.add_child(_lbl("Your four Technologies go on the table for all to see. From now on you can strike - and be a target of threats. Everyone declares again after a test.", 13, C_MUT, fonts.body, true))
	var bb := _sheet_buttons(body)
	var y := _pbtn("Conduct the test", "primary")
	y.pressed.connect(func():
		close_sheet()
		M._act_test())
	bb.add_child(y)
	var n := _pbtn("Not yet", "quiet")
	n.pressed.connect(close_sheet)
	bb.add_child(n)

func _player_sub(p: NPGame.Player) -> String:
	if not p.alive:
		return "Eliminated" + ((" by " + G.players[p.eliminated_by].name) if p.eliminated_by >= 0 else "")
	var bits := ["%d card%s in hand" % [p.hand.size(), "" if p.hand.size() == 1 else "s"]]
	if G.is_superpower(p):
		bits.append("Superpower")
	elif p.tested:
		bits.append("tested")
	if G.is_disarmed(p):
		bits.append("disarmed")
	return " · ".join(bits)

## Tap a seat: who they are, what the table can see of their cards, whether they can reach you,
## and your history with them.
func player_sheet(p: NPGame.Player) -> void:
	var body := sheet_open("", "")
	var hd := _hbox(12)
	hd.add_child(_photo(p, 64))
	var tv := _vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(_head(p.name, 22))
	tv.add_child(_small(_player_sub(p)))
	hd.add_child(tv)
	body.add_child(hd)
	# their hand, face down: something to look at, and a sense of how much they hold
	var hidden := 0
	for c in p.hand:
		if not c.pub:
			hidden += 1
	if hidden > 0:
		var fan := Spread.new()
		fan.cw = 80.0
		fan.ch = 80.0 * CARD_R
		fan.max_sliver = 88.0
		fan.custom_minimum_size = Vector2(0, fan.ch)
		fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in range(hidden):
			fan.add_child(_back(80.0))
		var fc := MarginContainer.new()
		fc.add_theme_constant_override("margin_top", 8)
		fc.add_child(fan)
		body.add_child(fc)
	var shown: Array = []
	for c in p.table:
		shown.append(c)
	for c in p.hand:
		if c.pub:
			shown.append(c)
	if not shown.is_empty():
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 8)
		fl.add_theme_constant_override("v_separation", 8)
		for c in shown:
			var cc: Dictionary = c
			fl.add_child(_tap_card(c.key, 80, zoom_sheet.bind(cc, ""), not p.alive))
		var flc := MarginContainer.new()
		flc.add_theme_constant_override("margin_top", 8)
		flc.add_child(fl)
		body.add_child(flc)
	var lines := _vbox(6)
	if p.alive and _reaches_me(p):
		var rl := _hbox(8)
		var tgt := Control.new()
		tgt.custom_minimum_size = Vector2(14, 14)
		tgt.draw.connect(func():
			tgt.draw_arc(Vector2(7, 7), 5, 0, TAU, 24, C_AMBER, 1.5, true)
			tgt.draw_circle(Vector2(7, 7), 1.5, C_AMBER)
			for v in [[Vector2(7, 0.5), Vector2(7, 3)], [Vector2(7, 11), Vector2(7, 13.5)], [Vector2(0.5, 7), Vector2(3, 7)], [Vector2(11, 7), Vector2(13.5, 7)]]:
				tgt.draw_line(v[0], v[1], C_AMBER, 1.5, true))
		rl.add_child(tgt)
		rl.add_child(_small("Can reach you", C_AMBER, 12))
		lines.add_child(rl)
	var nb := int(M.betrayals.get(p.id, 0))
	if nb > 0:
		lines.add_child(_mark_line(C_RED, "Broke %s with you" % ("a deal" if nb == 1 else "%d deals" % nb)))
	for d in G.debts:
		if int(d.to) == p.id and int(d.from) == ME.id:
			lines.add_child(_mark_line(C_AMBER, "Owes you a card, due on their next turn"))
		elif int(d.from) == p.id and int(d.to) == ME.id:
			lines.add_child(_mark_line(C_AMBER, "You owe them a card, due on your next turn"))
	var pr := G.prompt
	if str(pr.get("type", "")) == "trade" and pr.from == ME and pr.player == p:
		lines.add_child(_mark_line(C_AMBER, "Your offer is on their table"))
	if lines.get_child_count() > 0:
		var lc := MarginContainer.new()
		lc.add_theme_constant_override("margin_top", 10)
		lc.add_child(lines)
		body.add_child(lc)
	if p.alive and _strike_ok("super", p):
		var bb := _sheet_buttons(body)
		var sb := _pbtn("Superpower strike", "danger")
		sb.pressed.connect(func():
			close_sheet()
			M._declare({"kind": "attack", "type": "super", "target": p.id}))
		bb.add_child(sb)

func _mark_line(c: Color, text: String) -> Control:
	var hb := _hbox(10)
	var sq := ColorRect.new()
	sq.color = c
	sq.custom_minimum_size = Vector2(10, 10)
	sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(sq)
	hb.add_child(_lbl(text, 15, C_INK, fonts.body, true))
	return hb

## The paper, unfolded: the whole story so far, and the map at its foot.
func paper_sheet() -> void:
	var body := sheet_open("", "", false, true)
	var mast := _lbl("The Atomic Herald", 30, INK, fonts.mast)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(mast)
	body.add_child(_rule(INK, 2))
	var dl := _hbox(0)
	for t in ["LATE EDITION", "ROUND %d" % G.round_no, "ONE CENT"]:
		var l := _lbl(t, 11, INK, fonts.paper)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][dl.get_child_count()]
		dl.add_child(l)
	body.add_child(dl)
	body.add_child(_rule(INK, 1))
	var r2 := _rule(INK, 1)
	var r2c := MarginContainer.new()
	r2c.add_theme_constant_override("margin_top", 2)
	r2c.add_theme_constant_override("margin_bottom", 6)
	r2c.add_child(r2)
	body.add_child(r2c)
	var log := RichTextLabel.new()
	log.bbcode_enabled = true
	log.fit_content = true
	log.scroll_active = false
	log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log.add_theme_font_override("normal_font", fonts.paper)
	log.add_theme_font_override("bold_font", fonts.paperb)
	log.add_theme_font_override("italics_font", fonts.paperi)
	log.add_theme_font_size_override("normal_font_size", 15)
	log.add_theme_font_size_override("bold_font_size", 15)
	log.add_theme_font_size_override("italics_font_size", 15)
	log.add_theme_constant_override("paragraph_separation", 7)
	log.add_theme_color_override("default_color", INK)
	log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tones := {"attack": INK_RED.to_html(false), "death": INK_RED.to_html(false), "broken": INK_RED.to_html(false),
		"test": INK_BRASS.to_html(false), "reveal": "#5a3d1e", "quiet": "#7d7357", "sys": "#5a523f"}
	var text := ""
	for e in G.log_entries:
		var txt: String = M._you(str(e.text)).replace("[", "(")
		if e.tone in ["attack", "death", "test", "broken"]:
			txt = "[b]%s[/b]" % txt
		text += "[color=%s]%s[/color]\n" % [tones.get(e.tone, INK.to_html(false)), txt]
	log.text = text
	body.add_child(log)
	var tm = MainS.TableMap.new()
	tm.font = fonts.mono
	tm.custom_minimum_size = Vector2(0, 190)
	tm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var al := G.alive_list()
	for p in G.players:
		tm.seats.append({"name": M._short_name(p), "alive": p.alive, "tested": p.tested, "turn": G.turn == p.id and not G.over,
			"you": p == ME, "color": C_GREEN if p == ME else M._persona_color(p)})
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
	var mapc := MarginContainer.new()
	mapc.add_theme_constant_override("margin_top", 12)
	mapc.add_child(tm)
	body.add_child(mapc)
	# open on the latest news
	await get_tree().process_frame
	await get_tree().process_frame
	if sheet != null and is_instance_valid(body):
		var sc: ScrollContainer = body.get_parent()
		sc.scroll_vertical = int(log.get_global_rect().end.y - sc.get_global_rect().position.y)

## The ... menu: the rest of what you can do, none of it urgent.
func menu_sheet() -> void:
	var body := sheet_open("", "")
	var bb := _sheet_buttons(body)
	var cf := _pbtn("Propose stand-down", "green")
	cf.disabled = G.over or not ME.alive or not G.can_propose_ceasefire(ME)
	cf.pressed.connect(func():
		close_sheet()
		M._act_ceasefire())
	bb.add_child(cf)
	if G.can_disarm(ME):
		var db := _pbtn("Disarm", "neutral")
		db.pressed.connect(func():
			close_sheet()
			disarm_sheet())
		bb.add_child(db)
	var how := _pbtn("How to play", "neutral")
	how.pressed.connect(func():
		close_sheet()
		M._rules_modal())
	bb.add_child(how)
	var so := _pbtn("Sound   %s" % ("OFF" if M.muted else "ON"), "neutral")
	so.pressed.connect(func():
		M.muted = not M.muted
		M._save_cfg()
		M._ambience(G != null and not G.over)
		M._music_update()
		so.text = "Sound   %s" % ("OFF" if M.muted else "ON"))
	bb.add_child(so)
	var mn := _pbtn("Menu", "neutral")
	mn.pressed.connect(func():
		close_sheet()
		if G.over:
			M._to_menu()
		else:
			abandon_sheet())
	bb.add_child(mn)

func abandon_sheet() -> void:
	var body := sheet_open("Abandon this game?", "You will return to the menu")
	var bb := _sheet_buttons(body)
	var y := _pbtn("Abandon", "danger")
	y.pressed.connect(func():
		close_sheet()
		M._to_menu())
	bb.add_child(y)
	var n := _pbtn("Keep playing", "quiet")
	n.pressed.connect(close_sheet)
	bb.add_child(n)

func disarm_sheet() -> void:
	var held: Array = G.caps_held(ME)
	var body := sheet_open("Disarm?", "At any time, once you have tested")
	body.add_child(_lbl("Return all your Capability cards (%s) to the deck. Your Technologies stay on the table. You cannot strike or retaliate until you collect Capabilities again." % ", ".join(held.map(func(c): return NPGame.INFO[c.key].name)), 13, C_MUT, fonts.body, true))
	var bb := _sheet_buttons(body)
	var y := _pbtn("Disarm", "danger")
	y.pressed.connect(func():
		close_sheet()
		if not G.disarm_caps(ME):
			M._toast("Answer the decision in front of you first.")
		M._after_human())
	bb.add_child(y)
	var n := _pbtn("Keep my weapons", "quiet")
	n.pressed.connect(close_sheet)
	bb.add_child(n)

## A pledge of yours is due: deliver it, or break the deal.
func honour_sheet() -> void:
	if G.phase != "honour" or G.cur() != ME or G._debts_of(ME).is_empty():
		return
	var dd: Dictionary = G._debts_of(ME)[0]
	var cr: NPGame.Player = G.players[dd.from]
	var pl = G._trade_card(ME, int(dd.pledge))
	var body := sheet_open("A card is due", "Your pledge to %s" % cr.name)
	var row := _hbox(12)
	if pl != null:
		row.add_child(_card(pl.key, TABLE_W))
	row.add_child(_lbl("%s has already given you theirs. Deliver yours as promised - or keep it, and they will remember." % cr.name, 13, C_MUT, fonts.body, true))
	body.add_child(row)
	var bb := _sheet_buttons(body)
	var dv := _pbtn("Deliver %s" % (NPGame.INFO[pl.key].name if pl != null else "the card"), "primary")
	dv.pressed.connect(func():
		close_sheet()
		G.honour(ME)
		M._after_human())
	bb.add_child(dv)
	var rb := _pbtn("Break the deal", "danger")
	rb.pressed.connect(func():
		close_sheet()
		G.renege(ME)
		M._after_human())
	bb.add_child(rb)
	var n := _pbtn("Not yet", "quiet")
	n.pressed.connect(close_sheet)
	bb.add_child(n)

# ---- decisions the game waits for
func _reach_text(from: NPGame.Player) -> String:
	var reach := []
	for av in G.attack_types(from):
		if av.targets.has(ME.id):
			reach.append({"short": "Short range", "long": "Long range", "super": "Superpower"}[av.type])
	return "" if reach.is_empty() else " They can strike you (%s)." % ", ".join(reach)

func threat_sheet() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human:
		return
	var held: Array = G.caps_held(ME)
	var body := sheet_open("You are threatened", "By %s" % pr.from.name, true)
	var txt := "%s demands that you return all your Capability cards to the deck - or else.%s" % [pr.from.name, _reach_text(pr.from)]
	if held.is_empty():
		txt += " You hold no Capability cards: nothing to give up."
	else:
		txt += " You hold %s. Refuse, and nothing happens by itself - but they may attack." % ", ".join(held.map(func(c): return NPGame.INFO[c.key].name))
	body.add_child(_lbl(txt, 15, C_INK, fonts.body, true))
	var bb := _sheet_buttons(body)
	var y := _pbtn("Give in: disarm", "danger")
	y.disabled = held.is_empty()
	y.pressed.connect(func():
		close_sheet()
		G.answer_threat(true)
		M._after_human())
	bb.add_child(y)
	var n := _pbtn("Refuse", "primary")
	n.pressed.connect(func():
		close_sheet()
		G.answer_threat(false)
		M._after_human())
	bb.add_child(n)

func demand_sheet() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human:
		return
	var offered: Dictionary = {}
	for c in pr.from.hand:
		if c.id == int(pr.offer):
			offered = c
	var body := sheet_open("You are threatened", "By %s: trade, or else" % pr.from.name, true)
	var row := _hbox(12)
	if not offered.is_empty():
		row.add_child(_card(offered.key, TABLE_W))
	row.add_child(_lbl("Take their %s and give them a card of your choice - tap one below. Only the two of you will know what changed hands.%s Refuse, and you both keep your cards." % [NPGame.INFO[offered.key].name, _reach_text(pr.from)], 13, C_INK, fonts.body, true))
	body.add_child(row)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 8)
	fl.add_theme_constant_override("v_separation", 8)
	var hand: Array = ME.hand.duplicate()
	hand.sort_custom(func(a, b): return ORDER.find(a.key) < ORDER.find(b.key))
	for c in hand:
		var cid: int = c.id
		fl.add_child(_tap_card(c.key, 80, func():
			close_sheet()
			G.answer_demand(cid)
			M._after_human()))
	var flc := MarginContainer.new()
	flc.add_theme_constant_override("margin_top", 8)
	flc.add_child(fl)
	body.add_child(flc)
	var bb := _sheet_buttons(body)
	var n := _pbtn("Refuse", "primary")
	n.pressed.connect(func():
		close_sheet()
		G.answer_demand(-1)
		M._after_human())
	bb.add_child(n)

func ceasefire_sheet() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human:
		return
	var body := sheet_open("Stand-down proposed", "By %s" % pr.from.name, true)
	var names: Array = G.others(ME).filter(func(x): return x != pr.from).map(func(x): return x.name)
	var txt := "%s proposes that everyone stops here." % pr.from.name
	if not names.is_empty():
		txt += " %s agree%s." % [" and ".join(names), "s" if names.size() == 1 else ""]
	txt += " Agree, and the game ends with everyone still at the table alive. Refuse, and it goes on."
	body.add_child(_lbl(txt, 15, C_INK, fonts.body, true))
	var bb := _sheet_buttons(body)
	var y := _pbtn("Agree: stand down", "primary")
	y.pressed.connect(func():
		close_sheet()
		G.answer_ceasefire(true)
		M._after_human())
	bb.add_child(y)
	var n := _pbtn("Refuse", "danger")
	n.pressed.connect(func():
		close_sheet()
		G.answer_ceasefire(false)
		M._after_human())
	bb.add_child(n)

func counter_sheet() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human:
		return
	var body := sheet_open("Counter-strike", "Choose who goes down with you", true)
	var by_txt := (" by %s" % pr.by.name) if pr.by != null else ""
	body.add_child(_lbl("You have been eliminated%s - but your Counter-strike fires." % by_txt, 15, C_INK, fonts.body, true))
	var bb := _sheet_buttons(body)
	for id in pr.options:
		var tid: int = id
		var b := _pbtn("Strike %s" % G.players[tid].name, "danger")
		b.pressed.connect(func():
			close_sheet()
			G.choose_counter(tid)
			M._after_human())
		bb.add_child(b)

# ====================================================================== the end
## The end: a special edition of the paper, the whole screen.
func end_page() -> void:
	close_sheet()
	var r: Dictionary = G.result
	var alive: Array = r.survivors.map(func(i): return G.players[i])
	var title := ""
	var stand := ""
	var pic := ""
	var cap := ""
	var good := false
	if r.kind == "mad":
		if M.mad_pic < 0:
			M.mad_pic = randi() % M.MAD_PICS.size()
		var m: Dictionary = M.MAD_PICS[M.mad_pic]
		title = "Balance of terror"
		stand = str(m.sub)
		pic = "res://assets/ui/mad/%s.jpg" % m.pic
		cap = str(m.cap)
		good = true
	elif r.kind == "annihilation":
		title = "Mutual annihilation"
		stand = "Nobody is left. Nobody wins."
	elif r.kind == "last":
		var w: NPGame.Player = alive[0]
		good = w == ME
		title = "You are the last one standing" if good else "%s is the last power standing" % w.name
		stand = "You survived. Look at what it cost." if good else "The rest of the table is gone."
	elif r.kind == "stalemate":
		title = "Stalemate"
		stand = "The draw pile ran dry and nobody could - or would - move again. %d of %d powers survive." % [alive.size(), G.players.size()]
		good = ME.alive
	elif r.kind == "hegemony":
		var w2: NPGame.Player = G.players[int(r.winner)]
		good = w2 == ME
		title = "You rule the world" if good else "%s rules the world" % w2.name
		stand = "The only Superpower at a table where no one else holds a Capability. Nobody can stand against %s - and nobody had to die." % ("you" if good else w2.name)
	elif alive.size() == G.players.size():
		title = "Deterrence held"
		stand = "Nobody died. That is the only winning move."
		good = true
	else:
		title = "Stand-down"
		stand = "%d of %d powers survive." % [alive.size(), G.players.size()]
	var vp := get_viewport_rect().size
	sheet = Control.new()
	sheet_sticky = true
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pn := PanelContainer.new()
	pn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var w := minf(vp.x, 480.0)
	pn.offset_left = (vp.x - w) / 2.0
	pn.offset_right = -(vp.x - w) / 2.0
	pn.add_theme_stylebox_override("panel", _paper_sb(16, 0))
	sheet.add_child(pn)
	if vp.x > w:
		var bgc := ColorRect.new()
		bgc.color = C_BG
		bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sheet.add_child(bgc)
		sheet.move_child(bgc, 0)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pn.add_child(sc)
	var body := _vbox(0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", int(top_pad) + 40)
	pad.add_theme_constant_override("margin_bottom", int(bot_pad) + 24)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pad)
	var col := _vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(col)
	var centred := func(text: String, size: int, font: Font, color := INK, wrap := true, top := 0) -> Label:
		var l := _lbl(text, size, color, font, wrap)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if top > 0:
			var mc := MarginContainer.new()
			mc.add_theme_constant_override("margin_top", top)
			mc.add_child(l)
			col.add_child(mc)
		else:
			col.add_child(l)
		return l
	centred.call("The Atomic Herald", 40, fonts.mast, INK, false)
	var rl := MarginContainer.new()
	rl.add_theme_constant_override("margin_top", 8)
	rl.add_theme_constant_override("margin_bottom", 8)
	rl.add_child(_rule(INK, 2))
	col.add_child(rl)
	var dl := _hbox(0)
	for t in ["SPECIAL EDITION", "ROUND %d" % G.round_no, "ONE CENT"]:
		var l := _lbl(t, 11, INK, fonts.paper)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][dl.get_child_count()]
		dl.add_child(l)
	col.add_child(dl)
	var r1c := MarginContainer.new()
	r1c.add_theme_constant_override("margin_top", 6)
	r1c.add_child(_rule(INK, 1))
	col.add_child(r1c)
	var r2c := MarginContainer.new()
	r2c.add_theme_constant_override("margin_top", 2)
	r2c.add_theme_constant_override("margin_bottom", 12)
	r2c.add_child(_rule(INK, 1))
	col.add_child(r2c)
	centred.call(title.to_upper(), 28, fonts.paperb)
	centred.call(stand, 14, fonts.paperi, INK, true, 8)
	if pic != "" and ResourceLoader.exists(pic):
		var tr := TextureRect.new()
		tr.texture = load(pic)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.custom_minimum_size.y = 200
		var trp := PanelContainer.new()
		trp.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), INK, 1, 0, 0))
		trp.add_child(tr)
		var trc := MarginContainer.new()
		trc.add_theme_constant_override("margin_top", 12)
		trc.add_child(trp)
		col.add_child(trc)
		centred.call(cap + " — Herald photograph", 10, fonts.paper, INK, true, 4)
	# the table at the end: who survived, who fell, and by whose hand
	var story := ""
	for p in G.players:
		var who: String = p.name + (" (you)" if p == ME and p.name != "You" else "")
		if p.alive:
			story += "%s survived%s. " % [who, (", a Superpower" if G.is_superpower(p) else (", tested" if p.tested else ""))]
		else:
			story += "%s was eliminated%s. " % [who, ((" by " + G.players[p.eliminated_by].name) if p.eliminated_by >= 0 else "")]
	var sl := _lbl(story.strip_edges(), 15, INK, fonts.paper, true)
	var slc := MarginContainer.new()
	slc.add_theme_constant_override("margin_top", 12)
	slc.add_child(sl)
	col.add_child(slc)
	centred.call("\"The only winning move is not to play.\"", 13, fonts.paperi, INK, true, 10)
	var sep := MarginContainer.new()
	sep.add_theme_constant_override("margin_top", 16)
	sep.add_theme_constant_override("margin_bottom", 16)
	sep.add_child(_rule(Color(INK, 0.35), 1))
	col.add_child(sep)
	var bb := _vbox(8)
	col.add_child(bb)
	var again := _pbtn("Play again", "primary")
	again.pressed.connect(func():
		close_sheet()
		M._start_game())
	bb.add_child(again)
	var mn := _pbtn("Menu", "neutral")
	mn.pressed.connect(func():
		close_sheet()
		M._to_menu())
	bb.add_child(mn)
	var board := _pbtn("Look at the table", "paper")
	board.pressed.connect(close_sheet)
	bb.add_child(board)
	var tr2 := _pbtn("Debug transcript", "paper")
	tr2.pressed.connect(func():
		close_sheet()
		M._transcript_modal())
	bb.add_child(tr2)
	M.modal_root.add_child(sheet)
	sheet.modulate.a = 0.0
	sheet.create_tween().tween_property(sheet, "modulate:a", 1.0, 0.3)

# ====================================================================== the menu
## The main menu on a phone: the table, the powers, the callsign, Begin.
func _build_menu() -> Control:
	var cfg: Dictionary = M.cfg
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sc := ScrollContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 16)
	mc.add_theme_constant_override("margin_top", int(top_pad) + 24)
	mc.add_theme_constant_override("margin_bottom", int(bot_pad) + 16)
	sc.add_child(mc)
	var col := _vbox(10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(col)
	var logo := _hbox(12)
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	var tre = MainS.Trefoil.new()
	tre.custom_minimum_size = Vector2(44, 44)
	logo.add_child(tre)
	logo.add_child(_head("Nuclear", 34))
	logo.add_child(_head("Poker", 34, C_AMBER))
	col.add_child(logo)
	var tag := _small("a fun, scary teaching game")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _sb(C_PANEL, C_LINE, 1, 12, 16))
	var bv := _vbox(10)
	box.add_child(bv)
	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_top", 12)
	bm.add_child(box)
	col.add_child(bm)
	bv.add_child(_small("Players at the table"))
	var players_opt := OptionButton.new()
	players_opt.focus_mode = Control.FOCUS_NONE
	players_opt.custom_minimum_size.y = 44
	for n in [3, 4, 5]:
		players_opt.add_item("%d players - you and %s powers" % [n, ["two", "three", "four"][n - 3]])
	for st in ["normal", "hover", "pressed"]:
		players_opt.add_theme_stylebox_override(st, _sb(C_PANEL2, C_LINE, 1, 8, 9))
	players_opt.select(int(cfg.players) - 3)
	bv.add_child(players_opt)
	bv.add_child(_small("Your callsign"))
	var name_edit := LineEdit.new()
	name_edit.text = str(cfg.name)
	name_edit.max_length = 18
	name_edit.custom_minimum_size.y = 44
	name_edit.add_theme_stylebox_override("normal", _sb(C_PANEL2, C_LINE, 1, 8, 9))
	name_edit.add_theme_stylebox_override("focus", _sb(C_PANEL2, C_AMBER, 1, 8, 9))
	bv.add_child(name_edit)
	var opp_btns: Array = []
	var opp_cells: Array = []
	for i in range(4):
		var cell := _vbox(3)
		cell.add_child(_small("Opponent %d" % (i + 1)))
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.clip_text = true
		ob.custom_minimum_size.y = 44
		ob.add_item("Random")
		ob.add_theme_constant_override("icon_max_width", 28)
		ob.get_popup().add_theme_constant_override("icon_max_width", 32)
		for pid in M.PERSONA_IDS.slice(1):
			var pe: Dictionary = NPGame.PERSONAS[pid]
			var hp := "res://assets/portraits/%s_head.png" % pid
			if ResourceLoader.exists(hp):
				ob.add_icon_item(load(hp), pe.name)
			else:
				ob.add_item(pe.name)
		for st in ["normal", "hover", "pressed"]:
			ob.add_theme_stylebox_override(st, _sb(C_PANEL2, C_LINE, 1, 8, 9))
		ob.select(maxi(0, M.PERSONA_IDS.find(cfg["p%d" % (i + 1)])))
		cell.add_child(ob)
		bv.add_child(cell)
		opp_btns.append(ob)
		opp_cells.append(cell)
	var refresh := func():
		var n_ai := players_opt.selected + 2
		for i in range(4):
			opp_cells[i].visible = i < n_ai
	players_opt.item_selected.connect(func(_i): refresh.call())
	refresh.call()
	var bb := _vbox(8)
	var bbm := MarginContainer.new()
	bbm.add_theme_constant_override("margin_top", 8)
	bbm.add_child(bb)
	col.add_child(bbm)
	var begin := _pbtn("Begin", "primary")
	begin.pressed.connect(func():
		cfg.name = name_edit.text.strip_edges().left(18) if name_edit.text.strip_edges() != "" else "You"
		for i in range(4):
			cfg["p%d" % (i + 1)] = M.PERSONA_IDS[opp_btns[i].selected]
		cfg.players = str(players_opt.selected + 3)
		M._save_cfg()
		M._start_game())
	bb.add_child(begin)
	var how := _pbtn("How to play", "neutral")
	how.pressed.connect(M._rules_modal)
	bb.add_child(how)
	var lic := _pbtn("Licences", "quiet")
	lic.pressed.connect(M._licences_modal)
	bb.add_child(lic)
	var cred := _rtl("Original game by [b]Vinay Gupta[/b] & [b]Dan Carter[/b] ([url=https://files.howtolivewiki.com/nuclear_poker_card_game_proliferation.pdf]original rules, PDF[/url]), GNU FDL licensed. Unofficial digital adaptation: code MIT, art and audio CC0, made with [url=https://godotengine.org]Godot Engine[/url].", 12, C_MUT)
	cred.mouse_filter = Control.MOUSE_FILTER_STOP
	cred.meta_clicked.connect(func(m): OS.shell_open(str(m)))
	var crm := MarginContainer.new()
	crm.add_theme_constant_override("margin_top", 12)
	crm.add_child(cred)
	col.add_child(crm)
	return root
