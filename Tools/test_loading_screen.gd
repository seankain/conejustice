extends Node
## The loading screen, end to end: the menu's button puts it up, it brings the
## cabinet in behind it, and a screen with nothing to load goes back to the menu.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless Tools/test_loading_screen.tscn
## [/codeblock]
##
## A scene rather than a [code]--script[/code] tool, like the pause-flow test
## and for the same reason: [Parkade] is an autoload, and a script run with
## [code]--script[/code] never registers autoloads.
##
## The checks run on [Runner], parented straight to the window root, rather than
## on this node. Every swap this test watches frees the current scene and this
## node [i]is[/i] the current scene, so a harness sitting in it would be deleted
## by the first launch it made.


func _ready() -> void:
	get_tree().root.add_child.call_deferred(Runner.new())


## The test proper. Deliberately outside the scene tree's current scene.
class Runner extends Node:
	## Longest a cabinet is given to load before the test calls it hung. The
	## parking game's lot is the slowest thing either cabinet pulls in, and it
	## loads in well under a second on a cold cache.
	const PATIENCE := 30.0

	var _failures: Array[String] = []
	## Held rather than asked for: a swap can free the node a check is standing
	## on, and [method Node.get_tree] on a freed node is nothing to rely on.
	var _tree: SceneTree = null

	func _ready() -> void:
		_tree = get_tree()
		_run()

	func _check(condition: bool, description: String) -> void:
		print("  %-4s %s" % ["ok" if condition else "FAIL", description])
		if not condition:
			_failures.append(description)

	## The scene the tree is showing, by its file path. Empty while a swap is
	## still pending, which is what the polling below waits out.
	func _current_path() -> String:
		var scene := _tree.current_scene
		return "" if scene == null else scene.scene_file_path

	## Waits for the tree to be showing [param path], or gives up after
	## [constant PATIENCE]. Returns whether it got there.
	func _await_scene(path: String) -> bool:
		var deadline := Time.get_ticks_msec() + int(PATIENCE * 1000.0)
		while Time.get_ticks_msec() < deadline:
			if _current_path() == path:
				return true
			await _tree.process_frame
		return false

	func _await_frames(count: int) -> void:
		for i in count:
			await _tree.process_frame

	func _run() -> void:
		print("Loading screen")
		await _menu_launch_shows_the_loading_screen()
		await _loading_screen_brings_the_cabinet_in(&"parking_game")
		await _blocking_load_brings_the_cabinet_in()
		await _nothing_pending_goes_back_to_the_menu()
		_finish()

	## The button hands the player the loading screen, not the game: the whole
	## point is that the swap into the game happens behind something.
	func _menu_launch_shows_the_loading_screen() -> void:
		print(" launch from the menu")
		_check(Parkade.launch(&"cone_justice"), "launching a listed cabinet is accepted")
		_check(Parkade.current_game_id == &"cone_justice", "the shell knows which cabinet")
		_check(await _await_scene(Parkade.LOADING_SCENE), "the loading screen comes up")
		_check(_current_path() != "res://Scenes/Main.tscn", "the game is not up yet")

		var up_at := Time.get_ticks_msec()
		_check(await _await_scene("res://Scenes/Main.tscn"), "the cabinet comes up behind it")
		var screen_time := (Time.get_ticks_msec() - up_at) / 1000.0
		# A cabinet already in the resource cache loads in a couple of frames,
		# so without the hold this screen would be a flash nobody can read.
		_check(screen_time >= 0.4, "the screen is up long enough to read (%.2fs)" % screen_time)

		Parkade.return_to_menu()
		_check(await _await_scene(Parkade.MENU_SCENE), "the menu comes back")
		_check(Parkade.current_game_id == Parkade.NO_GAME, "the shell is back on the menu")

		# Unknown ids never got as far as a scene swap and still do not.
		_check(not Parkade.launch(&"no_such_cabinet"), "an unknown cabinet is refused")
		await _await_frames(2)
		_check(_current_path() == Parkade.MENU_SCENE, "a refused launch leaves the menu up")

	## The other cabinet, the heavier one, over the same path.
	func _loading_screen_brings_the_cabinet_in(id: StringName) -> void:
		print(" launch %s" % id)
		var game := Parkade.find(id)
		_check(game != null, "the cabinet is listed")
		if game == null:
			return
		_check(Parkade.launch(id), "launching it is accepted")
		_check(await _await_scene(Parkade.LOADING_SCENE), "the loading screen comes up")
		_check(await _await_scene(game.scene_path), "the cabinet comes up behind it")

		Parkade.return_to_menu()
		_check(await _await_scene(Parkade.MENU_SCENE), "the menu comes back")

	## The path the web build takes. It has no thread support -- the export
	## preset cannot have it without the COOP/COEP headers GitHub Pages will not
	## serve -- so there the load blocks the frame it runs in, and it still has
	## to end up in the cabinet. The screen is instanced and handed its cabinet
	## here rather than launched, because which way it loads is a property on it
	## and a launch would load the screen fresh with the default.
	func _blocking_load_brings_the_cabinet_in() -> void:
		print(" blocking load, the way the web build loads")
		var packed := ResourceLoader.load(Parkade.LOADING_SCENE) as PackedScene
		_check(packed != null, "the loading screen scene loads")
		if packed == null:
			return
		var screen := packed.instantiate() as LoadingScreen
		_check(screen != null, "it instances as a loading screen")
		if screen == null:
			return
		screen.background_load = false
		screen.game = Parkade.find(&"cone_justice")
		# A child of this node rather than the current scene, so the cabinet it
		# loads can replace the current scene without taking the screen with it.
		add_child(screen)
		_check(await _await_scene("res://Scenes/Main.tscn"),
				"the blocking load ends up in the cabinet")
		screen.queue_free()

		Parkade.return_to_menu()
		_check(await _await_scene(Parkade.MENU_SCENE), "the menu comes back")

	## Run on its own -- from the editor, or by a scene path that outlived the
	## menu button that used to set one -- the screen has nothing to load. It
	## has to leave rather than sit there loading forever.
	func _nothing_pending_goes_back_to_the_menu() -> void:
		print(" nothing pending")
		_tree.change_scene_to_file(Parkade.LOADING_SCENE)
		_check(await _await_scene(Parkade.MENU_SCENE), "the screen sends the player back")

	func _finish() -> void:
		if _failures.is_empty():
			print("PASS")
			_tree.quit(0)
			return
		print("FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
		_tree.quit(1)
