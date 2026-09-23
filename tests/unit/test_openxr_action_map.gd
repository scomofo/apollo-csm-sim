## The shipped OpenXR action map binds what the rig and the hand-controller
## input rely on (and the menu button a wrist menu will use), for
## gemini-capsule's primary headset (HTC Vive XR Elite: Vive Focus 3
## controller profile) and the other PC VR profiles. Ported from
## gemini-capsule at 40e449c; its project-settings case waits until
## OpenXR is enabled here (docs/ROADMAP.md, slice 2c).
extends GutTest

const MAP := "res://openxr_action_map.tres"

var _profiles: Dictionary = {}   # profile path -> Array of [action, binding_path]


func before_all() -> void:
	var text := FileAccess.get_file_as_string(MAP)
	var actions := {}
	var re_action := RegEx.create_from_string("\\[sub_resource type=\"OpenXRAction\" id=\"(\\w+)\"\\]\\nresource_name = \"(\\w+)\"")
	for m in re_action.search_all(text):
		actions[m.get_string(1)] = m.get_string(2)
	var bindings := {}
	var re_b := RegEx.create_from_string("\\[sub_resource type=\"OpenXRIPBinding\" id=\"(\\w+)\"\\]\\naction = SubResource\\(\"(\\w+)\"\\)\\nbinding_path = \"([^\"]+)\"")
	for m in re_b.search_all(text):
		bindings[m.get_string(1)] = [actions.get(m.get_string(2), "?"), m.get_string(3)]
	var re_p := RegEx.create_from_string("interaction_profile_path = \"([^\"]+)\"\\nbindings = \\[([^\\]]*)\\]")
	var re_id := RegEx.create_from_string("SubResource\\(\"(OpenXRIPBinding_\\w+)\"\\)")
	for m in re_p.search_all(text):
		var rows := []
		for i in re_id.search_all(m.get_string(2)):
			rows.append(bindings.get(i.get_string(1), ["?", "?"]))
		_profiles[m.get_string(1)] = rows


func _has(profile: String, action: String, path_suffix: String) -> bool:
	for row in _profiles.get(profile, []):
		if row[0] == action and str(row[1]).ends_with(path_suffix):
			return true
	return false


func test_vive_focus3_profile_covers_the_rig() -> void:
	var p := "/interaction_profiles/htc/vive_focus3_controller"
	assert_true(_profiles.has(p), "Vive XR Elite / Focus 3 profile present")
	assert_true(_has(p, "by_button", "left/input/y/click"), "recentre on Y")
	assert_true(_has(p, "by_button", "right/input/b/click"), "recentre on B")
	assert_true(_has(p, "primary", "left/input/thumbstick"), "roll stick")
	assert_true(_has(p, "primary", "right/input/thumbstick"), "pitch/yaw stick")
	assert_true(_has(p, "trigger", "right/input/trigger/value"))
	assert_true(_has(p, "grip", "right/input/squeeze/click"))
	assert_true(_has(p, "menu_button", "left/input/menu/click"), "wrist menu toggle")
	assert_true(_has(p, "aim_pose", "left/input/aim/pose"))
	assert_true(_has(p, "palm_pose", "left/input/palm_ext/pose"))


func test_other_pc_vr_profiles_keep_recentre_and_sticks() -> void:
	for p in ["/interaction_profiles/oculus/touch_controller", "/interaction_profiles/valve/index_controller",
			"/interaction_profiles/htc/vive_cosmos_controller", "/interaction_profiles/bytedance/pico4_controller"]:
		assert_true(_profiles.has(p), p)
		assert_true(_has(p, "by_button", "/click"), "%s: by_button" % p)
		assert_true(_has(p, "primary", "right/input/thumbstick"), "%s: right stick" % p)
		assert_true(_has(p, "menu_button", "/click"), "%s: menu" % p)


func test_left_grip_is_bound_for_the_translation_modifier() -> void:
	# HandControllerInput switches the sticks to the THC while the left grip
	# is held.
	for p in ["/interaction_profiles/htc/vive_focus3_controller", "/interaction_profiles/oculus/touch_controller",
			"/interaction_profiles/valve/index_controller", "/interaction_profiles/htc/vive_cosmos_controller",
			"/interaction_profiles/bytedance/pico4_controller"]:
		assert_true(_has(p, "grip", "left/input/squeeze/click") or _has(p, "grip", "left/input/squeeze/value"),
			"%s: left grip" % p)
		assert_true(_has(p, "primary", "left/input/thumbstick"), "%s: left stick" % p)
