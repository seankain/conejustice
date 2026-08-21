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
## Geometry, for anyone tuning throws: the hull runs y -0.51 to +0.25 (0.76m
## tall) with a 0.51m square base plate, and the origin sits near the top of it,
## roughly 0.5m above the tip.

## Seconds a cone may live once thrown. Scored cones ignore this: they are the
## scoreboard the player can see, so they stay where they landed.
@export var despawn_time: float = 25.0

## Below this height a cone has left the world through a seam and is never
## coming back. Cheaper and more reliable than trusting the ground to catch it.
@export var kill_below_y: float = -5.0

## Set by TargetCar once this cone counts toward a car. Keeps it out of the
## despawn timer and out of the thrower's live-cone cull.
var is_scored: bool = false

var _age: float = 0.0


func _physics_process(delta: float) -> void:
	if global_position.y < kill_below_y:
		queue_free()
		return

	if is_scored:
		return

	_age += delta
	if _age >= despawn_time:
		queue_free()
