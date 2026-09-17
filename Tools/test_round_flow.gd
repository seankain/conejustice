extends Node
## A round, end to end: the lot fills, the car is graded, the level advances.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless Tools/test_round_flow.tscn
## [/codeblock]
##
## A scene rather than a [code]--script[/code] tool, like the pause test and for
## the same reason: [ParkingRound] names the [SfxPlayer] autoload, and a script
## run with [code]--script[/code] replaces the main loop and never registers
## autoloads, so anything naming one fails to compile. That rules out the whole
## round.
##
## It drives the round by putting the car where a player would have driven it.
## Actually driving it into a specific bay would be a test of the physics, which
## [code]Tools/test_drive_chassis.gd[/code] already covers, and would fail for
## reasons that have nothing to do with the round.

var _failures: Array[String] = []
var _tree: SceneTree = null
var _main: Node3D = null
var _round: ParkingRound = null


func _ready() -> void:
	_tree = get_tree()
	_run()


func _check(condition: bool, description: String) -> void:
	print("  %-4s %s" % ["ok" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await _tree.physics_frame


func _empty_bay() -> ScoredParkingSpace:
	for node in _tree.get_nodes_in_group(ScoredParkingSpace.GROUP):
		var bay := node as ScoredParkingSpace
		if not bay.has_parked_car():
			return bay
	return null


## Two empty bays next to each other, for the manoeuvres that need room.
func _empty_pair() -> Array[ScoredParkingSpace]:
	for node in _tree.get_nodes_in_group(ScoredParkingSpace.GROUP):
		var bay := node as ScoredParkingSpace
		if bay.has_parked_car():
			continue
		for other in _tree.get_nodes_in_group(ScoredParkingSpace.GROUP):
			var next_door := other as ScoredParkingSpace
			if next_door == bay or next_door.has_parked_car():
				continue
			if bay.bay_centre().distance_to(next_door.bay_centre()) < 4.0:
				return [bay, next_door]
	return []


## Moves the car at [param velocity] for [param seconds], holding its yaw, the
## way a car being driven keeps moving. Teleporting it would not do: a car put
## somewhere is a car that has already stopped, and half of what the bays do is
## decide which of them a car is still on its way through.
func _roll(velocity: Vector3, yaw_degrees: float, seconds: float) -> void:
	for i in int(seconds * 60.0):
		_round.car.linear_velocity = velocity
		_round.car.angular_velocity = Vector3.ZERO
		_round.car.global_rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
		await _tree.physics_frame


## Puts the car in [param bay] as though it had been driven there.
func _park(bay: ScoredParkingSpace, offset: Vector3, yaw_degrees: float) -> void:
	_round.car.global_position = bay.bay_centre() + offset + Vector3(0, 0.25, 0)
	_round.car.global_rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	_round.car.linear_velocity = Vector3.ZERO
	_round.car.angular_velocity = Vector3.ZERO


func _run() -> void:
	Parkade.current_game_id = &"parking_game"
	_main = (load("res://Scenes/ParkingGame/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(0.5)
	(_main.get_node("VehicleSelect") as VehicleSelect).confirm()
	await _wait(4.0)
	_round = _main.get_node("Round") as ParkingRound

	print("The lot at level 1")
	var traffic := _round.get_node("Traffic") as TrafficSpawner
	var cars := traffic.parked_cars()
	_check(_round.level == 1, "the cabinet starts at level 1")
	_check(is_equal_approx(ParkingRound.seconds_for_level(1), ParkingRules.DEFAULT_SECONDS),
			"level 1 gets the full clock")
	_check(cars.size() == ParkingRules.VEHICLES_PER_LEVEL, "the lot is filled with level x 2 cars")
	var frozen := 0
	var spots := {}
	for car in cars:
		if car.freeze:
			frozen += 1
		spots[Vector2(car.global_position.x, car.global_position.z).snappedf(1.0)] = true
	_check(frozen == cars.size(), "every parked car has settled and frozen")
	_check(spots.size() == cars.size(), "no two cars share a bay")

	var painted_glass := false
	var painted_any := false
	for car in cars:
		var body := car.visuals.get_node("Body") as MeshInstance3D
		for surface in body.mesh.get_surface_count():
			var override := body.get_surface_override_material(surface)
			if override == null:
				continue
			painted_any = true
			var material := body.mesh.surface_get_material(surface)
			var material_name := material.resource_name.to_lower() if material != null else ""
			if material_name.contains("glass") or material_name.contains("optic"):
				painted_glass = true
	_check(painted_any, "parked cars are painted")
	_check(not painted_glass, "the paint stays off the glass and the lights")

	print("A square park")
	var bay := _empty_bay()
	_check(bay != null, "the lot always keeps a bay free")
	_park(bay, Vector3.ZERO, 90.0)
	await _wait(2.0)
	_check(_round.state == ParkingRound.State.OVER, "coming to rest in a bay ends the round")
	_check(_round.data.grade_letter() == "A", "square and centred is an A")
	_check(not _round.car.input_enabled, "the car is taken off the player while it is graded")

	print("The next level")
	await _wait(ParkingRules.ROUND_OVER_SECONDS + 0.5)
	_check(_round.level == 2, "a pass advances a level")
	_check(_round.seconds_remaining < ParkingRules.DEFAULT_SECONDS, "and the clock is shorter")
	_check(_round.car.input_enabled, "the car is handed back")
	await _wait(3.5)
	_check(traffic.parked_cars().size() == 2 * ParkingRules.VEHICLES_PER_LEVEL,
			"and the lot is fuller")

	print("A bad park")
	var level_before := _round.level
	bay = _empty_bay()
	_round.data.collisions.append(Obstacle.Kind.VEHICLE)
	_park(bay, Vector3(0.6, 0, 1.3), 70.0)
	await _wait(2.0)
	_check(_round.data.grade_letter() == "F", "slewed, off centre, over a line and a collision is an F")
	await _wait(ParkingRules.ROUND_OVER_SECONDS + 0.5)
	_check(_round.level == level_before, "a failure re-runs the same level")

	print("Running out of time away from a bay")
	_round.car.global_position = Vector3(6.0, 0.6, 0.0)
	await _wait(0.5)
	_round.seconds_remaining = 0.5
	await _wait(1.5)
	_check(_round.state == ParkingRound.State.OVER, "the clock ends the round")
	_check(not _round.data.parked_in_space and _round.data.grade_letter() == "F",
			"parking nowhere is an F")

	print("Falling out of the world")
	await _wait(ParkingRules.ROUND_OVER_SECONDS + 0.5)
	var clock_before := _round.seconds_remaining
	await _wait(1.0)
	_round.car.global_position = Vector3(0.0, -60.0, 0.0)
	await _wait(1.5)
	_check(_round.car.global_position.y > -5.0, "the kill plane puts the car back")
	_check(_round.seconds_remaining > clock_before, "and the attempt starts over")

	print("A park that brushes the bay next door")
	await _wait(ParkingRules.ROUND_OVER_SECONDS + 1.5)
	var pair := _empty_pair()
	_check(not pair.is_empty(), "the lot has two empty bays side by side")
	var target := pair[0]
	var next_door := pair[1]
	var middle := target.bay_centre()
	# In off the aisle, a lean over the line towards the bay next door, and then
	# straight again -- which is how a car is actually parked, and which used to
	# leave the round scoring no bay at all: the last bay entered was the one it
	# brushed, and leaving that one again cleared it.
	_round.car.global_position = Vector3(middle.x + 5.5, middle.y + 0.25, middle.z)
	_round.car.global_rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	await _roll(Vector3(-3.0, 0, 0), 90.0, 1.6)
	await _roll(Vector3(0, 0, signf(next_door.bay_centre().z - middle.z) * 1.2), 90.0, 1.0)
	await _roll(Vector3(0, 0, signf(middle.z - next_door.bay_centre().z) * 1.2), 90.0, 1.0)
	_round.car.linear_velocity = Vector3.ZERO
	await _wait(2.0)
	_check(_round.state == ParkingRound.State.OVER,
			"stopping between the lines ends the round, whatever the car brushed on the way in")
	_check(_round.data.parked_in_space, "and it is graded as parked")

	if _failures.is_empty():
		print("PASS")
		_tree.quit(0)
		return
	printerr("%d check(s) failed" % _failures.size())
	_tree.quit(1)
