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

## Cars that must be coned before the rail advances. Paths are relative to this
## stop. An empty list means the section can never be cleared.
@export var target_cars: Array[NodePath] = []:
	set(value):
		target_cars = value
		update_configuration_warnings()

## Cones that must settle on each car for it to count as coned.
@export_range(1, 10) var cones_required: int = 3

## Seconds allowed once the camera arrives. The clock does not run before that.
@export_range(5.0, 180.0, 1.0) var time_limit: float = 60.0

## Seconds spent travelling *into* this stop from the previous one. A stop owns
## its own approach, so retiming one leg never touches its neighbours.
@export_range(0.0, 10.0, 0.1) var travel_time: float = 2.5

@export var travel_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var travel_ease: Tween.EaseType = Tween.EASE_IN_OUT


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
## point at anything. Returns Node3D because TargetCar does not exist yet.
func get_target_cars() -> Array[Node3D]:
	var cars: Array[Node3D] = []
	for path in target_cars:
		if path.is_empty():
			continue
		var node := get_node_or_null(path) as Node3D
		if node != null:
			cars.append(node)
	return cars


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if target_cars.is_empty():
		warnings.append("No target_cars set: this section can never be cleared.")
	for path in target_cars:
		if path.is_empty():
			warnings.append("An entry in target_cars is empty.")
			continue
		var node := get_node_or_null(path)
		if node == null:
			warnings.append("target_cars path does not resolve: \"%s\"." % path)
		elif not (node is Node3D):
			warnings.append("target_cars path is not a Node3D: \"%s\"." % path)
	return warnings
