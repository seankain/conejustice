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


## Temporary: the title screen starts the run once it exists. Until then Main
## starts it directly so the game is playable from F5.
@export var auto_start_run: bool = true


func _ready() -> void:
	if auto_start_run:
		section_manager.start_run()
