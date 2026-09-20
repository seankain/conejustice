class_name LotEvents
extends Node
## The lot with something going on in it: a parked car that decides to leave,
## rivals turning up for the same space you are going for, and something living
## walking across in front of you. All three get likelier every level.
##
## Nothing in the source does this. Its lot is filled once per level and then
## holds still, and the only thing that moves is the player -- which makes a
## level twenty exactly a level one with less time on the clock and more of the
## same furniture. What escalates here is what the lot is doing while you park in
## it:
##
## - [b]A car leaves.[/b] One of the parked cars backs out and drives off, which
##   opens a space that was not there when you started -- and puts a moving car
##   across the aisle while you are looking at a different bay.
## - [b]A rival arrives.[/b] A car comes in off the road looking for a space, and
##   takes one. At the top of the lot, where there were two spaces left, it takes
##   one of yours.
## - [b]Somebody walks out.[/b] A person gets out of a parked car and heads for
##   the building, or a gaggle of geese crosses the aisle. Hitting one costs a
##   grade, and unlike the other two this one is on the lot from the start of
##   every round -- see [PedestrianSpawner].
##
## The odds of each, per roll, come from [ParkingRules]; the rolls themselves are
## [constant ParkingRules.RANDOM_EVENT_SECONDS] apart. The driving is
## [NpcDriver]'s and the lanes are [LotGeometry]'s; this file decides what
## happens, to which car, and when.
##
## [b]The policy lives here and the driving does not.[/b] A driver knows how to
## get a car from where it is to a waypoint. Whether the bay it is heading for is
## still free, whether two rivals are going for the same one, and what happens to
## a car that gets there -- those are this node's, and are checked every frame
## rather than once when the plan was made.

## A parked car has started backing out of [param bay]. The round says so across
## the middle of the screen: a space opening up is worth knowing about.
signal car_leaving(bay: ScoredParkingSpace)
## A rival has come in off the road and is going for [param bay].
signal rival_arriving(bay: ScoredParkingSpace)
## ...and has parked in it. That space is gone.
signal rival_parked(bay: ScoredParkingSpace)
## Something living has started across the lot. [param bodies] is how many went,
## because a gaggle is several at once.
signal crossing_started(bodies: int)

## The cars a rival can turn up in -- the same catalog the player picks out of.
var catalog: VehicleCatalog = null
## Where parked cars come from and go back to. A departing car is released by it
## and a rival that parks is adopted by it, so at any moment exactly one node
## owns each car in the lot.
var traffic: TrafficSpawner = null
## Where the lot's people and geese come from. Null in a lot the round has
## switched them off for, and the third roll is then never made.
var pedestrians: PedestrianSpawner = null
## The round's generator, seeded once and shared, rather than one per system.
var rng: RandomNumberGenerator = null
## Yielded to by every driver, and the thing a rival is racing.
var player: PlayerCar = null

## Off turns the lot back into the source's: filled once and holding still. The
## round exports the same switch, and the round-flow test uses it to keep the lot
## still while it measures a park.
var enabled: bool = true

## Cars driving themselves around the lot right now.
var drivers: Array[NpcDriver] = []

var _geometry: LotGeometry = null
var _bays: Array[ScoredParkingSpace] = []
var _level: int = 1
var _running: bool = false
var _until_roll: float = 0.0


func _ready() -> void:
	set_process(false)


## Starts the dice rolling for a new round. Called after the lot has been filled,
## so the first roll sees the lot the player sees.
func begin(
		bays: Array[ScoredParkingSpace],
		level: int,
		player_car: PlayerCar,
		entrance: Vector3 = Vector3.INF) -> void:
	_bays = bays
	_level = level
	player = player_car
	_geometry = LotGeometry.new(bays, entrance)
	# The first roll is a whole interval away: the player gets the opening of a
	# round to themselves.
	_until_roll = ParkingRules.RANDOM_EVENT_SECONDS
	_running = true
	set_process(true)


## The round is over. Everything stops where it stands -- the card is up and the
## camera is turning around the car, and a rival still creeping into a bay behind
## it would be the only thing moving on screen.
func stop() -> void:
	_running = false
	set_process(false)
	for driver in drivers:
		if is_instance_valid(driver):
			driver.hold()


## A new round is starting: every car that was driving itself goes, whether it
## had arrived or not. Called before the lot is refilled, so the spawner is
## putting cars into a lot nothing else is holding.
func reset() -> void:
	stop()
	for driver in drivers:
		if not is_instance_valid(driver):
			continue
		if is_instance_valid(driver.car):
			driver.car.queue_free()
		driver.queue_free()
	drivers.clear()


func _process(delta: float) -> void:
	if not _running:
		return
	_watch_rivals()
	_until_roll -= delta
	if _until_roll > 0.0:
		return
	_until_roll = ParkingRules.RANDOM_EVENT_SECONDS
	_roll()


## One roll of each of the lot's dice. Any of them can come up in the same roll,
## which at the top of the table is most of what makes it feel like a car park
## rather than a diagram.
func _roll() -> void:
	if not enabled or rng == null:
		return
	if rng.randf() < ParkingRules.departure_chance(_level):
		start_departure()
	if rng.randf() < ParkingRules.arrival_chance(_level):
		start_arrival()
	if rng.randf() < ParkingRules.walker_chance(_level):
		start_crossing()


## Sends one of the parked cars home. Returns whether one went.
##
## Public because the odds are the only random part of this, and a test that had
## to wait for a die to come up the right way would be a test that fails one run
## in ten.
func start_departure() -> bool:
	if traffic == null or _geometry == null or not _has_room_for_another():
		return false
	var leaving := _car_that_can_leave()
	if leaving == null:
		return false
	var bay := traffic.bay_of(leaving)
	var driver := _new_driver()
	# Released into the driver's hands before it is configured: from here the
	# spawner will not free it, and the driver will.
	traffic.release(leaving, driver)
	driver.configure(leaving, _geometry, player, rng)
	driver.leave(bay)
	car_leaving.emit(bay)
	return true


## Brings a rival in off the road for a space. Returns whether one came.
func start_arrival() -> bool:
	if traffic == null or _geometry == null or catalog == null or not _has_room_for_another():
		return false
	var target := _bay_for_a_rival()
	if target == null:
		return false
	var vehicle := _rival_vehicle()
	if vehicle == null:
		return false
	var car := traffic.build(vehicle)
	if car == null:
		return false
	# Placed before it enters the tree, the way the spawner places a parked car,
	# because the driver reads the pose it is handed as where the car is.
	var gate := _geometry.gate_point(target)
	gate.y = target.global_position.y + traffic.ride_height(vehicle)
	var pose := Transform3D(Basis.looking_at(-_geometry.gate_direction(), Vector3.UP), gate)
	car.global_transform = pose
	var driver := _new_driver()
	driver.add_child(car)
	car.global_transform = pose
	# Placed at the gate rather than driven to it, and placed again after
	# entering the tree: without this the car is drawn arriving from wherever the
	# spawner built it.
	car.reset_physics_interpolation()
	driver.configure(car, _geometry, player, rng)
	driver.arrive(target)
	rival_arriving.emit(target)
	return true


## Sends somebody across the lot on foot. Returns whether anybody went.
##
## The policy is the spawner's -- whether it is a person or a gaggle, where they
## start and where they are going. This decides only that it happens.
func start_crossing() -> bool:
	if pedestrians == null:
		return false
	var bodies := pedestrians.send_crossing()
	if bodies > 0:
		crossing_started.emit(bodies)
	return bodies > 0


## Which bays have nothing in them: no parked car, no rival on its way, and not
## the one the player is sitting in.
func free_bays() -> Array[ScoredParkingSpace]:
	var free: Array[ScoredParkingSpace] = []
	for bay in _bays:
		if _is_free(bay):
			free.append(bay)
	return free


## The lanes, gates and aisle sides this round is being played on. Built by
## [method begin] from the bays it was handed, and read by anything else that has
## to know where the aisle is -- [PedestrianSpawner], for one. Null before the
## first round starts.
func lot_geometry() -> LotGeometry:
	return _geometry


## The same, for a rival that is allowed to be standing in one of them itself.
func _free_bays_for(driver: NpcDriver) -> Array[ScoredParkingSpace]:
	var free: Array[ScoredParkingSpace] = []
	for bay in _bays:
		if _is_free(bay, driver):
			free.append(bay)
	return free


## Whether [param bay] is empty, ignoring [param ignoring] -- the rival asking
## whether the space it is already sitting in is still free is asking about
## everyone except itself.
func _is_free(bay: ScoredParkingSpace, ignoring: NpcDriver = null) -> bool:
	var ignored_car: PlayerCar = ignoring.car if ignoring != null else null
	# bay.car is the player: a bay they are being measured in is not a bay a
	# rival may park on top of them.
	if bay.has_parked_car(ignored_car) or bay.car != null:
		return false
	for driver in drivers:
		if driver == ignoring or not is_instance_valid(driver):
			continue
		if driver.intent == NpcDriver.Intent.ARRIVING and driver.bay == bay:
			return false
	return true


## Rivals are re-checked every frame rather than trusted to the plan they were
## given: the player can take the space a rival is halfway down the aisle for,
## and a rival that parks on top of them would be worse than no rival at all.
func _watch_rivals() -> void:
	for driver in drivers:
		if not is_instance_valid(driver) or driver.phase != NpcDriver.Phase.DRIVING:
			# A rival already straightening up in the bay has arrived as far as
			# this is concerned. Sending it back out of a space it is sitting in
			# would have it drive out through the paint.
			continue
		if driver.intent != NpcDriver.Intent.ARRIVING or driver.bay == null:
			continue
		if _is_free(driver.bay, driver):
			continue
		var next := _nearest_free_bay_ahead(driver)
		if next == null:
			driver.give_up()
			continue
		driver.arrive(next)


## A free bay the car has not already driven past, nearest first. A rival sent
## after a bay behind it would have to turn around in an aisle it does not fit
## across, so it drives off instead.
func _nearest_free_bay_ahead(driver: NpcDriver) -> ScoredParkingSpace:
	if not is_instance_valid(driver.car):
		return null
	var from := driver.car.global_position
	var travel := LotGeometry.flat(-driver.car.global_basis.z)
	var best: ScoredParkingSpace = null
	var best_distance := INF
	for bay in _free_bays_for(driver):
		var approach := _geometry.turn_in_point(bay)
		var offset := approach - from
		if LotGeometry.flat(offset).dot(travel) <= 0.0:
			continue
		var distance := offset.length()
		if distance < best_distance:
			best_distance = distance
			best = bay
	return best


## Which bay a rival goes for: the free one nearest the player, or any free one.
##
## Uniformly random is the honest choice and the boring one -- in a lot with
## eighteen free bays a rival takes one the player was never going to reach, and
## the whole event goes unnoticed. The rest of the time it goes for the space the
## player is closest to, which is the one they are probably going for, and how
## often that happens is the third thing that climbs with the level.
func _bay_for_a_rival() -> ScoredParkingSpace:
	var free := free_bays()
	if free.is_empty():
		return null
	if player != null and is_instance_valid(player) \
			and rng.randf() < ParkingRules.rival_focus_chance(_level):
		var nearest: ScoredParkingSpace = null
		var nearest_distance := INF
		for bay in free:
			var distance := bay.centre_distance(player)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = bay
		return nearest
	return free[rng.randi_range(0, free.size() - 1)]


## A parked car that can be sent home: one this spawner parked, in a bay the
## player is not already half inside.
func _car_that_can_leave() -> PlayerCar:
	var candidates: Array[PlayerCar] = []
	for car in traffic.parked_cars():
		if not is_instance_valid(car):
			continue
		var bay := traffic.bay_of(car)
		if bay == null or bay.car != null:
			continue
		candidates.append(car)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## Which car a rival turns up in: one of the chassis the spawner has already
## measured a ride height for. That is every chassis the lot filled with this
## round, which is at least two cars from the same catalog the player picked out
## of -- and it means nothing ever has to guess how high off the road a car sits.
func _rival_vehicle() -> DrivableVehicle:
	var measured := traffic.measured_vehicles()
	if measured.is_empty():
		return null
	return measured[rng.randi_range(0, measured.size() - 1)]


## A driver in the tree with nothing to drive yet. The car is put in its hands
## by the caller, because where the car comes from is the difference between the
## two events: one is already in the lot and one is not.
func _new_driver() -> NpcDriver:
	var driver := NpcDriver.new()
	driver.name = "Driver"
	driver.finished.connect(_on_driver_finished)
	add_child(driver)
	drivers.append(driver)
	return driver


func _has_room_for_another() -> bool:
	var live := 0
	for driver in drivers:
		if is_instance_valid(driver) and driver.phase != NpcDriver.Phase.DONE:
			live += 1
	return live < ParkingRules.active_driver_limit(_level)


func _on_driver_finished(driver: NpcDriver) -> void:
	var car := driver.car
	drivers.erase(driver)
	if driver.intent == NpcDriver.Intent.ARRIVING and is_instance_valid(car):
		traffic.adopt(car, driver.bay)
		rival_parked.emit(driver.bay)
	elif is_instance_valid(car):
		# It reached the gate. Off the lot is off the lot.
		car.queue_free()
	driver.queue_free()
