## The view through the LM's alignment optical telescope (src/systems/
## aot.gd): its Aot.FIELD_DEG field, round, centred on the detent's line of
## sight, its up along the reticle's Y-line and its right along the X-line
## (turned against the LM in the side and rear detents, as the flown
## field appeared turned). It shows the navigation stars (dots by
## magnitude) and the Earth, the Moon and the Sun where they are, from the
## LM's true attitude and position, and the reticle over them, turned
## clockwise by the reticle knob (slice 11b): the Y-line, the X-line and
## the pair of one-turn spirals from the centre to the Y-line's top, each
## point of them Aot.SPIRAL_RATIO of the reticle's turn back to the
## Y-line out from the centre [adapted: the pair drawn as a double line
## either side of that, SPIRAL_GAP_DEG apart], and under it the counter's
## reading. In the rear detent (CL) the prism is stowed: nothing shows.
## With [member names] it names the stars it shows [aid: the flown AOT
## named none].
##
## Reads: lm.dyn.att_q, lm.dyn.r_m, lm.dyn.primary, time.get_s,
##        lm.aot.detent, lm.aot.reticle_deg, lm.dsky.verb, lm.dsky.noun
class_name AotView
extends OpticsView

const DETENT_NAMES := ["", "LEFT FRONT", "FRONT", "RIGHT FRONT", "RIGHT REAR", "CL (STOWED)", "LEFT REAR"]
const SPIRAL := Color(0.9, 0.35, 0.2, 0.6)
## The spirals' spacing, deg of the field [estimated].
const SPIRAL_GAP_DEG := 0.25


## The view axes in ECI now: right, up, line of sight.
static func aot_axes_eci() -> Array:
	var b := Basis(Bus.get_value("lm.dyn.att_q", Quaternion.IDENTITY) as Quaternion)
	var ax := Aot.view_axes(int(Bus.get_value("lm.aot.detent", 2)))
	return [b * (ax[0] as Vector3), b * (ax[1] as Vector3), b * (ax[2] as Vector3)]


func _draw() -> void:
	var r := minf(size.x, size.y - 40.0) / 2.0 - 6.0
	var c := Vector2(size.x / 2.0, 18.0 + r + 2.0)
	var detent := int(Bus.get_value("lm.aot.detent", 2))
	var f := font if font != null else get_theme_default_font()
	draw_circle(c, r, SKY)
	if detent != Aot.CL:
		_sky(c, r, aot_axes_eci())
	var turn := float(Bus.get_value("lm.aot.reticle_deg", 0.0))
	_reticle(c, r, turn)
	draw_arc(c, r, 0.0, TAU, 96, RIM, 2.0)
	draw_string(f, Vector2(size.x - 130.0, size.y - 6.0), "COUNTER %06.2f" % snappedf(turn, 0.01),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85))
	draw_string(f, Vector2(c.x - r, 14.0), "AOT %d°  DETENT %d %s" % [int(Aot.FIELD_DEG), detent, DETENT_NAMES[detent]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RIM)
	var verb := str(Bus.get_value("lm.dsky.verb", ""))
	var marks := {"54": "MARK X OR Y", "53": "MARK Y", "52": "MARK X"}
	var want := str(marks.get(verb, "")) if str(Bus.get_value("lm.dsky.noun", "")) == "71" else ""
	draw_string(f, Vector2(8.0, size.y - 6.0), "AZ %+04d  EL %d   %s" % [int(Aot.azimuth(detent)), int(Aot.ELEVATION_DEG), want],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85))


## The stars and the Earth, the Moon and the Sun, along [param axes].
func _sky(c: Vector2, r: float, axes: Array) -> void:
	var fov := Aot.FIELD_DEG
	var half := deg_to_rad(fov) / 2.0
	var los: Vector3 = axes[2]
	var near := bodies("lm.")
	var rim := PackedVector2Array()
	for i in 64:
		rim.append(c + Vector2.from_angle(TAU * i / 64.0) * r)
	_discs(c, r, fov, axes, near, rim, 1.0)
	var f := font if font != null else get_theme_default_font()
	for code in Stars.codes():
		var s := Stars.direction(code)
		if los.angle_to(s) > half:
			continue
		var hidden := false
		for i in 2:
			if s.angle_to(near[i][0]) < deg_to_rad(float(near[i][1])):
				hidden = true
		if hidden:
			continue
		var p: Vector2 = project(s, axes, c, r, fov)
		var size_px := clampf(3.2 - 0.6 * Stars.magnitude(code), 1.3, 4.5)
		draw_circle(p, size_px * 2.0, Color(1.0, 1.0, 0.9, 0.15))
		draw_circle(p, size_px, Color(1.0, 1.0, 0.95))
		if names:
			draw_string(f, p + Vector2(6.0, -4.0), "%s %s" % [Stars.label(code).substr(3), Stars.name_of(code)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0, 0.85))


## The reticle turned [param turn] deg clockwise: the Y-line up the field
## and down, the X-line across it, and the two spirals, each a turn from
## the centre out to the Y-line's top.
func _reticle(c: Vector2, r: float, turn: float) -> void:
	var k := r / tan(deg_to_rad(Aot.FIELD_DEG) / 2.0)
	var t := deg_to_rad(turn)
	var up := Vector2(sin(t), -cos(t))
	draw_line(c - up * r, c + up * r, RETICLE, 1.0)
	draw_line(c - up.orthogonal() * r, c + up.orthogonal() * r, RETICLE, 1.0)
	for side in [-0.5, 0.5]:
		var pts := PackedVector2Array()
		for i in 181:
			# The reticle's angle back from the Y-line's top, anticlockwise.
			var psi := TAU * i / 180.0
			var off := deg_to_rad(maxf(rad_to_deg(psi) * Aot.SPIRAL_RATIO + side * SPIRAL_GAP_DEG, 0.0))
			pts.append(c + Vector2(sin(t - psi), -cos(t - psi)) * tan(off) * k)
		draw_polyline(pts, SPIRAL, 1.0)
