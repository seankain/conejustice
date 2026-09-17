class_name ScoreCard
extends Control
## The card at the end of a round: what you hit, how long you spent off the
## tarmac, whether you stayed inside the lines, and the grade.
##
## Ported from [code]LevelScoreHudElement.cs[/code]. Two differences. It reads
## the grade off [RoundData] rather than off a second copy of the rank maths, so
## the letter here is the same function as the number the HUD shows while you
## park. And its rollout is a tween rather than an [AnimationPlayer] track,
## which keeps the timing next to the thing it animates.

## Seconds the card takes to roll out.
@export var rollout_seconds: float = 0.45
## How far below its resting place the card starts.
@export var rollout_offset: float = 40.0

@export_group("Colours")
@export var pass_colour: Color = Color(0.55, 1.0, 0.55)
@export var fail_colour: Color = Color(1.0, 0.42, 0.35)

@onready var _panel: PanelContainer = $Panel
@onready var _cars_hit: Label = $Panel/Rows/CarsHit/Value
@onready var _living: Label = $Panel/Rows/LivingThings/Value
@onready var _offroad: Label = $Panel/Rows/Offroad/Value
@onready var _in_the_lines: Label = $Panel/Rows/InTheLines/Value
@onready var _grade: Label = $Panel/Rows/Grade

var _tween: Tween


func _ready() -> void:
	visible = false


## Fills the card from [param data] and rolls it out.
func show_round(data: RoundData) -> void:
	_cars_hit.text = str(data.collisions_of([Obstacle.Kind.VEHICLE]))
	_living.text = str(data.collisions_of([Obstacle.Kind.PERSON, Obstacle.Kind.WILDLIFE]))
	_offroad.text = ParkingClock.format_duration(data.seconds_offroad)
	_in_the_lines.text = _lines_text(data)
	_grade.text = data.grade_letter()
	_grade.add_theme_color_override(
			&"font_color", pass_colour if data.passed() else fail_colour)

	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var resting := _panel.position
	_panel.position = resting + Vector2(0.0, rollout_offset)
	_panel.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, ^"position", resting, rollout_seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, ^"modulate:a", 1.0, rollout_seconds * 0.8)


## Takes the card away for the next round.
func hide_card() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false


## The source's own joke, kept: a car over both lines at once has done something
## the bay's geometry did not expect.
func _lines_text(data: RoundData) -> String:
	if data.over_left_line and data.over_right_line:
		return "HOW?!"
	if data.over_left_line or data.over_right_line:
		return "NO"
	if not data.parked_in_space:
		return "NOT IN A BAY"
	return "YES"
