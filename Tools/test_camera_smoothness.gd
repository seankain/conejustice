extends Node
## Measures how steady the car looks on screen while it is being driven.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless Tools/test_camera_smoothness.tscn
## [/codeblock]
##
## A scene rather than a [code]--script[/code] tool, like the round-flow and
## pause tests: it names [ParkingGame], which reaches the [SfxPlayer] and
## [Parkade] autoloads through the round, and a script run with
## [code]--script[/code] never registers those.
##
## [code]Tools/test_chase_camera.gd[/code] asks what the rig copies from the
## car. This asks the question that one cannot: it samples on [signal
## SceneTree.physics_frame], which is the one instant where the car and the
## camera are both exactly on a tick, so a camera that is right on the ticks and
## stepping everywhere between them reads there as perfect. This test samples
## every [i]drawn[/i] frame instead, because a drawn frame is what the player
## sees, and at frame rates that are not the physics rate, because those are the
## ones that catch it.
##
## Two things about how it samples, both of which the measurement is wrong
## without:
##
## - From a node of its own, rather than from [signal SceneTree.process_frame],
##   which is emitted [i]before[/i] the frame's [method Node._process] calls.
##   Measuring there pairs this frame's car with last frame's camera and invents
##   a frame of jitter that nobody can see. [member Node.process_priority] puts
##   the sampler last instead.
## - Through [method Node3D.get_global_transform_interpolated], which is where a
##   body is being [i]drawn[/i]. With the lot drawn between ticks -- see
##   [method ParkingGame.use_physics_interpolation] -- that is not
##   [member Node3D.global_transform], and a test that reads the latter measures
##   a car nobody is looking at.
##
## What it measures is the second difference of the car's position on screen --
## [code]p[i] - (p[i-1] + p[i+1]) / 2[/code] -- which is zero for anything moving
## at a steady rate across the screen, whatever that rate is, and rings at every
## discontinuity. A car followed smoothly holds still in frame and scores near
## zero however fast it is driven. A car whose position is resampled at one rate
## and drawn at another scores the size of the step.
##
## The same number is taken for a fixed point in the world, so the two failures
## are told apart: a car that jitters against a steady world is the follow, and a
## world that jitters around a steady car is the camera.

const CAMERA_SCENE := "res://Scenes/ParkingGame/ChaseCamera.tscn"
const CHASSIS := "res://Scenes/Vehicles/SuvDrivable.tscn"

## Frame rates to drive at. 60 is the browser on an ordinary display and is the
## rate the physics runs at too, which is the case that looks right at a tick
## boundary because it never falls between two; 90 and 144 are the displays this
## is drawn on the rest of the time. A camera that is steady only when those two
## numbers match is a camera that is steady on one machine.
const FRAME_RATES: Array[int] = [60, 90, 144]

## Seconds of driving before sampling starts: the car reaching speed, the
## springs settling and the camera's own easing reaching its steady lag.
const SETTLE := 4.0
## Seconds sampled.
const MEASURE := 3.0

## The screen the pixel figures are quoted for. Fixed here rather than read from
## the viewport so the numbers mean the same thing on every machine.
const SCREEN_HEIGHT := 648.0

## Pixels of frame-to-frame wobble allowed, peak. Measured before this was
## fixed: 2.1 px at 90 and at 144, on every single frame, which is the car
## buzzing and smearing that the fix is about. A third of a pixel is below what
## a rendered edge can show.
const MAX_JITTER_PX := 0.35

## Metres the car may be away from the respawn marker on the first frame drawn
## after it is put there. A car that is interpolated across a teleport is drawn
## somewhere on the way, which for a lot this size is metres.
const MAX_TELEPORT_SMEAR := 0.05

## Metres a wheel may sit away from where the car it belongs to says it is. The
## wheel visuals are written every drawn frame from wheels the physics moves on
## the tick, so if interpolation reached the body and the wheels differently
## they would come apart by a tick of travel -- 0.2 m at speed.
const MAX_WHEEL_DRIFT := 0.02

var _failures: Array[String] = []
var _tree: SceneTree = null
var _world: Node3D = null
var _rig: ChaseCamera = null
var _lens: Camera3D = null
var _car: PlayerCar = null
var _sampler: FrameSampler = null


## Records where the car and a fixed point in the world land on screen, once per
## drawn frame, after everything else in the frame has moved.
class FrameSampler:
	extends Node

	var lens: Camera3D = null
	var car: Node3D = null
	var marker := Vector3.ZERO
	## Off through a turn: a fixed point swept across a 65 degree lens is not a
	## steadiness reference, because tan() curves and the frame it is measured
	## against is rotating. The car is the question there.
	var sample_world: bool = true
	var recording: bool = false
	var car_screen: Array[Vector2] = []
	var world_screen: Array[Vector2] = []

	func _init() -> void:
		# After the rig, whatever order the two were added to the tree in.
		process_priority = 1000

	func _process(_delta: float) -> void:
		if not recording or lens == null or not is_instance_valid(car):
			return
		car_screen.append(_to_screen(car.get_global_transform_interpolated().origin))
		if sample_world:
			world_screen.append(_to_screen(marker))

	## Where [param point] lands on screen, in pixels from the middle. Computed
	## here rather than taken from [method Camera3D.unproject_position] so the
	## figure is against [constant SCREEN_HEIGHT] whatever window the test is
	## given, and so it is defined with no rendering server in the room.
	func _to_screen(point: Vector3) -> Vector2:
		var local := lens.get_global_transform_interpolated().affine_inverse() * point
		if local.z > -0.05:
			return Vector2.ZERO
		var focal := (SCREEN_HEIGHT * 0.5) / tan(deg_to_rad(lens.fov) * 0.5)
		return Vector2(local.x, local.y) * focal / -local.z


func _ready() -> void:
	_tree = get_tree()
	_run()


func _run() -> void:
	for fps in FRAME_RATES:
		await _drive_at(fps, false)
	await _drive_at(144, true)
	await _teleport_check()

	if _failures.is_empty():
		print("PASS")
		_tree.quit(0)
		return
	for failure in _failures:
		printerr("FAIL: ", failure)
	_tree.quit(1)


func _check(condition: bool, description: String) -> void:
	print("  %-4s %s" % ["ok" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _build() -> void:
	if _world != null:
		_world.free()
	# The same call the cabinet makes before it builds its lot. Without it this
	# measures a lot drawn on the tick, which is not the lot the game ships.
	ParkingGame.use_physics_interpolation(_tree)
	_world = Node3D.new()
	add_child(_world)

	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000, 2, 2000)
	collision.shape = box
	collision.position = Vector3(0, -1, 0)
	ground.add_child(collision)
	_world.add_child(ground)

	_car = (load(CHASSIS) as PackedScene).instantiate() as PlayerCar
	_car.position = Vector3(0, 0.5, 0)
	_world.add_child(_car)

	_rig = (load(CAMERA_SCENE) as PackedScene).instantiate() as ChaseCamera
	# Headless has no pointer to capture, and a test has no business taking one.
	_rig.capture_mouse = false
	_world.add_child(_rig)
	_rig.follow(_car)
	_lens = _rig.get_children().filter(func(child): return child is Camera3D).front()

	_sampler = FrameSampler.new()
	_sampler.lens = _lens
	_sampler.car = _car
	_world.add_child(_sampler)


func _wait(seconds: float) -> void:
	for i in int(seconds * 60.0):
		await _tree.physics_frame


## Peak and RMS of the second difference of [param series], which is how far
## each sample sits from the straight line between the samples either side of
## it: zero for a steady sweep across the screen, the size of the step for a
## staircase.
func _jitter(series: Array[Vector2]) -> Vector2:
	var peak := 0.0
	var sum_squares := 0.0
	var count := 0
	for i in range(1, series.size() - 1):
		var residual := (series[i] - (series[i - 1] + series[i + 1]) * 0.5).length()
		peak = maxf(peak, residual)
		sum_squares += residual * residual
		count += 1
	if count == 0:
		return Vector2.ZERO
	return Vector2(peak, sqrt(sum_squares / count))


## How far the front left wheel is drawn from where the car says it is.
func _wheel_drift() -> float:
	var wheel := _car.visuals.get_node_or_null(^"WheelFrontLeft") as Node3D
	if wheel == null:
		return 0.0
	var drawn: Vector3 = wheel.get_global_transform_interpolated().origin
	var expected: Vector3 = _car.get_global_transform_interpolated() * wheel.position
	return drawn.distance_to(expected)


func _drive_at(fps: int, turning: bool) -> void:
	print("Driving %s at %d frames a second, physics at 60" % [
		"round a corner" if turning else "in a straight line", fps])
	Engine.max_fps = fps
	_build()

	Input.action_press(&"drive_forward")
	if turning:
		Input.action_press(&"steer_left")
	await _wait(SETTLE)

	# A post in the ground, far enough ahead to stay in frame for the whole
	# sample: the world's own answer to the same question.
	_sampler.marker = _car.global_position + (-_car.global_basis.z) * 40.0
	_sampler.sample_world = not turning
	_sampler.recording = true
	var ticks_at_start := Engine.get_physics_frames()
	var started := Time.get_ticks_usec()
	var worst_wheel := 0.0
	while Time.get_ticks_usec() - started < int(MEASURE * 1_000_000.0):
		await _tree.process_frame
		worst_wheel = maxf(worst_wheel, _wheel_drift())
	var elapsed := (Time.get_ticks_usec() - started) / 1_000_000.0
	var ticks := Engine.get_physics_frames() - ticks_at_start
	_sampler.recording = false
	Input.action_release(&"drive_forward")
	if turning:
		Input.action_release(&"steer_left")

	var car := _jitter(_sampler.car_screen)
	var world := _jitter(_sampler.world_screen)
	print("  rate:      %d drawn frames and %d physics ticks in %.2f s (%.0f fps, %.0f Hz)" % [
		_sampler.car_screen.size(), ticks, elapsed,
		_sampler.car_screen.size() / elapsed, ticks / elapsed])
	print("  speed:     %.1f m/s, camera %.2f m back" % [
		_car.ground_speed(), _lens.global_position.distance_to(_car.global_position)])
	print("  car:       %.3f px peak, %.3f px rms of frame-to-frame wobble" % [car.x, car.y])
	if turning:
		print("  world:     not measured through a turn")
	else:
		print("  world:     %.3f px peak, %.3f px rms" % [world.x, world.y])
	print("  wheels:    drawn %.4f m from where the car is drawn" % worst_wheel)
	_check(_sampler.car_screen.size() > int(MEASURE * fps * 0.5),
			"the test drew frames at the rate it asked for")
	_check(_rig.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,
			"the rig draws itself rather than being interpolated")
	var what := "round a corner" if turning else "in a straight line"
	_check(car.x < MAX_JITTER_PX, "the car is steady in frame %s at %d fps" % [what, fps])
	if not turning:
		_check(world.x < MAX_JITTER_PX, "the world is steady behind it at %d fps" % fps)
	_check(worst_wheel < MAX_WHEEL_DRIFT, "the wheels are drawn on the car they belong to")


## A car that is put somewhere is drawn there, not on the way there.
func _teleport_check() -> void:
	print("A car put back on its marker rather than driven there")
	Engine.max_fps = 144
	_build()
	var marker := Marker3D.new()
	marker.add_to_group(PlayerCar.RESPAWN_GROUP)
	marker.position = Vector3(60.0, 0.5, -40.0)
	_world.add_child(marker)

	Input.action_press(&"drive_forward")
	await _wait(2.0)
	Input.action_release(&"drive_forward")
	var from := _car.global_position

	_car.respawn()
	await _tree.process_frame
	var drawn: Vector3 = _car.get_global_transform_interpolated().origin
	var smear := drawn.distance_to(marker.global_position)
	print("  respawn:   car moved %.1f m, drawn %.3f m from the marker on the next frame" % [
		from.distance_to(marker.global_position), smear])
	_check(smear < MAX_TELEPORT_SMEAR, "a respawned car is drawn on its marker, not on the way to it")
