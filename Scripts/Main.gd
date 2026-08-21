extends Node3D
## Composition root. Owns nothing, decides nothing.
##
## Main's whole job is to hold the level, the camera rig, the gameplay nodes and
## the HUD in one tree and kick things off. Game rules belong in SectionManager;
## resist the pull to grow this into a god object.

@onready var camera_rig: CameraRig = $CameraRig
@onready var cone_thrower: ConeThrower = $ConeThrower
@onready var section_manager: SectionManager = $SectionManager
@onready var hud: HUD = $HUD


func _ready() -> void:
	# The title screen starts the run. Main only makes sure the state behind it
	# is clean, so the first frame never shows a stale score from a hot reload.
	GameState.reset_run()
