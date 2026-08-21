class_name Crosshair
extends Control
## The cursor, as a cone.
##
## This is a light-gun parody, so the pointer is the weapon. The system cursor
## is hidden and this is drawn in its place, which also gives somewhere to show
## the throw cooldown: the reticle opens on release and closes as it recovers,
## making the wait visible instead of mysterious.

## Turn off to get the ordinary system cursor back, e.g. while debugging.
@export var hide_system_cursor: bool = true
@export var idle_radius: float = 11.0
@export var kick_radius: float = 22.0
@export var colour: Color = Color(1.0, 0.62, 0.15)

var _radius: float = 11.0:
	set(value):
		_radius = value
		queue_redraw()

var _tween: Tween


var _aiming: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radius = idle_radius
	visible = false
	EventBus.cone_thrown.connect(_on_cone_thrown)


func _process(_delta: float) -> void:
	# The reticle replaces the cursor only while there is something to aim at.
	# On the title and run-over screens the system cursor comes back, or the
	# player would be clicking buttons they cannot see the pointer on.
	var aiming := GameState.run_state == GameState.RunState.ENGAGED
	if aiming != _aiming:
		_aiming = aiming
		visible = aiming
		if hide_system_cursor:
			Input.set_mouse_mode(
					Input.MOUSE_MODE_HIDDEN if aiming else Input.MOUSE_MODE_VISIBLE)
	if not aiming:
		return
	# The cursor moves without emitting anything this node can hook, so the
	# position is read every frame rather than pushed.
	queue_redraw()


func _draw() -> void:
	var p := get_local_mouse_position()
	var r := _radius

	# Four ticks around the aim point, opening and closing with the cooldown.
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(p + dir * (r * 0.45), p + dir * r, colour, 2.0)

	# A small cone at the centre, so the pointer reads as what it throws.
	var h := 9.0
	var half := 4.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(p.x - half, p.y + h * 0.5),
		Vector2(p.x + half, p.y + h * 0.5),
		Vector2(p.x + half * 0.25, p.y - h * 0.5),
		Vector2(p.x - half * 0.25, p.y - h * 0.5),
	]), colour)
	draw_rect(Rect2(p.x - half * 1.35, p.y + h * 0.5, half * 2.7, 2.0), colour)


func _on_cone_thrown(_remaining: int, cooldown: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_radius = kick_radius
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Recovery is tied to the real cooldown, so retuning the throw rate keeps
	# the reticle honest.
	_tween.tween_property(self, "_radius", idle_radius, maxf(cooldown, 0.01))
