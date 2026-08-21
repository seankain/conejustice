@tool
class_name CameraTrack
extends Node3D
## The camera rail. Its ordered [CameraStop] children *are* the track.
##
## There is no separate list to keep in sync: reordering the stops in the scene
## tree reorders the route. Non-CameraStop children are ignored, so it is safe
## to park helper nodes under here.

## The track joins this group so CameraRig and SectionManager can find it. They
## live in the game root while the track lives inside the instanced level scene,
## and an exported node reference cannot be wired across that boundary.
const GROUP := &"camera_track"


func _enter_tree() -> void:
	# _enter_tree, not _ready: the whole tree enters before anything is ready,
	# so consumers can resolve the track in their own _ready.
	add_to_group(GROUP)


func _ready() -> void:
	if Engine.is_editor_hint():
		child_order_changed.connect(update_configuration_warnings)
		return

	# Report a dead rail once, here, rather than letting every later call quietly
	# return null. An empty stop list means the camera never moves and no section
	# ever arms, which on its own gives no clue where to look.
	if get_stops().is_empty():
		var markers := 0
		for child in get_children():
			if child is Marker3D:
				markers += 1
		if markers > 0:
			push_error(("CameraTrack '%s': %d Marker3D children but none are " % [name, markers])
					+ "CameraStop. The markers are there, so CameraStop.gd is not "
					+ "attaching. Check the Output panel for a parse error in it.")
		else:
			push_error("CameraTrack '%s' has no CameraStop children at all." % name)


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
