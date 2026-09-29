## Desktop cockpit overlay: DSKY, crew switches, flight and systems data,
## Mission Control (PAD requests), CAPCOM log and the flight-plan checklist.
## Controls publish ctl.* channels on the Bus; displays read the Bus.
##
## Flying the LM (set_vehicle("lm")) it is Eagle's: the LGC's DSKY, the
## LM's switches (the LGC's mode, ENGINE ARM, ABORT STAGE, ENGINE START and
## STOP, the RCS systems and the ROD switch), its flight data and systems,
## its checklists, and the FDAI on its attitude [simplified: an overlay,
## not the LM's panels].
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
L             fly the LM / the CSM, while the LM flies free
[  ]  P       time rate slower / faster, pause
C             window / chase / cabin view   (right-drag: look)
Cabin view    click a control, scroll to move it; right-click: mouse look,
              Z: inspect, Home: recentre, M: wrist menu
O             the optics (sextant and telescope): W/S A/D move them,
              X MARK, Y MARK REJECT
F5 / F9       quick save / back to it (the flight menu's SAVES lists it)
F1            the flight menu: another mission or start phase, saved flights
H             this help"""

var rt: SimRuntime
var mono: Font
var dsky_panel: DskyPanel
## The LGC's DSKY, shown in place of the CMC's while the player flies the
## LM.
var lgc_panel: DskyPanel
## "csm" or "lm": the vehicle the panels are for.
var vehicle: String = "csm"
## The checklists the panel shows: Columbia's (csm_book), shared with the
## cabin's card and the wrist menu, or, flying the LM, Eagle's (lm_book).
## Both keep up with the Bus whichever shows.
var book: ChecklistBook
var csm_book: ChecklistBook
var lm_book: ChecklistBook
var _flight: Label
var _systems: Label
var _top: Label
var _capcom: RichTextLabel
var _check_title: OptionButton
var _check_text: RichTextLabel
var _help: Label
var _fdai: Fdai
var _switches: PanelContainer
var _lm_switches: PanelContainer
var _mcc: PanelContainer
var _lm_mcc: PanelContainer
var _flight_panel: PanelContainer
var _systems_panel: PanelContainer
## The optics: their view and their controls (toggle_optics()).
var _optics: PanelContainer
var optics_view: OpticsView
var _in_cabin: bool = false
var _toggles: Dictionary = {}
var _options: Dictionary = {}
var _capcom_lines: PackedStringArray = []


func setup(p_rt: SimRuntime, p_book: ChecklistBook = null, p_lm_book: ChecklistBook = null) -> void:
	rt = p_rt
	csm_book = p_book if p_book != null else ChecklistBook.load_default(rt.mission.id())
	lm_book = p_lm_book if p_lm_book != null else ChecklistBook.load_lm(rt.mission.id())
	book = csm_book
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
	lgc_panel = DskyPanel.new()
	_style(lgc_panel)
	lgc_panel.setup(rt.lgc().dsky, mono)
	left.add_child(lgc_panel)
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
	_fdai = Fdai.new()
	_fdai.custom_minimum_size = Vector2(150, 150)
	fh.add_child(_fdai)
	var sp := PanelContainer.new()
	_style(sp)
	right.add_child(sp)
	_systems_panel = sp
	_systems = _label(sp, 12)
	_switches = _switch_panel()
	right.add_child(_switches)
	_lm_switches = _lm_switch_panel()
	right.add_child(_lm_switches)
	_mcc = _mcc_panel([["MCC", "mcc"], ["LOI-1", "loi"], ["LOI-2", "circ"], ["TEI", "tei"], ["SV", "sv"]])
	right.add_child(_mcc)
	_lm_mcc = _mcc_panel([["DOI", "doi"], ["PDI", "pdi"], ["ASCENT", "ascent"], ["CSI", "csi"]])
	right.add_child(_lm_mcc)
	# The optics, over the middle of the screen when opened.
	_optics = _optics_panel()
	_optics.anchor_left = 0.5
	_optics.anchor_right = 0.5
	_optics.offset_left = -290
	_optics.offset_right = 290
	_optics.offset_top = 34
	_optics.visible = false
	root.add_child(_optics)
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
	# The HUD lives for the whole app run (created once in main.gd), so this
	# relies on Godot 4's automatic signal disconnect when the node is freed
	# at exit; no _exit_tree disconnect needed.
	rt.sequencer.capcom.connect(_on_capcom)
	var last = Bus.get_value("mission.capcom")
	if last != null:
		_capcom_lines.append(str(last))
		_capcom.text = str(last)
	set_vehicle(str(Bus.get_value("player.vehicle", "csm")))


## Open the checklist that fits the flight phase, in the book the panel
## shows.
func select_checklist_for(phase: String) -> void:
	book.select_for_phase(phase)
	_check_title.selected = book.current


func toggle_help() -> void:
	_help.visible = not _help.visible


## Open or close the optics: while they are open the rotation keys move
## them (player.optics, src/interaction/hand_controller_input.gd). Only
## from Columbia.
func toggle_optics(on: Variant = null) -> void:
	var want: bool = (not _optics.visible) if on == null else bool(on)
	_optics.visible = want and vehicle != "lm"
	Bus.set_value("player.optics", _optics.visible)


func optics_open() -> bool:
	return _optics.visible


## The sextant and telescope's view, their mode, zero and speed switches,
## and MARK and MARK REJECT.
func _optics_panel() -> PanelContainer:
	var p := PanelContainer.new()
	_style(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	optics_view = OpticsView.new()
	optics_view.font = mono
	optics_view.custom_minimum_size = Vector2(560, 300)
	v.add_child(optics_view)
	var h := HBoxContainer.new()
	v.add_child(h)
	_option(h, "OPTICS MODE", "ctl.optics.mode", ["MANUAL", "CMC"])
	_toggle(h, "ZERO", "ctl.optics.zero")
	_option(h, "SPEED", "ctl.optics.speed", ["LO", "MED", "HI"])
	_momentary(h, "MARK", "ctl.optics.mark")
	_momentary(h, "MARK REJECT", "ctl.optics.mark_reject")
	var names := CheckButton.new()
	names.text = "NAMES"
	names.focus_mode = Control.FOCUS_NONE
	names.add_theme_font_size_override("font_size", 11)
	names.button_pressed = optics_view.names
	names.toggled.connect(func(on: bool) -> void: optics_view.names = on)
	h.add_child(names)
	return p


## The cabin view has its own DSKY, FDAI, switches and readouts: the 2D
## panels step aside, and the checklist, Mission Control and CAPCOM stay
## until they move to the wrist menu (docs/ROADMAP.md, slice 2d).
func set_cabin_view(on: bool) -> void:
	_in_cabin = on
	_show_panels()


## Show the panels for [param v]: "csm", or "lm" for Eagle's.
func set_vehicle(v: String) -> void:
	vehicle = v
	_fdai.vehicle = v
	book = lm_book if v == "lm" else csm_book
	_fill_titles()
	_show_panels()


func _show_panels() -> void:
	var lm := vehicle == "lm"
	for p in [_flight_panel, _systems_panel]:
		p.visible = not _in_cabin
	dsky_panel.visible = not lm and not _in_cabin
	_switches.visible = not lm and not _in_cabin
	lgc_panel.visible = lm and not _in_cabin
	_lm_switches.visible = lm and not _in_cabin
	_mcc.visible = not lm
	_lm_mcc.visible = lm
	if lm and _optics.visible:
		toggle_optics(false)


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
	_toggle(g, "UP TLM CM (ACCEPT)", "ctl.cmc.up_tlm")
	g.add_child(Control.new())
	for q in ["a", "b", "c", "d"]:
		_toggle(g, "RCS QUAD " + q.to_upper(), "ctl.rcs.quad_" + q)
	_toggle(g, "FC 1", "ctl.eps.fc1")
	_toggle(g, "FC 2", "ctl.eps.fc2")
	_toggle(g, "FC 3", "ctl.eps.fc3")
	_toggle(g, "BATT TO BUS", "ctl.eps.batt_bus")
	_option(g, "CM POWER", "ctl.eps.cm_power", ["OFF", "EMER", "ALL"])
	_toggle(g, "LM PWR", "ctl.eps.lm_power")
	_toggle(g, "ELS LOGIC", "ctl.els.logic")
	_toggle(g, "ELS AUTO", "ctl.els.auto")
	_momentary(g, "DROGUE", "ctl.els.drogue")
	_momentary(g, "MAIN CHUTES", "ctl.els.main")
	_momentary(g, "CSM/LV SEP", "ctl.seq.csm_sep")
	_momentary(g, "UNDOCK", "ctl.seq.undock")
	_momentary(g, "LM JETT", "ctl.seq.lm_jett")
	_momentary(g, "CM/SM SEP", "ctl.seq.cm_sm_sep")
	_momentary(g, "MASTER ALARM", "ctl.cw.master_alarm")
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


func _momentary(parent: Node, text: String, ch: String, on: Variant = true,
		off: Variant = false) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.button_down.connect(func() -> void: Bus.set_value(ch, on))
	b.button_up.connect(func() -> void: Bus.set_value(ch, off))
	parent.add_child(b)


## Eagle's switches: the LGC's mode, the engines, staging, the RCS and the
## ROD switch; the LM's power, its PGNS and AGS, the AGS's body-axis align
## and the guidance control switch (Apollo 13's lifeboat).
func _lm_switch_panel() -> PanelContainer:
	var p := PanelContainer.new()
	_style(p)
	var g := GridContainer.new()
	g.columns = 3
	p.add_child(g)
	_option(g, "LGC MODE", "ctl.lm.mode", ["FREE", "HOLD", "AUTO"])
	_option(g, "ENG ARM", "ctl.lm.engine_arm", ["OFF", "ASC", "DES"])
	_momentary(g, "ABORT STAGE", "ctl.lm.stage")
	_momentary(g, "ENG START", "ctl.lm.eng_start")
	_momentary(g, "ENG STOP", "ctl.lm.eng_stop")
	g.add_child(Control.new())
	_toggle(g, "RCS SYS A", "ctl.lm.rcs.sys_a")
	_toggle(g, "RCS SYS B", "ctl.lm.rcs.sys_b")
	g.add_child(Control.new())
	_momentary(g, "ROD UP", "ctl.lm.rod", 1, 0)
	_momentary(g, "ROD DOWN", "ctl.lm.rod", -1, 0)
	g.add_child(Control.new())
	_toggle(g, "LM PWR", "ctl.lm.power")
	_toggle(g, "PGNS", "ctl.lm.pgns")
	_toggle(g, "AGS", "ctl.lm.ags")
	_option(g, "GUID CONT", "ctl.lm.guid_cont", ["PGNS", "AGS"])
	_momentary(g, "AGS ALIGN", "ctl.lm.ags_align")
	return p


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


## Mission Control's PAD requests, [param pads] [[label, kind], ...].
func _mcc_panel(pads: Array) -> PanelContainer:
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
	for pair in pads:
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
	_fill_titles()
	_check_title.item_selected.connect(func(i: int) -> void: book.select(i))
	h.add_child(_check_title)
	var nb := Button.new()
	nb.text = "Next"
	nb.focus_mode = Control.FOCUS_NONE
	nb.pressed.connect(func() -> void: book.next())
	h.add_child(nb)
	_check_text = RichTextLabel.new()
	_check_text.fit_content = true
	_check_text.bbcode_enabled = true
	_check_text.custom_minimum_size = Vector2(420, 150)
	_check_text.add_theme_font_size_override("normal_font_size", 12)
	v.add_child(_check_text)
	return p


## The checklist choices: the titles in the book the panel shows.
func _fill_titles() -> void:
	_check_title.clear()
	for c in book.lists:
		_check_title.add_item(c.title)
	if not book.lists.is_empty():
		_check_title.selected = book.current


func _checklist_text() -> String:
	csm_book.update()
	lm_book.update()
	if book.list() == null:
		return ""
	var lines := PackedStringArray()
	for s in book.window():
		var mark := "[color=#6c6]✓[/color] " if s["state"] == "done" else ("[color=#fd4]▶[/color] " if s["state"] == "current" else "   ")
		var auto := " [color=#888](Next)[/color]" if s["state"] == "current" and s["manual"] else ""
		lines.append(mark + str(s["text"]) + auto)
	if book.list().done():
		lines.append("[color=#6c6]Checklist complete.[/color]")
	return "\n".join(lines)


# --- per frame --------------------------------------------------------------------

## Eagle's flight data: its height over the ground below it, its speed
## over the turning surface, its orbit, the landing radar's ΔH, the
## rendezvous radar's range, and the LGC's ALT and VEL lamps and CONTACT
## LIGHT.
func _lm_flight_text() -> String:
	var ft := Units.FT
	var nm := Units.NMI
	var ra: Array = Bus.get_value("lm.dyn.r_m", [Bodies.R_MOON, 0.0, 0.0])
	var va: Array = Bus.get_value("lm.dyn.v_mps", [0.0, 0.0, 0.0])
	var r := Vector3(ra[0], ra[1], ra[2])
	var agl := INF
	var vh := 0.0
	if str(Bus.get_value("lm.dyn.primary", "moon")) == "moon":
		agl = LunarGround.height_over_ground(LunarGround.lm_moon_fixed())
		var rel := Vector3(va[0], va[1], va[2]) - Bodies.moon_omega(SimClock.get_seconds).cross(r)
		vh = (rel - r.normalized() * rel.dot(r.normalized())).length()
	var apo := float(Bus.get_value("lm.dyn.apo_alt_m", 0.0))
	var landed := bool(Bus.get_value("lm.dyn.landed", false))
	var w := Fdai.crew_axes(Bus.get_value("lm.dyn.omega", Vector3.ZERO), "lm")
	var lamps := PackedStringArray()
	for l in ["alt", "vel"]:
		if bool(Bus.get_value("lm.dsky.lamp." + l, false)):
			lamps.append(l.to_upper())
	if bool(Bus.get_value("lm.contact_light", false)):
		lamps.append("CONTACT LIGHT")
	var rr := "RR   no track"
	if bool(Bus.get_value("lm.rr.data_good", false)):
		rr = "RR   %8.2f nmi  %+7.1f ft/s" % [float(Bus.get_value("lm.rr.range_m", 0.0)) / nm,
			float(Bus.get_value("lm.rr.range_rate_mps", 0.0)) / ft]
	return """EAGLE  CONFIG %s%s
AGL     %9s ft
HDOT    %+9.1f ft/s
VH      %9.1f ft/s
HA      %9s nmi
HP      %9s nmi
MASS    %9.0f lb
RATE  %+.2f %+.2f %+.2f °/s
ΔH (LR) %+9.0f ft
%s
LAMPS %s""" % [
		str(Bus.get_value("lm.dyn.config", "lm")).to_upper(),
		"  LANDED" if landed else "",
		"%.0f" % (agl / ft) if agl != INF else "--",
		float(Bus.get_value("lm.dyn.alt_rate_mps", 0.0)) / ft, vh / ft,
		"--" if landed else "UNBOUND" if apo == INF else "%.1f" % (apo / nm),
		"--" if landed else "%.1f" % (float(Bus.get_value("lm.dyn.peri_alt_m", 0.0)) / nm),
		Units.kg_to_lb(float(Bus.get_value("lm.dyn.mass_kg", 0.0))),
		rad_to_deg(w.x), rad_to_deg(w.y), rad_to_deg(w.z),
		float(Bus.get_value("lm.guid.delta_h_m", 0.0)) / ft, rr,
		" ".join(lamps) if not lamps.is_empty() else "--"]


## Eagle's engines, RCS and LGC.
func _lm_systems_text() -> String:
	var mnvr := ""
	if bool(Bus.get_value("lm.guid.maneuver_valid", false)):
		mnvr = "MNVR LOADED TIG " + Units.hms(float(Bus.get_value("lm.guid.maneuver_tig", 0.0)))
	return """DPS  %6.0f lb  THR %3.0f%%  %s
APS  %6.0f lb  %s
RCS  A %4.0f  B %4.0f lb
LGC  P%02d %s  VG %.1f ft/s  %s""" % [
		Units.kg_to_lb(float(Bus.get_value("lm.dps.prop_kg", 0.0))),
		float(Bus.get_value("lm.dps.throttle_pct", 0.0)),
		"FIRING" if bool(Bus.get_value("lm.dps.on", false)) else "",
		Units.kg_to_lb(float(Bus.get_value("lm.aps.prop_kg", 0.0))),
		"FIRING" if float(Bus.get_value("lm.aps.thrust_n", 0.0)) > 0.0 else "",
		Units.kg_to_lb(float(Bus.get_value("lm.rcs.sys_a_kg", 0.0))),
		Units.kg_to_lb(float(Bus.get_value("lm.rcs.sys_b_kg", 0.0))),
		int(Bus.get_value("lm.guid.program", 0)), str(Bus.get_value("lm.guid.step", "")),
		float(Bus.get_value("lm.guid.vg_mps", 0.0)) / Units.FT, mnvr]


## While the LM flies free: where its docking port is from the CSM's, in
## the CSM's body axes (X along the probe), and the last contact.
func _docking_text() -> String:
	if str(Bus.get_value("dock.state", "")) != "free":
		return ""
	var p: Vector3 = Bus.get_value("dock.rel_pos", Vector3.ZERO)
	var v: Vector3 = Bus.get_value("dock.rel_vel", Vector3.ZERO)
	var text := """
LM RNG  %9.1f ft
RDOT    %+9.2f ft/s
X %+7.1f Y %+6.1f Z %+6.1f
VX %+5.2f VY %+5.2f VZ %+5.2f
MISALIGN %4.1f°""" % [
		float(Bus.get_value("dock.range_m", 0.0)) / Units.FT,
		float(Bus.get_value("dock.range_rate_mps", 0.0)) / Units.FT,
		p.x / Units.FT, p.y / Units.FT, p.z / Units.FT,
		v.x / Units.FT, v.y / Units.FT, v.z / Units.FT,
		float(Bus.get_value("dock.misalign_deg", 0.0))]
	var contact: Dictionary = Bus.get_value("dock.contact", {})
	if not contact.is_empty() and not contact["captured"]:
		text += "\n" + Docking.describe(contact)
	return text


## Through the launch: the stage burning and its engines, their thrust,
## the Mach number and the dynamic pressure.
func _launch_text() -> String:
	if str(Bus.get_value("dyn.config", "")) != "saturn_v":
		return ""
	var stage := str(Bus.get_value("lv.stage", ""))
	if bool(Bus.get_value("lv.held", false)):
		stage = "ON PAD"
	return """
STAGE   %9s  ENG %d
THRUST  %9.0f klbf
MACH    %9.2f
Q       %9.0f psf""" % [stage if stage != "" else "STAGING", int(Bus.get_value("lv.engines", 0)),
		float(Bus.get_value("lv.thrust_n", 0.0)) / (1000.0 * Units.LBF), float(Bus.get_value("lv.mach", 0.0)),
		float(Bus.get_value("lv.q_pa", 0.0)) / Units.PSF]


func _process(_delta: float) -> void:
	if rt == null:
		return
	var primary := str(Bus.get_value("dyn.primary", "earth"))
	_top.text = "APOLLO 11  GET %s   %s   %s   rate x%s%s   %s" % [SimClock.get_display(),
		str(Bus.get_value("mission.phase", "")).to_upper().replace("_", " "),
		"EAGLE" if vehicle == "lm" else "COLUMBIA",
		str(int(SimClock.rate)), "  PAUSED" if SimClock.paused else "",
		"[controls locked]" if SimClock.controls_locked() else ""]
	_sync_controls()
	if vehicle == "lm":
		_flight.text = _lm_flight_text()
		_systems.text = _lm_systems_text()
		return
	var nm := Units.NMI
	var ft := Units.FT
	var apo := float(Bus.get_value("dyn.apo_alt_m", 0.0))
	var gim: Vector3 = Bus.get_value("imu.icdu_deg", Vector3.ZERO)
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
	_flight.text += _docking_text()
	_flight.text += _launch_text()
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
		"MASTER ALARM" if bool(Bus.get_value("sys.master_alarm", false)) else "",
		int(Bus.get_value("guid.program", 0)), str(Bus.get_value("guid.step", "")),
		float(Bus.get_value("guid.vg_mps", 0.0)) / ft,
		"MNVR LOADED TIG " + Units.hms(float(Bus.get_value("guid.maneuver_tig", 0.0))) if bool(Bus.get_value("guid.maneuver_valid", false)) else ""]
	if o2 <= 0.0:
		_systems.text += "\nO2 DEPLETED"


## The checklist and the switches, in step with the Bus (checkpoint loads,
## tests).
func _sync_controls() -> void:
	if _check_title.selected != book.current:
		_check_title.selected = book.current
	_check_text.text = _checklist_text()
	for ch in _toggles:
		var want := bool(Bus.get_value(ch, false))
		if _toggles[ch].button_pressed != want:
			_toggles[ch].set_pressed_no_signal(want)
	for ch in _options:
		var want := int(Bus.get_value(ch, 0))
		if _options[ch].selected != want:
			_options[ch].selected = want
