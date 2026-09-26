## The guidance computers' 37 navigation stars (data/stars/
## navigation_stars.json, from tools/stars/navigation_stars.py): each by
## its code, a number whose decimal digits are the octal code the DSKY and
## the crew use (1 Alpheratz to 45 Fomalhaut), with its name, its direction
## in ECI (the ICRS, on Apollo 11's launch day) and its magnitude. The same
## positions are the sky the optics show and the computer's catalog.
class_name Stars
extends RefCounted

const PATH := "res://data/stars/navigation_stars.json"

## code: {"name", "dir" (Vector3, ECI), "mag"}.
static var _stars: Dictionary = {}


static func _table() -> Dictionary:
	if _stars.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		assert(f != null, "no star catalog at " + PATH)
		var d: Dictionary = JSON.parse_string(f.get_as_text())
		for s in d["stars"]:
			var ra := deg_to_rad(float(s["ra_deg"]))
			var dec := deg_to_rad(float(s["dec_deg"]))
			_stars[int(s["code"])] = {
				"name": str(s["name"]),
				"dir": Vector3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)),
				"mag": float(s["mag"]),
			}
	return _stars


## The codes, in order.
static func codes() -> Array:
	var c := _table().keys()
	c.sort()
	return c


static func has(code: int) -> bool:
	return _table().has(code)


## The star's direction, a unit vector in ECI.
static func direction(code: int) -> Vector3:
	return _table()[code]["dir"]


static func name_of(code: int) -> String:
	return _table()[code]["name"]


static func magnitude(code: int) -> float:
	return _table()[code]["mag"]


## The code as the DSKY shows it: five octal digits.
static func label(code: int) -> String:
	return "%05d" % code
