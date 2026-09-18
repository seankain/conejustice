extends Node
## The lot doing something: a car leaving, a rival arriving, and the odds of both.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless Tools/test_lot_events.tscn
## [/codeblock]
##
## A scene rather than a [code]--script[/code] tool, like the round-flow test and
## for the same reason: [ParkingRound] names the [SfxPlayer] autoload, and a
## script run with [code]--script[/code] never registers autoloads.
##
## The events are forced rather than waited for. Their whole point is that they
## are a die roll, and a test that waited for one to come up would be a test that
## fails one run in five -- so [method LotEvents.start_departure] and
## [method LotEvents.start_arrival] are public, the odds are checked as a table,
## and what those two do is checked by calling them.
##
## The clock is pushed out of the way for the same reason: a round is sixty
## seconds and a car takes ten to get off the lot, so the test would otherwise be
## measuring the round ending rather than the car leaving.

## Seconds a car is given to get where it is going before the test calls it
## stuck. Generous: the lot is 33 m end to end and a car crosses it at six
## metres a second, with a manoeuvre at each end.
const PATIENCE := 30.0

var _failures: Array[String] = []
var _tree: SceneTree = null
var _main: Node3D = null
var _round: ParkingRound = null
var _events: LotEvents = null
var _traffic: TrafficSpawner = null
## What the lot's events said happened. Members rather than locals because a
## GDScript lambda captures a local by value, so a signal handler that wrote to
## one would be writing to its own copy.
var _left_from: ScoredParkingSpace = null
var _wanted: ScoredParkingSpace = null
var _took: ScoredParkingSpace = null


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


## Waits until [param done] returns true, or until the patience runs out.
func _until(done: Callable, seconds: float = PATIENCE) -> bool:
	for i in int(seconds * 60.0):
		if done.call():
			return true
		await _tree.physics_frame
	return false


func _npc_cars() -> Array:
	return _tree.get_nodes_in_group(TrafficSpawner.VEHICLE_GROUP)


## Keeps the round from ending underneath the test.
func _hold_the_clock() -> void:
	_round.seconds_remaining = 600.0


func _on_car_leaving(bay: ScoredParkingSpace) -> void:
	_left_from = bay


func _on_rival_arriving(bay: ScoredParkingSpace) -> void:
	_wanted = bay


func _on_rival_parked(bay: ScoredParkingSpace) -> void:
	_took = bay


func _bay_is_empty() -> bool:
	return _left_from != null and not _left_from.has_parked_car()


func _nothing_is_driving() -> bool:
	return _events.drivers.is_empty()


func _a_rival_has_parked() -> bool:
	return _took != null


func _run() -> void:
	print("The odds, level by level")
	var rows := ""
	for level in range(1, 11):
		rows += "  level %2d  leaving %.2f  arriving %.2f  focus %.2f  drivers %d\n" % [
			level,
			ParkingRules.departure_chance(level),
			ParkingRules.arrival_chance(level),
			ParkingRules.rival_focus_chance(level),
			ParkingRules.active_driver_limit(level),
		]
	print(rows.strip_edges())
	var rising := true
	var capped := true
	for level in range(1, 40):
		if ParkingRules.departure_chance(level + 1) < ParkingRules.departure_chance(level) \
				or ParkingRules.arrival_chance(level + 1) < ParkingRules.arrival_chance(level) \
				or ParkingRules.rival_focus_chance(level + 1) \
						< ParkingRules.rival_focus_chance(level) \
				or ParkingRules.active_driver_limit(level + 1) \
						< ParkingRules.active_driver_limit(level):
			rising = false
		if ParkingRules.departure_chance(level) > ParkingRules.DEPARTURE_CHANCE_MAX \
				or ParkingRules.arrival_chance(level) > ParkingRules.ARRIVAL_CHANCE_MAX \
				or ParkingRules.rival_focus_chance(level) > ParkingRules.RIVAL_FOCUS_MAX \
				or ParkingRules.active_driver_limit(level) > ParkingRules.ACTIVE_DRIVERS_MAX:
			capped = false
	_check(rising, "every event gets likelier with the level, and never less likely")
	_check(capped, "and none of them climbs past its ceiling")
	_check(ParkingRules.departure_chance(1) > 0.0 and ParkingRules.arrival_chance(1) > 0.0,
			"the lot is already alive at level 1")
	_check(ParkingRules.arrival_chance(10) > ParkingRules.arrival_chance(1) * 2.0,
			"a level 10 lot is a different lot, not the same one in a hurry")

	Parkade.current_game_id = &"parking_game"
	_main = (load("res://Scenes/ParkingGame/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(0.5)
	(_main.get_node("VehicleSelect") as VehicleSelect).confirm()
	await _wait(4.0)
	_round = _main.get_node("Round") as ParkingRound
	# Only the forced events, so the test measures what it asked for.
	_round.lot_events_enabled = false
	# ...and an empty lot underfoot: a car sent across it should be held up by
	# the player and by nothing else.
	_round.pedestrians_enabled = false
	_events = _round.get_node("LotEvents") as LotEvents
	_traffic = _round.get_node("Traffic") as TrafficSpawner
	_hold_the_clock()

	print("The lanes this lot has")
	var bays := _round._bays()
	var lot := LotGeometry.new(bays, _round._entrance())
	var lanes_clear := true
	var lanes_face_the_aisle := true
	var gate_is_past_the_row := true
	var row := lot.row_axis()
	var gate_along := lot.gate_point(bays[0]).dot(row) * signf(lot.gate_direction().dot(row))
	for bay in bays:
		var lane := lot.lane_point(bay)
		for other in bays:
			# Half a bay is 3.24 m of paint: a lane running closer than that to
			# the middle of any bay is a lane running over a parked car.
			if Vector2(lane.x - other.bay_centre().x, lane.z - other.bay_centre().z).length() \
					< 3.3:
				lanes_clear = false
		if (lane - bay.bay_centre()).length() < LotGeometry.LANE_OFFSET - 0.01:
			lanes_face_the_aisle = false
		# Measured along the way out of the lot, so "past" is the same word for
		# either end of the row: the gate is further out than every bay, by the
		# margin and no less.
		var bay_along := bay.bay_centre().dot(row) * signf(lot.gate_direction().dot(row))
		if gate_along < bay_along + LotGeometry.GATE_MARGIN - 0.01:
			gate_is_past_the_row = false
	_check(lanes_clear, "no lane runs over a bay")
	_check(lanes_face_the_aisle, "every lane is a bay's length out into the aisle")
	_check(gate_is_past_the_row, "the gate is past the last bay in the row")
	var rows_face_each_other := false
	for bay in bays:
		if lot.aisle_axis(bay).dot(lot.aisle_axis(bays[0])) < 0.0:
			rows_face_each_other = true
	_check(rows_face_each_other, "the two rows face each other across the aisle")
	_check(lot.gate_direction().dot(_round._entrance() - bays[0].bay_centre()) > 0.0,
			"the gate is at the end of the lot the player comes in from")

	print("A car leaving")
	var parked_before := _traffic.parked_cars().size()
	_events.car_leaving.connect(_on_car_leaving)
	_check(_events.start_departure(), "a parked car can be sent home")
	_check(_left_from != null and _left_from.has_parked_car(),
			"it is still in its bay when it sets off")
	var leaving := _events.drivers[0] if not _events.drivers.is_empty() else null
	_check(leaving != null and leaving.intent == NpcDriver.Intent.LEAVING,
			"and a driver has it")
	_check(_traffic.parked_cars().size() == parked_before - 1,
			"the lot stops counting it as furniture")
	_check(await _until(_bay_is_empty), "the space it was in opens up")
	_check(await _until(_nothing_is_driving), "and the car is off the lot")
	_check(_npc_cars().size() == parked_before - 1, "with nothing left behind")

	print("A rival arriving")
	_hold_the_clock()
	_events.rival_arriving.connect(_on_rival_arriving)
	_events.rival_parked.connect(_on_rival_parked)
	var parked_now := _traffic.parked_cars().size()
	_check(_events.start_arrival(), "a rival can be sent for a space")
	_check(_wanted != null and not _wanted.has_parked_car(), "it goes for an empty one")
	var rival: PlayerCar = _events.drivers[0].car if not _events.drivers.is_empty() else null
	_check(rival != null and not rival.is_in_group(PlayerCar.GROUP),
			"a rival is not the player, whatever scene it is")
	_check(rival != null and rival.is_in_group(Obstacle.GROUP),
			"and hitting one is still hitting a car")
	_check(await _until(_a_rival_has_parked), "it parks")
	_check(_took == _wanted, "in the space it went for")
	_check(_traffic.parked_cars().size() == parked_now + 1,
			"and the lot counts it as furniture from then on")
	if rival != null and is_instance_valid(rival) and _took != null:
		_check(rival.freeze, "a rival that has parked stops simulating, like any parked car")
		_check(_took.parking_angle(rival) < 6.0,
				"a rival parks square: %.1f degrees off" % _took.parking_angle(rival))
		_check(_took.centre_distance(rival) < 0.7,
				"and between the lines: %.2f m off centre" % _took.centre_distance(rival))

	print("Two rivals at once")
	_hold_the_clock()
	# Level 3 is where the lot is first allowed a second car under its own power,
	# and is still not allowed a third.
	var busy := 3
	_events.begin(_round._bays(), busy, _round.car, _round._entrance())
	_check(ParkingRules.active_driver_limit(busy) == 2,
			"level %d allows exactly two" % busy)
	var first := _events.start_arrival()
	var second := _events.start_arrival()
	_check(first and second, "a later level has room for two at once")
	_check(_events.drivers.size() == 2, "and both are driving")
	if _events.drivers.size() == 2:
		_check(_events.drivers[0].bay != _events.drivers[1].bay,
				"two rivals never go for the same space")
	_check(not _events.start_arrival(), "but never more at once than the level allows")

	print("Yielding to the player")
	_hold_the_clock()
	await _until(_nothing_is_driving)
	_check(_events.start_departure(), "another car sets off")
	var driver: NpcDriver = _events.drivers[0] if not _events.drivers.is_empty() else null
	var blocked_bay: ScoredParkingSpace = driver.bay if driver != null else null
	if driver != null and blocked_bay != null:
		# Parked across the lane it is about to drive down, which is where a
		# player hunting for a space in a busy lot actually is.
		var block := lot.lane_point(blocked_bay, 7.0)
		_round.car.global_position = Vector3(block.x, _round.car.global_position.y, block.z)
		_round.car.linear_velocity = Vector3.ZERO
		var closest := INF
		var ever_yielded := false
		for i in int(12.0 * 60.0):
			if not is_instance_valid(driver) or driver.phase == NpcDriver.Phase.DONE:
				break
			ever_yielded = ever_yielded or driver.yielding
			var gap := driver.car.global_position.distance_to(_round.car.global_position)
			closest = minf(closest, gap)
			await _tree.physics_frame
		_check(ever_yielded, "a car with nobody in it waits for the car with somebody in it")
		_check(closest > 2.0, "and stops short of it: %.1f m at the closest" % closest)

	print("The round ending, and the next one")
	_hold_the_clock()
	if _events.drivers.is_empty():
		_events.start_arrival()
	await _wait(0.5)
	var moving: NpcDriver = _events.drivers[0] if not _events.drivers.is_empty() else null
	_round.end_round()
	var held := moving.car.global_position if moving != null else Vector3.ZERO
	await _wait(1.0)
	_check(moving == null or moving.car.global_position.distance_to(held) < 0.01,
			"the lot holds still while the score card is up")
	await _wait(ParkingRules.ROUND_OVER_SECONDS + 4.0)
	_check(_events.drivers.is_empty(), "a new round clears whatever was driving itself")
	_check(_npc_cars().size() == _traffic.parked_cars().size(),
			"and leaves no car behind that nothing owns")

	if _failures.is_empty():
		print("PASS")
		_tree.quit(0)
		return
	printerr("%d check(s) failed" % _failures.size())
	_tree.quit(1)
