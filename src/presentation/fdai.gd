## Simplified Flight Director Attitude Indicator: an attitude "ball" drawn
## relative to the local horizontal (LVLH), with body-rate needles on the
## edges and the computer's attitude-error needles across the face. It
## shows the CSM (vehicle "csm": nose along body X, crew's down along Z) or
## the LM ("lm": windows along body Z, crew's down along -X), each with
## its own computer's errors.
class_name Fdai
extends Control

## "csm" or "lm".
var vehicle: String = "csm"


func _process(_delta: float) -> void:
	queue_redraw()


## [param v] (body axes of [param vehicle]) as the crew's roll, pitch and
## yaw, positive right, up and right: the CSM's body axes are already; the
## LM rolls about Z, pitches about Y and yaws about -X.
static func crew_axes(v: Vector3, p_vehicle: String) -> Vector3:
	return Vector3(v.z, v.y, -v.x) if p_vehicle == "lm" else v


func _draw() -> void:
	var p := "lm." if vehicle == "lm" else ""
	var c := size / 2.0
	var rad := minf(size.x, size.y) / 2.0 - 12.0
	draw_circle(c, rad + 2.0, Color(0.05, 0.05, 0.05))
	var q: Quaternion = Bus.get_value(p + "dyn.att_q", Quaternion.IDENTITY)
	var r: Array = Bus.get_value(p + "dyn.r_m", [1.0, 0.0, 0.0])
	var v: Array = Bus.get_value(p + "dyn.v_mps", [0.0, 1.0, 0.0])
	var lv := Trajectory.lvlh_basis(Vector3(r[0], r[1], r[2]), Vector3(v[0], v[1], v[2]))
	var b := Basis(q)
	var lm := vehicle == "lm"
	var fwd := lv.inverse() * (b * (Vector3(0, 0, 1) if lm else Vector3(1, 0, 0)))   # nose in LVLH
	var down_body := lv.inverse() * (b * (Vector3(-1, 0, 0) if lm else Vector3(0, 0, 1)))
	var pitch := asin(clampf(-fwd.z, -1.0, 1.0))          # nose above horizon
	var roll := atan2(down_body.y, down_body.z)
	# Horizon: sky (light) above, ground (dark) below, filled as wedges.
	var off := pitch / (PI / 2.0) * rad
	var dir := Vector2(cos(-roll), sin(-roll))
	var nrm := Vector2(-dir.y, dir.x)
	for i in 64:
		var a := TAU * i / 64.0
		var pt := c + Vector2(cos(a), sin(a)) * rad
		var sky := (pt - c - nrm * off).dot(nrm) < 0.0
		draw_line(c, pt, Color(0.75, 0.75, 0.72) if sky else Color(0.22, 0.22, 0.24), rad * TAU / 64.0 + 1.0)
	var h0 := c + nrm * off - dir * rad
	var h1 := c + nrm * off + dir * rad
	draw_line(h0, h1, Color(1, 1, 1), 2.0)
	draw_arc(c, rad, 0, TAU, 64, Color(0.6, 0.6, 0.6), 2.0)
	# Fixed aircraft symbol.
	draw_line(c + Vector2(-rad * 0.5, 0), c + Vector2(-rad * 0.15, 0), Color(1, 0.6, 0.1), 3.0)
	draw_line(c + Vector2(rad * 0.15, 0), c + Vector2(rad * 0.5, 0), Color(1, 0.6, 0.1), 3.0)
	# Attitude-error needles (the computer's): yaw vertical bar, pitch
	# horizontal bar.
	var e := crew_axes(Bus.get_value(p + "guid.att_error_deg", Vector3.ZERO), vehicle)
	var ex := clampf(e.z / 15.0, -1.0, 1.0) * rad * 0.8
	var ey := clampf(-e.y / 15.0, -1.0, 1.0) * rad * 0.8
	draw_line(c + Vector2(ex, -rad * 0.8), c + Vector2(ex, rad * 0.8), Color(0.9, 0.2, 0.9), 1.5)
	draw_line(c + Vector2(-rad * 0.8, ey), c + Vector2(rad * 0.8, ey), Color(0.9, 0.2, 0.9), 1.5)
	# Rate needles (±2 °/s full scale): roll top, pitch right, yaw bottom.
	var w := crew_axes(Bus.get_value(p + "dyn.omega", Vector3.ZERO), vehicle)
	var k := rad / deg_to_rad(2.0)
	draw_rect(Rect2(c + Vector2(clampf(w.x * k, -rad, rad) - 2, -rad - 10), Vector2(4, 8)), Color(1, 1, 0.3))
	draw_rect(Rect2(c + Vector2(rad + 2, clampf(-w.y * k, -rad, rad) - 2), Vector2(8, 4)), Color(1, 1, 0.3))
	draw_rect(Rect2(c + Vector2(clampf(w.z * k, -rad, rad) - 2, rad + 2), Vector2(4, 8)), Color(1, 1, 0.3))
