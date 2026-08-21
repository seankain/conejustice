@tool
class_name CameraTrack
extends Node3D
## The camera rail. Its ordered [CameraStop] children *are* the track.
##
## There is no separate list to keep in sync: reordering the stops in the scene
## tree reorders the route. Non-CameraStop children are ignored, so it is safe
## to park helper nodes under here.


func _ready() -> void:
	if Engine.is_editor_hint():
		child_order_changed.connect(update_configuration_warnings)


## Every stop on the track, in travel order.
func get_stops() -> Array[CameraStop]:
	var stops: Array[CameraStop] = []
	for child in get_children():
		var stop := child as CameraStop
		if stop != null:
			stops.append(stop)
	return stops


## The stop at [param index], or null when the index is off the track. Callers
## use null to detect the end of the rail rather than bounds-checking twice.
func get_stop(index: int) -> CameraStop:
	var stops := get_stops()
	if index < 0 or index >= stops.size():
		return null
	return stops[index]


func stop_count() -> int:
	return get_stops().size()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if stop_count() < 2:
		warnings.append("A track needs at least two CameraStop children to travel between.")
	return warnings
