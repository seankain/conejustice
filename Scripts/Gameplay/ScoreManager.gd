class_name ScoreManager
extends Node
## Turns the event stream into a number.
##
## Listens to EventBus and nothing else: it never reaches into a car, a cone or
## the section manager. That makes the score a pure function of what happened,
## and means scoring rules can be retuned without touching gameplay code.
##
## Coning a correctly parked car is the one way to lose points here, and it has
## to hurt enough that the player looks before throwing -- otherwise the cheapest
## strategy is to cone every car in the area and let the section sort it out.

@export_group("Awards")
@export var points_cone_body: int = 100
@export var points_cone_roof: int = 250
@export var points_car_coned: int = 500
@export var points_section_cleared: int = 1000
## Multiplied by whole seconds left on the clock when a section clears.
@export var points_per_second_left: int = 10

@export_group("Penalties")
## Taken off for each cone that settles on a correctly parked car.
@export var penalty_innocent_cone: int = 200
## Taken off again when a correctly parked car takes a full set of cones, on top
## of what its cones already cost. Doing it by accident is one thing; burying the
## car is another.
@export var penalty_innocent_car: int = 600

@export_group("Combo")
## Consecutive landings raise the multiplier. Without it every section pays the
## same and a good run feels no different from a lucky one.
@export var combo_max: int = 4

## Height above a car's origin that a score popup floats from, roughly where a
## cone comes to rest on the bodywork.
@export var popup_height: float = 1.2

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
	EventBus.innocent_coned.connect(_on_innocent_coned)


func _on_run_started() -> void:
	combo = 1
	_awards.clear()


func _on_section_started(_index: int, _time_limit: float) -> void:
	# A new section starts cold. Carrying a combo across the travel tween would
	# reward the previous section twice.
	combo = 1
	_awards.clear()


func _on_cone_landed(car: Node3D, on_roof: bool, on_violator: bool) -> void:
	if not on_violator:
		# No roof bonus and no multiplier on a mistake, and the streak that was
		# building dies with it. A well-aimed cone on the wrong car is still wrong.
		_land(car, -penalty_innocent_cone)
		combo = 1
		return

	var base := points_cone_roof if on_roof else points_cone_body
	_land(car, base * combo)
	combo = mini(combo + 1, combo_max)


func _on_cone_unlanded(car: Node3D, _on_roof: bool, _on_violator: bool) -> void:
	_award(-_pop_award(car))


func _on_cone_missed() -> void:
	combo = 1


func _on_car_coned(_car: Node3D) -> void:
	_award(points_car_coned)


func _on_innocent_coned(_car: Node3D) -> void:
	_award(-penalty_innocent_car)


func _on_section_cleared(_index: int, time_remaining: float) -> void:
	var seconds := floori(maxf(time_remaining, 0.0))
	var total := points_section_cleared + seconds * points_per_second_left
	_award(total)
	# Broken out so the transition can count the bonus up without knowing, or
	# duplicating, any of the rules above.
	EventBus.section_bonus.emit(seconds, total)
	combo = 1


## Pays out for a cone that settled, remembers what was actually paid, and floats
## it where it was earned. This is the only place that knows both halves.
func _land(car: Node3D, amount: int) -> void:
	# What was applied, not what was nominally worth: the score floors at zero, so
	# a penalty near the bottom takes less than its face value, and a popup or a
	# later reversal quoting the face value would be inventing points.
	var applied := _award(amount)
	_push_award(car, applied)
	if applied != 0:
		EventBus.score_popup.emit(applied, car.global_position + Vector3.UP * popup_height)


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


## Applies an award and returns what actually landed on the score. Clamped at
## zero, so a penalty near the bottom is smaller than its face value and callers
## that remember it for a later reversal remember the real number.
func _award(amount: int) -> int:
	if amount == 0:
		return 0
	var before := GameState.score
	GameState.score = maxi(before + amount, 0)
	var applied := GameState.score - before
	if applied != 0:
		EventBus.score_changed.emit(GameState.score, applied)
	return applied
