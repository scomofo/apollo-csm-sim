## Data-driven cockpit: loads a cabin's controls file and
## data/cockpit/channels.csv, validates every row, and builds each one onto
## its panel with its lettering. Nothing on a panel is placed by hand.
## Columbia's rows are in data/cockpit/controls.csv, on CmCabin's panels
## (load_default()); Eagle's in lm_controls.csv, on LmCabin's (load_lm()).
## Adapted from gemini-capsule's src/cabin/cockpit_layout.gd at 40e449c
## (README.md lists the port). Rows are checked against the cabin's panels
## and against the channel types in channels.csv, in place of Gemini's
## cabin datum and cockpit spec: no CM or LM panel drawings are transcribed
## yet, so there is no spec_id column. A control on a bool channel
## publishes a bool, as the HUD does. Switch positions are lettered above
## and below the lever and around the knob.
class_name CockpitLayout
extends RefCounted

const CONTROLS_PATH := "res://data/cockpit/controls.csv"
const LM_CONTROLS_PATH := "res://data/cockpit/lm_controls.csv"
const CHANNELS_PATH := "res://data/cockpit/channels.csv"

const COLUMNS := ["id", "panel", "type", "label", "x_mm", "y_mm", "rot_deg", "channel", "params", "source", "confidence", "status", "role"]
const CHANNEL_COLUMNS := ["channel", "type", "units", "writer", "description"]
const CHANNEL_TYPES := ["bool", "int", "float", "string", "quat", "group"]
const ROLES := ["historical", "proxy"]
const STATUS := ["placeholder", "implemented", "validated"]
const CONFIDENCE := ["A", "B", "C", "D"]

## type -> prefab; whether the crew sets it (a control publishes a crew
## ctl.* channel, a display reads any channel); the channel types it takes;
## and its footprint's half size on the panel (mm): a control's touch
## volume, a display's face.
const TYPES := {
	"toggle": {"scene": "res://scenes/controls/toggle_switch.tscn", "control": true, "takes": ["bool", "int"], "half_mm": Vector2(15, 30)},
	"rotary": {"scene": "res://scenes/controls/rotary_switch.tscn", "control": true, "takes": ["int"], "half_mm": Vector2(15, 25)},
	"pushbutton": {"scene": "res://scenes/controls/pushbutton.tscn", "control": true, "takes": ["bool"], "half_mm": Vector2(15, 25)},
	"lamp": {"scene": "res://scenes/instruments/lamp.tscn", "control": false, "takes": ["bool", "float"], "half_mm": Vector2(15, 10)},
	"numeric": {"scene": "res://scenes/instruments/numeric_display.tscn", "control": false, "takes": ["float", "int"], "half_mm": Vector2(25, 8)},
	"clock": {"scene": "res://scenes/instruments/clock_display.tscn", "control": false, "takes": ["float"], "half_mm": Vector2(35, 8)},
	"fdai": {"scene": "res://scenes/instruments/fdai.tscn", "control": false, "takes": ["quat"], "half_mm": Vector2(55, 55)},
	"dsky": {"scene": "res://scenes/instruments/cabin_dsky.tscn", "control": false, "takes": ["group"], "half_mm": Vector2(100, 120)},
	"optics": {"scene": "res://scenes/instruments/optics_eyepiece.tscn", "control": false, "takes": ["group"], "half_mm": Vector2(180, 105)},
	"aot": {"scene": "res://scenes/instruments/aot_eyepiece.tscn", "control": false, "takes": ["group"], "half_mm": Vector2(100, 110)},
	"deda": {"scene": "res://scenes/instruments/cabin_deda.tscn", "control": false, "takes": ["group"], "half_mm": Vector2(75, 85)},
}
## Printed lettering, capital height (m) [estimated].
const CAPTION_HEIGHT := 0.0055
const LEGEND_HEIGHT := 0.0042

var rows: Array[Dictionary] = []
## channel (or pattern) -> its channels.csv row.
var channels: Dictionary = {}
## The panels the rows go on: a cabin's PANELS (name -> centre and size),
## the CM's unless load_lm() says otherwise.
var panels: Dictionary = {}
var errors: PackedStringArray = []
var _channel_rows: Array[Dictionary] = []


func _init() -> void:
	panels = CmCabin.PANELS


## Columbia's layout, on the CM's main display console.
static func load_default() -> CockpitLayout:
	var l := CockpitLayout.new()
	l.load_channels(CHANNELS_PATH)
	l.load_controls(CONTROLS_PATH)
	return l


## Eagle's layout, on the LM's panels.
static func load_lm() -> CockpitLayout:
	var l := CockpitLayout.new()
	l.panels = LmCabin.PANELS
	l.load_channels(CHANNELS_PATH)
	l.load_controls(LM_CONTROLS_PATH)
	return l


## Rows keyed by the header. Blank lines and # comments are skipped;
## "_line" is the row's line in the file and "_columns" its column count.
static func _read_csv(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var header: PackedStringArray = []
	var line_no := 0
	while not f.eof_reached():
		var line := f.get_line()
		line_no += 1
		if line.strip_edges().is_empty() or line.begins_with("#"):
			continue
		var cols := line.split(",")
		if header.is_empty():
			header = cols
			continue
		var row := {"_line": line_no, "_columns": cols.size()}
		for i in range(header.size()):
			row[header[i].strip_edges()] = cols[i].strip_edges() if i < cols.size() else ""
		out.append(row)
	return out


func load_channels(path: String) -> void:
	_channel_rows = _read_csv(path)
	for r in _channel_rows:
		channels[r.get("channel", "")] = r


func load_controls(path: String) -> void:
	rows = _read_csv(path)


## The channels.csv type of [param channel], matching * patterns one path
## segment at a time; "" when it isn't listed.
func channel_type(channel: String) -> String:
	if channels.has(channel):
		return channels[channel].get("type", "")
	var parts := channel.split(".")
	for pattern: String in channels:
		var p := pattern.split(".")
		if p.size() != parts.size():
			continue
		var ok := true
		for i in range(p.size()):
			if p[i] != "*" and p[i] != parts[i]:
				ok = false
				break
		if ok:
			return channels[pattern].get("type", "")
	return ""


func channel_writer(channel: String) -> String:
	return channels[channel].get("writer", "") if channels.has(channel) else ""


func validate() -> bool:
	errors.clear()
	_validate_channels()
	var seen := {}
	for r in rows:
		_validate_row(r, "row %d (%s)" % [r.get("_line", 0), r.get("id", "?")], seen)
	_validate_overlaps()
	return errors.is_empty()


func _validate_channels() -> void:
	var seen := {}
	for r in _channel_rows:
		var where := "channels.csv row %d (%s)" % [r.get("_line", 0), r.get("channel", "?")]
		if r.get("_columns", 0) != CHANNEL_COLUMNS.size():
			errors.append("%s: %d columns, the header has %d" % [where, r.get("_columns", 0), CHANNEL_COLUMNS.size()])
		if seen.has(r.get("channel", "")):
			errors.append("%s: listed twice" % where)
		seen[r.get("channel", "")] = true
		if not CHANNEL_TYPES.has(r.get("type", "")):
			errors.append("%s: type must be one of %s" % [where, CHANNEL_TYPES])
		if r.get("writer", "") == "":
			errors.append("%s: every channel needs a writer" % where)


func _validate_row(r: Dictionary, where: String, seen: Dictionary) -> void:
	if r.get("_columns", 0) != COLUMNS.size():
		errors.append("%s: %d columns, the header has %d" % [where, r.get("_columns", 0), COLUMNS.size()])
	for c in COLUMNS:
		if not r.has(c):
			errors.append("%s: missing column %s" % [where, c])
	var id: String = r.get("id", "")
	if id == "":
		errors.append("%s: empty id" % where)
	elif seen.has(id):
		errors.append("%s: duplicate id" % where)
	seen[id] = true
	var panel: String = r.get("panel", "")
	if not panels.has(panel):
		errors.append("%s: unknown panel '%s'" % [where, panel])
	var type: String = r.get("type", "")
	if not TYPES.has(type):
		errors.append("%s: unknown type '%s'" % [where, type])
	var ch: String = r.get("channel", "")
	var ctype := channel_type(ch)
	if ctype == "":
		errors.append("%s: channel '%s' not in channels.csv" % [where, ch])
	elif TYPES.has(type) and not ctype in TYPES[type]["takes"]:
		errors.append("%s: a %s can't bind the %s channel %s" % [where, type, ctype, ch])
	if TYPES.has(type) and TYPES[type]["control"] and ctype != "" \
			and (not ch.begins_with("ctl.") or channel_writer(ch) != "crew"):
		errors.append("%s: a control publishes a crew ctl.* channel, not %s" % [where, ch])
	if type == "dsky" and ctype == "group":
		var lamp_set := str(parse_params(r.get("params", "")).get("lamp_set", "cmc"))
		for c in CabinDsky.channels_read(ch, lamp_set):
			if channel_type(c) == "":
				errors.append("%s: the DSKY reads %s, which channels.csv doesn't list" % [where, c])
	if type == "deda" and ctype == "group":
		for c in CabinDeda.channels_read(ch):
			if channel_type(c) == "":
				errors.append("%s: the DEDA reads %s, which channels.csv doesn't list" % [where, c])
	for c in ["x_mm", "y_mm", "rot_deg"]:
		if not str(r.get(c, "")).is_valid_float():
			errors.append("%s: %s must be a number" % [where, c])
	if TYPES.has(type):
		_validate_params(r, where, type, ctype)
		if panels.has(panel):
			var half: Vector2 = panels[panel]["size"] * 500.0
			var at := Vector2(float(r.get("x_mm", "0")), float(r.get("y_mm", "0")))
			var reach := footprint_mm(r)
			if absf(at.x) + reach.x > half.x or absf(at.y) + reach.y > half.y:
				errors.append("%s: (%d, %d) mm is off the %s face (±%d, ±%d)" % [where, at.x, at.y, panel, half.x, half.y])
	if not CONFIDENCE.has(r.get("confidence", "")):
		errors.append("%s: confidence must be one of A-D" % where)
	if not STATUS.has(r.get("status", "")):
		errors.append("%s: status must be placeholder / implemented / validated" % where)
	if r.get("status", "") == "validated" and r.get("confidence", "") in ["C", "D"]:
		errors.append("%s: a validated row needs confidence A or B" % where)
	if not ROLES.has(r.get("role", "")):
		errors.append("%s: role must be one of %s" % [where, ROLES])
	if r.get("source", "") == "":
		errors.append("%s: every row names its source" % where)


func _validate_params(r: Dictionary, where: String, type: String, ctype: String) -> void:
	var probe: Node = load(TYPES[type]["scene"]).instantiate()
	var params := parse_params(r.get("params", ""))
	for k: String in params:
		if k == "scale":
			if TYPES[type]["control"]:
				errors.append("%s: controls keep their size (their touch volumes are tuned)" % where)
			elif not str(params[k]).is_valid_float() or float(params[k]) <= 0.0:
				errors.append("%s: scale must be a positive number" % where)
		elif k in ["channel", "label", "publish_bool"]:
			errors.append("%s: %s comes from its column or the channel type, not params" % [where, k])
		elif not _has_property(probe, k):
			errors.append("%s: %s has no property '%s'" % [where, type, k])
		else:
			var bad := coerce_error(probe, k, params[k])
			if bad != "":
				errors.append("%s: %s" % [where, bad])
			elif k.ends_with("channel") and params[k] != "" and channel_type(params[k]) == "":
				errors.append("%s: %s '%s' not in channels.csv" % [where, k, params[k]])
			else:
				probe.set(k, coerce(probe, k, params[k]))
	if type in ["toggle", "rotary"]:
		var n := int(probe.get("positions"))
		if (probe.get("labels") as PackedStringArray).size() != n:
			errors.append("%s: labels must name all %d positions" % [where, n])
		if type == "rotary" and not params.has("labels"):
			errors.append("%s: a rotary needs its position labels" % where)
		if ctype == "bool" and n != 2:
			errors.append("%s: a %d-position switch can't publish a bool" % [where, n])
		if params.has("values"):
			var vals: PackedInt32Array = probe.get("values")
			var seen := {}
			for v in vals:
				seen[v] = true
			if ctype == "bool":
				errors.append("%s: a switch on a bool channel publishes a bool, not values" % where)
			elif vals.size() != n:
				errors.append("%s: values must give all %d positions a value" % [where, n])
			elif seen.size() != n:
				errors.append("%s: two positions publish the same value" % where)
	probe.free()


## Every item's footprint must stay clear of the others on its panel.
func _validate_overlaps() -> void:
	for i in rows.size():
		for j in range(i + 1, rows.size()):
			var a := rows[i]
			var b := rows[j]
			if a.get("panel") != b.get("panel") or not TYPES.has(a.get("type", "")) or not TYPES.has(b.get("type", "")):
				continue
			var d := Vector2(float(a.get("x_mm", "0")) - float(b.get("x_mm", "0")), float(a.get("y_mm", "0")) - float(b.get("y_mm", "0")))
			var room := footprint_mm(a) + footprint_mm(b)
			if absf(d.x) < room.x and absf(d.y) < room.y:
				errors.append("row %d (%s) overlaps row %d (%s)" % [a.get("_line", 0), a.get("id", "?"), b.get("_line", 0), b.get("id", "?")])


## Half size of a row's footprint on the panel, mm.
static func footprint_mm(r: Dictionary) -> Vector2:
	var half: Vector2 = TYPES[r["type"]]["half_mm"]
	var s := str(parse_params(r.get("params", "")).get("scale", "1"))
	return half * (float(s) if s.is_valid_float() else 1.0)


static func _has_property(node: Object, prop: String) -> bool:
	for p in node.get_property_list():
		if p["name"] == prop:
			return true
	return false


static func parse_params(text: String) -> Dictionary:
	var out := {}
	for kv in text.split(";", false):
		var eq := kv.find("=")
		if eq > 0:
			out[kv.substr(0, eq).strip_edges()] = kv.substr(eq + 1).strip_edges()
	return out


## Why [param text] can't set [param prop] on [param node], or "".
static func coerce_error(node: Object, prop: String, text: String) -> String:
	match typeof(node.get(prop)):
		TYPE_BOOL:
			if not text.to_lower() in ["1", "0", "true", "false", "yes", "no", "on", "off"]:
				return "%s=%s is not a bool" % [prop, text]
		TYPE_INT:
			if not text.is_valid_int():
				return "%s=%s is not an integer" % [prop, text]
		TYPE_FLOAT:
			if not text.is_valid_float():
				return "%s=%s is not a number" % [prop, text]
		TYPE_COLOR:
			if not Color.html_is_valid(text):
				return "%s=%s is not a colour" % [prop, text]
		TYPE_PACKED_INT32_ARRAY:
			for s in text.split("|", false):
				if not s.is_valid_int():
					return "%s=%s is not a list of integers" % [prop, text]
	return ""


static func coerce(node: Object, prop: String, text: String) -> Variant:
	match typeof(node.get(prop)):
		TYPE_BOOL: return text.to_lower() in ["1", "true", "yes", "on"]
		TYPE_INT: return int(text)
		TYPE_FLOAT: return float(text)
		TYPE_PACKED_STRING_ARRAY: return PackedStringArray(text.split("|"))
		TYPE_PACKED_INT32_ARRAY:
			var a := PackedInt32Array()
			for s in text.split("|", false):
				a.append(int(s))
			return a
		TYPE_COLOR: return Color(text)
	return text


## Build every row onto its panel; returns id -> node. Rows with an unknown
## panel or type are left out (validate() reports them).
func build(cabin: Cabin) -> Dictionary:
	var made := {}
	for r in rows:
		var panel := cabin.panel_node(r.get("panel", ""))
		if panel == null or not TYPES.has(r.get("type", "")):
			continue
		var node: Node3D = load(TYPES[r["type"]]["scene"]).instantiate()
		node.name = r["id"]
		node.set("channel", r["channel"])
		if _has_property(node, "label"):
			node.set("label", r["label"])
		if _has_property(node, "publish_bool"):
			node.set("publish_bool", channel_type(r["channel"]) == "bool")
		var params := parse_params(r["params"])
		for k: String in params:
			if k == "scale":
				node.scale = Vector3.ONE * float(params[k])
			elif _has_property(node, k):
				node.set(k, coerce(node, k, params[k]))
		node.position = Vector3(float(r["x_mm"]), float(r["y_mm"]), 0.0) / 1000.0
		node.rotation.z = deg_to_rad(float(r["rot_deg"]))
		node.set_meta("row", r)
		panel.add_child(node)
		_letter(panel, node, r)
		made[r["id"]] = node
	return made


## Captions and position legends, printed on the panel beside the item.
func _letter(panel: Node3D, node: Node3D, r: Dictionary) -> void:
	var at := node.position
	var mm := 0.001
	match r["type"]:
		"dsky", "deda":
			return # The DSKY and the DEDA carry their own legends.
		"lamp":
			# The legend is on the lens.
			var lens := _text(node, "Legend", r["label"].replace(" ", "\n"), Vector3(0, 0, 0.0095), LEGEND_HEIGHT, Color(0.1, 0.08, 0.06))
			lens.shaded = true
			return
		"toggle":
			_caption(panel, r, at + Vector3(0, 38 * mm, 0.001), 60 * mm, VERTICAL_ALIGNMENT_BOTTOM)
			var labels: PackedStringArray = node.get("labels")
			var n: int = node.get("positions")
			_legend(panel, r, 0, labels[n - 1], at + Vector3(0, 22 * mm, 0.001))
			_legend(panel, r, 1, labels[0], at + Vector3(0, -22 * mm, 0.001))
			if n == 3:
				var mid := _legend(panel, r, 2, labels[1], at + Vector3(12 * mm, 0, 0.001))
				mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		"rotary":
			_caption(panel, r, at + Vector3(0, -30 * mm, 0.001), 70 * mm, VERTICAL_ALIGNMENT_TOP)
			var labels: PackedStringArray = node.get("labels")
			for i in int(node.get("positions")):
				var a := deg_to_rad(float(node.get("start_angle_deg")) + float(node.get("detent_deg")) * i)
				_legend(panel, r, i, labels[i], at + Vector3(sin(a), cos(a), 0.0) * 26 * mm + Vector3(0, 0, 0.001))
		"pushbutton":
			_caption(panel, r, at + Vector3(0, -18 * mm, 0.001), 60 * mm, VERTICAL_ALIGNMENT_TOP)
		"fdai":
			_caption(panel, r, at + Vector3(0, -60 * mm * node.scale.x, 0.001), 120 * mm, VERTICAL_ALIGNMENT_TOP)
		_:
			_caption(panel, r, at + Vector3(0, -14 * mm, 0.001), 70 * mm, VERTICAL_ALIGNMENT_TOP)


func _caption(panel: Node3D, r: Dictionary, at: Vector3, width: float, valign: VerticalAlignment) -> Label3D:
	var l := _text(panel, r["id"] + "Caption", r["label"], at, CAPTION_HEIGHT, CabinMaterials.lettering_colour())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = width / l.pixel_size
	l.vertical_alignment = valign
	l.set_meta("lettering_role", "panel_caption")
	return l


func _legend(panel: Node3D, r: Dictionary, i: int, text: String, at: Vector3) -> Label3D:
	var l := _text(panel, "%sPosition%d" % [r["id"], i], text, at, LEGEND_HEIGHT, CabinMaterials.lettering_colour())
	l.set_meta("lettering_role", "position_legend")
	return l


## Lettering [param height] m tall (capital height, roughly). Unshaded: the
## CM's panel legends are lit from behind.
static func _text(parent: Node3D, node_name: String, text: String, at: Vector3, height: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.text = text
	l.font = ThemeDB.fallback_font
	l.font_size = 64
	l.pixel_size = height / 45.0
	l.outline_size = 0
	l.modulate = colour
	l.shaded = false
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = at
	parent.add_child(l)
	return l
