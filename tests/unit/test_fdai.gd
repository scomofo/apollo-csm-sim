## The HUD's FDAI reads the vehicle the player flies: the LM's rates and
## attitude errors, about its own axes, as its crew's roll, pitch and yaw.
extends GutTest


func test_the_lm_s_axes_read_as_its_crew_s_roll_pitch_and_yaw() -> void:
	# The LM rolls about +Z (forward), pitches about +Y (right) and yaws
	# nose right about -X (up).
	assert_eq(Fdai.crew_axes(Vector3(0, 0, 1), "lm"), Vector3(1, 0, 0), "roll right")
	assert_eq(Fdai.crew_axes(Vector3(0, 1, 0), "lm"), Vector3(0, 1, 0), "pitch up")
	assert_eq(Fdai.crew_axes(Vector3(-1, 0, 0), "lm"), Vector3(0, 0, 1), "yaw right")
	assert_eq(Fdai.crew_axes(Vector3(1, 2, 3), "csm"), Vector3(1, 2, 3), "the CSM's already are")


func test_the_aca_and_the_fdai_agree() -> void:
	# A crew command, through the ACA to the LM's axes and back through the
	# FDAI, is the same command.
	var cmd := Vector3(0.3, -0.5, 0.8)
	var aca: Vector3 = HandControllerInput.lm_commands(cmd, Vector3.ZERO)[0]
	assert_eq(Fdai.crew_axes(aca, "lm"), cmd)
