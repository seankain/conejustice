extends Node
## Pooled one-shot sound effects.
##
## Everything is played from a fixed pool of players. Spawning a fresh
## AudioStreamPlayer per cone impact would thrash allocation exactly when the
## game is busiest, which is when a section full of cones is settling at once.
##
## Streams are loaded rather than preloaded, and a missing file degrades to
## silence with a warning. A preload of a file that has not been imported yet
## fails at compile time and takes the whole autoload with it.

enum Cue {
	THROW,
	CONE_CAR,
	CONE_GROUND,
	SETTLED,
	CAR_CONED,
	RELOAD,
	EMPTY,
	BEEP,
	CLEAR,
	TIMEOUT,
}

const SOUND_DIR := "res://Assets/Audio/"
const CUE_FILES := {
	Cue.THROW: "throw_whoosh.wav",
	Cue.CONE_CAR: "cone_car.wav",
	Cue.CONE_GROUND: "cone_ground.wav",
	Cue.SETTLED: "cone_settled.wav",
	Cue.CAR_CONED: "car_coned.wav",
	Cue.RELOAD: "reload_rustle.wav",
	Cue.EMPTY: "empty_click.wav",
	Cue.BEEP: "low_time_beep.wav",
	Cue.CLEAR: "section_clear.wav",
	Cue.TIMEOUT: "time_up.wav",
}

const BUS_SFX := &"SFX"
const BUS_UI := &"UI"

@export var pool_size_3d: int = 12
@export var pool_size_ui: int = 6
## Impacts are already rate limited per cone; this caps the whole frame, so a
## pile of cones settling together cannot produce a wall of clatter.
@export var max_impacts_per_frame: int = 3
## Impact speed treated as "as loud as it gets", in m/s.
@export var impact_reference_speed: float = 9.0
## Seconds between beeps once the clock is in the danger zone.
@export var beep_interval: float = 1.0

var _streams: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_ui: int = 0
var _impacts_this_frame: int = 0
var _beeping: bool = false
var _beep_accum: float = 0.0


func _ready() -> void:
	_load_streams()
	_build_pools()

	EventBus.cone_thrown.connect(_on_cone_thrown)
	EventBus.cone_impact.connect(_on_cone_impact)
	EventBus.cone_landed.connect(_on_cone_landed)
	EventBus.car_coned.connect(_on_car_coned)
	EventBus.reload_started.connect(_on_reload_started)
	EventBus.throw_refused_empty.connect(_on_throw_refused_empty)
	EventBus.timer_warning.connect(_on_timer_warning)
	EventBus.section_cleared.connect(_on_section_cleared)
	EventBus.section_timeout.connect(_on_section_timeout)
	EventBus.section_started.connect(_on_section_started)
	EventBus.run_started.connect(_stop_beeping)


func _process(delta: float) -> void:
	_impacts_this_frame = 0

	if not _beeping:
		return
	# Only a live section beeps. Carrying it into the travel tween or the
	# run-over screen would be nagging, not tension.
	if GameState.run_state != GameState.RunState.ENGAGED:
		return
	_beep_accum += delta
	if _beep_accum >= beep_interval:
		_beep_accum -= beep_interval
		play_ui(Cue.BEEP)


## Plays a cue at a world position, on the SFX bus.
func play_3d(cue: Cue, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(cue)
	if stream == null:
		return
	var player := _take_3d()
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Plays a cue without a position, on the UI bus. For the player's own actions
## and for anything that must read clearly wherever the camera is.
func play_ui(cue: Cue, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(cue)
	if stream == null:
		return
	var player := _take_ui()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _load_streams() -> void:
	for cue in CUE_FILES:
		var path: String = SOUND_DIR + CUE_FILES[cue]
		if ResourceLoader.exists(path):
			_streams[cue] = load(path)
		else:
			push_warning("SfxPlayer: no audio at %s, that cue will be silent." % path)


func _build_pools() -> void:
	for _i in pool_size_3d:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS_SFX
		p.max_distance = 40.0
		add_child(p)
		_pool_3d.append(p)
	for _i in pool_size_ui:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_UI
		add_child(p)
		_pool_ui.append(p)


## Prefers an idle player, and steals round-robin when every one is busy. A
## stolen sound is better than a dropped one at this pool size.
func _take_3d() -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	_next_3d = (_next_3d + 1) % _pool_3d.size()
	return _pool_3d[_next_3d]


func _take_ui() -> AudioStreamPlayer:
	for p in _pool_ui:
		if not p.playing:
			return p
	_next_ui = (_next_ui + 1) % _pool_ui.size()
	return _pool_ui[_next_ui]


func _on_cone_thrown(_remaining: int, _cooldown: float) -> void:
	play_ui(Cue.THROW, -4.0, randf_range(0.94, 1.06))


func _on_cone_impact(position: Vector3, speed: float, on_car: bool) -> void:
	if _impacts_this_frame >= max_impacts_per_frame:
		return
	_impacts_this_frame += 1
	# Harder hits are louder and brighter, which is most of what makes a throw
	# feel like it connected.
	var t := clampf(speed / impact_reference_speed, 0.0, 1.0)
	var volume := linear_to_db(lerpf(0.3, 1.0, t))
	var pitch := lerpf(0.88, 1.12, t) * randf_range(0.96, 1.04)
	if on_car:
		play_3d(Cue.CONE_CAR, position, volume, pitch)
	else:
		play_3d(Cue.CONE_GROUND, position, volume - 5.0, pitch)


func _on_cone_landed(car: Node3D, on_roof: bool) -> void:
	if is_instance_valid(car):
		play_3d(Cue.SETTLED, car.global_position + Vector3.UP, 0.0, 1.18 if on_roof else 1.0)


func _on_car_coned(car: Node3D) -> void:
	if is_instance_valid(car):
		play_3d(Cue.CAR_CONED, car.global_position + Vector3.UP)


func _on_reload_started(duration: float) -> void:
	# Repitched to the real lockout, so the rustle ends as throwing comes back
	# however reload_time is tuned.
	var pitch := 1.0
	var stream: AudioStream = _streams.get(Cue.RELOAD)
	if stream != null and duration > 0.0:
		pitch = clampf(stream.get_length() / duration, 0.25, 4.0)
	play_ui(Cue.RELOAD, -3.0, pitch)


func _on_throw_refused_empty() -> void:
	play_ui(Cue.EMPTY, -2.0)


func _on_timer_warning() -> void:
	_beeping = true
	_beep_accum = beep_interval


func _on_section_started(_index: int, _time_limit: float) -> void:
	_stop_beeping()


func _on_section_cleared(_index: int, _time_remaining: float) -> void:
	_stop_beeping()
	play_ui(Cue.CLEAR)


func _on_section_timeout(_index: int) -> void:
	_stop_beeping()
	play_ui(Cue.TIMEOUT)


func _stop_beeping() -> void:
	_beeping = false
	_beep_accum = 0.0
