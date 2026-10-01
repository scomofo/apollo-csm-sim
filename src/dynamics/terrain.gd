## The lunar surface: heights from NASA's elevation maps (data/terrain/,
## built by tools/terrain/build_terrain.py; sources in NOTICE). Around
## Tranquility Base it is LROC's 2 m terrain model of the Apollo 11 site,
## resampled to 4 m, with West crater and Little West in it, and around
## Apollo 12's, 14's, 15's and 16's sites LROC's of each, with Surveyor
## crater at Apollo 12's. Along each approach it is SLDEM2015 (59 m, then
## 118 m for Apollo 11's, 237 m for Apollo 12's, and 474 m for Apollo 14's,
## for Apollo 15's over the Apennine front and for Apollo 16's over the
## Kant plateau); elsewhere LOLA at 1°. Finer
## maps are blended into coarser ones over a margin at their edges.
##
## Heights are relative to the 1737.4 km reference sphere (Bodies.R_MOON),
## in the Moon-fixed frame (Bodies.moon_fixed()). Tranquility Base lies
## 1,927 m below it. [simplified: bilinear between posts; the surface
## between the 4 m posts is smooth, so rocks smaller than that aren't in
## it.]
class_name Terrain
extends RefCounted

const MANIFEST := "res://data/terrain/terrain.json"


## One map: a grid of heights, row 0 northmost, in latitude and east
## longitude.
class Layer:
	var name: String
	var data: PackedByteArray
	var rows: int
	var cols: int
	var lat_top: float
	var lon_left: float
	var ppd: float
	var blend_px: float
	var offset: float
	var scale: float
	var wrap: bool

	func post(r: int, c: int) -> float:
		return data.decode_s16((r * cols + c) * 2) * scale + offset

	## Height and blend weight at [param lat], [param lon] (degrees east,
	## 0-360); weight 0 outside the map.
	func sample(lat: float, lon: float) -> Vector2:
		var y := (lat_top - lat) * ppd
		var x := (lon - lon_left) * ppd
		var w := 1.0
		if wrap:
			x = fposmod(x, cols)
			y = clampf(y, 0.0, rows - 1.0)
		else:
			if y < 0.0 or x < 0.0 or y > rows - 1.0 or x > cols - 1.0:
				return Vector2.ZERO
			if blend_px > 0.0:
				w = clampf(minf(minf(y, rows - 1.0 - y), minf(x, cols - 1.0 - x)) / blend_px, 0.0, 1.0)
		var r0 := mini(int(y), rows - 2)
		var fy := y - r0
		var c0 := int(x)
		var c1 := c0 + 1
		if wrap:
			c0 %= cols
			c1 %= cols
		elif c0 > cols - 2:
			c0 = cols - 2
			c1 = cols - 1
		var fx := x - int(x) if wrap else x - c0
		var a := lerpf(post(r0, c0), post(r0, c1), fx)
		var b := lerpf(post(r0 + 1, c0), post(r0 + 1, c1), fx)
		return Vector2(lerpf(a, b, fy), w)


## Coarsest first.
static var _layers: Array[Layer] = []


static func _load() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var dir := MANIFEST.get_base_dir()
	var ls: Array = m["layers"]
	ls.reverse()
	for d in ls:
		var l := Layer.new()
		l.name = str(d["name"])
		l.data = FileAccess.get_file_as_bytes(dir.path_join(str(d["file"])))
		l.rows = int(d["rows"])
		l.cols = int(d["cols"])
		assert(l.data.size() == l.rows * l.cols * 2, "terrain layer " + l.name)
		l.lat_top = float(d["lat_top"])
		l.lon_left = float(d["lon_left"])
		l.ppd = float(d["ppd"])
		l.blend_px = float(d["blend_px"])
		l.offset = float(d["offset_m"])
		l.scale = float(d["scale_m"])
		l.wrap = bool(d["wrap"])
		_layers.append(l)


## The surface's height at [param lat_deg] N, [param lon_deg] E, m above
## the reference sphere.
static func height(lat_deg: float, lon_deg: float) -> float:
	if _layers.is_empty():
		_load()
	var lon := fposmod(lon_deg, 360.0)
	var h := 0.0
	for l in _layers:
		var s := l.sample(lat_deg, lon)
		if s.y > 0.0:
			h = lerpf(h, s.x, s.y)
	return h


## The surface's height under the Moon-fixed point [param p_mf].
static func height_under(p_mf: Vector3) -> float:
	var s := Bodies.fixed_to_selenographic(p_mf)
	return height(s.x, s.y)


## The surface's radius (m from the Moon's centre) under the Moon-fixed
## point [param p_mf].
static func radius_under(p_mf: Vector3) -> float:
	return Bodies.R_MOON + height_under(p_mf)


## The name of the finest map at [param lat_deg], [param lon_deg].
static func source(lat_deg: float, lon_deg: float) -> String:
	if _layers.is_empty():
		_load()
	var lon := fposmod(lon_deg, 360.0)
	for i in range(_layers.size() - 1, -1, -1):
		if _layers[i].sample(lat_deg, lon).y > 0.0:
			return _layers[i].name
	return ""
