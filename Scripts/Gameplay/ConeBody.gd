class_name ConeBody
extends RigidBody3D
## A thrown traffic cone.
##
## Physics layers used by the game:
##   1  world    ground plane, building
##   2  cars     target vehicles
##   3  cones    everything thrown
## Cones sit on layer 3 and mask 1|2|3, so cone-vs-cone contacts can be made
## cheaper later without touching how the world or the cars collide.
##
## Geometry, for anyone tuning throws: the hull runs y -0.25 to +0.51 (0.76m
## tall), tapering from a 0.36m-wide skirt to a 0.07m tip, over a 0.51m square
## base plate. The origin sits at mid-height, 0.25m above the bottom of the plate.

## Seconds a cone may live once thrown. Scored cones ignore this: they are the
## scoreboard the player can see, so they stay where they landed.
@export var despawn_time: float = 25.0

## Below this height a cone has left the world through a seam and is never
## coming back. Cheaper and more reliable than trusting the ground to catch it.
@export var kill_below_y: float = -5.0

## Seconds at rest, off any car, before the throw is called a miss. Longer than
## TargetCar's settle_time on purpose: a cone landing on a car must win that
## race and be claimed before this fires, or every landing would also miss.
@export var miss_settle_time: float = 1.0

## Speed below which a cone counts as at rest, in m/s.
@export var miss_settle_speed: float = 0.35

## Set by TargetCar once this cone counts toward a car. Keeps it out of the
## despawn timer and out of the thrower's live-cone cull.
var is_scored: bool = false

## The TargetCar currently counting this cone. Untyped to avoid a hard cycle
## between the two scripts. A cone wedged between two cars pays out once only.
var claimed_by: Node = null

var _age: float = 0.0
## A throw resolves exactly once, as a landing or as a miss.
var _resolved: bool = false
var _rest_time: float = 0.0


func _physics_process(delta: float) -> void:
	if global_position.y < kill_below_y:
		# Out of the world: a miss, and not a close one.
		_resolve_miss()
		queue_free()
		return

	if is_scored:
		# A landing resolves the throw. Being knocked off later does not turn it
		# back into a miss; the combo was already earned.
		_resolved = true
		return

	if not _resolved:
		if linear_velocity.length() < miss_settle_speed:
			_rest_time += delta
			if _rest_time >= miss_settle_time:
				_resolve_miss()
		else:
			_rest_time = 0.0

	_age += delta
	if _age >= despawn_time:
		queue_free()


## Settles the throw without scoring it and without calling it a miss. Used for
## a cone that hit a car which was already fully coned: wasted, not fumbled.
func mark_resolved() -> void:
	_resolved = true
	_rest_time = 0.0


## Calls the throw a miss, once. Waiting for the despawn timer instead would
## break the combo some twenty seconds after the throw that earned it.
func _resolve_miss() -> void:
	if _resolved:
		return
	_resolved = true
	EventBus.cone_missed.emit()


## Claims this cone for a car. Returns false when another car got there first,
## which is how a cone touching two cars is stopped from counting for both.
func claim(car: Node) -> bool:
	if claimed_by != null:
		return false
	claimed_by = car
	is_scored = true
	return true


## Releases a claim, e.g. when a later throw knocks this cone off the car.
## Only the claiming car may release it.
func release(car: Node) -> void:
	if claimed_by == car:
		claimed_by = null
		is_scored = false
