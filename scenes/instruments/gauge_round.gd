## Round analogue gauge with one or two needles. Each needle maps a bus
## channel (SI) through a named unit conversion and a linear or curve
## calibration onto a sweep of the dial. Needle geometry is real so it
## reads correctly in VR.
## Taken from gemini-capsule at 40e449c (README.md lists the port).
extends Node3D

@export var channel: String = ""
@export var channel2: String = ""            ## optional second needle
@export var converter: String = "none"       ## see Units.convert
@export var min_value: float = 0.0           ## display units
@export var max_value: float = 100.0
@export var min_angle_deg: float = -135.0    ## needle angle at min (CW positive)
@export var max_angle_deg: float = 135.0
## Optional non-linear scale: maps normalised value (0..1) to normalised sweep.
@export var calibration: Curve
## Unpowered gauges park at min; set to a bus voltage channel to model it.
@export var power_channel: String = ""
@export var power_min_volts: float = 20.0
## Provisional presentation; the bus binding and calibration stay identical.
@export_enum("round", "vertical") var face_style: String = "round"
@export var face_caption: String = ""

const VERTICAL_MIN_Y := -0.052
const VERTICAL_MAX_Y := 0.052

var value: float = 0.0
var value2: float = 0.0
var _powered: bool = true

@onready var _needle: Node3D = $Needle
@onready var _needle2: Node3D = get_node_or_null("Needle2")


func _ready() -> void:
	if face_style == "vertical":
		_build_vertical_face()
	else:
		_build_scale()
	if _needle2:
		_needle2.visible = channel2 != ""
	if channel != "":
		Bus.subscribe(channel, _on_value)
	if channel2 != "":
		Bus.subscribe(channel2, _on_value2)
	if power_channel != "":
		Bus.subscribe(power_channel, _on_power)
	_update()


## Provisional presentation of the existing display range, not a sourced
## instrument-face drawing. One MultiMesh batches all eleven scale marks.
func _build_scale() -> void:
	var bezel: MeshInstance3D = $Bezel
	bezel.transform = Transform3D.IDENTITY
	bezel.mesh = _round_bezel_mesh()
	bezel.material_override = CabinMaterials.get_material("bezel")
	var ink := StandardMaterial3D.new()
	ink.albedo_color = CabinMaterials.lettering_colour()
	ink.roughness = 0.9
	var mark := BoxMesh.new()
	mark.size = Vector3.ONE
	mark.material = ink
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mark
	instances.instance_count = 11
	var ticks := MultiMeshInstance3D.new()
	ticks.name = "ScaleMarks"
	ticks.multimesh = instances
	ticks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ticks)
	var numerals := Node3D.new()
	numerals.name = "Numerals"
	add_child(numerals)
	for i in range(11):
		var display := lerpf(min_value, max_value, i / 10.0)
		var angle := deg_to_rad(scale_angle_for(display))
		var major := i % 5 == 0
		var length := 0.0036 if major else 0.0020
		var radius := 0.025 - length / 2.0
		var basis := Basis(Vector3.BACK, -angle) * Basis.from_scale(Vector3(0.0009, length, 0.0002))
		instances.set_instance_transform(i, Transform3D(basis,
			Vector3(sin(angle) * radius, cos(angle) * radius, 0.0078)))
		if major:
			var label := Label3D.new()
			label.name = "N%d" % i
			label.text = _format_tick(display)
			label.font_size = 64
			# Limit long ranges (e.g. 100000 ft) to the same face footprint.
			label.pixel_size = minf(0.000085, 0.00038 / maxf(label.text.length(), 1)) * 48.0 / 64.0
			label.outline_size = 0
			label.modulate = CabinMaterials.lettering_colour()
			label.shaded = true
			label.double_sided = false
			label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			label.position = Vector3(sin(angle) * 0.0165, cos(angle) * 0.0165, 0.0079)
			numerals.add_child(label)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.0025
	hub_mesh.bottom_radius = 0.0025
	hub_mesh.height = 0.0015
	hub_mesh.radial_segments = 16
	hub.mesh = hub_mesh
	hub.material_override = CabinMaterials.get_material("bezel")
	hub.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, 0.0105))
	hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hub)


## A formed annular rim catches light on its outer chamfer and inner return,
## instead of reading as a cylinder behind a disc. gemini-capsule based the
## treatment on a photograph of a Gemini panel; for the CM it and the section
## dimensions are [estimated]. Keep the original 30 mm radius and every
## scale/needle/attachment coordinate.
func _round_bezel_mesh() -> ArrayMesh:
	var section := PackedVector2Array([
		Vector2(0.0300, 0.0000), Vector2(0.0300, 0.0055),
		Vector2(0.0291, 0.0087), Vector2(0.0272, 0.0093),
		Vector2(0.0262, 0.0085), Vector2(0.0262, 0.0070)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 48
	for band in section.size() - 1:
		var a := section[band]
		var b := section[band + 1]
		var normal_section := Vector2(b.y - a.y, a.x - b.x).normalized()
		for i in SEGMENTS:
			var angle_a := TAU * float(i) / SEGMENTS
			var angle_b := TAU * float(i + 1) / SEGMENTS
			# Smooth around the circumference, with intentional hard changes
			# between the five machined section bands.
			for vertex in [[a, angle_a], [b, angle_a], [b, angle_b],
					[a, angle_a], [b, angle_b], [a, angle_b]]:
				var rz: Vector2 = vertex[0]
				var angle: float = vertex[1]
				var radial := Vector2(cos(angle), sin(angle))
				surface.set_normal(Vector3(radial.x * normal_section.x,
					radial.y * normal_section.x, normal_section.y))
				surface.add_vertex(Vector3(radial.x * rz.x, radial.y * rz.x, rz.y))
	surface.index()
	return surface.commit()


## A narrow recessed linear face for vertical-scale meters. Its dimensions
## and styling are provisional [estimated]. Replace the scene's round meshes
## in place so named nodes remain compatible.
func _build_vertical_face() -> void:
	var bezel: MeshInstance3D = $Bezel
	bezel.transform = Transform3D.IDENTITY
	bezel.mesh = _vertical_bezel_mesh()
	bezel.material_override = CabinMaterials.get_material("bezel")
	var dial: MeshInstance3D = $Dial
	var face := BoxMesh.new()
	face.size = Vector3(0.054, 0.139, 0.002)
	dial.mesh = face
	dial.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.010))
	var ink := StandardMaterial3D.new()
	ink.albedo_color = CabinMaterials.lettering_colour()
	ink.roughness = 0.9
	for pointer: Node3D in [_needle, _needle2]:
		if pointer == null:
			continue
		var pointer_mesh: MeshInstance3D = pointer.get_node("Mesh")
		var triangle := SurfaceTool.new()
		triangle.begin(Mesh.PRIMITIVE_TRIANGLES)
		triangle.set_normal(Vector3.BACK)
		triangle.add_vertex(Vector3(-0.018, -0.0025, 0))
		triangle.add_vertex(Vector3(-0.018, 0.0025, 0))
		triangle.add_vertex(Vector3(0.001, 0, 0))
		pointer_mesh.mesh = triangle.commit()
		pointer_mesh.material_override = ink
		pointer_mesh.transform = Transform3D.IDENTITY
		pointer_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pointer.position = Vector3(0, 0, 0.0135 if pointer == _needle2 else 0.013)
	var mark := BoxMesh.new()
	mark.size = Vector3.ONE
	mark.material = ink
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mark
	instances.instance_count = 21
	var ticks := MultiMeshInstance3D.new()
	ticks.name = "ScaleMarks"
	ticks.multimesh = instances
	ticks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ticks)
	var numerals := Node3D.new()
	numerals.name = "Numerals"
	add_child(numerals)
	for i in range(21):
		var display := lerpf(min_value, max_value, i / 20.0)
		var y := scale_position_for(display)
		var major := i % 4 == 0
		var length := 0.005 if major else 0.0027
		instances.set_instance_transform(i, Transform3D(
			Basis.from_scale(Vector3(length, 0.0007, 0.0002)),
			Vector3(0.003 + length / 2.0, y, 0.012)))
		if major:
			_vertical_label(numerals, "N%d" % i, _format_tick(display), Vector3(0.017, y, 0.0122), 0.00011)
	if face_caption != "":
		_vertical_label(self, "FaceCaption", face_caption, Vector3(0, -0.063, 0.0122), 0.00009)


func _vertical_label(parent: Node3D, node_name: String, text: String, at: Vector3, pixel_size: float) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font_size = 64
	label.pixel_size = minf(pixel_size, 0.0015 / maxf(text.length(), 1)) * 48.0 / 64.0
	label.outline_size = 0
	label.modulate = CabinMaterials.lettering_colour()
	label.shaded = true
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = at
	parent.add_child(label)


func _vertical_bezel_mesh() -> ArrayMesh:
	var rings: Array[PackedVector3Array] = [
		_bezel_ring(0.035, 0.0775, 0.004, 0.000),
		_bezel_ring(0.035, 0.0775, 0.004, 0.006),
		_bezel_ring(0.031, 0.0735, 0.003, 0.014),
		_bezel_ring(0.027, 0.0695, 0.0015, 0.014),
		_bezel_ring(0.026, 0.0685, 0.0015, 0.0105),
	]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rings.size() - 1):
		for i in range(8):
			var next := (i + 1) % 8
			var a := rings[row][i]
			var b := rings[row][next]
			var c := rings[row + 1][next]
			var d := rings[row + 1][i]
			surface.set_normal((b - a).cross(c - a).normalized())
			# Clockwise triangles face the crew with these outward normals.
			for point: Vector3 in [a, c, b, a, d, c]:
				surface.add_vertex(point)
	return surface.commit()


func _bezel_ring(w: float, h: float, corner: float, z: float) -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-w + corner, -h, z), Vector3(w - corner, -h, z),
		Vector3(w, -h + corner, z), Vector3(w, h - corner, z),
		Vector3(w - corner, h, z), Vector3(-w + corner, h, z),
		Vector3(-w, h - corner, z), Vector3(-w, -h + corner, z),
	])


func _format_tick(display: float) -> String:
	if is_equal_approx(display, roundf(display)):
		return str(int(roundf(display)))
	return "%.1f" % display


func _on_value(v: Variant) -> void:
	value = Units.convert(float(v), converter)
	_update()


func _on_value2(v: Variant) -> void:
	value2 = Units.convert(float(v), converter)
	_update()


func _on_power(v: Variant) -> void:
	_powered = float(v) >= power_min_volts
	_update()


## Needle angle for a display-unit value, degrees clockwise from straight up.
func angle_for(display_value: float) -> float:
	if not _powered:
		return min_angle_deg
	return scale_angle_for(display_value)


## Fixed face markings use the calibration even when the powered needle parks.
func scale_angle_for(display_value: float) -> float:
	return lerpf(min_angle_deg, max_angle_deg, _scale_fraction_for(display_value))


## Linear pointer position in metres; loss of power parks at the lower stop.
func position_for(display_value: float) -> float:
	if not _powered:
		return VERTICAL_MIN_Y
	return scale_position_for(display_value)


func scale_position_for(display_value: float) -> float:
	return lerpf(VERTICAL_MIN_Y, VERTICAL_MAX_Y, _scale_fraction_for(display_value))


func _scale_fraction_for(display_value: float) -> float:
	var t := clampf(inverse_lerp(min_value, max_value, display_value), 0.0, 1.0)
	if calibration:
		t = clampf(calibration.sample(t), 0.0, 1.0)
	return t


func _update() -> void:
	if face_style == "vertical":
		if _needle:
			_needle.rotation.z = 0
			_needle.position.y = position_for(value)
		if _needle2 and channel2 != "":
			_needle2.rotation.z = 0
			_needle2.position.y = position_for(value2)
		return
	if _needle:
		_needle.rotation.z = -deg_to_rad(angle_for(value))
	if _needle2 and channel2 != "":
		_needle2.rotation.z = -deg_to_rad(angle_for(value2))
