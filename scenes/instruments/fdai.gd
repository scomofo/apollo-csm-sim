## Flight Director Attitude Indicator. The ball stands for the reference
## frame and the case for the vehicle. Like the flown instrument, it shows
## the view from inside the ball: nose up puts sky at the centre, a right
## roll turns the horizon counter-clockwise, and a right yaw moves the
## markings left.
## Reads guid.indicator.attitude (Quaternion), which the CMC publishes: the
## CSM's attitude relative to the IMU's stable member, the ICDU angles, so
## the ball shows total attitude against REFSMMAT. Or, with [member vehicle]
## "lm", the LGC's lm.guid.indicator.attitude, relative to LVLH (orbit-rate
## mode): the LM flies level with its windows forward along the track and
## its +X up (Frames.LM_LEVEL), so that attitude reads level on its ball.
## Adapted from gemini-capsule at 40e449c (README.md lists the port). Its
## ball shows the outside view, as a gimballed sphere seen from behind:
## pitch and yaw read reversed. INSIDE_VIEW corrects that. Its ball is also
## set in world axes; here it turns relative to the case, so an instrument
## mounted on a tilted panel still shows a level horizon across its centre.
extends Node3D

@export var channel: String = "guid.indicator.attitude"
## Whose attitude the channel is: "csm" or "lm".
@export var vehicle: String = "csm"

## Mirror through the face plane. Conjugating the outside-view rotation by it
## reverses its pitch and yaw and keeps its roll: the inside view.
const INSIDE_VIEW: Basis = Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))

@onready var _ball: MeshInstance3D = $Ball


func _ready() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back;
varying vec3 p;
void vertex() { p = normalize(VERTEX); }
void fragment() {
	// Ball +Y = "up" (away from nadir), +Z = nose direction in the reference frame.
	float pitch = degrees(asin(clamp(p.y, -1.0, 1.0)));
	float yaw = degrees(atan(p.x, p.z));
	vec3 col = p.y > 0.0 ? vec3(0.55, 0.55, 0.58) : vec3(0.05, 0.05, 0.05);
	float pl = abs(fract(pitch / 30.0 + 0.5) - 0.5) * 30.0;
	float yl = abs(fract(yaw / 30.0 + 0.5) - 0.5) * 30.0 * cos(radians(pitch));
	float line = 1.0 - min(smoothstep(0.0, 1.2, pl), smoothstep(0.0, 1.2, yl));
	float horizon = 1.0 - smoothstep(0.0, 1.0, abs(pitch));
	col = mix(col, vec3(0.95), max(line * 0.7, horizon));
	ALBEDO = col;
	ROUGHNESS = 0.4;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_ball.material_override = mat
	Bus.subscribe(channel, _on_attitude)


func _on_attitude(q: Variant) -> void:
	if not (q is Quaternion):
		return
	# q maps LVLH-aligned body vectors to actual body vectors (in the LVLH
	# frame); taken from the vehicle's level attitude and into Godot axes,
	# it is the turn the ball shows.
	var r_godot := Frames.level_turn(q as Quaternion, vehicle)
	# r_godot.inverse() is the reference frame as seen from the case: the
	# outside view. The crew reads the inside view.
	_ball.basis = INSIDE_VIEW * r_godot.inverse() * INSIDE_VIEW
