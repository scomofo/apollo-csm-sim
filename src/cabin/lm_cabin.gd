## Eagle's cabin blockout (docs/ROADMAP.md, slice 3f): the LM ascent
## stage's crew compartment, a cylinder 92 in across and 42 in deep lying
## fore and aft, and the midsection behind it under the docking tunnel; the
## two forward windows, the overhead docking window and the forward hatch;
## the commander's station on the left and the LM pilot's on the right,
## where they stood, with their hand controllers; and panels 1 to 5, which
## CockpitLayout fills from data/cockpit/lm_controls.csv. The commander's
## window carries the landing point designator's scale.
##
## Built in the LM's body axes (+X up, +Y right, +Z forward, out of the
## windows) from the docking port at the top of the tunnel, where Docking
## has the drogue: Docking.lm_port_m() above the centre of mass of the LM
## or, staged, of its ascent stage. Its basis is Frames.LM_BODY_TO_GODOT,
## and it keeps itself about the centre of mass for the LM's configuration,
## where the space view draws the world from Eagle. The panels' identity
## follows the LM's: 1 the commander's flight displays and engine arming,
## 2 the LM pilot's, with the RCS, 3 between them, with the guidance mode,
## 4 the LGC's DSKY, and 5 by the commander's left hand, with the engine
## start and stop and the rate of descent switch; overhead between them the
## alignment optical telescope's eyepiece (slice 11a), its detent knob and
## the MARK X, MARK Y and REJECT buttons on its guard. Every dimension and
## position is [estimated]: the shapes follow the LM in outline only.
##
## Reads: lm.dyn.config
class_name LmCabin
extends Cabin

## Crew compartment: a cylinder along Z, its radius CC_R and its axis
## CC_AXIS_X below the port, from its aft end CC_AFT_Z to the front
## bulkhead FRONT_Z, 42 in deep.
const CC_R := 1.17
const CC_AXIS_X := -2.15
const CC_AFT_Z := 0.55
const FRONT_Z := 1.62
## The bulkheads reach a centimetre into the wall, so no crack shows where
## their chords and the wall's meet.
const BULKHEAD_R := CC_R + 0.01
## The floor, a chord of the cylinder 3.9 m above the footpads.
const FLOOR_X := -3.10
## Midsection: behind the crew compartment and under the tunnel, its
## floor raised over the ascent engine.
const MID_HALF_Y := 0.58
const MID_AFT_Z := -0.80
const MID_FLOOR_X := -2.80
const MID_TOP_X := -1.15
## Docking tunnel, up from the midsection's ceiling to the port.
const TUNNEL_R := 0.42
## The commander's and the LM pilot's eyes, standing: 1.6 m above the
## floor, 0.3 m behind the windows.
const EYE_CDR := Vector3(-1.50, -0.46, 1.32)
const EYE_LMP := Vector3(-1.50, 0.46, 1.32)
const SEATS := {"CDR": EYE_CDR, "LMP": EYE_LMP}
## Axes of a panel face on the front bulkhead, and of the player anchor,
## in body axes: +X to the crew's right (+Y), +Y their up (+X), +Z toward
## them (-Z).
const FACE_BASIS := Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1))
## The panels: face centre (m, body), size (m), and how the face is turned
## from facing straight aft: yawed toward the crew member who works it
## (deg, positive to the right) and tilted up (deg).
const PANELS := {
	"P1": {"centre": Vector3(-1.78, -0.155, 1.55), "size": Vector2(0.29, 0.36), "yaw": -20.0, "tilt": 0.0},
	"P2": {"centre": Vector3(-1.78, 0.155, 1.55), "size": Vector2(0.29, 0.36), "yaw": 20.0, "tilt": 0.0},
	"P3": {"centre": Vector3(-2.05, 0.0, 1.50), "size": Vector2(0.58, 0.16), "yaw": 0.0, "tilt": 35.0},
	"P4": {"centre": Vector3(-2.30, 0.0, 1.40), "size": Vector2(0.30, 0.34), "yaw": 0.0, "tilt": 45.0},
	"P5": {"centre": Vector3(-2.02, -0.80, 1.52), "size": Vector2(0.24, 0.22), "yaw": 35.0, "tilt": 15.0},
	"P6": {"centre": Vector3(-2.02, 0.80, 1.52), "size": Vector2(0.24, 0.22), "yaw": -35.0, "tilt": 15.0},
	"AOT": {"centre": Vector3(-1.15, 0.0, 1.45), "size": Vector2(0.32, 0.30), "yaw": 0.0, "tilt": -60.0},
}
## The forward windows in the front bulkhead, square to +Z: (Y, X) corners
## (m, body), wide at the top about eye level and narrowing to a point
## below and ahead of each eye, so the commander sees down to 65 deg.
const WINDOWS := {
	"CommanderWindow": [Vector2(-0.74, -1.42), Vector2(-0.28, -1.42), Vector2(-0.46, -2.24)],
	"PilotWindow": [Vector2(0.28, -1.42), Vector2(0.74, -1.42), Vector2(0.46, -2.24)],
}
## The overhead docking window above the commander: its angles round the
## cylinder from +X toward +Y (deg) and its extent along Z (m).
const OVERHEAD := {"theta_deg": Vector2(-24.0, -6.0), "z": Vector2(1.00, 1.40)}
## The forward hatch, low in the front bulkhead: (Y, X) extent, m.
const HATCH := Rect2(-0.41, FLOOR_X, 0.82, 0.82)
## The landing point designator on the commander's window: a mark every
## LPD_STEP_DEG from 0 to LPD_MAX_DEG below the LM's +Z, as seen from the
## commander's eye, and figures every LPD_FIGURE_DEG.
const LPD_STEP_DEG := 5
const LPD_MAX_DEG := 65
const LPD_FIGURE_DEG := 10
## Centre of the checklist card for the commander, by the left shoulder,
## 0.44 m from the eye (body, m); the LM pilot's is by the right.
const CARD_CENTRE := Vector3(-1.66, -0.86, 1.40)
## Wall mesh resolution: 5 cm along the cylinder, 2 deg around it.
const WALL_STEP_Z := 0.05
const WALL_STEP_DEG := 2.0

## The LPD's marks: degrees -> the mark's node.
var lpd_marks: Dictionary = {}


func _init() -> void:
	name = "LmCabin"
	basis = Frames.LM_BODY_TO_GODOT
	_build_shell()
	_build_stations()
	_build_panels()
	_build_lpd()
	_build_lights()
	_build_anchor()
	place("lm")


## A cabin with the shipped layout built onto its panels. Layout errors are
## reported and the rows that can be built still are.
static func create() -> LmCabin:
	var cabin := LmCabin.new()
	var layout := CockpitLayout.load_lm()
	if not layout.validate():
		for e in layout.errors:
			push_error("lm_controls.csv: " + e)
	cabin.items = layout.build(cabin)
	return cabin


func panels() -> Dictionary:
	var out := {}
	for p in PANELS:
		var d: Dictionary = PANELS[p]
		out[p] = {"centre": d["centre"], "size": d["size"], "basis": face(d["yaw"], d["tilt"])}
	return out


func seats() -> Dictionary:
	return SEATS


func eye_basis() -> Basis:
	return FACE_BASIS


## By the commander's left shoulder, or the LM pilot's right: each toward
## the wall on the outboard side.
func card_centre(seat_name: String) -> Vector3:
	return CARD_CENTRE if seat_name == "CDR" else Vector3(CARD_CENTRE.x, -CARD_CENTRE.y, CARD_CENTRE.z)


## The LGC's DSKY is on panel 4.
func computer(rt: SimRuntime) -> AgcCore:
	return rt.lgc()


func _process(_delta: float) -> void:
	place(str(Bus.get_value("lm.dyn.config", "lm")))


## Put the cabin where it is from the centre of mass of the LM in
## configuration [param cfg] ("lm", or "lm_ascent" once staged), the
## space view's origin: the port lm_port_m above it.
func place(cfg: String) -> void:
	position = Frames.LM_BODY_TO_GODOT * Vector3(Docking.lm_port_m(cfg), 0.0, 0.0)


## A panel face's axes (body), yawed [param yaw_deg] to the right about
## the vertical and tilted [param tilt_deg] up about its horizontal: its
## +X stays level.
static func face(yaw_deg: float, tilt_deg: float) -> Basis:
	return Basis(Vector3(1, 0, 0), deg_to_rad(yaw_deg)) * Basis(Vector3(0, 1, 0), deg_to_rad(-tilt_deg)) * FACE_BASIS


## Where the landing point designator's mark for [param deg] is (body):
## on the commander's window, straight ahead of the commander's eye,
## [param deg] below the LM's +Z.
static func lpd_mark(deg: float) -> Vector3:
	var d := FRONT_Z - EYE_CDR.z
	return Vector3(EYE_CDR.x - d * tan(deg_to_rad(deg)), EYE_CDR.y, FRONT_Z)


## A bulkhead's outline, (Y, X) in m: the cylinder's cross-section above
## the floor, an arc of BULKHEAD_R in 72 chords closed along the floor.
static func bulkhead_outline() -> PackedVector2Array:
	var theta_f := acos((FLOOR_X - CC_AXIS_X) / CC_R)
	var out := PackedVector2Array()
	for i in 73:
		var t := -theta_f + 2.0 * theta_f * i / 72.0
		out.append(Vector2(BULKHEAD_R * sin(t), CC_AXIS_X + BULKHEAD_R * cos(t)))
	return out


## The cylinder's half width at height x (body), or 0 above or below it.
static func half_width(x: float) -> float:
	var h := x - CC_AXIS_X
	return sqrt(CC_R * CC_R - h * h) if absf(h) < CC_R else 0.0


## Whether the cylinder's wall is open at angle [param theta_deg] (from
## +X toward +Y) and station [param z]: the overhead window.
static func overhead_at(theta_deg: float, z: float) -> bool:
	var t: Vector2 = OVERHEAD["theta_deg"]
	var zz: Vector2 = OVERHEAD["z"]
	return theta_deg > t.x and theta_deg < t.y and z > zz.x and z < zz.y


## The pressure shell: the crew compartment's wall, floor and bulkheads,
## the midsection and the tunnel.
func _build_shell() -> void:
	var wall := CabinMaterials.get_material("wall")
	var bulkhead := CabinMaterials.get_material("bulkhead")
	_build_wall(wall)
	var section := bulkhead_outline()
	var windows: Array = []
	for w in WINDOWS:
		windows.append(PackedVector2Array(WINDOWS[w]))
	var yx := [Vector3(0, 1, 0), Vector3(1, 0, 0)]
	add_child(Cabin._flat_face("FrontBulkhead", Vector3(0, 0, FRONT_Z), yx[0], yx[1], section, windows, bulkhead))
	var opening := PackedVector2Array([Vector2(-MID_HALF_Y, MID_FLOOR_X), Vector2(MID_HALF_Y, MID_FLOOR_X),
		Vector2(MID_HALF_Y, MID_TOP_X), Vector2(-MID_HALF_Y, MID_TOP_X)])
	add_child(Cabin._flat_face("AftBulkhead", Vector3(0, 0, CC_AFT_Z), yx[0], yx[1], section, [opening], bulkhead))
	# Floors (Y, Z): the crew compartment's, and the midsection's above it.
	var w := half_width(FLOOR_X)
	var floor_mat := CabinMaterials.get_material("dsky_case")
	var zy := [Vector3(0, 1, 0), Vector3(0, 0, 1)]
	add_child(Cabin._flat_face("Floor", Vector3(FLOOR_X, 0, 0), zy[0], zy[1], _rect(-w, CC_AFT_Z, w, FRONT_Z), [], floor_mat))
	add_child(Cabin._flat_face("MidsectionFloor", Vector3(MID_FLOOR_X, 0, 0), zy[0], zy[1],
		_rect(-MID_HALF_Y, MID_AFT_Z, MID_HALF_Y, CC_AFT_Z), [], floor_mat))
	# Midsection: its sides (X, Z), its aft wall (Y, X), and its ceiling
	# (Y, Z), open under the tunnel.
	for side in [-1.0, 1.0]:
		add_child(Cabin._flat_face("MidsectionSide" + ("Left" if side < 0.0 else "Right"), Vector3(0, side * MID_HALF_Y, 0),
			Vector3(1, 0, 0), Vector3(0, 0, 1), _rect(MID_FLOOR_X, MID_AFT_Z, MID_TOP_X, CC_AFT_Z), [], wall))
	add_child(Cabin._flat_face("MidsectionAft", Vector3(0, 0, MID_AFT_Z), yx[0], yx[1],
		_rect(-MID_HALF_Y, MID_FLOOR_X, MID_HALF_Y, MID_TOP_X), [], bulkhead))
	var hole := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		hole.append(Vector2(TUNNEL_R * cos(a), TUNNEL_R * sin(a)))
	add_child(Cabin._flat_face("MidsectionCeiling", Vector3(MID_TOP_X, 0, 0), zy[0], zy[1],
		_rect(-MID_HALF_Y, MID_AFT_Z, MID_HALF_Y, CC_AFT_Z), [hole], wall))
	_build_tunnel(bulkhead)
	# The ascent engine's cover on the midsection floor, and the forward
	# hatch in the front bulkhead.
	var cover := Cabin._box(self, "EngineCover", Vector3(MID_FLOOR_X + 0.2, 0.0, -0.12), Vector3(0.4, 0.8, 0.8),
		Basis.IDENTITY, bulkhead)
	cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	Cabin._box(self, "ForwardHatch", Vector3(HATCH.position.y + HATCH.size.y * 0.5, 0.0, FRONT_Z - 0.01),
		Vector3(HATCH.size.y, HATCH.size.x, 0.02), Basis.IDENTITY, floor_mat)


## The crew compartment's cylinder above the floor, open at the overhead
## window.
func _build_wall(mat: Material) -> void:
	var theta_f := rad_to_deg(acos((FLOOR_X - CC_AXIS_X) / CC_R))
	var n_theta := ceili(2.0 * theta_f / WALL_STEP_DEG)
	var n_z := ceili((FRONT_Z - CC_AFT_Z) / WALL_STEP_Z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n_theta:
		var t0 := -theta_f + 2.0 * theta_f * i / n_theta
		var t1 := -theta_f + 2.0 * theta_f * (i + 1) / n_theta
		for j in n_z:
			var z0 := CC_AFT_Z + (FRONT_Z - CC_AFT_Z) * j / n_z
			var z1 := CC_AFT_Z + (FRONT_Z - CC_AFT_Z) * (j + 1) / n_z
			if overhead_at((t0 + t1) * 0.5, (z0 + z1) * 0.5):
				continue
			var q := [_on_wall(t0, z0), _on_wall(t1, z0), _on_wall(t1, z1), _on_wall(t0, z1)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(q[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Wall"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(mi)


static func _on_wall(theta_deg: float, z: float) -> Vector3:
	var t := deg_to_rad(theta_deg)
	return Vector3(CC_AXIS_X + CC_R * cos(t), CC_R * sin(t), z)


## The docking tunnel up from the midsection's ceiling, closed at the top
## by the hatch and drogue.
func _build_tunnel(mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var q := [Vector3(MID_TOP_X, TUNNEL_R * cos(a0), TUNNEL_R * sin(a0)), Vector3(MID_TOP_X, TUNNEL_R * cos(a1), TUNNEL_R * sin(a1)),
			Vector3(0.0, TUNNEL_R * cos(a1), TUNNEL_R * sin(a1)), Vector3(0.0, TUNNEL_R * cos(a0), TUNNEL_R * sin(a0))]
		for k in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(q[k])
		for k in [[0.0, 0.0], [a0, TUNNEL_R], [a1, TUNNEL_R]]:
			st.add_vertex(Vector3(-0.04, float(k[1]) * cos(k[0]), float(k[1]) * sin(k[0])))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Tunnel"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(mi)


## The two stations' hand controllers: the ACA at the right hand, the TTCA
## at the left. Not grabbed yet: the keys and thumbsticks fly them
## (HandControllerInput).
func _build_stations() -> void:
	var grip := CabinMaterials.get_material("dsky_case")
	var frame := CabinMaterials.get_material("bulkhead")
	for s in [["Commander", -1.0], ["Pilot", 1.0]]:
		var side: float = s[1]
		# Each crew member's ACA is by the right hand and TTCA by the left:
		# the commander's ACA inboard, the LM pilot's outboard.
		for c in [["ACA", 0.22 if side < 0.0 else 0.70], ["TTCA", 0.70 if side < 0.0 else 0.22]]:
			var y := side * float(c[1])
			var prefix: String = str(s[0]) + str(c[0])
			Cabin._box(self, prefix + "Mount", Vector3(-2.26, y, 1.44), Vector3(0.05, 0.07, 0.16), Basis.IDENTITY, frame)
			Cabin._box(self, prefix, Vector3(-2.15, y, 1.40), Vector3(0.14, 0.04, 0.05), Basis.IDENTITY, grip)


## Floodlights overhead, so the panels and the card are lit; otherwise
## only the windows let light in.
func _build_lights() -> void:
	for spot in [["FloodLeft", Vector3(-1.10, -0.50, 1.10)], ["FloodRight", Vector3(-1.10, 0.50, 1.10)],
			["FloodAft", Vector3(-1.30, 0.0, 0.30)]]:
		var l := OmniLight3D.new()
		l.name = spot[0]
		l.position = spot[1]
		l.omni_range = 2.0
		l.light_energy = 0.45
		l.light_color = Color(1.0, 0.95, 0.86)
		l.shadow_enabled = false
		add_child(l)


## The landing point designator: marks on the commander's window every
## LPD_STEP_DEG, as seen from the commander's eye, with figures every
## LPD_FIGURE_DEG. The LGC's N64 gives the angle at which to look for the
## landing point.
func _build_lpd() -> void:
	var root := Node3D.new()
	root.name = "LPD"
	add_child(root)
	var mat := CabinMaterials.get_material("lpd")
	for deg in range(0, LPD_MAX_DEG + 1, LPD_STEP_DEG):
		var at := lpd_mark(deg) - Vector3(0, 0, 0.004)
		var long := deg % LPD_FIGURE_DEG == 0
		var mark := Cabin._box(root, "Mark%d" % deg, at, Vector3(0.0015, 0.030 if long else 0.018, 0.001), Basis.IDENTITY, mat)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lpd_marks[deg] = mark
		if long:
			var l := CockpitLayout._text(root, "Figure%d" % deg, str(deg), Vector3.ZERO, 0.0055, CabinMaterials.lpd_colour())
			l.transform = Transform3D(FACE_BASIS, at + Vector3(0, 0.030, 0))


static func _rect(u0: float, v0: float, u1: float, v1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
