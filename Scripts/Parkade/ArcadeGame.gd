class_name ArcadeGame
extends RefCounted
## One cabinet in the Parkade: a game the main menu can list and launch.
##
## Plain data. The registry lives in code on [Parkade] rather than as `.tres`
## files because adding a game is a one-line change either way, and a code
## registry cannot silently lose its scene path to a botched resource reimport.
##
## [member available] is deliberately separate from the scene existing: a game
## being half-ported is the normal state for a while, and the menu should say so
## rather than hand the player a scene that does not play yet.

## Stable identifier. Used by [method Parkade.launch] and nothing else, so it is
## safe to rename [member title] without touching any call site.
var id: StringName
var title: String
## One line under the title. The pitch, not the instructions.
var tagline: String
## The control scheme, shown dimmer under the tagline.
var controls: String
## Scene handed to [method SceneTree.change_scene_to_file].
var scene_path: String
## False while a game is still being built. The menu lists it, greyed, so the
## cabinet is visibly on its way rather than absent.
var available: bool


func _init(
		p_id: StringName,
		p_title: String,
		p_tagline: String,
		p_controls: String,
		p_scene_path: String,
		p_available: bool = true) -> void:
	id = p_id
	title = p_title
	tagline = p_tagline
	controls = p_controls
	scene_path = p_scene_path
	available = p_available
