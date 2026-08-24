class_name TargetCar
extends StaticBody3D
## A parked car, and the rules for deciding when it has been coned.
##
## Not every one of these deserves a cone. [member is_violator] says whether this
## car is parked badly enough to be fair game, and everything downstream branches
## on it -- coning a car that is parked correctly costs the player points. The
## detection below does not care either way: it decides when a cone has *landed*,
## and the bus carries the violator flag out so scoring can decide what that
## landing was worth.
##
## The hard part is telling a cone that landed from a cone that merely touched.
## A cone counts only once it has been overlapping the catcher *at rest* for
## settle_time without interruption, which is what rejects a graze: a cone that
## clips the bumper and rolls into the gutter is never still while touching.

## Whether this car is parked illegally. Written by [ParkingLot] from the pose
## the car was actually placed at, so it always agrees with what the player can
## see. Defaults true so a car authored directly into a level is a target, which
## is what a hand-placed car in this game has always meant.
@export var is_violator: bool = true

## Cones that must settle on this car before it counts as coned. Overwritten
## per section by the CameraStop that owns this car.
@export var cones_required: int = 3

## Continuous seconds a cone must sit still, in contact, before it counts.
@export var settle_time: float = 0.5

## Speed below which a cone counts as at rest, in m/s.
@export var settle_speed: float = 0.35

@export_group("Marker")
## Height above this car's origin that its HUD bracket hangs at, roughly
## mid-body. Per vehicle rather than per HUD: a van and a hatchback do not keep
## their middles in the same place, and the bracket is how the player finds the
## car on screen at all.
@export var marker_height: float = 1.1
## World height the bracket is sized against, so it shrinks with distance
## without anyone having to invent a pixels-per-metre constant. Roughly how tall
## this vehicle reads from the rail.
@export var marker_size: float = 1.3

## Emitted per cone as it settles. on_roof marks the bonus landing.
signal cone_settled(car: TargetCar, on_roof: bool)
## Emitted once, when the car reaches cones_required.
signal fully_coned(car: TargetCar)
## For the HUD's per-car progress pips. Visuals stay out of this script.
signal progress_changed(counted: int, required: int)

@onready var _catcher: Area3D = $ConeCatcher
@onready var _roof: Area3D = $RoofZone

## ConeBody -> seconds it has been at rest in contact.
var _candidates: Dictionary = {}
## ConeBody -> whether it landed on the roof. Size is the current count.
var _counted: Dictionary = {}
## Once coned, always coned: the section has already banked this car.
var _latched: bool = false


func _ready() -> void:
	add_to_group("target_cars")
	_catcher.body_entered.connect(_on_catcher_body_entered)
	_catcher.body_exited.connect(_on_catcher_body_exited)


func _physics_process(delta: float) -> void:
	if _latched or _candidates.is_empty():
		return
	# keys() returns a copy, so settling a cone can erase from the dictionary
	# while this loop is running.
	for cone in _candidates.keys():
		# The final cone latching the car clears _candidates mid-loop, and the
		# keys array we are walking is a stale copy of it.
		if _latched:
			return
		if not is_instance_valid(cone):
			_candidates.erase(cone)
			continue
		if not _candidates.has(cone):
			continue
		if cone.linear_velocity.length() < settle_speed:
			_candidates[cone] += delta
			if _candidates[cone] >= settle_time:
				_settle(cone)
		else:
			# Moving again: the clock restarts from zero, not from where it was.
			_candidates[cone] = 0.0


## Cones counted so far.
func coned_count() -> int:
	return _counted.size()


func is_fully_coned() -> bool:
	return _latched


## Returns the car to its pre-section state and hands back every cone it held.
## Called when a section arms and when a run restarts; without the release a
## second run would start with cones still claimed by the first.
func reset() -> void:
	for cone in _counted.keys():
		if is_instance_valid(cone):
			cone.release(self)
	_counted.clear()
	_candidates.clear()
	_latched = false
	progress_changed.emit(0, cones_required)


func _on_catcher_body_entered(body: Node3D) -> void:
	var cone := body as ConeBody
	if cone == null:
		return
	if _latched:
		# This car is already done. The throw is wasted, but it did hit a car,
		# so it should not read as a miss and break the player's combo.
		cone.mark_resolved()
		return
	if _counted.has(cone) or _candidates.has(cone):
		return
	_candidates[cone] = 0.0


func _on_catcher_body_exited(body: Node3D) -> void:
	var cone := body as ConeBody
	if cone == null:
		return
	_candidates.erase(cone)
	# A latched car keeps its score: the section already banked it, and
	# un-clearing a finished section would be worse than a slightly generous rule.
	if _latched or not _counted.has(cone):
		return
	var on_roof: bool = _counted[cone]
	_counted.erase(cone)
	cone.release(self)
	EventBus.cone_unlanded.emit(self, on_roof, is_violator)
	progress_changed.emit(_counted.size(), cones_required)


func _settle(cone: ConeBody) -> void:
	_candidates.erase(cone)
	# First car to settle a cone owns it. A cone wedged between two cars pays
	# out once, for whichever car counted it first.
	if not cone.claim(self):
		return

	var on_roof := _roof.overlaps_body(cone)
	_counted[cone] = on_roof
	cone_settled.emit(self, on_roof)
	EventBus.cone_landed.emit(self, on_roof, is_violator)
	progress_changed.emit(_counted.size(), cones_required)

	if _counted.size() >= cones_required:
		_latched = true
		_candidates.clear()
		# The award first: fully_coned is what clears the section, and on the last
		# car that would pay the section bonus before this car's own award.
		if is_violator:
			EventBus.car_coned.emit(self)
		else:
			EventBus.innocent_coned.emit(self)
		fully_coned.emit(self)
