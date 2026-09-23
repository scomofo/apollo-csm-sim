## Base for every panel control. Subclasses implement actuate() and, for
## spring-loaded controls, release(); this class owns the touch volume, the
## bus binding, and the far-field click contract.
##
##   actuate(dir)  dir = +1 push up / -1 push down / 0 cycle (far-field click)
##   release()     finger left the control / far-field click ended
##
## Subclasses choose which finger motion counts by overriding
## _touch_direction(). Nothing changes on hover: only a crossing actuates.
## Taken from gemini-capsule at 40e449c (README.md lists the port), with
## one addition for the headset acceptance recorder: a fingertip crossing
## also names the control on player.last_touch_label, so presses of the
## DSKY keys and the wrist menu, which write no channel, can be told apart.
class_name ControlBase
extends Node3D

## Bus channel this control publishes to.
@export var channel: String = ""
@export var label: String = ""
## Ignore repeated touches within this many seconds.
@export var retrigger_s: float = 0.25
## How long a far-field click "holds" a spring-loaded control.
@export var far_hold_s: float = 0.25

## Presentation buttons can remain usable during time acceleration. A bound
## simulation channel always keeps the normal aircraft-control lock.
var presentation_only: bool = false

var _touch: Area3D
var _last_touch_time: float = -1.0
var _touching: Area3D


func _ready() -> void:
	_touch = get_node_or_null("Touch")
	if _touch == null:
		_touch = Area3D.new()
		_touch.name = "Touch"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.03, 0.05, 0.05)
		shape.shape = box
		_touch.add_child(shape)
		add_child(_touch)
	_touch.monitorable = true
	_touch.monitoring = true
	_touch.area_entered.connect(_on_area_entered)
	_touch.area_exited.connect(_on_area_exited)


func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("interactor") or not _interaction_allowed():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_touch_time < retrigger_s:
		return
	_last_touch_time = now
	_touching = area
	var v_local: Vector3 = global_transform.basis.inverse() * (area as Interactor).velocity
	var dir := _touch_direction(v_local)
	if dir != 0:
		# Evidence for the headset gate, published before the control's own
		# channel so a subscriber sees the source with the state change:
		# this actuation came from a fingertip crossing, not a far-field
		# click or a script. The count goes last, so its subscribers see
		# which control and channel it was.
		Bus.set_value("player.last_touch_label", label if label != "" else str(name))
		Bus.set_value("player.last_touch_channel", channel)
		Bus.set_value("player.touch_actuations", int(Bus.get_value("player.touch_actuations", 0)) + 1)
		actuate(dir)


func _on_area_exited(area: Area3D) -> void:
	if area == _touching:
		_touching = null
		release()


## Map the finger's local velocity to an actuation direction. Default: the
## finger crossing the lever vertically.
func _touch_direction(v_local: Vector3) -> int:
	return 1 if v_local.y > 0.0 else -1


## Far-field (pointer) actuation: actuate now, release after far_hold_s.
func actuate_far(dir: int) -> void:
	if not _interaction_allowed():
		return
	actuate(dir)
	if is_inside_tree():
		get_tree().create_timer(far_hold_s).timeout.connect(release)


## Shared near/far policy. Hidden in-tree controls cannot receive physical
## input; direct actuate() remains available to procedure automation.
func _interaction_allowed() -> bool:
	if is_inside_tree() and not is_visible_in_tree():
		return false
	return not SimClock.controls_locked() or (presentation_only and channel.is_empty())


## Implemented by subclasses.
func actuate(_dir: int) -> void:
	pass


## Called when the finger or pointer lets go. Spring-loaded controls return.
func release() -> void:
	pass
