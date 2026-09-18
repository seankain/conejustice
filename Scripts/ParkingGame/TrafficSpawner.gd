class_name TrafficSpawner
extends Node
## Fills the lot's bays with parked cars, and clears them again between rounds.
##
## Ported from [code]Spawner.cs[/code] and [code]NpcCar.cs[/code]. The NPC car
## class itself is not ported: it is a [VehicleBody3D] with an empty
## [code]_PhysicsProcess[/code] override wrapped around commented-out driving
## code and three steering fields nothing reads, and the only thing it really
## does is paint itself. A parked car here is the same chassis the player
## drives, with its input off and its body frozen, dressed by this node.
##
## Two things the source does that are not ported:
##
## - [b]It frees with [code]Free()[/code].[/b] An immediate free during a
##   physics callback is how you get a crash that only shows up when a car is
##   touching something. These go through [method Node.queue_free].
## - [b]It rejection-samples which bays to fill[/b], drawing random indices into
##   a set until enough distinct ones turn up, which gets slower the fuller the
##   lot is and can in principle never finish. This shuffles the bays and takes
##   the first few.
##
## Cars are spawned unfrozen, allowed to drop onto their own suspension, and
## frozen where they land. That costs a second of physics at the start of a
## round and buys a car that is sitting on the road at exactly the height its
## own springs put it, rather than at a height this file would otherwise have to
## know -- and that height, written down per chassis, is what lets [LotEvents]
## drive a car around the lot without simulating one.
##
## It owns the lot's furniture but not for the whole of a round. A car that
## decides to leave is [method release]d into an [NpcDriver]'s hands and is that
## driver's to free; a rival that parks itself is [method adopt]ed back. At any
## moment exactly one node is responsible for each car in the lot.

## Parked cars join both: the round clears by the first, and [Obstacle] reports
## a collision by the second.
const VEHICLE_GROUP := &"npc_vehicles"

## Metres a settling car may move in one frame and still count as parked.
##
## Measured rather than guessed at: a car standing still on this chassis reports
## over a metre per second of vertical velocity for seconds while its springs
## ring, so velocity is the wrong question. Where the car actually is settles
## almost immediately.
const SETTLE_MOVEMENT := 0.002
## ...and how many frames it has to stay that still.
const SETTLE_FRAMES := 12
## A car that will not settle is frozen anyway rather than simulated forever.
const SETTLE_GIVE_UP_FRAMES := 240

## The cars to choose from. The same catalog the player picks out of, so the lot
## is full of the cars the game is about.
var catalog: VehicleCatalog = null
## Seeded once by the round and shared, rather than the source's Random.Shared
## reached for from three different files.
var rng: RandomNumberGenerator = null

var _cars: Array[PlayerCar] = []
var _settling: Array[PlayerCar] = []
var _settled_frames: Dictionary[PlayerCar, int] = {}
var _last_position: Dictionary[PlayerCar, Vector3] = {}
var _waited_frames: int = 0
## Which bay each parked car is in. [LotEvents] asks, to send one of them home.
var _bay_of: Dictionary[PlayerCar, ScoredParkingSpace] = {}
## ...and which catalog entry it came from, so freezing it can be turned into a
## measurement of that chassis.
var _vehicle_of: Dictionary[PlayerCar, DrivableVehicle] = {}
## How high above the tarmac each chassis sits once it has settled onto its own
## suspension. Measured, kept for the life of the cabinet rather than the round,
## and read by [LotEvents] -- a car driven rather than simulated has to be told
## its own ride height, and this is the only place that ever learns it.
var _ride_heights: Dictionary[DrivableVehicle, float] = {}


func _ready() -> void:
	set_physics_process(false)


## Clears the lot and parks [param count] cars in randomly chosen bays, never
## filling the last one -- a lot with nowhere to park is not a round.
func fill(bays: Array[ScoredParkingSpace], count: int) -> void:
	clear()
	if catalog == null or bays.is_empty():
		return
	var cars := catalog.usable()
	if cars.is_empty():
		return
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var shuffled := bays.duplicate()
	_shuffle(shuffled)
	var wanted := clampi(count, 0, bays.size() - 1)
	for i in wanted:
		_park(shuffled[i], cars[rng.randi_range(0, cars.size() - 1)])
	if not _settling.is_empty():
		_waited_frames = 0
		set_physics_process(true)


## Frees every parked car. Safe to call mid-physics, which is the whole reason
## it does not use the source's Free().
func clear() -> void:
	for car in _cars:
		if is_instance_valid(car):
			car.queue_free()
	_cars.clear()
	_settling.clear()
	_settled_frames.clear()
	_last_position.clear()
	_bay_of.clear()
	_vehicle_of.clear()
	# _ride_heights is not cleared: it is what this spawner knows about a
	# chassis, not what it did this round.
	set_physics_process(false)


## The cars currently parked, for anything that wants to count them.
func parked_cars() -> Array[PlayerCar]:
	return _cars.duplicate()


## Which bay [param car] is parked in, or null if this spawner did not park it.
func bay_of(car: PlayerCar) -> ScoredParkingSpace:
	return _bay_of.get(car)


## How high [param vehicle]'s chassis sits above the tarmac, or a negative number
## if no car of that chassis has settled yet.
##
## A car [NpcDriver] drives is moved rather than simulated, so something has to
## know where the road is under it. Nothing here guesses: the number is the one a
## car of that chassis settled to on its own springs, and a chassis that has
## never been parked has no answer to give.
func ride_height(vehicle: DrivableVehicle) -> float:
	return _ride_heights.get(vehicle, -1.0)


## Every chassis this spawner has measured a ride height for. The lot fills from
## the catalog at the start of every round, so this is never empty by the time
## anything asks.
func measured_vehicles() -> Array[DrivableVehicle]:
	var out: Array[DrivableVehicle] = []
	for vehicle in _ride_heights:
		out.append(vehicle)
	return out


## Builds one of the lot's cars without parking it: the player's chassis with
## nobody in it, painted, out of the player's group and into the obstacle one.
## The caller adds it to the tree and decides where it goes.
func build(vehicle: DrivableVehicle) -> PlayerCar:
	if vehicle == null:
		return null
	var car := vehicle.spawn()
	if car == null:
		return null
	car.input_enabled = false
	# Set before it enters the tree: this is what keeps it out of the player's
	# group, and so out of every bay's measurements and the offroad clock.
	car.driven_by_player = false
	car.add_to_group(VEHICLE_GROUP)
	car.add_to_group(Obstacle.GROUP)
	_vehicle_of[car] = vehicle
	_paint(car)
	return car


## Hands [param car] over to [param to] -- it is leaving, and this spawner is no
## longer the thing that frees it.
func release(car: PlayerCar, to: Node) -> void:
	if not is_instance_valid(car):
		return
	_cars.erase(car)
	_settling.erase(car)
	_settled_frames.erase(car)
	_last_position.erase(car)
	_bay_of.erase(car)
	_vehicle_of.erase(car)
	if car.get_parent() != to:
		car.reparent(to, true)


## Takes [param car] on as the lot's furniture: it has parked itself in
## [param bay] and is not going anywhere else.
##
## It is frozen static rather than left kinematic, which is the difference
## between a parked car and a driven one: a static freeze is the cheap one, and
## nothing is going to move this again.
func adopt(car: PlayerCar, bay: ScoredParkingSpace) -> void:
	if not is_instance_valid(car):
		return
	if car.get_parent() != self:
		car.reparent(self, true)
	if not _cars.has(car):
		_cars.append(car)
	_bay_of[car] = bay
	car.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	_freeze(car)


func _physics_process(_delta: float) -> void:
	_waited_frames += 1
	var still_settling: Array[PlayerCar] = []
	for car in _settling:
		if not is_instance_valid(car):
			continue
		var frames: int = _settled_frames.get(car, 0)
		var moved := car.global_position.distance_to(_last_position.get(car, Vector3.INF))
		_last_position[car] = car.global_position
		if moved <= SETTLE_MOVEMENT:
			frames += 1
		else:
			frames = 0
		_settled_frames[car] = frames
		if frames >= SETTLE_FRAMES or _waited_frames >= SETTLE_GIVE_UP_FRAMES:
			_freeze(car)
			continue
		still_settling.append(car)
	_settling = still_settling
	if _settling.is_empty():
		set_physics_process(false)


## Puts one car in one bay, facing along the bay either way round -- backing in
## is as legal here as nosing in, and a lot where every car faces the same way
## looks stamped out.
func _park(bay: ScoredParkingSpace, vehicle: DrivableVehicle) -> void:
	var car := build(vehicle)
	if car == null:
		return
	var axis := bay.global_basis.x
	axis = Vector3(axis.x, 0.0, axis.z).normalized()
	if rng.randf() < 0.5:
		axis = -axis
	# Dropped from just above the road: the car finds its own ride height on its
	# own suspension, and is frozen there.
	var spot := bay.bay_centre()
	spot.y = bay.global_position.y + 0.2
	car.global_transform = Transform3D(Basis.looking_at(axis, Vector3.UP), spot)
	add_child(car)
	car.global_transform = Transform3D(Basis.looking_at(axis, Vector3.UP), spot)
	_bay_of[car] = bay
	_cars.append(car)
	_settling.append(car)
	_settled_frames[car] = 0
	_last_position[car] = car.global_position


## Stops a settled car simulating. Twenty live VehicleBody3Ds is the single most
## likely thing to sink the web build, and a parked car has nothing left to do:
## its wheels never turn again, so its visuals never need another frame either.
func _freeze(car: PlayerCar) -> void:
	if not is_instance_valid(car):
		return
	_measure_ride_height(car)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = true
	car.set_process(false)
	car.set_physics_process(false)


## Writes down how high this chassis sits once it has stopped bouncing, which is
## the one thing a car that is driven rather than simulated cannot work out for
## itself. Measured against the bay's own ground level, so it is a property of
## the car and not of where in the lot it happened to be parked.
func _measure_ride_height(car: PlayerCar) -> void:
	var vehicle: DrivableVehicle = _vehicle_of.get(car)
	var bay: ScoredParkingSpace = _bay_of.get(car)
	if vehicle == null or bay == null:
		return
	_ride_heights[vehicle] = car.global_position.y - bay.global_position.y


## Paints the bodywork, and only the bodywork.
##
## The material is duplicated first: the meshes share one resource, so tinting
## it in place would repaint every car in the lot, the player's included.
##
## Which surface is the bodywork is asked of the mesh rather than assumed. The
## SUV is one surface for the whole car; the minivan splits into Body, Optics
## and Glass, and painting all three gives it headlights and windows in the
## body colour -- a lot full of cars with hot pink glass.
func _paint(car: PlayerCar) -> void:
	if car.visuals == null:
		return
	var body := car.visuals.get_node_or_null(^"Body") as MeshInstance3D
	if body == null or body.mesh == null:
		return
	var surface := _bodywork_surface(body.mesh)
	if surface < 0:
		return
	var source_material := body.mesh.surface_get_material(surface)
	var material := (source_material.duplicate() if source_material != null
			else StandardMaterial3D.new()) as BaseMaterial3D
	if material == null:
		return
	material.albedo_color = Color.from_hsv(
			rng.randf(), rng.randf_range(0.15, 0.6), rng.randf_range(0.35, 0.9))
	body.set_surface_override_material(surface, material)


## The surface holding the paintwork: the one whose material says it is the
## body, or the first if none of them says anything. A single-surface car is
## its own bodywork.
func _bodywork_surface(mesh: Mesh) -> int:
	if mesh.get_surface_count() == 0:
		return -1
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material != null and material.resource_name.to_lower().contains("body"):
			return surface
	return 0


## Fisher-Yates, on the generator this system was seeded with, rather than
## [method Array.shuffle], which uses the global one.
func _shuffle(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = array[i]
		array[i] = array[j]
		array[j] = swap
