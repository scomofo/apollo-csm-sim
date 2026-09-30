## The LM's alignment optical telescope's eyepiece, overhead between the
## crew: the view through it (src/presentation/aot_view.gd), rendered in a
## SubViewport and shown on the panel's face [simplified: a screen in place
## of the eyepiece the crew looked up into]. It reads the AOT's channels
## itself; [member channel] names their group.
extends Node3D

## The face (m), and the view's resolution (px).
const SIZE := Vector2(0.18, 0.20)
const PIXELS := Vector2i(360, 400)

@export var channel: String = "lm.aot"

var view: AotView
var viewport: SubViewport


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "View"
	viewport.size = PIXELS
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.025)
	bg.size = Vector2(PIXELS)
	viewport.add_child(bg)
	view = AotView.new()
	view.size = Vector2(PIXELS)
	view.names = false
	viewport.add_child(view)
	var face := MeshInstance3D.new()
	face.name = "Face"
	var q := QuadMesh.new()
	q.size = SIZE
	face.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	face.material_override = mat
	face.position.z = 0.004
	add_child(face)
	var bezel := MeshInstance3D.new()
	bezel.name = "Bezel"
	var b := BoxMesh.new()
	b.size = Vector3(SIZE.x + 0.02, SIZE.y + 0.02, 0.006)
	bezel.mesh = b
	bezel.material_override = CabinMaterials.get_material("dsky_case")
	add_child(bezel)
