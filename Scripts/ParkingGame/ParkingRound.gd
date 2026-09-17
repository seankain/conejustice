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

## Pedestrians are the riskiest part of the port and the least load-bearing, so
## the cabinet can open without them (T15).
@export var pedestrians_enabled: bool = false

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
var _camera_scene: PackedScene = null
var _traffic: TrafficSpawner = null
var _camera: ChaseCamera = null
var _space: ScoredParkingSpace = null
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
		catalog: VehicleCatalog = null) -> void:
	_lot = lot
	_vehicle = vehicle
	_camera_scene = camera_scene
	_catalog = catalog


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
	_start_round(false)


func _process(delta: float) -> void:
	match state:
		State.ACTIVE:
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
	if _camera != null:
		_camera.start_idle_rotation()
	# The card first, then the reason. The HUD clears whatever banner was up when
	# a round ends -- a "GO!" from a round the player finished in under three
	# seconds, for one -- so the failure has to be said after that, not before.
	round_ended.emit(data)
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
	for bay in _bays():
		bay.clear()
	for zone in _offroad_zones():
		zone.reset()
	_place_car()
	# Filled after the car is placed, so a bay the player is sitting in is
	# cleared of them first.
	if _traffic != null:
		_traffic.fill(_bays(), level * ParkingRules.VEHICLES_PER_LEVEL)
	if _camera != null:
		_camera.snap_to_default()
	state = State.ACTIVE
	round_started.emit(level, seconds_remaining)
	message.emit(MESSAGE_GO)


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
	if _camera_scene == null:
		return
	_camera = _camera_scene.instantiate() as ChaseCamera
	car.add_child(_camera)


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
	# A car can straddle two bays. The one it entered most recently is the one
	# being scored, which is also the one it is most likely trying to park in.
	_space = bay


func _on_bay_exited(_leaving: PlayerCar, bay: ScoredParkingSpace) -> void:
	if _space == bay:
		_space = null


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


func _on_hit_obstacle(kind: Obstacle.Kind) -> void:
	if state != State.ACTIVE:
		return
	data.collisions.append(kind)


## The player asked for a respawn, or the kill plane gave them one. Either way
## the attempt is over: the source restarts the level on exactly this, and a car
## that just fell out of the world has no round left to finish.
func _on_respawned() -> void:
	if _placing or state != State.ACTIVE:
		return
	_start_round(false)
