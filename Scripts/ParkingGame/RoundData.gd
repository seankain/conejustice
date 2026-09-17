class_name RoundData
extends RefCounted
## Everything one round tallied, and the single grade calculation that reads it.
##
## Ported from [code]LevelData.cs[/code]. The source has this maths twice --
## [code]LevelData.CalculateRank[/code] and
## [code]ParkingSpace.CalculateCurrentParkingScore[/code] -- and the two have
## drifted: the space's copy leaves collisions out, so the number on screen
## while you park and the grade on the card at the end are different functions
## of the same park. This is the only copy, and the live readout and the score
## card both call it.
##
## Plain data with one method on it, not a node: the round owns one of these and
## throws it away when the next round starts.

## Worst to best is F to A; [method rank] counts the other way, from 0 for an A,
## because that is the direction the penalties add in.
enum Grade { A, B, C, D, F }

const GRADE_LETTERS := ["A", "B", "C", "D", "F"]

## Seconds the player spent off the tarmac. Tallied and shown, but it does not
## move the grade -- neither does it in the source, whose own comment calls that
## a to-do.
var seconds_offroad: float = 0.0

## What the player hit, in the order they hit it. Each one costs a full rank.
var collisions: Array[Obstacle.Kind] = []

## Degrees off the bay's axis, folded so nose-in and backed-in are both square.
## Zero is perfectly aligned.
var parking_angle: float = 0.0

## Metres from the middle of the bay, measured flat.
var centre_distance: float = 0.0

## Whether the car is sitting on either painted line.
var over_left_line: bool = false
var over_right_line: bool = false

## Whether the car came to rest inside a bay at all. A round that ends anywhere
## else is a failure however square the car happens to be.
var parked_in_space: bool = false


## The round's numeric rank: 0 for an A, 4 for an F.
##
## Distance and angle average, then every line crossed and everything hit adds a
## rank. The halving is integer division, exactly as the source does it, so a
## perfect angle rescues a sloppy distance by one rank and not two.
func rank() -> int:
	if not parked_in_space:
		return Grade.F

	var distance_rank := ParkingRules.DISTANCE_BANDS.size()
	for i in ParkingRules.DISTANCE_BANDS.size():
		if centre_distance <= ParkingRules.DISTANCE_BANDS[i]:
			distance_rank = i
			break

	# One rank per whole degree off square, which is strict, and is the feel the
	# source was tuned around.
	var angle_rank := mini(floori(parking_angle), ParkingRules.MAX_ANGLE_RANK)

	var total := (distance_rank + angle_rank) / 2
	if over_left_line:
		total += 1
	if over_right_line:
		total += 1
	total += collisions.size()
	return clampi(total, 0, Grade.F)


## The rank as a [enum Grade].
func grade() -> Grade:
	return rank() as Grade


## The letter the score card shows.
func grade_letter() -> String:
	return GRADE_LETTERS[rank()]


## Whether this round earns the next level rather than a re-run.
func passed() -> bool:
	return rank() <= ParkingRules.PASSING_RANK


## How many of [param kinds] were hit. The score card counts cars separately
## from living things.
func collisions_of(kinds: Array) -> int:
	var count := 0
	for kind in collisions:
		if kinds.has(kind):
			count += 1
	return count
