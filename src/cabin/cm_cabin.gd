## The CM cabin blockout (docs/ROADMAP.md, slice 2c): the pressure vessel
## with its five windows, the three couches, the hand controllers, the
## three panels of the main display console, and the lower equipment bay's
## guidance and navigation panel beyond the couches' feet, with the optics'
## eyepieces, their switches and the second DSKY (slice 4c), which
## CockpitLayout fills from data/cockpit/controls.csv.
##
## Built in body axes (+X toward the apex, +Y right, +Z toward the crew's
## feet) with x = 0 at the heat-shield base, as in the space view's CSM
## model. The node's own basis is Frames.BODY_TO_GODOT, so at the render
## origin it sits where the space view draws the CM. Panel assignments are
## transcribed from AOH Vol 1 §3 (Panels 1-3); every dimension is
## [estimated]: the shapes follow the CM in outline only, until dimensioned
## drawings are transcribed.
class_name CmCabin
extends Cabin

## Commander's (left couch) design eye point, m.
const EYE_CDR := Vector3(0.75, -0.62, -0.30)
## Centre couch design eye point, m: the command module pilot's seat for
## launch and entry, and where the main DSKY is straight ahead.
const EYE_CMP := Vector3(0.75, 0.0, -0.30)
## Right couch design eye point, m: the lunar module pilot's station. The
## couches run CDR-CMP-LMP left to right (AOH Vol 1 §3; TN D-7440).
const EYE_LMP := Vector3(0.75, 0.62, -0.30)
## At the lower equipment bay, m: the command module pilot beyond the
## couches' feet, head toward the apex, facing the navigation panel, away
## from the couch.
const EYE_LEB := Vector3(1.05, 0.0, 0.72)
## Where the player can be.
const SEATS := {"CDR": EYE_CDR, "CMP": EYE_CMP, "LEB": EYE_LEB}
## Axes of a panel face and of the player anchor, in body axes: +X to the
## crew's right, +Y the crew's up (body -Z), +Z toward the crew (body -X).
const FACE_BASIS := Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))
## The same at the lower equipment bay: the right is body +Y, the up body
## +X (the apex) and toward the crew body -Z.
const LEB_BASIS := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
## Main display console: face centre (m, body) and face size (m).
## MDC1/MDC2/MDC3 are AOH Main Display Console Panels 1/2/3 (left/centre/
## right as the crew sees them; AOH Vol 1 §3 p. 3-2). The real MDC is a
## ~2.1 x 0.91 m crescent of 14 subpanels (Panels 1-10, 12, 13, 15, 16);
## only the three top-row panels are modelled.
## Main display console, plus the lower-equipment-bay navigation panel carrying
## the optics, the DSKY and the third master alarm (AOH C&W §2.10: the MASTER
## ALARM switchlight on LEB-122; the bay's nav station is the same physical
## panel). Face centre (m, body) and face size (m). LEB-122's coordinates
## are [estimated]: the bay sits below the MDC, forward of the couches, where
## the navigator works the optics; panel identity, type and bay are sourced.
const PANELS := {
	"MDC1": {"centre": Vector3(1.35, -0.66, -0.30), "size": Vector2(0.60, 0.50)},
	"MDC2": {"centre": Vector3(1.37, 0.0, -0.30), "size": Vector2(0.62, 0.56)},
	"MDC3": {"centre": Vector3(1.35, 0.66, -0.30), "size": Vector2(0.60, 0.50)},
	"LEB122": {"centre": Vector3(1.05, 0.0, 1.20), "size": Vector2(0.55, 0.45)},
}
## Pressure vessel: inner radius VESSEL_R0 - VESSEL_SLOPE * x between the
## aft bulkhead and the forward bulkhead, then the tunnel to the forward
## hatch. VESSEL_R0 is ~3.7 m inner diameter at the base, the working
## estimate derived from the wall stack (see the cabin research notes).
const VESSEL_R0 := 1.85
const VESSEL_SLOPE := 0.46
const AFT_X := 0.25
const FORWARD_X := 2.3
const TUNNEL_R := 0.40
const TUNNEL_X := 2.9
## Window openings in the wall: axial extent (m) and the angle about +X of
## their centre (deg; 0 is +Y, the crew's right, and -90 is -Z, the crew's
## up), with their angular half width. The five crew windows (AOH §2.12.4.1.1):
## side 1/5 (square), rendezvous 2/4 (triangular), hatch 3. The left
## rendezvous window serves the commander (AOH §2.12.4.1.5).
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


func _init() -> void:
	name = "CmCabin"
	basis = Frames.BODY_TO_GODOT
	_build_vessel()
	_build_window_reveals()
	_build_couches()
	_build_panels()
	_build_lights()
	_build_anchor()


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


## The main display console's three panels, facing the crew, and the
## lower equipment bay's, facing its station.
func panels() -> Dictionary:
	var out := {}
	for p in PANELS:
		out[p] = PANELS[p].merged({"basis": LEB_BASIS if p == "LEB122" else FACE_BASIS})
	return out


func seats() -> Dictionary:
	return SEATS


func eye_basis() -> Basis:
	return FACE_BASIS


func seat_basis(seat_name: String) -> Basis:
	return LEB_BASIS if seat_name == "LEB" else FACE_BASIS


## By the seat's left shoulder: the card keeps its place from the eye as
## the seat moves, and at the lower equipment bay it turns with the eye.
func card_centre(seat_name: String) -> Vector3:
	var off := FACE_BASIS.inverse() * (CARD_CENTRE - EYE_CDR)
	return SEATS[seat_name] + seat_basis(seat_name) * off


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


## Recessed window assemblies (NASA TN D-6721, figures 2-6). The liner is
## black to suppress glare, with a pressure-frame retainer on the cabin side.
## [simplified] These bands follow our conical shell, not the flown planar
## panes. Apertures, 55 mm recess, frame widths and screw spacing remain
## estimated. See docs/CABIN_FIDELITY.md for sources and limits.
func _build_window_reveals() -> void:
	var frame := CabinMaterials.get_material("window_frame")
	var seal := CabinMaterials.get_material("window_seal")
	for window_name in WINDOWS:
		var root := Node3D.new()
		root.name = window_name + "Retainer"
		add_child(root)
		# Each loop uses the SAME shell coordinates as the aperture. A flat
		# box at the centre's radius used to float at one end and sink into
		# the wall at the other (the radius changes by 18 cm over a window).
		_window_band(root, "Gasket", window_name, Vector2(0.0, -0.004), Vector2(0.034, -0.004), seal)
		_window_band(root, "InnerBevel", window_name, Vector2(0.0, -0.004), Vector2(0.006, -0.014), frame)
		_window_band(root, "Retainer", window_name, Vector2(0.006, -0.014), Vector2(0.028, -0.014), frame)
		_window_band(root, "OuterBevel", window_name, Vector2(0.028, -0.014), Vector2(0.032, -0.004), frame)
		_window_band(root, "Recess", window_name, Vector2(0.0, -0.004), Vector2(0.0, 0.055), seal)
		_window_band(root, "PressureSeal", window_name, Vector2(-0.006, 0.055), Vector2(0.0, 0.055), seal)
		_window_fasteners(root, window_name)


## A point on a window loop. uv runs -1..1 around the aperture, margin
## expands it in metres, and depth is radial (positive out of the cabin).
## The angle is deliberately not wrapped: the left side straddles +/-PI.
static func window_point(window_name: String, uv: Vector2, margin: float = 0.0, depth: float = 0.0) -> Vector3:
	var w: Dictionary = WINDOWS[window_name]
	var ext: Vector2 = w["x"]
	var centre_x := (ext.x + ext.y) * 0.5
	var x := centre_x + uv.x * ((ext.y - ext.x) * 0.5 + margin)
	var phi := deg_to_rad(float(w["phi_deg"])) + uv.y * (deg_to_rad(float(w["half_deg"])) + margin / wall_radius(centre_x))
	return Vector3(x, 0, 0) + Vector3(0, cos(phi), sin(phi)) * (wall_radius(x) + depth)


## One continuous strip between two loops (margin, depth), subdivided to
## follow the cone. The six bands cost six surfaces per window, regardless
## of the number of segments. No collision shapes intercept the controls.
func _window_band(parent: Node3D, node_name: String, window_name: String, inner: Vector2, outer: Vector2, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for side in 4:
		for step in 8:
			var a: Vector2 = corners[side].lerp(corners[(side + 1) % 4], step / 8.0)
			var b: Vector2 = corners[side].lerp(corners[(side + 1) % 4], (step + 1) / 8.0)
			var q := [window_point(window_name, a, inner.x, inner.y), window_point(window_name, b, inner.x, inner.y),
				window_point(window_name, b, outer.x, outer.y), window_point(window_name, a, outer.x, outer.y)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	parent.add_child(mi)


## Small slotted screw heads, batched into two draws per window. Their
## axes follow the local shell normal, including its axial slope.
func _window_fasteners(parent: Node3D, window_name: String) -> void:
	var head := CylinderMesh.new()
	head.top_radius = 0.0035
	head.bottom_radius = 0.0035
	head.height = 0.002
	head.radial_segments = 12
	var slot := BoxMesh.new()
	slot.size = Vector3(0.005, 0.0004, 0.0009)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for part in ["Heads", "Slots"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = head if part == "Heads" else slot
		mm.instance_count = 12
		for side in 4:
			for i in 3:
				var uv: Vector2 = corners[side].lerp(corners[(side + 1) % 4], (i + 1) / 4.0)
				var p := window_point(window_name, uv, 0.017, -0.015)
				var radial := Vector3(0, p.y, p.z).normalized()
				var along := (Vector3.RIGHT - VESSEL_SLOPE * radial).normalized()
				var normal := -(Vector3.RIGHT * VESSEL_SLOPE + radial).normalized()
				var axes := Basis(along, normal, along.cross(normal))
				if part == "Slots":
					p += normal * 0.0011
				mm.set_instance_transform(side * 3 + i, Transform3D(axes, p))
		var batch := MultiMeshInstance3D.new()
		batch.name = "Fastener" + part
		batch.multimesh = mm
		batch.material_override = CabinMaterials.get_material("fastener" if part == "Heads" else "window_seal")
		parent.add_child(batch)


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
	var frame := CabinMaterials.get_material("couch_frame")
	var fastener := CabinMaterials.get_material("fastener")
	var names := ["CouchLeft", "CouchCentre", "CouchRight"]
	for i in COUCH_Y.size():
		var y: float = COUCH_Y[i]
		var couch := Node3D.new()
		couch.name = names[i]
		add_child(couch)
		# Back, headrest, seat and raised leg rests with tubular side rails.
		_slab(couch, "Back", Vector3(0.50, y, 0.31), Vector3(0.50, y, -0.55), 0.50, 0.06, pad)
		_slab(couch, "Headrest", Vector3(0.53, y, -0.55), Vector3(0.53, y, -0.72), 0.26, 0.08, pad)
		_slab(couch, "Seat", Vector3(0.52, y, 0.31), Vector3(0.92, y, 0.58), 0.46, 0.06, pad)
		_slab(couch, "Legs", Vector3(0.92, y, 0.58), Vector3(0.80, y, 0.98), 0.40, 0.05, pad)
		# Tubular frame rails along left and right sides of each couch
		_slab(couch, "RailLeft", Vector3(0.44, y - 0.24, 0.58), Vector3(0.44, y - 0.24, -0.72), 0.03, 0.03, frame)
		_slab(couch, "RailRight", Vector3(0.44, y + 0.24, 0.58), Vector3(0.44, y + 0.24, -0.72), 0.03, 0.03, frame)
		_slab(couch, "Footrest", Vector3(0.80, y, 0.98), Vector3(0.75, y, 1.05), 0.38, 0.04, fastener)
	# The commander's hand controllers: rotation on the right armrest
	# (RHC-1, left-hand couch right armrest), translation on the left
	# (THC, commander's left armrest) — AOH Vol 1 §3 p. 3-9; TN D-7884.
	# Not grabbed yet: the keys and thumbsticks fly them
	# (HandControllerInput).
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


## Floodlights between the crew and the console, so the panel faces and
## the checklist card are lit; otherwise only the windows let light in.
func _build_lights() -> void:
	for spot in [["FloodLeft", Vector3(0.85, -0.95, -0.60)], ["FloodRight", Vector3(0.85, 0.95, -0.60)],
			["FloodCentre", Vector3(0.9, 0.0, -0.95)], ["FloodNavigation", Vector3(1.10, -0.33, 0.85)]]:
		var l := OmniLight3D.new()
		l.name = spot[0]
		l.position = spot[1]
		# [estimated] Task lighting calibrated for realistic panel visibility.
		l.omni_range = 1.0 if spot[0] == "FloodNavigation" else 2.5
		l.light_energy = 0.55
		l.light_color = Color(1.0, 0.92, 0.82)
		l.shadow_enabled = false
		add_child(l)
