@tool
class_name CameraStop
extends Marker3D
## One parking spot on the camera rail, and the section played there.
##
## Place and aim it in the editor; the gizmo you drag is exactly where the
## camera ends up. Location and section rules live on the same node on purpose,
## so tuning a stop never means hunting for its config somewhere else.

## Where the camera looks while parked here. Leave null to use the marker's own
## facing (its local -Z), which the gizmo already shows.
@export var look_target: Node3D:
	set(value):
		look_target = value
		update_configuration_warnings()

## Cars authored straight into the level, with no bay behind them. Every one of
## these is a target: a hand-placed car in this game has always meant "cone me".
## Paths are relative to this stop.
@export var target_cars: Array[NodePath] = []:
	set(value):
		target_cars = value
		update_configuration_warnings()

## Parking bays this section overlooks. The cars in them are spawned and rolled
## per run, so which of them are parked illegally changes between runs and the
## section stops being something the player can memorise. Paths are relative to
## this stop.
@export var parking_spaces: Array[NodePath] = []:
	set(value):
		parking_spaces = value
		update_configuration_warnings()

@export_group("Violators")
## Fewest cars in this section parked illegally. Below one the section has
## nothing that can clear it, and the rail rolls straight past.
@export_range(0, 10) var min_violators: int = 1
## Most cars in this section parked illegally. Capped by the number of bays.
@export_range(0, 10) var max_violators: int = 2
## Cars deliberately parked correctly, held back before the spare bays are rolled
## for occupancy. Without at least one there is nothing to get wrong, and the
## section is a plain shooting gallery again.
@export_range(0, 10) var min_innocents: int = 1

@export_group("")

## Cones that must settle on each car for it to count as coned.
@export_range(1, 10) var cones_required: int = 3

## Seconds allowed once the camera arrives. The clock does not run before that.
@export_range(5.0, 180.0, 1.0) var time_limit: float = 60.0

## Seconds spent travelling *into* this stop from the previous one. A stop owns
## its own approach, so retiming one leg never touches its neighbours.
@export_range(0.0, 10.0, 0.1) var travel_time: float = 2.5

## Stored as plain ints rather than Tween.TransitionType / Tween.EaseType.
## The values match those enums one for one; the named types are avoided here
## because exporting an engine enum is the kind of thing that stops a script
## compiling, and a CameraStop that fails to compile takes the whole rail with it.
@export_enum("Linear", "Sine", "Quint", "Quart", "Quad", "Expo", "Elastic",
		"Cubic", "Circ", "Bounce", "Back", "Spring")
var travel_trans: int = Tween.TRANS_CUBIC

@export_enum("In", "Out", "InOut", "OutIn")
var travel_ease: int = Tween.EASE_IN_OUT


## The transform the camera parks at: this marker, already aimed at
## [member look_target]. The rig never has to think about aiming.
func get_parked_transform() -> Transform3D:
	var xform := global_transform
	if look_target != null and is_instance_valid(look_target):
		var to_target := look_target.global_position - xform.origin
		if to_target.length_squared() > 0.000001:
			# looking_at() fails when the view direction is parallel to up, which
			# happens the moment someone puts a stop directly above a car.
			var up := Vector3.UP
			if absf(to_target.normalized().dot(up)) > 0.999:
				up = Vector3.FORWARD
			xform = xform.looking_at(look_target.global_position, up)
	# A camera inheriting scale from a parent is never what anyone wanted.
	return xform.orthonormalized()


## Resolves [member target_cars] to live nodes, skipping paths that no longer
## point at anything.
func get_target_cars() -> Array[Node3D]:
	var cars: Array[Node3D] = []
	for path in target_cars:
		if path.is_empty():
			continue
		var node := get_node_or_null(path) as Node3D
		if node != null:
			cars.append(node)
	return cars


## Resolves [member parking_spaces] to live bays, skipping paths that no longer
## point at one.
func get_parking_spaces() -> Array[ParkingSpace]:
	var spaces: Array[ParkingSpace] = []
	for path in parking_spaces:
		if path.is_empty():
			continue
		var space := get_node_or_null(path) as ParkingSpace
		if space != null:
			spaces.append(space)
	return spaces


## Every car this section is played against: the ones parked in its bays this run
## plus any authored directly in the level. Innocent cars are in here too --
## they can be hit, so the section has to know about them.
func get_section_cars() -> Array[Node3D]:
	var cars := get_target_cars()
	for space in get_parking_spaces():
		var car := space.get_occupant()
		if car != null:
			cars.append(car)
	return cars


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if target_cars.is_empty() and parking_spaces.is_empty():
		warnings.append("No target_cars and no parking_spaces set: this section has "
				+ "nothing to play against and can never be cleared.")
	if max_violators < min_violators:
		warnings.append("max_violators is below min_violators; min_violators wins.")
	if not parking_spaces.is_empty() and min_violators < 1:
		warnings.append("min_violators is zero, so this section may roll a layout with "
				+ "nothing illegally parked in it and be skipped.")
	if not parking_spaces.is_empty() and parking_spaces.size() < min_violators + min_innocents:
		warnings.append("Fewer parking_spaces than min_violators plus min_innocents: "
				+ "the guarantees cannot all be met.")
	for path in target_cars:
		if path.is_empty():
			warnings.append("An entry in target_cars is empty.")
			continue
		var node := get_node_or_null(path)
		if node == null:
			warnings.append("target_cars path does not resolve: \"%s\"." % path)
		elif not (node is Node3D):
			warnings.append("target_cars path is not a Node3D: \"%s\"." % path)
	for path in parking_spaces:
		if path.is_empty():
			warnings.append("An entry in parking_spaces is empty.")
			continue
		var node := get_node_or_null(path)
		if node == null:
			warnings.append("parking_spaces path does not resolve: \"%s\"." % path)
		elif not (node is ParkingSpace):
			warnings.append("parking_spaces path is not a ParkingSpace: \"%s\"." % path)
	return warnings
