@tool
class_name DrivableVehicle
extends Resource
## One car the player can pick and drive: the chassis to spawn, the handful of
## numbers that make it handle like itself, and what the select screen says
## about it.
##
## Adding a car to the game is this resource plus a chassis scene. No code knows
## how many cars there are: the round spawns whichever entry it was handed, and
## the carousel builds a plate per entry in the catalog.
##
## The numbers here are applied to the car on spawn and win over whatever the
## chassis scene was authored with. Godot omits a property equal to its default
## when it saves a resource, so the defaults below are deliberately the SUV's --
## the reference car's entry is a nearly empty file, and every other car's entry
## lists exactly what makes it different.
##
## This is not [VehicleProfile], and the two are deliberately not merged. That
## one answers what Cone Justice's lot needs to know about a car *before* it
## exists, to decide whether it fits a bay. This one answers what the parking
## game needs to build a car that drives. They overlap in nothing but the mesh.

## Shown on the select screen, and nowhere else.
@export var display_name: String = ""

## The chassis, whose root must be a [PlayerCar]. A [PackedScene] rather than a
## path so a renamed scene follows the resource instead of leaving a dead entry.
@export var chassis: PackedScene

@export_group("Handling")
## Kilograms. Applied to the chassis on spawn, so one chassis scene can stand
## in for a heavier or lighter version of the same car without a second scene.
@export var mass: float = 1400.0
## Newtons per driven wheel -- see [member PlayerCar.engine_power], which this
## sets.
@export var engine_power: float = 2200.0
## Steering lock in radians.
@export var max_steer: float = 0.55
## Forward speed in m/s where the engine stops pulling.
@export var top_speed: float = 16.0


## Whether this entry can be spawned at all. A half-filled entry is skipped
## rather than crashing the round.
func is_usable() -> bool:
	return chassis != null


## A car, ready to add to the tree, with this entry's numbers on it.
func spawn() -> PlayerCar:
	if not is_usable():
		push_error("DrivableVehicle: %s has no chassis scene." % describe())
		return null
	var car := chassis.instantiate() as PlayerCar
	if car == null:
		push_error("DrivableVehicle: %s does not instantiate a PlayerCar." % describe())
		return null
	car.mass = mass
	car.engine_power = engine_power
	car.max_steer = max_steer
	car.top_speed = top_speed
	return car


## The car's visuals alone, with no physics body behind them: what the select
## screen puts on a turntable. The body is instanced and thrown away rather than
## the meshes being listed here, so the preview cannot drift from the car.
##
## Returns null if the chassis has no Visuals node, which is the one rule a
## chassis scene has to follow.
func instantiate_preview() -> Node3D:
	if not is_usable():
		return null
	var car := chassis.instantiate()
	var visuals := car.get_node_or_null(^"Visuals") as Node3D
	if visuals == null:
		push_error("DrivableVehicle: %s has no Visuals node to preview." % describe())
		car.free()
		return null
	car.remove_child(visuals)
	# Freed, not queue_freed: this body was never in the tree, and the preview
	# must not be holding a VehicleBody3D that the physics server will pick up.
	car.free()
	visuals.owner = null
	return visuals


## What to call this entry in an error. Its display name, then its file.
func describe() -> String:
	if not display_name.is_empty():
		return display_name
	if not resource_path.is_empty():
		return resource_path.get_file()
	return "<unsaved DrivableVehicle>"
