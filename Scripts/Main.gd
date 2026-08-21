extends Node3D
## Composition root. Owns nothing, decides nothing.
##
## Main's whole job is to hold the level, the camera rig, the gameplay nodes and
## the HUD in one tree and kick things off. Game rules belong in SectionManager;
## resist the pull to grow this into a god object.

@onready var camera_rig: CameraRig = $CameraRig
@onready var cone_thrower: ConeThrower = $ConeThrower
@onready var section_manager: Node = $SectionManager
@onready var hud: CanvasLayer = $HUD


## Temporary: SectionManager owns the run state once it exists. Until then Main
## flips it on arrival so throwing is testable while walking the rail by hand.
## Delete this, and _on_travel_finished_debug, when sections drive the run.
@export var debug_engage_on_arrival: bool = true


func _ready() -> void:
	GameState.reset_run()
	# The run is started deliberately from the title screen once that exists.
	# TODO: hand off to SectionManager.start_run().
	if debug_engage_on_arrival:
		EventBus.travel_finished.connect(_on_travel_finished_debug)
		GameState.run_state = GameState.RunState.ENGAGED


func _on_travel_finished_debug(index: int) -> void:
	# The rig sets TRAVELLING on departure but deliberately never clears it,
	# so without this the throw lock would stay on after the first leg.
	GameState.run_state = (GameState.RunState.ENGAGED if index >= 0
			else GameState.RunState.RUN_OVER)
