class_name PlayerCar
extends VehicleBody3D
## The car the player drives: steering, drive, brakes, respawn, and reporting
## what it just hit.
##
## Ported from the source's [code]Player.cs[/code], which drives a box. This one
## drives the SUV and minivan meshes Cone Justice already ships, so the numbers
## below are tuned against a real body rather than carried across: the source's
## [code]ENGINE_POWER = 300[/code] against a 500 kg cube says nothing about a
## 1400 kg car.
##
## Three things the source does that are not ported:
##
## - [b]It has no brakes.[/b] Reverse and braking are the same key there, so a
##   car at speed pressing back gets reverse torque rather than stopping. Here
##   input that opposes the way the car is moving brakes instead.
## - [b]It respawns through a flag checked in [code]_integrate_forces[/code].[/b]
##   Once respawn is a method, the flag is dead weight.
## - [b]Its kill plane invokes the car's own event.[/b] C# allows that inside one
##   assembly; GDScript does not let one object emit another's signal. Callers
##   call [method respawn] and the car emits.
##
## Two buttons the source has no equivalent of at all: [b]boost[/b], the
## throttle held at full whatever the drive keys are saying, and the
## [b]handbrake[/b], which locks every wheel harder than anything else on the
## car.
## Neither is a resource the player spends -- see [method _drive].
##
## The visual half of the car lives under [member visuals] and is driven from
## the physics wheels each frame, never the other way round. That subtree is
## self-contained on purpose: vehicle select (T10) instances it on a turntable
## without the body, because a [VehicleBody3D] under a rotating parent is owned
## by the physics engine and fights it.

## The car the player drives joins this. The lot's areas ask for it by group
## rather than by type, and the type is not enough on its own: a parked car is
## this same scene, so a bay that asked "is this a PlayerCar?" would measure the
## traffic and end the round the moment a parked car settled into its bay.
const GROUP := &"player_car"

## Where [method respawn] puts the car. One marker per lot.
const RESPAWN_GROUP := &"respawn"

## Wheels are paired to their visuals by name: a [VehicleWheel3D] child called
## WheelFrontLeft drives the [Node3D] at Visuals/WheelFrontLeft.
const VISUAL_WHEEL_MISSING := "PlayerCar: wheel '%s' has no visual under %s."

## [b]Godot's [VehicleBody3D] drives towards +Z, not -Z.[/b] Its wheels take
## their axle from local -X, so the forward they push along is
## [code]up.cross(axle)[/code] = +Z -- the opposite of the -Z that [method
## Node3D.look_at], [ParkingSpace] and every car scene in this repo call
## forward. Rather than build this one car backwards, the sign is applied where
## input meets the engine, here. Measured, not assumed: a chassis with +2600 of
## engine force travels +Z.
##
## [b]Steering takes no sign of its own[/b], which is the one thing about this
## that reads wrong and is right. The engine's steering angle turns the car
## around its [i]steered[/i] wheels, and this chassis puts those at its -Z nose
## while the engine pushes it along +Z -- two reversals, which cancel. A car
## driving the way the player calls forward and holding a positive steering
## angle turns the way the player calls left, so
## [code]Input.get_axis(&"steer_right", &"steer_left")[/code], which is already
## positive for left, goes to [member VehicleBody3D.steering] as it is.
## [code]Tools/test_drive_chassis.gd[/code] measures which way the car actually
## goes, because reasoning about it is how it was got backwards in the first
## place.
const DRIVE_SIGN := -1.0

## The car was put back at the respawn marker, by the player or by a kill plane.
signal respawned
## The car hit something worth scoring. [param kind] is never
## [constant Obstacle.Kind.NONE] -- scenery is dropped here rather than at the
## round.
signal hit_obstacle(kind: Obstacle.Kind)

@export_group("Driving")
## Newtons at full throttle, [b]per driven wheel[/b] -- Godot applies
## [member VehicleBody3D.engine_force] at every wheel marked
## [member VehicleWheel3D.use_as_traction], so four-wheel drive multiplies this
## by four. Tuned for the ~1400 kg SUV body.
@export var engine_power: float = 2200.0
## Forward speed in m/s where the engine stops pulling. Godot's vehicle has no
## drag worth the name, so without a curve the car accelerates in a straight
## line until the lot runs out. This is a parking lot, not a motorway.
@export var top_speed: float = 16.0
## The same limit in reverse, where nobody needs to be quick.
@export var top_reverse_speed: float = 6.0
## Steering lock in radians. The source's 0.9 rad is 51 degrees, which is a
## forklift; 0.55 is about 31 and still turns inside a parking aisle.
@export var max_steer: float = 0.55
## How fast the wheels reach full lock, in radians per second.
@export var steering_speed: float = 2.4
## Brake force applied when the drive input opposes the way the car is moving.
@export var brake_strength: float = 40.0
## Brake force the handbrake applies, at every wheel at once. Stronger than
## [member brake_strength] on purpose: that one is the car braking itself
## because the player asked for the other direction, and this one is the player
## standing on the pedal. Measured on the SUV with
## [code]Tools/test_drive_chassis.gd[/code]: 11 m/s to a stop in 0.78 s over
## 4.3 m, against 1.70 s for the drive key. Twice the brake and not four times
## it -- 120 stops the same car in 0.53 s, which reads less like braking than
## like the car hitting something.
@export var handbrake_strength: float = 80.0
## Brake force applied with no input at all, so a car left alone rolls to a stop
## instead of coasting across the lot. The round ends on the car settling, so
## coasting forever would mean a round that never ends.
@export var idle_brake: float = 3.0
## Below this speed in m/s the car counts as stopped, and drive input in either
## direction is a pull-away rather than a brake.
@export var creep_speed: float = 0.4

## Whether this is the car the player is driving. Off for the cars the traffic
## spawner parks, which are this same scene with nobody in them: they keep the
## physics and the mesh, and stay out of [constant GROUP], so nothing in the lot
## mistakes one for the player.
@export var driven_by_player: bool = true

@export_group("Nodes")
## The whole visual car. Instanced on its own by the select screen.
@export var visuals: Node3D

## Input is off while the round is over, while the game is paused, and for every
## parked car in the lot -- they are this same scene with the input switched off
## rather than a second chassis with its own copy of these numbers.
var input_enabled: bool = true:
	set(value):
		input_enabled = value
		if not value:
			steering = 0.0
			engine_force = 0.0

var _wheels: Array[VehicleWheel3D] = []
var _wheel_visuals: Array[Node3D] = []
## How far each wheel has rolled, in radians. Only a car nobody is simulating
## keeps this -- see [method roll_wheel_visuals].
var _wheel_spin := PackedFloat32Array()


func _ready() -> void:
	if driven_by_player:
		add_to_group(GROUP)
	# body_entered needs both of these; without them the car silently never
	# reports a collision.
	contact_monitor = true
	if max_contacts_reported < 1:
		max_contacts_reported = 8
	body_entered.connect(_on_body_entered)
	_bind_wheel_visuals()


## Pairs each physics wheel with the visual node of the same name. Done once, by
## name, so adding a wheel to a chassis scene is a scene edit and not a script
## edit.
func _bind_wheel_visuals() -> void:
	_wheels.clear()
	_wheel_visuals.clear()
	if visuals == null:
		return
	for child in get_children():
		if child is not VehicleWheel3D:
			continue
		var visual := visuals.get_node_or_null(NodePath(child.name)) as Node3D
		if visual == null:
			push_error(VISUAL_WHEEL_MISSING % [child.name, visuals.name])
			continue
		_wheels.append(child)
		_wheel_visuals.append(visual)
	_wheel_spin.resize(_wheels.size())
	_wheel_spin.fill(0.0)


func _physics_process(delta: float) -> void:
	_drive(delta)


func _process(_delta: float) -> void:
	# Visual work, and the wheel transforms it reads are written by the physics
	# step -- so reading them here rather than in _physics_process is a frame
	# fresher, not a frame behind.
	_follow_wheels()


## Steering eases toward the input; drive is immediate. Pushing against the way
## the car is already moving brakes rather than reverses, which is the one place
## this deliberately does not behave like the source.
##
## [b]The handbrake outranks everything the throttle is doing[/b], boost
## included. It is read after the steering is set, so the wheels still turn
## while it is held: the car can be dragged round on a locked set of wheels
## rather than being frozen where it stands.
##
## [b]Boost is the gas pedal on the floor, and nothing else.[/b] No extra power,
## no charge to spend, no fade of its own -- it writes full forward throttle
## into the same axis the drive keys write, and everything downstream treats it
## as the throttle it is: the brake-rather-than-reverse rule still brakes a car
## that is rolling backwards, [method _power_fade] still tapers it out at
## [member top_speed], and [EngineAudio] still hears it as load. On a keyboard,
## where that axis is already 0 or 1, holding boost is the same as holding
## forward, and that is the whole of it. What it is for is the throttle that is
## not a key -- an analog trigger, a stick, a touch button -- where the axis
## sits somewhere below 1.0 and "all the way down" is otherwise something the
## player cannot ask for.
func _drive(delta: float) -> void:
	if not input_enabled:
		brake = idle_brake
		return

	var steer_input := Input.get_axis(&"steer_right", &"steer_left")
	steering = move_toward(steering, steer_input * max_steer, delta * steering_speed)

	if Input.is_action_pressed(&"handbrake"):
		engine_force = 0.0
		brake = handbrake_strength
		return

	var drive_input := Input.get_axis(&"drive_back", &"drive_forward")
	if Input.is_action_pressed(&"boost"):
		drive_input = 1.0
	var forward_speed := speed()

	if is_zero_approx(drive_input):
		engine_force = 0.0
		brake = idle_brake
		return

	var rolling := absf(forward_speed) > creep_speed
	if rolling and signf(drive_input) != signf(forward_speed):
		engine_force = 0.0
		brake = brake_strength
		return

	engine_force = drive_input * engine_power * DRIVE_SIGN * _power_fade(forward_speed, drive_input)
	brake = 0.0


## Fraction of full engine force left at this speed: full until the car is
## moving, tapering to nothing at the limit for the direction it is travelling.
## A curve rather than a hard cap so the car eases up to its top speed instead
## of hitting a wall.
func _power_fade(forward_speed: float, drive_input: float) -> float:
	var limit := top_speed if drive_input > 0.0 else top_reverse_speed
	var travelling := absf(forward_speed)
	return clampf(1.0 - travelling / limit, 0.0, 1.0)


## How fast the car is going along its own nose, in m/s. Negative is reversing.
func speed() -> float:
	return linear_velocity.dot(-global_basis.z)


## How fast the car is travelling across the ground, in m/s, ignoring whatever
## its suspension is doing vertically.
##
## This is the number to ask "has it stopped?" with. A car standing still on
## this chassis still reports a second or two of vertical velocity while the
## springs settle -- measured at up to 1.9 m/s -- against a planar speed of
## 0.004. The source asks for [code]LinearVelocity.Length() < 0.02[/code], which
## that bounce fails for seconds after the player has plainly parked.
func ground_speed() -> float:
	return Vector2(linear_velocity.x, linear_velocity.z).length()


## The visuals follow the physics wheels, so steering angle, suspension travel
## and wheel spin all come from the simulation rather than being animated to
## look like it. Each visual is a bare pivot; the mesh under it keeps its own
## scale and its mirrored basis, which is why this assigns the whole transform
## and the mesh still looks right on the left-hand side.
func _follow_wheels() -> void:
	for i in _wheels.size():
		_wheel_visuals[i].transform = _wheels[i].transform


## Rolls and steers the wheel visuals of a car that is not being simulated.
##
## [method _follow_wheels] reads the wheels the physics engine moves. A frozen
## car has none: its [VehicleWheel3D]s stay where they stopped, so a car an
## [NpcDriver] slides across the lot arrives with its wheels pointing straight
## ahead and never turning, which reads as a car on ice. This puts the same
## transform together from the outside -- [param distance] is how far the car
## travelled this frame, negative when it is reversing, and [param steer_angle]
## is where the front wheels are pointing, in radians.
##
## The wheel pivots are bare, and the meshes under them keep their own scale and
## their mirrored basis, which is why the whole transform can be rebuilt here and
## the left-hand wheels still look right.
func roll_wheel_visuals(distance: float, steer_angle: float) -> void:
	for i in _wheels.size():
		var wheel := _wheels[i]
		var spin := wrapf(
				_wheel_spin[i] + distance / maxf(wheel.wheel_radius, 0.05), -TAU, TAU)
		_wheel_spin[i] = spin
		var yaw := steer_angle if wheel.use_as_steering else 0.0
		# Rolling forward is -Z, and the axle is X, so a wheel going the way the
		# car calls forward turns the negative way about it.
		_wheel_visuals[i].transform = Transform3D(
				Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -spin), wheel.position)


func _unhandled_input(event: InputEvent) -> void:
	# Both halves matter. The round switches input off while it grades; and a
	# parked car or one an [NpcDriver] is driving is this same scene, so without
	# the second test the player's restart key would teleport the whole lot onto
	# the respawn marker.
	if not input_enabled or not driven_by_player:
		return
	if event.is_action_pressed(&"restart"):
		respawn()
		get_viewport().set_input_as_handled()


## Puts the car back on the respawn marker, stopped. Called by the player, and
## by anything that decides the car should not be where it is -- the kill plane
## under the lot, for one.
func respawn() -> void:
	var markers := get_tree().get_nodes_in_group(RESPAWN_GROUP)
	if markers.is_empty():
		push_error("PlayerCar: no node in the '%s' group to respawn to." % RESPAWN_GROUP)
		return
	var marker := markers[0] as Node3D
	global_transform = marker.global_transform
	# The car did not travel here, so nothing should be drawn of the journey: a
	# body that is interpolated between where it was and where it was put is
	# drawn smeared across the lot for a frame, and the chase camera, which
	# follows what is drawn, goes with it.
	reset_physics_interpolation()
	# Zeroed after the move, not before: a body teleported with velocity still on
	# it arrives at the marker sliding, which reads as the respawn having failed.
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steering = 0.0
	engine_force = 0.0
	respawned.emit()


## What this car is to another car that hits it. Every car is a vehicle,
## whoever is driving it; whether a hit is reported at all is decided by
## membership of [constant Obstacle.GROUP], which the traffic spawner grants to
## parked cars and nothing grants to the player's.
func obstacle_kind() -> Obstacle.Kind:
	return Obstacle.Kind.VEHICLE


func _on_body_entered(body: Node) -> void:
	var kind := Obstacle.kind_of(body)
	if kind == Obstacle.Kind.NONE:
		return
	hit_obstacle.emit(kind)
	# ...and tell it, if it is the kind of thing that has something to do about
	# being hit. A [Pedestrian] falls over here, in the same frame the hit is
	# scored, so nothing is ever both down and still worth a grade. Every car in
	# the lot runs this, the player's and the ones an [NpcDriver] is driving --
	# a goose knocked over by a car with nobody in it costs the player nothing,
	# because nothing is listening to that car.
	if body.has_method(Obstacle.STRUCK_METHOD):
		body.call(Obstacle.STRUCK_METHOD, self)
