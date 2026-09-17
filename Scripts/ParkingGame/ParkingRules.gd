class_name ParkingRules
extends RefCounted
## The tuning constants for a round: how long you get, how much of it you lose
## each level, how many cars fill the lot, and where the grade boundaries sit.
##
## Ported from the source's [code]LevelDefaults[/code], plus the grade
## boundaries that were loose numbers inside the two copies of the rank maths.
## They are here rather than as [code]@export[/code]s because the same numbers
## have to be readable from a plain [RoundData], which is not a node and has no
## inspector.
##
## Never instantiated.

## Seconds in the first round.
const DEFAULT_SECONDS := 60.0
## However many rounds in, a round is never shorter than this.
const MIN_SECONDS := 25.0
## Seconds taken off per level reached.
const SECONDS_PER_LEVEL := 5.0
## Cars parked in the lot per level. The source declares a starting count of 5
## as well and then never reads it: its spawner fills level x 2 spaces from
## level 1 onwards.
const VEHICLES_PER_LEVEL := 2
## Seconds between random events -- a pedestrian walking out of a car (T15).
const RANDOM_EVENT_SECONDS := 10.0
## Seconds the round holds on the score card before the next one starts.
const ROUND_OVER_SECONDS := 5.0

## Distance from the middle of the bay, in metres, for each distance rank. Read
## in order: the first band the car is inside wins, and anything past the last
## one scores the worst rank.
const DISTANCE_BANDS: Array[float] = [0.5, 0.9, 1.5]

## Degrees off the bay's axis per angle rank: under one degree is square, and
## the source caps the angle contribution at the worst rank from three degrees
## out. That is strict, and it is the feel the game was tuned around.
const MAX_ANGLE_RANK := 3

## Grade at or below this numeric rank advances to the next level; worse re-runs
## the same one. Source: [code]levelData.GradeAsNumeric <= 2[/code], a C.
const PASSING_RANK := 2
