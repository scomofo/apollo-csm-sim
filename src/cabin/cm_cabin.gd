## The CM cabin blockout (docs/ROADMAP.md, slice 2c): the pressure vessel
## with its five windows, the three couches, the hand controllers and the
## three panels of the main display console, which CockpitLayout fills from
## data/cockpit/controls.csv.
##
## Built in body axes (+X toward the apex, +Y right, +Z toward the crew's
## feet) with x = 0 at the heat-shield base, as in the space view's CSM
## model. The node's own basis is Frames.BODY_TO_GODOT, so at the render
## origin it sits where the space view draws the CM. Every dimension is
## [estimated]: the shapes follow the CM in outline only, until its
## drawings are transcribed.
class_name CmCabin
extends Node3D

## Commander's (left couch) design eye point, m.
const EYE_CDR := Vector3(0.75, -0.62, -0.30)
## Centre couch design eye point, m: the command module pilot's seat for
## launch and entry, and where the main DSKY is straight ahead.
const EYE_CMP := Vector3(0.75, 0.0, -0.30)
## Where the player can sit.
const SEATS := {"CDR": EYE_CDR, "CMP": EYE_CMP}
## Axes of a panel face and of the player anchor, in body axes: +X to the
## crew's right, +Y the crew's up (body -Z), +Z toward the crew (body -X).
const FACE_BASIS := Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))
## Main display console: face centre (m, body) and face size (m).
const PANELS := {
	"MDC1": {"centre": Vector3(1.35, -0.66, -0.30), "size": Vector2(0.60, 0.50)},
	"MDC2": {"centre": Vector3(1.37, 0.0, -0.30), "size": Vector2(0.62, 0.56)},
	"MDC3": {"centre": Vector3(1.35, 0.66, -0.30), "size": Vector2(0.60, 0.50)},
}
## Pressure vessel: inner radius VESSEL_R0 - VESSEL_SLOPE * x between the
## aft bulkhead and the forward bulkhead, then the tunnel to the forward
## hatch.
const VESSEL_R0 := 1.85
const VESSEL_SLOPE := 0.46
const AFT_X := 0.25
const FORWARD_X := 2.3
const TUNNEL_R := 0.40
const TUNNEL_X := 2.9
## Window openings in the wall: axial extent (m) and the angle about +X of
## their centre (deg; 0 is +Y, the crew's right, and -90 is -Z, the crew's
## up), with their angular half width.
const WINDOWS := {
	"LeftRendezvous": {"x": Vector2(1.45, 1.85), "phi_deg": -135.0, "half_deg": 10.0},
	"RightRendezvous": {"x": Vector2(1.45, 1.85), "phi_deg": -45.0, "half_deg": 10.0},
	"LeftSide": {"x": Vector2(0.70, 1.10), "phi_deg": 180.0, "half_deg": 5.0},
	"RightSide": {"x": Vector2(0.70, 1.10), "phi_deg": 0.0, "half_deg": 5.0},
	"Hatch": {"x": Vector2(0.80, 1.15), "phi_deg": -90.0, "half_deg": 7.5},
}
## How far the desktop rig's pointer reaches from the commander's eye (m):
## the whole console, including the right-hand panel the commander can't
## touch from the couch.
const CLICK_RANGE := 2.0
## Centre of the checklist card, by the commander's left shoulder, 0.5 m
## from the eye (body, m).
const CARD_CENTRE := Vector3(1.02, -1.02, -0.40)
## Couch centrelines, y (m): commander, centre, right.
const COUCH_Y := [-0.62, 0.0, 0.62]
## Wall mesh resolution: 5 cm along the axis, 2.5 deg around it.
const WALL_STEPS := 41
const AROUND_STEPS := 144

## Where the player's rig goes: the seat's eye, looking along +X with the
## crew's up. Its global basis is the identity in the space view.
var anchor: Node3D
## The seat the anchor is at (a SEATS key).
var seat: String = "CDR"
## Where the checklist card goes: +Z faces the commander's eye, +Y is the
## crew's up.
var card_mount: Node3D
## CockpitLayout.build() output: row id -> node.
var items: Dictionary = {}
var _panels: Dictionary = {}


func _init() -> void:
	name = "CmCabin"
	basis = Frames.BODY_TO_GODOT
	_build_vessel()
	_build_couches()
	_build_panels()
	_build_lights()
	anchor = Node3D.new()
	anchor.name = "PlayerAnchor"
	anchor.transform = Transform3D(FACE_BASIS, EYE_CDR)
	add_child(anchor)
	card_mount = Node3D.new()
	card_mount.name = "CardMount"
	add_child(card_mount)
	set_seat("CDR")


## A cabin with the shipped layout built onto its panels. Layout errors are
## reported and the rows that can be built still are.
static func create() -> CmCabin:
	var cabin := CmCabin.new()
	var layout := CockpitLayout.load_default()
	if not layout.validate():
		for e in layout.errors:
			push_error("controls.csv: " + e)
	cabin.items = layout.build(cabin)
	return cabin


## Move the player's anchor to [param seat_name]'s eye, and the checklist
## card with it, so the card sits by that seat's left shoulder. The rig
## rides on the anchor, so the player moves too; the cabin never does.
func set_seat(seat_name: String) -> void:
	if not SEATS.has(seat_name):
		return
	seat = seat_name
	var eye: Vector3 = SEATS[seat_name]
	anchor.position = eye
	card_mount.transform = Transform3D(Basis.looking_at(CARD_CENTRE - EYE_CDR, Vector3(0, 0, -1)), eye + CARD_CENTRE - EYE_CDR)
	Bus.set_value("player.seat", seat_name)


## Hand the cabin DSKY the CMC's keyboard.
func connect_runtime(rt: SimRuntime) -> void:
	for id in items:
		if items[id] is CabinDsky:
			(items[id] as CabinDsky).dsky = rt.agc().dsky


## The attachment frame of a panel face: x/y are panel coordinates (m) and
## +Z faces the crew.
func panel_node(panel_name: String) -> Node3D:
	return _panels.get(panel_name)


## The inner wall radius at station x.
static func wall_radius(x: float) -> float:
	return VESSEL_R0 - VESSEL_SLOPE * x


## Whether the wall is open at station x, angle phi (deg): inside a window.
static func window_at(x: float, phi_deg: float) -> String:
	for w in WINDOWS:
		var win: Dictionary = WINDOWS[w]
		var ext: Vector2 = win["x"]
		if x > ext.x and x < ext.y and absf(wrapf(phi_deg - float(win["phi_deg"]), -180.0, 180.0)) < float(win["half_deg"]):
			return w
	return ""


func _build_vessel() -> void:
	var wall := CabinMaterials.get_material("wall")
	var bulkhead := CabinMaterials.get_material("bulkhead")
	var r_aft := wall_radius(AFT_X)
	var r_fwd := wall_radius(FORWARD_X)
	_revolve("AftBulkhead", Vector2(AFT_X, 0.0), Vector2(AFT_X, r_aft), 1, bulkhead, false)
	_revolve("Wall", Vector2(AFT_X, r_aft), Vector2(FORWARD_X, r_fwd), WALL_STEPS, wall, true)
	_revolve("ForwardBulkhead", Vector2(FORWARD_X, r_fwd), Vector2(FORWARD_X, TUNNEL_R), 1, bulkhead, false)
	_revolve("Tunnel", Vector2(FORWARD_X, TUNNEL_R), Vector2(TUNNEL_X, TUNNEL_R), 4, bulkhead, false)
	_revolve("ForwardHatch", Vector2(TUNNEL_X, TUNNEL_R), Vector2(TUNNEL_X, 0.0), 1, bulkhead, false)


## A surface of revolution about +X between profile points (x, r), cut
## where the windows are when [param cut].
func _revolve(node_name: String, a: Vector2, b: Vector2, steps: int, mat: Material, cut: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dphi := 360.0 / AROUND_STEPS
	for i in steps:
		var p0 := a.lerp(b, float(i) / steps)
		var p1 := a.lerp(b, float(i + 1) / steps)
		for j in AROUND_STEPS:
			var f0 := -180.0 + j * dphi
			if cut and window_at((p0.x + p1.x) * 0.5, f0 + dphi * 0.5) != "":
				continue
			var q := [_ring(p0, f0), _ring(p0, f0 + dphi), _ring(p1, f0 + dphi), _ring(p1, f0)]
			# A ring of radius 0 is the centre of a disc: one triangle there.
			var tris := []
			if p0.y > 1e-6:
				tris.append_array([0, 1, 2])
			if p1.y > 1e-6:
				tris.append_array([0, 2, 3])
			for k in tris:
				st.add_vertex(q[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	# Both faces cast: with the default setting the shell let the Sun
	# through onto the far side of its own interior.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(mi)


static func _ring(p: Vector2, phi_deg: float) -> Vector3:
	var f := deg_to_rad(phi_deg)
	return Vector3(p.x, p.y * cos(f), p.y * sin(f))


func _build_couches() -> void:
	var pad := CabinMaterials.get_material("couch")
	var frame := CabinMaterials.get_material("bulkhead")
	var names := ["CouchLeft", "CouchCentre", "CouchRight"]
	for i in COUCH_Y.size():
		var y: float = COUCH_Y[i]
		var couch := Node3D.new()
		couch.name = names[i]
		add_child(couch)
		# Back and headrest behind the crew member, then the seat and the
		# raised legs (knees toward +X, feet toward +Z).
		_slab(couch, "Back", Vector3(0.50, y, 0.31), Vector3(0.50, y, -0.55), 0.50, 0.06, pad)
		_slab(couch, "Headrest", Vector3(0.53, y, -0.55), Vector3(0.53, y, -0.72), 0.26, 0.08, pad)
		_slab(couch, "Seat", Vector3(0.52, y, 0.31), Vector3(0.92, y, 0.58), 0.46, 0.06, pad)
		_slab(couch, "Legs", Vector3(0.92, y, 0.58), Vector3(0.80, y, 0.98), 0.40, 0.05, pad)
		_slab(couch, "Frame", Vector3(0.44, y, 0.40), Vector3(0.44, y, -0.60), 0.08, 0.04, frame)
	# The commander's hand controllers: rotation on the right armrest,
	# translation on the left. Not grabbed yet: the keys and thumbsticks fly
	# them (HandControllerInput).
	var arms := CabinMaterials.get_material("dsky_case")
	_slab(self, "ArmrestRight", Vector3(0.56, -0.33, -0.05), Vector3(0.56, -0.33, 0.25), 0.07, 0.05, frame)
	_slab(self, "ArmrestLeft", Vector3(0.56, -0.91, -0.05), Vector3(0.56, -0.91, 0.25), 0.07, 0.05, frame)
	_slab(self, "RHC", Vector3(0.60, -0.33, 0.12), Vector3(0.76, -0.33, 0.12), 0.035, 0.04, arms)
	_slab(self, "THC", Vector3(0.60, -0.91, 0.12), Vector3(0.72, -0.91, 0.12), 0.03, 0.03, arms)


## A box from [param a] to [param b] (body, m), [param width] across the
## cabin (y) and [param thickness] across the other side.
func _slab(parent: Node3D, node_name: String, a: Vector3, b: Vector3, width: float, thickness: float, mat: Material) -> MeshInstance3D:
	var along := b - a
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, width, along.length())
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	var z := along.normalized()
	var y := Vector3(0, 1, 0)
	mi.transform = Transform3D(Basis(y.cross(z), y, z), (a + b) * 0.5)
	parent.add_child(mi)
	return mi


func _build_panels() -> void:
	var root := Node3D.new()
	root.name = "Panels"
	add_child(root)
	for panel_name in PANELS:
		var p: Dictionary = PANELS[panel_name]
		var size: Vector2 = p["size"]
		var mount := Node3D.new()
		mount.name = panel_name
		mount.transform = Transform3D(FACE_BASIS, p["centre"])
		mount.set_meta("size_m", size)
		root.add_child(mount)
		var plate := MeshInstance3D.new()
		plate.name = "Plate"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x, size.y, 0.02)
		plate.mesh = mesh
		plate.position.z = -0.01
		plate.material_override = CabinMaterials.get_material("panel_face")
		mount.add_child(plate)
		_panels[panel_name] = mount


## Floodlights between the crew and the console, so the panel faces and
## the checklist card are lit; otherwise only the windows let light in.
func _build_lights() -> void:
	for spot in [["FloodLeft", Vector3(0.85, -0.95, -0.60)], ["FloodRight", Vector3(0.85, 0.95, -0.60)],
			["FloodCentre", Vector3(0.9, 0.0, -0.95)]]:
		var l := OmniLight3D.new()
		l.name = spot[0]
		l.position = spot[1]
		l.omni_range = 2.2
		l.light_energy = 0.45
		l.light_color = Color(1.0, 0.95, 0.86)
		l.shadow_enabled = false
		add_child(l)
