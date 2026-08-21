class_name TargetCar
extends StaticBody3D
## An illegally parked car, and the rules for deciding when it has been coned.
##
## The hard part is telling a cone that landed from a cone that merely touched.
## A cone counts only once it has been overlapping the catcher *at rest* for
## settle_time without interruption, which is what rejects a graze: a cone that
## clips the bumper and rolls into the gutter is never still while touching.

## Cones that must settle on this car before it counts as coned. Overwritten
## per section by the CameraStop that owns this car.
@export var cones_required: int = 3

## Continuous seconds a cone must sit still, in contact, before it counts.
@export var settle_time: float = 0.5

## Speed below which a cone counts as at rest, in m/s.
@export var settle_speed: float = 0.35

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
	EventBus.cone_unlanded.emit(self, on_roof)
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
	EventBus.cone_landed.emit(self, on_roof)
	progress_changed.emit(_counted.size(), cones_required)

	if _counted.size() >= cones_required:
		_latched = true
		_candidates.clear()
		# car_coned first: fully_coned is what clears the section, and on the
		# last car that would pay the section bonus before this car's award.
		EventBus.car_coned.emit(self)
		fully_coned.emit(self)
