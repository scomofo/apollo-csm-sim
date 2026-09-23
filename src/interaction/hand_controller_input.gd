## Publishes the crew's hand controllers: the rotation controller (ctl.rhc,
## roll/pitch/yaw, each -1..1) and the translation controller (ctl.thc,
## X/Y/Z). The keyboard and, when a headset runs, the XR thumbsticks feed
## the same channels, so nothing downstream knows which one moved.
##
## Keyboard (as it always was in scenes/main.gd):
##   W/S pitch down / up (stick forward / back), A/D yaw left / right,
##   Q/E roll left / right, Shift for 10 % deflection;
##   R/F +X / -X (ullage), Left/Right -Y / +Y, Up/Down -Z / +Z.
## XR thumbsticks, provisional until the headset run (docs/ROADMAP.md, 2e):
##   right stick pitch (forward = nose down) and yaw, left stick X roll, as
##   in gemini-capsule. With the left grip held they fly the translation
##   controller instead: left stick +/-Y and up/down (forward = up, -Z),
##   right stick forward/back +/-X. Each stick axis reads zero within
##   STICK_DEADZONE of centre, as each RHC axis has a breakout detent, so a
##   stick resting off centre or drifting commands nothing; beyond it the
##   command runs from 0 to 1.
## Above the interactive time-rate limit both controllers read zero.
##
## Adapted from gemini-capsule at 40e449c (README.md lists the port), which
## writes scalar ctl.hand_controller.* channels for Gemini's single
## attitude controller.
## Writes: ctl.rhc, ctl.thc
class_name HandControllerInput
extends Node

## Thumbstick deflection that reads as centred, per axis [estimated]: worn
## sticks rest a few per cent off centre, and CMC MODE FREE and a manual
## entry bank take the command without a deadband of their own.
const STICK_DEADZONE := 0.15

@export var left_hand_path: NodePath
@export var right_hand_path: NodePath

var _left: XRController3D
var _right: XRController3D


## One that reads [param xr_rig]'s thumbsticks as well as the keys.
static func for_xr_rig(xr_rig: Node3D) -> HandControllerInput:
	var hci := HandControllerInput.new()
	hci.left_hand_path = xr_rig.get_node("LeftHand").get_path()
	hci.right_hand_path = xr_rig.get_node("RightHand").get_path()
	return hci


func _ready() -> void:
	_left = get_node_or_null(left_hand_path)
	_right = get_node_or_null(right_hand_path)


func _process(_delta: float) -> void:
	if SimClock.controls_locked():
		Bus.set_value("ctl.rhc", Vector3.ZERO)
		Bus.set_value("ctl.thc", Vector3.ZERO)
		return
	var keys := keyboard_commands(Callable(Input, "is_key_pressed"))
	var sticks := stick_commands(_stick(_left), _stick(_right), _grip(_left))
	Bus.set_value("ctl.rhc", (keys[0] + sticks[0]).clamp(-Vector3.ONE, Vector3.ONE))
	Bus.set_value("ctl.thc", (keys[1] + sticks[1]).clamp(-Vector3.ONE, Vector3.ONE))


## [rhc, thc] from the keyboard. [param pressed] is Callable(Key) -> bool.
static func keyboard_commands(pressed: Callable) -> Array[Vector3]:
	var k := 0.1 if pressed.call(KEY_SHIFT) else 1.0
	var rhc := Vector3(
		_axis(pressed, KEY_E, KEY_Q),     # roll right / left
		_axis(pressed, KEY_S, KEY_W),     # pitch up (stick back) / down
		_axis(pressed, KEY_D, KEY_A)) * k # yaw right / left
	var thc := Vector3(_axis(pressed, KEY_R, KEY_F), _axis(pressed, KEY_RIGHT, KEY_LEFT),
		_axis(pressed, KEY_DOWN, KEY_UP))
	return [rhc, thc]


## [rhc, thc] from the thumbsticks (Godot's +y is pushed forward).
## [param translate]: the left grip is held.
static func stick_commands(left: Vector2, right: Vector2, translate: bool) -> Array[Vector3]:
	if translate:
		return [Vector3.ZERO, Vector3(right.y, left.x, -left.y)]
	return [Vector3(left.x, -right.y, right.x), Vector3.ZERO]


static func _axis(pressed: Callable, pos: Key, neg: Key) -> float:
	return (1.0 if pressed.call(pos) else 0.0) - (1.0 if pressed.call(neg) else 0.0)


static func _stick(hand: XRController3D) -> Vector2:
	return deadzone(hand.get_vector2("primary")) if hand and hand.get_is_active() else Vector2.ZERO


## [param v] with each axis zero within STICK_DEADZONE of centre, rescaled
## to run from 0 to 1 beyond it.
static func deadzone(v: Vector2) -> Vector2:
	return Vector2(_deadzone(v.x), _deadzone(v.y))


static func _deadzone(x: float) -> float:
	if absf(x) <= STICK_DEADZONE:
		return 0.0
	return signf(x) * minf(1.0, (absf(x) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE))


static func _grip(hand: XRController3D) -> bool:
	return hand != null and hand.get_is_active() and hand.get_float("grip") > 0.5
