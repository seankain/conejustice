class_name Screens
extends CanvasLayer
## Title screen and run-over screen.
##
## Buttons raise start_run_requested rather than calling SectionManager, so the
## UI still never drives gameplay directly: it says what the player asked for
## and the gameplay side decides what that means.

@onready var _title: Control = $Title
@onready var _run_over: Control = $RunOver
@onready var _heading: Label = $RunOver/Box/Heading
@onready var _stats: Label = $RunOver/Box/Stats
@onready var _start_button: Button = $Title/Box/StartButton
@onready var _retry_button: Button = $RunOver/Box/RetryButton

@export var won_heading: String = "JUSTICE SERVED"
@export var lost_heading: String = "TIME UP"
@export var won_colour: Color = Color(0.55, 1.0, 0.55)
@export var lost_colour: Color = Color(1.0, 0.42, 0.35)


func _ready() -> void:
	_start_button.pressed.connect(_request_run)
	_retry_button.pressed.connect(_request_run)
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_over.connect(_on_run_over)
	_title.visible = true
	_run_over.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_request_run()
		get_viewport().set_input_as_handled()


func _request_run() -> void:
	EventBus.start_run_requested.emit()


func _on_run_started() -> void:
	_title.visible = false
	_run_over.visible = false


func _on_run_over(won: bool) -> void:
	_heading.text = won_heading if won else lost_heading
	_heading.add_theme_color_override(&"font_color", won_colour if won else lost_colour)
	_stats.text = "\n".join([
		"SCORE          %d" % GameState.score,
		"CARS CONED     %d" % GameState.cars_coned,
		"CONES THROWN   %d" % GameState.cones_thrown,
		"ACCURACY       %d%%" % roundi(GameState.accuracy() * 100.0),
	])
	_run_over.visible = true
	_retry_button.grab_focus()
