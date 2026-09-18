class_name LoadingScreen
extends Control
## The screen between the menu and a cabinet.
##
## A game's scene brings its whole level with it -- meshes, textures and the
## scenes it spawns from -- and reading that off a browser's virtual filesystem
## takes a noticeable moment. Nothing used to be on screen while it happened:
## the menu sat there, frozen, with the button still lit, which reads as a
## button that did not work. This screen goes up first, so the wait says which
## cabinet is coming and shows its controls while the player waits for it.
##
## [Parkade] puts it up and it hands the loaded scene back, through
## [method Parkade.take_pending_game] and [method Parkade.finish_launch]. It is
## never launched by itself: with nothing pending there is nothing to load, so
## it goes back to the menu rather than sit on a screen that never leaves.
##
## [b]Two ways to load.[/b] Given threads, the scene is loaded on one and this
## screen keeps drawing, so the bar moves and Escape still gets out. The web
## export has no thread support -- turning it on would need the COOP/COEP
## headers GitHub Pages cannot serve, see the README -- and there the load is a
## blocking call that stops the frame it runs in. What matters either way is
## that the load starts only once this screen has been [i]drawn[/i]: a frame is
## drawn after it is processed, so a load started in [method Node._ready] runs
## before the player ever sees this screen, which is the frozen menu again with
## extra steps.
##
## Leaving while a threaded load is in flight simply abandons it -- there is no
## cancelling one in Godot 4. It finishes into the resource cache, unused, and
## makes the next launch of that cabinet quicker.

## Frames this screen waits before it starts loading. Two, because a frame is
## drawn after it is processed: the first [method _process] call comes one frame
## too early, and the second is the first that can know the screen is up.
const FRAMES_BEFORE_LOADING := 2

## Load on a background thread where the build has them. Off is what the web
## build does anyway, and what the test uses to cover that path.
@export var background_load: bool = true
## Shortest time the screen stays up. A cabinet already in the resource cache
## loads in a couple of frames, and without this the screen is a flash nobody
## can read -- worse than no screen at all.
@export var min_visible_time: float = 0.45

## The cabinet to load. Left unset, which is how [Parkade] puts this screen up,
## it takes whichever cabinet the shell has pending; set before the screen
## enters the tree, it loads that one instead, which is how the test drives it
## without going through a launch.
var game: ArcadeGame = null

@onready var _game_title: Label = $Root/GameTitle
@onready var _tagline: Label = $Root/Tagline
@onready var _controls: Label = $Root/Controls
@onready var _progress: ProgressBar = $Root/Progress

## The loaded scene, waiting on [member min_visible_time] to be swapped in.
var _scene: PackedScene = null
## Whether the load is running on a thread, and so whether there is progress to
## report. Decided once, in [method Node._ready], because the answer cannot
## change while a screen is up.
var _threaded: bool = false
## Set while [method ResourceLoader.load_threaded_get_status] is worth polling.
var _polling: bool = false
## Frames this screen has been processed, against [constant FRAMES_BEFORE_LOADING].
var _frames: int = 0
## Seconds this screen has been up, against [member min_visible_time].
var _visible_for: float = 0.0


func _ready() -> void:
	if game == null:
		game = Parkade.take_pending_game()
	if game == null:
		# Nobody asked for this screen -- it was run on its own, from the editor
		# or by a stale scene path. There is nothing to load and nothing to wait
		# for, so go somewhere the player can pick something.
		push_warning("LoadingScreen: no cabinet pending, going back to the menu.")
		set_process(false)
		Parkade.return_to_menu()
		return

	_game_title.text = game.title
	_tagline.text = game.tagline
	_controls.text = game.controls
	_threaded = background_load and OS.has_feature("threads")
	# A bar that cannot move is worse than no bar: the blocking load reports
	# nothing until it is over, and a frozen bar reads as a hung game.
	_progress.visible = _threaded
	_progress.value = 0.0


func _process(delta: float) -> void:
	_visible_for += delta

	if _scene != null:
		if _visible_for >= min_visible_time:
			set_process(false)
			Parkade.finish_launch(_scene)
		return

	if _polling:
		_poll()
		return

	_frames += 1
	if _frames >= FRAMES_BEFORE_LOADING:
		_start_load()


## Begins the load, on a thread or on this one. Called from [method _process]
## rather than [method Node._ready] so that the screen is on the player's
## display before either kind of load starts.
func _start_load() -> void:
	if _threaded:
		var err := ResourceLoader.load_threaded_request(game.scene_path, "PackedScene")
		if err != OK:
			_give_up("could not start loading %s (error %d)" % [game.scene_path, err])
			return
		_polling = true
		return
	# No threads: this call holds the frame until the scene is in memory. The
	# screen the player is looking at was drawn last frame, so the wait at least
	# happens under it.
	_loaded(ResourceLoader.load(game.scene_path, "PackedScene") as PackedScene)


func _poll() -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(game.scene_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not progress.is_empty():
				_progress.value = float(progress[0]) * _progress.max_value
		ResourceLoader.THREAD_LOAD_LOADED:
			_polling = false
			_progress.value = _progress.max_value
			_loaded(ResourceLoader.load_threaded_get(game.scene_path) as PackedScene)
		_:
			_polling = false
			_give_up("loading %s failed (status %d)" % [game.scene_path, status])


## Holds the finished scene for [method _process] to swap in. Not swapped in
## here: the hold on [member min_visible_time] applies to both load paths, and
## doing it in the one place keeps a cached cabinet from flashing past.
func _loaded(scene: PackedScene) -> void:
	if scene == null:
		_give_up("%s did not load as a PackedScene" % game.scene_path)
		return
	_scene = scene


## A cabinet that will not load is a dead end, and the menu is the only place
## with a way out of it. [method Parkade.launch] checked the scene exists before
## putting this screen up, so anything landing here is a genuinely broken build.
func _give_up(reason: String) -> void:
	push_error("LoadingScreen: %s." % reason)
	set_process(false)
	Parkade.return_to_menu()
