class_name ChaseCamera
extends SpringArm3D
## The camera behind the car: it follows where the car goes and which way the
## car is pointing, and ignores everything else the car does.
##
## [b]It is not parented to the car, and that is the point.[/b] It used to be,
## which is what this rewrite is about: a camera bolted to a [VehicleBody3D]
## inherits every degree of freedom the suspension has. The body pitches under
## braking, rolls into every turn, shakes on its springs over the paint and
## kicks when a wheel finds a kerb -- and a camera parented to it does all of
## that too, about a pivot a metre and a half in front of the player's eyes.
## That is the motion sickness: the view rolls and the horizon does not stay
## put.
##
## So the rig is a sibling of the car in the lot and follows it, taking only the
## two things a chase camera has any business taking:
##
## - [b]Where the car is[/b], eased -- horizontally at [member follow_response],
##   and vertically at the much slower [member height_response]. A slow vertical
##   follow is a low-pass filter: suspension bounce is small and fast and does
##   not survive it, while a kerb or a ramp is a sustained change of height and
##   comes through.
## - [b]Which way the car is pointing[/b], flattened to a heading and eased at
##   [member yaw_response]. Flattened, so the car's pitch and roll never reach
##   the camera at all -- not damped, not reduced, absent. The rig's basis is
##   built from a yaw and a pitch and nothing else, so it [i]cannot[/i] roll.
##
## The car's speed is allowed to do one thing: ease the camera back and widen
## the lens a little, so 14 m/s feels different from 4. That is framing, not
## rotation, and it is what [member distance_gain] and [member fov_gain] are.
##
## Still a [SpringArm3D], so the camera is pulled in when the lot's geometry
## gets between it and the car rather than clipping through a wall. Being a
## sibling rather than a child means the car has to be excluded from that cast
## by hand -- see [method follow].
##
## [b]The framing is authored in the scene, not here.[/b] The rig's own
## transform and spring length are read once in [method _ready] and then the
## transform is written every frame: [code]position.y[/code] is how far above
## the car's origin the rig sits, [code]rotation.x[/code] is how far it looks
## down, [member SpringArm3D.spring_length] is how far behind it sits, and the
## [Camera3D] child's [member Camera3D.fov] is the lens it sits behind. The
## exports below are how it [i]moves[/i]; [code]ChaseCamera.tscn[/code] is where
## it sits.
##
## Mouse look, the idle recentre and the end-of-round spin are carried over from
## [code]CameraControl.cs[/code], with its tilt clamp fixed. The source reads
## [codeblock lang=csharp]
## rot.X -= mouseMotionEvent.Relative.Y;
## rot.X = Mathf.Clamp(this.Rotation.X, -TiltMax, TiltMax);
## [/codeblock]
## which clamps the [i]old[/i] pitch rather than the one it just computed, and
## clamps radians against a limit written in degrees (75). Both together mean
## the clamp never does anything and the camera can be spun under the road.
## Here the new pitch is clamped, in radians, against [member tilt_max]
## converted.

enum State {
	FOLLOW, ## Behind the car, looking where it is going.
	FREELOOK, ## The player is looking around, and the view holds still while the car turns under it.
	RECENTRING, ## Easing back behind the car after a look.
	SPINNING, ## End-of-round showpiece, driven by [method start_idle_rotation].
}

## Asked of the followed node to find out how fast it is going across the
## ground. [PlayerCar] has it; anything else is measured by how far it moved.
const GROUND_SPEED_METHOD := &"ground_speed"

## A car pointing this close to straight up or straight down has no heading left
## to read, so the rig keeps the one it has rather than snapping to whatever
## rounding produced.
const HEADING_EPSILON := 0.001

@export_group("Follow")
## How hard the rig chases the car across the ground: the rate, per second, at
## which it closes the gap. Higher is tighter and more like being bolted on;
## lower trails further through a turn.
@export var follow_response: float = 9.0
## The same, vertically, and deliberately far slower. This is the number that
## takes the bounce out: at 2.0 a spring oscillation several times a second
## reaches the camera a tenth as far, while a kerb or a ramp, which is a height
## the car keeps, is followed within half a second.
@export var height_response: float = 2.0
## How hard the rig swings round to sit behind the car's new heading. Low
## enough that a flick of the wheel does not whip the view, high enough that the
## camera is behind the car again by the end of a turn.
@export var yaw_response: float = 4.5
## Metres the rig may fall behind the car before it gives up easing and is
## simply already there. What this catches is the car being [i]moved[/i] rather
## than driven -- a respawn, a kill plane, the start of a round -- which eased
## over is a second of the lot flying past the player. Zero switches it off.
@export var leash: float = 8.0

@export_group("Speed framing")
## Speed in m/s at which the speed framing is fully applied. The cars top out
## around 16.
@export var speed_reference: float = 14.0
## Extra metres the camera pulls back to at [member speed_reference]. Nothing
## about the car changes with speed, so this is the only thing that says the
## car is going quickly.
@export var distance_gain: float = 1.4
## Extra degrees of field of view at [member speed_reference]. Small on purpose:
## a lens that visibly breathes is its own kind of nausea.
@export var fov_gain: float = 6.0
## How quickly the speed framing follows a change in speed. Slow, so that a
## bump, a gear of throttle or a kerb does not pump the lens.
@export var speed_response: float = 1.2

@export_group("Look")
## Degrees the camera can be raised or lowered from the default. The source's 75
## is kept; it is only now that it does anything.
@export var tilt_max: float = 75.0
## Radians of rotation per pixel of mouse movement.
@export var mouse_sensitivity: float = 0.004
## Seconds of no mouse movement before the camera starts easing back.
@export var duration_to_snap: float = 1.2
## Seconds the ease back takes.
@export var recentre_duration: float = 0.45
## Radians per second for the end-of-round spin.
@export var spin_speed: float = 0.6
## Whether the camera captures the mouse while it is in the tree. Free look
## needs relative motion, and a browser only reports that under pointer lock.
## [Parkade] puts the cursor back on the way out of any game, so nothing has to
## undo this to leave.
@export var capture_mouse: bool = true

var state: State = State.FOLLOW

## The car. Null until [method follow] is handed one, and again if it is freed.
var _target: Node3D = null
## The [Camera3D] the arm carries, found by type so the scene may name it
## anything.
var _camera: Camera3D = null

## The authored framing, read from the scene once -- see the class docs.
var _pivot_height: float = 0.0
var _base_pitch: float = 0.0
var _base_distance: float = 0.0
var _base_fov: float = 0.0

## Where the rig is, in the world: the point it turns about, which is the car's
## origin plus [member _pivot_height], eased.
var _anchor := Vector3.ZERO
## Which way the rig is looking. Absolute, not an offset from the car: during a
## free look it is the player's, the rest of the time it eases toward the car's
## heading, and either way the car's roll and pitch are nowhere in it.
var _yaw: float = 0.0
## How far the rig is looking down. The car never writes this.
var _pitch: float = 0.0
## How much of the speed framing is applied, 0 to 1.
var _speed_blend: float = 0.0

var _idle_elapsed: float = 0.0
var _recentre_elapsed: float = 0.0
var _recentre_from_yaw: float = 0.0
var _recentre_from_pitch: float = 0.0

## Last known position of a followed node that cannot say how fast it is going,
## so its speed can be measured instead. Unused for [PlayerCar].
var _last_position := Vector3.ZERO
var _measuring_speed: bool = false


func _ready() -> void:
	_pivot_height = position.y
	# Only the pitch. The heading comes from the car and the roll is never
	# anything but zero, so authoring either of those in the scene would be
	# authoring something that is overwritten on the first frame.
	_base_pitch = rotation.x
	_pitch = _base_pitch
	_base_distance = spring_length
	_camera = _find_camera()
	if _camera != null:
		_base_fov = _camera.fov
	if capture_mouse:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Handed a car before it entered the tree: place the rig now that there is
	# a framing to place it with.
	if _target != null:
		snap_to_default()


func _find_camera() -> Camera3D:
	for child in get_children():
		if child is Camera3D:
			return child as Camera3D
	return null


## The car to follow, and where the rig goes at once. Called by [ParkingRound]
## after the rig is added to the lot -- [i]to the lot[/i], not to the car.
##
## The car is excluded from the spring arm's cast here. It has to be: the arm
## casts from a pivot level with the car's own roof -- inside the cabin shape on
## two of the three chassis -- and any look down sends the ray through the body,
## so an arm that treats the car as scenery finds the car it is looking at and
## pulls the camera into it. While the rig was a child of the car this question
## did not arise.
func follow(target: Node3D) -> void:
	_target = target
	_measuring_speed = false
	if target is CollisionObject3D:
		add_excluded_object((target as CollisionObject3D).get_rid())
	if is_node_ready():
		snap_to_default()


func _unhandled_input(event: InputEvent) -> void:
	if state == State.SPINNING:
		return
	if event is not InputEventMouseMotion:
		return
	var motion := event as InputEventMouseMotion
	state = State.FREELOOK
	_idle_elapsed = 0.0
	var limit := deg_to_rad(tilt_max)
	_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -limit, limit)
	_yaw -= motion.relative.x * mouse_sensitivity


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		# The car can go out from under the rig: leaving the cabinet frees the
		# lot, and the order its children go in is not ours to rely on.
		_target = null
	_advance_look(delta)
	if _target == null:
		return
	_follow(delta)
	_frame_for_speed(delta)
	_apply()


## The look half of a frame: the idle timer, the ease back, and the end-of-round
## spin. All of it writes [member _yaw] and [member _pitch] and nothing else.
func _advance_look(delta: float) -> void:
	match state:
		State.FREELOOK:
			# The view holds the heading the player left it at while the car
			# turns underneath -- which is the whole use of a free look, and
			# what tracking the car through one would take away.
			_idle_elapsed += delta
			if _idle_elapsed >= duration_to_snap:
				_begin_recentre()
		State.RECENTRING:
			_recentre_elapsed += delta
			var t := 1.0 if recentre_duration <= 0.0 \
					else minf(_recentre_elapsed / recentre_duration, 1.0)
			# Eased rather than linear, so the camera leaves and arrives gently
			# and the player is not told twice that it moved.
			var eased := ease(t, 0.35)
			# lerp_angle takes the short way round. The source lerps the raw
			# angle, so a player who swung the camera past half a turn watched
			# it unwind the long way home.
			_yaw = lerp_angle(_recentre_from_yaw, _heading(_yaw), eased)
			_pitch = lerpf(_recentre_from_pitch, _base_pitch, eased)
			if is_equal_approx(t, 1.0):
				state = State.FOLLOW
		State.SPINNING:
			_yaw = wrapf(_yaw + spin_speed * delta, -PI, PI)
		State.FOLLOW:
			pass


## The follow half: where the rig is, and -- when it is behind the car rather
## than being looked around -- which way it faces.
func _follow(delta: float) -> void:
	var pivot := _target.global_position + Vector3.UP * _pivot_height
	if leash > 0.0 and _anchor.distance_to(pivot) > leash:
		_anchor = pivot
	else:
		var planar := _damp(follow_response, delta)
		_anchor.x = lerpf(_anchor.x, pivot.x, planar)
		_anchor.z = lerpf(_anchor.z, pivot.z, planar)
		_anchor.y = lerpf(_anchor.y, pivot.y, _damp(height_response, delta))
	if state == State.FOLLOW:
		_yaw = lerp_angle(_yaw, _heading(_yaw), _damp(yaw_response, delta))


func _frame_for_speed(delta: float) -> void:
	var wanted := clampf(_ground_speed(delta) / maxf(speed_reference, 0.001), 0.0, 1.0)
	_speed_blend = lerpf(_speed_blend, wanted, _damp(speed_response, delta))
	spring_length = _base_distance + distance_gain * _speed_blend
	if _camera != null:
		_camera.fov = _base_fov + fov_gain * _speed_blend


## Writes the frame. The basis is built from a yaw and a pitch, in that order,
## and there is no third term: a rig whose roll is not a value anywhere is a rig
## that cannot be rolled by a car landing on one wheel.
func _apply() -> void:
	global_transform = Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), _anchor)


func _begin_recentre() -> void:
	state = State.RECENTRING
	_recentre_elapsed = 0.0
	_recentre_from_yaw = _yaw
	_recentre_from_pitch = _pitch


## Puts the camera back behind the car immediately: default pitch, default
## framing, and the rig itself moved rather than eased. Called at the end of a
## recentre, and by anything that wants the default view [i]now[/i] -- the start
## of a round, or a car that has just been put back on its marker.
func snap_to_default() -> void:
	state = State.FOLLOW
	_pitch = _base_pitch
	_speed_blend = 0.0
	spring_length = _base_distance
	if _camera != null:
		_camera.fov = _base_fov
	if _target == null:
		return
	_yaw = _heading(_yaw)
	_anchor = _target.global_position + Vector3.UP * _pivot_height
	_measuring_speed = false
	_apply()


## Circles the car for the end-of-round card. Mouse look is ignored until
## something calls [method snap_to_default] again.
func start_idle_rotation() -> void:
	state = State.SPINNING


## The way the car is pointing, as a heading the rig can sit behind: its forward
## axis flattened onto the ground and read as a yaw. This is where the car's
## pitch and roll are dropped -- flattening the nose of a car leaning into a
## turn gives the same heading as flattening the nose of one standing level, so
## neither reaches the camera.
##
## [param fallback] is returned for a car with no heading left to read: one
## nose-up or nose-down enough that its forward axis is more or less vertical.
func _heading(fallback: float) -> float:
	if _target == null:
		return fallback
	var forward := -_target.global_basis.z
	if absf(forward.x) + absf(forward.z) < HEADING_EPSILON:
		return fallback
	# atan2(sin, cos) of the yaw whose +Z -- the way the arm reaches, and so the
	# way the camera sits -- points back down the car's nose.
	return atan2(-forward.x, -forward.z)


## How fast the followed car is going across the ground, in m/s.
##
## [PlayerCar.ground_speed] is the answer when there is one: it is planar
## already, so a car sitting still on settling suspension reads as stopped
## rather than as doing 1.9 m/s straight up. Anything else is measured by how
## far it moved, which is what the test harness follows.
func _ground_speed(delta: float) -> float:
	if _target.has_method(GROUND_SPEED_METHOD):
		return absf(_target.call(GROUND_SPEED_METHOD))
	var here := _target.global_position
	var moved := 0.0
	if _measuring_speed and delta > 0.0:
		moved = Vector2(here.x - _last_position.x, here.z - _last_position.z).length() / delta
	_last_position = here
	_measuring_speed = true
	return moved


## The fraction of the way to a target to travel this frame, for a follow that
## closes [param response] of what is left of the gap every second.
##
## Exponential rather than a fixed lerp weight, because a fixed weight is a
## different camera at every frame rate -- and this cabinet runs in a browser,
## where the frame rate is whatever the tab is given. Zero or less means no
## easing at all.
static func _damp(response: float, delta: float) -> float:
	if response <= 0.0:
		return 1.0
	return 1.0 - exp(-response * delta)
