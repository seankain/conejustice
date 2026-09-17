class_name VehicleSelect
extends Node3D
## The screen between picking the cabinet and driving it: a carousel of cars,
## each turning on its own plate, in the San Francisco Rush shape.
##
## It is a 3D scene rather than a [Control] because the cars are models. Picking
## a car is only worth a screen of its own because both cabinets share real
## vehicle meshes -- a list of names would not be.
##
## The rack is built at [method Node._ready] from the catalog, so adding a car
## to the game is a [code].tres[/code] and no change here. Nothing is lit except
## the plate at the front: the focused car is the one standing in the key light,
## which is most of the arcade look for one light and no shader.
##
## Escape is not handled here on purpose. [Parkade] takes it as unhandled input
## and leaves the cabinet, and this screen has no pause menu to consume it
## first.

## Emitted when the player commits to a car. [ParkingGame] frees this scene and
## starts the round in it.
signal vehicle_confirmed(vehicle: DrivableVehicle)

## Metres between plates.
@export var plate_spacing: float = 6.0
## Seconds one step of the carousel takes. Short, and eased, so a held key steps
## rather than slides.
@export var step_seconds: float = 0.28

@export_group("Nodes")
@export var rack: Node3D
@export var name_label: Label
@export var stats_label: Label
@export var hint_label: Label

## What to show. Set by [ParkingGame] before this scene enters the tree.
var catalog: VehicleCatalog = null
## Which plate is at the front.
var index: int = 0

var _plates: Array[VehicleTurntable] = []
var _tween: Tween


func _ready() -> void:
	if rack == null:
		push_error("VehicleSelect: no rack node.")
		return
	var cars := catalog.usable() if catalog != null else [] as Array[DrivableVehicle]
	if cars.is_empty():
		push_error("VehicleSelect: the catalog has no usable cars.")
		return
	for i in cars.size():
		var plate := VehicleTurntable.new()
		plate.name = "Plate%d" % i
		plate.position = Vector3(float(i) * plate_spacing, 0.0, 0.0)
		rack.add_child(plate)
		plate.show_vehicle(cars[i])
		plate.set_focused(i == index, true)
		_plates.append(plate)
	rack.position.x = 0.0
	_show_stats()
	if hint_label != null:
		hint_label.text = "A D  or  ARROWS   choose        ENTER / CLICK   drive        ESC   back"


func _unhandled_input(event: InputEvent) -> void:
	if _plates.is_empty():
		return
	if event.is_action_pressed(&"steer_left") or event.is_action_pressed(&"ui_left"):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"steer_right") or event.is_action_pressed(&"ui_right"):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"throw_cone"):
		# throw_cone is this project's left mouse button. A click anywhere takes
		# the car at the front rather than the car under the pointer: the one at
		# the front is the one the screen is about.
		confirm()
		get_viewport().set_input_as_handled()


## Moves the carousel by [param direction] plates, stopping at either end
## rather than wrapping -- a carousel that wraps makes the ends invisible, and
## with two cars it would just flicker.
func _step(direction: int) -> void:
	var wanted := clampi(index + direction, 0, _plates.size() - 1)
	if wanted == index:
		return
	_plates[index].set_focused(false)
	index = wanted
	_plates[index].set_focused(true)
	_show_stats()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(rack, ^"position:x", -float(index) * plate_spacing, step_seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Commits to the car at the front.
func confirm() -> void:
	if _plates.is_empty():
		return
	vehicle_confirmed.emit(_plates[index].vehicle)


func _show_stats() -> void:
	var vehicle := _plates[index].vehicle
	if name_label != null:
		name_label.text = vehicle.display_name
	if stats_label == null:
		return
	# Only what DrivableVehicle actually carries. A handling stat nothing reads
	# would be a number the screen made up.
	stats_label.text = "\n".join([
		"WEIGHT      %d kg" % roundi(vehicle.mass),
		"PULL        %d N per wheel" % roundi(vehicle.engine_power),
		"TOP SPEED   %d m/s" % roundi(vehicle.top_speed),
		"LOCK        %d deg" % roundi(rad_to_deg(vehicle.max_steer)),
	])
