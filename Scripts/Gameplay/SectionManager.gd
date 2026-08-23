class_name SectionManager
extends Node
## Ties the rail to the targets: roll the street's layout, arrive, arm the stop's
## cars, wait for the illegally parked ones to be coned, advance.
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
##
## A section arms every car parked at its stop but only *waits* on the illegally
## parked ones. The correctly parked cars are armed so they can be hit -- coning
## one is a penalty, not a no-op -- and they are deliberately not what clears the
## section, or the player would be rewarded for coning the whole street.

@export var rig: CameraRig
## Usually left empty and found through CameraTrack.GROUP: the track lives
## inside the instanced level scene, which an exported node reference cannot
## reach from the game root.
@export var track: CameraTrack
## Like the track, usually left empty and found through ConeThrower.GROUP. An
## exported reference that fails to resolve leaves restarts unable to clear the
## cones, and nothing about that failure is visible until a second run starts.
@export var thrower: ConeThrower
## The lot that parks the cars. Like the track, it lives inside the level scene,
## so it is normally found through ParkingLot.GROUP rather than wired here.
@export var lot: ParkingLot

## Seconds held after the last car is coned, so the player sees the cone land
## before the camera pulls away.
@export var clear_delay: float = 1.5

## Traces the clear-to-arrival chain to the Output panel. Cheap, and the rail
## is the part of this game with the least visible failure mode.
@export var log_travel: bool = true

## Every car at the stop being played, legally parked ones included.
var _armed: Array[TargetCar] = []
## The subset that is parked illegally. Clearing the section waits on these and
## only these.
var _required: Array[TargetCar] = []
var _coned_count: int = 0
var _time_remaining: float = 0.0


func _ready() -> void:
	_resolve_track()
	EventBus.start_run_requested.connect(start_run)
	EventBus.travel_finished.connect(_on_travel_finished)
	EventBus.section_timeout.connect(_on_section_timeout)
	# The clock is owned by SectionTimer; this only mirrors it so the clear
	# bonus can be paid without reaching into the timer node.
	EventBus.timer_tick.connect(_on_timer_tick)

	# The title screen looks out at the street, so it needs a street to look at.
	# Starting a run rolls it again: the layout the player is shown behind the
	# title is scenery, not the one they will be playing.
	_repark_the_street()


func _resolve_track() -> CameraTrack:
	if track == null:
		track = get_tree().get_first_node_in_group(CameraTrack.GROUP) as CameraTrack
	return track


func _resolve_thrower() -> ConeThrower:
	if thrower == null:
		thrower = get_tree().get_first_node_in_group(ConeThrower.GROUP) as ConeThrower
	return thrower


func _resolve_lot() -> ParkingLot:
	if lot == null:
		lot = get_tree().get_first_node_in_group(ParkingLot.GROUP) as ParkingLot
	return lot


## Starts a fresh run at the first stop.
func start_run() -> void:
	if rig == null:
		push_error("SectionManager: rig is not assigned.")
		return
	if _resolve_track() == null:
		push_error("SectionManager: no CameraTrack found. Add one to the level, "
				+ "or assign the track property directly.")
		return

	GameState.reset_run()
	EventBus.run_started.emit()
	_disarm()

	# Cars first, then cones. Reparking frees the previous run's cars, and each
	# one hands its cones back on the way out, so no cone is left flagged as
	# scored and claimed by a node that no longer exists.
	#
	# This is also where the run gets its replay value: the whole street is rolled
	# again, so which cars are parked badly is different every time.
	_repark_the_street()

	# Every authored car on the track, not just the first stop's: a retry must not
	# inherit cones claimed during the previous run. Bay cars are new nodes and
	# need no reset, but sweeping the lot as well costs nothing and cannot miss.
	for stop in track.get_stops():
		for car in stop.get_section_cars():
			var target := car as TargetCar
			if target != null:
				target.reset()

	var current_thrower := _resolve_thrower()
	if current_thrower != null:
		current_thrower.clear_cones()
		current_thrower.refill()
	else:
		push_error("SectionManager: no ConeThrower found. Cones from the previous "
				+ "run will not be cleared.")

	rig.snap_to(0)


## Rolls a fresh layout for every stop that has bays: once on load for the title
## screen, then once per run before the rig is placed, so the first section
## always arrives at a street that already exists.
func _repark_the_street() -> void:
	if _resolve_track() == null:
		return
	var current_lot := _resolve_lot()
	if current_lot == null:
		for stop in track.get_stops():
			if not stop.parking_spaces.is_empty():
				push_error(("SectionManager: stop '%s' has parking bays but there is no "
						% stop.name)
						+ "ParkingLot in the tree, so they will all stay empty.")
				return
		return

	current_lot.reseed()
	current_lot.clear_cars()
	for stop in track.get_stops():
		var spaces := stop.get_parking_spaces()
		if spaces.is_empty():
			continue
		current_lot.populate(spaces, stop.min_violators, stop.max_violators, stop.min_innocents)


func _on_timer_tick(seconds_remaining: float) -> void:
	_time_remaining = seconds_remaining


func _on_travel_finished(index: int) -> void:
	_disarm()

	if index < 0:
		# The rail ran off its last stop: every section was cleared.
		_end_run(true)
		return

	var current_track := _resolve_track()
	if current_track == null:
		push_error("SectionManager: no CameraTrack found.")
		_end_run(false)
		return

	var stop := current_track.get_stop(index)
	if stop == null:
		_end_run(false)
		return

	for car in stop.get_section_cars():
		var target := car as TargetCar
		if target == null:
			push_warning("SectionManager: %s is not a TargetCar." % car.name)
			continue
		target.cones_required = stop.cones_required
		target.reset()
		_armed.append(target)
		# Only the badly parked cars are connected. A legally parked one still
		# counts cones and still pays out -- in the wrong direction -- but it must
		# never be able to clear the section.
		if not target.is_violator:
			continue
		target.fully_coned.connect(_on_car_fully_coned)
		_required.append(target)

	if _required.is_empty():
		# Nothing worth throwing at. Warn and move on rather than hanging the run
		# on a section that can never be cleared.
		push_warning(("SectionManager: stop %d has no illegally parked car, skipping. "
				% index)
				+ "Check that stop's min_violators and its bays' roles.")
		GameState.section_index = index
		rig.advance()
		return

	_coned_count = 0
	GameState.section_index = index
	GameState.run_state = GameState.RunState.ENGAGED
	_time_remaining = stop.time_limit
	# Armed before started, so anything drawing the targets has them in hand by
	# the time the section is live. Duplicated so a listener cannot reorder ours.
	EventBus.section_armed.emit(_armed.duplicate(), _required.size())
	EventBus.section_started.emit(index, stop.time_limit)


func _on_car_fully_coned(_car: TargetCar) -> void:
	_coned_count += 1
	if _coned_count < _required.size():
		return
	# Deferred out of the emission: _disarm() disconnects fully_coned, and doing
	# that from inside its own emit, in a handler that then awaits, is asking
	# for the coroutine to be torn down with the connection.
	_complete_section.call_deferred()


func _complete_section() -> void:
	if GameState.run_state != GameState.RunState.ENGAGED:
		return

	var index := GameState.section_index
	GameState.run_state = GameState.RunState.SECTION_CLEAR
	_disarm()
	EventBus.section_cleared.emit(index, _time_remaining)
	if log_travel:
		print("[rail] section %d cleared, departing in %.2fs" % [index, clear_delay])

	# Hold before departing so the winning cone is visible where it landed.
	await get_tree().create_timer(clear_delay).timeout
	# The run may have been restarted while we waited.
	if GameState.run_state != GameState.RunState.SECTION_CLEAR:
		if log_travel:
			print("[rail] hold ended in state %d, not departing" % GameState.run_state)
		return
	if log_travel:
		print("[rail] hold ended, calling rig.advance()")
	rig.advance()


func _on_section_timeout(_index: int) -> void:
	_end_run(false)


## The single exit from a run, so no ending can forget to disarm or to say
## whether it was won.
func _end_run(won: bool) -> void:
	if GameState.run_state == GameState.RunState.RUN_OVER:
		return
	_disarm()
	GameState.run_state = GameState.RunState.RUN_OVER
	EventBus.run_over.emit(won)


func _disarm() -> void:
	for car in _required:
		if is_instance_valid(car) and car.fully_coned.is_connected(_on_car_fully_coned):
			car.fully_coned.disconnect(_on_car_fully_coned)
	_armed.clear()
	_required.clear()
	_coned_count = 0
