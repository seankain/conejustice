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
## Refill instantly on the reload action. Temporary: the timed reload with its
## lockout replaces this, at which point this should go off.
@export var debug_instant_reload: bool = true

@export_group("Performance")
## Live cones allowed before the oldest unscored one is culled. A full run can
## otherwise leave hundreds of bodies simulating, which the web build hates.
@export var max_live_cones: int = 40

## Cones left in the magazine.
var remaining: int = 0

## Set while a reload is running; blocks throwing. Owned by the reload phase.
var is_reloading: bool = false

var _cooldown_left: float = 0.0
var _live_cones: Array[ConeBody] = []


func _ready() -> void:
	# The cursor is the aiming device, so it stays visible.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	remaining = mag_size
	EventBus.magazine_changed.emit(remaining, mag_size)


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("throw_cone"):
		try_throw()
	elif debug_instant_reload and event.is_action_pressed("reload"):
		refill()


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
		return false
	_spawn_cone()
	remaining -= 1
	_cooldown_left = throw_cooldown
	EventBus.cone_thrown.emit(remaining)
	EventBus.magazine_changed.emit(remaining, mag_size)
	return true


## Fills the magazine. The reload phase calls this when its timer completes.
func refill() -> void:
	if remaining == mag_size:
		return
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
