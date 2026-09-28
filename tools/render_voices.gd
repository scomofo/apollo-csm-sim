## Renders the audio director's voices (src/presentation/audio_director.gd)
## to WAV files for the listening pass (docs/LISTENING_PASS.md), without
## flying the mission:
##   godot --headless --path . -s tools/render_voices.gd -- --out=/tmp/voices
## Each one-shot is a file of its own, and each continuous voice its loop
## played LOOPS times over, as the director plays it at full gain. all.wav
## has them all in turn, a second apart. --out defaults to user://voices.
extends SceneTree

const LOOPS := 3
const GAP_S := 1.0

## The director's script, loaded once the autoloads it names exist.
var director: GDScript


func _initialize() -> void:
	director = load("res://src/presentation/audio_director.gd")
	var out := "user://voices"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var dir := ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var all := PackedByteArray()
	var gap := PackedByteArray()
	gap.resize(int(GAP_S * director.SAMPLE_RATE) * 2)
	for kind: String in director.ONE_SHOTS:
		var data: PackedByteArray = director.render_one_shot(director.ONE_SHOTS[kind], rng).data
		_save(data, dir.path_join(kind + ".wav"))
		all.append_array(data)
		all.append_array(gap)
	for voice: String in director.LAYERS:
		var loop: PackedByteArray = director.render_loop(director.LAYERS[voice], rng).data
		var data := PackedByteArray()
		for i in LOOPS:
			data.append_array(loop)
		_save(data, dir.path_join(voice + ".wav"))
		all.append_array(data)
		all.append_array(gap)
	_save(all, dir.path_join("all.wav"))
	print("The voices are in ", dir)
	quit()


## 16-bit mono PCM [param data] at the director's rate, to [param path].
func _save(data: PackedByteArray, path: String) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(director.SAMPLE_RATE)
	wav.data = data
	var err := wav.save_to_wav(path)
	if err != OK:
		push_error("can't write %s: %s" % [path, error_string(err)])
