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
## Seconds between rolls of the lot's dice: whether a parked car backs out and
## leaves, whether a rival turns up for a space, and whether anything living
## walks out in front of you ([LotEvents]). The source keeps the same constant
## for a pedestrian climbing out of a car, which is where the third roll came
## from.
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

## The chance, per roll, that one of the parked cars backs out and leaves: at
## level one, per level after that, and the ceiling it climbs to.
##
## Nothing in the source escalates but the clock and the number of parked cars,
## which makes its level twenty a level one in a hurry. These are what make a
## later lot a busier one rather than only a fuller one. A round at level one is
## five or six rolls long, so a fifth of a chance each is about one car leaving
## per round; at the ceiling it is most rounds, twice.
const DEPARTURE_CHANCE := 0.20
const DEPARTURE_CHANCE_PER_LEVEL := 0.08
const DEPARTURE_CHANCE_MAX := 0.75

## The same, for a rival driving in off the road to take a space. It starts
## lower than a departure and climbs faster: a car leaving is a gift and a rival
## is a tax, and the tax is what the levels are for.
const ARRIVAL_CHANCE := 0.15
const ARRIVAL_CHANCE_PER_LEVEL := 0.10
const ARRIVAL_CHANCE_MAX := 0.85

## The chance a rival goes for the free space nearest the player rather than any
## free space at all. In an empty lot a rival that picks at random takes a bay
## the player was never going to reach; this is what makes it a competitor rather
## than scenery, so it climbs too.
const RIVAL_FOCUS_CHANCE := 0.25
const RIVAL_FOCUS_PER_LEVEL := 0.15
const RIVAL_FOCUS_MAX := 0.9

## How many living things are already crossing the lot when a round starts, how
## many more each level adds, and the most that may be walking at once.
##
## [b]Every level has them[/b], which is the difference between this and the two
## dice above: a lot with nobody in it is a lot you can take at speed, and the
## whole point of a pedestrian is that you cannot. What the levels add is how
## many of them there are, and how often another one steps out while you are
## already parking.
const WALKERS_AT_LEVEL_ONE := 2
const WALKERS_PER_LEVEL := 1
const WALKERS_MAX := 6

## The chance, per roll, that another crossing starts mid-round.
const WALKER_CHANCE := 0.30
const WALKER_CHANCE_PER_LEVEL := 0.10
const WALKER_CHANCE_MAX := 0.80

## The chance a crossing is wildlife rather than somebody on foot, and how many
## geese a gaggle is. A gaggle counts as several of [constant WALKERS_MAX], so
## wildlife fills the lot faster than people do -- which is the point of a
## goose.
const WILDLIFE_CHANCE := 0.35
const GAGGLE_MIN := 2
const GAGGLE_MAX := 4

## How many cars may be driving themselves around the lot at once, at level one,
## and how many levels buy another one.
##
## A cap rather than a chance, and a low one. Every car under its own power is a
## car the player can be hit by, and three of them in a twenty-bay lot is already
## a lot to keep an eye on.
const ACTIVE_DRIVERS := 1
const LEVELS_PER_EXTRA_DRIVER := 2
const ACTIVE_DRIVERS_MAX := 3


## The chance, per roll, of a parked car leaving at [param level].
static func departure_chance(level: int) -> float:
	return _chance(DEPARTURE_CHANCE, DEPARTURE_CHANCE_PER_LEVEL, DEPARTURE_CHANCE_MAX, level)


## The chance, per roll, of a rival arriving at [param level].
static func arrival_chance(level: int) -> float:
	return _chance(ARRIVAL_CHANCE, ARRIVAL_CHANCE_PER_LEVEL, ARRIVAL_CHANCE_MAX, level)


## The chance a rival at [param level] goes for the space the player is nearest.
static func rival_focus_chance(level: int) -> float:
	return _chance(RIVAL_FOCUS_CHANCE, RIVAL_FOCUS_PER_LEVEL, RIVAL_FOCUS_MAX, level)


## How many living things a round at [param level] starts with.
static func walkers_for_level(level: int) -> int:
	var extra := maxi(level, 1) - 1
	return clampi(WALKERS_AT_LEVEL_ONE + extra * WALKERS_PER_LEVEL, 0, WALKERS_MAX)


## The chance, per roll, of another crossing starting at [param level].
static func walker_chance(level: int) -> float:
	return _chance(WALKER_CHANCE, WALKER_CHANCE_PER_LEVEL, WALKER_CHANCE_MAX, level)


## How many cars may be driving themselves at [param level].
static func active_driver_limit(level: int) -> int:
	var extra := maxi(level - 1, 0) / LEVELS_PER_EXTRA_DRIVER
	return clampi(ACTIVE_DRIVERS + extra, ACTIVE_DRIVERS, ACTIVE_DRIVERS_MAX)


## One straight line and a ceiling, counted from level one -- the same off-by-one
## the clock had: a level reached by a reset and a level the game booted into
## have to be the same level.
static func _chance(base: float, per_level: float, ceiling: float, level: int) -> float:
	return clampf(base + float(maxi(level, 1) - 1) * per_level, 0.0, ceiling)
