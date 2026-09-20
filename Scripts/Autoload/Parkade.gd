extends Node
## The arcade shell: which games exist, which one is running, and the way back.
##
## Parkade (Park + Arcade) is the front end. Each game is a whole scene of its
## own, swapped in for whatever was running, so the games share the autoloads and
## nothing else -- no game can leave a node running inside another one.
##
## The games themselves never need to know this node exists. Escape is handled
## here, on the shell, because leaving a game is a shell decision and wiring it
## into every game would mean every new cabinet has to remember to do it.
##
## A cabinet is not swapped in straight from the menu. [method launch] puts
## [LoadingScreen] up instead, and that screen loads the game's scene and calls
## [method finish_launch] with it -- a game's scene takes long enough to read
## that a direct swap leaves the menu sitting frozen on screen, looking like a
## button that did nothing.

## Where [method return_to_menu] goes. Also the project's main scene.
const MENU_SCENE := "res://Scenes/Parkade/MainMenu.tscn"

## What [method launch] puts up while a cabinet's scene loads.
const LOADING_SCENE := "res://Scenes/Parkade/LoadingScreen.tscn"

## [member current_game_id] while the menu itself is up.
const NO_GAME := &""

## Every cabinet, in the order the menu lists them.
var games: Array[ArcadeGame] = []

## The game currently running, or [constant NO_GAME] on the menu. Set as soon as
## [method launch] is called, so Escape over the loading screen gets out of a
## cabinet that is still coming up. Read by the Escape handler below so the
## menu's own Escape does nothing.
var current_game_id: StringName = NO_GAME

## The cabinet the loading screen is up for, until it takes it. Null the rest of
## the time.
var _pending_game: ArcadeGame = null


func _ready() -> void:
	# A game that pauses its tree must still be escapable, so this node keeps
	# processing input while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	games = [
		ArcadeGame.new(
				&"cone_justice",
				"CONE JUSTICE",
				"Some people park like the rules are for other people.",
				"LEFT CLICK  throw a cone      RIGHT CLICK  reload",
				"res://Scenes/Main.tscn"),
		ArcadeGame.new(
				&"parking_game",
				"PARKING GAME",
				"Beat the clock, find a space, and put it between the lines.",
				"WASD  drive      SHIFT  boost      SPACE  handbrake      MOUSE  look      R  start over      ESC  pause",
				"res://Scenes/ParkingGame/Main.tscn"),
	]


## Escape leaves whatever is running. Unhandled input, so a focused button or a
## game's own Escape binding still gets first refusal.
func _unhandled_input(event: InputEvent) -> void:
	if current_game_id == NO_GAME:
		return
	if event.is_action_pressed(&"menu_back"):
		get_viewport().set_input_as_handled()
		return_to_menu()


## The cabinet with this id, or null. Never assume a match: the menu is built
## from the same list, but callers outside it are typing the id by hand.
func find(id: StringName) -> ArcadeGame:
	for game in games:
		if game.id == id:
			return game
	return null


## Switches to a game. Returns false, having changed nothing, when the id is
## unknown, the game is not finished, or its scene is missing -- a dead menu
## button is a far better failure than a half-loaded scene.
##
## What it switches to is the loading screen, not the game: a cabinet's scene
## takes long enough to read that swapping straight to it leaves the menu frozen
## on screen while it happens. [LoadingScreen] loads it and calls
## [method finish_launch], so a true from here means the cabinet is on its way
## rather than already up.
func launch(id: StringName) -> bool:
	var game := find(id)
	if game == null:
		push_error("Parkade: no game with id '%s'." % id)
		return false
	if not game.available:
		push_warning("Parkade: '%s' is not playable yet." % game.title)
		return false
	if not ResourceLoader.exists(game.scene_path):
		push_error("Parkade: '%s' has no scene at %s." % [game.title, game.scene_path])
		return false
	current_game_id = id
	_pending_game = game
	_change_scene(LOADING_SCENE)
	return true


## The cabinet the loading screen was put up for, handed over once. Null when
## nothing is pending -- that screen run on its own, or a player who left while
## it was loading -- and the screen takes that as its cue to go back to the menu
## rather than guess at a cabinet.
func take_pending_game() -> ArcadeGame:
	var game := _pending_game
	_pending_game = null
	return game


## Swaps in a cabinet whose scene the loading screen has finished loading. For
## that screen to call; everything else starts a game with [method launch].
func finish_launch(scene: PackedScene) -> void:
	if scene == null:
		push_error("Parkade: finish_launch was given no scene.")
		return_to_menu()
		return
	_reset_tree()
	var err := get_tree().change_scene_to_packed(scene)
	if err != OK:
		push_error("Parkade: could not enter the loaded scene (error %d)." % err)
		return_to_menu()


## Drops whatever is running and goes back to the cabinet list. Also the way out
## of a launch that has not finished: the pending cabinet is dropped with it, so
## a loading screen that comes up after this has nothing to load and says so.
func return_to_menu() -> void:
	current_game_id = NO_GAME
	_pending_game = null
	_change_scene(MENU_SCENE)


## The one place scenes are swapped by path.
func _change_scene(path: String) -> void:
	_reset_tree()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Parkade: could not load %s (error %d)." % [path, err])


## Every swap goes through here, so each one leaves the tree in the same state:
## running, with a visible cursor. A game that paused the tree or hid the
## pointer to aim would otherwise hand those over to whatever comes next.
func _reset_tree() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
