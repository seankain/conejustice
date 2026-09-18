class_name LotGeometry
extends RefCounted
## Which way is out of a bay, where the lanes run, and where cars come in from.
##
## A [ScoredParkingSpace] knows where its own paint is and which way a car in it
## should be pointing. It does not know which of its two ends is the aisle and
## which is the kerb, because until a car had to drive itself out of one, nothing
## needed to: the player can see the lot, and [TrafficSpawner] drops its cars in
## from above.
##
## [b]It is worked out from the bays rather than authored onto them.[/b] The
## alternative is twenty inspector overrides in [code]Lot.tscn[/code] that have
## to be right and that nothing checks; the bays' own positions already say where
## the aisle is, so this reads it off them. Two assumptions come with that, and
## [code]Tools/test_lot_events.tscn[/code] checks both against the real lot:
##
## - [b]One aisle, and the bays face it.[/b] A bay's aisle side is the side its
##   own middle looks at when it looks at the middle of the lot. Two rows facing
##   each other, which is this lot, resolve correctly; a lot with two aisles
##   would need the bays grouped per aisle first.
## - [b]The rows run one way.[/b] Every bay's row axis is taken from the first
##   bay's, so a lot whose rows are not parallel would need the same grouping.
##
## The one thing it does not give is where a car ends up when it turns out of a
## bay. That is a manoeuvre rather than a destination -- see [NpcDriver] -- and
## the point it finishes at is whatever falls out of the turn.
##
## Distances are in metres and were picked against this lot's aisle, which is
## 10.9 m between the two rows of paint. They are the numbers to turn down for a
## tighter lot -- see [member LANE_OFFSET] in particular.

## How far out from the middle of a bay a driving lane runs. Far enough that a
## car leaving can swing its nose clear of the bay it is backing out of: the
## paint ends 3.24 m out and a car is about 2.25 m from its middle to its nose,
## so anything under 5.5 m has it sweeping the cars parked next door.
##
## Two rows 17.35 m apart put the two lanes 5.35 m apart with this, which is one
## lane per row and room between them.
const LANE_OFFSET := 6.0

## How far straight out of the bay a car goes before it starts turning. The same
## 5.49 m of nose clearance, rounded up.
const BAY_CLEARANCE := 5.5

## The most a car may travel, in metres, turning itself to face down the aisle
## after it has come out of its bay. A quarter circle at the tightest a car turns
## is about six metres of it; past eight, something has gone wrong and the car
## takes whatever heading it has and drives off with it.
const EXIT_SWING_LIMIT := 8.0

## How far short of a bay a car arriving for it starts turning in. A car cannot
## turn in from level with the bay any more than a player can: at the lane's
## 6 m, the arc that puts a car square between the lines starts about a bay and a
## half before it.
const TURN_IN_LEAD := 5.0

## How far past the [i]turn-in point[/i] of the last bay in a row the lot's gate
## sits -- where arriving cars come in, and where leaving cars stop being
## anything the round has to think about.
##
## Past the turn-in point rather than past the bay, which is what it was at first
## and which put the gate for the row's end bay [i]inside[/i] the run-up to it: a
## rival came in already past the point it was supposed to turn at, could not
## reach a bay a car's length behind it, and drove a slow circle in the middle of
## the aisle before coming back for it. Every bay gets its whole run-up now.
const GATE_MARGIN := 2.0

## The bays this was built from, in the order they were handed over.
var bays: Array[ScoredParkingSpace] = []

## The middle of every bay, which is what "the middle of the lot" means here.
var _centre := Vector3.ZERO
## The direction a row of bays runs in, lot-wide.
var _row := Vector3.FORWARD
## Which end of the row the lot is entered from: -1 or +1 along [member _row].
var _gate_sign := -1.0
## How far along [member _row] the gate is, as a projection onto it.
var _gate_coordinate := 0.0


## [param for_bays] is every bay in the lot. [param entrance] is somewhere cars
## come into the lot from -- the player's own respawn marker, for want of a
## better authority on which end of the lot is the front. Left out, the low end
## of the row is used.
func _init(for_bays: Array[ScoredParkingSpace], entrance: Vector3 = Vector3.INF) -> void:
	bays = for_bays.duplicate()
	if bays.is_empty():
		return
	for bay in bays:
		_centre += bay.bay_centre()
	_centre /= float(bays.size())
	_row = flat(bays[0].global_basis.z)
	if _row == Vector3.ZERO:
		_row = Vector3.FORWARD

	var low := INF
	var high := -INF
	for bay in bays:
		var along := bay.bay_centre().dot(_row)
		low = minf(low, along)
		high = maxf(high, along)
	if entrance.is_finite():
		_gate_sign = signf((entrance - _centre).dot(_row))
	if is_zero_approx(_gate_sign):
		_gate_sign = -1.0
	var beyond := TURN_IN_LEAD + GATE_MARGIN
	_gate_coordinate = (low - beyond) if _gate_sign < 0.0 else (high + beyond)


## The way out of [param bay]: the flat unit vector from the middle of the bay
## towards the aisle, along the bay's own axis.
func aisle_axis(bay: ScoredParkingSpace) -> Vector3:
	var axis := flat(bay.global_basis.x)
	if axis == Vector3.ZERO:
		return Vector3.RIGHT
	# The aisle is the side the middle of the lot is on. A bay whose middle is
	# the middle of the lot -- a single row -- gets its own +X, which is as good
	# an answer as the lot has given.
	if (_centre - bay.bay_centre()).dot(axis) < 0.0:
		return -axis
	return axis


## The direction the row of bays runs in, lot-wide.
func row_axis() -> Vector3:
	return _row


## The way out of the lot, along the row.
func gate_direction() -> Vector3:
	return _row * _gate_sign


## A point in [param bay]'s lane, [param along] metres towards the gate from the
## bay itself.
func lane_point(bay: ScoredParkingSpace, along: float = 0.0) -> Vector3:
	return bay.bay_centre() + aisle_axis(bay) * LANE_OFFSET + gate_direction() * along


## Straight out of [param bay], far enough that the car's far end has cleared the
## paint. The first thing a car leaving does, and the only part of leaving that
## happens in a straight line.
func clearance_point(bay: ScoredParkingSpace) -> Vector3:
	return bay.bay_centre() + aisle_axis(bay) * BAY_CLEARANCE


## Where a car arriving for [param bay] leaves the lane and starts turning in:
## in the lane, [constant TURN_IN_LEAD] short of the bay.
func turn_in_point(bay: ScoredParkingSpace) -> Vector3:
	return lane_point(bay, TURN_IN_LEAD)


## Where [param bay]'s lane meets the edge of the lot: where a car arriving for
## it comes in, and where a car leaving it stops mattering.
func gate_point(bay: ScoredParkingSpace) -> Vector3:
	var lane := lane_point(bay)
	return lane + _row * (_gate_coordinate - lane.dot(_row))


## The pose a car parked properly in [param bay] has: dead centre, square, and
## nosed in. [param height] is the ride height the car is being driven at, which
## is measured rather than assumed -- see [NpcDriver].
func parked_transform(bay: ScoredParkingSpace, height: float) -> Transform3D:
	var spot := bay.bay_centre()
	spot.y = height
	return Transform3D(Basis.looking_at(-aisle_axis(bay), Vector3.UP), spot)


## [param vector] flattened onto the ground plane, as a unit vector.
static func flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z).normalized()
