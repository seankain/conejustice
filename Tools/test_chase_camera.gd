extends SceneTree
## Measures what the chase camera does and does not copy from the car.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless --script Tools/test_chase_camera.gd
## [/codeblock]
##
## The camera used to be a child of the car, so the player's view pitched,
## rolled and shook with the body -- which is nauseating, and is the one thing
## about a chase camera that cannot be judged from a screenshot. This is the
## test that says it is fixed, and stays fixed.
##
## Two harnesses. The first follows a stand-in the test poses by hand, because a
## car cannot be asked to roll 28 degrees on cue and hold it: pitch, roll,
## bounce and heading go in as exact numbers and the camera's answer is measured
## against exact numbers. The second follows a real [PlayerCar] on real
## suspension, driven in a circle, which is where the arm's cast and the
## settling springs are real -- and which would have caught the camera being
## dragged inside the car it is now a sibling of.

const CAMERA_SCENE := "res://Scenes/ParkingGame/ChaseCamera.tscn"
const CHASSIS := "res://Scenes/Vehicles/SuvDrivable.tscn"
const STEP := 1.0 / 60.0

## Radians of roll the camera is allowed. Not a tolerance so much as a
## statement: the rig's basis has no roll term in it, so anything here beyond
## float noise means it grew one.
const MAX_ROLL := 0.001
## Radians the camera's pitch may drift from the pitch the scene authored while
## the car pitches and lands under it. Half a degree.
const MAX_PITCH_DRIFT := 0.0087
## Metres the camera may move when the car does nothing but rotate about its own
## axes.
const MAX_ROTATION_SHIFT := 0.05

## How fast the stand-in is bounced, and how far, standing in for suspension:
## a spring oscillation, not a ramp.
const BOUNCE_HZ := 4.0
const BOUNCE_AMPLITUDE := 0.25
## The fraction of that bounce the camera may pass on. The vertical follow is a
## low-pass filter with a corner an octave and a half below this, so the real
## figure is nearer a tenth; the mark is where "visibly damped" sits.
const MAX_BOUNCE_FRACTION := 0.25

## Where the stand-in is teleported to, to see the camera keep up.
const TELEPORT := Vector3(30.0, 0.0, -20.0)

var _failures: Array[String] = []
var _world: Node3D = null
var _rig: ChaseCamera = null
var _lens: Camera3D = null
var _stand_in: Node3D = null
var _car: PlayerCar = null

## The framing the scene authors, read off the rig before it enters the tree and
## starts writing its own transform every frame.
var _pivot_height: float = 0.0
var _base_pitch: float = 0.0
var _base_distance: float = 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _stand_in_checks()
	await _driving_checks()

	if _failures.is_empty():
		print("PASS")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: ", failure)
	quit(1)


func _check(condition: bool, description: String) -> void:
	print("  %-4s %s" % ["ok" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


func _wait(seconds: float) -> void:
	for i in int(seconds / STEP):
		await physics_frame


## Builds a world with the rig in it, following [param target].
func _build(target: Node3D, with_ground: bool) -> void:
	if _world != null:
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)

	if with_ground:
		var ground := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1000, 2, 1000)
		collision.shape = box
		collision.position = Vector3(0, -1, 0)
		ground.add_child(collision)
		_world.add_child(ground)

	_world.add_child(target)

	var scene := load(CAMERA_SCENE) as PackedScene
	_rig = scene.instantiate() as ChaseCamera
	# Headless has no pointer to capture, and a test has no business taking one.
	_rig.capture_mouse = false
	_pivot_height = _rig.position.y
	_base_pitch = _rig.rotation.x
	_base_distance = _rig.spring_length
	# Beside the target, not under it -- which is the arrangement being tested.
	_world.add_child(_rig)
	_rig.follow(target)
	_lens = _rig.get_children().filter(func(child): return child is Camera3D).front()


## Where the camera sits when it is squarely behind [param target]: the rig's
## authored offset, rebuilt from the outside.
func _resting_lens_position(target: Node3D) -> Vector3:
	var forward := -target.global_basis.z
	var heading := atan2(-forward.x, -forward.z)
	var basis := Basis.from_euler(Vector3(_base_pitch, heading, 0.0))
	var anchor := target.global_position + Vector3.UP * _pivot_height
	return anchor + basis.z * _base_distance


func _rig_heading_error(target: Node3D) -> float:
	var forward := -target.global_basis.z
	var heading := atan2(-forward.x, -forward.z)
	return absf(angle_difference(_rig.global_rotation.y, heading))


func _stand_in_checks() -> void:
	print("A stand-in the test poses by hand")
	_stand_in = Node3D.new()
	_build(_stand_in, false)
	await _wait(0.5)

	var resting := _rig.global_position
	var framing := _lens.global_position.distance_to(_resting_lens_position(_stand_in))
	print("  rest:      camera %.2f m up, %.2f m back, %.3f m from where the scene puts it" % [
		_lens.global_position.y - _stand_in.global_position.y,
		absf(_lens.global_position.z - _stand_in.global_position.z), framing])
	_check(framing < 0.05, "camera rests where the scene's framing puts it")
	_check(_lens.global_position.y > _stand_in.global_position.y + 1.0,
			"camera rests above the car")

	# The point of all of it: the car turns itself over and the camera does not
	# move at all. Not "moves less" -- the pitch and roll are not in the
	# camera's basis to be reduced.
	_stand_in.global_basis = Basis.from_euler(
			Vector3(deg_to_rad(18.0), 0.0, deg_to_rad(-28.0)))
	await _wait(1.0)
	var shift := _rig.global_position.distance_to(resting)
	print("  pitch/roll: car at 18 deg nose-up and 28 deg of roll -> camera roll %.4f deg, " \
			% rad_to_deg(_rig.global_rotation.z)
			+ "pitch off by %.3f deg, moved %.3f m" % [
				rad_to_deg(absf(angle_difference(_rig.global_rotation.x, _base_pitch))), shift])
	_check(absf(_rig.global_rotation.z) < MAX_ROLL, "a rolled car does not roll the camera")
	_check(absf(angle_difference(_rig.global_rotation.x, _base_pitch)) < MAX_PITCH_DRIFT,
			"a pitched car does not pitch the camera")
	_check(_rig_heading_error(_stand_in) < MAX_PITCH_DRIFT,
			"pitch and roll leave the heading alone")
	_check(shift < MAX_ROTATION_SHIFT, "a car rotating about its own axes does not move the camera")

	# Suspension: small, fast, and the one thing a camera must not repeat.
	_stand_in.global_basis = Basis.IDENTITY
	_rig.snap_to_default()
	var elapsed := 0.0
	var lowest := INF
	var highest := -INF
	while elapsed < 2.0:
		await physics_frame
		elapsed += STEP
		_stand_in.position.y = BOUNCE_AMPLITUDE * sin(TAU * BOUNCE_HZ * elapsed)
		# The first quarter second is the filter settling, not the answer.
		if elapsed > 0.25:
			lowest = minf(lowest, _rig.global_position.y)
			highest = maxf(highest, _rig.global_position.y)
	var passed_on := highest - lowest
	var went_in := 2.0 * BOUNCE_AMPLITUDE
	print("  bounce:    car bounced %.2f m at %.0f Hz -> camera moved %.3f m (%.0f%% of it)" % [
		went_in, BOUNCE_HZ, passed_on, 100.0 * passed_on / went_in])
	_check(passed_on < went_in * MAX_BOUNCE_FRACTION, "suspension bounce does not reach the camera")

	# Heading: followed, but not instantly -- a camera that snaps to the car's
	# heading is a camera bolted to the car in every way that matters.
	_stand_in.position.y = 0.0
	_stand_in.global_basis = Basis.IDENTITY
	_rig.snap_to_default()
	await _wait(0.25)
	_stand_in.global_basis = Basis.from_euler(Vector3(0.0, deg_to_rad(90.0), 0.0))
	await _wait(0.1)
	var part_way := rad_to_deg(_rig.global_rotation.y)
	await _wait(2.0)
	var arrived := _rig_heading_error(_stand_in)
	print("  heading:   car turned 90 deg -> camera %.1f deg round after 0.1 s, %.2f deg out after 2 s" % [
		part_way, rad_to_deg(arrived)])
	_check(part_way > 1.0, "the camera does follow the car's heading")
	_check(part_way < 54.0, "the camera trails the heading rather than snapping to it")
	_check(arrived < deg_to_rad(1.0), "the camera ends up behind the car")

	# Being put somewhere, rather than driving there.
	_stand_in.global_position = TELEPORT
	_rig.snap_to_default()
	var after_snap := _rig.global_position.distance_to(
			_stand_in.global_position + Vector3.UP * _pivot_height)
	_check(after_snap < 0.01, "snap_to_default() puts the camera on the car in the same frame")

	_stand_in.global_position = TELEPORT * 2.0
	await _wait(0.1)
	var after_leash := _rig.global_position.distance_to(
			_stand_in.global_position + Vector3.UP * _pivot_height)
	print("  teleport:  %.3f m behind after a snap, %.3f m behind after a %.0f m jump with no snap" % [
		after_snap, after_leash, TELEPORT.length()])
	_check(after_leash < 0.5, "a car that jumps past the leash is caught rather than chased")

	# The end-of-round showpiece.
	var before_spin := _rig.global_rotation.y
	_rig.start_idle_rotation()
	await _wait(1.0)
	var turned := absf(angle_difference(_rig.global_rotation.y, before_spin))
	var orbit := _rig.global_position.distance_to(
			_stand_in.global_position + Vector3.UP * _pivot_height)
	print("  spin:      %.2f rad in a second at %.2f rad/s, %.3f m off the car, roll %.4f deg" % [
		turned, _rig.spin_speed, orbit, rad_to_deg(_rig.global_rotation.z)])
	_check(absf(turned - _rig.spin_speed) < 0.1, "the end-of-round spin turns at spin_speed")
	_check(orbit < 0.05, "the spin circles the car rather than leaving it")
	_check(absf(_rig.global_rotation.z) < MAX_ROLL, "the spin does not roll the camera")
	_rig.snap_to_default()


func _driving_checks() -> void:
	print("A real car on real suspension")
	var scene := load(CHASSIS) as PackedScene
	if scene == null:
		_failures.append("could not load " + CHASSIS)
		return
	_car = scene.instantiate() as PlayerCar
	_car.position = Vector3(0, 0.5, 0)
	_build(_car, true)
	await _wait(1.5)

	# The arm is cast from a pivot inside the car's own cabin shape. While the
	# rig was a child of the car that was somebody else's problem; a sibling has
	# to exclude it, and this is what says it did.
	var reach := _lens.global_position.distance_to(_rig.global_position)
	print("  arm:       camera %.2f m out of a %.2f m arm at rest" % [reach, _rig.spring_length])
	_check(absf(reach - _rig.spring_length) < 0.05,
			"the arm does not pull the camera in on the car it is looking at")

	# Round a corner under power, sampling every frame rather than at the end:
	# the roll that made people ill was in the middle of the turn, not at the
	# end of it.
	Input.action_press(&"drive_forward")
	Input.action_press(&"steer_left")
	var elapsed := 0.0
	var worst_roll := 0.0
	var worst_pitch := 0.0
	var worst_height := 0.0
	var worst_lag := 0.0
	var worst_body_roll := 0.0
	while elapsed < 6.0:
		await physics_frame
		elapsed += STEP
		worst_roll = maxf(worst_roll, absf(_rig.global_rotation.z))
		worst_pitch = maxf(worst_pitch,
				absf(angle_difference(_rig.global_rotation.x, _base_pitch)))
		worst_body_roll = maxf(worst_body_roll, rad_to_deg(_car.global_basis.y.angle_to(Vector3.UP)))
		# Measured flat and vertically apart: how far the camera is trailing is
		# a different question from whether it is riding the springs.
		var pivot := _car.global_position + Vector3.UP * _pivot_height
		worst_height = maxf(worst_height, absf(_rig.global_position.y - pivot.y))
		worst_lag = maxf(worst_lag, Vector2(
				_rig.global_position.x - pivot.x, _rig.global_position.z - pivot.z).length())
	Input.action_release(&"steer_left")
	Input.action_release(&"drive_forward")

	print("  driving:   car leaned %.1f deg -> camera roll %.4f deg, pitch %.3f deg, " \
			% [worst_body_roll, rad_to_deg(worst_roll), rad_to_deg(worst_pitch)]
			+ "%.2f m of height, trailing %.2f m at %.1f m/s" % [
				worst_height, worst_lag, _car.ground_speed()])
	_check(worst_body_roll > 0.5, "the car itself does lean, so there was something to reject")
	_check(worst_roll < MAX_ROLL, "the camera never rolls, whatever the car does")
	_check(worst_pitch < MAX_PITCH_DRIFT, "the camera never pitches, whatever the car does")
	_check(worst_height < 0.5, "the camera rides above the car rather than on its springs")
	_check(worst_lag < 3.0, "the camera stays with the car through a turn under power")
	_check(_rig_heading_error(_car) < deg_to_rad(45.0), "the camera ends the turn behind the car")
