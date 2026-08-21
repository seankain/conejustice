class_name ConeThrower
extends Node
## Turns clicks into flying cones, and owns the magazine.
##
## This is a light-gun parody, so the cursor is the gun: throws go where the
## mouse points, not at screen centre.

@export var cone_scene: PackedScene
@export var camera: Camera3D

## Where thrown cones are parented. Never the camera rig: a cone parented to a
## travelling rig rides along with it instead of falling in the world.
@export var cone_container: Node

@export_group("Throw")
## Impulse magnitude. Launch speed is this divided by the cone's mass, so
## retuning the cone's mass means retuning this too.
@export var throw_impulse: float = 22.0
## Upward bias added to the aim direction before launch. This is the arc the
## player learns to lead with.
@export var throw_arc: float = 0.18
## Spawn point in camera-local space: right, down and forward of the eye.
@export var spawn_offset: Vector3 = Vector3(0.25, -0.2, -0.6)
## Random tumble applied on release, so no two throws land the same way.
@export var spin_impulse: float = 1.5
@export var throw_cooldown: float = 0.25

@export_group("Magazine")
@export var mag_size: int = 6
## Seconds a reload takes, during which throwing is blocked. The reserve is
## infinite, exactly as in Time Crisis: a reload costs time, not ammunition,
## and that cost is what makes the 60 second limit bite.
@export var reload_time: float = 0.9
## Off by default. Forgetting to reload should be a mistake the player makes,
## not something the game quietly covers for.
@export var auto_reload_on_empty: bool = false

@export_group("Performance")
## Live cones allowed before the oldest unscored one is culled. A full run can
## otherwise leave hundreds of bodies simulating, which the web build hates.
@export var max_live_cones: int = 40

## Cones left in the magazine.
var remaining: int = 0

## Set while a reload is running; blocks throwing.
var is_reloading: bool = false

var _reload_left: float = 0.0
var _cooldown_left: float = 0.0
var _live_cones: Array[ConeBody] = []


func _ready() -> void:
	# Mouse mode belongs to Crosshair, which draws the replacement cursor.
	remaining = mag_size
	# Deferred: the HUD is built after this node in the tree, so announcing the
	# magazine right here would broadcast it to nobody and leave the row empty.
	announce_magazine.call_deferred()


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if not is_reloading:
		return
	# A reload belongs to the section it started in. Letting one run on through
	# the travel tween would hand the next section a magazine it did not pay for.
	if GameState.run_state != GameState.RunState.ENGAGED:
		cancel_reload()
		return
	_reload_left = maxf(_reload_left - delta, 0.0)
	if _reload_left <= 0.0:
		_finish_reload()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("throw_cone"):
		try_throw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload"):
		try_reload()
		# Handled here so nothing else in the tree acts on it. This does not
		# stop the browser's own context menu on right click: that is the web
		# shell's job, and it only shows up in a real export, not the editor.
		get_viewport().set_input_as_handled()


## True when a throw would actually happen right now.
func can_throw() -> bool:
	return (GameState.run_state == GameState.RunState.ENGAGED
			and not is_reloading
			and remaining > 0
			and _cooldown_left <= 0.0
			and cone_scene != null
			and camera != null)


## Throws a cone if the player is allowed one. Rejected clicks are dropped, not
## queued: a click that arrives during a reload should feel like a mistake.
func try_throw() -> bool:
	if not can_throw():
		if auto_reload_on_empty and remaining <= 0:
			try_reload()
		return false
	_spawn_cone()
	remaining -= 1
	_cooldown_left = throw_cooldown
	EventBus.cone_thrown.emit(remaining, throw_cooldown)
	EventBus.magazine_changed.emit(remaining, mag_size)
	return true


## Starts a reload. Refused when one is already running, when the magazine is
## already full, or when the run is not live.
func try_reload() -> bool:
	if is_reloading or remaining >= mag_size:
		return false
	if GameState.run_state != GameState.RunState.ENGAGED:
		return false
	is_reloading = true
	_reload_left = reload_time
	# Emitted with the real duration so the magazine widget paces its refill
	# against the lockout instead of hardcoding one.
	EventBus.reload_started.emit(reload_time)
	return true


## Stops a running reload without filling the magazine.
func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_left = 0.0
	EventBus.reload_finished.emit()
	EventBus.magazine_changed.emit(remaining, mag_size)


func _finish_reload() -> void:
	is_reloading = false
	_reload_left = 0.0
	remaining = mag_size
	EventBus.reload_finished.emit()
	EventBus.magazine_changed.emit(remaining, mag_size)


## Re-announces magazine state. Anything that builds its display from the
## capacity needs this after a late connect.
func announce_magazine() -> void:
	EventBus.magazine_changed.emit(remaining, mag_size)


## Fills the magazine. The reload phase calls this when its timer completes.
func refill() -> void:
	cancel_reload()
	_cooldown_left = 0.0
	remaining = mag_size
	EventBus.magazine_changed.emit(remaining, mag_size)


## Frees every live cone. Used when restarting a run.
func clear_cones() -> void:
	for cone in _live_cones:
		if is_instance_valid(cone):
			cone.queue_free()
	_live_cones.clear()


func _spawn_cone() -> void:
	var mouse := camera.get_viewport().get_mouse_position()
	var aim := camera.project_ray_normal(mouse)
	var cam_xform := camera.global_transform

	var cone := cone_scene.instantiate() as ConeBody
	if cone == null:
		push_error("ConeThrower: cone_scene is not a ConeBody.")
		return

	var parent := cone_container if cone_container != null else get_parent()
	parent.add_child(cone)

	# Start roughly upright with a random yaw, so a throw reads as a cone
	# pulled off a stack rather than one spawned at a random angle.
	var tilt := Basis.from_euler(Vector3(
			randf_range(-0.4, 0.4), randf_range(0.0, TAU), randf_range(-0.4, 0.4)))
	cone.global_transform = Transform3D(tilt, cam_xform * spawn_offset)

	cone.apply_impulse((aim + Vector3.UP * throw_arc).normalized() * throw_impulse)
	cone.apply_torque_impulse(Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
	) * spin_impulse)

	_live_cones.append(cone)
	_enforce_cone_cap()


func _enforce_cone_cap() -> void:
	var alive: Array[ConeBody] = []
	for cone in _live_cones:
		if is_instance_valid(cone):
			alive.append(cone)
	_live_cones = alive

	# Cull oldest first, skipping scored cones. If every live cone is scored the
	# cap is allowed to be exceeded: the player earned those and watching them
	# vanish would be worse than the frames it costs.
	var over := _live_cones.size() - max_live_cones
	var index := 0
	while over > 0 and index < _live_cones.size():
		var cone := _live_cones[index]
		if cone.is_scored:
			index += 1
			continue
		cone.queue_free()
		_live_cones.remove_at(index)
		over -= 1
