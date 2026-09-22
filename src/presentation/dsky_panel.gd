## On-screen DSKY: the status/caution lamps, the electroluminescent
## PROG/VERB/NOUN/R1-R3 display and the 19-key keyboard, laid out like the
## Block II main display console DSKY. Clicking a key calls Dsky.press();
## the panel only renders the Dsky's state.
class_name DskyPanel
extends PanelContainer

const KEYS := [
	["VERB", "+", "7", "8", "9", "CLR", "ENTR"],
	["NOUN", "-", "4", "5", "6", "PRO", "RSET"],
	["", "0", "1", "2", "3", "KEY REL", ""],
]
const LAMP_ROWS := [["uplink_acty", "temp"], ["no_att", "gimbal_lock"], ["stby", "prog"],
	["key_rel", "restart"], ["opr_err", "tracker"]]
const LAMP_AMBER := ["temp", "gimbal_lock", "prog", "restart", "tracker"]
const EL_GREEN := Color(0.45, 1.0, 0.55)

var dsky: Dsky
var _lamps: Dictionary = {}
var _prog: Label
var _verb: Label
var _noun: Label
var _r: Array[Label] = []
var _comp: ColorRect
var _blink: float = 0.0


func setup(p_dsky: Dsky, mono: Font) -> void:
	dsky = p_dsky
	var box := VBoxContainer.new()
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	# Lamps.
	var lamps := GridContainer.new()
	lamps.columns = 2
	top.add_child(lamps)
	for row in LAMP_ROWS:
		for l in row:
			var lab := Label.new()
			lab.text = l.replace("_", " ").to_upper()
			lab.custom_minimum_size = Vector2(92, 24)
			lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lab.add_theme_font_size_override("font_size", 10)
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(0.2, 0.2, 0.2)
			bg.set_corner_radius_all(2)
			lab.add_theme_stylebox_override("normal", bg)
			lamps.add_child(lab)
			_lamps[l] = lab
	# EL display.
	var el := PanelContainer.new()
	var elbg := StyleBoxFlat.new()
	elbg.bg_color = Color(0.03, 0.05, 0.03)
	elbg.set_content_margin_all(6)
	el.add_theme_stylebox_override("panel", elbg)
	top.add_child(el)
	var col := VBoxContainer.new()
	el.add_child(col)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	col.add_child(row1)
	var comp_box := VBoxContainer.new()
	row1.add_child(comp_box)
	var ct := Label.new()
	ct.text = "COMP ACTY"
	ct.add_theme_font_size_override("font_size", 9)
	ct.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
	comp_box.add_child(ct)
	_comp = ColorRect.new()
	_comp.custom_minimum_size = Vector2(48, 26)
	comp_box.add_child(_comp)
	_prog = _el_field(row1, "PROG", mono)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	col.add_child(row2)
	_verb = _el_field(row2, "VERB", mono)
	_noun = _el_field(row2, "NOUN", mono)
	for i in 3:
		var lab := Label.new()
		lab.add_theme_font_override("font", mono)
		lab.add_theme_font_size_override("font_size", 24)
		lab.add_theme_color_override("font_color", EL_GREEN)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lab.custom_minimum_size = Vector2(130, 0)
		col.add_child(lab)
		_r.append(lab)
	# Keyboard.
	var kb := GridContainer.new()
	kb.columns = 7
	box.add_child(kb)
	for row in KEYS:
		for k in row:
			if k == "":
				var sp := Control.new()
				sp.custom_minimum_size = Vector2(46, 38)
				kb.add_child(sp)
				continue
			var b := Button.new()
			b.text = k
			b.custom_minimum_size = Vector2(46, 38)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 11 if k.length() > 2 else 16)
			b.pressed.connect(func() -> void: dsky.press(k))
			kb.add_child(b)


func _el_field(parent: Container, title: String, mono: Font) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 9)
	t.add_theme_color_override("font_color", Color(0.3, 0.8, 0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var v := Label.new()
	v.add_theme_font_override("font", mono)
	v.add_theme_font_size_override("font_size", 24)
	v.add_theme_color_override("font_color", EL_GREEN)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(48, 0)
	box.add_child(v)
	return v


func _process(delta: float) -> void:
	if dsky == null:
		return
	_blink = fmod(_blink + delta, 1.2)
	var on := _blink < 0.8
	var powered := bool(Bus.get_value("sys.powered", true))
	_prog.text = dsky.prog if powered else ""
	_verb.text = dsky.verb if (powered and (not dsky.flashing or on)) else ""
	_noun.text = dsky.noun if (powered and (not dsky.flashing or on)) else ""
	for i in 3:
		_r[i].text = dsky.r[i] if powered else ""
	_comp.color = Color(0.45, 1.0, 0.55) if powered and dsky.mode != "" else Color(0.05, 0.1, 0.05)
	for l in _lamps:
		var lit: bool = dsky.lamps.get(l, false)
		var sb: StyleBoxFlat = _lamps[l].get_theme_stylebox("normal")
		var lit_col := Color(1.0, 0.75, 0.2) if l in LAMP_AMBER else Color(0.95, 0.95, 0.9)
		sb.bg_color = lit_col if lit else Color(0.2, 0.2, 0.2)
		_lamps[l].add_theme_color_override("font_color", Color(0.1, 0.1, 0.1) if lit else Color(0.45, 0.45, 0.45))
