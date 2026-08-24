@tool
class_name VehicleProfile
extends Resource
## One kind of vehicle the street may be filled with: the scene to spawn, and
## the few numbers [ParkingLot] has to know about it *before* it exists.
##
## The split is the whole design. A bay works out how much room it has beside it
## from the width of whatever is parked next door, and it does that while the
## layout is still being decided -- before any of those neighbours have been
## instanced. Anything needed at that point has to be readable off a resource
## rather than measured off a node, and that is the entire reason this file
## exists.
##
## Everything else about a vehicle stays in its scene, next to the mesh it is
## shaped around: the cone catcher, the roof zone, the collision shape, the
## height its HUD bracket hangs at. If getting a number right means looking at
## the model in the editor, it does not belong here.
##
## Authored, then checked. [ParkingLot] measures the car it instanced and warns
## when [member footprint] disagrees with it, the same way it measures a placed
## pose rather than trusting the role it was placed for.

## The vehicle. Must instantiate a [TargetCar]; the lot says so loudly if it
## does not, because a scene that spawns something else leaves a bay that looks
## occupied and cannot be coned.
@export var scene: PackedScene

## Width across and length along, in metres. This is the number the room maths
## runs on: how much of the gap beside a bay this vehicle eats when it is the
## neighbour, and how far it may slew before its own corners swing into that gap.
##
## Derive it with [code]Tools/derive_vehicle_profile.gd[/code] rather than
## guessing -- an authored footprint smaller than the mesh is how two cars end
## up sharing a patch of road.
@export var footprint := Vector2(1.8, 4.5)

## Metres this vehicle's origin sits above the bay marker.
##
## Zero for the SUV, because the bays were authored at its resting height. A
## model whose origin is somewhere else on the body gets the difference here,
## which is one number per vehicle instead of re-levelling every bay in the
## level for it.
@export var bay_height_offset: float = 0.0

## How often this vehicle is drawn, relative to the others in the pool. Halve it
## for something that should show up but not be the street's default; a weight
## of zero is still eligible, but only when nothing else fits the bay.
@export_range(0.0, 10.0, 0.05, "or_greater") var spawn_weight: float = 1.0


## Whether this profile can actually be spawned. A pool entry left half-filled
## in the inspector is skipped rather than crashing a run.
func is_usable() -> bool:
	return scene != null


## What to call this profile in a warning. The resource file's name, or the
## scene's if the profile is inline in a scene rather than saved to disk.
func describe() -> String:
	if not resource_path.is_empty():
		return resource_path.get_file()
	if scene != null and not scene.resource_path.is_empty():
		return scene.resource_path.get_file()
	return "<unsaved VehicleProfile>"


## The box every visible part of [param vehicle] sits inside, in the vehicle's
## own space, or a zero-sized box if it has no meshes.
##
## Both the check in [ParkingLot] and the authoring tool in [code]Tools/[/code]
## measure through here on purpose: an authored footprint and a derived one have
## to be the same measurement, or the check would flag its own disagreement with
## the tool that produced the number.
static func measure_bounds(vehicle: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	# owned = false: a car's meshes are its own scene's children, not children
	# owned by whatever scene the car was instanced into.
	for node in vehicle.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var box := _relative_transform(mesh, vehicle) * mesh.get_aabb()
		if found:
			bounds = bounds.merge(box)
		else:
			bounds = box
			found = true
	return bounds


## [param node]'s transform in [param root]'s space, walked by hand rather than
## taken from global_transform: the authoring tool measures scenes that were
## instanced but never added to the tree, where there is no global to read.
static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			xform = spatial.transform * xform
		current = current.get_parent()
	return xform
