## The view through the CSM's optics (src/systems/optics.gd): the scanning
## telescope's FIELD_SCT_DEG field and the sextant's FIELD_SXT_DEG, side by
## side, each round and centred on the star line, its image's right the
## way the shaft turns and its up the way the trunnion rises. They show the
## navigation stars (dots by magnitude) and the Earth, the Moon and the Sun
## where they are, from the CSM's true attitude and position, with a
## reticle at the centre. The sextant lays its landmark line's image of the
## Earth and the Moon over the star line's, fainter, for P23's star on a
## horizon [simplified: the landmark line's stars are left out]. With
## [member names] on the telescope names the stars it shows [aid: the
## flown optics named none, and showed the fainter stars too]. P22's
## landmark is ringed where it lies [aid: the Moon's disc here has no
## surface to find it on].
##
## Reads: dyn.att_q, dyn.r_m, dyn.primary, time.get_s, optics.shaft_deg,
##        optics.trunnion_deg, optics.mode, guid.landmark_mf
class_name OpticsView
extends Control

const SKY := Color(0.01, 0.01, 0.02)
const RIM := Color(0.45, 0.45, 0.45)
const RETICLE := Color(0.9, 0.35, 0.2, 0.9)
const EARTH := Color(0.22, 0.38, 0.72)
const MOON := Color(0.55, 0.54, 0.52)
const SUN := Color(1.0, 0.96, 0.85)
const SUN_RADIUS_DEG := 0.267
## The landmark line's image in the sextant, over the star line's.
const LANDMARK_ALPHA := 0.55
const LANDMARK_RING := Color(1.0, 0.62, 0.2)

## Name the stars in the telescope.
var names: bool = true
var font: Font


func _process(_delta: float) -> void:
	queue_redraw()


## Where direction [param d] (ECI) falls in a field of [param fov_deg]
## centred at [param centre], radius [param radius] px, for view axes
## [param axes] (ECI: right, up, line of sight); null behind the eye.
static func project(d: Vector3, axes: Array, centre: Vector2, radius: float, fov_deg: float) -> Variant:
	var z := d.dot(axes[2])
	if z <= 1e-6:
		return null
	var k := radius / tan(deg_to_rad(fov_deg) / 2.0)
	return centre + Vector2(d.dot(axes[0]) / z, -d.dot(axes[1]) / z) * k


## The view axes in ECI now: right, up, line of sight; the landmark
## line's with [param landmark].
static func view_axes_eci(landmark: bool = false) -> Array:
	var b := Basis(Bus.get_value("dyn.att_q", Quaternion.IDENTITY) as Quaternion)
	var trunnion := 0.0 if landmark else float(Bus.get_value("optics.trunnion_deg", 0.0))
	var ax := Optics.view_axes(float(Bus.get_value("optics.shaft_deg", 0.0)), trunnion)
	return [b * (ax[0] as Vector3), b * (ax[1] as Vector3), b * (ax[2] as Vector3)]


## The Earth, the Moon and the Sun from the CSM: [direction (ECI), angular
## radius (deg), colour] each.
static func bodies() -> Array:
	var r: Array = Bus.get_value("dyn.r_m", [Bodies.R_EARTH + 185000.0, 0.0, 0.0])
	var t := float(Bus.get_value("time.get_s", 0.0))
	var m := Bodies.moon_position(t)
	var moon := Vector3(m[0], m[1], m[2])
	var pos := Vector3(r[0], r[1], r[2])
	var geo := pos if str(Bus.get_value("dyn.primary", "earth")) == "earth" else pos + moon
	var out := []
	for b in [[-geo, Bodies.R_EARTH, EARTH], [moon - geo, Bodies.R_MOON, MOON]]:
		var d: Vector3 = b[0]
		out.append([d.normalized(), rad_to_deg(asin(clampf(float(b[1]) / d.length(), 0.0, 1.0))), b[2]])
	out.append([Bodies.sun_direction(t), SUN_RADIUS_DEG, SUN])
	return out


## P22's landmark from the CSM (ECI), or null: none, or below its horizon.
static func landmark() -> Variant:
	var mf: Vector3 = Bus.get_value("guid.landmark_mf", Vector3.ZERO)
	if mf == Vector3.ZERO:
		return null
	var r: Array = Bus.get_value("dyn.r_m", [Bodies.R_EARTH + 185000.0, 0.0, 0.0])
	var t := float(Bus.get_value("time.get_s", 0.0))
	var pos := Vector3(r[0], r[1], r[2])
	if str(Bus.get_value("dyn.primary", "earth")) == "earth":
		var m := Bodies.moon_position(t)
		pos -= Vector3(m[0], m[1], m[2])
	var site := Bodies.moon_fixed(t) * mf
	if (pos - site).dot(site) <= 0.0:
		return null
	return (site - pos).normalized()


func _draw() -> void:
	var r := minf(size.x / 2.0, size.y - 36.0) / 2.0 - 8.0
	var cy := 18.0 + r + 4.0
	var axes := view_axes_eci()
	var near := bodies()
	_field(Vector2(size.x * 0.25, cy), r, Optics.FIELD_SCT_DEG, axes, near, names)
	_field(Vector2(size.x * 0.75, cy), r, Optics.FIELD_SXT_DEG, axes, near, false, view_axes_eci(true))
	var f := font if font != null else get_theme_default_font()
	draw_string(f, Vector2(size.x * 0.25 - r, 14.0), "SCT %d°" % int(Optics.FIELD_SCT_DEG), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RIM)
	draw_string(f, Vector2(size.x * 0.75 - r, 14.0), "SXT %.1f°" % Optics.FIELD_SXT_DEG, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, RIM)
	draw_string(f, Vector2(8.0, size.y - 6.0), "SHAFT %06.2f   TRUNNION %06.3f   OPTICS %s" % [
		float(Bus.get_value("optics.shaft_deg", 0.0)), float(Bus.get_value("optics.trunnion_deg", 0.0)),
		str(Bus.get_value("optics.mode", "")).to_upper()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.85))


func _field(c: Vector2, r: float, fov: float, axes: Array, near: Array, named: bool, landmark: Array = []) -> void:
	draw_circle(c, r, SKY)
	var half := deg_to_rad(fov) / 2.0
	var los: Vector3 = axes[2]
	var rim := PackedVector2Array()
	for i in 64:
		rim.append(c + Vector2.from_angle(TAU * i / 64.0) * r)
	# The Earth, the Moon and the Sun: their discs, clipped to the field;
	# in the sextant the landmark line's too, fainter, over them.
	_discs(c, r, fov, axes, near, rim, 1.0)
	if not landmark.is_empty():
		_discs(c, r, fov, landmark, near, rim, LANDMARK_ALPHA)
	# Reticle: crosshairs with a gap at the centre, where the star is set.
	var gap := r * 0.06
	for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * gap, c + dir * r, RETICLE, 1.0)
	# The stars, but not behind the Earth or the Moon; bigger in the
	# sextant's magnified view.
	var grow := 1.6 if fov < 10.0 else 1.0
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
		var size_px := clampf(3.2 - 0.6 * Stars.magnitude(code), 1.3, 4.5) * grow
		draw_circle(p, size_px * 2.0, Color(1.0, 1.0, 0.9, 0.15))
		draw_circle(p, size_px, Color(1.0, 1.0, 0.95))
		if named:
			draw_string(f, p + Vector2(6.0, -4.0), "%s %s" % [Stars.label(code).substr(3), Stars.name_of(code)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.8, 1.0, 0.85))
	var lm = landmark()
	if lm != null and los.angle_to(lm) < half:
		draw_arc(project(lm, axes, c, r, fov), 6.0, 0.0, TAU, 24, LANDMARK_RING, 1.5)
	draw_arc(c, r, 0.0, TAU, 96, RIM, 2.0)


## The bodies [param near] seen along view axes [param axes], their discs
## clipped to the field [param rim], at [param alpha].
func _discs(c: Vector2, r: float, fov: float, axes: Array, near: Array, rim: PackedVector2Array, alpha: float) -> void:
	var half := deg_to_rad(fov) / 2.0
	var los: Vector3 = axes[2]
	for b in near:
		var d: Vector3 = b[0]
		var ar := deg_to_rad(float(b[1]))
		if los.angle_to(d) > half + ar:
			continue
		var limb := PackedVector2Array()
		var p0 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		for i in 96:
			var e := (d * cos(ar) + p0.rotated(d, TAU * i / 96.0) * sin(ar)).normalized()
			var p = project(e, axes, c, r, fov)
			if p == null:
				# Behind the eye: far out the way it lies, so the disc still
				# covers its side of the field.
				p = c + Vector2(e.dot(axes[0]), -e.dot(axes[1])).normalized() * r * 1000.0
			limb.append(p)
		var col: Color = b[2]
		col.a *= alpha
		for poly in Geometry2D.intersect_polygons(limb, rim):
			draw_colored_polygon(poly, col)
