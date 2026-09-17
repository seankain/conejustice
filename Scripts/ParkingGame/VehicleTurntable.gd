class_name VehicleTurntable
extends Node3D
## One plate in the carousel: a car, turning slowly, with nothing underneath it
## but the plate.
##
## What it holds is the chassis scene's [code]Visuals[/code] subtree and not the
## chassis -- see [method DrivableVehicle.instantiate_preview]. A
## [VehicleBody3D] parented to a rotating node does not spin: the physics engine
## owns its transform, so it fights the turntable and then falls over. That is
## the single rule every chassis scene follows, and this is the thing it follows
## it for.

## Radians per second. Slow enough to read the shape of a car, fast enough that
## the screen is never still.
@export var spin_speed: float = 0.5
## Scale of a plate that is not the one being looked at.
@export var unfocused_scale: float = 0.78
## How far back an unfocused plate sits, in metres.
@export var unfocused_depth: float = 2.2
## Seconds a plate takes to come forward or fall back.
@export var focus_seconds: float = 0.25

@export_group("Plate")
## Radius of the disc the car stands on. Wide enough to sit under the longest
## car in the catalog.
@export var plate_radius: float = 3.4
@export var plate_height: float = 0.12
@export var plate_colour: Color = Color(0.11, 0.12, 0.15)

## The catalog entry this plate shows.
var vehicle: DrivableVehicle = null
var focused: bool = false

var _preview: Node3D = null
var _tween: Tween


## Builds the plate. Separate from [method Node._ready] because the rack decides
## what goes on which plate, and it decides at runtime from the catalog.
func show_vehicle(entry: DrivableVehicle) -> void:
	vehicle = entry
	if _preview != null:
		_preview.queue_free()
	_preview = entry.instantiate_preview()
	if _preview == null:
		return
	add_child(_preview)
	_add_plate()


## The disc under the car. Built here rather than in the scene because the rack
## builds its plates from the catalog, and a plate with no car on it would be
## a disc lit for nothing.
func _add_plate() -> void:
	var disc := MeshInstance3D.new()
	disc.name = "Plate"
	var mesh := CylinderMesh.new()
	mesh.top_radius = plate_radius
	mesh.bottom_radius = plate_radius
	mesh.height = plate_height
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = plate_colour
	material.metallic = 0.2
	material.roughness = 0.45
	disc.material_override = material
	# Under the car, not part of it: the car turns and the plate does not.
	disc.position = Vector3(0.0, -plate_height * 0.5, 0.0)
	add_child(disc)


func _process(delta: float) -> void:
	if _preview == null:
		return
	_preview.rotate_y(spin_speed * delta)


## Brings this plate forward, or sets it back. [param immediate] skips the
## tween, which is what the rack wants when it is first built.
func set_focused(value: bool, immediate: bool = false) -> void:
	focused = value
	var wanted_scale := Vector3.ONE if value else Vector3.ONE * unfocused_scale
	var wanted_position := Vector3(position.x, position.y, 0.0 if value else -unfocused_depth)
	if immediate:
		scale = wanted_scale
		position = wanted_position
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, ^"scale", wanted_scale, focus_seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"position", wanted_position, focus_seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
