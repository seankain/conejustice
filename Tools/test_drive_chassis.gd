extends SceneTree
## Drives a chassis on a flat plane and reports whether it behaves like a car.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless --script Tools/test_drive_chassis.gd
## godot --headless --script Tools/test_drive_chassis.gd -- res://Scenes/Vehicles/MinivanDrivable.tscn
## [/codeblock]
##
## It exists because vehicle tuning is otherwise done by feel, one number at a
## time, with no way to tell a change from a placebo -- and because the numbers
## that matter are not the ones in the inspector. Godot applies
## [member VehicleBody3D.engine_force] at [i]every[/i] wheel marked
## [member VehicleWheel3D.use_as_traction], and its vehicle has no drag to speak
## of, so "engine power" on its own says nothing about how the car actually
## pulls away. This measures the things a player feels instead: how long to
## 10 m/s, how long to stop, how far over it leans in a turn, and whether it is
## sitting at the height its own wheels say it should be.
##
## The pass marks are deliberately loose. This is a check for a chassis that is
## broken -- bottomed suspension, no traction, a car that rolls onto its roof in
## a normal turn -- not a lap time.

## Chassis used when none is named on the command line.
const DEFAULT_CHASSIS := "res://Scenes/Vehicles/SuvDrivable.tscn"

## Seconds of simulation allowed for each measured manoeuvre.
const MANOEUVRE_TIMEOUT := 12.0
const STEP := 1.0 / 60.0

## A car that leans past this in a flat turn is on its way onto its roof.
const MAX_SAFE_TILT_DEGREES := 25.0
## The body should rest within this of where its own wheels put it. Much lower
## and the suspension is bottomed out, which reads as the car being sunk into
## the road and drives like it too.
const MAX_REST_SAG := 0.12
## Metres a car at full lock must have moved towards the side it is steering,
## measured over the first stretch of the turn. Loose on purpose: this asks
## which way the car went, not how tight its circle is.
const MIN_TURN_OFFSET := 0.5
## How far the engine force under boost may sit from the force under the drive
## key, as a fraction of the car's own engine power. Boost is the same throttle
## asked for a different way, so the honest allowance is small: the two samples
## are taken a few frames apart and the car has moved on a little between them,
## which [method PlayerCar._power_fade] turns into a few newtons.
const MAX_THROTTLE_DIFFERENCE := 0.03
## Metres a car may travel with the e-brake held and the throttle on the floor.
## Not zero: the wheels are braked, not welded, and the first frames of it are
## the car already moving.
const MAX_HANDBRAKE_CREEP := 0.5

var _car: PlayerCar
var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var path := DEFAULT_CHASSIS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		path = args[0]

	var scene := load(path) as PackedScene
	if scene == null:
		printerr("test_drive_chassis: could not load ", path)
		quit(1)
		return

	print("Chassis: ", path)
	_build_world(scene)
	await _wait(2.0)
	_report_rest()
	await _measure_acceleration()
	await _measure_braking()
	await _measure_boost()
	await _measure_handbrake()
	await _measure_turn()
	await _measure_respawn()

	if _failures.is_empty():
		print("PASS")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _build_world(scene: PackedScene) -> void:
	var world := Node3D.new()
	root.add_child(world)

	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 2, 1000)
	collision.shape = box
	collision.position = Vector3(0, -1, 0)
	ground.add_child(collision)
	world.add_child(ground)

	var respawn := Node3D.new()
	respawn.position = Vector3(50, 0.5, 50)
	respawn.add_to_group(PlayerCar.RESPAWN_GROUP)
	world.add_child(respawn)

	_car = scene.instantiate()
	_car.position = Vector3(0, 0.5, 0)
	world.add_child(_car)


func _wait(seconds: float) -> void:
	for i in int(seconds / STEP):
		await physics_frame


func _tilt_degrees() -> float:
	return rad_to_deg(_car.global_basis.y.angle_to(Vector3.UP))


func _report_rest() -> void:
	var wheel: VehicleWheel3D = null
	for child in _car.get_children():
		if child is VehicleWheel3D:
			wheel = child
			break
	# Where the body sits relative to where the wheels hold it: the wheel centre
	# should be one radius off the ground, and the body at the height its scene
	# was authored at.
	var sag := -_car.global_position.y
	print("rest:         body y %+.3f m, tilt %.1f deg, wheel centre %.3f m, radius %.3f m" % [
		_car.global_position.y, _tilt_degrees(),
		_car.global_position.y + wheel.position.y, wheel.wheel_radius])
	if sag > MAX_REST_SAG:
		_failures.append("body rests %.3f m below its authored height -- suspension too soft" % sag)
	if _tilt_degrees() > 5.0:
		_failures.append("body rests tilted %.1f degrees on flat ground" % _tilt_degrees())


func _measure_acceleration() -> void:
	if await _pull_away_on(&"drive_forward", "acceleration") < 0.0:
		_failures.append("never reached 10 m/s under full throttle")


## Holds [param action] for the length of a manoeuvre and reports how long the
## car took to reach 10 m/s, or -1.0 if it never did. Takes the action rather
## than naming the drive key, so the same pull-away can be asked for on boost.
func _pull_away_on(action: StringName, label: String) -> float:
	Input.action_press(action)
	var elapsed := 0.0
	var to_ten := -1.0
	while elapsed < MANOEUVRE_TIMEOUT:
		await physics_frame
		elapsed += STEP
		if to_ten < 0.0 and _car.speed() >= 10.0:
			to_ten = elapsed
	print("%-13s %.2f m/s after %.0f s, 0-10 m/s in %s" % [
		label + ":", _car.speed(), MANOEUVRE_TIMEOUT,
		"never" if to_ten < 0.0 else "%.2f s" % to_ten])
	Input.action_release(action)
	return to_ten


func _measure_braking() -> void:
	var from := _car.speed()
	Input.action_press(&"drive_back")
	var elapsed := 0.0
	var stopped := -1.0
	while elapsed < MANOEUVRE_TIMEOUT:
		await physics_frame
		elapsed += STEP
		if _car.speed() <= 0.2:
			stopped = elapsed
			break
	print("braking:      %.2f m/s to a stop in %s" % [
		from, "never" if stopped < 0.0 else "%.2f s" % stopped])
	if stopped < 0.0:
		_failures.append("pressing back at %.1f m/s did not stop the car" % from)
	Input.action_release(&"drive_back")


## Boost is the gas pedal on the floor and nothing else, so what is measured is
## that it asks the engine for exactly what the drive key asks it for -- at a
## standstill, where the throttle is worth all of it, and at speed, where
## [method PlayerCar._power_fade] has taken some of it back.
##
## The force, not the stopwatch: two pull-aways from what looks like the same
## standstill are not the same run. The first one the car does after it has
## dropped onto its suspension is half a second slower to 10 m/s than the ones
## after it, on the two chassis that come to rest with a degree of tilt in them,
## which says something about the suspension and nothing at all about boost.
##
## The car is left where the braking measurement left it, which is stopped.
func _measure_boost() -> void:
	var at_rest_key := await _throttle_force(&"drive_forward")
	var at_rest_boost := await _throttle_force(&"boost")
	_compare_throttle("at a stop", at_rest_key, at_rest_boost)

	if await _pull_away_on(&"boost", "boost") < 0.0:
		_failures.append("never reached 10 m/s on boost")
		return

	# Sampled while the car is still rolling at the speed the run left it at, so
	# both readings are taken against the same power fade.
	var at_speed_key := await _throttle_force(&"drive_forward")
	var at_speed_boost := await _throttle_force(&"boost")
	_compare_throttle("at speed", at_speed_key, at_speed_boost)

	# And the rule boost does not get out of: a throttle pushed against the way
	# the car is moving brakes instead of driving.
	Input.action_press(&"drive_back")
	var reversing := await _wait_until(func() -> bool: return _car.speed() <= -2.0)
	Input.action_release(&"drive_back")
	if not reversing:
		_failures.append("the car never reversed, so boost against it went unmeasured")
		return
	Input.action_press(&"boost")
	await physics_frame
	await physics_frame
	print("boost back:   %.2f m/s, engine force %.0f N, brake %.0f" % [
		_car.speed(), _car.engine_force, _car.brake])
	if not is_zero_approx(_car.engine_force) or _car.brake < _car.brake_strength:
		_failures.append("boost against the way the car was moving drove instead of braking")
	# Held until the car has stopped, which is that brake doing the stopping.
	if not await _wait_until(func() -> bool: return _car.speed() >= -0.2):
		_failures.append("boost held against a reversing car never brought it to a stop")
	Input.action_release(&"boost")


## Engine force one throttle input produces, in newtons. Two frames rather than
## one: [signal SceneTree.physics_frame] fires before the nodes step, so the
## first one still reports the force from before the press.
func _throttle_force(action: StringName) -> float:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	var force := _car.engine_force
	Input.action_release(action)
	await physics_frame
	return force


func _compare_throttle(where: String, on_key: float, on_boost: float) -> void:
	var allowed := _car.engine_power * MAX_THROTTLE_DIFFERENCE
	print("throttle:     %-11s key %.0f N, boost %.0f N, %+.0f N" % [
		where + ",", on_key, on_boost, on_boost - on_key])
	if absf(on_boost - on_key) > allowed:
		_failures.append("boost asked for %.0f N %s where the drive key asks for %.0f N"
				% [on_boost, where, on_key])


## Runs the simulation until [param predicate] is true, and reports whether it
## became true before the manoeuvre timed out. A car that never does what it is
## being asked to do fails the test rather than hanging it.
func _wait_until(predicate: Callable) -> bool:
	var elapsed := 0.0
	while elapsed < MANOEUVRE_TIMEOUT:
		await physics_frame
		elapsed += STEP
		if predicate.call():
			return true
	return false


## The e-brake: how hard it stops the car, and that it outranks the throttle.
## Measured against the service brake the car already has -- pressing back --
## because the one thing an e-brake has to be is the strongest pedal on the car.
func _measure_handbrake() -> void:
	Input.action_press(&"drive_forward")
	await _wait(4.0)
	Input.action_release(&"drive_forward")

	var from := _car.speed()
	var start := _car.global_position
	Input.action_press(&"handbrake")
	var elapsed := 0.0
	var stopped := -1.0
	while elapsed < MANOEUVRE_TIMEOUT:
		await physics_frame
		elapsed += STEP
		if _car.speed() <= 0.2:
			stopped = elapsed
			break
	var travelled := Vector2(
			_car.global_position.x - start.x, _car.global_position.z - start.z).length()
	print("e-brake:      %.2f m/s to a stop in %s, %.2f m" % [
		from, "never" if stopped < 0.0 else "%.2f s" % stopped, travelled])
	if stopped < 0.0:
		_failures.append("the e-brake at %.1f m/s did not stop the car" % from)

	# Still held, now with the throttle on the floor and boost with it: the
	# e-brake is the one input that beats the gas pedal.
	var held_from := _car.global_position
	Input.action_press(&"drive_forward")
	Input.action_press(&"boost")
	await _wait(2.0)
	var crept := Vector2(
			_car.global_position.x - held_from.x, _car.global_position.z - held_from.z).length()
	print("e-brake held: %.2f m in 2 s with the throttle down and boost on" % crept)
	if crept > MAX_HANDBRAKE_CREEP:
		_failures.append("the car drove %.2f m against a held e-brake" % crept)
	Input.action_release(&"boost")
	Input.action_release(&"drive_forward")
	Input.action_release(&"handbrake")


func _measure_turn() -> void:
	Input.action_press(&"drive_forward")
	await _wait(4.0)
	var from := _car.global_position
	# The driver's right, in the frame the car starts the turn in: forward
	# crossed with up. Which way the car actually went is the one thing about
	# the steering that cannot be reasoned out from the sign of a constant --
	# the engine drives this chassis backwards and steers it around the wheels
	# at its nose, and those two cancel. It was shipped turning the wrong way
	# because that was worked out on paper rather than measured.
	var forward := -_car.global_basis.z
	var right := Vector3(-forward.z, 0.0, forward.x).normalized()
	Input.action_press(&"steer_left")
	var worst := 0.0
	var elapsed := 0.0
	var lateral := 0.0
	while elapsed < 8.0:
		await physics_frame
		elapsed += STEP
		worst = maxf(worst, _tilt_degrees())
		# Sampled early, before a car at full lock has come far enough round to
		# be heading back the way it came.
		if elapsed < 1.2:
			lateral = (_car.global_position - from).dot(right)
	print("hard turn:    %.2f m/s, worst lean %.1f deg, went %.2f m to the %s" % [
		_car.speed(), worst, absf(lateral), "right" if lateral > 0.0 else "left"])
	if worst > MAX_SAFE_TILT_DEGREES:
		_failures.append("leaned %.1f degrees in a turn" % worst)
	if lateral > -MIN_TURN_OFFSET:
		_failures.append("steering left went %.2f m to the driver's right" % lateral)
	Input.action_release(&"steer_left")
	Input.action_release(&"drive_forward")


func _measure_respawn() -> void:
	_car.respawn()
	var carried := _car.linear_velocity.length()
	# Settling is expected: the marker is above the road, so the car drops onto
	# its suspension. What must not survive the respawn is the velocity it had,
	# and where it ends up is measured flat -- a car that landed is not a car
	# that missed.
	await _wait(1.5)
	var markers := get_nodes_in_group(PlayerCar.RESPAWN_GROUP)
	var marker := markers[0] as Node3D
	var offset := Vector2(
			_car.global_position.x - marker.global_position.x,
			_car.global_position.z - marker.global_position.z).length()
	var drift := Vector2(_car.linear_velocity.x, _car.linear_velocity.z).length()
	print("respawn:      carried %.2f m/s over, landed %.2f m from the marker, drifting %.2f m/s" % [
		carried, offset, drift])
	if carried > 0.01:
		_failures.append("respawn kept %.2f m/s of the velocity it had" % carried)
	if offset > 1.0:
		_failures.append("respawned %.2f m from the marker" % offset)
	if drift > 0.5:
		_failures.append("respawned drifting at %.2f m/s" % drift)
