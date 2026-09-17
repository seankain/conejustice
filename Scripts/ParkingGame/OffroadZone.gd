class_name OffroadZone
extends Area3D
## Grass, kerbs and everything else that is not the tarmac. Counts how long the
## player spends on it, which the round grades against.
##
## Ported from [code]OffroadArea.cs[/code]. That version resolves the level by
## the absolute path [code]/root/Main/Level[/code] in [code]_Ready[/code] and
## writes [code]level.levelData.OffroadingTime[/code] every frame, which cannot
## survive the game being instanced under Parkade as a cabinet. This one keeps
## its own total and says when it changes; the round reads it.
##
## Several zones can exist in one lot. Each counts the time the player is inside
## it, so a player standing in an overlap is charged by each -- which is why a
## lot should not overlap its own grass.

## The player drove onto, or off, this zone.
signal offroad_changed(offroad: bool)

## Seconds the player has spent inside this zone since the last [method reset].
var seconds_offroad: float = 0.0

## Whether the player is on it right now.
var player_inside: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if player_inside:
		seconds_offroad += delta


## Called by the round when it starts a new one. The zone is part of the lot and
## outlives the round, so it cannot use its own lifetime as the clock.
func reset() -> void:
	seconds_offroad = 0.0


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(PlayerCar.GROUP):
		return
	player_inside = true
	offroad_changed.emit(true)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group(PlayerCar.GROUP):
		return
	# Asked of the zone rather than tracked with a counter: a car can leave one
	# of its shapes and still be standing on another.
	player_inside = _player_still_here()
	if not player_inside:
		offroad_changed.emit(false)


func _player_still_here() -> bool:
	for body in get_overlapping_bodies():
		if body.is_in_group(PlayerCar.GROUP):
			return true
	return false
