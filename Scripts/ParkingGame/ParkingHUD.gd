class_name ParkingHUD
extends CanvasLayer
## Clock, level, live grade, the banner across the middle, and the score card.
##
## Named ParkingHUD rather than Hud: Cone Justice already has a [HUD], and two
## scripts whose [code]class_name[/code]s differ only in case would parse and
## would be a trap.
##
## It listens to [ParkingRound] and reaches into nothing. The source's version
## calls [code]GetNode<Level>("/root/Main/Level")[/code] [i]every frame[/i] in
## [code]_Process[/code] and pulls the clock and score off it, which is both a
## per-frame tree lookup and a path that does not exist once the game is a
## cabinet under Parkade.

## Seconds a banner stays up. The source starts its message timer twice --
## once with an explicit 3 s and once with whatever the inspector says -- so the
## duration is whichever call wins.
@export var message_seconds: float = 3.0
## The live grade readout and the round's clock share this: under it, the clock
## turns red.
@export var warning_seconds: float = 10.0
## The three live measurements, off by default. The source ships its debug HUD
## in the level scene, visible.
@export var show_debug: bool = false

@export_group("Colours")
@export var clock_normal: Color = Color(1, 1, 1)
@export var clock_warning: Color = Color(1.0, 0.30, 0.25)

@onready var _level_label: Label = $Root/TopBar/LevelLabel
@onready var _clock_label: Label = $Root/TopBar/ClockLabel
@onready var _grade_label: Label = $Root/TopBar/GradeLabel
@onready var _message: Label = $Root/CenterMessage
@onready var _score_card: ScoreCard = $Root/ScoreCard
@onready var _debug: DebugReadout = $Root/DebugReadout

var _message_left: float = 0.0


func _ready() -> void:
	_message.text = ""
	_debug.visible = show_debug
	_debug.clear()
	set_process(false)


## Points the HUD at a round. Called once, by the game root, rather than the HUD
## going looking for the round itself.
func follow(round_to_watch: ParkingRound) -> void:
	round_to_watch.round_started.connect(_on_round_started)
	round_to_watch.time_changed.connect(_on_time_changed)
	round_to_watch.measurements_changed.connect(_on_measurements_changed)
	round_to_watch.round_ended.connect(_on_round_ended)
	round_to_watch.message.connect(show_message)
	_on_round_started(round_to_watch.level, round_to_watch.seconds_remaining)


func _process(delta: float) -> void:
	_message_left -= delta
	if _message_left <= 0.0:
		_message.text = ""
		set_process(false)


## Puts [param text] across the middle of the screen for [member
## message_seconds].
func show_message(text: String) -> void:
	_message.text = text
	_message_left = message_seconds
	set_process(true)


func _on_round_started(level: int, seconds: float) -> void:
	_level_label.text = "LEVEL %d" % level
	_on_time_changed(seconds)
	_grade_label.text = "--"
	_score_card.hide_card()
	_debug.clear()


func _on_time_changed(seconds_remaining: float) -> void:
	_clock_label.text = ParkingClock.format(seconds_remaining)
	_clock_label.add_theme_color_override(
			&"font_color",
			clock_warning if seconds_remaining <= warning_seconds else clock_normal)


func _on_measurements_changed(data: RoundData) -> void:
	# The same RoundData the card grades at the end, so the letter cannot change
	# when the round stops for a reason other than the car moving.
	_grade_label.text = data.grade_letter()
	if show_debug:
		_debug.show_measurements(data)


func _on_round_ended(data: RoundData) -> void:
	_grade_label.text = data.grade_letter()
	# Whatever was across the middle belongs to the round that just ended; the
	# card is the message now. The round says why it ended after this.
	show_message("")
	_score_card.show_round(data)
