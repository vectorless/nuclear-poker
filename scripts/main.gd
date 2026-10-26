extends Control
## Nuclear Poker — Godot UI. Talks to NPGame (engine.gd). All controls are built in code.
## Game design: Vinay Gupta. Print-and-play v4.2: Jonathan Korman. Card designs inspired by Ian Willey.

const C_BG := Color("#0a0d11")
const C_BG2 := Color("#10151b")
const C_PANEL := Color("#151b23")
const C_PANEL2 := Color("#1b232d")
const C_LINE := Color("#2a3644")
const C_INK := Color("#e9eef3")
const C_MUT := Color("#8c9aab")
const C_AMBER := Color("#f2b134")
const C_RED := Color("#e5483f")
const C_GREEN := Color("#3ecf8e")

const ORDER := ["uranium", "refinement", "warhead", "testing", "short", "long", "counter", "super", "labs", "plague"]
const DELAY := {"classic": 1.0, "slow": 1.05, "fog": 0.95, "fast": 1.25}
const PERSONA_IDS := ["random", "hawk", "dove", "opp", "wild"]
const CARD_DESC := {
	"uranium": "Technology. Hold all four different Technologies to perform a Nuclear Test.",
	"refinement": "Technology. Hold all four different Technologies to perform a Nuclear Test.",
	"warhead": "Technology. Hold all four different Technologies to perform a Nuclear Test.",
	"testing": "Technology. Hold all four different Technologies to perform a Nuclear Test.",
	"short": "Needs a Nuclear Test. Attack: eliminate one neighboring player.",
	"long": "Needs Nuclear Test + Short-range. Attack: eliminate any one player.",
	"counter": "Needs Nuclear Test + Short + Long. When you are eliminated, eliminate one player.",
	"super": "Needs Nuclear Test + all 4 Capabilities. Attack any player at any time.",
	"labs": "Biotech. Enables and protects against Plague attacks.",
	"plague": "Biotech. Requires Labs. Attack: eliminate all players without Labs.",
}

var HEAD: Font
var MONO: Font
var TEX := {}

var cfg := {"name": "You", "mode": "classic", "bio": "off", "players": "3", "p1": "random", "p2": "random", "p3": "random", "fullscreen": false}
var G: NPGame = null
var ME: NPGame.Player = null

# game flow state
var speed := 1.0                  # >1 only in the automated test
var paused := 0
var pump_token := 0
var fast_tok := {}
var end_shown := false
var fog_open := false
var muted := false
var ff := false
var fresh := {}
var log_shown := 0
var card_w := 100.0
var mini_w := 46.0
var btn := {}                     # live buttons by key (also used by the automated test)
var modal_btns: Array = []
var opt_nodes: Array = []

# node refs
var menu_root: Control
var game_root: Control
var topbar: HBoxContainer
var board: VBoxContainer
var arsenal: RichTextLabel
var map_box: VBoxContainer
var logbox: RichTextLabel
var overlay: CanvasLayer
var modal_root: Control
var popup_root: Control
var fx_root: Control
var modal: Control = null
var modal_scroll: ScrollContainer = null
var modal_vbox: VBoxContainer = null
var modal_pause := false
var modal_sticky := false
var popup: Control = null
var name_edit: LineEdit
var opp_btns: Array = []
var opp_lbls: Array = []
var players_opt: OptionButton
var sounds := {}

# ====================================================================== custom controls
class Trefoil extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color("#f2b134"))
		for k in range(3):
			var mid := -PI / 2.0 + k * TAU / 3.0
			var pts := PackedVector2Array()
			for i in range(13):
				var a := mid - PI / 6.0 + (PI / 3.0) * i / 12.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.78)
			for i in range(12, -1, -1):
				var a2 := mid - PI / 6.0 + (PI / 3.0) * i / 12.0
				pts.append(c + Vector2(cos(a2), sin(a2)) * r * 0.26)
			draw_colored_polygon(pts, Color("#14181d"))
		draw_circle(c, r * 0.12, Color("#14181d"))

class Hazard extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#14181d"))
		var x := -size.y
		while x < size.x + size.y:
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + 12, size.y), Vector2(x + 12 + size.y, 0), Vector2(x + size.y, 0)]), Color("#f2b134"))
			x += 24.0

class RadioDot extends Control:
	var on := false
	func _draw() -> void:
		var c := size / 2.0
		draw_arc(c, 8.0, 0, TAU, 24, Color("#8c9aab") if not on else Color("#f2b134"), 2.0, true)
		if on:
			draw_circle(c, 4.0, Color("#f2b134"))

class CardBack extends Control:
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var base := StyleBoxFlat.new()
		base.bg_color = Color("#10151b")
		base.set_corner_radius_all(int(maxf(3.0, size.x * 0.07)))
		draw_style_box(base, rect)
		var c := size / 2.0
		for k in range(12):
			var a := TAU * k / 12.0
			var d := Vector2(cos(a), sin(a))
			var lim := minf((size.x / 2.0 - 3.0) / maxf(0.001, absf(d.x)), (size.y / 2.0 - 3.0) / maxf(0.001, absf(d.y)))
			if k % 2 == 0:
				draw_line(c, c + d * lim, Color("#1d252f"), maxf(3.0, size.x * 0.12))
		draw_circle(c, maxf(3.0, size.x * 0.09), Color("#d9a22e"))
		var border := StyleBoxFlat.new()
		border.draw_center = false
		border.border_color = Color("#38465a")
		border.set_border_width_all(2)
		border.set_corner_radius_all(int(maxf(3.0, size.x * 0.07)))
		draw_style_box(border, rect)

class HandCard extends Control:
	signal picked(cid: int, node: Control)
	var cid := 0
	var base_y := 0.0
	var fresh := false
	var tw: Tween
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(_hover.bind(true))
		mouse_exited.connect(_hover.bind(false))
	func _hover(on: bool) -> void:
		if tw:
			tw.kill()
		z_index = 20 if on else 0
		tw = create_tween()
		tw.tween_property(self, "position:y", base_y - (24.0 if on else 0.0), 0.12)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(cid, self)

class HandView extends Control:
	var cw := 100.0
	var ch := 130.0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			layout()
	func layout() -> void:
		custom_minimum_size.y = ch + 36.0
		var cards := get_children()
		var n := cards.size()
		if n == 0:
			return
		var avail := maxf(100.0, size.x - 40.0)
		var overlap := cw * 0.08
		if n > 1 and n * cw - (n - 1) * overlap > avail:
			overlap = (n * cw - avail) / (n - 1)
		overlap = minf(overlap, cw * 0.72)
		var total := n * cw - (n - 1) * overlap
		var x0 := (size.x - total) / 2.0
		for i in range(n):
			var c: HandCard = cards[i]
			c.size = Vector2(cw, ch)
			c.base_y = 28.0
			c.position = Vector2(x0 + i * (cw - overlap), 28.0)
			if c.fresh:
				c.fresh = false
				c.position.y -= 50.0
				c.modulate.a = 0.0
				var t := c.create_tween().set_parallel(true)
				t.tween_property(c, "position:y", 28.0, 0.35)
				t.tween_property(c, "modulate:a", 1.0, 0.25)

class TableMap extends Control:
	# Seats around the table. Solid amber = neighbours (Short range reaches); dashed = across (Long range only).
	var seats: Array = []     # {name, alive, tested, turn, you, color}
	var links: Array = []     # [i, j, "short" | "long"]
	var font: Font
	func _geom() -> Dictionary:
		return {"c": size / 2.0, "rx": size.x * 0.5 - 78.0, "ry": size.y * 0.5 - 34.0}
	func _draw() -> void:
		var n := seats.size()
		if n == 0:
			return
		var g := _geom()
		var c: Vector2 = g.c
		var rx: float = g.rx
		var ry: float = g.ry
		var poly := PackedVector2Array()
		for k in range(48):
			var a := TAU * k / 48.0
			poly.append(c + Vector2(cos(a) * (rx + 8.0), sin(a) * (ry + 8.0)))
		draw_colored_polygon(poly, Color("#10151b"))
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, Color("#2a3644"), 1.5, true)
		var pts: Array = []
		for i in range(n):
			var th := PI / 2.0 + TAU * i / n
			pts.append(c + Vector2(cos(th) * rx, sin(th) * ry))
		for l in links:
			var a2: Vector2 = pts[l[0]]
			var b2: Vector2 = pts[l[1]]
			if l[2] == "short":
				draw_line(a2, b2, Color("#f2b134"), 3.0, true)
			else:
				draw_dashed_line(a2, b2, Color("#8c9aab"), 2.0, 6.0, true, true)
		for i in range(n):
			var s: Dictionary = seats[i]
			var p: Vector2 = pts[i]
			var col: Color = s.color
			if not s.alive:
				col = Color("#3a4350")
			if s.turn and s.alive:
				draw_circle(p, 19.0, Color(0.95, 0.69, 0.2, 0.35))
			draw_circle(p, 13.0, col)
			if s.you:
				draw_arc(p, 16.0, 0.0, TAU, 28, Color("#3ecf8e"), 2.5, true)
			if s.tested and s.alive:
				draw_circle(p + Vector2(11.0, -11.0), 4.5, Color("#ffd37a"))
			if not s.alive:
				draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), Color("#ff6a60"), 2.5, true)
				draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), Color("#ff6a60"), 2.5, true)
			var txt: String = s.name
			var fs := 12
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var dir := p - c
			var lp := Vector2.ZERO
			if absf(dir.x) < 6.0:
				lp = Vector2(p.x - w / 2.0, p.y + (29.0 if dir.y > 0.0 else -21.0))
			elif dir.x > 0.0:
				lp = Vector2(p.x + 21.0, p.y + 4.0)
			else:
				lp = Vector2(p.x - 21.0 - w, p.y + 4.0)
			draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#e9eef3") if s.alive else Color("#667587"))

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
	var hbg := Color("#222a35")
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

func _tex(key: String, w: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = TEX[key]
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.custom_minimum_size = Vector2(w, w * 430.0 / 330.0)
	t.tooltip_text = NPGame.INFO[key].name
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	return t

func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

func _persona_color(p: NPGame.Player) -> Color:
	return Color(p.persona.color) if not p.persona.is_empty() else C_GREEN

# ====================================================================== boot
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	HEAD = load("res://fonts/Oswald-Medium.woff2")
	MONO = load("res://fonts/ShareTechMono.woff2")
	for k in ORDER:
		TEX[k] = load("res://assets/%s.png" % k)
	_load_cfg()
	if bool(cfg.fullscreen) and not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_build_sounds()
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
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
		overlay.add_child(c)
		set(nm, c)
	get_viewport().size_changed.connect(_on_resize)
	if "--autotest" in OS.get_cmdline_user_args():
		_autotest.call_deferred()
	elif "--shots" in OS.get_cmdline_user_args():
		_shots.call_deferred()

func _load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://nuclear_poker.cfg") == OK:
		for k in cfg.keys():
			cfg[k] = cf.get_value("s", k, cfg[k])
		muted = bool(cf.get_value("s", "muted", false))
	cfg.mode = "classic"          # the other WAR modes are locked for now
	cfg.players = "4" if str(cfg.players) == "4" else "3"

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

func _build_sounds() -> void:
	for k in ["test", "attack", "death", "click"]:
		var p := AudioStreamPlayer.new()
		p.stream = _make_sound(k)
		add_child(p)
		sounds[k] = p

func snd(kind: String) -> void:
	if muted or not sounds.has(kind) or DisplayServer.get_name() == "headless":
		return
	sounds[kind].play()

# ====================================================================== menu
func _build_menu() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scroll)
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 0)
	scroll.add_child(outer)
	var hz := Hazard.new()
	hz.custom_minimum_size = Vector2(0, 10)
	outer.add_child(hz)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	col.add_child(_lbl("a fun, scary teaching game  ·  you vs. two or three AI powers", 14, C_MUT, MONO))

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

	var b1 := _box(left, "Rules")
	opt_nodes.clear()
	_opt(b1, "mode", "classic", "Classic", "The original rules sheet. Each turn you draw a card OR offer a trade - and a trading partner may deceive you. Anyone can Test or Attack, in order of play around the table.")
	_opt(b1, "mode", "slow", "Slow WAR", "Locked for now.", true)
	_opt(b1, "mode", "fog", "Fog WAR", "Locked for now.", true)
	_opt(b1, "mode", "fast", "Fast WAR", "Locked for now.", true)
	var b2 := _box(left, "Biowar expansion")
	_opt(b2, "bio", "off", "Off", "Standard nuclear game.")
	_opt(b2, "bio", "2000", "2000", "Labs and Plague cards join the deck. Plague needs a Nuclear Test + all 4 Capabilities first.")
	_opt(b2, "bio", "2035", "2035", "Biotech is cheap: just show Labs and have Plague. Everyone without Labs dies. Brutal.")

	var b3 := _box(right, "The table")
	b3.add_child(_lbl("PLAYERS AT THE TABLE", 12, C_MUT, MONO))
	players_opt = OptionButton.new()
	players_opt.focus_mode = Control.FOCUS_NONE
	players_opt.add_item("3 players - you and two AI powers")
	players_opt.add_item("4 players - you and three AI powers")
	for st0 in ["normal", "hover", "pressed"]:
		players_opt.add_theme_stylebox_override(st0, _sb(C_PANEL2, C_LINE, 1, 8, 9))
	players_opt.select(1 if str(cfg.players) == "4" else 0)
	players_opt.item_selected.connect(func(i):
		cfg.players = "4" if i == 1 else "3"
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
	for i in range(3):
		var ol := _lbl("OPPONENT %d" % (i + 1), 12, C_MUT, MONO)
		b3.add_child(ol)
		opp_lbls.append(ol)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.add_item("Random")
		for pid in ["hawk", "dove", "opp", "wild"]:
			var pe: Dictionary = NPGame.PERSONAS[pid]
			ob.add_item("%s - %s" % [pe.name, pe.title])
		for st in ["normal", "hover", "pressed"]:
			ob.add_theme_stylebox_override(st, _sb(C_PANEL2, C_LINE, 1, 8, 9))
		ob.select(maxi(0, PERSONA_IDS.find(cfg["p%d" % (i + 1)])))
		b3.add_child(ob)
		opp_btns.append(ob)
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
	var spc := Control.new()
	spc.custom_minimum_size = Vector2(0, 8)
	b3.add_child(spc)
	b3.add_child(row)
	btn["begin"] = begin

	var cred := _rtl("Game design by [b]Vinay Gupta[/b] ([url=https://twitter.com/leashless]@leashless[/url]) · card designs inspired by [b]Ian Willey[/b] · print-and-play v4.2 by [b]Jonathan Korman[/b] ([url=https://miniver.itch.io/nuclear-poker]miniver.itch.io[/url]).\nThis is an unofficial digital adaptation using the print-and-play card art. \"The only winning move is not to play.\"", 13, C_MUT)
	cred.meta_clicked.connect(func(m): OS.shell_open(str(m)))
	right.add_child(cred)
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 6)
	strip.add_theme_constant_override("v_separation", 6)
	for k in ORDER:
		strip.add_child(_tex(k, 52))
	right.add_child(strip)
	_refresh_opts()
	return root

func _opt(parent: Control, group: String, value: String, title: String, desc: String, locked := false) -> void:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if locked else Control.CURSOR_POINTING_HAND
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := RadioDot.new()
	dot.custom_minimum_size = Vector2(20, 20)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(dot)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _lbl(title.to_upper() + ("  -  LOCKED" if locked else ""), 18, Color("#667587") if locked else C_INK, HEAD)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := _lbl(desc, 13, Color("#556070") if locked else C_MUT, null, true)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)
	vb.add_child(d)
	hb.add_child(vb)
	pc.add_child(hb)
	pc.gui_input.connect(func(e):
		if locked:
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			cfg[group] = value
			_refresh_opts())
	parent.add_child(pc)
	if locked:
		dot.visible = false
	opt_nodes.append({"group": group, "value": value, "panel": pc, "dot": dot, "locked": locked})

func _refresh_opts() -> void:
	for o in opt_nodes:
		var sel: bool = cfg[o.group] == o.value and not o.locked
		var s := _sb(Color("#241f12") if sel else (C_BG2 if o.locked else C_PANEL2), C_AMBER if sel else (Color("#1c2530") if o.locked else C_LINE), 1, 10, 10)
		o.panel.add_theme_stylebox_override("panel", s)
		o.dot.on = sel
		o.dot.queue_redraw()
	var four := str(cfg.players) == "4"
	if opp_btns.size() > 2:
		opp_btns[2].visible = four
		opp_lbls[2].visible = four

func _on_begin() -> void:
	cfg.name = name_edit.text.strip_edges().left(18) if name_edit.text.strip_edges() != "" else "You"
	cfg.p1 = PERSONA_IDS[opp_btns[0].selected]
	cfg.p2 = PERSONA_IDS[opp_btns[1].selected]
	cfg.p3 = PERSONA_IDS[opp_btns[2].selected]
	cfg.players = "4" if players_opt.selected == 1 else "3"
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
	arsenal = _rtl("", 13)
	arsenal.add_theme_font_override("normal_font", MONO)
	arsenal.add_theme_font_override("bold_font", MONO)
	sv.add_child(arsenal)
	map_box = VBoxContainer.new()
	sv.add_child(map_box)
	sv.add_child(HSeparator.new())
	sv.add_child(_lbl("EVENT LOG", 14, C_AMBER, HEAD))
	logbox = RichTextLabel.new()
	logbox.bbcode_enabled = true
	logbox.scroll_following = true
	logbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	logbox.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	logbox.add_theme_font_override("normal_font", MONO)
	logbox.add_theme_font_size_override("normal_font_size", 13)
	logbox.add_theme_color_override("default_color", Color("#aab6c3"))
	sv.add_child(logbox)
	return root

# ====================================================================== start / events
func _start_game() -> void:
	var ids := ["hawk", "dove", "opp", "wild"]
	var n_ai := 3 if str(cfg.players) == "4" else 2
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
	G.setup({"mode": cfg.mode, "bio": cfg.bio, "players": plist})
	ME = G.players[0]
	end_shown = false
	ff = false
	fresh.clear()
	paused = 0
	fog_open = false
	log_shown = 0
	logbox.clear()
	_close_modal(true)
	_close_popup()
	G.event.connect(_on_event)
	menu_root.visible = false
	game_root.visible = true
	G.log_msg("Game on - %s rules, %d players%s. %s goes first." % [G.mode.to_upper(), G.players.size(), (" + BIOWAR " + G.bio) if G.bio != "off" else "", G.cur().name], "sys")
	_fast_start()
	_pump()

func _on_event(t: String, d: Dictionary) -> void:
	match t:
		"test":
			_fx("Nuclear Test", "test")
			snd("test")
			_fast_react(d.p)
		"attack":
			_fx("PLAGUE" if d.type == "plague" else "Launch Detected", "attack")
			snd("attack")
			_fast_react(d.attacker)
		"death":
			_fx("You are eliminated" if d.p == ME else d.p.name + " eliminated", "death")
			snd("death")
			_shake()
		"draw":
			if d.p == ME:
				fresh[d.c.id] = true
		"give":
			if d.to == ME:
				fresh[d.c.id] = true

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
			_trade_modal()
		else:
			_counter_modal()
		return
	if st == "human":
		_on_human_turn(tok)
		return
	var delay: float = (float(DELAY[G.mode]) if ME.alive else (0.04 if ff else 0.26)) / speed
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
	elif G.phase == "war" and G.mode != "classic":
		var L2 := G.legal(ME)
		if not L2.can_test and L2.attacks.is_empty():
			_toast("No Test or Attack available - standing down.")
			await get_tree().create_timer(0.8 / speed).timeout
			if tok == pump_token and G != null and G.cur() == ME and G.phase == "war":
				G.human_war({"kind": "pass"})
				_pump()
	elif G.phase == "fog":
		if not fog_open and G.fog_pending().has(ME):
			_fog_modal()

# ---- Fast mode: AIs act on their own clocks
func _fast_start() -> void:
	fast_tok.clear()
	if G.mode != "fast":
		return
	for p in G.players:
		if not p.human:
			_schedule_fast(p, 2.5 + randf() * 3.0)

func _schedule_fast(p: NPGame.Player, secs: float) -> void:
	var gen := G
	var tok: int = int(fast_tok.get(p.id, 0)) + 1
	fast_tok[p.id] = tok
	await get_tree().create_timer(secs / speed).timeout
	if G != gen or G == null or fast_tok.get(p.id, 0) != tok:
		return
	_fast_tick(p)

func _fast_tick(p: NPGame.Player) -> void:
	if G == null or G.over or not p.alive or G.mode != "fast":
		return
	if paused > 0 or not G.prompt.is_empty():
		_schedule_fast(p, 0.5)
		return
	var acted := G.ai_fast_tick(p)
	var r: Array = p.persona.react
	_schedule_fast(p, lerpf(r[0], r[1], randf()) + (1.2 if acted else 0.0))
	if acted:
		_pump()

func _fast_react(by: NPGame.Player) -> void:
	if G == null or G.mode != "fast":
		return
	for p in G.players:
		if p.human or not p.alive or p == by:
			continue
		var r: Array = p.persona.react
		_schedule_fast(p, lerpf(r[0], r[1], randf()) * 0.45)

func _fs_on() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _fs_label() -> String:
	return "Windowed" if _fs_on() else "Fullscreen"

func _toggle_fullscreen() -> void:
	var on := not _fs_on()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	cfg.fullscreen = on
	_save_cfg()
	_refresh_fs_buttons()

func _refresh_fs_buttons() -> void:
	if btn.has("fs_menu") and is_instance_valid(btn.fs_menu):
		btn.fs_menu.text = _fs_label().to_upper()
	if G != null and game_root.visible:
		_render_top()

func _on_resize() -> void:
	_refresh_fs_buttons()
	if G != null and game_root.visible:
		_render()

# ====================================================================== render
func _render() -> void:
	if G == null:
		return
	_render_top()
	_render_board()
	_render_side()

func _render_top() -> void:
	_clear(topbar)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 6)
	brand.add_child(_lbl("NUCLEAR", 22, C_INK, HEAD))
	brand.add_child(_lbl("POKER", 22, C_AMBER, HEAD))
	topbar.add_child(brand)
	topbar.add_child(_chip({"classic": "Classic", "slow": "Slow WAR", "fog": "Fog WAR", "fast": "Fast WAR"}[G.mode], true))
	topbar.add_child(_chip("%d players" % G.players.size()))
	if G.bio != "off":
		topbar.add_child(_chip("Biowar " + G.bio, true))
	topbar.add_child(_chip("Round %d" % G.round_no))
	topbar.add_child(_chip("Deck %d" % G.deck.size()))
	topbar.add_child(_spacer())
	var cf := _btn("Propose stand-down", "default", 13)
	cf.disabled = G.over or not ME.alive
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
		_render_top())
	topbar.add_child(so)
	var me := _btn("Menu", "default", 13)
	me.pressed.connect(_act_menu)
	topbar.add_child(me)

func _render_board() -> void:
	_clear(board)
	btn.clear()
	var vw := get_viewport_rect().size.x
	card_w = clampf(vw * 0.085, 84.0, 128.0)
	mini_w = clampf(vw * 0.036, 38.0, 56.0)
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
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 5)
	fl.add_theme_constant_override("v_separation", 5)
	fl.custom_minimum_size.y = mini_w * 430.0 / 330.0 + 4
	for it in items:
		fl.add_child(it)
	if items.is_empty():
		fl.add_child(_lbl(empty_text, 12, C_MUT, MONO))
	vb.add_child(fl)
	return vb

func _mini_pub(key: String) -> Control:
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
	hd.add_child(_lbl(p.name.to_upper(), 20, C_INK, HEAD))
	hd.add_child(_lbl(p.persona.title, 12, _persona_color(p), MONO))
	if ME.alive and p.alive and p != ME:
		if G.neighbors_of(ME).has(p):
			var al := G.alive_list()
			var side := "LEFT" if al[(al.find(ME) + 1) % al.size()] == p else "RIGHT"
			hd.add_child(_badge("ON YOUR %s - SHORT RANGE" % side, Color("#ffd37a"), Color("#2b2210"), Color("#7a5d18")))
		else:
			hd.add_child(_badge("ACROSS - LONG RANGE ONLY", C_MUT, C_PANEL2, C_LINE))
	if G.mode == "classic" and p.alive:
		for d in G.debts:
			if d.to == p.id:
				hd.add_child(_badge("OWES %s A CARD" % ("YOU" if d.from == ME.id else G.players[d.from].name.to_upper()), Color("#9fd2ff"), Color("#101c2a"), Color("#2f5f8f")))
	if p.tested:
		hd.add_child(_badge("TESTED", Color("#ffd37a"), Color("#2b2210"), Color("#7a5d18")))
	if G.phase == "fog" and G.fog_choices.has(p.id) and p.alive:
		hd.add_child(_badge("order sealed", Color("#9db4ff"), Color("#12172b"), Color("#34457f")))
	if not p.alive:
		hd.add_child(_badge(("killed by " + G.players[p.eliminated_by].name) if p.eliminated_by >= 0 else "eliminated", C_MUT, C_PANEL2, C_LINE))
	vb.add_child(hd)
	var hand_items: Array = []
	var unk := 0
	for c in p.hand:
		if c.pub:
			hand_items.append(_mini_pub(c.key))
		else:
			unk += 1
	var backs: Array = []
	for i in range(mini(unk, 14)):
		var cb := CardBack.new()
		cb.custom_minimum_size = Vector2(mini_w, mini_w * 430.0 / 330.0)
		backs.append(cb)
	if unk > 14:
		backs.append(_lbl("+%d" % (unk - 14), 12, C_MUT, MONO))
	vb.add_child(_zone("Hand · %d card%s" % [p.hand.size(), "" if p.hand.size() == 1 else "s"], backs + hand_items, "(empty)"))
	var tbl: Array = []
	for c in p.table:
		tbl.append(_tex(c.key, mini_w))
	vb.add_child(_zone("On the table", tbl, "nothing yet"))
	if not p.alive:
		pc.modulate = Color(0.55, 0.55, 0.55)
		var ov := _lbl("ELIMINATED", 26, Color("#ff6a60"), HEAD)
		ov.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ov.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(ov)
	return pc

func _warcard_text() -> String:
	match G.mode:
		"slow": return "[b]SLOW WAR[/b]\nEach turn: play action, then no action / Test / Attack. Superpower may strike at any time."
		"fog": return "[b]FOG WAR[/b]\nAfter each turn all players secretly choose: no action / Test / Attack a named player. Resolved together."
	return "[b]FAST WAR[/b]\nEveryone may Test or Attack at any moment, in the order announced. Superpower can pause and peek."

func _banner() -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text := ""
	var tone := "n"
	if G.over:
		text = "The game is over."
	elif not ME.alive:
		text = "You were eliminated. The game continues without you..."
		tone = "dead"
	elif G.mode == "classic":
		var wa := _war_peek()
		if G.phase == "honour":
			if G.cur() == ME and not G._debts_of(ME).is_empty():
				text = "[b][color=#f2b134]A trade is due.[/color][/b] %s gave you a card. Click a card in your hand to hand one back - or deceive them." % G.players[G._debts_of(ME)[0].from].name
				tone = "you"
			else:
				text = "%s is deciding whether to honour a trade..." % G.cur().name
		elif G.phase == "play":
			if G.cur() == ME:
				text = "[b][color=#f2b134]Your turn.[/color][/b] Research a card - or click a card in your hand to offer it in a trade."
				tone = "you"
			else:
				text = "%s is thinking..." % G.cur().name
		elif wa == ME.id:
			text = "[b][color=#f2b134]Exchange window.[/color][/b] Declare a Nuclear Test or an Attack - or stand down."
			tone = "you"
		elif wa >= 0:
			text = "Exchange window: %s is deciding..." % G.players[wa].name
		else:
			text = "Nuclear exchanges: nobody has anything to declare."
	elif G.phase == "fog":
		if G.fog_pending().has(ME):
			text = "[b][color=#f2b134]Fog of war.[/color][/b] Write down your order."
			tone = "you"
		else:
			text = "The fog gathers... orders are being written."
	elif G.cur() == ME:
		tone = "you"
		if G.phase == "play":
			text = "[b][color=#f2b134]Your turn.[/color][/b] Research a card - or click a card in your hand to give it away or return it."
		else:
			text = "[b][color=#f2b134]War step.[/color][/b] Stand down, perform a Nuclear Test, or Attack."
	else:
		text = "%s is %s..." % [G.cur().name, "weighing the war step" if G.phase == "war" else "thinking"]
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
	pc.custom_minimum_size.y = 46
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	var r := _rtl("[center]%s[/center]" % text, 16)
	hb.add_child(r)
	if not ME.alive and not G.over:
		var sk := _btn("Skip to end", "default", 13)
		sk.pressed.connect(func():
			ff = true
			_pump())
		hb.add_child(sk)
	pc.add_child(hb)
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
	if G.mode == "classic":
		return hb
	var wc := PanelContainer.new()
	wc.add_theme_stylebox_override("panel", _sb(C_PANEL2, C_LINE, 1, 8, 8))
	wc.custom_minimum_size.x = 250
	wc.add_child(_rtl(_warcard_text(), 12, C_MUT))
	hb.add_child(wc)
	return hb

func _war_peek() -> int:
	if G.mode == "classic" and G.phase == "war" and not G.war_queue.is_empty():
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
	vb.add_child(_lbl("THE TABLE  -  turns go clockwise", 12, C_MUT, MONO))
	var tm := TableMap.new()
	tm.font = MONO
	tm.custom_minimum_size = Vector2(296, 176)
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
	var lg := _rtl("[color=#f2b134][b]Solid[/b][/color] = neighbours: [b]Short range[/b] reaches.  [color=#8c9aab][b]Dashed[/b][/color] = across: needs [b]Long range[/b].", 12, C_MUT)
	vb.add_child(lg)
	return pc

func _me_panel() -> Control:
	var myturn: bool = not G.over and ME.alive and ((G.cur() == ME and G.phase != "war") or (G.phase == "fog" and G.fog_pending().has(ME)) or _war_peek() == ME.id or (G.mode != "classic" and G.cur() == ME))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _sb(C_PANEL, C_AMBER if myturn else C_LINE, 2 if myturn else 1, 12, 12))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	var hd := HBoxContainer.new()
	hd.add_theme_constant_override("separation", 8)
	hd.add_child(_lbl(ME.name.to_upper(), 20, C_INK, HEAD))
	hd.add_child(_lbl("You", 12, C_GREEN, MONO))
	if ME.tested:
		hd.add_child(_badge("TESTED", Color("#ffd37a"), Color("#2b2210"), Color("#7a5d18")))
	if not ME.alive:
		hd.add_child(_badge("eliminated", C_MUT, C_PANEL2, C_LINE))
	if G.mode == "classic" and ME.alive:
		for d in G.debts:
			if d.to == ME.id:
				hd.add_child(_badge("YOU OWE %s A CARD" % G.players[d.from].name.to_upper(), Color("#9fd2ff"), Color("#101c2a"), Color("#2f5f8f")))
			elif d.from == ME.id:
				hd.add_child(_badge("%s OWES YOU A CARD" % G.players[d.to].name.to_upper(), Color("#9fd2ff"), Color("#101c2a"), Color("#2f5f8f")))
	hd.add_child(_spacer())
	hd.add_child(_lbl("%d in hand" % ME.hand.size(), 12, C_MUT, MONO))
	vb.add_child(hd)
	if not ME.table.is_empty():
		var tr := HBoxContainer.new()
		tr.add_theme_constant_override("separation", 8)
		for c in ME.table:
			tr.add_child(_tex(c.key, mini_w * 1.35))
		vb.add_child(tr)
	var hv := HandView.new()
	hv.cw = card_w
	hv.ch = card_w * 430.0 / 330.0
	hv.custom_minimum_size = Vector2(0, hv.ch + 36)
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
		var t := _tex(c.key, hv.cw)
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.tooltip_text = ""
		hc.add_child(t)
		if c.pub:
			var mk := _badge("REVEALED", C_AMBER, Color(0, 0, 0, 0.75), Color(0, 0, 0, 0))
			mk.position = Vector2(4, hv.ch - 24)
			mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hc.add_child(mk)
		hc.picked.connect(_card_menu)
		hv.add_child(hc)
	vb.add_child(hv)
	hv.layout.call_deferred()
	fresh.clear()
	vb.add_child(_action_bar())
	return pc

func _action_bar() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	if G.over:
		return wrap
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 10)
	bar.add_theme_constant_override("v_separation", 8)
	wrap.add_child(bar)
	if not ME.alive:
		bar.add_child(_lbl("Spectating.", 13, C_MUT))
		return wrap
	if G.mode == "classic":
		_classic_actions(bar)
		return wrap
	var my_turn: bool = G.cur() == ME
	var L := G.legal(ME)
	if G.phase == "play" and my_turn:
		var rb := _btn("Research - draw a card", "primary")
		rb.disabled = not L.can_research
		rb.pressed.connect(_act_research)
		bar.add_child(rb)
		btn["research"] = rb
		bar.add_child(_lbl("or click a card in your hand to give / return it" if L.can_research else "The deck is empty - give or return a card.", 13, C_MUT))
		if not L.can_research and ME.hand.is_empty():
			var sk := _btn("Skip")
			sk.pressed.connect(func():
				G.play_skip(ME)
				_pump())
			bar.add_child(sk)
			btn["skip"] = sk
	elif G.phase == "war" and my_turn:
		var sd := _btn("Stand down")
		sd.pressed.connect(func():
			G.human_war({"kind": "pass"})
			_after_human())
		bar.add_child(sd)
		btn["stand"] = sd
		var tb := _btn("Nuclear Test")
		tb.disabled = not L.can_test
		tb.pressed.connect(_act_test)
		bar.add_child(tb)
		btn["test"] = tb
		var ab := _btn("Attack...", "danger")
		ab.disabled = L.attacks.is_empty()
		ab.pressed.connect(_attack_modal.bind("turn"))
		bar.add_child(ab)
		btn["attack"] = ab
		bar.add_child(_lbl("choose one", 13, C_MUT))
	elif G.phase == "fog" and G.fog_pending().has(ME):
		var fo := _btn("Write down your order", "primary")
		fo.pressed.connect(_fog_modal)
		bar.add_child(fo)
		btn["fogopen"] = fo
	else:
		bar.add_child(_lbl("Waiting for %s..." % G.cur().name, 13, C_MUT))
	# Fast WAR / Superpower bar
	var F := G.legal(ME, true)
	if G.mode == "fast" or (not F.attacks.is_empty() and not (G.phase == "war" and my_turn)):
		var fb := PanelContainer.new()
		fb.add_theme_stylebox_override("panel", _sb(Color("#1f1612"), Color("#5a3322"), 1, 9, 8))
		var fh := HFlowContainer.new()
		fh.add_theme_constant_override("h_separation", 8)
		fh.add_child(_lbl(("FAST WAR - act any time" if G.mode == "fast" else "SUPERPOWER - attack any time").to_upper(), 13, Color("#ff9e6b"), HEAD))
		if G.mode == "fast":
			var ft := _btn("Nuclear Test", "default", 13)
			ft.disabled = not F.can_test
			ft.pressed.connect(_act_test)
			fh.add_child(ft)
			btn["ftest"] = ft
		var fa := _btn("Attack...", "danger", 13)
		fa.disabled = F.attacks.is_empty()
		fa.pressed.connect(_attack_modal.bind("interrupt"))
		fh.add_child(fa)
		btn["fattack"] = fa
		if F.can_peek:
			var pk := _btn("Superpower: examine hands", "default", 13)
			pk.pressed.connect(_peek_modal)
			fh.add_child(pk)
			btn["peek"] = pk
		fb.add_child(fh)
		wrap.add_child(fb)
	return wrap

func _classic_actions(bar: HFlowContainer) -> void:
	var L := G.legal(ME)
	if G.phase == "honour" and G.cur() == ME and not G._debts_of(ME).is_empty():
		var cr: NPGame.Player = G.players[G._debts_of(ME)[0].from]
		var rb := _btn("Deceive %s - keep the card" % cr.name, "danger")
		rb.pressed.connect(func():
			G.renege(ME)
			_after_human())
		bar.add_child(rb)
		btn["renege"] = rb
		bar.add_child(_lbl("or click a card in your hand to give it to %s" % cr.name, 13, C_MUT))
	elif G.phase == "play" and G.cur() == ME:
		var rb2 := _btn("Research - draw a card", "primary")
		rb2.disabled = not L.can_research
		rb2.pressed.connect(_act_research)
		bar.add_child(rb2)
		btn["research"] = rb2
		bar.add_child(_lbl("or click a card in your hand to offer it in a trade" if L.can_research else "The deck is empty - offer a trade, or skip.", 13, C_MUT))
		if not L.can_research:
			var sk := _btn("Skip turn")
			sk.pressed.connect(func():
				G.play_skip(ME)
				_after_human())
			bar.add_child(sk)
			btn["skip"] = sk
	elif G.phase == "war" and _war_peek() == ME.id:
		var sd := _btn("Stand down")
		sd.pressed.connect(func():
			G.war_declare(ME, {"kind": "pass"})
			_after_human())
		bar.add_child(sd)
		btn["stand"] = sd
		var tb := _btn("Nuclear Test")
		tb.disabled = not L.can_test
		tb.pressed.connect(_act_test)
		bar.add_child(tb)
		btn["test"] = tb
		var ab := _btn("Attack...", "danger")
		ab.disabled = L.attacks.is_empty()
		ab.pressed.connect(_attack_modal.bind("turn"))
		bar.add_child(ab)
		btn["attack"] = ab
		bar.add_child(_lbl("choose one", 13, C_MUT))
	else:
		bar.add_child(_lbl("Waiting for the table...", 13, C_MUT))

func _render_side() -> void:
	_clear(map_box)
	if G.mode == "classic":
		map_box.add_child(_map_panel())
	var tested := ME.tested
	var lines: Array = []
	var tech_bits: Array = []
	for k in NPGame.TECH:
		var have := G.holds(ME, k)
		tech_bits.append("[color=%s]%s %s[/color]" % ["#3ecf8e" if have else "#667587", "+" if have else "-", NPGame.INFO[k].name])
	lines.append("  ".join(tech_bits))
	var pre := {
		"short": tested,
		"long": tested and G.holds(ME, "short"),
		"counter": tested and G.holds(ME, "short") and G.holds(ME, "long"),
		"super": tested and G.has_all_caps(ME)}
	for k in NPGame.CAPS:
		var have2 := G.holds(ME, k)
		var col := "#667587"
		var mark := "-"
		if have2 and pre[k]:
			col = "#3ecf8e"
			mark = "armed"
		elif have2:
			col = "#f2b134"
			mark = "held"
		lines.append("[color=%s]%s: %s[/color]" % [col, NPGame.INFO[k].name, mark])
	if G.bio != "off":
		lines.append("[color=%s]Labs %s[/color]   [color=%s]Plague %s[/color]" % [
			"#3ecf8e" if G.holds(ME, "labs") else "#667587", "held" if G.holds(ME, "labs") else "-",
			"#3ecf8e" if G.holds(ME, "plague") else "#667587", "held" if G.holds(ME, "plague") else "-"])
	var need := 0
	for k in NPGame.TECH:
		if not G.holds(ME, k):
			need += 1
	if tested:
		lines.append("Nuclear Test done - Capabilities you hold are armed.")
	elif G.can_test(ME):
		lines.append("[color=#3ecf8e]You hold all four Technologies - you can perform a Nuclear Test![/color]")
	else:
		lines.append("%d Technolog%s short of a Nuclear Test." % [need, "y" if need == 1 else "ies"])
	arsenal.text = "[color=#f2b134][b]YOUR ARSENAL[/b][/color]\n" + "\n".join(lines)
	var tones := {"attack": "#ff8b82", "death": "#ff5b50", "test": "#ffd37a", "reveal": "#9fd2ff", "fog": "#b8a6ff", "quiet": "#66758a", "sys": "#f2b134"}
	while log_shown < G.log_entries.size():
		var e: Dictionary = G.log_entries[log_shown]
		log_shown += 1
		logbox.append_text("[color=%s]%s[/color]\n" % [tones.get(e.tone, "#aab6c3"), e.text.replace("[", "(")])

# ====================================================================== actions
func _after_human() -> void:
	_close_popup()
	_pump()

func _act_research() -> void:
	if G.play_research(ME):
		snd("click")
		_after_human()

func _act_test() -> void:
	if G.mode == "classic":
		G.war_declare(ME, {"kind": "test"})
	elif G.mode == "fast" or not (G.phase == "war" and G.cur() == ME):
		G.instant(ME, {"kind": "test"}, true)
	else:
		G.human_war({"kind": "test"})
	_after_human()

func _act_launch(mode: String, type: String, tid: int) -> void:
	var choice := {"kind": "attack", "type": type, "target": tid}
	_close_modal()
	if G.mode == "classic":
		G.war_declare(ME, choice)
	elif mode == "turn":
		G.human_war(choice)
	elif mode == "fog":
		G.submit_fog(ME.id, choice)
	else:
		G.instant(ME, choice, true)
	_after_human()

func _act_fog_submit(kind: String) -> void:
	_close_modal(true)
	G.submit_fog(ME.id, {"kind": kind})
	_after_human()

func _act_counter(tid: int) -> void:
	_close_modal(true)
	G.choose_counter(tid)
	_after_human()

func _act_ceasefire() -> void:
	var r := G.propose_ceasefire(ME)
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
	fast_tok.clear()
	_close_modal(true)
	_close_popup()
	G = null
	game_root.visible = false
	menu_root.visible = true

# ---- card popup
func _card_menu(cid: int, node: Control) -> void:
	_close_popup()
	var c = null
	for x in ME.hand:
		if x.id == cid:
			c = x
	if c == null:
		return
	var my_play: bool = not G.over and ME.alive and G.cur() == ME and G.phase == "play"
	popup = Control.new()
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_popup())
	popup.add_child(catcher)
	var pn := PanelContainer.new()
	pn.add_theme_stylebox_override("panel", _sb(Color("#0f141a"), C_AMBER, 1, 10, 10))
	pn.custom_minimum_size.x = 250
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	pn.add_child(vb)
	vb.add_child(_lbl(NPGame.INFO[c.key].name.to_upper(), 18, C_AMBER, HEAD))
	vb.add_child(_lbl(CARD_DESC[c.key], 12, C_MUT, null, true))
	var any := false
	if G.mode == "classic":
		if G.phase == "honour" and G.cur() == ME and not G._debts_of(ME).is_empty():
			var cr: NPGame.Player = G.players[G._debts_of(ME)[0].from]
			var hb := _btn("Give to " + cr.name, "primary", 14)
			hb.pressed.connect(func():
				G.honour(ME, cid)
				_after_human())
			vb.add_child(hb)
			vb.add_child(_lbl("Completes the trade you agreed to.", 12, C_MUT, null, true))
			any = true
		elif my_play:
			vb.add_child(_lbl("Offer this card face-down. If they agree they take it now - and owe you one back on their next turn (or deceive you).", 12, C_MUT, null, true))
			for o in G.others(ME):
				var ob := _btn("Offer to " + o.name, "default", 14)
				ob.pressed.connect(func():
					var res := G.trade_offer(ME, cid, o.id)
					if res == "declined":
						_toast("%s declines your offer." % o.name)
					_after_human())
				vb.add_child(ob)
			any = true
	elif not c.pub:
		var rb := _btn("Reveal to everyone", "default", 14)
		rb.pressed.connect(func():
			G.reveal(ME, cid)
			_close_popup()
			_render())
		vb.add_child(rb)
		any = true
	if my_play and G.mode != "classic":
		for o in G.others(ME):
			var gb := _btn("Give to " + o.name, "default", 14)
			gb.pressed.connect(func():
				G.play_give(ME, cid, o.id)
				_after_human())
			vb.add_child(gb)
		var db := _btn("Return to deck", "default", 14)
		db.pressed.connect(func():
			G.play_disarm(ME, cid)
			_after_human())
		vb.add_child(db)
		any = true
	if not any:
		vb.add_child(_lbl("Nothing to do with this card right now.", 12, C_MUT))
	popup.add_child(pn)
	popup_root.add_child(popup)
	await get_tree().process_frame
	if popup == null or not is_instance_valid(pn):
		return
	var r := node.get_global_rect()
	var vp := get_viewport_rect().size
	pn.position = Vector2(clampf(r.get_center().x - pn.size.x / 2.0, 8.0, vp.x - pn.size.x - 8.0), maxf(8.0, r.position.y - pn.size.y - 10.0))

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
	fog_open = false
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

func _attack_list(vb: VBoxContainer, L: Dictionary, mode: String) -> void:
	var info := {
		"short": ["Short-range strike", "Eliminates a player sitting immediately to your left or right. Shows the Capabilities it needs."],
		"long": ["Long-range strike", "Eliminates any one player. Shows the Capabilities it needs."],
		"super": ["Superpower strike", "Eliminates any one player - usable at any time."],
		"plague": ["Plague", "Eliminates ALL players without Labs. You are protected by your own Labs."]}
	for a in L.attacks:
		var fl := _atk_panel(vb, info[a.type][0], info[a.type][1])
		if a.type == "plague":
			var pb := _btn("Release Plague", "danger")
			pb.pressed.connect(_act_launch.bind(mode, "plague", -1))
			fl.add_child(pb)
			modal_btns.append({"kind": "launch", "type": "plague", "button": pb})
		else:
			for tid in a.targets:
				var rel := ""
				if a.type == "long" or a.type == "super":
					rel = " (next to you)" if G.neighbors_of(ME).has(G.players[tid]) else " (across the table)"
				var tb := _btn("Target: " + G.players[tid].name + rel, "danger")
				tb.pressed.connect(_act_launch.bind(mode, a.type, tid))
				fl.add_child(tb)
				modal_btns.append({"kind": "launch", "type": a.type, "button": tb})

func _attack_modal(mode: String) -> void:
	var L := G.legal(ME, mode == "interrupt")
	if L.attacks.is_empty():
		_toast("No attacks available.")
		return
	var vb := _open_modal("Choose your attack", true, false, true)
	_close_btn(vb, "Cancel")
	vb.add_child(_lbl("This cannot be undone.", 15, C_MUT))
	_attack_list(vb, L, mode)

func _fog_modal() -> void:
	fog_open = true
	var L := G.legal(ME)
	var vb := _open_modal("Fog of war - write down your order", false, true, false)
	fog_open = true
	vb.add_child(_rtl("Everyone (including the AIs) writes one order. When all are in, they are revealed and resolve [b]simultaneously[/b]. An attack needs a Nuclear Test that is already on the table.", 15, Color("#c3ccd6")))
	var f1 := _atk_panel(vb, "Hold", "No action.")
	var hb := _btn("No action")
	hb.pressed.connect(_act_fog_submit.bind("pass"))
	f1.add_child(hb)
	modal_btns.append({"kind": "fog_pass", "button": hb})
	if L.can_test:
		var f2 := _atk_panel(vb, "Nuclear Test", "Put your four Technologies on the table for all to see. Unlocks your Capabilities - and tells everyone what you are building.")
		var tb := _btn("Perform Nuclear Test")
		tb.pressed.connect(_act_fog_submit.bind("test"))
		f2.add_child(tb)
		modal_btns.append({"kind": "fog_test", "button": tb})
	_attack_list(vb, L, "fog")

func _trade_modal() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human or modal != null:
		return
	var vb := _open_modal("Trade offer", false, true, false)
	vb.add_child(_rtl("[b]%s[/b] offers you a face-down card in trade.\n\nAccept, and the card is yours now - but you owe them one card back on your next turn (you may deceive them, as they may deceive you). Decline, and nothing changes." % pr.from.name, 15, Color("#c3ccd6")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var y := _btn("Accept", "primary")
	y.pressed.connect(func():
		_close_modal(true)
		G.answer_trade(true)
		_after_human())
	var n := _btn("Decline")
	n.pressed.connect(func():
		_close_modal(true)
		G.answer_trade(false)
		_after_human())
	row.add_child(y)
	row.add_child(n)
	vb.add_child(row)
	modal_btns.append({"kind": "trade_yes", "button": y})
	modal_btns.append({"kind": "trade_no", "button": n})

func _counter_modal() -> void:
	var pr := G.prompt
	if pr.is_empty() or not pr.player.human or modal != null:
		return
	var vb := _open_modal("Counter-strike!", true, true, false)
	var by_txt := (" by [b]%s[/b]" % pr.by.name) if pr.by != null else ""
	vb.add_child(_rtl("You have been eliminated%s - but your Counter-strike fires. Choose who goes down with you." % by_txt, 15, Color("#c3ccd6")))
	var fl := _atk_panel(vb, "Choose a target", "")
	for id in pr.options:
		var b := _btn("Target: " + G.players[id].name, "danger")
		b.pressed.connect(_act_counter.bind(id))
		fl.add_child(b)
		modal_btns.append({"kind": "counter", "button": b})

func _peek_modal() -> void:
	var vb := _open_modal("Superpower - game paused", false, false, true)
	_close_btn(vb, "Resume")
	vb.add_child(_lbl("You examine every hand. The AIs cannot see yours.", 15, C_MUT))
	for o in G.others(ME):
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _sb(C_PANEL2, C_LINE, 1, 10, 10))
		var iv := VBoxContainer.new()
		iv.add_child(_lbl("%s  ·  %d in hand" % [o.name, o.hand.size()], 15, C_INK, HEAD))
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 5)
		for c in o.hand:
			fl.add_child(_tex(c.key, 52))
		if o.hand.is_empty():
			fl.add_child(_lbl("empty hand", 12, C_MUT, MONO))
		iv.add_child(fl)
		pc.add_child(iv)
		vb.add_child(pc)

func _rules_modal() -> void:
	var vb := _open_modal("How to play", false, false, G != null)
	_close_btn(vb, "Close")
	var classic: bool = (G.mode == "classic") if G != null else (str(cfg.mode) == "classic")
	var txt := "Nuclear Poker teaches the logic of nuclear deterrence. There is [b]no victory rule[/b] - play until someone is the last power standing, or everyone agrees to stop.\n\n"
	if classic:
		txt += "[color=#f2b134][b]GOAL[/b][/color]\n"
		txt += "Successfully [b]test a nuclear weapon[/b] (collect all four Technology cards), then become a [b]Nuclear Superpower[/b] (all four Capability cards).\n\n"
		txt += "[color=#f2b134][b]SET UP[/b][/color]\n"
		txt += "One 8-card set per player, plus one extra set: 3 players = 32 cards, 4 players = 40 (plus 4 Labs + 4 Plague per set with Biowar). Everyone is dealt 3 cards; the rest is the draw pile.\n\n"
		txt += "[color=#f2b134][b]YOUR TURN: DRAW OR TRADE[/b][/color]\n"
		txt += "- [b]Research[/b]: draw a card.\n"
		txt += "- [b]Trade[/b]: click a card in your hand and offer it face-down to another player. If they agree, they take your card [i]now[/i] - but they only give a card back on [i]their[/i] next turn, and they are [b]not obliged[/b] to. Trading partners can deceive!\n"
		txt += "- If the draw pile runs out you can only trade, or skip.\n\n"
		txt += "[color=#f2b134][b]NUCLEAR TEST[/b][/color]\n"
		txt += "Hold Uranium, Refinement, Warhead and Testing and put them on the table whenever you like. You only need to do this once.\n\n"
		txt += "[color=#f2b134][b]ATTACKS[/b][/color]\n"
		txt += "- [b]Short range[/b] (after a test): eliminate a player sitting immediately to your left or right.\n"
		txt += "- [b]Long range[/b] (needs Short): eliminate anyone at the table.\n"
		txt += "- [b]Counter-strike[/b] (the sheet's Second Strike; needs Short + Long): when you are eliminated, you immediately eliminate one player in retaliation.\n"
		txt += "- [b]Superpower[/b] (all four Capabilities + a test): strike several countries.\n"
		txt += "- Anyone can attack [b]out of turn[/b]. Here, nuclear exchanges follow the sheet's house rule - declared in [b]order of play[/b]: after every turn, starting with the player who just moved and going clockwise, each player may declare a test or an attack, or stand down. After any action the order starts again.\n\n"
		txt += "[color=#f2b134][b]THE TABLE MAP[/b][/color]\n"
		txt += "[b]Solid amber[/b] lines join neighbours - Short range reaches them. [b]Dashed[/b] lines join players across the table - only Long range reaches them. With 3 players everybody is a neighbour. When a player is eliminated the gap closes and the players either side become neighbours.\n\n"
		txt += "[color=#f2b134][b]NOTES[/b][/color]\n"
		txt += "- An attack shows (and locks on the table) the Capabilities it needs. An eliminated player's hand is revealed and set aside.\n"
		txt += "- [b]Biowar[/b]: [b]Labs[/b] protect you from [b]Plague[/b]; a Plague attack eliminates all players without Labs. In [b]2000[/b] you need a test and all 4 Capabilities first; in [b]2035[/b] you just show Labs and play it."
		vb.add_child(_rtl(txt, 15, Color("#c3ccd6")))
		var strip0 := HFlowContainer.new()
		strip0.add_theme_constant_override("h_separation", 6)
		for k0 in ORDER:
			strip0.add_child(_tex(k0, 56))
		vb.add_child(strip0)
		return
	txt += "[color=#f2b134][b]YOUR TURN[/b][/color]\n"
	txt += "- [b]Research[/b]: draw a card. [b]Proliferation[/b]: give a card from your hand to another player. [b]Disarmament[/b]: return a card to the deck. (Click a card in your hand to give or return it.)\n"
	txt += "- Then the [b]WAR rules[/b] decide what else you can do. [b]Slow[/b]: after your play action you may do nothing, a Nuclear Test, or an Attack. [b]Fog[/b]: after each turn everyone secretly picks an order and all resolve at once. [b]Fast[/b]: anyone may Test or Attack at any time, in real time.\n\n"
	txt += "[color=#f2b134][b]CARDS[/b][/color]\n"
	txt += "- [b]Technologies[/b] (grey): hold all four different - Uranium, Refinement, Warhead, Testing - and put them on the table to perform a [b]Nuclear Test[/b]. You must test before any nuclear Attack.\n"
	txt += "- [b]Short-range[/b]: after a Test, eliminate a neighboring player. [b]Long-range[/b] (needs Short): eliminate any player. [b]Counter-strike[/b] (needs Short + Long): when you are eliminated, immediately eliminate one player. [b]Superpower[/b] (needs all 4 Capabilities): attack any player at any time - and in Fast mode, pause the game and examine everyone's hands.\n"
	txt += "- Capabilities stay hidden until you use them; afterwards you keep and display them. You may also [b]reveal[/b] a card from your hand as a deterrent - or hold back to bluff.\n"
	txt += "- [b]Biowar[/b]: [b]Labs[/b] protect you from [b]Plague[/b]; a Plague attack eliminates all players without Labs. In [b]2000[/b] you need a Nuclear Test and all 4 Capabilities first; in [b]2035[/b] you just show Labs and play it.\n\n"
	txt += "[color=#f2b134][b]RULES AS IMPLEMENTED HERE[/b][/color]\n"
	txt += "- A turn is one play action, then the WAR step. 3 players = 4 sets of 8 cards (plus 4 Labs + 4 Plague with Biowar). Everyone starts with 3 cards.\n"
	txt += "- Cards on the table (tested Technologies, Capabilities used in an attack) are locked and public. An attack shows the Capabilities it requires.\n"
	txt += "- In Fog, a Test and an Attack can't happen in the same round - an attack needs a Test already on the table at the start of the round. Simultaneous attacks all land, even from players who die that round.\n"
	txt += "- An eliminated player's hand is revealed and set aside. Returned cards are shuffled into the draw pile at a random position.\n"
	txt += "- \"Neighbors\" are the nearest living players on either side of you."
	vb.add_child(_rtl(txt, 15, Color("#c3ccd6")))
	var strip := HFlowContainer.new()
	strip.add_theme_constant_override("h_separation", 6)
	for k in ORDER:
		strip.add_child(_tex(k, 56))
	vb.add_child(strip)

# ====================================================================== end
func _finish() -> void:
	fast_tok.clear()
	if end_shown:
		return
	end_shown = true
	await get_tree().create_timer(1.1 / speed).timeout
	if G != null and G.over:
		_end_modal()

func _end_modal() -> void:
	var r := G.result
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
	elif alive.size() == G.players.size():
		title = "Deterrence held"
		sub = "Nobody died. That is the only winning move."
		good = true
	else:
		title = "Stand-down"
		sub = "%d of %d powers survive." % [alive.size(), G.players.size()]
	var vb := _open_modal(title, not good, true, false)
	vb.add_child(_lbl("%s  (%d round%s)" % [sub, G.round_no, "" if G.round_no == 1 else "s"], 15, C_MUT, null, true))
	for p in G.players:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", _sb(C_PANEL2, Color("#27664a") if p.alive else Color("#6a2a25"), 1, 8, 10))
		var hb := HBoxContainer.new()
		var who := "%s%s - %s" % [p.name, " (you)" if p == ME else "", "survived" if p.alive else ("eliminated" + ((" by " + G.players[p.eliminated_by].name) if p.eliminated_by >= 0 else ""))]
		hb.add_child(_lbl(who, 15, C_INK if p.alive else Color("#e7b0aa"), null, true))
		hb.add_child(_lbl("%s%d kill%s" % ["tested · " if p.tested else "", p.kills, "" if p.kills == 1 else "s"], 12, C_MUT, MONO))
		pc.add_child(hb)
		vb.add_child(pc)
	vb.add_child(_lbl("\"The only winning move is not to play.\"", 14, C_AMBER, MONO))
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

# ====================================================================== effects
func _fx(text: String, kind: String) -> void:
	var col: Color = {"test": Color("#ffe08a"), "attack": Color("#ff7a70"), "death": Color("#ff4a40")}[kind]
	var root := Control.new()
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
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if popup != null:
			_close_popup()
		elif modal != null and not modal_sticky:
			_close_modal()

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
	var runs := [["classic", "off", "3"], ["classic", "off", "4"], ["classic", "2035", "3"], ["classic", "2000", "4"], ["classic", "off", "4"]]
	var bad := 0
	for run in runs:
		cfg.mode = run[0]
		cfg.bio = run[1]
		cfg.players = run[2]
		_start_game()
		var acts := {"research": 0, "offer": 0, "trade_yes": 0, "trade_no": 0, "honour": 0, "renege": 0, "test": 0, "attack": 0, "stand": 0, "counter": 0, "skip": 0, "declined": 0}
		var iter := 0
		var shot_taken := false
		while iter < 6000:
			iter += 1
			await get_tree().create_timer(0.02).timeout
			if G == null or G.over and modal != null and not modal_btns.is_empty() and modal_btns[0].kind == "again":
				break
			var handled := false
			for mb in modal_btns:
				if not is_instance_valid(mb.button) or mb.button.disabled:
					continue
				if mb.kind == "counter":
					mb.button.pressed.emit()
					acts.counter += 1
					handled = true
					break
				if mb.kind == "trade_yes" or mb.kind == "trade_no":
					var want := "trade_yes" if randf() < 0.55 else "trade_no"
					for mb2 in modal_btns:
						if mb2.kind == want:
							mb2.button.pressed.emit()
							acts[want] += 1
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
			# honour a trade, or deceive
			if btn.has("renege") and is_instance_valid(btn.renege):
				if randf() < 0.4:
					btn.renege.pressed.emit()
					acts.renege += 1
				else:
					var hc0 := _first_hand_card()
					if hc0 != null:
						hc0.picked.emit(hc0.cid, hc0)
						await get_tree().process_frame
						await get_tree().process_frame
						if _popup_press("GIVE"):
							acts.honour += 1
						else:
							_close_popup()
				continue
			# exchange window
			if btn.has("stand") and is_instance_valid(btn.stand):
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
					await _shot("%s/%s-%s-%s-board.png" % [out_dir, run[0], run[1], run[2]])
				if randf() < 0.3 and not ME.hand.is_empty():
					var hc := _first_hand_card()
					if hc != null:
						var before := G.log_entries.size()
						hc.picked.emit(hc.cid, hc)
						await get_tree().process_frame
						await get_tree().process_frame
						if _popup_press("OFFER"):
							acts.offer += 1
						else:
							_close_popup()
						continue
				if not btn.research.disabled:
					btn.research.pressed.emit()
					acts.research += 1
		var title := "(no end)"
		if G != null and G.over:
			await get_tree().create_timer(0.3).timeout
			title = G.result.kind
			await _shot("%s/%s-%s-%s-end.png" % [out_dir, run[0], run[1], run[2]])
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

func _stage(np: String, bio: String, mine: Array, tested: bool) -> void:
	cfg.mode = "classic"
	cfg.bio = bio
	cfg.players = np
	cfg.p1 = "hawk"
	cfg.p2 = "dove"
	cfg.p3 = "wild"
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
	G.trade_tried = false
	G.war_queue = []
	G.debts = []
	G.int_checked = true
	G.log_entries.clear()
	log_shown = 0
	logbox.clear()
	G.log_msg("Staged position for screenshots.", "sys")
	_render()
	await get_tree().create_timer(0.5).timeout

func _shots() -> void:
	var d := "/tmp/gshots2"
	DirAccess.make_dir_recursive_absolute(d)
	await get_tree().process_frame
	await _shot(d + "/0-menu.png")
	await _stage("4", "off", ["uranium", "refinement", "warhead", "testing", "short", "long"], false)
	await _shot(d + "/1-board4.png")
	var hc := _first_hand_card()
	if hc != null:
		_card_menu(hc.cid, hc)
		await get_tree().create_timer(0.4).timeout
		await _shot(d + "/2-offer-popup.png")
		_close_popup()
	await _stage("3", "off", ["uranium", "refinement", "warhead", "testing", "short", "long", "counter"], false)
	await _shot(d + "/3-board3.png")
	G.do_test(ME)
	G.phase = "war"
	G._rebuild_war_queue(0)
	_render()
	await get_tree().create_timer(0.4).timeout
	await _shot(d + "/4-war.png")
	_attack_modal("turn")
	await get_tree().create_timer(0.6).timeout
	await _shot(d + "/5-attack.png")
	_close_modal(true)
	# a trade offer from an AI, and a debt to honour
	await _stage("4", "off", ["uranium", "short"], false)
	G.turn = 1
	var offered = G.players[1].hand[0]
	G.prompt = {"type": "trade", "player": ME, "from": G.players[1], "card_id": offered.id}
	_trade_modal()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/6-trade-offer.png")
	_close_modal(true)
	G.prompt = {}
	G.debts = [{"from": 2, "to": 0, "got": 0}]
	G.turn = 0
	G.phase = "honour"
	_render()
	await get_tree().create_timer(0.5).timeout
	await _shot(d + "/7-honour.png")
	_rules_modal()
	await get_tree().create_timer(0.6).timeout
	await _shot(d + "/8-rules.png")
	print("SHOTS DONE")
	get_tree().quit(0)
