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
##
## Which vehicle goes in which bay is rolled the same way, from [member
## vehicles]. Size is the part that has to be settled early: a bay works out its
## room from the width of whatever is parked beside it, so every bay in a section
## knows what it is getting before any of them are filled.

## Lets SectionManager find the lot without an exported reference across the
## level scene boundary, the same way the camera track is found.
const GROUP := &"parking_lot"

## How far an authored footprint may sit from the mesh it describes before
## [member verify_footprints] complains, in metres. Loose enough not to fire on
## a wing mirror, tight enough to catch a number copied from the wrong vehicle.
const FOOTPRINT_TOLERANCE := 0.25

## Vehicles to park. One is drawn per bay, weighted by each profile's
## spawn_weight and filtered to what actually fits that bay, so adding a second
## profile here is all it takes to stop every area being a row of identical SUVs.
@export var vehicles: Array[VehicleProfile] = []

## Drops the vehicle parked in the previous bay from the draw for the next one.
## A run of identical cars reads as a spawner rather than a street. Ignored when
## it would leave a bay with nothing to put in it: a repeat beats a gap.
@export var avoid_adjacent_repeats: bool = true

## Zero seeds from the clock, so every run differs. Set a non-zero seed to replay
## one exact layout while tuning bays.
@export var random_seed: int = 0

## Warns when a placed car does not classify the way it was meant to. The
## generators clear the legal band by construction, so this firing means a bay's
## tolerances and its violation margins have been tuned into contradiction.
@export var verify_poses: bool = true

## Warns when a profile's authored footprint disagrees with the mesh it names.
## The room maths runs entirely on those authored numbers, and a footprint that
## has drifted from its model is how two cars end up sharing a patch of road --
## a failure with no visible cause until you are looking straight at it. Checked
## once per profile per run, not once per car.
@export var verify_footprints: bool = true

var _rng := RandomNumberGenerator.new()
## Every car this lot has spawned and not yet freed, in spawn order.
var _cars: Array[TargetCar] = []
## Bays this run has already made its mind up about. A bay that is not in here
## has not been rolled yet, and is assumed to be getting a car: better a straddle
## that stays modest than one that ends up inside a car parked a moment later.
var _decided: Dictionary = {}
## ParkingSpace -> the VehicleProfile parked there this run. Kept for the whole
## run rather than per section, because a bay on a section boundary has to know
## the width of a neighbour an earlier section already filled.
var _assigned: Dictionary = {}
## Profiles already checked against their meshes this run, so a fourteen-car
## street measures each model once instead of fourteen times.
var _verified: Dictionary = {}
## The vehicle parked in the last bay filled, for [member avoid_adjacent_repeats].
var _previous_profile: VehicleProfile = null
## Widest footprint in the pool, refreshed per section. Stood in for any bay that
## has not been rolled yet, where nothing is known about what will be parked.
var _widest_width: float = 0.0


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
	_assigned.clear()
	_verified.clear()
	_previous_profile = null
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

	_widest_width = _pool_widest_width()
	if _widest_width <= 0.0:
		push_error("ParkingLot: no usable vehicles assigned -- a profile needs a scene "
				+ "and a non-zero footprint -- so every bay stays empty.")
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

	# Which vehicle goes where is settled in the same pass, and for the same
	# reason: the room beside a bay depends on how wide its neighbour is, and a
	# neighbour that has not been drawn yet has no width to ask about. Walked in
	# the section's own bay order so the no-repeat rule sees the row as the
	# player does, and so a seeded run draws them back in the same order.
	for space in spaces:
		if not occupied.has(space):
			continue
		var profile := _pick_profile(space)
		if profile == null:
			push_warning(("ParkingLot: nothing in vehicles fits %s (%.1f x %.1f m), "
					% [space.name, space.bay_width, space.bay_length])
					+ "so it stays empty.")
			occupied.erase(space)
			continue
		_assigned[space] = profile
		_previous_profile = profile

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
## Both cars' widths come out of the gap -- this one's and the neighbour's -- and
## what is left is halved, because that neighbour may be drifting this way just
## as far. Assuming it parked dead centre is how two violators side by side end
## up sharing the same metre of road.
func _lateral_room(space: ParkingSpace, occupied: Dictionary) -> Vector2:
	var room := Vector2(INF, INF)
	var width := _width_at(space)
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
		var between := absf(along) - (width + _width_at(other)) * 0.5
		var free := maxf(between * 0.5, 0.0)
		if along < 0.0:
			room.x = minf(room.x, free)
		else:
			room.y = minf(room.y, free)
	return room


## How wide the car in [param space] is. A bay that has not been rolled yet is
## given the widest vehicle in the pool: it is the assumption that cannot put two
## cars through each other, and it is the same conservatism [method
## _will_hold_a_car] already applies to whether that bay is occupied at all.
func _width_at(space: ParkingSpace) -> float:
	var profile: VehicleProfile = _assigned.get(space)
	return profile.footprint.x if profile != null else _widest_width


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
	var profile: VehicleProfile = _assigned.get(space)
	if profile == null:
		# Already reported when the draw came up empty; the bay simply stays so.
		return null
	var car := profile.scene.instantiate() as TargetCar
	if car == null:
		push_error("ParkingLot: %s does not instantiate a TargetCar." % profile.describe())
		_assigned.erase(space)
		return null

	add_child(car)
	var pose := space.pose(_rng, legal, lateral_room, profile.footprint)
	# Bays are authored at the height a car's origin sits, so a model whose
	# origin is elsewhere on the body is lifted or dropped to meet the road
	# rather than every bay being re-levelled for it. Height is not part of what
	# is_legally_parked measures, so this cannot change what the car scores as.
	pose.origin += pose.basis.y * profile.bay_height_offset
	car.global_transform = pose

	# The pose is the truth, not the intent. Measuring what was actually placed
	# is what guarantees a car that looks parked is scored as parked.
	var parked_legally := space.is_legally_parked(pose)
	if verify_poses and parked_legally != legal:
		push_warning(("ParkingLot: %s wanted a %s pose but placed a %s one. "
				% [space.name, _describe(legal), _describe(parked_legally)])
				+ "Check that bay's legal tolerances against its violation margins.")
	if verify_footprints:
		_verify_footprint(car, profile)
	car.is_violator = not parked_legally
	car.name = "%s%s" % [space.name, "Violator" if car.is_violator else "Innocent"]

	space.occupy(car)
	_cars.append(car)
	return car


## Draws a vehicle for [param space]: what fits it, weighted, and preferably not
## whatever is parked in the bay before it.
func _pick_profile(space: ParkingSpace) -> VehicleProfile:
	var candidates: Array[VehicleProfile] = []
	for profile in vehicles:
		if profile == null or not profile.is_usable():
			continue
		if not space.fits(profile.footprint):
			continue
		candidates.append(profile)
	if candidates.is_empty():
		return null

	# Only when there is something else to park here. A gap in the row reads as
	# worse than a repeat, and a pool of one would otherwise empty the street.
	if avoid_adjacent_repeats and _previous_profile != null and candidates.size() > 1:
		candidates.erase(_previous_profile)

	var total := 0.0
	for profile in candidates:
		total += maxf(profile.spawn_weight, 0.0)
	# Every survivor weighted at zero, which is still a bay that wants a car.
	if total <= 0.0:
		return candidates[_rng.randi_range(0, candidates.size() - 1)]

	var roll := _rng.randf() * total
	for profile in candidates:
		roll -= maxf(profile.spawn_weight, 0.0)
		if roll <= 0.0:
			return profile
	# Only reachable on floating-point drift at the very top of the range.
	return candidates[candidates.size() - 1]


func _pool_widest_width() -> float:
	var widest := 0.0
	for profile in vehicles:
		if profile == null or not profile.is_usable():
			continue
		widest = maxf(widest, profile.footprint.x)
	return widest


## Checks an authored footprint against the mesh it names, once per profile per
## run. The room maths cannot measure the car it is making room for -- that car
## does not exist yet -- so this is the only place the two can be compared at all.
func _verify_footprint(car: TargetCar, profile: VehicleProfile) -> void:
	if _verified.has(profile):
		return
	_verified[profile] = true

	var bounds := VehicleProfile.measure_bounds(car)
	if bounds.size == Vector3.ZERO:
		push_warning("ParkingLot: %s has no meshes to measure, so its footprint is taken "
				% profile.describe() + "on trust.")
		return
	var measured := Vector2(bounds.size.x, bounds.size.z)
	if absf(measured.x - profile.footprint.x) <= FOOTPRINT_TOLERANCE \
			and absf(measured.y - profile.footprint.y) <= FOOTPRINT_TOLERANCE:
		return
	push_warning(("ParkingLot: %s declares a %.2f x %.2f m footprint but its mesh "
			% [profile.describe(), profile.footprint.x, profile.footprint.y])
			+ "measures %.2f x %.2f m. " % [measured.x, measured.y]
			+ "Re-run Tools/derive_vehicle_profile.gd; the room beside every bay "
			+ "is worked out from the declared number.")


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
