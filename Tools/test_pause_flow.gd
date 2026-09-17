extends Node
## Escape, end to end: pause, resume, and the way out of the cabinet.
##
## Run it headless, from the project root, once per mode:
## [codeblock]
## godot --headless Tools/test_pause_flow.tscn -- round
## godot --headless Tools/test_pause_flow.tscn -- select
## [/codeblock]
##
## It is a scene rather than a [code]--script[/code] tool, unlike the other two
## tests here, and that is the point worth knowing: a script run with
## [code]--script[/code] replaces the main loop, and autoloads are never
## registered, so any script naming [Parkade] fails to compile. Anything that
## touches the shell has to be tested by running a scene.
##
## Two modes because the way out frees this harness. Leaving for the Parkade
## menu swaps the whole scene, so the run that tests it cannot test anything
## afterwards.

const SELECT_MODE := "select"

var _failures: Array[String] = []
## Held rather than asked for: leaving the cabinet swaps the scene and frees
## this node, and a freed node has no tree to quit with.
var _tree: SceneTree = null


func _ready() -> void:
	_tree = get_tree()
	var mode := "round"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	_run(mode)


func _check(condition: bool, description: String) -> void:
	print("  %-4s %s" % ["ok" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await _tree.physics_frame


func _press_escape() -> void:
	var event := InputEventAction.new()
	event.action = &"menu_back"
	event.pressed = true
	get_viewport().push_unhandled_input(event)
	await _tree.process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("PASS")
		_tree.quit(0)
		return
	printerr("%d check(s) failed" % _failures.size())
	_tree.quit(1)


func _run(mode: String) -> void:
	# The shell is normally what launches a cabinet, and it is what Escape asks
	# to leave, so the harness has to look like a launched cabinet.
	Parkade.current_game_id = &"parking_game"
	var main := (load("res://Scenes/ParkingGame/Main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _wait(0.5)

	var select := main.get_node_or_null("VehicleSelect") as VehicleSelect
	_check(select != null, "the cabinet opens on vehicle select")
	_check(main.get_node_or_null("PauseMenu") == null, "there is no pause menu on the select screen")

	if mode == SELECT_MODE:
		await _press_escape()
		_check(Parkade.current_game_id == Parkade.NO_GAME,
				"Escape on the select screen leaves for the Parkade menu")
		_finish()
		return

	select.confirm()
	await _wait(1.0)
	var menu := main.get_node_or_null("PauseMenu") as PauseMenu
	var parking_round := main.get_node_or_null("Round") as ParkingRound
	_check(menu != null and parking_round != null, "confirming a car starts a round with a pause menu")
	if menu == null or parking_round == null:
		_finish()
		return
	_check(not menu.paused, "the round does not start paused")

	var clock_before := parking_round.seconds_remaining
	await _press_escape()
	await _wait(0.75)
	_check(menu.paused and menu.visible, "Escape pauses and shows the menu")
	_check(_tree.paused, "the tree is paused")
	_check(is_equal_approx(clock_before, parking_round.seconds_remaining), "the clock stops")
	_check(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "the cursor comes back")
	_check(Parkade.current_game_id != Parkade.NO_GAME,
			"the shell did not also take the Escape that opened the menu")

	await _press_escape()
	await _wait(0.75)
	_check(not menu.paused and not _tree.paused, "Escape again resumes")
	_check(parking_round.seconds_remaining < clock_before, "the clock runs again")

	# Not pressed: leaving swaps the whole scene and frees this harness
	# mid-await. The select run covers that path; what matters here is the
	# button being wired to it.
	_check(menu._menu_button.pressed.is_connected(Parkade.return_to_menu),
			"PARKADE MENU is wired to the shell")
	_finish()
