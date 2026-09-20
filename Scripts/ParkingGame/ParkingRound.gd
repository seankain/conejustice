class_name ParkingRound
extends Node
## One round: the clock, the car, the bays, the grade, and what happens next.
##
## Ported from [code]Level.cs[/code]. Three things are different, and all three
## are the same kind of difference -- the source's version cannot survive being
## a cabinet in Parkade, or says the same thing twice.
##
## [b]It resolves nothing by path.[/b] The source reaches for
## [code]/root/Main/Level/Player[/code], [code]/root/Main/Menu[/code] and
## [code]/root/Main/Level/Player/SpringArm3D[/code] from inside
## [code]_Ready[/code]. This one is handed a lot and a car through
## [method configure] and finds the bays by group.
##
## [b]It starts a round in one method.[/b] The source has
## [code]ResetLevel[/code] and [code]NextLevel[/code], near-identical, one of
## which builds its [code]LevelData[/code] twice; the difference between them is
## whether the level number goes up, which is now an argument.
##
## [b]It owns the score.[/b] The source writes [code]level.Score[/code] from
## inside the parking space on every frame the player is in a bay. Here the bay
## reports measurements and the round writes them down.
##
## The HUD (T12) listens to the signals below. Nothing here reaches into a HUD,
## which is the other half of why the source's version needs absolute paths.

enum State {
	ACTIVE, ## The clock is running.
	OVER, ## Graded, holding on the score card before the next round.
}

## A new round has begun. [param seconds] is what the clock starts at, which
## shrinks as the levels go up.
signal round_started(level: int, seconds: float)
## The clock, every frame it is running.
signal time_changed(seconds_remaining: float)
## The player is in a bay and these are its numbers. The live grade readout
## reads this; it is the same [RoundData] the score card grades at the end, so
## the two cannot disagree.
signal measurements_changed(data: RoundData)
## The round is over, parked or not. The score card reads [param data].
signal round_ended(data: RoundData)
## Something worth saying across the middle of the screen: "GO!", or why the
## round ended.
signal message(text: String)

## The one-line reasons a round can end, shown by the HUD.
const MESSAGE_GO := "GO!"
const MESSAGE_FAILED := "FAILED TO PARK"
## ...and the two things the lot can do to you while it is running.
const MESSAGE_CAR_LEAVING := "A CAR IS BACKING OUT"
const MESSAGE_SPACE_TAKEN := "A RIVAL TOOK A SPACE"
## ...and what it says when you forget the lot has people and geese in it.
const MESSAGE_HIT_PERSON := "YOU HIT A PEDESTRIAN"
const MESSAGE_HIT_WILDLIFE := "YOU HIT A GOOSE"

## Whether anything lives in the lot: people walking in from their cars and
## geese crossing the aisle ([PedestrianSpawner]). On, and every level has them.
##
## Off empties the lot of them and keeps it empty, which is what the round-flow
## test wants while it measures a park -- the same job
## [member lot_events_enabled] does for the cars.
@export var pedestrians_enabled: bool = true:
	set(value):
		pedestrians_enabled = value
		if _pedestrians == null:
			return
		_pedestrians.enabled = value
		if not value:
			_pedestrians.reset()

## Whether the lot does anything but hold still: cars leaving, rivals arriving
## ([LotEvents]). Off gives the source's lot, which fills once per level and then
## waits -- which is what the round-flow test wants while it measures a park.
@export var lot_events_enabled: bool = true:
	set(value):
		lot_events_enabled = value
		if _events != null:
			_events.enabled = value

## Which level this is. Round one is level one.
var level: int = 1
var state: State = State.ACTIVE
## This round's tallies. Replaced, not cleared, when a round starts.
var data := RoundData.new()
var seconds_remaining: float = ParkingRules.DEFAULT_SECONDS
## The car the player is driving. Spawned here, from the chosen catalog entry.
var car: PlayerCar = null

var _lot: Node3D = null
var _vehicle: DrivableVehicle = null
var _catalog: VehicleCatalog = null
## The people and geese this lot can have in it. Null is a lot with nobody in
## it, which is not an error.
var _pedestrian_catalog: PedestrianCatalog = null
var _camera_scene: PackedScene = null
var _traffic: TrafficSpawner = null
## The lot's own traffic: what leaves, what turns up, and how likely either is.
var _events: LotEvents = null
## Everything in the lot that is on foot.
var _pedestrians: PedestrianSpawner = null
var _camera: ChaseCamera = null
## The bay being scored, or null when the car is in none.
var _space: ScoredParkingSpace = null
## Every bay the car is inside. More than one whenever it is sitting on a line,
## and a car swinging into a bay is briefly inside three.
var _occupied: Array[ScoredParkingSpace] = []
var _hold_remaining: float = 0.0
## True while [method _start_round] is putting the car back, so the respawn it
## does to place the car is not mistaken for the player asking for one.
var _placing: bool = false
## One generator for this system, seeded once, rather than the source's
## [code]Random.Shared[/code] reached for from three files.
var _rng := RandomNumberGenerator.new()


## Everything the round needs, before it enters the tree. [param catalog] is
## what the lot is filled from -- the same cars the player picks between.
func configure(
		lot: Node3D,
		vehicle: DrivableVehicle,
		camera_scene: PackedScene,
		catalog: VehicleCatalog = null,
		pedestrians: PedestrianCatalog = null) -> void:
	_lot = lot
	_vehicle = vehicle
	_camera_scene = camera_scene
	_catalog = catalog
	_pedestrian_catalog = pedestrians


func _ready() -> void:
	_rng.randomize()
	if _lot == null or _vehicle == null:
		push_error("ParkingRound: configure() must be called before the round enters the tree.")
		set_process(false)
		return
	_spawn_car()
	_connect_bays()
	_traffic = TrafficSpawner.new()
	_traffic.name = "Traffic"
	_traffic.catalog = _catalog
	_traffic.rng = _rng
	add_child(_traffic)
	_pedestrians = PedestrianSpawner.new()
	_pedestrians.name = "Pedestrians"
	_pedestrians.catalog = _pedestrian_catalog
	_pedestrians.rng = _rng
	_pedestrians.enabled = pedestrians_enabled
	add_child(_pedestrians)
	_events = LotEvents.new()
	_events.name = "LotEvents"
	_events.catalog = _catalog
	_events.traffic = _traffic
	_events.pedestrians = _pedestrians
	_events.rng = _rng
	_events.enabled = lot_events_enabled
	_events.car_leaving.connect(_on_car_leaving)
	_events.rival_parked.connect(_on_rival_parked)
	add_child(_events)
	_start_round(false)


func _process(delta: float) -> void:
	match state:
		State.ACTIVE:
			_update_scored_bay()
			if state != State.ACTIVE:
				# The car was already at rest in the bay that just became the
				# one being scored, so that was the round.
				return
			seconds_remaining = maxf(seconds_remaining - delta, 0.0)
			time_changed.emit(seconds_remaining)
			if is_zero_approx(seconds_remaining):
				end_round()
		State.OVER:
			_hold_remaining -= delta
			if _hold_remaining <= 0.0:
				# A pass moves on; anything worse re-runs the same level with
				# the same clock.
				_start_round(data.passed())


## Seconds on the clock for [param for_level]: the default, less a slice per
## level reached, never under the floor.
##
## The source computes this as [code]DEFAULT - level * DECREMENT[/code], which
## makes its first level 55 seconds if it is reached by a reset and 60 if it is
## the one the game booted into. Counting from level one removes that.
static func seconds_for_level(for_level: int) -> float:
	var seconds := ParkingRules.DEFAULT_SECONDS \
			- float(for_level - 1) * ParkingRules.SECONDS_PER_LEVEL
	return clampf(seconds, ParkingRules.MIN_SECONDS, ParkingRules.DEFAULT_SECONDS)


## Ends the round where it stands: grades it, holds on the card, and spins the
## camera around the car while it does.
func end_round() -> void:
	if state == State.OVER:
		return
	state = State.OVER
	_hold_remaining = ParkingRules.ROUND_OVER_SECONDS
	data.parked_in_space = _space != null
	data.seconds_offroad = _offroad_seconds()
	if car != null:
		car.input_enabled = false
	# The lot holds still while the card is up: a rival still creeping into a bay
	# behind the score card would be the only thing moving on screen, and so
	# would a goose.
	if _events != null:
		_events.stop()
	if _pedestrians != null:
		_pedestrians.stop()
	if _camera != null:
		_camera.start_idle_rotation()
	# The card first, then the reason. The HUD clears whatever banner was up when
	# a round ends -- a "GO!" from a round the player finished in under three
	# seconds, for one -- so the failure has to be said after that, not before.
	round_ended.emit(data)
	SfxPlayer.play_ui(SfxPlayer.Cue.ROUND_OVER)
	if not data.parked_in_space:
		message.emit(MESSAGE_FAILED)


## Starts a round. [param advance] is the whole difference between the source's
## NextLevel and its ResetLevel.
func _start_round(advance: bool) -> void:
	if advance:
		level += 1
	data = RoundData.new()
	seconds_remaining = seconds_for_level(level)
	_space = null
	_occupied.clear()
	# Before the bays are cleared and the lot refilled: every car that was
	# driving itself, and everything that was walking, belongs to the round that
	# just ended.
	if _events != null:
		_events.reset()
	if _pedestrians != null:
		_pedestrians.reset()
	for bay in _bays():
		bay.clear()
	for zone in _offroad_zones():
		zone.reset()
	_place_car()
	# Filled after the car is placed, so a bay the player is sitting in is
	# cleared of them first.
	if _traffic != null:
		_traffic.fill(_bays(), level * ParkingRules.VEHICLES_PER_LEVEL)
	# Started on the lot the player is about to see, and only once it is full.
	if _events != null:
		_events.begin(_bays(), level, car, _entrance())
	# After the events, because the lanes and aisle sides it walks people across
	# are worked out once, by them, and handed on rather than computed twice.
	if _pedestrians != null and _events != null:
		_pedestrians.player = car
		_pedestrians.begin(
				_bays(), level, _events.lot_geometry(), _building_entrance())
	if _camera != null:
		_camera.snap_to_default()
	state = State.ACTIVE
	round_started.emit(level, seconds_remaining)
	message.emit(MESSAGE_GO)
	SfxPlayer.play_ui(SfxPlayer.Cue.ROUND_START)


## Puts the car back on the lot's respawn marker and hands it back to the
## player.
func _place_car() -> void:
	if car == null:
		return
	_placing = true
	car.respawn()
	_placing = false
	car.input_enabled = true


func _spawn_car() -> void:
	car = _vehicle.spawn()
	if car == null:
		return
	_lot.add_child(car)
	car.hit_obstacle.connect(_on_hit_obstacle)
	car.respawned.connect(_on_respawned)
	var engine := EngineAudio.new()
	engine.name = "EngineAudio"
	car.add_child(engine)
	if _camera_scene == null:
		return
	_camera = _camera_scene.instantiate() as ChaseCamera
	# Into the lot, beside the car, and then pointed at it -- not added to the
	# car. A camera parented to a [VehicleBody3D] inherits the body's roll,
	# pitch and bounce along with its heading, which is a view that tips into
	# every turn and shakes over every kerb. [ChaseCamera] follows the car
	# instead and takes only where it is and which way it is pointing.
	_lot.add_child(_camera)
	_camera.follow(car)


## Whether the round's camera wants the pointer captured. Asked by the game root
## after a pause, which had to release it to show a menu.
func camera_captures_mouse() -> bool:
	return _camera != null and _camera.capture_mouse


func _connect_bays() -> void:
	for bay in _bays():
		bay.player_entered.connect(_on_bay_entered.bind(bay))
		bay.player_exited.connect(_on_bay_exited.bind(bay))
		bay.measured.connect(_on_bay_measured.bind(bay))
		bay.player_settled.connect(_on_bay_settled.bind(bay))


func _bays() -> Array[ScoredParkingSpace]:
	var bays: Array[ScoredParkingSpace] = []
	for node in get_tree().get_nodes_in_group(ScoredParkingSpace.GROUP):
		var bay := node as ScoredParkingSpace
		if bay != null:
			bays.append(bay)
	return bays


func _offroad_zones() -> Array[OffroadZone]:
	var zones: Array[OffroadZone] = []
	if _lot == null:
		return zones
	for node in _lot.find_children("*", "Area3D", true, false):
		var zone := node as OffroadZone
		if zone != null:
			zones.append(zone)
	return zones


func _offroad_seconds() -> float:
	var total := 0.0
	for zone in _offroad_zones():
		total += zone.seconds_offroad
	return total


func _on_bay_entered(_entering: PlayerCar, bay: ScoredParkingSpace) -> void:
	if not _occupied.has(bay):
		_occupied.append(bay)
	_update_scored_bay()


func _on_bay_exited(_leaving: PlayerCar, bay: ScoredParkingSpace) -> void:
	_occupied.erase(bay)
	_update_scored_bay()


## Picks the bay to score: of the bays the car is inside, the one its middle is
## nearest.
##
## [b]Not the one it entered most recently[/b], which is what this used to do
## and is what made a good park go unnoticed. A car swings into a bay nose
## first and sweeps its tail through the bay next door, so the last bay entered
## is as likely to be the neighbour it brushed as the one it is parking in --
## and when it straightened up and left that neighbour again, the round was
## left scoring no bay at all. The car was then sitting squarely between the
## lines with nothing watching it, which is why parking properly did nothing
## and parking on the line, where the car never leaves the bay it entered last,
## worked.
func _update_scored_bay() -> void:
	var nearest: ScoredParkingSpace = null
	var nearest_distance := INF
	if car != null:
		for bay in _occupied:
			var distance := bay.centre_distance(car)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = bay
	_space = nearest
	# A bay can come to rest before it is the one being scored -- a car stopped
	# on a line settles in both at once -- so the bay is asked, rather than
	# waited on to say it again.
	if _space != null and _space.settled and state == State.ACTIVE:
		end_round()


func _on_bay_measured(
		angle: float, centre_distance: float, over_left: bool, over_right: bool,
		bay: ScoredParkingSpace) -> void:
	if state != State.ACTIVE or bay != _space:
		return
	data.parking_angle = angle
	data.centre_distance = centre_distance
	data.over_left_line = over_left
	data.over_right_line = over_right
	data.parked_in_space = true
	measurements_changed.emit(data)


func _on_bay_settled(_settled: PlayerCar, bay: ScoredParkingSpace) -> void:
	if state != State.ACTIVE or bay != _space:
		return
	end_round()


## Where cars come into the lot from. The player's own respawn marker, for want
## of a better authority on which end of the lot is the front -- a lot that grew
## a proper entrance marker would name it here.
func _entrance() -> Vector3:
	var markers := get_tree().get_nodes_in_group(PlayerCar.RESPAWN_GROUP)
	if markers.is_empty():
		return Vector3.INF
	var marker := markers[0] as Node3D
	return marker.global_position if marker != null else Vector3.INF


## Where anybody on foot in this lot is headed. Infinite when the lot has no
## entrance marked, and a walk then ends at the lot's own gate instead.
func _building_entrance() -> Vector3:
	var markers := get_tree().get_nodes_in_group(PedestrianSpawner.DESTINATION_GROUP)
	if markers.is_empty():
		return Vector3.INF
	var marker := markers[0] as Node3D
	return marker.global_position if marker != null else Vector3.INF


func _on_car_leaving(_bay: ScoredParkingSpace) -> void:
	# Worth saying out loud: it is a space that was not there when the round
	# started, and the player is probably looking somewhere else.
	message.emit(MESSAGE_CAR_LEAVING)


func _on_rival_parked(_bay: ScoredParkingSpace) -> void:
	message.emit(MESSAGE_SPACE_TAKEN)


func _on_hit_obstacle(kind: Obstacle.Kind) -> void:
	if state != State.ACTIVE:
		return
	data.collisions.append(kind)
	if car != null:
		SfxPlayer.play_3d(SfxPlayer.Cue.CAR_IMPACT, car.global_position)
	# Said out loud, because a body going over behind the camera is easy to miss
	# and the score card is the only other place it shows up.
	if kind == Obstacle.Kind.PERSON:
		message.emit(MESSAGE_HIT_PERSON)
	elif kind == Obstacle.Kind.WILDLIFE:
		message.emit(MESSAGE_HIT_WILDLIFE)


## The player asked for a respawn, or the kill plane gave them one. Either way
## the attempt is over: the source restarts the level on exactly this, and a car
## that just fell out of the world has no round left to finish.
func _on_respawned() -> void:
	if _placing or state != State.ACTIVE:
		return
	_start_round(false)
