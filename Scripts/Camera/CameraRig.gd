class_name CameraRig
extends Node3D
## Drives the camera along a [CameraTrack].
##
## The rig carries the transform; the Camera3D under it sits at identity. That
## keeps "where the camera is" in exactly one place, and means nothing has to
## reach through to the camera to move it.

## The rail to follow. Usually left empty: the track lives inside the instanced
## level scene, which an exported node reference cannot reach from here, so it
## is found through CameraTrack.GROUP instead. Set this only when the track and
## the rig are in the same scene.
@export var track: CameraTrack

## Temporary: advance the rail with ui_accept (Space/Enter) so the track is
## testable before SectionManager exists. Turn off once sections drive the rig.
@export var debug_advance_with_ui_accept: bool = true

## Index of the stop the rig is parked at, or -1 before the first placement.
var current_index: int = -1
var is_travelling: bool = false

var _tween: Tween
var _from_xform: Transform3D
var _to_xform: Transform3D


func _ready() -> void:
	resolve_track()
	# Place silently at the first stop so the level looks right on load. No
	# signal here: emitting travel_finished during _ready would fire before
	# SectionManager has connected, and the first section would never arm.
	if track != null and track.stop_count() > 0:
		_place_at(0)


## Returns the track, finding it by group the first time if it was not wired.
func resolve_track() -> CameraTrack:
	if track == null:
		track = get_tree().get_first_node_in_group(CameraTrack.GROUP) as CameraTrack
	return track


func _unhandled_input(event: InputEvent) -> void:
	if debug_advance_with_ui_accept and event.is_action_pressed("ui_accept"):
		advance()


## Jumps straight to a stop, no tween. Used to start a run. Emits
## travel_finished so arrival is handled by the same path as a normal trip.
func snap_to(index: int) -> void:
	_kill_tween()
	if _get_stop(index) == null:
		var where := "no track found" if track == null else "%d stops" % track.stop_count()
		push_error("CameraRig.snap_to: no stop at index %d (%s)." % [index, where])
		return
	_place_at(index)
	is_travelling = false
	EventBus.travel_finished.emit(index)


## Tweens to a stop using that stop's own travel timing. Calling this mid-travel
## retargets from the camera's current position instead of stacking tweens.
func travel_to(index: int) -> void:
	var stop := _get_stop(index)
	if stop == null:
		push_error("CameraRig.travel_to: no stop at index %d." % index)
		return

	_kill_tween()

	var from_index := current_index
	_from_xform = global_transform
	_to_xform = stop.get_parked_transform()
	is_travelling = true
	# The rig only ever sets TRAVELLING. SectionManager owns the transition out
	# of it on arrival, since only it knows whether a section armed or the run ended.
	GameState.run_state = GameState.RunState.TRAVELLING
	EventBus.travel_started.emit(from_index, index)

	_tween = create_tween()
	_tween.set_trans(stop.travel_trans)
	_tween.set_ease(stop.travel_ease)
	_tween.tween_method(_apply_progress, 0.0, 1.0, maxf(stop.travel_time, 0.001))
	_tween.finished.connect(_on_tween_finished.bind(index))


## Moves to the next stop. Past the last one the rail is done: travel_finished
## reports -1 so the run can be wrapped up.
func advance() -> void:
	if resolve_track() == null or current_index + 1 >= track.stop_count():
		_kill_tween()
		is_travelling = false
		EventBus.travel_finished.emit(-1)
		return
	travel_to(current_index + 1)


## The stop the rig is parked at, or null while travelling or unplaced.
func get_current_stop() -> CameraStop:
	if is_travelling:
		return null
	return _get_stop(current_index)


# Interpolating the whole transform slerps the basis. Tweening position and
# rotation as separate properties visibly wobbles between stops that face
# different directions, which is most of them.
func _apply_progress(t: float) -> void:
	global_transform = _from_xform.interpolate_with(_to_xform, t)


func _on_tween_finished(index: int) -> void:
	_tween = null
	is_travelling = false
	current_index = index
	# Land on the exact authored transform rather than the last interpolated
	# step, so a stop's framing is pixel-identical every time it is visited.
	global_transform = _to_xform
	EventBus.travel_finished.emit(index)


func _place_at(index: int) -> void:
	var stop := _get_stop(index)
	if stop == null:
		return
	current_index = index
	global_transform = stop.get_parked_transform()


func _kill_tween() -> void:
	# kill() does not emit finished, so the retargeted trip cannot report an
	# arrival at the stop it was abandoning.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _get_stop(index: int) -> CameraStop:
	if resolve_track() == null:
		return null
	return track.get_stop(index)
