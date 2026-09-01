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
##
## The badly parked cars go down first, and the rest of the row is fitted around
## them. A violator is what an area is about, so it is never the car that gives
## way; a correctly parked one is checked against what is already on the road
## before it is placed at all, and if it does not clear, its bay is left empty and
## that car takes the next bay in the area that will have it. An empty space
## beside a bad park reads as exactly what it is.

## Lets SectionManager find the lot without an exported reference across the
## level scene boundary, the same way the camera track is found.
const GROUP := &"parking_lot"

## Metres of road kept clear between two parked cars, for the collision checks
## below and for the room maths that feeds them. Wing mirrors are already inside
## an authored footprint, so this is breathing space rather than clearance for
## anything in particular -- enough that two cars read as parked beside each other
## rather than as having collided.
const PARKING_CLEARANCE := 0.08

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
## Widest and longest footprint in the pool, refreshed per section. Stood in for
## any bay that has not been rolled yet, where nothing is known about what will be
## parked.
var _widest_footprint := Vector2.ZERO


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
##
## The whole area is rolled before anything is placed, then the badly parked cars
## go down, then the rest are fitted around them one at a time. A correctly parked
## car with nowhere to be goes to the next bay in the area that will have it, and
## the bay it came from is left empty.
func populate(spaces: Array[ParkingSpace], min_violators: int, max_violators: int,
		min_innocents: int) -> Array[TargetCar]:
	var parked: Array[TargetCar] = []
	if spaces.is_empty():
		return parked

	_widest_footprint = _pool_widest_footprint()
	if _widest_footprint.x <= 0.0:
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
	# What each bay is getting, which is what the room beside its neighbours is
	# predicted from until there is a real car there to measure instead. A bay
	# drops out of the plan the moment the run gives up on it, so nothing later
	# leaves room for a car that was never parked.
	var plan: Dictionary = {}
	for space in violators:
		plan[space] = ParkingSpace.Role.VIOLATOR
	for space in innocents:
		plan[space] = ParkingSpace.Role.INNOCENT

	# Which vehicle goes where is settled in the same pass, and for the same
	# reason: the room beside a bay depends on how wide its neighbour is, and a
	# neighbour that has not been drawn yet has no width to ask about. Walked in
	# the section's own bay order so the no-repeat rule sees the row as the
	# player does, and so a seeded run draws them back in the same order.
	for space in spaces:
		if not plan.has(space):
			continue
		var profile := _pick_profile(space)
		if profile == null:
			push_warning(("ParkingLot: nothing in vehicles fits %s (%.1f x %.1f m), "
					% [space.name, space.bay_width, space.bay_length])
					+ "so it stays empty.")
			plan.erase(space)
			continue
		_assigned[space] = profile
		_previous_profile = profile

	# The badly parked cars first, in the row's own order. They are what the area
	# is about and they take the room their fault needs; everything after this is
	# fitted around where they actually ended up.
	for space in spaces:
		if plan.get(space, -1) != ParkingSpace.Role.VIOLATOR:
			continue
		var car := _park(space, false, plan)
		if car == null:
			plan.erase(space)
			continue
		parked.append(car)

	# Then the correctly parked ones, each checked against what is already on the
	# road. A bay whose car cannot clear the violator leaning into it is left
	# empty rather than parked through.
	var displaced: Array[ParkingSpace] = []
	for space in spaces:
		if plan.get(space, -1) != ParkingSpace.Role.INNOCENT:
			continue
		var car := _park(space, true, plan)
		if car == null:
			plan.erase(space)
			displaced.append(space)
			continue
		parked.append(car)

	var lost := 0
	for space in displaced:
		var car := _repark(space, spaces, plan)
		if car == null:
			lost += 1
			continue
		parked.append(car)
	_report_displaced(spaces, parked, displaced.size(), lost, min_innocents)
	return parked


## How far a car in [param space] may drift each way across its bay before it
## would be sitting inside a neighbour: x towards the bay's local -X, y towards
## +X. INF on a side with nothing beside it, which is what makes straddling into
## an empty space worth doing, and negative on a side where something has already
## taken the room -- a car parked there has to move over by that much to clear it.
##
## Where the neighbour is already parked this is a measurement rather than a
## prediction: its real pose, crookedness and all, is what the gap is worked out
## from. That is the whole reason the violators go down first.
##
## A bay still waiting on its car has to be guessed at, and the gap between the
## two is split down the middle: either of them may come this way, and assuming a
## neighbour parked dead centre is how two violators side by side end up sharing
## the same metre of road. A bay that has not been rolled at all belongs to a
## later section and is guessed at the same way, with the widest vehicle in the
## pool, because assuming it is empty is how a car ends up standing in one from
## the next area.
##
## The exception is what makes an innocent parkable beside a bad park at all: a
## violator measuring a bay an innocent has not reached yet takes the whole gap
## plus however far that bay can push a legally parked car aside. The innocent
## shifts over when it gets there -- or gives up the bay altogether, which is the
## point of checking rather than predicting.
func _lateral_room(space: ParkingSpace, plan: Dictionary) -> Vector2:
	var room := Vector2(INF, INF)
	var width := _footprint_at(space).x
	# Only a car that is being parked badly is owed the room a neighbour will
	# give up. Two correctly parked cars are not yielding to each other.
	var claims_give: bool = plan.get(space, -1) == ParkingSpace.Role.VIOLATOR
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
		var along := offset.dot(bay.basis.x)
		var side := -1.0 if along < 0.0 else 1.0
		var free := INF
		var neighbour := other.get_occupant()
		if neighbour != null:
			# Measured, not predicted: how far towards us that car actually came,
			# taken from where it is rather than from the middle of its bay.
			var reach := side * (neighbour.global_position - bay.origin).dot(bay.basis.x)
			free = reach - _extent_across(bay.basis.x, neighbour.global_transform,
					_footprint_at(other)) - width * 0.5 - PARKING_CLEARANCE
		elif plan.has(other):
			var between := absf(along) - (width + _footprint_at(other).x) * 0.5 \
					- PARKING_CLEARANCE
			if claims_give and plan[other] == ParkingSpace.Role.INNOCENT:
				free = between + other.legal_give()
			else:
				free = between * 0.5
		elif not _decided.has(other):
			free = (absf(along) - (width + _widest_footprint.x) * 0.5
					- PARKING_CLEARANCE) * 0.5
		if side < 0.0:
			room.x = minf(room.x, free)
		else:
			room.y = minf(room.y, free)
	return room


## How big the car in [param space] is. A bay that has not been rolled yet is
## given the widest and longest vehicle in the pool: it is the assumption that
## cannot put two cars through each other.
func _footprint_at(space: ParkingSpace) -> Vector2:
	var profile: VehicleProfile = _assigned.get(space)
	return profile.footprint if profile != null else _widest_footprint


## Half the width [param footprint] takes up along [param axis] when it is parked
## at [param xform]. A crooked car reaches further across a row than its own
## width, and this is that reach.
static func _extent_across(axis: Vector3, xform: Transform3D, footprint: Vector2) -> float:
	var car_basis := xform.basis.orthonormalized()
	return absf(axis.dot(car_basis.x)) * footprint.x * 0.5 \
			+ absf(axis.dot(car_basis.z)) * footprint.y * 0.5


## Whether a car of [param footprint] parked at [param pose] would be standing in
## one of the cars already on the street, with [param clearance] metres held clear
## around it.
##
## Every bay in the level, not just this section's: the row runs on past where one
## section's bays end, and a car half a metre over the line does not care which
## camera stop is watching it.
func _would_overlap(pose: Transform3D, footprint: Vector2, clearance: float) -> bool:
	for node in get_tree().get_nodes_in_group(ParkingSpace.GROUP):
		var other := node as ParkingSpace
		if other == null:
			continue
		var car := other.get_occupant()
		if car == null:
			continue
		if _overlaps(pose, footprint, car.global_transform, _footprint_at(other), clearance):
			return true
	return false


## Whether two cars these sizes, parked at these poses, would share any road.
##
## A separating-axis test on the two footprints, flattened onto the road: bays are
## level and cars differ only in yaw, so a rectangle each is the whole of the
## geometry. [param clearance] is grown around the first of them, so a car being
## fitted into a gap can be asked for room to park in rather than merely for a
## pose that does not intersect.
static func _overlaps(a: Transform3D, a_footprint: Vector2, b: Transform3D,
		b_footprint: Vector2, clearance: float) -> bool:
	var a_half := a_footprint * 0.5 + Vector2.ONE * clearance
	var b_half := b_footprint * 0.5
	var a_x := _flatten(a.basis.x)
	var a_z := _flatten(a.basis.z)
	var b_x := _flatten(b.basis.x)
	var b_z := _flatten(b.basis.z)
	var between := Vector2(b.origin.x - a.origin.x, b.origin.z - a.origin.z)
	var axes: Array[Vector2] = [a_x, a_z, b_x, b_z]
	for axis in axes:
		var reach := absf(axis.dot(a_x)) * a_half.x + absf(axis.dot(a_z)) * a_half.y \
				+ absf(axis.dot(b_x)) * b_half.x + absf(axis.dot(b_z)) * b_half.y
		# One axis with daylight along it is all it takes: the two do not touch.
		if absf(axis.dot(between)) > reach:
			return false
	return true


## A direction on the road, with the height thrown away.
static func _flatten(direction: Vector3) -> Vector2:
	return Vector2(direction.x, direction.z).normalized()


## Parks a car in [param space] and returns it, or null when it cannot be parked
## there at all. [param plan] is what the section has decided to put in each of
## its bays, which is what the room beside this one is worked out from.
##
## A correctly parked car that would be standing in a car already on the street is
## not placed: its bay is left empty and the caller takes it elsewhere. A violator
## is placed either way -- it went first precisely so that everything else could
## be fitted around it -- so an overlap there is the room maths having been wrong
## and says so rather than quietly parking two cars in one space.
func _park(space: ParkingSpace, legal: bool, plan: Dictionary) -> TargetCar:
	var profile: VehicleProfile = _assigned.get(space)
	if profile == null:
		# Already reported when the draw came up empty; the bay simply stays so.
		return null

	var pose := space.pose(_rng, legal, _lateral_room(space, plan), profile.footprint)
	# Bays are authored at the height a car's origin sits, so a model whose
	# origin is elsewhere on the body is lifted or dropped to meet the road
	# rather than every bay being re-levelled for it. Height is not part of what
	# is_legally_parked measures, so this cannot change what the car scores as.
	pose.origin += pose.basis.y * profile.bay_height_offset

	# Checked before anything is instanced, so a bay that cannot take this car
	# costs a rectangle test rather than a node that has to be freed again.
	if legal:
		# The check this whole ordering exists for. Clearance included: a car has
		# to be parked *beside* what is already there, not shaved past it.
		if _would_overlap(pose, profile.footprint, PARKING_CLEARANCE):
			return null
	elif _would_overlap(pose, profile.footprint, 0.0):
		# No clearance in that one: a violator squeezing past a neighbour with
		# centimetres to spare is the street working as intended, and only cars
		# actually sharing road mean the room maths was wrong.
		push_warning(("ParkingLot: the violator in %s was placed standing in a car that "
				% space.name)
				+ "was already parked. Check that bay's violation reaches against the "
				+ "pitch of the row -- the room maths let it take space it did not have.")

	var car := profile.scene.instantiate() as TargetCar
	if car == null:
		push_error("ParkingLot: %s does not instantiate a TargetCar." % profile.describe())
		_assigned.erase(space)
		return null

	add_child(car)
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


## Takes the car that could not park in [param space] to the next bay in the area
## that will have it, and returns it, or null when the area has nowhere to put it.
##
## "Next" is the section's own bay order rather than the nearest gap: the row is
## filled the way it is read, and a driver who finds a space blocked carries on
## down the street. Bays pinned EMPTY are left alone -- an author who marked a bay
## never-occupied meant it -- and every candidate is checked exactly the way the
## original bay was, so a gap that is only a gap because a violator is leaning
## into it does not get offered as a fresh start.
##
## The car keeps the vehicle it drew. It is the same car moving down the row, and
## redrawing here would quietly undo the no-repeat rule the row was dealt with.
func _repark(space: ParkingSpace, spaces: Array[ParkingSpace],
		plan: Dictionary) -> TargetCar:
	var profile: VehicleProfile = _assigned.get(space)
	# The bay it was pushed out of is empty for the rest of the run, and nothing
	# measuring the row from here on should think a car is standing in it.
	_assigned.erase(space)
	if profile == null:
		return null

	for target in spaces:
		if target == space or plan.has(target) or target.role == ParkingSpace.Role.EMPTY:
			continue
		if target.get_occupant() != null or not target.fits(profile.footprint):
			continue
		_assigned[target] = profile
		var car := _park(target, true, plan)
		if car != null:
			return car
		_assigned.erase(target)
	return null


## Says when an area came out of all that with less to look at than it was meant
## to have. Cars being crowded out is the feature working; a whole area of them
## with nowhere to go is a row too tight for the violations it is being asked to
## hold, and that is a tuning problem with no other visible symptom.
func _report_displaced(spaces: Array[ParkingSpace], parked: Array[TargetCar],
		displaced: int, lost: int, min_innocents: int) -> void:
	if displaced == 0:
		return
	var innocents := 0
	for car in parked:
		if not car.is_violator:
			innocents += 1
	if innocents >= min_innocents:
		return
	push_warning(("ParkingLot: the area at %s crowded %d correctly parked car(s) out of "
			% [spaces[0].name, displaced])
			+ "their bays, %d of which had nowhere else to go, leaving %d where "
					% [lost, innocents]
			+ "min_innocents is %d. Its %d bays are pitched too tightly for the "
					% [min_innocents, spaces.size()]
			+ "violations they are being asked to hold: widen the row, lower that "
			+ "stop's max_violators, or bring in those bays' violation reaches.")


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


## The box no vehicle in the pool is bigger than, taken axis by axis. Stood in for
## a bay nothing is known about yet, where the only safe guess is the worst one.
func _pool_widest_footprint() -> Vector2:
	var widest := Vector2.ZERO
	for profile in vehicles:
		if profile == null or not profile.is_usable():
			continue
		widest.x = maxf(widest.x, profile.footprint.x)
		widest.y = maxf(widest.y, profile.footprint.y)
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
