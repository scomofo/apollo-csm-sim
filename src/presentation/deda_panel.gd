## On-screen DEDA (slice 11e): the AGS's address and data windows, its
## OPR ERR light and its 16 keys, laid out as the LM's on panel 6 (the
## address above, OPR ERR beside the data, the keys + 7 8 9 CLR, - 4 5 6
## READ OUT, 0 1 2 3 ENTR, HOLD below). Clicking a key calls Ags.press();
## the windows read the AGS's lm.deda channels.
class_name DedaPanel
extends PanelContainer

const KEYS := [
	["+", "7", "8", "9", "CLR"],
	["-", "4", "5", "6", "READOUT"],
	["0", "1", "2", "3", "ENTR"],
	["", "", "HOLD", "", ""],
]
const EL_GREEN := Color(0.45, 1.0, 0.55)

## The AGS: its press() takes the keys.
var ags: Object
var _addr: Label
var _data: Label
var _err: Label


func setup(p_ags: Object, mono: Font) -> void:
	ags = p_ags
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "DEDA"
	title.add_theme_font_size_override("font_size", 11)
	box.add_child(title)
	_addr = _window(box, mono, 3)
	_addr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_err = Label.new()
	_err.text = "OPR ERR"
	_err.custom_minimum_size = Vector2(64, 28)
	_err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_err.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_err.add_theme_font_size_override("font_size", 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.2)
	bg.set_corner_radius_all(2)
	_err.add_theme_stylebox_override("normal", bg)
	row.add_child(_err)
	_data = _window(row, mono, 6)
	var kb := GridContainer.new()
	kb.columns = 5
	box.add_child(kb)
	for keys in KEYS:
		for k: String in keys:
			if k == "":
				var sp := Control.new()
				sp.custom_minimum_size = Vector2(46, 36)
				kb.add_child(sp)
				continue
			var b := Button.new()
			b.text = "READ\nOUT" if k == "READOUT" else k
			b.custom_minimum_size = Vector2(46, 36)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 10 if k.length() > 2 else 16)
			b.pressed.connect(func() -> void: press(k))
			kb.add_child(b)


## A key, as clicked: one of Deda.KEYS.
func press(key: String) -> void:
	if ags != null:
		ags.press(key)


func _window(parent: Container, mono: Font, digits: int) -> Label:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.03)
	sb.set_content_margin_all(4)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var l := Label.new()
	l.add_theme_font_override("font", mono)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", EL_GREEN)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(16 * digits + 8, 0)
	p.add_child(l)
	return l


func _process(_delta: float) -> void:
	_addr.text = str(Bus.get_value("lm.deda.addr", ""))
	_data.text = str(Bus.get_value("lm.deda.data", ""))
	var lit := bool(Bus.get_value("lm.deda.opr_err", false))
	var sb: StyleBoxFlat = _err.get_theme_stylebox("normal")
	sb.bg_color = Color(1.0, 0.75, 0.2) if lit else Color(0.2, 0.2, 0.2)
	_err.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1) if lit else Color(0.45, 0.45, 0.45))
