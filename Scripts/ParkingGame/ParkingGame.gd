class_name ParkingGame
extends Node3D
## The parking game cabinet's root: pick a car, then drive it.
##
## Two states, select then play. The select screen is a whole scene that this
## node adds and frees; so is the lot. Parkade swaps scenes [i]between[/i]
## cabinets, but inside one, the game root owns its own children -- which is why
## nothing here calls [method SceneTree.change_scene_to_file].
##
## The cabinet is loaded fresh every time it is launched from the menu, so the
## chosen car lives on this node for exactly one session and a re-entry starts
## back at select. Persisting it would need a [code]user://[/code] config, which
## nothing in this repo has yet.
##
## This game adds no autoload. [GameState] and [EventBus] are Cone Justice's --
## a run state enum about cones means nothing here -- and the round owns its own
## state, the way the source's [code]Level[/code] does.

## Emitted by the select screen when the player confirms a car. Connected by
## name rather than statically because the select scene is instanced, not a
## child of this scene.
const VEHICLE_CONFIRMED_SIGNAL := &"vehicle_confirmed"

enum State {
	SELECT, ## The carousel is up and nothing is simulating.
	PLAY, ## The lot is built and the round is running.
}

## Every car the cabinet offers, in carousel order. The round starts in the
## first one when nothing was picked.
@export var catalog: VehicleCatalog
## The people and geese the lot is populated with. Unset is a lot with nobody
## walking across it, which is a lot easier to park in.
@export var pedestrian_catalog: PedestrianCatalog
## The carousel (T10). Unset skips selection and plays the default car, which is
## what the cabinet does until that screen exists.
@export var vehicle_select_scene: PackedScene
## The lot the round is played in.
@export var lot_scene: PackedScene
## The camera rig. Added to the lot and pointed at whichever car the player
## is driving, rather than parented to it -- see [ChaseCamera].
@export var chase_camera_scene: PackedScene
## Clock, grade and score card. Added with the lot and pointed at the round.
@export var hud_scene: PackedScene
## Escape, mid-round. Only exists while a round is being played: on the select
## screen Escape belongs to the shell.
@export var pause_menu_scene: PackedScene

var state: State = State.SELECT

## Puts the pointer back the way the round had it. The pause menu let it go so
## its buttons could be clicked; the chase camera wants it captured again.
func _on_resumed() -> void:
	if current_round != null and current_round.camera_captures_mouse():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## The car the player confirmed, handed to the round when it starts. Falls back
## to the catalog's first entry, so the cabinet is playable before the select
## screen exists and after a select screen that was skipped.
var _chosen_vehicle: DrivableVehicle = null
var _select: Node = null
var _lot: Node3D = null
## The round in progress. Held so the HUD can be pointed at it (T12). Named
## current_round rather than round: a member called round shadows GDScript's own
## round() inside this class.
var current_round: ParkingRound = null


## Draws the lot between physics ticks rather than on them.
##
## The lot is a rigid body simulation stepped sixty times a second, drawn as
## often as the machine will draw it -- and in a browser that is whatever the
## tab is given, which is rarely sixty. Without this, every car in the lot is
## drawn where it was at the last tick and stays there for two or three frames
## before jumping, and [ChaseCamera], which eases towards the car every drawn
## frame, turns that staircase into a car that visibly buzzes against a lot that
## does not. With it, the cars are drawn along the line between the last two
## ticks, which is where the camera is already looking.
##
## Turned on here rather than in [code]project.godot[/code] because it is a
## property of [i]this[/i] cabinet: Cone Justice moves its camera along a rail
## with a tween and has no simulation under it, and is left alone.
## [method Parkade._reset_tree] puts it back on the way out, the way it puts the
## pointer and the pause state back.
##
## Anything that puts a body somewhere rather than driving it there has to say
## so afterwards -- [method Node.reset_physics_interpolation], or the body is
## drawn smeared between the two places for a frame. [method PlayerCar.respawn],
## [TrafficSpawner], [PedestrianSpawner] and [LotEvents] each do.
static func use_physics_interpolation(tree: SceneTree) -> void:
	tree.physics_interpolation = true


func _ready() -> void:
	if vehicle_select_scene == null:
		_enter_play()
		return
	_enter_select()


## Shows the carousel and waits for it to name a car.
func _enter_select() -> void:
	state = State.SELECT
	_select = vehicle_select_scene.instantiate()
	# Handed the catalog before it enters the tree: it builds a plate per car in
	# its own _ready.
	if _select is VehicleSelect:
		(_select as VehicleSelect).catalog = catalog
	if not _select.has_signal(VEHICLE_CONFIRMED_SIGNAL):
		push_error("ParkingGame: %s has no %s signal." % [
			vehicle_select_scene.resource_path, VEHICLE_CONFIRMED_SIGNAL])
		_select.free()
		_select = null
		_enter_play()
		return
	_select.connect(VEHICLE_CONFIRMED_SIGNAL, _on_vehicle_confirmed)
	add_child(_select)


func _on_vehicle_confirmed(vehicle: DrivableVehicle) -> void:
	_chosen_vehicle = vehicle
	# Freed rather than hidden: it is a 3D scene with lights and spinning cars in
	# it, and none of that should still be drawing behind the lot.
	if _select != null:
		_select.queue_free()
		_select = null
	_enter_play()


## Builds the lot and starts a round in the chosen car.
##
## The lot goes in first and on its own: the round finds the bays by group in
## its own [method Node._ready], so they have to be in the tree before it is.
func _enter_play() -> void:
	state = State.PLAY
	# Before the lot is built, so every body in it is interpolated from the first
	# tick it is simulated for.
	use_physics_interpolation(get_tree())
	if _chosen_vehicle == null:
		_chosen_vehicle = catalog.first() if catalog != null else null
	if lot_scene == null:
		push_warning("ParkingGame: no lot scene set, so there is nothing to drive yet.")
		return
	if _chosen_vehicle == null:
		push_warning("ParkingGame: no vehicle to drive -- is the catalog empty?")
		return
	_lot = lot_scene.instantiate()
	add_child(_lot)
	# The HUD goes in before the round, and is connected before the round enters
	# the tree: the round announces its first level from _ready, and a HUD
	# connected afterwards would miss the round it is already showing.
	var hud: ParkingHUD = null
	if hud_scene != null:
		hud = hud_scene.instantiate() as ParkingHUD
		add_child(hud)
	current_round = ParkingRound.new()
	current_round.name = "Round"
	current_round.configure(
			_lot, _chosen_vehicle, chase_camera_scene, catalog, pedestrian_catalog)
	if hud != null:
		# Handed the round rather than going looking for it: the source's HUD
		# resolves /root/Main/Level every frame.
		hud.follow(current_round)
	add_child(current_round)
	if pause_menu_scene == null:
		return
	var pause_menu := pause_menu_scene.instantiate() as PauseMenu
	add_child(pause_menu)
	pause_menu.resumed.connect(_on_resumed)
