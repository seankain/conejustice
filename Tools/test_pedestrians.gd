extends Node
## The lot with people and geese in it: where a crossing runs, what it costs to
## hit one, and that hitting it costs exactly once.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless Tools/test_pedestrians.tscn
## [/codeblock]
##
## A scene rather than a [code]--script[/code] tool, like the round-flow and
## lot-events tests and for the same reason: [ParkingRound] names the
## [SfxPlayer] autoload, and a script run with [code]--script[/code] never
## registers autoloads.
##
## Crossings are forced rather than waited for, exactly as the lot's other two
## dice are: [method PedestrianSpawner.send_walker] and
## [method PedestrianSpawner.send_gaggle] are public, the odds are checked as a
## table, and what those two do is checked by calling them.

## Seconds a body is given to fall over before the test calls it upright.
const PATIENCE := 4.0

var _failures: Array[String] = []
var _tree: SceneTree = null
var _main: Node3D = null
var _round: ParkingRound = null
var _pedestrians: PedestrianSpawner = null


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


## How far from upright [param body] gets over the next [param seconds]: 1.0 is
## still on its feet and 0.0 is flat on the tarmac. Watched rather than sampled
## once, because a body that is still tumbling is upright again every turn.
func _flattest(body: Node3D, seconds: float) -> float:
	var lowest := 1.0
	for i in int(seconds * 60.0):
		if not is_instance_valid(body):
			return lowest
		lowest = minf(lowest, body.global_basis.y.dot(Vector3.UP))
		await _tree.physics_frame
	return lowest


## Keeps the round from ending underneath the test.
func _hold_the_clock() -> void:
	_round.seconds_remaining = 600.0


func _living() -> Array:
	return _tree.get_nodes_in_group(Pedestrian.GROUP)


## Metres between two points on the ground, which is the only distance this test
## ever wants.
static func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


## Drives the player's car into [param target] and waits for the two to meet.
##
## Put down [param behind] the target and steered every frame rather than aimed
## once, because the thing it is aiming at is walking away from it. The caller
## passes the aisle's own direction, so the run-up happens down the lane and the
## car is never dropped into a bay it might settle in and end the round from.
func _run_over(target: Pedestrian, behind: Vector3) -> void:
	var car := _round.car
	var start := target.global_position + behind * 4.0
	start.y = car.global_position.y
	car.global_transform = Transform3D(Basis.looking_at(-behind, Vector3.UP), start)
	car.angular_velocity = Vector3.ZERO
	car.linear_velocity = Vector3.ZERO
	for i in int(2.0 * 60.0):
		if not is_instance_valid(target) or target.state == Pedestrian.State.DOWN:
			return
		var towards := LotGeometry.flat(target.global_position - car.global_position)
		if towards == Vector3.ZERO:
			towards = Vector3.FORWARD
		car.linear_velocity = towards * 8.0
		await _tree.physics_frame
	# Stopped where it ended up. A car left at eight metres a second carries on
	# through whatever else is on the lot while the test is measuring what it
	# already hit.
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO


func _run() -> void:
	print("How many, and how likely")
	var rising := true
	var capped := true
	for level in range(1, 25):
		if ParkingRules.walkers_for_level(level + 1) < ParkingRules.walkers_for_level(level) \
				or ParkingRules.walker_chance(level + 1) < ParkingRules.walker_chance(level):
			rising = false
		if ParkingRules.walkers_for_level(level) > ParkingRules.WALKERS_MAX \
				or ParkingRules.walker_chance(level) > ParkingRules.WALKER_CHANCE_MAX:
			capped = false
	_check(ParkingRules.walkers_for_level(1) > 0,
			"every level has somebody on it, starting with the first")
	_check(rising, "a later lot has more of them, and never fewer")
	_check(capped, "and neither the count nor the odds climb past their ceiling")
	_check(ParkingRules.walkers_for_level(20) == ParkingRules.WALKERS_MAX,
			"a late lot is at the ceiling rather than unbounded")

	Parkade.current_game_id = &"parking_game"
	_main = (load("res://Scenes/ParkingGame/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	await _wait(0.5)
	(_main.get_node("VehicleSelect") as VehicleSelect).confirm()
	await _wait(4.0)
	_round = _main.get_node("Round") as ParkingRound
	# Only the forced crossings, and a lot that is otherwise holding still: a
	# rival driving through the middle of this would knock over the thing the
	# test is about to.
	_round.lot_events_enabled = false
	_pedestrians = _round.get_node("Pedestrians") as PedestrianSpawner
	_hold_the_clock()
	await _wait(1.0)

	print("The lot at level 1")
	var bays := _round._bays()
	var lot := LotGeometry.new(bays, _round._entrance())
	_check(_pedestrians != null, "a round builds a pedestrian spawner")
	_check(_pedestrians.walking() >= ParkingRules.walkers_for_level(1),
			"and the lot already has people on it: %d" % _pedestrians.walking())
	_check(_pedestrians.walking() <= ParkingRules.WALKERS_MAX,
			"but never more than the lot allows")
	_check(_living().size() == _pedestrians.living().size(),
			"everything living is in the '%s' group" % Pedestrian.GROUP)

	print("Where a crossing runs")
	# A gaggle goes from clear of one row's paint to clear of the other's, so
	# the line it walks has to have both driving lanes on it and neither row's
	# paint.
	var crosses_both_lanes := true
	var stops_short_of_the_paint := true
	var facing_pairs := 0
	for bay in bays:
		var out := lot.aisle_axis(bay)
		var from := (lot.clearance_point(bay) - bay.bay_centre()).dot(out)
		var to := (lot.across_point(bay) - bay.bay_centre()).dot(out)
		# This bay's own lane, and the lane of the row facing it.
		for other in bays:
			var along := (lot.lane_point(other) - bay.bay_centre()).dot(out)
			var sideways := (lot.lane_point(other) - bay.bay_centre()) - out * along
			if Vector2(sideways.x, sideways.z).length() > 1.0:
				continue
			if along <= from or along >= to:
				crosses_both_lanes = false
			var paint := (other.bay_centre() - bay.bay_centre()).dot(out)
			if paint <= 0.1:
				continue
			facing_pairs += 1
			if to >= paint:
				stops_short_of_the_paint = false
	_check(facing_pairs > 0, "the lot has a row facing a row: %d pairs" % facing_pairs)
	_check(crosses_both_lanes, "a crossing has both driving lanes on it")
	_check(stops_short_of_the_paint, "and ends before the paint on the far side")

	print("Somebody gets out of a car")
	var walker := _pedestrians.send_walker()
	_check(walker != null, "a person can be sent across the lot")
	if walker == null:
		_finish()
		return
	await _wait(0.6)
	var nearest: ScoredParkingSpace = null
	var nearest_distance := INF
	for bay in bays:
		var distance := bay.centre_distance(walker)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = bay
	var side := (walker.global_position - nearest.bay_centre()).dot(lot.aisle_axis(nearest))
	_check(side > 0.0, "on the aisle side of the bay, whichever row it is in")
	_check(nearest_distance > 3.24,
			"and clear of the paint rather than standing in the bay: %.1f m" % nearest_distance)
	_check(walker.obstacle_kind() == Obstacle.Kind.PERSON, "a person is a person to hit")
	_check(Obstacle.kind_of(walker) == Obstacle.Kind.PERSON, "and says so through the group")
	var was := walker.global_position
	var moved := await _until(func() -> bool:
		return _flat_distance(was, walker.global_position) > 1.0)
	_check(moved, "and walks off towards the building")

	print("A gaggle of geese")
	var before := _pedestrians.living()
	var geese := _pedestrians.send_gaggle(3)
	var gaggle: Array[Pedestrian] = []
	for pedestrian in _pedestrians.living():
		if not before.has(pedestrian):
			gaggle.append(pedestrian)
	_check(geese == 3 and gaggle.size() == 3, "a gaggle crosses together: %d" % geese)
	var all_wildlife := not gaggle.is_empty()
	for goose in gaggle:
		if goose.obstacle_kind() != Obstacle.Kind.WILDLIFE:
			all_wildlife = false
	_check(all_wildlife, "and a goose is wildlife, which the score card counts with people")

	print("Hitting one")
	# A goose rather than the walker: a gaggle crosses the aisle and stays in
	# it, so the car can be run up the lane at one without being put anywhere it
	# could settle and end the round.
	#
	# And on its own: everything else goes first, so every living thing the
	# round tallies from here is this one body and the count is a fact rather
	# than a guess at how many the car went through on the way.
	var victim := gaggle[0]
	for pedestrian in _pedestrians.living():
		if pedestrian != victim and is_instance_valid(pedestrian):
			pedestrian.queue_free()
	await _wait(0.5)
	_hold_the_clock()
	var kind := victim.obstacle_kind()
	var upright_before := victim.global_basis.y.dot(Vector3.UP)
	_round.data = RoundData.new()
	await _run_over(victim, lot.row_axis())
	_hold_the_clock()
	var struck_at := victim.global_position
	var living_hits := _round.data.collisions_of(
			[Obstacle.Kind.PERSON, Obstacle.Kind.WILDLIFE])
	_check(victim.state == Pedestrian.State.DOWN, "a car reaching one puts it down")
	_check(living_hits == 1, "and the round scores it as a living thing: %d" % living_hits)
	_check(_round.data.collisions.has(kind), "of the kind it actually was")
	_check(Obstacle.kind_of(victim) == Obstacle.Kind.NONE,
			"a body on the tarmac is not an obstacle any more")
	_check(upright_before > 0.99, "it was on its feet before")
	_check(not victim.axis_lock_angular_x and not victim.axis_lock_angular_z,
			"the locks that were holding it upright are off")
	var flattest := await _flattest(victim, 6.0)
	_check(flattest < 0.5, "so it goes over: %.2f of upright at its flattest" % flattest)
	var thrown := await _until(func() -> bool:
		return _flat_distance(struck_at, victim.global_position) > 1.0)
	_check(thrown, "and it is thrown rather than driven through")

	print("...and only once")
	await _run_over(victim, lot.row_axis())
	await _wait(0.5)
	_hold_the_clock()
	_check(_round.data.collisions_of(
			[Obstacle.Kind.PERSON, Obstacle.Kind.WILDLIFE]) == living_hits,
			"driving over the same body again costs nothing more")
	_check(_living().has(victim), "but it is still there to be driven around")

	print("What it costs")
	var clean := RoundData.new()
	clean.parked_in_space = true
	var ranked := clean.rank()
	var guilty := RoundData.new()
	guilty.parked_in_space = true
	guilty.collisions.append(Obstacle.Kind.PERSON)
	_check(guilty.rank() == ranked + 1, "a living thing costs a full grade")
	_check(guilty.collisions_of([Obstacle.Kind.PERSON, Obstacle.Kind.WILDLIFE]) == 1,
			"and the score card's living count is the one that carries it")

	print("The next round, and a lot without them")
	_round.end_round()
	await _wait(ParkingRules.ROUND_OVER_SECONDS + 1.5)
	_hold_the_clock()
	_check(not _living().is_empty(), "a new round has its own people on it")
	var stale := false
	for pedestrian in _living():
		if pedestrian.state == Pedestrian.State.DOWN:
			stale = true
	_check(not stale, "and none of the last round's bodies is still lying in it")
	_round.pedestrians_enabled = false
	await _wait(0.5)
	_check(_living().is_empty(), "switching them off empties the lot")
	_check(not _pedestrians.enabled and _pedestrians.send_crossing() == 0,
			"and keeps it empty")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("PASS")
	else:
		print("FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	_tree.quit(0 if _failures.is_empty() else 1)
