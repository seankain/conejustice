class_name TargetMarkers
extends Control
## Screen-space brackets over the cars this section wants coned, and the score
## that floats off them when a cone lands.
##
## Without this the player cannot tell which cars are targets or how close one
## is to being done. Rails shooters live on that readout.
##
## Only the armed cars are tracked. Iterating every car in the level each frame
## would work today and stop working the moment the level grows.

## Height above a car's origin to hang its bracket, roughly mid-body.
@export var marker_height: float = 1.1
## World height used to size the bracket, so it shrinks with distance without
## anyone having to invent a pixels-per-metre constant.
@export var marker_world_size: float = 1.3
@export var bracket_min_half: float = 16.0
@export var bracket_max_half: float = 160.0

@export_group("Colours")
@export var active_colour: Color = Color(1.0, 0.85, 0.30)
@export var done_colour: Color = Color(0.45, 1.0, 0.5)
@export var popup_colour: Color = Color(1.0, 0.95, 0.6)
@export var stamp_colour: Color = Color(0.5, 1.0, 0.55)

@export_group("Feedback")
@export var popup_life: float = 1.1
@export var popup_rise: float = 54.0
@export var done_fade: float = 0.8

## Typed, and hoisted out of _draw. Iterating an untyped array literal yields
## Variant corners, and Vector2 arithmetic against a Variant has no inferable
## result type; as a constant it is also not rebuilt on every frame.
const BRACKET_CORNERS: Array[Vector2] = [
	Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1),
]

var _cars: Array[TargetCar] = []
## Seconds since each car was finished, for fading its bracket out.
var _done_age: Dictionary = {}
## Floating text: {text, world, age, colour, size}
var _popups: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.section_armed.connect(_on_section_armed)
	EventBus.section_cleared.connect(_on_section_ended)
	EventBus.section_timeout.connect(_on_section_ended)
	EventBus.run_started.connect(_clear)
	EventBus.car_coned.connect(_on_car_coned)
	EventBus.score_popup.connect(_on_score_popup)


func _process(delta: float) -> void:
	var live := false

	for key in _done_age.keys():
		_done_age[key] += delta
		live = true

	var i := _popups.size() - 1
	while i >= 0:
		_popups[i]["age"] += delta
		if _popups[i]["age"] >= popup_life:
			_popups.remove_at(i)
		i -= 1

	if _cars.is_empty() and _popups.is_empty() and not live:
		return
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	for car in _cars:
		if not is_instance_valid(car):
			continue
		_draw_bracket(camera, car)

	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for popup in _popups:
		_draw_popup(camera, font, font_size, popup)


func _draw_bracket(camera: Camera3D, car: TargetCar) -> void:
	var anchor := car.global_position + Vector3.UP * marker_height
	# A bracket for a car behind the camera would smear across the screen as
	# the rig turns, so those are simply not drawn.
	if camera.is_position_behind(anchor):
		return

	var centre := camera.unproject_position(anchor)
	var top := camera.unproject_position(anchor + Vector3.UP * marker_world_size)
	var half := clampf(absf(centre.y - top.y), bracket_min_half, bracket_max_half)
	var half_w := half * 1.35

	var colour := active_colour
	var key := car.get_instance_id()
	if _done_age.has(key):
		var t: float = clampf(float(_done_age[key]) / done_fade, 0.0, 1.0)
		colour = done_colour
		colour.a = 1.0 - t
		if colour.a <= 0.0:
			return

	var rect := Rect2(centre.x - half_w, centre.y - half, half_w * 2.0, half * 2.0)
	var arm := minf(half_w, half) * 0.4
	var width := 2.0
	# Corner brackets, not a full box: less to read past when aiming.
	for corner in BRACKET_CORNERS:
		var p := rect.position + rect.size * corner
		var sx := 1.0 if corner.x == 0.0 else -1.0
		var sy := 1.0 if corner.y == 0.0 else -1.0
		draw_line(p, p + Vector2(arm * sx, 0.0), colour, width)
		draw_line(p, p + Vector2(0.0, arm * sy), colour, width)

	_draw_pips(car, Vector2(centre.x, rect.end.y + 10.0), colour)


## Progress pips under the bracket, so how close a car is to done is readable
## without counting cones on the model.
func _draw_pips(car: TargetCar, centre: Vector2, colour: Color) -> void:
	var required := maxi(car.cones_required, 1)
	var done := car.coned_count()
	var pip := 4.0
	var gap := 5.0
	var total := required * pip * 2.0 + (required - 1) * gap
	var x := centre.x - total * 0.5 + pip

	for i in required:
		var at := Vector2(x + i * (pip * 2.0 + gap), centre.y)
		if i < done:
			draw_circle(at, pip, colour)
		else:
			var dim := colour
			dim.a *= 0.35
			draw_circle(at, pip, dim)


func _draw_popup(camera: Camera3D, font: Font, font_size: int, popup: Dictionary) -> void:
	var world: Vector3 = popup["world"]
	if camera.is_position_behind(world):
		return
	var age: float = popup["age"]
	var t := clampf(age / popup_life, 0.0, 1.0)
	var at := camera.unproject_position(world)
	at.y -= popup_rise * t

	var colour: Color = popup["colour"]
	colour.a = 1.0 - t * t
	var text: String = popup["text"]
	var size: int = popup["size"]
	# Centred by measuring, since draw_string aligns within a width rather than
	# around a point.
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(at.x - w * 0.5, at.y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


func _on_section_armed(cars: Array) -> void:
	_clear()
	for car in cars:
		var target := car as TargetCar
		if target != null:
			_cars.append(target)


func _on_section_ended(_a = null, _b = null) -> void:
	_cars.clear()
	_done_age.clear()


func _on_car_coned(car: Node3D) -> void:
	var target := car as TargetCar
	if target == null:
		return
	_done_age[target.get_instance_id()] = 0.0
	_push(target.global_position + Vector3.UP * marker_height, "CONED!", stamp_colour, 30)


func _on_score_popup(amount: int, world_position: Vector3) -> void:
	if amount <= 0:
		return
	_push(world_position, "+%d" % amount, popup_colour, 22)


func _push(world: Vector3, text: String, colour: Color, size: int) -> void:
	_popups.append({"world": world, "text": text, "age": 0.0, "colour": colour, "size": size})


func _clear() -> void:
	_cars.clear()
	_done_age.clear()
	_popups.clear()
	queue_redraw()
