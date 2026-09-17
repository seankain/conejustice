class_name DebugReadout
extends Control
## The three numbers the bay is measuring, on screen, while tuning the grade.
##
## Ported from [code]debug_hud.tscn[/code] and [code]DebugHud.cs[/code], which
## is three exported labels and nothing else -- the source writes to them from
## inside [code]ParkingSpace.CalculateCurrentParkingScore[/code], so the bay
## reaches across the tree into the HUD on every frame the player is in it.
## Here the round feeds it, the same way it feeds the rest of the HUD, and it is
## hidden unless somebody turns it on.

@onready var _angle: Label = $Panel/Rows/Angle
@onready var _distance: Label = $Panel/Rows/Distance
@onready var _lines: Label = $Panel/Rows/Lines
@onready var _grade: Label = $Panel/Rows/Grade


## Writes the live measurements. Called only while the player is in a bay.
func show_measurements(data: RoundData) -> void:
	_angle.text = "angle      %6.2f deg" % data.parking_angle
	_distance.text = "off centre %6.2f m" % data.centre_distance
	_lines.text = "lines      %s" % _describe_lines(data)
	_grade.text = "would be   %s" % data.grade_letter()


## Blanks the readout when the player is not in a bay, so a stale number is
## never read as a live one.
func clear() -> void:
	_angle.text = "angle         --"
	_distance.text = "off centre    --"
	_lines.text = "lines         --"
	_grade.text = "would be      --"


func _describe_lines(data: RoundData) -> String:
	if data.over_left_line and data.over_right_line:
		return "both"
	if data.over_left_line:
		return "left"
	if data.over_right_line:
		return "right"
	return "clear"
