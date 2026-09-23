## OpenXR seated rig. The rig's parent (PlayerAnchor) sits at the design eye
## point of the commander's couch; recenter() moves the tracked head there.
## Recentering happens on session start, when the runtime reports a recenter
## (the user's own headset recenter gesture) and on the B/Y button of either
## controller (gemini-capsule's docs/VR_INTERACTION.md §4). The cabin never
## moves; only this origin does.
## Taken from gemini-capsule at 40e449c (README.md lists the port).
extends XROrigin3D

## Controller action that triggers a snap recenter.
const RECENTER_ACTION := "by_button"

@onready var _camera: XRCamera3D = $XRCamera3D
var recenter_count := 0
## Seated-height calibration: raise (+) or lower (-) the eye relative to the
## design eye point, metres. Set from the wrist menu, applied on recenter.
var height_offset := 0.0


func _ready() -> void:
	for hand in [$LeftHand, $RightHand]:
		hand.button_pressed.connect(_on_button.bind(hand.name))
	var xr := XRServer.find_interface("OpenXR")
	if xr != null:
		if not xr.pose_recentered.is_connected(recenter):
			xr.pose_recentered.connect(recenter)
		if not xr.session_begun.is_connected(recenter):
			xr.session_begun.connect(recenter)
	call_deferred("recenter")


func _on_button(action: String, _hand: String) -> void:
	if action == RECENTER_ACTION:
		recenter()


## Move the origin so that the current head position lands on the anchor
## (the design eye point), and yaw so the user faces -Z. Cabin geometry
## never moves.
func recenter() -> void:
	var head := _camera.transform
	# Heading of the head's forward (-Z) axis about +Y: a user turned left
	# by 30 degrees gives +30, and the origin is yawed by -30 so the cabin's
	# -Z is straight ahead again. (The earlier atan2(-z.x, -z.z) was the
	# heading of +Z, 180 degrees out: the user would face the aft bulkhead.)
	var yaw := atan2(head.basis.z.x, head.basis.z.z)
	var offset := Basis(Vector3.UP, -yaw) * head.origin
	transform = Transform3D(Basis(Vector3.UP, -yaw), -offset + Vector3(0, height_offset, 0))
	recenter_count += 1
	Bus.set_value("player.recenter_count", recenter_count)
