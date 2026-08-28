@tool
extends EditorScript
## Prints the numbers a [VehicleProfile] wants, measured off the vehicle scenes
## themselves. Run it from the editor: File -> Run, or the Run button while this
## script is open.
##
## It exists because the alternative is guessing. The footprint in a profile is
## what every bay's room maths runs on, and a number that is a little small does
## not look wrong anywhere -- it just quietly lets two cars occupy the same patch
## of road. Measuring the mesh takes a second and is right.
##
## Nothing here writes to disk. It prints a block you paste into a .tres, so the
## numbers stay authored and tunable by hand; [member ParkingLot.verify_footprints]
## is what tells you later if one has drifted from its model.

## Scanned for scenes whose root is a [TargetCar]. Everything else is skipped.
const SCAN_DIRECTORY := "res://Scenes"

## The vehicle the parking bays were authored around. Every other vehicle's
## bay_height_offset is measured against this one, because the bays sit at the
## height *its* origin rests at, and that is the baseline the level encodes.
const REFERENCE_SCENE := "res://Scenes/SUV.tscn"


func _run() -> void:
	var reference := _bottom_of(REFERENCE_SCENE)
	if is_nan(reference):
		push_error("derive_vehicle_profile: could not measure the reference scene %s."
				% REFERENCE_SCENE)
		return

	var paths := _scene_paths(SCAN_DIRECTORY)
	paths.sort()
	var found := 0
	for path in paths:
		if _report(path, reference):
			found += 1
	if found == 0:
		push_warning("derive_vehicle_profile: no TargetCar scenes under %s." % SCAN_DIRECTORY)
	else:
		print("\n%d vehicle scene(s) measured. Paste each block into its "
				% found + "Assets/Vehicles/*.tres.")


## Measures one scene and prints its block. Returns whether it was a vehicle at
## all, so the summary can tell "nothing found" from "nothing matched".
func _report(path: String, reference: float) -> bool:
	var car := _instantiate_vehicle(path)
	if car == null:
		return false

	var bounds := VehicleProfile.measure_bounds(car)
	var label := path.get_file().get_basename()
	if bounds.size == Vector3.ZERO:
		push_warning("derive_vehicle_profile: %s has no meshes to measure." % label)
		car.free()
		return true

	# x across, z along: the same two axes ParkingSpace works in, and the reason
	# footprint is a Vector2 rather than the whole box.
	var footprint := Vector2(bounds.size.x, bounds.size.z)
	# Positive lifts the car. A model whose lowest point sits further below its
	# origin than the reference's needs raising by exactly that difference to put
	# its wheels back on the road.
	var offset := reference - bounds.position.y

	print("\n--- %s (%s) ---" % [label, path])
	print("scene = ExtResource(\"...\")  # %s" % path)
	print("footprint = Vector2(%.3f, %.3f)" % [footprint.x, footprint.y])
	print("bay_height_offset = %.4f" % offset)
	print("spawn_weight = 1.0")
	print("# height %.3f m, origin %.3f m above its lowest point"
			% [bounds.size.y, -bounds.position.y])
	print("# marker_height on the scene's TargetCar: try %.2f (mid-body)"
			% (bounds.position.y + bounds.size.y * 0.5))
	_report_fit(footprint)
	car.free()
	return true


## Says up front whether this vehicle can be parked in the level's bays at all.
## Finding that out here beats finding it out as an empty row and a warning.
func _report_fit(footprint: Vector2) -> void:
	var too_wide := PackedStringArray()
	var too_long := PackedStringArray()
	var bays := 0
	for node in _bays():
		bays += 1
		if footprint.x > node.bay_width:
			too_wide.append(String(node.name))
		elif footprint.y > node.bay_length:
			too_long.append(String(node.name))
	if bays == 0:
		print("# no open level to check bay fit against")
		return
	if too_wide.is_empty() and too_long.is_empty():
		print("# fits all %d bay(s) in the open scene" % bays)
		return
	if not too_wide.is_empty():
		print("# TOO WIDE for %d/%d bay(s): %s" % [too_wide.size(), bays, ", ".join(too_wide)])
	if not too_long.is_empty():
		print("# TOO LONG for %d/%d bay(s): %s" % [too_long.size(), bays, ", ".join(too_long)])
	print("# those bays will skip this vehicle rather than park it over the paint")


## Bays in whatever scene is open in the editor, or an empty list if none is.
func _bays() -> Array[ParkingSpace]:
	var bays: Array[ParkingSpace] = []
	var root := get_scene()
	if root == null:
		return bays
	for node in root.find_children("*", "Marker3D", true, false):
		var bay := node as ParkingSpace
		if bay != null:
			bays.append(bay)
	return bays


## The lowest point of a scene's meshes relative to its origin, or NAN if it is
## not a vehicle. Negative for anything whose origin sits above its wheels.
func _bottom_of(path: String) -> float:
	var car := _instantiate_vehicle(path)
	if car == null:
		return NAN
	var bounds := VehicleProfile.measure_bounds(car)
	car.free()
	return NAN if bounds.size == Vector3.ZERO else bounds.position.y


## Instantiates [param path] if it is a vehicle scene, else null. The node is
## never added to the tree -- [method VehicleProfile.measure_bounds] walks
## transforms by hand precisely so that measuring costs nothing but a free().
func _instantiate_vehicle(path: String) -> TargetCar:
	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		return null
	return packed.instantiate() as TargetCar


func _scene_paths(directory: String) -> PackedStringArray:
	var paths := PackedStringArray()
	var dir := DirAccess.open(directory)
	if dir == null:
		push_error("derive_vehicle_profile: cannot open %s." % directory)
		return paths
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := directory.path_join(entry)
		if dir.current_is_dir():
			paths.append_array(_scene_paths(full))
		elif entry.get_extension().to_lower() == "tscn":
			paths.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return paths
