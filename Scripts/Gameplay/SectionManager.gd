class_name SectionManager
extends Node
## Ties the rail to the targets: arrive, arm the stop's cars, wait for them all
## to be coned, advance.
##
##     IDLE --start_run()--> TRAVELLING --arrival--> ENGAGED
##                               ^                      |
##                               |              all cars coned
##                               |                      v
##                               +---------------- SECTION_CLEAR
##
## Every per-section signal connection is torn down on the way out. A stale
## fully_coned connection from a previous section silently corrupts the next
## section's count, and that is a miserable bug to find later.

@export var rig: CameraRig
@export var track: CameraTrack
@export var thrower: ConeThrower

## Seconds held after the last car is coned, so the player sees the cone land
## before the camera pulls away.
@export var clear_delay: float = 1.5

## Cars armed for the section being played.
var _armed: Array[TargetCar] = []
var _coned_count: int = 0
var _time_remaining: float = 0.0


func _ready() -> void:
	EventBus.travel_finished.connect(_on_travel_finished)
	EventBus.section_timeout.connect(_on_section_timeout)


## Starts a fresh run at the first stop.
func start_run() -> void:
	if track == null or rig == null:
		push_error("SectionManager: rig and track must be assigned.")
		return

	GameState.reset_run()
	_disarm()
	if thrower != null:
		thrower.clear_cones()
		thrower.refill()

	# Every car on the track, not just the first stop's: a retry must not
	# inherit cones claimed during the previous run.
	for stop in track.get_stops():
		for car in stop.get_target_cars():
			var target := car as TargetCar
			if target != null:
				target.reset()

	rig.snap_to(0)


## Reported by SectionTimer so the clear bonus can be paid. Kept as a setter
## rather than read back from the timer, so the timer stays a leaf.
func set_time_remaining(seconds: float) -> void:
	_time_remaining = seconds


func _on_travel_finished(index: int) -> void:
	_disarm()

	if index < 0:
		# The rail ran off its last stop: the run is won.
		GameState.run_state = GameState.RunState.RUN_OVER
		return

	var stop := track.get_stop(index)
	if stop == null:
		GameState.run_state = GameState.RunState.RUN_OVER
		return

	for car in stop.get_target_cars():
		var target := car as TargetCar
		if target == null:
			push_warning("SectionManager: %s is not a TargetCar." % car.name)
			continue
		target.cones_required = stop.cones_required
		target.reset()
		target.fully_coned.connect(_on_car_fully_coned)
		_armed.append(target)

	if _armed.is_empty():
		# Nothing to shoot at. Warn and move on rather than hanging the run on a
		# section that can never be cleared.
		push_warning("SectionManager: stop %d has no TargetCar targets, skipping." % index)
		GameState.section_index = index
		rig.advance()
		return

	_coned_count = 0
	GameState.section_index = index
	GameState.run_state = GameState.RunState.ENGAGED
	_time_remaining = stop.time_limit
	EventBus.section_started.emit(index, stop.time_limit)


func _on_car_fully_coned(_car: TargetCar) -> void:
	_coned_count += 1
	if _coned_count < _armed.size():
		return

	var index := GameState.section_index
	GameState.run_state = GameState.RunState.SECTION_CLEAR
	_disarm()
	EventBus.section_cleared.emit(index, _time_remaining)

	# Hold before departing so the winning cone is visible where it landed.
	await get_tree().create_timer(clear_delay).timeout
	# The run may have been restarted while we waited.
	if GameState.run_state == GameState.RunState.SECTION_CLEAR:
		rig.advance()


func _on_section_timeout(_index: int) -> void:
	_disarm()
	GameState.run_state = GameState.RunState.RUN_OVER


func _disarm() -> void:
	for car in _armed:
		if is_instance_valid(car) and car.fully_coned.is_connected(_on_car_fully_coned):
			car.fully_coned.disconnect(_on_car_fully_coned)
	_armed.clear()
	_coned_count = 0
