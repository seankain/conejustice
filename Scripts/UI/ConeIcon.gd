class_name ConeIcon
extends Control
## One cone in the magazine row, drawn rather than textured.
##
## Drawing it avoids an imported asset entirely: no SVG, no SubViewport
## rendering a 3D cone, nothing for the GL Compatibility renderer to upload. It
## also stays crisp at any HUD scale, which a small bitmap would not.

const LOADED_BODY := Color(0.95, 0.42, 0.10)
const LOADED_STRIPE := Color(0.97, 0.97, 0.95)
const LOADED_BASE := Color(0.72, 0.28, 0.05)

const SPENT_BODY := Color(0.42, 0.42, 0.46)
const SPENT_STRIPE := Color(0.56, 0.56, 0.60)
const SPENT_BASE := Color(0.30, 0.30, 0.34)
const SPENT_ALPHA := 0.25

## Spent cones sink a few pixels, so the row reads at a glance even in
## greyscale or for a player who cannot pick the colours apart.
const SPENT_DROP := 4.0

## Read-only from outside; go through set_loaded() so the drop animation and
## the state can never disagree.
var loaded: bool = true

var _drop: float = 0.0:
	set(value):
		_drop = value
		queue_redraw()

var _drop_tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(20, 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var cx := w * 0.5
	var base_h := maxf(h * 0.13, 3.0)
	var base_y := h - base_h + _drop
	var tip_y := _drop

	var alpha := 1.0 if loaded else SPENT_ALPHA
	var body := LOADED_BODY if loaded else SPENT_BODY
	var stripe := LOADED_STRIPE if loaded else SPENT_STRIPE
	var base := LOADED_BASE if loaded else SPENT_BASE

	draw_rect(Rect2(cx - w * 0.44, base_y, w * 0.88, base_h), Color(base, alpha))
	draw_colored_polygon(_band(0.0, 1.0, base_y, tip_y, cx, w), Color(body, alpha))
	draw_colored_polygon(_band(0.34, 0.58, base_y, tip_y, cx, w), Color(stripe, alpha))


## Sets the state, optionally without animating. Assigning through a property
## setter here would start the very tween an instant set is trying to skip, so
## the two paths are one function instead.
func set_loaded(value: bool, animate: bool = true) -> void:
	if loaded == value:
		return
	loaded = value
	if animate and is_inside_tree():
		_animate_drop()
		return
	_kill_tween()
	_drop = 0.0 if loaded else SPENT_DROP
	queue_redraw()


## A horizontal slice of the cone between two heights, 0 at the base and 1 at
## the tip. Both the body and the stripe are slices, so the stripe always
## follows the taper instead of poking out of the sides.
func _band(t0: float, t1: float, base_y: float, tip_y: float, cx: float, w: float) -> PackedVector2Array:
	var y0 := lerpf(base_y, tip_y, t0)
	var y1 := lerpf(base_y, tip_y, t1)
	var half0 := lerpf(w * 0.35, w * 0.09, t0)
	var half1 := lerpf(w * 0.35, w * 0.09, t1)
	return PackedVector2Array([
		Vector2(cx - half0, y0), Vector2(cx + half0, y0),
		Vector2(cx + half1, y1), Vector2(cx - half1, y1),
	])


func _animate_drop() -> void:
	_kill_tween()
	_drop_tween = create_tween()
	_drop_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_drop_tween.tween_property(self, "_drop", 0.0 if loaded else SPENT_DROP, 0.12)


func _kill_tween() -> void:
	if _drop_tween != null and _drop_tween.is_valid():
		_drop_tween.kill()
	_drop_tween = null
