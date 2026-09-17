class_name ChaseCamera
extends SpringArm3D
## The camera behind the car: looks where the mouse says, recentres when the
## mouse stops, and spins around the car when the round is over.
##
## A [SpringArm3D], so the camera is pulled in when the lot's geometry gets
## between it and the car rather than clipping through a wall. Parented to the
## car, so it inherits the car's heading and only ever has to think about its
## own offset from it.
##
## Ported from [code]CameraControl.cs[/code], with its tilt clamp fixed. The
## source reads
## [codeblock lang=csharp]
## rot.X -= mouseMotionEvent.Relative.Y;
## rot.X = Mathf.Clamp(this.Rotation.X, -TiltMax, TiltMax);
## [/codeblock]
## which clamps the [i]old[/i] pitch rather than the one it just computed, and
## clamps radians against a limit written in degrees (75). Both together mean the
## clamp never does anything, and the camera can be spun under the road. Here the
## new pitch is clamped, in radians, against [member tilt_max] converted.
##
## The other difference is the recentre. The source teleports the camera back to
## its default the moment the mouse has been still for a second, which reads as a
## glitch at speed; this eases back over [member recentre_duration].

enum State {
	FOLLOW, ## Sitting at the default offset behind the car.
	FREELOOK, ## The player is looking around.
	RECENTRING, ## Easing back to the default after a look.
	SPINNING, ## End-of-round showpiece, driven by [method start_idle_rotation].
}

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

var _default_rotation: Vector3
var _idle_elapsed: float = 0.0
var _recentre_elapsed: float = 0.0
var _recentre_from: Vector3


func _ready() -> void:
	_default_rotation = rotation
	if capture_mouse:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.SPINNING:
		return
	if event is not InputEventMouseMotion:
		return
	var motion := event as InputEventMouseMotion
	state = State.FREELOOK
	_idle_elapsed = 0.0
	var limit := deg_to_rad(tilt_max)
	rotation.x = clampf(rotation.x - motion.relative.y * mouse_sensitivity, -limit, limit)
	rotation.y -= motion.relative.x * mouse_sensitivity


func _process(delta: float) -> void:
	match state:
		State.FREELOOK:
			_idle_elapsed += delta
			if _idle_elapsed >= duration_to_snap:
				_begin_recentre()
		State.RECENTRING:
			_recentre_elapsed += delta
			var t := 1.0 if recentre_duration <= 0.0 else minf(_recentre_elapsed / recentre_duration, 1.0)
			# Eased rather than linear, so the camera leaves and arrives gently
			# and the player is not told twice that it moved.
			rotation = _recentre_from.lerp(_default_rotation, ease(t, 0.35))
			if is_equal_approx(t, 1.0):
				snap_to_default()
		State.SPINNING:
			rotation.y = wrapf(rotation.y + spin_speed * delta, -PI, PI)
		State.FOLLOW:
			pass


func _begin_recentre() -> void:
	state = State.RECENTRING
	_recentre_elapsed = 0.0
	_recentre_from = rotation


## Puts the camera back behind the car immediately. Called at the end of the
## recentre, and by anything that wants the default view now -- the start of a
## round, for one.
func snap_to_default() -> void:
	rotation = _default_rotation
	state = State.FOLLOW


## Circles the car for the end-of-round card. Mouse look is ignored until
## something calls [method snap_to_default] again.
func start_idle_rotation() -> void:
	state = State.SPINNING
