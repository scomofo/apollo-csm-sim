## Desktop cockpit overlay: DSKY, crew switches, flight and systems data,
## Mission Control (PAD requests), CAPCOM log and the flight-plan checklist.
## Controls publish ctl.* channels on the Bus; displays read the Bus.
class_name Hud
extends CanvasLayer

const HELP := """KEYS
W/S A/D Q/E   RHC pitch / yaw / roll (Shift = fine)
Arrows, R/F   THC  Y/Z, and +X/-X (ullage)
0-9 + -       DSKY digits (top row or keypad)
V  N  Enter   VERB  NOUN  ENTR
Space  Bksp   PRO   CLR
Insert  Del   KEY REL  RSET
T             SPS THRUST ON (hold, manual backup)
[  ]  P       time rate slower / faster, pause
C             window / chase / cabin view   (right-drag: look)
Cabin view    click a control, scroll to move it; right-click: mouse look,
              Z: inspect, Home: recentre, M: wrist menu
F5 / F9       save / load checkpoint
H             this help"""

var rt: SimRuntime
var mono: Font
var dsky_panel: DskyPanel
var _flight: Label
var _systems: Label
var _top: Label
var _capcom: RichTextLabel
var _check_title: OptionButton
var _check_text: RichTextLabel
var _help: Label
var _fdai: Control
## The checklists and which one is open, shared with the cabin's card and
## the wrist menu.
var book: ChecklistBook
var _switches: PanelContainer
var _flight_panel: PanelContainer
var _systems_panel: PanelContainer
var _toggles: Dictionary = {}
var _options: Dictionary = {}
var _capcom_lines: PackedStringArray = []


func setup(p_rt: SimRuntime, p_book: ChecklistBook = null) -> void:
	rt = p_rt
	book = p_book if p_book != null else ChecklistBook.load_default()
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "Courier New", "monospace"])
	mono = sf
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Top bar.
	_top = _label(root, 15)
	_top.position = Vector2(12, 6)
	# Left column: DSKY + checklist.
	var left := VBoxContainer.new()
	left.position = Vector2(10, 34)
	root.add_child(left)
	dsky_panel = DskyPanel.new()
	_style(dsky_panel)
	dsky_panel.setup(rt.agc().dsky, mono)
	left.add_child(dsky_panel)
	left.add_child(_checklist_panel())
	# Right column: flight data, FDAI, systems, switches, Mission Control.
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -430
	right.offset_right = -10
	right.offset_top = 34
	root.add_child(right)
	var fp := PanelContainer.new()
	_style(fp)
	right.add_child(fp)
	_flight_panel = fp
	var fh := HBoxContainer.new()
	fp.add_child(fh)
	_flight = _label(fh, 13)
	_flight.custom_minimum_size = Vector2(250, 0)
	_fdai = preload("res://src/presentation/fdai.gd").new()
	_fdai.custom_minimum_size = Vector2(150, 150)
	fh.add_child(_fdai)
	var sp := PanelContainer.new()
	_style(sp)
	right.add_child(sp)
	_systems_panel = sp
	_systems = _label(sp, 12)
	_switches = _switch_panel()
	right.add_child(_switches)
	right.add_child(_mcc_panel())
	# CAPCOM strip along the bottom.
	var cp := PanelContainer.new()
	_style(cp)
	cp.anchor_top = 1.0
	cp.anchor_bottom = 1.0
	cp.anchor_right = 1.0
	cp.offset_top = -92
	cp.offset_left = 470
	cp.offset_right = -450
	cp.offset_bottom = -8
	root.add_child(cp)
	_capcom = RichTextLabel.new()
	_capcom.scroll_following = true
	_capcom.bbcode_enabled = true
	_capcom.add_theme_font_size_override("normal_font_size", 13)
	cp.add_child(_capcom)
	# Help overlay.
	_help = _label(root, 14)
	_help.text = HELP
	_help.position = Vector2(480, 60)
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0, 0, 0, 0.8)
	hb.set_content_margin_all(12)
	_help.add_theme_stylebox_override("normal", hb)
	_help.visible = true
	rt.sequencer.capcom.connect(_on_capcom)
	var last = Bus.get_value("mission.capcom")
	if last != null:
		_capcom_lines.append(str(last))
		_capcom.text = str(last)


## Open the checklist that fits the flight phase.
func select_checklist_for(phase: String) -> void:
	book.select_for_phase(phase)
	_check_title.selected = book.current


func toggle_help() -> void:
	_help.visible = not _help.visible


## The cabin view has its own DSKY, FDAI, switches and readouts: the 2D
## panels step aside, and the checklist, Mission Control and CAPCOM stay
## until they move to the wrist menu (docs/ROADMAP.md, slice 2d).
func set_cabin_view(on: bool) -> void:
	for p in [dsky_panel, _flight_panel, _systems_panel, _switches]:
		p.visible = not on


func _style(p: PanelContainer) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.1, 0.82)
	sb.border_color = Color(0.35, 0.37, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)


func _label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", mono)
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _on_capcom(text: String) -> void:
	_capcom_lines.append("[color=#8fd]%s[/color]  %s" % [Units.hms(SimClock.get_seconds), text])
	while _capcom_lines.size() > 30:
		_capcom_lines.remove_at(0)
	_capcom.text = "\n".join(_capcom_lines)


# --- switches -------------------------------------------------------------------

func _switch_panel() -> PanelContainer:
	var p := PanelContainer.new()
	_style(p)
	var g := GridContainer.new()
	g.columns = 3
	p.add_child(g)
	_toggle(g, "ΔV THRUST A", "ctl.sps.arm_a")
	_toggle(g, "ΔV THRUST B", "ctl.sps.arm_b")
	var thrust := Button.new()
	thrust.text = "THRUST ON"
	thrust.focus_mode = Control.FOCUS_NONE
	thrust.button_down.connect(func() -> void: Bus.set_value("ctl.sps.thrust_on", true))
	thrust.button_up.connect(func() -> void: Bus.set_value("ctl.sps.thrust_on", false))
	g.add_child(thrust)
	_option(g, "ATT SOURCE", "ctl.scs.att_source", ["CMC", "SCS", "DIRECT"])
	_option(g, "CMC MODE", "ctl.cmc.mode", ["FREE", "HOLD", "AUTO"])
	g.add_child(Control.new())
	for q in ["a", "b", "c", "d"]:
		_toggle(g, "RCS QUAD " + q.to_upper(), "ctl.rcs.quad_" + q)
	_toggle(g, "FC 1", "ctl.eps.fc1")
	_toggle(g, "FC 2", "ctl.eps.fc2")
	_toggle(g, "FC 3", "ctl.eps.fc3")
	_toggle(g, "BATT TO BUS", "ctl.eps.batt_bus")
	_toggle(g, "ELS LOGIC", "ctl.els.logic")
	_toggle(g, "ELS AUTO", "ctl.els.auto")
	_momentary(g, "DROGUE", "ctl.els.drogue")
	_momentary(g, "MAIN CHUTES", "ctl.els.main")
	_momentary(g, "CSM/LV SEP", "ctl.seq.csm_sep")
	_momentary(g, "LM JETT", "ctl.seq.lm_jett")
	_momentary(g, "CM/SM SEP", "ctl.seq.cm_sm_sep")
	return p


func _toggle(parent: Node, text: String, ch: String) -> void:
	var b := CheckButton.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.button_pressed = bool(Bus.get_value(ch, false))
	b.toggled.connect(func(on: bool) -> void: Bus.set_value(ch, on))
	parent.add_child(b)
	_toggles[ch] = b


func _momentary(parent: Node, text: String, ch: String) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.button_down.connect(func() -> void: Bus.set_value(ch, true))
	b.button_up.connect(func() -> void: Bus.set_value(ch, false))
	parent.add_child(b)


func _option(parent: Node, text: String, ch: String, items: Array) -> void:
	var box := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	box.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for it in items:
		o.add_item(it)
	o.selected = int(Bus.get_value(ch, 0))
	o.item_selected.connect(func(i: int) -> void: Bus.set_value(ch, i))
	box.add_child(o)
	parent.add_child(box)
	_options[ch] = o


func _mcc_panel() -> PanelContainer:
	var p := PanelContainer.new()
	_style(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var t := Label.new()
	t.text = "MISSION CONTROL - request PAD uplink"
	t.add_theme_font_size_override("font_size", 11)
	v.add_child(t)
	var h := HBoxContainer.new()
	v.add_child(h)
	for pair in [["MCC", "mcc"], ["LOI-1", "loi"], ["LOI-2", "circ"], ["TEI", "tei"]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		var kind: String = pair[1]
		b.pressed.connect(func() -> void: Bus.set_value("ctl.ground.pad_request", kind))
		h.add_child(b)
	return p


# --- checklist ------------------------------------------------------------------

func _checklist_panel() -> PanelContainer:
	var p := PanelContainer.new()
	_style(p)
	p.custom_minimum_size = Vector2(440, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	_check_title = OptionButton.new()
	_check_title.focus_mode = Control.FOCUS_NONE
	for c in book.lists:
		_check_title.add_item(c.title)
	_check_title.item_selected.connect(book.select)
	h.add_child(_check_title)
	var nb := Button.new()
	nb.text = "Next"
	nb.focus_mode = Control.FOCUS_NONE
	nb.pressed.connect(book.next)
	h.add_child(nb)
	_check_text = RichTextLabel.new()
	_check_text.fit_content = true
	_check_text.bbcode_enabled = true
	_check_text.custom_minimum_size = Vector2(420, 150)
	_check_text.add_theme_font_size_override("normal_font_size", 12)
	v.add_child(_check_text)
	return p


func _checklist_text() -> String:
	if book.list() == null:
		return ""
	book.update()
	var lines := PackedStringArray()
	for s in book.window():
		var mark := "[color=#6c6]✓[/color] " if s["state"] == "done" else ("[color=#fd4]▶[/color] " if s["state"] == "current" else "   ")
		var auto := " [color=#888](Next)[/color]" if s["state"] == "current" and s["manual"] else ""
		lines.append(mark + str(s["text"]) + auto)
	if book.list().done():
		lines.append("[color=#6c6]Checklist complete.[/color]")
	return "\n".join(lines)


# --- per frame --------------------------------------------------------------------

func _process(_delta: float) -> void:
	if rt == null:
		return
	var primary := str(Bus.get_value("dyn.primary", "earth"))
	_top.text = "APOLLO 11  GET %s   %s   rate x%s%s   %s" % [SimClock.get_display(),
		str(Bus.get_value("mission.phase", "")).to_upper().replace("_", " "),
		str(int(SimClock.rate)), "  PAUSED" if SimClock.paused else "",
		"[controls locked]" if SimClock.controls_locked() else ""]
	var nm := Units.NMI
	var ft := Units.FT
	var apo := float(Bus.get_value("dyn.apo_alt_m", 0.0))
	var q: Quaternion = Bus.get_value("dyn.att_q", Quaternion.IDENTITY)
	var gim := Agc.gimbal_angles(q)
	var w: Vector3 = Bus.get_value("dyn.omega", Vector3.ZERO)
	_flight.text = """REF %s   CONFIG %s
ALT     %9.1f nmi
VEL     %9.0f ft/s
HDOT    %+9.0f ft/s
HA      %9s nmi
HP      %9.1f nmi
EARTH   %9.0f nmi
MOON    %9.0f nmi
MASS    %9.0f lb
G       %9.2f
ATT R/P/Y %06.2f %06.2f %06.2f
RATE  %+.2f %+.2f %+.2f °/s""" % [
		primary.to_upper(), str(Bus.get_value("dyn.config", "")).to_upper(),
		float(Bus.get_value("dyn.alt_m", 0.0)) / nm,
		float(Bus.get_value("dyn.speed_mps", 0.0)) / ft,
		float(Bus.get_value("dyn.alt_rate_mps", 0.0)) / ft,
		"UNBOUND" if apo == INF else "%.1f" % (apo / nm),
		float(Bus.get_value("dyn.peri_alt_m", 0.0)) / nm,
		float(Bus.get_value("dyn.earth_dist_m", 0.0)) / nm,
		float(Bus.get_value("dyn.moon_dist_m", 0.0)) / nm,
		Units.kg_to_lb(float(Bus.get_value("dyn.mass_kg", 0.0))),
		float(Bus.get_value("dyn.g_load", 0.0)),
		gim.x, gim.y, gim.z, rad_to_deg(w.x), rad_to_deg(w.y), rad_to_deg(w.z)]
	var o2 := float(Bus.get_value("eps.o2_tank1_kg", 0.0)) + float(Bus.get_value("eps.o2_tank2_kg", 0.0))
	var fc := PackedStringArray()
	for n in 3:
		var ok := bool(Bus.get_value("eps.fc%d_ok" % (n + 1), true))
		fc.append("%d:%s" % [n + 1, "%.2fkW" % float(Bus.get_value("eps.fc%d_kw" % (n + 1), 0.0)) if ok else "FAIL"])
	_systems.text = """SPS  %6.0f lb  PC %3.0f%%  %s   ignitions %d
RCS  A %3.0f  B %3.0f  C %3.0f  D %3.0f lb   CM %3.0f lb
EPS  MAIN A %4.1f V  B %4.1f V  load %4.0f W
FC   %s
CRYO O2 T1 %5.1f T2 %5.1f lb   H2 %4.1f lb
BAT  A %4.1f  B %4.1f  C %4.1f Ah   %s
CMC  P%02d %s  VG %.1f ft/s  %s""" % [
		Units.kg_to_lb(float(Bus.get_value("sps.prop_kg", 0.0))), float(Bus.get_value("sps.chamber_pct", 0.0)),
		"FIRING" if bool(Bus.get_value("sps.on", false)) else "", int(Bus.get_value("sps.ignitions", 0)),
		Units.kg_to_lb(float(Bus.get_value("rcs.quad_a_kg", 0.0))), Units.kg_to_lb(float(Bus.get_value("rcs.quad_b_kg", 0.0))),
		Units.kg_to_lb(float(Bus.get_value("rcs.quad_c_kg", 0.0))), Units.kg_to_lb(float(Bus.get_value("rcs.quad_d_kg", 0.0))),
		Units.kg_to_lb(float(Bus.get_value("rcs.cm_prop_kg", 0.0))),
		float(Bus.get_value("eps.bus_a_v", 0.0)), float(Bus.get_value("eps.bus_b_v", 0.0)), float(Bus.get_value("eps.load_w", 0.0)),
		"  ".join(fc),
		Units.kg_to_lb(float(Bus.get_value("eps.o2_tank1_kg", 0.0))), Units.kg_to_lb(float(Bus.get_value("eps.o2_tank2_kg", 0.0))),
		Units.kg_to_lb(float(Bus.get_value("eps.h2_tank1_kg", 0.0)) + float(Bus.get_value("eps.h2_tank2_kg", 0.0))),
		float(Bus.get_value("eps.batt_a_ah", 0.0)), float(Bus.get_value("eps.batt_b_ah", 0.0)), float(Bus.get_value("eps.batt_c_ah", 0.0)),
		"MASTER ALARM" if bool(Bus.get_value("sys.master_alarm.eps", false)) else "",
		int(Bus.get_value("guid.program", 0)), str(Bus.get_value("guid.step", "")),
		float(Bus.get_value("guid.vg_mps", 0.0)) / ft,
		"MNVR LOADED TIG " + Units.hms(float(Bus.get_value("guid.maneuver_tig", 0.0))) if bool(Bus.get_value("guid.maneuver_valid", false)) else ""]
	if o2 <= 0.0:
		_systems.text += "\nO2 DEPLETED"
	if _check_title.selected != book.current:
		_check_title.selected = book.current
	_check_text.text = _checklist_text()
	# Keep toggles in step with the Bus (checkpoint loads, tests).
	for ch in _toggles:
		var want := bool(Bus.get_value(ch, false))
		if _toggles[ch].button_pressed != want:
			_toggles[ch].set_pressed_no_signal(want)
	for ch in _options:
		var want := int(Bus.get_value(ch, 0))
		if _options[ch].selected != want:
			_options[ch].selected = want
