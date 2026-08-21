class_name SectionTimer
extends Node
## The 60 second countdown on a section.
##
## The clock belongs to the section, not to the run: it starts when the camera
## arrives and stops the moment the section clears. It never runs during the
## travel tween or the post-clear hold, so time spent watching the camera move
## is never charged to the player.

## Seconds left at which the HUD should go red and the audio should start
## beeping. Emitted once as timer_warning so neither has to re-derive it.
@export var low_time_threshold: float = 10.0

var seconds_remaining: float = 0.0
var is_running: bool = false

var _index: int = -1
var _warned: bool = false


func _ready() -> void:
	EventBus.section_started.connect(_on_section_started)
	EventBus.section_cleared.connect(_on_section_cleared)
	EventBus.run_started.connect(_on_run_started)


func _process(delta: float) -> void:
	if not is_running:
		return
	# Only a live section burns clock. This is what pauses the countdown during
	# travel and during the SECTION_CLEAR hold, without either of them having to
	# remember to stop the timer.
	if GameState.run_state != GameState.RunState.ENGAGED:
		return

	seconds_remaining = maxf(seconds_remaining - delta, 0.0)
	EventBus.timer_tick.emit(seconds_remaining)

	if not _warned and seconds_remaining <= low_time_threshold:
		_warned = true
		EventBus.timer_warning.emit()

	if seconds_remaining <= 0.0:
		is_running = false
		EventBus.section_timeout.emit(_index)


func stop() -> void:
	is_running = false


func _on_run_started() -> void:
	is_running = false
	seconds_remaining = 0.0
	_index = -1
	_warned = false


func _on_section_started(index: int, time_limit: float) -> void:
	_index = index
	seconds_remaining = time_limit
	_warned = time_limit <= low_time_threshold
	is_running = true
	# Publish the starting value immediately so the HUD reads 60 on arrival
	# rather than staying blank until the first frame of countdown.
	EventBus.timer_tick.emit(seconds_remaining)


func _on_section_cleared(_index_cleared: int, _time_remaining: float) -> void:
	is_running = false
