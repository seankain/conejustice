extends Node
## The arcade shell: which games exist, which one is running, and the way back.
##
## Parkade (Park + Arcade) is the front end. Each game is a whole scene of its
## own, swapped in with [method SceneTree.change_scene_to_file], so the games
## share the autoloads and nothing else -- no game can leave a node running
## inside another one.
##
## The games themselves never need to know this node exists. Escape is handled
## here, on the shell, because leaving a game is a shell decision and wiring it
## into every game would mean every new cabinet has to remember to do it.

## Where [method return_to_menu] goes. Also the project's main scene.
const MENU_SCENE := "res://Scenes/Parkade/MainMenu.tscn"

## [member current_game_id] while the menu itself is up.
const NO_GAME := &""

## Every cabinet, in the order the menu lists them.
var games: Array[ArcadeGame] = []

## The game currently running, or [constant NO_GAME] on the menu. Read by the
## Escape handler below so the menu's own Escape does nothing.
var current_game_id: StringName = NO_GAME


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
				"WASD  drive      MOUSE  look      R  start over      ESC  pause",
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
	_change_scene(game.scene_path)
	return true


## Drops whatever is running and goes back to the cabinet list.
func return_to_menu() -> void:
	current_game_id = NO_GAME
	_change_scene(MENU_SCENE)


## The one place scenes are swapped, so every swap leaves the tree in the same
## state: running, with a visible cursor. A game that paused the tree or hid the
## pointer to aim would otherwise hand those over to whatever comes next.
func _change_scene(path: String) -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Parkade: could not load %s (error %d)." % [path, err])
