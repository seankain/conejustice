extends Node3D
## Composition root. Owns nothing, decides nothing.
##
## Main's whole job is to hold the level, the camera rig, the gameplay nodes and
## the HUD in one tree and kick things off. Game rules belong in SectionManager;
## resist the pull to grow this into a god object.

@onready var camera_rig: CameraRig = $CameraRig
@onready var cone_thrower: Node = $ConeThrower
@onready var section_manager: Node = $SectionManager
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	GameState.reset_run()
	# The run is started deliberately from the title screen once that exists.
	# Until then the camera simply sits at the rig's authored transform.
	# TODO: hand off to SectionManager.start_run().
