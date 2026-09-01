@tool
class_name ParkingSpace
extends Marker3D
## One painted parking bay: where a car gets put, and the rule for whether the
## car in it is parked legally.
##
## The bay owns both halves of that on purpose. It generates the pose a car is
## placed at *and* it measures a pose to say whether that car is a violator, so
## the label the game scores against is derived from the same geometry the player
## is looking at. [ParkingLot] generates then measures rather than generating and
## assuming, which is what stops a tuning change from quietly producing cars that
## score one way and read the other.
##
## Axes follow Marker3D: local -Z is the direction a nosed-in car faces, local X
## runs across the bay. A car backed in is parked exactly as legally as one nosed
## in, which is why [method yaw_error_degrees] folds at 90 degrees.
##
## The node sits where a parked car's *origin* sits, a few centimetres above the
## road rather than on it: cars are placed at the bay's own height, so a bay
## dragged around in the editor never needs its cars re-levelled afterwards.

## Bays join this so a restart can sweep every one of them clean, including any
## that no [CameraStop] happens to reference.
const GROUP := &"parking_spaces"

enum Role {
	RANDOM, ## Rolled per run. The default, and the whole point of the feature.
	VIOLATOR, ## Always occupied, always parked badly.
	INNOCENT, ## Always occupied, always parked correctly.
	EMPTY, ## Never occupied.
}

## Chance a car is backed into the bay rather than nosed in. Both are legal, and
## the mix is most of what stops a full row from looking stamped out.
const REVERSED_CHANCE := 0.35
## Fraction of the legal band a correctly parked car is allowed to use. A car
## sitting exactly on the tolerance line reads as a violation to the player, and
## the player's read is the game.
const LEGAL_JITTER := 0.55
## Past this, the fold at 90 degrees starts calling a car legal again: it reads
## as parked the other way round rather than as parked badly.
const MAX_VIOLATION_YAW := 80.0

const MARKING_COLOUR := Color(0.88, 0.88, 0.82)
const GIZMO_BAY_COLOUR := Color(0.35, 0.85, 1.0)
const GIZMO_LEGAL_COLOUR := Color(0.45, 1.0, 0.55)
## Editor lines are lifted off the paint so the two do not z-fight in the viewport.
const GIZMO_LIFT := 0.02

enum _Fault { LATERAL, LONGITUDINAL, YAW }

## What gets parked here. Leave on RANDOM unless a bay has to be pinned for
## pacing, e.g. a first area that should always have something to throw at.
@export var role: Role = Role.RANDOM

@export_group("Bay")
## Bay size along local Z, the direction a car points.
@export var bay_length: float = 5.2:
	set(value):
		bay_length = maxf(value, 0.1)
		_rebuild()
## Bay size across local X. Keep it under the spacing between neighbouring bays.
@export var bay_width: float = 2.4:
	set(value):
		bay_width = maxf(value, 0.1)
		_rebuild()
## Chance a bay left spare, once the violators and the guaranteed innocents have
## been placed, gets a car at all. Gaps in the row are what stop every area from
## looking like the same wall of cars.
@export_range(0.0, 1.0) var occupancy_chance: float = 0.8

@export_group("Legal tolerance")
## How far across the bay a car's centre may sit and still read as parked in it.
@export var legal_lateral: float = 0.22:
	set(value):
		legal_lateral = maxf(value, 0.0)
		_rebuild()
## How far along the bay a car's centre may sit, i.e. how much nose-out is fine.
@export var legal_longitudinal: float = 0.55:
	set(value):
		legal_longitudinal = maxf(value, 0.0)
		_rebuild()
## Degrees of crookedness allowed. Folded at 90, so backed in is still fine.
@export_range(0.0, 45.0) var legal_yaw_degrees: float = 7.0

@export_group("Violation")
## Metres past the legal band at which a bad park starts. This gap is what keeps
## a violator unmistakable instead of borderline.
@export var violation_margin: float = 0.20
## Range past that margin, across the bay. How much of it a car actually gets is
## decided by [ParkingLot] from the room beside that bay: straddling into an
## empty space is worth all of this, straddling next to a parked car is not.
@export var violation_lateral_reach: float = 0.45
## Range past that margin, along the bay. This is the one that reads best from
## the camera, so it gets the most room.
@export var violation_longitudinal_reach: float = 0.85
@export var violation_yaw_margin: float = 9.0
## Kept short enough that a crooked car sweeps its corners no further sideways
## than a straddling one is allowed to sit. Widen it and cars in a tight row
## start clipping through each other.
@export var violation_yaw_reach: float = 12.0
## Chance a violator is also sticking out of its bay, on top of whatever else it
## is doing wrong. One fault reads cleanest; a second now and then reads
## worst-offender.
@export_range(0.0, 1.0) var second_fault_chance: float = 0.35

@export_group("Markings")
## Paints the bay on the road. Without it the player has nothing to judge a car
## against and the whole innocent/violator read falls apart, so this is a
## debugging switch rather than a style one.
@export var paint_markings: bool = true:
	set(value):
		paint_markings = value
		_rebuild()
@export var marking_width: float = 0.12:
	set(value):
		marking_width = maxf(value, 0.01)
		_rebuild()
## Local height of the paint. The bay node sits at a parked car's origin, which
## is above the road, so this is negative.
@export var marking_height: float = -0.015:
	set(value):
		marking_height = value
		_rebuild()

## The car parked here this run, or null. Written by [ParkingLot]; a bay never
## spawns anything itself.
var occupant: Node3D = null

var _paint: MeshInstance3D


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_rebuild()


## The bay's pose without any inherited scale. Every measurement below is taken
## against this rather than against global_transform.
func bay_transform() -> Transform3D:
	return global_transform.orthonormalized()


## The transform a car parked here sits at. [param legal] picks which side of the
## bay's own tolerance the pose lands on.
##
## [param room] is how far a car may reach each way across the bay before it
## would be standing inside a neighbour -- x towards local -X, y towards +X, INF
## on a side with nothing beside it, and negative on a side where something has
## already taken the space. [param car_footprint] is that car's width and length,
## which is what turns room into an angle. Only [ParkingLot] can work either of
## them out, because only the lot knows what else is parked in the row.
##
## Both poses use them, and for opposite reasons: a badly parked car takes as
## much of the room as its fault needs, and a correctly parked one is pushed
## across its bay by whatever room is left. Neither has a default. They used to,
## back when every car on the street was the same SUV and a stand-in was
## harmless; with a pool of models a wrong footprint silently hands a car an angle
## it does not have the room for, so the caller has to say what it is placing.
func pose(rng: RandomNumberGenerator, legal: bool, room: Vector2,
		car_footprint: Vector2) -> Transform3D:
	if legal:
		return _legal_pose(rng, room, car_footprint)
	return _violation_pose(rng, room, car_footprint)


## How far off centre a legally parked car here can be pushed and still read as
## parked properly.
##
## [ParkingLot] uses it as what this bay is willing to give up to a car parked
## badly beside it: an innocent shifts over rather than being parked through, and
## the lot has to know how far that goes while it is still deciding how much room
## the violator gets.
func legal_give() -> float:
	return legal_lateral * LEGAL_JITTER


## Whether a vehicle this size can be parked here at all.
##
## The test is containment by the paint: a body wider or longer than its own bay
## hangs out of it however carefully it is placed, which would make it a violator
## by mesh rather than by pose -- and the player, looking at a car that is
## squarely in the middle of its lines and still over them, would have no way to
## read it. Such a vehicle is simply not a candidate for this bay.
##
## It says nothing about the neighbours on purpose. How much room a car has
## beside it depends on what else the run decided to park there, which only
## [ParkingLot] is in a position to know.
func fits(footprint: Vector2) -> bool:
	return footprint.x <= bay_width and footprint.y <= bay_length


## A car's centre in bay-local metres: x across the bay, z along it.
func offset_in_bay(xform: Transform3D) -> Vector3:
	return bay_transform().affine_inverse() * xform.origin


## How crooked a car sits, in degrees, folded at 90 so that a car backed in reads
## as zero. Backing into a space is not an offence.
func yaw_error_degrees(xform: Transform3D) -> float:
	var facing := bay_transform().basis.inverse() * (-xform.basis.orthonormalized().z)
	var degrees := absf(rad_to_deg(atan2(facing.x, -facing.z)))
	if degrees > 90.0:
		degrees = 180.0 - degrees
	return degrees


## The rule the whole feature turns on. Everything else here generates poses;
## this is the only thing that decides what one means.
func is_legally_parked(xform: Transform3D) -> bool:
	var offset := offset_in_bay(xform)
	if absf(offset.x) > legal_lateral:
		return false
	if absf(offset.z) > legal_longitudinal:
		return false
	return yaw_error_degrees(xform) <= legal_yaw_degrees


func occupy(car: Node3D) -> void:
	occupant = car


func vacate() -> void:
	occupant = null


## The car parked here, or null once it has been freed. Prefer this over reading
## [member occupant] directly: a car from a previous run may still be referenced
## for the frame between queue_free() and the node actually going away.
func get_occupant() -> Node3D:
	if occupant != null and not is_instance_valid(occupant):
		occupant = null
	return occupant


## A pose inside the bay's own tolerance, fitted into whatever room is left over
## once the badly parked cars have taken theirs.
##
## The yaw is settled first because it decides how much of the bay this car needs:
## a car sitting even slightly crooked reaches further across than its own width,
## and in a tight row that overhang is the difference between fitting beside a bad
## park and not. What is left of the room after paying for it is what the car has
## to shift across in.
func _legal_pose(rng: RandomNumberGenerator, room: Vector2,
		car_footprint: Vector2) -> Transform3D:
	var ceiling := _legal_yaw_ceiling(room, car_footprint)
	var yaw := rng.randf_range(-ceiling, ceiling)
	var overhang := _across(car_footprint, yaw) - car_footprint.x * 0.5
	return _pose(
			_legal_lateral(rng, Vector2(room.x - overhang, room.y - overhang)),
			rng.randf_range(-legal_longitudinal, legal_longitudinal) * LEGAL_JITTER,
			yaw,
			rng.randf() < REVERSED_CHANCE)


## The most crookedness a correctly parked car here can afford, given its room.
##
## Bounded before the angle is rolled rather than clamped after, because a car
## that has already been turned cannot be untangled by shifting it: sitting out of
## square costs width on *both* sides at once, and the shift across the bay can
## only pay for one of them. Rolling an angle the bay cannot afford and then
## shifting anyway is how a legally parked car ends up reaching further across the
## row than the room it was given -- which nothing catches when the bay it reaches
## into belongs to a section the run has not filled yet.
func _legal_yaw_ceiling(room: Vector2, car_footprint: Vector2) -> float:
	# The shift can buy back a legal_give() on the tighter side, and what is spare
	# on one side cannot pay for the other, so the two sides also have to average
	# out. Whichever binds first is the overhang this car can afford.
	var slack := minf(minf(room.x, room.y) + legal_give(), (room.x + room.y) * 0.5)
	return clampf(_yaw_ceiling(slack, car_footprint), 0.0,
			legal_yaw_degrees * LEGAL_JITTER)


## Where across the bay a legally parked car sits, given the room it has.
##
## The legal band is never left: a car sitting on its own tolerance line reads as
## a violation, and the player's read is the game. Inside it the car goes wherever
## the room allows, which is what lets an innocent park beside a violator at all
## -- shifted up against the far line because someone took half its space is
## exactly what a real street looks like. When the room asks for more than the
## band has to give, this returns the least this car can be in anybody's way and
## [ParkingLot] decides whether that will do.
func _legal_lateral(rng: RandomNumberGenerator, room: Vector2) -> float:
	var give := legal_give()
	var low := maxf(-give, -room.x)
	var high := minf(give, room.y)
	if low > high:
		# Crowded from both sides by more than the band can answer. Midway between
		# the two is the least this car can be in anybody's way; whether that is
		# little enough to park here at all is [ParkingLot]'s call, not the bay's.
		return clampf((room.y - room.x) * 0.5, -give, give)
	return rng.randf_range(low, high)


func _violation_pose(rng: RandomNumberGenerator, room: Vector2,
		car_footprint: Vector2) -> Transform3D:
	# The headline fault: what this car is doing wrong. Drifting sideways and
	# sitting crooked both need room beside the bay, so a car boxed in on both
	# sides can only offend by sticking out, which needs no room at all.
	var choices: Array[int] = [_Fault.LONGITUDINAL]
	if maxf(room.x, room.y) > _violation_floor():
		choices.append(_Fault.LATERAL)
	var yaw_ceiling := _yaw_ceiling(minf(room.x, room.y), car_footprint)
	if yaw_ceiling > legal_yaw_degrees + violation_yaw_margin:
		choices.append(_Fault.YAW)

	var lateral := 0.0
	var longitudinal := 0.0
	var yaw := 0.0
	match choices[rng.randi_range(0, choices.size() - 1)]:
		_Fault.LATERAL:
			lateral = _straddle(rng, room)
		_Fault.YAW:
			yaw = _crooked(rng, yaw_ceiling)
		_:
			longitudinal = _sticking_out(rng)

	# The second fault is always sticking out. It is the one that costs no room
	# beside the bay, so it can be added to anything; a car that drifted sideways
	# *and* slewed round would be standing in its neighbour's space.
	if longitudinal == 0.0 and rng.randf() < second_fault_chance:
		longitudinal = _sticking_out(rng)

	return _pose(lateral, longitudinal, yaw, rng.randf() < REVERSED_CHANCE)


## The smallest sideways offset that still counts as being out of the bay.
func _violation_floor() -> float:
	return legal_lateral + violation_margin


## How far out of the head of the bay a car is parked. Nothing is ever beside a
## bay in this direction, so this fault is always available.
func _sticking_out(rng: RandomNumberGenerator) -> float:
	return _beyond(rng, legal_longitudinal, violation_margin, violation_longitudinal_reach)


## The most a car may be turned in this bay before a corner swings further across
## than [param room] allows. A long car in a narrow bay runs out of angle fast,
## which is exactly why a crooked one blocks the space next to it.
##
## The inverse of [method _across], which is the same geometry read the other way
## round: what a given angle costs, rather than what a given gap allows.
func _yaw_ceiling(room: float, car_footprint: Vector2) -> float:
	if not is_finite(room):
		return MAX_VIOLATION_YAW
	var half_width := car_footprint.x * 0.5
	var half_length := car_footprint.y * 0.5
	var corner := sqrt(half_width * half_width + half_length * half_length)
	var allowed := half_width + room
	if allowed >= corner:
		return MAX_VIOLATION_YAW
	# Room enough gone that even parked square this car is in its neighbour. There
	# is no angle that helps; the caller wants no angle at all.
	if allowed <= 0.0:
		return 0.0
	# The car's half-width across the bay is corner * sin(yaw + atan2(w, l)), so
	# the largest yaw that still fits falls straight out of it.
	return rad_to_deg(asin(allowed / corner) - atan2(half_width, half_length))


## Half the width a car of [param car_footprint] takes across the bay when it
## sits [param yaw_degrees] out of square: its own half-width parked straight, and
## more than that the moment it is not, because the corner leads.
static func _across(car_footprint: Vector2, yaw_degrees: float) -> float:
	var half_width := car_footprint.x * 0.5
	var half_length := car_footprint.y * 0.5
	var corner := sqrt(half_width * half_width + half_length * half_length)
	return corner * sin(absf(deg_to_rad(yaw_degrees)) + atan2(half_width, half_length))


## A crookedness past the legal band, up to whatever [param ceiling] allows.
func _crooked(rng: RandomNumberGenerator, ceiling: float) -> float:
	var floor_value := legal_yaw_degrees + violation_yaw_margin
	var magnitude := rng.randf_range(floor_value,
			minf(floor_value + violation_yaw_reach, minf(ceiling, MAX_VIOLATION_YAW)))
	return magnitude if rng.randf() < 0.5 else -magnitude


## A sideways drift into whichever side of the bay has room for it, never further
## than that room allows. Callers only reach this once [method _violation_pose]
## has established that at least one side qualifies.
func _straddle(rng: RandomNumberGenerator, room: Vector2) -> float:
	var floor_value := _violation_floor()
	var sides: Array[float] = []
	if room.x > floor_value:
		sides.append(-1.0)
	if room.y > floor_value:
		sides.append(1.0)
	var side := sides[rng.randi_range(0, sides.size() - 1)]
	var available := room.x if side < 0.0 else room.y
	return side * rng.randf_range(floor_value,
			minf(floor_value + violation_lateral_reach, available))


## A magnitude pushed clear of [param legal] by at least [param margin], signed
## at random.
func _beyond(rng: RandomNumberGenerator, legal: float, margin: float, reach: float) -> float:
	var magnitude := legal + margin + rng.randf() * maxf(reach, 0.0)
	return magnitude if rng.randf() < 0.5 else -magnitude


func _pose(lateral: float, longitudinal: float, yaw_degrees: float, reversed: bool) -> Transform3D:
	var bay := bay_transform()
	var up := bay.basis.y
	var basis := bay.basis
	if reversed:
		basis = basis.rotated(up, PI)
	basis = basis.rotated(up, deg_to_rad(yaw_degrees))
	return Transform3D(basis, bay.origin + bay.basis.x * lateral + bay.basis.z * longitudinal)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	update_configuration_warnings()

	var wants_gizmo := Engine.is_editor_hint()
	if not paint_markings and not wants_gizmo:
		if _paint != null:
			_paint.queue_free()
			_paint = null
		return

	if _paint == null:
		_paint = MeshInstance3D.new()
		# No owner: a generated child written into the scene file would be
		# duplicated every time the level is saved.
		add_child(_paint)

	var mesh := ImmediateMesh.new()
	if paint_markings:
		_surface_markings(mesh)
	if wants_gizmo:
		_surface_gizmo(mesh)
	_paint.mesh = mesh


func _surface_markings(mesh: ImmediateMesh) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = MARKING_COLOUR
	# Two-sided: the paint is one flat surface, and getting its winding wrong
	# would make it invisible from exactly the side the player looks from.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var half_width := bay_width * 0.5
	var half_length := bay_length * 0.5
	_add_quad(mesh, Vector2(-half_width, 0.0), Vector2(marking_width, bay_length))
	_add_quad(mesh, Vector2(half_width, 0.0), Vector2(marking_width, bay_length))
	# The head of the bay only. Leaving the other end open reads as the way in.
	_add_quad(mesh, Vector2(0.0, -half_length), Vector2(bay_width, marking_width))
	mesh.surface_end()


func _surface_gizmo(mesh: ImmediateMesh) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	_add_outline(mesh, bay_width, bay_length, GIZMO_BAY_COLOUR)
	# The band a car's centre may sit in and still count as parked.
	_add_outline(mesh, legal_lateral * 2.0, legal_longitudinal * 2.0, GIZMO_LEGAL_COLOUR)
	var y := marking_height + GIZMO_LIFT
	var tip := Vector3(0.0, y, -bay_length * 0.4)
	_add_line(mesh, Vector3(0.0, y, bay_length * 0.2), tip, GIZMO_BAY_COLOUR)
	_add_line(mesh, tip, tip + Vector3(0.25, 0.0, 0.35), GIZMO_BAY_COLOUR)
	_add_line(mesh, tip, tip + Vector3(-0.25, 0.0, 0.35), GIZMO_BAY_COLOUR)
	mesh.surface_end()


## One flat rectangle on the road, given its centre and size in the bay's XZ plane.
func _add_quad(mesh: ImmediateMesh, centre: Vector2, size: Vector2) -> void:
	var half_x := size.x * 0.5
	var half_z := size.y * 0.5
	var a := Vector3(centre.x - half_x, marking_height, centre.y - half_z)
	var b := Vector3(centre.x + half_x, marking_height, centre.y - half_z)
	var c := Vector3(centre.x + half_x, marking_height, centre.y + half_z)
	var d := Vector3(centre.x - half_x, marking_height, centre.y + half_z)
	var corners: Array[Vector3] = [a, b, c, a, c, d]
	for corner in corners:
		mesh.surface_add_vertex(corner)


func _add_outline(mesh: ImmediateMesh, width: float, length: float, colour: Color) -> void:
	var half_x := width * 0.5
	var half_z := length * 0.5
	var y := marking_height + GIZMO_LIFT
	var a := Vector3(-half_x, y, -half_z)
	var b := Vector3(half_x, y, -half_z)
	var c := Vector3(half_x, y, half_z)
	var d := Vector3(-half_x, y, half_z)
	_add_line(mesh, a, b, colour)
	_add_line(mesh, b, c, colour)
	_add_line(mesh, c, d, colour)
	_add_line(mesh, d, a, colour)


func _add_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, colour: Color) -> void:
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(to)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if legal_lateral * 2.0 >= bay_width:
		warnings.append("legal_lateral spans the whole bay, so no car can be outside it.")
	if legal_longitudinal * 2.0 >= bay_length:
		warnings.append("legal_longitudinal spans the whole bay, so no car can be outside it.")
	if legal_yaw_degrees + violation_yaw_margin >= MAX_VIOLATION_YAW:
		warnings.append(("legal_yaw_degrees plus violation_yaw_margin reaches %d degrees, "
				% int(MAX_VIOLATION_YAW))
				+ "where a crooked car gets clamped back inside the legal band.")
	return warnings
