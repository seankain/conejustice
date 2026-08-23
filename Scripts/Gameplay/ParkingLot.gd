class_name ParkingLot
extends Node3D
## Fills a section's [ParkingSpace] bays with cars, and decides which of them are
## parked badly enough to deserve a cone.
##
## The layout is rolled once per run: an area holds still for as long as the
## player is looking at it, and is a different puzzle the next time round. That
## is the whole reason the cars are spawned here instead of authored in the
## level -- a fixed street is memorised after two runs.
##
## Roles are assigned by *placing* a car and then measuring where it ended up,
## never by labelling it and hoping the pose agrees. The bay owns both the
## generator and the rule (see [ParkingSpace]), so the car the player judges and
## the car the game scores are always the same car.

## Lets SectionManager find the lot without an exported reference across the
## level scene boundary, the same way the camera track is found.
const GROUP := &"parking_lot"

## Cars to park. One is picked per bay, so adding a second model here is all it
## takes to stop every area being a row of identical SUVs.
@export var car_scenes: Array[PackedScene] = []

## Roughly how wide and how long the cars in [member car_scenes] are. Used for
## one thing: working out how far a badly parked car may drift or slew before it
## would be standing inside the car next to it.
@export var car_footprint := Vector2(1.8, 4.5)

## Zero seeds from the clock, so every run differs. Set a non-zero seed to replay
## one exact layout while tuning bays.
@export var random_seed: int = 0

## Warns when a placed car does not classify the way it was meant to. The
## generators clear the legal band by construction, so this firing means a bay's
## tolerances and its violation margins have been tuned into contradiction.
@export var verify_poses: bool = true

var _rng := RandomNumberGenerator.new()
## Every car this lot has spawned and not yet freed, in spawn order.
var _cars: Array[TargetCar] = []
## Bays this run has already made its mind up about. A bay that is not in here
## has not been rolled yet, and is assumed to be getting a car: better a straddle
## that stays modest than one that ends up inside a car parked a moment later.
var _decided: Dictionary = {}


func _enter_tree() -> void:
	# _enter_tree, not _ready: the level is instanced before the game root is
	# ready, so anything resolving the lot in its own _ready still finds it.
	add_to_group(GROUP)


## Starts a fresh sequence of layouts. Call once per run, before the first
## [method populate], so a seeded run lays out every area from that one number.
func reseed() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()


## Frees every parked car and empties every bay in the tree, not just the bays
## this lot was asked about. A restart means a clean street, and a bay that no
## stop happens to reference is exactly the one that would be missed.
func clear_cars() -> void:
	for node in get_tree().get_nodes_in_group(ParkingSpace.GROUP):
		var space := node as ParkingSpace
		if space != null:
			space.vacate()

	_decided.clear()
	for car in _cars:
		if not is_instance_valid(car):
			continue
		# Reset before freeing: a car freed while it still counts cones leaves
		# those cones flagged as scored, which exempts them from the thrower's
		# cull and leaves them standing through the next run.
		car.reset()
		# Removed as well as freed, so a lookup in the same frame cannot resolve
		# to a car that is on its way out.
		remove_child(car)
		car.queue_free()
	_cars.clear()


## Parks cars across [param spaces] and returns them. Violator count is rolled
## between the two bounds; [param min_innocents] is the guard that keeps at least
## one correctly parked car in the area, because an area with nothing to spare is
## an area with no decision in it.
func populate(spaces: Array[ParkingSpace], min_violators: int, max_violators: int,
		min_innocents: int) -> Array[TargetCar]:
	var parked: Array[TargetCar] = []
	if spaces.is_empty():
		return parked

	var violators: Array[ParkingSpace] = []
	var innocents: Array[ParkingSpace] = []
	var spare: Array[ParkingSpace] = []
	for space in spaces:
		space.vacate()
		match space.role:
			ParkingSpace.Role.VIOLATOR:
				violators.append(space)
			ParkingSpace.Role.INNOCENT:
				innocents.append(space)
			ParkingSpace.Role.EMPTY:
				pass
			_:
				spare.append(space)

	_shuffle(spare)

	# Bays pinned by their own role come first; the roll only tops the area up.
	# The innocent guarantee caps that roll, but never below min_violators: a
	# section with nothing illegally parked cannot be cleared at all, while one
	# with nothing correctly parked is merely a duller section.
	var ceiling := maxi(spaces.size() - min_innocents, min_violators)
	var wanted := clampi(_rng.randi_range(min_violators, maxi(max_violators, min_violators)),
			0, ceiling)
	while violators.size() < wanted and not spare.is_empty():
		violators.append(spare.pop_back())
	while innocents.size() < min_innocents and not spare.is_empty():
		innocents.append(spare.pop_back())

	# Whatever is left is occupied on a roll, so the row has gaps in it.
	for space in spare:
		if _rng.randf() < space.occupancy_chance:
			innocents.append(space)

	# Every bay in the section is settled before a single car is placed. A car
	# that straddles into the bay beside it has to know whether that bay is about
	# to be filled, and that answer does not exist until the whole roll is done.
	for space in spaces:
		_decided[space] = true
	var occupied: Dictionary = {}
	for space in violators:
		occupied[space] = true
	for space in innocents:
		occupied[space] = true

	for space in violators:
		var car := _park(space, false, _lateral_room(space, occupied))
		if car != null:
			parked.append(car)
	for space in innocents:
		var car := _park(space, true)
		if car != null:
			parked.append(car)
	return parked


## How far a car in [param space] may drift each way across its bay before it
## would be sitting inside a neighbour: x towards the bay's local -X, y towards
## +X. INF on a side with nothing beside it, which is what makes straddling into
## an empty space worth doing.
##
## The room to an occupied neighbour is halved, because that neighbour may be
## drifting this way just as far. Assuming it parked dead centre is how two
## violators side by side end up sharing the same metre of road.
func _lateral_room(space: ParkingSpace, occupied: Dictionary) -> Vector2:
	var room := Vector2(INF, INF)
	var bay := space.bay_transform()
	for node in get_tree().get_nodes_in_group(ParkingSpace.GROUP):
		var other := node as ParkingSpace
		if other == null or other == space:
			continue
		var offset := other.global_position - bay.origin
		# Beside this bay, not in front of or behind it. One row today, but a
		# second row facing the first must not count as a neighbour.
		if absf(offset.dot(bay.basis.z)) > space.bay_length * 0.5:
			continue
		if not _will_hold_a_car(other, occupied):
			continue
		var along := offset.dot(bay.basis.x)
		var free := maxf((absf(along) - car_footprint.x) * 0.5, 0.0)
		if along < 0.0:
			room.x = minf(room.x, free)
		else:
			room.y = minf(room.y, free)
	return room


func _will_hold_a_car(space: ParkingSpace, occupied: Dictionary) -> bool:
	if occupied.has(space):
		return true
	if _decided.has(space):
		return space.get_occupant() != null
	# Not rolled yet. Treated as occupied, so a car never straddles into a bay
	# that a later section is about to fill.
	return true


func _park(space: ParkingSpace, legal: bool,
		lateral_room := Vector2(INF, INF)) -> TargetCar:
	var scene := _pick_scene()
	if scene == null:
		push_error("ParkingLot: no car_scenes assigned, so %s stays empty." % space.name)
		return null
	var car := scene.instantiate() as TargetCar
	if car == null:
		push_error("ParkingLot: %s does not instantiate a TargetCar." % scene.resource_path)
		return null

	add_child(car)
	var pose := space.pose(_rng, legal, lateral_room, car_footprint)
	car.global_transform = pose

	# The pose is the truth, not the intent. Measuring what was actually placed
	# is what guarantees a car that looks parked is scored as parked.
	var parked_legally := space.is_legally_parked(pose)
	if verify_poses and parked_legally != legal:
		push_warning(("ParkingLot: %s wanted a %s pose but placed a %s one. "
				% [space.name, _describe(legal), _describe(parked_legally)])
				+ "Check that bay's legal tolerances against its violation margins.")
	car.is_violator = not parked_legally
	car.name = "%s%s" % [space.name, "Violator" if car.is_violator else "Innocent"]

	space.occupy(car)
	_cars.append(car)
	return car


func _pick_scene() -> PackedScene:
	var usable: Array[PackedScene] = []
	for scene in car_scenes:
		if scene != null:
			usable.append(scene)
	if usable.is_empty():
		return null
	return usable[_rng.randi_range(0, usable.size() - 1)]


func _describe(legal: bool) -> String:
	return "legal" if legal else "illegal"


## Fisher-Yates against this lot's generator. Array.shuffle() would draw from the
## global one instead, and a seeded layout would stop replaying.
func _shuffle(spaces: Array[ParkingSpace]) -> void:
	for i in range(spaces.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var held := spaces[i]
		spaces[i] = spaces[j]
		spaces[j] = held
