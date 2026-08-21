class_name SectionTransition
extends Control
## The band that covers the trip between stops.
##
## It opens when a section clears, holds while the time bonus counts up, and
## closes so that it is gone exactly as the camera parks. The close is timed
## from the duration travel_started reports, not from a constant here: hardcode
## it and the wipe desyncs the moment a stop's travel_time is tuned.

@export var open_time: float = 0.22
## Fraction of the trip spent held open before the band starts closing.
@export var hold_fraction: float = 0.55
@export var band_height: float = 150.0
@export var bonus_count_time: float = 0.6

@export_group("Colours")
@export var band_colour: Color = Color(0.05, 0.05, 0.08, 0.88)
@export var heading_colour: Color = Color(0.55, 1.0, 0.55)
@export var bonus_colour: Color = Color(1.0, 0.88, 0.35)

## 0 closed, 1 fully open.
var _open: float = 0.0:
	set(value):
		_open = value
		queue_redraw()

var _shown_bonus: float = 0.0:
	set(value):
		_shown_bonus = value
		queue_redraw()

var _heading: String = ""
var _bonus_text: String = ""
var _bonus_points: int = 0
var _tween: Tween
var _bonus_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.section_cleared.connect(_on_section_cleared)
	EventBus.section_bonus.connect(_on_section_bonus)
	EventBus.travel_started.connect(_on_travel_started)
	EventBus.travel_finished.connect(_on_travel_finished)
	EventBus.run_started.connect(_reset)
	EventBus.run_over.connect(_on_run_over)


func _draw() -> void:
	if _open <= 0.001:
		return

	var h := band_height * _open
	var mid := size.y * 0.5
	draw_rect(Rect2(0.0, mid - h * 0.5, size.x, h), band_colour)
	if _open < 0.9:
		return

	var font := get_theme_default_font()
	_draw_centred(font, _heading, 44, mid - 26.0, heading_colour)
	if _bonus_points > 0:
		var text := "%s  +%d" % [_bonus_text, roundi(_shown_bonus)]
		_draw_centred(font, text, 26, mid + 26.0, bonus_colour)


func _draw_centred(font: Font, text: String, font_size: int, y: float, colour: Color) -> void:
	if text.is_empty():
		return
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5, y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)


func _on_section_cleared(index: int, _time_remaining: float) -> void:
	_heading = "AREA %d CLEAR" % (index + 1)
	_bonus_points = 0
	_bonus_text = ""
	_shown_bonus = 0.0
	_kill(_tween)
	_tween = create_tween()
	_tween.tween_property(self, "_open", 1.0, open_time)


## Arrives in the same frame as section_cleared, in either order, so this only
## fills in the bonus rather than assuming it runs second.
func _on_section_bonus(seconds_left: int, points: int) -> void:
	_bonus_points = points
	_bonus_text = "TIME BONUS %ds" % seconds_left
	_kill(_bonus_tween)
	_shown_bonus = 0.0
	_bonus_tween = create_tween()
	_bonus_tween.tween_property(self, "_shown_bonus", float(points), bonus_count_time)


func _on_travel_started(_from_index: int, to_index: int, duration: float) -> void:
	_heading = "AREA %d" % (to_index + 1)
	_kill(_tween)
	_tween = create_tween()
	# Open first in case the trip began without a clear, e.g. a skipped section.
	_tween.tween_property(self, "_open", 1.0, minf(open_time, duration * 0.2))
	_tween.tween_interval(duration * hold_fraction)
	_tween.tween_property(self, "_open", 0.0, duration * (1.0 - hold_fraction) * 0.8)


func _on_travel_finished(_index: int) -> void:
	_kill(_tween)
	_tween = create_tween()
	_tween.tween_property(self, "_open", 0.0, 0.12)


func _on_run_over(_won: bool) -> void:
	_reset()


func _reset() -> void:
	_kill(_tween)
	_kill(_bonus_tween)
	_open = 0.0
	_bonus_points = 0
	_heading = ""


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
