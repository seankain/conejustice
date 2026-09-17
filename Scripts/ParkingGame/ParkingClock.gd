class_name ParkingClock
extends RefCounted
## The one place seconds become a clock.
##
## The source formats time twice, in [code]Hud.UpdateLevelTime[/code] and in
## [code]LevelScoreHudElement.SetValueLabels[/code], both with
## [code]TimeSpan.FromSeconds(x).ToString()[/code] -- which prints
## [code]00:01:00[/code] for a minute, and eight fractional digits for anything
## that is not a whole number of seconds.
##
## Never instantiated.


## [param seconds] as m:ss. Negative time reads as zero: a clock that has run
## out has run out.
static func format(seconds: float) -> String:
	var whole := maxi(floori(seconds), 0)
	return "%d:%02d" % [whole / 60, whole % 60]


## [param seconds] as a duration for the score card, where a tenth matters and a
## leading minute usually does not.
static func format_duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%.1f s" % maxf(seconds, 0.0)
	return format(seconds)
