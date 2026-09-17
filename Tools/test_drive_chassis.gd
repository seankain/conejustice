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
	Input.action_press(&"drive_forward")
	var elapsed := 0.0
	var to_ten := -1.0
	while elapsed < MANOEUVRE_TIMEOUT:
		await physics_frame
		elapsed += STEP
		if to_ten < 0.0 and _car.speed() >= 10.0:
			to_ten = elapsed
	print("acceleration: %.2f m/s after %.0f s, 0-10 m/s in %s" % [
		_car.speed(), MANOEUVRE_TIMEOUT, "never" if to_ten < 0.0 else "%.2f s" % to_ten])
	if to_ten < 0.0:
		_failures.append("never reached 10 m/s under full throttle")
	Input.action_release(&"drive_forward")


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


func _measure_turn() -> void:
	Input.action_press(&"drive_forward")
	await _wait(4.0)
	Input.action_press(&"steer_left")
	var worst := 0.0
	var elapsed := 0.0
	while elapsed < 8.0:
		await physics_frame
		elapsed += STEP
		worst = maxf(worst, _tilt_degrees())
	print("hard turn:    %.2f m/s, worst lean %.1f deg" % [_car.speed(), worst])
	if worst > MAX_SAFE_TILT_DEGREES:
		_failures.append("leaned %.1f degrees in a turn" % worst)
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
