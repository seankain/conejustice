class_name ScoredParkingSpace
extends Node3D
## A bay that watches the player park in it: how square the car is, how far off
## the middle, whether it is sitting on either painted line, and when it has
## finally stopped moving.
##
## Not [ParkingSpace], which is Cone Justice's and is a different thing -- a
## painted bay the lot parks a car into, which measures a pose once at spawn
## time to decide whether that car is a violator. This one measures the player,
## continuously, and its measurements end the round. [code]class_name[/code] is
## global in GDScript, so the two could not share a name even if they wanted to.
##
## It measures and reports. It does not grade -- that is [RoundData] -- and it
## does not write the round's score, which the source does from inside
## [code]_Process[/code] on every frame the player is in the bay.
##
## [b]Axes.[/b] The bay runs along its own local X: a car parked properly points
## along ±X, and both directions are equally legal, so the angle folds at 90
## degrees. The source arrives at the same number by comparing the car's -Z
## against the bay's +Z and subtracting 90, which reads as a magic number and is
## really just the angle between two perpendicular axes.
##
## The source's other two pieces of machinery are gone. Its
## [code]ParkingSpaceArea[/code] is a second node whose only job is to relay
## [signal Area3D.body_entered] up to this script -- its own TODO calls it "a
## needless subcomponent" -- and its four corner posts are exported, placed, and
## never read by anything.

## Every bay joins this, so the round can find them without being handed a list
## and a restart can clear all of them.
const GROUP := &"scored_parking_spaces"

## The player drove into this bay.
signal player_entered(car: PlayerCar)
## ...and left it again, without having stopped.
signal player_exited(car: PlayerCar)
## Fresh measurements, while the player is inside. The round writes these into
## its [RoundData]; nothing is graded here.
signal measured(angle: float, centre_distance: float, over_left: bool, over_right: bool)
## The player stopped inside the bay. This is what ends a round -- and it is
## emitted again if the car moves off and comes to rest here a second time,
## because a bay that reported a stop nobody was listening for is a bay the
## round can never end in.
signal player_settled(car: PlayerCar)

@export_group("Nodes")
## The bay volume. Entering it starts the measuring, and its overlapping bodies
## are what [method has_parked_car] reads.
@export var bay: Area3D
## The painted line on each side. Sitting on one costs a grade.
@export var left_line: Area3D
@export var right_line: Area3D
## Where somebody climbs out of a car parked here. Only its distance from the
## bay is read -- see [method door_distance].
@export var npc_spawn_point: Node3D

@export_group("Settling")
## Metres per second across the ground under which the car counts as stopped.
## The source uses 0.02 m/s of total velocity, found by logging because its car
## idles forward forever; this one brakes to a stop on its own, and asks for
## ground speed so a settling suspension does not read as a moving car.
@export var settle_speed: float = 0.2
## Seconds the car has to stay under [member settle_speed] before the round
## ends. The source ends the level the first frame the speed dips below its
## threshold, which a car passing through zero on its way from forward to
## reverse does in the middle of a three-point turn.
@export var settle_time: float = 0.5

## The car being measured, or null when the bay is empty.
var car: PlayerCar = null
## Whether the car is currently over each painted line.
var over_left_line: bool = false
var over_right_line: bool = false
## Whether the car in this bay has come to rest in it. A state rather than a
## signal the bay fires once and forgets: a car sitting astride a line comes to
## rest in two bays at once, only one of which is being scored, and the other
## one has to still know it is parked in if the round turns to it.
var settled: bool = false

var _settled_for: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	if bay == null or left_line == null or right_line == null:
		push_error("ScoredParkingSpace %s: bay and both lines must be set." % name)
		set_process(false)
		return
	bay.body_entered.connect(_on_bay_entered)
	bay.body_exited.connect(_on_bay_exited)
	left_line.body_entered.connect(_on_line_entered.bind(true))
	left_line.body_exited.connect(_on_line_exited.bind(true))
	right_line.body_entered.connect(_on_line_entered.bind(false))
	right_line.body_exited.connect(_on_line_exited.bind(false))
	set_process(false)


func _process(delta: float) -> void:
	if car == null:
		return
	measured.emit(parking_angle(car), centre_distance(car), over_left_line, over_right_line)

	# Asked of the car's ground speed, not its whole velocity: see
	# [method PlayerCar.ground_speed].
	if car.ground_speed() > settle_speed:
		_settled_for = 0.0
		settled = false
		return
	_settled_for += delta
	if _settled_for >= settle_time and not settled:
		settled = true
		player_settled.emit(car)


## Degrees between the car and the bay's own axis, folded at 90 so a car backed
## in is as square as one nosed in. Zero is perfectly aligned.
##
## Measured flat: a car sitting on a kerb is not thereby parked crookedly.
func parking_angle(for_car: Node3D) -> float:
	var axis := _flat(global_basis.x)
	var forward := _flat(-for_car.global_basis.z)
	if axis == Vector3.ZERO or forward == Vector3.ZERO:
		return 0.0
	var degrees := rad_to_deg(forward.angle_to(axis))
	return minf(degrees, 180.0 - degrees)


## Metres from the middle of the bay, measured flat.
##
## The source measures to the bay node's origin in three dimensions, which sits
## off to one end of the painted box and picks up the car's ride height as a
## constant error. This measures to the middle of the painted bay, on the
## ground.
func centre_distance(for_car: Node3D) -> float:
	var centre := bay_centre()
	var offset := for_car.global_position - centre
	return Vector2(offset.x, offset.z).length()


## The middle of the painted bay, in world space.
func bay_centre() -> Vector3:
	var shape := bay.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape == null:
		return bay.global_position
	return shape.global_position


## Whether one of the lot's parked cars is already in this bay. Read before a
## round fills the lot, so two cars never share a bay, and by [LotEvents] to find
## the spaces still going.
##
## [param except_car] is left out of the answer, for the one caller that is a car
## in a bay asking whether anybody [i]else[/i] is in it -- a rival parking itself
## would otherwise find the space taken the moment it drove into it.
func has_parked_car(except_car: Node3D = null) -> bool:
	for body in bay.get_overlapping_bodies():
		if body != except_car and body.is_in_group(&"npc_vehicles"):
			return true
	return false


## How far out of the bay somebody getting out of a car here stands, in metres.
## Zero when the bay has no marker for it.
##
## [b]Which side the marker is on is not part of the answer.[/b] Every bay in a
## lot is the same scene, so the marker sits on the same local side of all of
## them -- which is the aisle for one row of bays and the kerb for the other.
## How far the door is belongs to the bay; which way is out belongs to
## [LotGeometry].
func door_distance() -> float:
	if npc_spawn_point == null:
		return 0.0
	var offset := npc_spawn_point.global_position - bay_centre()
	return Vector2(offset.x, offset.z).length()


## Forgets the player and stops measuring. Called when a round ends, so a bay
## the player stopped in does not keep reporting into the next one.
func clear() -> void:
	car = null
	over_left_line = false
	over_right_line = false
	settled = false
	_settled_for = 0.0
	set_process(false)


func _on_bay_entered(body: Node3D) -> void:
	# By group, not by type: the lot's parked cars are the same scene as the
	# player's, and a bay filled by the spawner must not start scoring it.
	if not body.is_in_group(PlayerCar.GROUP):
		return
	var entering := body as PlayerCar
	if entering == null:
		return
	car = entering
	settled = false
	_settled_for = 0.0
	set_process(true)
	player_entered.emit(entering)


func _on_bay_exited(body: Node3D) -> void:
	if body != car:
		return
	var leaving := car
	clear()
	player_exited.emit(leaving)


func _on_line_entered(body: Node3D, left: bool) -> void:
	if not body.is_in_group(PlayerCar.GROUP):
		return
	if left:
		over_left_line = true
	else:
		over_right_line = true


func _on_line_exited(body: Node3D, left: bool) -> void:
	if not body.is_in_group(PlayerCar.GROUP):
		return
	if left:
		over_left_line = false
	else:
		over_right_line = false


## [param vector] flattened onto the ground plane.
func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z).normalized()
