class_name EngineAudio
extends AudioStreamPlayer3D
## The engine note, pitched by how hard the car is working.
##
## Nothing in the source makes a sound at all; this is the note the cabinet
## needs to feel like a car rather than a diagram. It is a node on the car
## rather than a cue through [SfxPlayer] because it is continuous: the pool
## there is for one-shots, and an engine that had to be re-triggered would
## stutter every time it looped.
##
## The loop is a placeholder from [code]Tools/generate_placeholder_audio.py[/code],
## built from a whole number of cycles of its own fundamental so the seam does
## not click. Replacing it with a recording means keeping that property and the
## filename; nothing here changes.

const STREAM_PATH := "res://Assets/Audio/engine_loop.wav"

## Pitch at a standstill, and at [member PlayerCar.top_speed]. The sample's own
## pitch sits at the idle end, so the range is what the recording has to hold up
## across.
@export var idle_pitch: float = 0.75
@export var full_pitch: float = 2.1
## Decibels at idle, and under full throttle.
@export var idle_volume_db: float = -22.0
@export var driving_volume_db: float = -8.0
## How quickly the note follows the car. Slow enough that a kerb strike does not
## sound like a gear change.
@export var response: float = 4.0

## The car this belongs to. Its own parent, unless something says otherwise.
@export var car: PlayerCar

var _pitch: float = 1.0
var _volume: float = -22.0


func _ready() -> void:
	if car == null:
		car = get_parent() as PlayerCar
	var stream_resource := load(STREAM_PATH)
	if stream_resource == null:
		# Same rule as SfxPlayer: a missing sound is silence and a warning, not
		# a broken car.
		push_warning("EngineAudio: no engine loop at %s." % STREAM_PATH)
		set_process(false)
		return
	stream = stream_resource
	bus = &"SFX"
	pitch_scale = idle_pitch
	volume_db = idle_volume_db
	_pitch = idle_pitch
	_volume = idle_volume_db
	play()


func _process(delta: float) -> void:
	if car == null:
		return
	# Engine load, roughly: how fast it is going against how fast it can, plus
	# whatever the throttle is asking for. A car pushing against a wall is
	# working hard at no speed at all, and should sound like it.
	var speed_fraction := clampf(absf(car.speed()) / maxf(car.top_speed, 0.01), 0.0, 1.0)
	var throttle := clampf(absf(car.engine_force) / maxf(car.engine_power, 0.01), 0.0, 1.0)
	var load_fraction := clampf(maxf(speed_fraction, throttle * 0.6), 0.0, 1.0)

	_pitch = lerpf(_pitch, lerpf(idle_pitch, full_pitch, load_fraction), delta * response)
	_volume = lerpf(_volume, lerpf(idle_volume_db, driving_volume_db, load_fraction), delta * response)
	pitch_scale = _pitch
	volume_db = _volume
