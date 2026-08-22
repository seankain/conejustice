class_name HUD
extends CanvasLayer
## Score, clock and section banner.
##
## Listens to EventBus and nothing else. If a HUD script ever reaches into a
## gameplay node, that is a bug in the HUD.
##
## CenterMessage announces failures only. The section *clear* belongs to
## SectionTransition, which already sequences the band against the real travel
## duration: both drawing it off section_cleared put two copies of "AREA n
## CLEAR" at screen centre, and because this label is only cleared when the next
## section starts, the HUD's copy then sat under the travel band's heading for
## the whole trip.

## Below this many seconds the clock shows tenths, the arcade tell that time is
## nearly gone. Above it, whole seconds.
@export var decimal_below_seconds: float = 10.0
## Seconds the score takes to roll up to a new total. Rolling digits are most of
## the arcade feel for very little work.
@export var score_roll_time: float = 0.35

@export_group("Colours")
@export var timer_normal: Color = Color(1, 1, 1)
@export var timer_warning: Color = Color(1, 0.30, 0.25)
@export var banner_fail: Color = Color(1.0, 0.35, 0.30)

@onready var _section_label: Label = $Root/TopBar/SectionLabel
@onready var _timer_label: Label = $Root/TopBar/TimerLabel
@onready var _score_label: Label = $Root/TopBar/ScoreLabel
@onready var _message: Label = $Root/CenterMessage

var _displayed_score: float = 0.0
var _score_tween: Tween
var _pulse_tween: Tween


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.section_started.connect(_on_section_started)
	EventBus.section_timeout.connect(_on_section_timeout)
	EventBus.timer_tick.connect(_on_timer_tick)
	EventBus.timer_warning.connect(_on_timer_warning)
	EventBus.score_changed.connect(_on_score_changed)
	_reset()


func _reset() -> void:
	_clear_warning()
	_displayed_score = 0.0
	_score_label.text = "0"
	_timer_label.text = "--"
	_section_label.text = ""
	_message.text = ""


func _on_run_started() -> void:
	_reset()


func _on_section_started(index: int, _time_limit: float) -> void:
	_clear_warning()
	_section_label.text = "AREA %d" % (index + 1)
	_message.text = ""


func _on_section_timeout(_index: int) -> void:
	_show_banner("TIME UP", banner_fail)


func _on_timer_tick(seconds_remaining: float) -> void:
	_timer_label.text = _format_time(seconds_remaining)


func _on_timer_warning() -> void:
	_timer_label.add_theme_color_override(&"font_color", timer_warning)
	_kill_pulse()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_timer_label, "modulate:a", 0.35, 0.3)
	_pulse_tween.tween_property(_timer_label, "modulate:a", 1.0, 0.3)


func _on_score_changed(total: int, _delta: int) -> void:
	if _score_tween != null and _score_tween.is_valid():
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_score_tween.tween_method(_set_displayed_score, _displayed_score, float(total), score_roll_time)


## Ceil, not floor: the clock should read 1 while any time is left and reach 0
## exactly when it runs out.
func _format_time(seconds: float) -> String:
	if seconds <= decimal_below_seconds:
		return "%.1f" % seconds
	return str(ceili(seconds))


func _set_displayed_score(value: float) -> void:
	_displayed_score = value
	_score_label.text = str(roundi(value))


func _show_banner(text: String, colour: Color) -> void:
	_message.text = text
	_message.add_theme_color_override(&"font_color", colour)


func _clear_warning() -> void:
	_kill_pulse()
	_timer_label.modulate.a = 1.0
	_timer_label.add_theme_color_override(&"font_color", timer_normal)


func _kill_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
