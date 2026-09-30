## What Columbia's cabin (CmCabin) and Eagle's (LmCabin) share: the
## player's anchor at a seat's eye, the checklist card's mount, and the
## panels CockpitLayout builds the cabin's controls and displays onto, from
## its controls file. Each cabin is built in its vehicle's body axes, and
## its node's basis turns them into the render axes, where the anchor looks
## along -Z with the crew's up on +Y, as the space view draws the world.
class_name Cabin
extends Node3D

## Where the player's rig goes: the seat's eye, looking along -Z with the
## crew's up on +Y. Its global basis is the identity in the space view.
var anchor: Node3D
## The seat the anchor is at (a seats() key).
var seat: String = ""
## Where the checklist card goes: +Z faces the seat's eye, +Y is the
## crew's up.
var card_mount: Node3D
## CockpitLayout.build() output: row id -> node.
var items: Dictionary = {}
var _panels: Dictionary = {}


# --- the cabin's own (CmCabin and LmCabin override these) -------------------

## The panels CockpitLayout places rows on: name -> {"centre": the face's
## centre (body, m), "size": its size (m), and "basis": its axes in body
## axes, x to the right and y up across the face and z toward the crew}.
func panels() -> Dictionary:
	return {}


## Seat name -> the seat's eye (body, m); the commander's first.
func seats() -> Dictionary:
	return {}


## The anchor's axes in body axes: x the crew's right, y their up and z
## behind them.
func eye_basis() -> Basis:
	return Basis.IDENTITY


## The anchor's axes at [param seat_name]: eye_basis(), unless a station
## faces elsewhere.
func seat_basis(_seat_name: String) -> Basis:
	return eye_basis()


## Where the checklist card's centre is (body, m) for [param seat_name].
func card_centre(_seat_name: String) -> Vector3:
	return Vector3.ZERO


## The computer the cabin's DSKY types into.
func computer(rt: SimRuntime) -> AgcCore:
	return rt.agc()


# --- shared ----------------------------------------------------------------

## The anchor and the card's mount, at the commander's seat.
func _build_anchor() -> void:
	anchor = Node3D.new()
	anchor.name = "PlayerAnchor"
	anchor.transform = Transform3D(eye_basis(), Vector3.ZERO)
	add_child(anchor)
	card_mount = Node3D.new()
	card_mount.name = "CardMount"
	add_child(card_mount)
	set_seat(seats().keys()[0])


## Move the player's anchor to [param seat_name]'s eye, and the checklist
## card to that seat's. The rig rides on the anchor, so the player moves
## too; the cabin never does.
func set_seat(seat_name: String) -> void:
	var s := seats()
	if not s.has(seat_name):
		return
	seat = seat_name
	var eye: Vector3 = s[seat_name]
	anchor.transform = Transform3D(seat_basis(seat_name), eye)
	var at := card_centre(seat_name)
	card_mount.transform = Transform3D(Basis.looking_at(at - eye, seat_basis(seat_name).y), at)
	Bus.set_value("player.seat", seat_name)


## The next seat round the cabin, for the wrist menu's SEAT.
func next_seat() -> void:
	var names := seats().keys()
	set_seat(names[(names.find(seat) + 1) % names.size()])


## Hand the cabin DSKY its computer's keyboard.
func connect_runtime(rt: SimRuntime) -> void:
	for id in items:
		if items[id] is CabinDsky:
			(items[id] as CabinDsky).dsky = computer(rt).dsky


## The attachment frame of a panel face: x/y are panel coordinates (m) and
## +Z faces the crew.
func panel_node(panel_name: String) -> Node3D:
	return _panels.get(panel_name)


## Each panel's face: a plate its rows are built onto.
func _build_panels() -> void:
	var root := Node3D.new()
	root.name = "Panels"
	add_child(root)
	var all := panels()
	for panel_name in all:
		var p: Dictionary = all[panel_name]
		var size: Vector2 = p["size"]
		var mount := Node3D.new()
		mount.name = panel_name
		mount.transform = Transform3D(p["basis"], p["centre"])
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
		_add_panel_hardware(mount, size)
		_panels[panel_name] = mount


## A narrow black reveal and real geometry at the panel corners keep the MDC
## from reading as one unbroken grey slab.  Fasteners stand just proud of the
## face so the grazing cabin light gives each one a highlight and a shadow.
func _add_panel_hardware(mount: Node3D, size: Vector2) -> void:
	var edge := CabinMaterials.get_material("panel_edge")
	var fastener := CabinMaterials.get_material("fastener")
	const REVEAL := 0.006
	const FACE_Z := 0.003
	for item in [
		["RevealTop", Vector3(0.0, size.y * 0.5, FACE_Z), Vector3(size.x, REVEAL, REVEAL)],
		["RevealBottom", Vector3(0.0, -size.y * 0.5, FACE_Z), Vector3(size.x, REVEAL, REVEAL)],
		["RevealLeft", Vector3(-size.x * 0.5, 0.0, FACE_Z), Vector3(REVEAL, size.y, REVEAL)],
		["RevealRight", Vector3(size.x * 0.5, 0.0, FACE_Z), Vector3(REVEAL, size.y, REVEAL)],
	]:
		var strip := MeshInstance3D.new()
		strip.name = item[0]
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = item[2]
		strip.mesh = strip_mesh
		strip.position = item[1]
		strip.material_override = edge
		mount.add_child(strip)
	var inset := 0.018
	var fastener_index := 0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var screw := MeshInstance3D.new()
		screw.name = "Fastener%d" % fastener_index
		fastener_index += 1
		var screw_mesh := CylinderMesh.new()
		screw_mesh.top_radius = 0.006
		screw_mesh.bottom_radius = 0.006
		screw_mesh.height = 0.003
		screw_mesh.radial_segments = 12
		screw.mesh = screw_mesh
		# CylinderMesh points along Y; its cap must face along panel +Z.
		screw.rotation.x = PI * 0.5
		screw.position = Vector3(corner.x * (size.x * 0.5 - inset), corner.y * (size.y * 0.5 - inset), 0.006)
		screw.material_override = fastener
		mount.add_child(screw)


## A flat face through [param origin] (body) spanned by [param u] and
## [param v]: [param outline], in (u, v) metres, less [param holes], each
## inside it. A band boundary runs through the middle of every hole, so no
## band holds a whole hole, and what is left of each band is a set of
## simple polygons to triangulate.
static func _flat_face(node_name: String, origin: Vector3, u: Vector3, v: Vector3, outline: PackedVector2Array,
		holes: Array, mat: Material) -> MeshInstance3D:
	var lo := INF
	var hi := -INF
	var left := INF
	var right := -INF
	for p in outline:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		left = minf(left, p.x)
		right = maxf(right, p.x)
	var edges: Array[float] = [lo - 1.0, hi + 1.0]
	for h: PackedVector2Array in holes:
		var h_lo := INF
		var h_hi := -INF
		for p in h:
			h_lo = minf(h_lo, p.y)
			h_hi = maxf(h_hi, p.y)
		edges.append((h_lo + h_hi) * 0.5)
	edges.sort()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in edges.size() - 1:
		if edges[i + 1] - edges[i] < 1e-6:
			continue
		var band := PackedVector2Array([Vector2(left - 1.0, edges[i]), Vector2(right + 1.0, edges[i]),
			Vector2(right + 1.0, edges[i + 1]), Vector2(left - 1.0, edges[i + 1])])
		var pieces: Array = Geometry2D.intersect_polygons(outline, band)
		for h: PackedVector2Array in holes:
			var cut: Array = []
			for piece: PackedVector2Array in pieces:
				cut.append_array(Geometry2D.clip_polygons(piece, h))
			pieces = cut
		for piece: PackedVector2Array in pieces:
			var tris := Geometry2D.triangulate_polygon(piece)
			for k in range(0, tris.size(), 3):
				for j in [0, 1, 2]:
					var p := piece[tris[k + j]]
					st.add_vertex(origin + u * p.x + v * p.y)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	# Both faces cast, or the Sun lights the cabin through its own walls.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	return mi


## A box [param size] (m) centred at [param centre] (body), its axes
## [param axes].
static func _box(parent: Node3D, node_name: String, centre: Vector3, size: Vector3, axes: Basis, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(axes, centre)
	parent.add_child(mi)
	return mi
