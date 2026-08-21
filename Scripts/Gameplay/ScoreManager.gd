class_name ScoreManager
extends Node
## Turns the event stream into a number.
##
## Listens to EventBus and nothing else: it never reaches into a car, a cone or
## the section manager. That makes the score a pure function of what happened,
## and means scoring rules can be retuned without touching gameplay code.

@export_group("Awards")
@export var points_cone_body: int = 100
@export var points_cone_roof: int = 250
@export var points_car_coned: int = 500
@export var points_section_cleared: int = 1000
## Multiplied by whole seconds left on the clock when a section clears.
@export var points_per_second_left: int = 10

@export_group("Combo")
## Consecutive landings raise the multiplier. Without it every section pays the
## same and a good run feels no different from a lucky one.
@export var combo_max: int = 4

## Current multiplier, 1 through combo_max.
var combo: int = 1

## Car instance id -> stack of amounts awarded for cones on that car, newest
## last. A knocked-off cone pops the most recent, so a reversal gives back what
## was actually paid rather than a base value that ignores the multiplier.
var _awards: Dictionary = {}


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.section_started.connect(_on_section_started)
	EventBus.section_cleared.connect(_on_section_cleared)
	EventBus.cone_landed.connect(_on_cone_landed)
	EventBus.cone_unlanded.connect(_on_cone_unlanded)
	EventBus.cone_missed.connect(_on_cone_missed)
	EventBus.car_coned.connect(_on_car_coned)


func _on_run_started() -> void:
	combo = 1
	_awards.clear()


func _on_section_started(_index: int, _time_limit: float) -> void:
	# A new section starts cold. Carrying a combo across the travel tween would
	# reward the previous section twice.
	combo = 1
	_awards.clear()


func _on_cone_landed(car: Node3D, on_roof: bool) -> void:
	var base := points_cone_roof if on_roof else points_cone_body
	var awarded := base * combo
	_push_award(car, awarded)
	_award(awarded)
	combo = mini(combo + 1, combo_max)


func _on_cone_unlanded(car: Node3D, _on_roof: bool) -> void:
	_award(-_pop_award(car))


func _on_cone_missed() -> void:
	combo = 1


func _on_car_coned(_car: Node3D) -> void:
	_award(points_car_coned)


func _on_section_cleared(_index: int, time_remaining: float) -> void:
	_award(points_section_cleared + floori(maxf(time_remaining, 0.0)) * points_per_second_left)
	combo = 1


func _push_award(car: Node3D, amount: int) -> void:
	var key := car.get_instance_id()
	if not _awards.has(key):
		_awards[key] = PackedInt32Array()
	var stack: PackedInt32Array = _awards[key]
	stack.append(amount)
	_awards[key] = stack


func _pop_award(car: Node3D) -> int:
	var key := car.get_instance_id()
	if not _awards.has(key):
		return 0
	var stack: PackedInt32Array = _awards[key]
	if stack.is_empty():
		return 0
	var amount := stack[stack.size() - 1]
	stack.remove_at(stack.size() - 1)
	_awards[key] = stack
	return amount


func _award(amount: int) -> void:
	if amount == 0:
		return
	# Clamp at zero and report what was actually applied, so a reversal near
	# zero cannot make the HUD float a delta the score never took.
	var before := GameState.score
	GameState.score = maxi(before + amount, 0)
	var applied := GameState.score - before
	if applied != 0:
		EventBus.score_changed.emit(GameState.score, applied)
