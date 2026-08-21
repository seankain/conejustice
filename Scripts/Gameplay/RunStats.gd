extends Node
## Keeps the tallies the run-over screen reports.
##
## Separate from ScoreManager on purpose: that one owns the scoring rules, this
## one just counts. Both listen to EventBus and neither reaches into the other.

func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.cone_thrown.connect(_on_cone_thrown)
	EventBus.cone_landed.connect(_on_cone_landed)
	EventBus.cone_unlanded.connect(_on_cone_unlanded)
	EventBus.car_coned.connect(_on_car_coned)


func _on_run_started() -> void:
	GameState.cones_thrown = 0
	GameState.cones_landed = 0
	GameState.cars_coned = 0


func _on_cone_thrown(_remaining: int, _cooldown: float) -> void:
	GameState.cones_thrown += 1


func _on_cone_landed(_car: Node3D, _on_roof: bool) -> void:
	GameState.cones_landed += 1


func _on_cone_unlanded(_car: Node3D, _on_roof: bool) -> void:
	# A cone knocked off is no longer landed, so accuracy stays honest.
	GameState.cones_landed = maxi(GameState.cones_landed - 1, 0)


func _on_car_coned(_car: Node3D) -> void:
	GameState.cars_coned += 1
