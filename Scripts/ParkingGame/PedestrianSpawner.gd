class_name PedestrianSpawner
extends Node
## The living half of the lot's traffic: people walking in from their cars, and
## geese crossing the aisle because it is there.
##
## The same shape as [TrafficSpawner], and deliberately separate from it. That
## one owns bodies that are furniture -- parked, frozen, and handed back and
## forth with [NpcDriver]. This one owns bodies that are hazards, and a hazard's
## whole lifetime is one crossing: it is spawned at one side, it walks, and it
## is freed when it gets where it was going. Nothing ever adopts one back.
##
## [b]Where a crossing runs is read off the lot, not authored onto it[/b], the
## same way [LotGeometry] works out where the aisle is. A person gets out of a
## car on the aisle side of the bay and walks to the building entrance, which
## puts them across at least one driving lane. A gaggle crosses from one side of
## the aisle to the other, which puts them across both. Neither needs a marker
## per route, so a second lot costs no authoring beyond its bays.
##
## Two things this does not do, which the real models will want:
##
## - [b]It does not path around parked cars.[/b] The navigation mesh is baked
##   from the empty lot -- see [constant Pedestrian.STUCK_SECONDS], which is how
##   a walker that has wedged itself against a bumper gets taken away instead.
## - [b]It does not have them avoid each other.[/b] The agents' avoidance is
##   off, so a gaggle going the same way jostles. On a goose that reads as a
##   goose; it will not on anything with legs.

## Where people on foot are walking to: the node a lot marks its building
## entrance with. One per lot, and a lot without one sends them out of the gate
## instead. Declared in [code]project.godot[/code].
const DESTINATION_GROUP := &"building_entrance"

## Metres a pedestrian is spawned above the tarmac, so it lands on it rather
## than being pushed out of it. The same trick [TrafficSpawner] parks cars with,
## at a tenth of the drop.
const SPAWN_HEIGHT := 0.15

## How far from the player's car a crossing has to start. A pedestrian that
## appeared inside the car would be a grade the player never had a chance to
## keep.
const CLEAR_OF_PLAYER := 6.0
## How many bays to try before giving up on finding a crossing that is clear of
## the player.
const PLACEMENT_TRIES := 6

## How far apart the members of a gaggle start, across the direction they are
## walking and along it.
const GAGGLE_SPREAD := 1.1
const GAGGLE_STAGGER := 0.9

## What to spawn. An empty catalog is a lot with nobody in it, not an error.
var catalog: PedestrianCatalog = null
## The round's generator, seeded once and shared with the rest of the lot.
var rng: RandomNumberGenerator = null
## Never scored against, only kept clear of when a crossing starts.
var player: PlayerCar = null

## Off empties the lot of everything living and keeps it that way -- what the
## round's [member ParkingRound.pedestrians_enabled] switches, and what the
## round-flow test wants while it measures a park.
var enabled: bool = true

var _bays: Array[ScoredParkingSpace] = []
var _geometry: LotGeometry = null
var _level: int = 1
## Where people on foot are headed: the building entrance, if the lot has one.
var _destination := Vector3.INF
var _living: Array[Pedestrian] = []


## Starts a round's worth of crossings. Called after the lot has been filled, so
## a crossing never starts in a bay a car is about to be dropped into.
func begin(
		bays: Array[ScoredParkingSpace],
		level: int,
		lot: LotGeometry,
		destination: Vector3 = Vector3.INF) -> void:
	_bays = bays
	_level = level
	_geometry = lot
	_destination = destination
	if not enabled:
		return
	var wanted := ParkingRules.walkers_for_level(level)
	while walking() < wanted:
		if send_crossing() == 0:
			return


## The round is over. Everything living stops where it stands, the same as
## everything driving: the card is up, and a goose still crossing behind it
## would be the only thing moving on screen.
func stop() -> void:
	for pedestrian in _living:
		if is_instance_valid(pedestrian):
			pedestrian.hold()


## A new round is starting: the lot is emptied of everything living, upright or
## otherwise. Called before the bays are refilled.
func reset() -> void:
	for pedestrian in _living:
		if is_instance_valid(pedestrian):
			pedestrian.queue_free()
	_living.clear()


## Sends one crossing on its way -- a person, or a gaggle of geese. Returns how
## many bodies it put on the lot, which is zero when there is no room, nothing
## to spawn, or nowhere clear to start.
##
## Public for the same reason [method LotEvents.start_departure] is: whether a
## crossing happens is a die roll, and a test that waited for one would fail one
## run in three.
func send_crossing() -> int:
	if not _can_spawn():
		return 0
	var room := ParkingRules.WALKERS_MAX - walking()
	if room <= 0:
		return 0
	if rng.randf() < ParkingRules.WILDLIFE_CHANCE:
		var flock := send_gaggle(mini(
				rng.randi_range(ParkingRules.GAGGLE_MIN, ParkingRules.GAGGLE_MAX), room))
		if flock > 0:
			return flock
		# Nothing in the catalog to be a goose. A person will do.
	return 1 if send_walker() != null else 0


## Somebody gets out of a parked car and walks to the building, across whatever
## is between them and it. Returns the pedestrian, or null.
func send_walker() -> Pedestrian:
	if not _can_spawn():
		return null
	var scene := catalog.a_person(rng)
	if scene == null:
		return null
	var bay := _bay_to_start_from()
	if bay == null:
		return null
	var door := _door_point(bay)
	var target := _destination if _destination.is_finite() else _geometry.gate_point(bay)
	return _spawn(scene, door, target)


## A gaggle crosses the aisle: out from one row's paint, over both driving
## lanes, and away on the other side. Returns how many geese went.
func send_gaggle(size: int) -> int:
	if not _can_spawn():
		return 0
	var scene := catalog.an_animal(rng)
	if scene == null or size <= 0:
		return 0
	var bay := _bay_to_start_from()
	if bay == null:
		return 0
	var from := _geometry.clearance_point(bay)
	var to := _geometry.across_point(bay)
	# Spread across the way they are walking so they do not start inside one
	# another, and staggered along it so they cross as a straggle rather than a
	# rank.
	var across := _geometry.row_axis()
	var along := _geometry.aisle_axis(bay)
	var sent := 0
	for i in size:
		var sideways := across * rng.randf_range(-GAGGLE_SPREAD, GAGGLE_SPREAD)
		var back := along * rng.randf_range(-GAGGLE_STAGGER, 0.0)
		if _spawn(scene, from + sideways + back, to + sideways) != null:
			sent += 1
	return sent


## How many are still on their feet and still going somewhere. A body on the
## tarmac is not one of these: it has been scored, it is not a hazard any more,
## and it should not keep the lot from sending another.
func walking() -> int:
	var count := 0
	for pedestrian in _living:
		if is_instance_valid(pedestrian) and pedestrian.state == Pedestrian.State.WALKING:
			count += 1
	return count


## Everything living the lot is holding, upright or down. For tests, and for
## anything that wants to count them.
func living() -> Array[Pedestrian]:
	return _living.duplicate()


## Whether there is anything to spawn and anywhere to spawn it. Also where the
## generator is made, for the case where nobody handed one over -- a test that
## forces a crossing rather than a round that rolled for one.
func _can_spawn() -> bool:
	if not enabled or catalog == null or _geometry == null or _bays.is_empty():
		return false
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return true


## Puts one body on the lot and points it at [param target].
func _spawn(scene: PackedScene, at: Vector3, target: Vector3) -> Pedestrian:
	var pedestrian := scene.instantiate() as Pedestrian
	if pedestrian == null:
		push_error("PedestrianSpawner: %s does not instantiate a Pedestrian." %
				scene.resource_path)
		return null
	var spot := at
	spot.y = _ground_height() + SPAWN_HEIGHT
	# Placed before it enters the tree and again after, the way the traffic
	# spawner places a car: a body that enters the tree at the origin is a body
	# the physics server has already seen at the origin.
	pedestrian.global_transform = Transform3D(
			Basis.looking_at(_facing(spot, target), Vector3.UP), spot)
	pedestrian.finished.connect(_on_finished)
	add_child(pedestrian)
	pedestrian.global_transform = Transform3D(
			Basis.looking_at(_facing(spot, target), Vector3.UP), spot)
	pedestrian.walk_to(target)
	_living.append(pedestrian)
	return pedestrian


## Which way a body spawned at [param from] should be facing to set off towards
## [param to]. Guarded, because [method Basis.looking_at] errors on a zero
## length or vertical direction and a crossing whose two ends coincide is
## exactly that.
static func _facing(from: Vector3, to: Vector3) -> Vector3:
	var direction := LotGeometry.flat(to - from)
	return direction if direction != Vector3.ZERO else Vector3.FORWARD


## A bay to run a crossing off, far enough from the player that they get to see
## it coming. Null when every try landed on top of them.
func _bay_to_start_from() -> ScoredParkingSpace:
	for i in PLACEMENT_TRIES:
		var bay := _bays[rng.randi_range(0, _bays.size() - 1)]
		if _clear_of_the_player(_geometry.clearance_point(bay)):
			return bay
	return null


func _clear_of_the_player(point: Vector3) -> bool:
	if player == null or not is_instance_valid(player):
		return true
	var offset := player.global_position - point
	return Vector2(offset.x, offset.z).length() >= CLEAR_OF_PLAYER


## Where somebody getting out of a car in [param bay] is standing: as far out as
## the bay's own marker says, on the side [LotGeometry] says the aisle is.
##
## [b]The marker's side is not used.[/b] Every bay is the same scene, so the
## marker is on the same local side of all of them -- which is the aisle for one
## row and the kerb for the other. How far the door is belongs to the bay; which
## way is out belongs to the lot.
func _door_point(bay: ScoredParkingSpace) -> Vector3:
	var out := _geometry.aisle_axis(bay)
	var reach := bay.door_distance()
	if is_zero_approx(reach):
		reach = LotGeometry.BAY_CLEARANCE
	return bay.bay_centre() + out * reach


## The height the lot's bays stand at, which is the height its tarmac stands at.
func _ground_height() -> float:
	if _bays.is_empty():
		return 0.0
	return _bays[0].global_position.y


func _on_finished(pedestrian: Pedestrian) -> void:
	_living.erase(pedestrian)
	pedestrian.queue_free()
