class_name NpcDriver
extends Node
## Drives one car that nobody is sitting in: out of its bay and off the lot, or
## in off the road and into a space before the player gets there.
##
## [b]It does not simulate the car.[/b] The car it drives is frozen, the same as
## every other parked car in the lot, and this moves its transform. Three reasons,
## in the order they matter:
##
## - A lot full of live [VehicleBody3D]s is the first thing to sink the web
##   build; [TrafficSpawner] freezes its cars for exactly that reason, and a
##   driving car has no better claim on a suspension simulation than a parked one.
## - A car steered by a controller arrives where the physics puts it. A car
##   parking itself has to end up [i]between the lines[/i], which is the one
##   thing the round measures, and "usually" is not good enough for something
##   that happens behind the player every ten seconds.
## - What it costs is a car that cannot be shoved out of its bay by the player.
##   That is a loss, and it is the right one to take: the alternative is a lot
##   whose furniture drifts.
##
## The car is frozen [constant RigidBody3D.FREEZE_MODE_KINEMATIC] rather than the
## static freeze a parked car gets, so it still pushes the player's car around
## rather than standing through it.
##
## [b]The lot is flat where cars drive[/b], so a car holds the height it started
## at for the whole trip. A car leaving already settled onto its own suspension
## when it was parked; a car arriving is given the ride height measured off a car
## of the same chassis that did -- see [method TrafficSpawner.ride_height]. A lot
## with a ramp in it would need a ground query here instead.

## Which way this car is going.
enum Intent {
	LEAVING, ## Out of a bay and off the lot. The car is freed at the gate.
	ARRIVING, ## In off the road and into a bay, where it becomes parked furniture.
}

enum Phase {
	DRIVING, ## Following the plan.
	ALIGNING, ## In the bay, straightening up over the last few centimetres.
	DONE, ## [signal finished] has been emitted; nothing moves again.
}

## The trip is over. [param driver] carries [member intent] and [member bay], and
## whoever started it decides what the car is now -- parked furniture, or gone.
signal finished(driver: NpcDriver)

## Metres per second down an aisle, and while getting in or out of a bay. A lot
## is not a road: the source's parked cars never move at all, so both of these
## are what looks right rather than what was ported.
const CRUISE_SPEED := 6.0
const MANOEUVRE_SPEED := 2.2
const ACCELERATION := 4.5
## Braking is what the arrival curve is computed against, so it is the number
## that decides how early a car starts slowing for its bay.
const BRAKING := 7.0

## The tightest circle a car will turn, in metres, and the fastest it will turn
## whatever its speed. A real car's steering lock fixes its radius, not its yaw
## rate: 3.08 m of wheelbase at this chassis's 31 degrees of lock is a 5 m circle
## at any speed at all. Four is a little tighter than the car can really manage
## and keeps a rival from taking half the aisle to get into a space.
const MIN_TURN_RADIUS := 4.0
const MAX_TURN_RATE := 0.9

## Close enough to a waypoint to be done with it.
const ARRIVE_RADIUS := 0.4
## ...and close enough, if the car has stopped anyway. A car that stops a hand's
## width outside the radius is a car that has arrived and a plan that never
## advances again.
const STOPPED_RADIUS := 1.5
const STOPPED_SPEED := 0.05
## How far past its closest approach a car will chase a waypoint before giving up
## on it.
##
## [b]A waypoint inside the car's own turning circle cannot be reached[/b], and a
## car chasing one drives round and round it forever -- which is what the first
## version of the manoeuvre out of a bay did, in a tidy four-metre circle, until
## the round ended. The legs are laid out so it should not happen; this is what
## makes it a scruffy exit rather than a car that never leaves.
const GIVE_UP_MARGIN := 2.0

## Pointing close enough down the aisle to stop turning and start driving.
const HEADING_TOLERANCE := 0.12

## A car slows for a corner rather than cornering at whatever speed it arrived
## with: full speed when it is pointing where it is going, this fraction of it
## when it is pointing a right angle away.
##
## Only where it is crossing the lot. A car getting out of a bay is turning
## because turning is the whole errand, and one that slowed down for that turn
## would turn slower for it -- the tighter circle a slow car can hold is not
## worth having when it is the yaw rate you are waiting on.
const TURN_SLOWDOWN := 0.35

## How much of the aisle ahead a car keeps clear of the player's car, and how far
## ahead of itself it looks for it.
##
## [b]A rival that hits the player costs the player a grade[/b] -- collisions are
## scored on the player's own [signal PlayerCar.hit_obstacle], which does not ask
## who drove into whom. A car with nobody in it yielding to one with somebody in
## it is the cheap way to keep the lot lively without making it unfair.
const YIELD_RADIUS := 4.5
const YIELD_LOOKAHEAD := 3.5

## Seconds spent straightening up once the car is in its bay.
const ALIGN_SECONDS := 0.35
## How far a rival parks from perfect: metres off the middle and degrees off
## square. A lot of cars parked to the millimetre looks stamped out, and a rival
## that parks better than the player can is a rival worth resenting.
const RIVAL_SLOPPINESS := 0.22
const RIVAL_SKEW_DEGREES := 3.5

## One step of a plan: somewhere to get to, or something to end up pointing at.
##
## [b]Both, because a car park is both.[/b] Crossing a lot is going somewhere, and
## a waypoint says it exactly. Getting out of a bay is not: what a driver is doing
## there is turning the car until it points down the aisle, and the point it
## arrives at is whatever falls out of that. Written as a waypoint it is a
## waypoint a car cannot reach -- too far to the side and too close to the nose --
## and a car that cannot reach a waypoint circles it.
class Leg extends RefCounted:
	## Where the car is going, for a leg that has somewhere to be.
	var point := Vector3.ZERO
	## What the car is turning to point at, for a leg that is a manoeuvre.
	## Zero means this is a waypoint leg.
	var turn_to := Vector3.ZERO
	## How far a manoeuvre may take before the car settles for where it got to.
	var limit := 0.0
	## Whether the car gets there backwards.
	var reverse := false
	## Whether the car holds the heading it has. Straight out of a bay is the
	## only place it does: a car that starts turning before its nose is clear of
	## the paint sweeps the cars parked next door.
	var straight := false
	## Whether to slow down for a corner. See [constant TURN_SLOWDOWN].
	var eases := true
	var speed := 0.0

	## A leg that goes somewhere.
	static func to_point(to: Vector3, at: float, backwards := false, locked := false) -> Leg:
		var leg := Leg.new()
		leg.point = to
		leg.speed = at
		leg.reverse = backwards
		leg.straight = locked
		return leg

	## A leg that turns until the car points at [param facing], for at most
	## [param within] metres.
	static func to_heading(facing: Vector3, at: float, within: float, backwards := false) -> Leg:
		var leg := Leg.new()
		leg.turn_to = facing
		leg.speed = at
		leg.limit = within
		leg.reverse = backwards
		leg.eases = false
		return leg


## The car being driven. Handed over already spawned and placed.
var car: PlayerCar = null
## Where it is coming out of, or going into.
var bay: ScoredParkingSpace = null
var intent: Intent = Intent.LEAVING
## The lot's lanes and gates.
var geometry: LotGeometry = null
## Yielded to, never scored against. May be null in a lot with no player in it.
var player: PlayerCar = null
## The round's generator, so a rival's sloppiness is part of the same seeded
## stream as everything else.
var rng: RandomNumberGenerator = null

var phase: Phase = Phase.DRIVING
## True while the car is holding still for the player, which is the one thing
## that stops a plan making progress.
var yielding: bool = false

var _legs: Array[Leg] = []
var _leg: int = 0
## How far the car has gone on this leg, and the closest it has been to the end
## of it. Both are how a leg ends when it cannot end the way it meant to.
var _leg_travel: float = 0.0
var _leg_closest: float = INF
var _position := Vector3.ZERO
var _heading := Vector3.FORWARD
var _speed: float = 0.0
var _steer: float = 0.0
## The height the car drives at, measured rather than assumed.
var _height: float = 0.0
var _align_left: float = 0.0
var _align_from := Transform3D.IDENTITY
var _align_to := Transform3D.IDENTITY


## Takes control of [param of_car] and points it at the lot. Called before the
## driver enters the tree; [method leave] or [method arrive] gives it its plan.
func configure(
		of_car: PlayerCar,
		lot: LotGeometry,
		player_car: PlayerCar,
		generator: RandomNumberGenerator) -> void:
	car = of_car
	geometry = lot
	player = player_car
	rng = generator
	if car == null:
		return
	# Kinematic rather than the static freeze parked cars get: this one is going
	# to move, and a static body that moves passes through whatever it meets
	# instead of shoving it.
	car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.freeze = true
	car.input_enabled = false
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	# The car's own _process drives its wheel visuals off wheels that are not
	# being simulated any more. This drives them instead.
	car.set_process(false)
	car.set_physics_process(false)
	_position = car.global_position
	_height = _position.y
	_heading = LotGeometry.flat(-car.global_basis.z)
	if _heading == Vector3.ZERO:
		_heading = Vector3.FORWARD


## Backs out of [param from_bay] and leaves the lot.
func leave(from_bay: ScoredParkingSpace) -> void:
	bay = from_bay
	intent = Intent.LEAVING
	phase = Phase.DRIVING
	# Which way the car is pointing decides whether it backs out or noses out,
	# and the spawner parks them both ways round on purpose.
	var reversing := _heading.dot(geometry.aisle_axis(bay)) < 0.0
	_legs = [
		# Straight out until the far end of the car has cleared the paint...
		Leg.to_point(geometry.clearance_point(bay), MANOEUVRE_SPEED, reversing, true),
		# ...then keep going the same way, turning, until it is pointing at the
		# way out. A car reversing swings its tail away from the gate to do that,
		# which is what leaves its nose facing it.
		Leg.to_heading(
				geometry.gate_direction(), MANOEUVRE_SPEED,
				LotGeometry.EXIT_SWING_LIMIT, reversing),
		Leg.to_point(geometry.gate_point(bay), CRUISE_SPEED),
	]
	_restart_leg(0)


## Drives to [param to_bay] and parks in it. Also how a rival is sent after a
## different space when the one it wanted is taken.
func arrive(to_bay: ScoredParkingSpace) -> void:
	bay = to_bay
	intent = Intent.ARRIVING
	phase = Phase.DRIVING
	_legs = [
		Leg.to_point(geometry.turn_in_point(bay), CRUISE_SPEED),
		Leg.to_point(bay.bay_centre(), MANOEUVRE_SPEED),
	]
	# The plan is rebuilt from wherever the car is now, so this is also the
	# retarget: a rival already halfway down the aisle picks the new bay up from
	# there. It only works for a bay it has not passed yet, which is why
	# [LotEvents] hands it one that is still ahead of it.
	_restart_leg(0)


## Gives up on parking and leaves the lot -- there was nowhere left to put it.
func give_up() -> void:
	intent = Intent.LEAVING
	phase = Phase.DRIVING
	_legs = [Leg.to_point(geometry.gate_point(bay), CRUISE_SPEED)]
	_restart_leg(0)


## Stops the car where it stands, for good. The round is over and the world holds
## still while the card is up.
func hold() -> void:
	_speed = 0.0
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	match phase:
		Phase.DRIVING:
			_drive(delta)
		Phase.ALIGNING:
			_align(delta)
		Phase.DONE:
			set_physics_process(false)


func _drive(delta: float) -> void:
	if car == null or not is_instance_valid(car) or _legs.is_empty():
		_finish()
		return
	var leg := _legs[_leg]
	var distance := Vector2(leg.point.x - _position.x, leg.point.z - _position.z).length()
	var error := _heading_error(leg, distance)

	yielding = _player_in_the_way(leg)
	var target_speed := 0.0
	if not yielding:
		target_speed = leg.speed
		if leg.eases:
			target_speed *= lerpf(
					1.0, TURN_SLOWDOWN, clampf(absf(error) / (PI * 0.5), 0.0, 1.0))
			# Arrive at the next leg's speed rather than at this one's, so a car
			# comes off the aisle at a walking pace instead of taking the corner
			# at six metres a second.
			var next_speed := _legs[_leg + 1].speed if _leg + 1 < _legs.size() else 0.0
			var room := maxf(distance - ARRIVE_RADIUS, 0.0)
			target_speed = minf(target_speed, next_speed + sqrt(2.0 * BRAKING * room))

	var rate := ACCELERATION if target_speed > _speed else BRAKING
	_speed = move_toward(_speed, target_speed, rate * delta)

	# Steering lock, not yaw rate: how fast a car can turn is how fast it is
	# going, divided by the tightest circle it can hold.
	var turn_rate := minf(_speed / MIN_TURN_RADIUS, MAX_TURN_RATE)
	var turn := clampf(error, -turn_rate * delta, turn_rate * delta)
	_heading = _heading.rotated(Vector3.UP, turn).normalized()
	# The front wheels point where the turn is coming from, which is the other
	# way round when the car is reversing.
	_steer = clampf(turn / maxf(turn_rate * delta, 0.0001), -1.0, 1.0) \
			* car.max_steer * (-1.0 if leg.reverse else 1.0)

	var travelled := _speed * delta * (-1.0 if leg.reverse else 1.0)
	_position += _heading * travelled
	_position.y = _height
	_leg_travel += absf(travelled)
	_leg_closest = minf(_leg_closest, distance)
	_apply(travelled)

	if _leg_is_done(leg, distance, error):
		_advance()


## Where the car wants to be pointing, as an angle off where it is pointing.
##
## A manoeuvre leg says so outright. A waypoint leg works it out: at the
## waypoint, pointing at it -- or away from it, for a car reversing towards one.
func _heading_error(leg: Leg, distance: float) -> float:
	if leg.straight:
		return 0.0
	var desired := leg.turn_to
	if desired == Vector3.ZERO:
		var to_target := LotGeometry.flat(leg.point - _position)
		if to_target == Vector3.ZERO or distance < ARRIVE_RADIUS:
			return 0.0
		desired = -to_target if leg.reverse else to_target
	return _heading.signed_angle_to(desired, Vector3.UP)


## Whether this leg is behind the car now. Three ways, and the third is the one
## that matters when the geometry did not work out.
func _leg_is_done(leg: Leg, distance: float, error: float) -> bool:
	if leg.turn_to != Vector3.ZERO:
		return absf(error) <= HEADING_TOLERANCE or _leg_travel >= leg.limit
	if distance <= ARRIVE_RADIUS:
		return true
	# Stopped as close as it is going to get.
	if not yielding and _speed <= STOPPED_SPEED and distance <= STOPPED_RADIUS:
		return true
	# ...or circling something it cannot reach.
	return distance > _leg_closest + GIVE_UP_MARGIN


## On to the next waypoint, or the end of the trip.
func _advance() -> void:
	_restart_leg(_leg + 1)
	if _leg < _legs.size():
		return
	if intent == Intent.ARRIVING:
		_start_aligning()
		return
	_finish()


func _restart_leg(index: int) -> void:
	_leg = index
	_leg_travel = 0.0
	_leg_closest = INF


## The last few centimetres, done by hand. A car that drove itself into a bay
## arrives within a hand's width of square, and a hand's width is exactly what
## the round grades on -- so the pose it settles into is the one the geometry
## says, not the one the arc happened to end on.
func _start_aligning() -> void:
	phase = Phase.ALIGNING
	_align_left = ALIGN_SECONDS
	_align_from = car.global_transform
	_align_to = geometry.parked_transform(bay, _height)
	if rng != null:
		var skew := deg_to_rad(rng.randf_range(-RIVAL_SKEW_DEGREES, RIVAL_SKEW_DEGREES))
		var drift := rng.randf_range(-RIVAL_SLOPPINESS, RIVAL_SLOPPINESS)
		_align_to.basis = _align_to.basis.rotated(Vector3.UP, skew)
		_align_to.origin += geometry.row_axis() * drift


func _align(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		_finish()
		return
	_align_left -= delta
	if _align_left <= 0.0:
		car.global_transform = _align_to
		_finish()
		return
	var t := 1.0 - clampf(_align_left / ALIGN_SECONDS, 0.0, 1.0)
	car.global_transform = _align_from.interpolate_with(_align_to, t)


func _finish() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	_speed = 0.0
	set_physics_process(false)
	finished.emit(self)


## Whether the player's car is in the bit of lot this one is about to occupy.
##
## Measured against a point ahead of the car rather than the car itself, so a
## driver stops short of the player rather than at the moment of contact, and
## against the direction it is actually travelling, so a car reversing out of a
## bay yields to a player behind it.
func _player_in_the_way(leg: Leg) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var travel := _heading * (-1.0 if leg.reverse else 1.0)
	var ahead := _position + travel * YIELD_LOOKAHEAD
	var to_player := player.global_position - ahead
	return Vector2(to_player.x, to_player.z).length() < YIELD_RADIUS


func _apply(travelled: float) -> void:
	car.global_transform = Transform3D(Basis.looking_at(_heading, Vector3.UP), _position)
	car.roll_wheel_visuals(travelled, _steer)
