extends Node
## Continuous background music: one track at a time, drawn at random.
##
## A track is picked when the game starts and another is picked the moment that
## one ends, so the music runs for as long as the game does and never settles
## into the same order twice. Nothing in gameplay drives this: the rotation is
## deliberately independent of runs, sections and the title screen, because music
## that restarts every time the player retries reads as a bug.
##
## Each track is played once, to its end, and then handed over. Looping a track
## instead would be simpler and wrong: a looping stream never reports that it
## finished, so the rotation would stop on its first track and play that one
## forever.
##
## Like [SfxPlayer], streams are loaded rather than preloaded and a missing file
## degrades to silence with a warning. A preload of a file that has not been
## imported yet fails at compile time and takes the whole autoload with it.

const MUSIC_DIR := "res://Assets/Audio/"
## The rotation. Adding a file here is all it takes to put it in the draw.
const TRACK_FILES: Array[String] = [
	"music_track1.mp3",
	"music_track2.mp3",
	"music_track3.mp3",
]

const BUS_MUSIC := &"Music"

## Per-track trim. The Music bus already sits below the rest of the mix, so this
## is for pulling the tracks themselves into line with each other.
@export var volume_db: float = 0.0

## Zero seeds from the clock, so the order differs every launch. Set a non-zero
## seed to replay one exact sequence while working on the mix.
@export var random_seed: int = 0

var _rng := RandomNumberGenerator.new()
## The loaded tracks, in [constant TRACK_FILES] order minus any that would not
## load. Indices into this array, not into TRACK_FILES, are what gets drawn.
var _tracks: Array[AudioStream] = []
var _player: AudioStreamPlayer
## Index of the track playing now, or -1 before the first one.
var _current: int = -1


func _ready() -> void:
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_load_tracks()
	_build_player()
	play_random()


## Starts the rotation on a randomly drawn track, replacing whatever is playing.
## Called once on launch; exposed so a future mode switch can re-draw without
## reaching into the internals.
func play_random() -> void:
	if _tracks.is_empty():
		return
	_play(_draw_next())


## Draws a track other than the one playing, so a handover is always audible as a
## new track rather than as a track restarting. Every other track is equally
## likely. With a single track loaded there is no other one, and repeating it
## beats falling silent.
func _draw_next() -> int:
	if _tracks.size() <= 1:
		return 0
	if _current < 0:
		return _rng.randi_range(0, _tracks.size() - 1)
	# Drawn from the tracks that are not playing, then folded back over the one
	# that is. Rerolling until the draw misses would do the same job without a
	# bound on how long it takes.
	var index := _rng.randi_range(0, _tracks.size() - 2)
	if index >= _current:
		index += 1
	return index


func _play(index: int) -> void:
	_current = index
	_player.stream = _tracks[index]
	_player.play()


func _on_track_finished() -> void:
	_play(_draw_next())


func _load_tracks() -> void:
	for file in TRACK_FILES:
		var path := MUSIC_DIR + file
		if not ResourceLoader.exists(path):
			push_warning("MusicPlayer: no audio at %s, that track is out of the rotation." % path)
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			push_warning("MusicPlayer: %s is not an audio stream, leaving it out." % path)
			continue
		_stop_looping(stream)
		_tracks.append(stream)
	if _tracks.is_empty():
		push_warning("MusicPlayer: no tracks loaded from %s, the game will play no music."
				% MUSIC_DIR)


func _build_player() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = BUS_MUSIC
	_player.volume_db = volume_db
	_player.finished.connect(_on_track_finished)
	add_child(_player)


## Forces a stream to play once, whatever it was imported as. A track imported
## with looping on would never finish, and the rotation would never advance past
## it -- a failure that looks like "the random picker is broken" from the outside.
static func _stop_looping(stream: AudioStream) -> void:
	# Written through the property rather than through a cast, because mp3, Ogg
	# Vorbis and WAV each spell their loop flag on their own class and this
	# rotation has no business caring which of them a track was authored as.
	if &"loop" in stream:
		stream.set(&"loop", false)
	elif &"loop_mode" in stream:
		stream.set(&"loop_mode", AudioStreamWAV.LOOP_DISABLED)
