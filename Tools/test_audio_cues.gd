extends Node
## Every sound the parking game asks for, and the engine note that follows the
## car.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless Tools/test_audio_cues.tscn
## [/codeblock]
##
## A scene rather than a --script tool because it needs the SfxPlayer autoload,
## which a --script run never registers. It cannot hear anything, so it checks
## the two things that actually go wrong: a cue whose file is missing (which
## degrades to silence, and would otherwise be noticed by nobody) and an engine
## note that does not move with the car.

var _failures: Array[String] = []
var _tree: SceneTree = null


func _ready() -> void:
	_tree = get_tree()
	_run()


func _check(condition: bool, description: String) -> void:
	print("  %-4s %s" % ["ok" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await _tree.physics_frame


func _run() -> void:
	for cue in [SfxPlayer.Cue.CAR_IMPACT, SfxPlayer.Cue.ROUND_START, SfxPlayer.Cue.ROUND_OVER]:
		var file: String = SfxPlayer.CUE_FILES[cue]
		_check(ResourceLoader.exists(SfxPlayer.SOUND_DIR + file), "%s is imported" % file)

	var engine_stream := load(EngineAudio.STREAM_PATH) as AudioStreamWAV
	_check(engine_stream != null, "the engine loop is imported")
	if engine_stream != null:
		_check(engine_stream.loop_mode != AudioStreamWAV.LOOP_DISABLED,
				"the engine loop is imported as a loop")

	Parkade.current_game_id = &"parking_game"
	var main := (load("res://Scenes/ParkingGame/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(0.5)
	(main.get_node("VehicleSelect") as VehicleSelect).confirm()
	await _wait(1.0)

	var parking_round := main.get_node("Round") as ParkingRound
	var engine := parking_round.car.get_node_or_null("EngineAudio") as EngineAudio
	_check(engine != null and engine.playing, "the engine is running")
	if engine == null:
		_finish()
		return

	var idle_pitch := engine.pitch_scale
	Input.action_press(&"drive_forward")
	await _wait(3.0)
	var driving_pitch := engine.pitch_scale
	Input.action_release(&"drive_forward")
	print("  pitch idle %.2f -> driving %.2f at %.1f m/s" % [
		idle_pitch, driving_pitch, parking_round.car.speed()])
	_check(driving_pitch > idle_pitch + 0.05, "the engine picks up with the car")

	await _wait(4.0)
	print("  pitch after letting off: %.2f" % engine.pitch_scale)
	_check(engine.pitch_scale < driving_pitch, "and settles back when it stops")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS")
		_tree.quit(0)
		return
	printerr("%d check(s) failed" % _failures.size())
	_tree.quit(1)
