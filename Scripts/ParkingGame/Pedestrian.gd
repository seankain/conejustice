class_name Pedestrian
extends RigidBody3D
## A living thing crossing the lot on foot: it walks a navigation path to
## somewhere, it is worth a grade to hit, and it goes over when a car reaches
## it.
##
## Ported from the source's [code]MobileNpc.cs[/code], which drives a 100 KB
## rigged human with a [PhysicalBoneSimulator3D] behind it. [b]That mesh is not
## in this repo[/b] -- it is a Sketchfab Standard licence download rather than
## one of the Creative Commons grants the lot and the building carry, so it
## cannot be committed here until that is cleared. What is here instead is the
## behaviour with a primitive in place of the model: a capsule for a person, a
## box for a goose. Everything a real model needs is already decided around it
## -- where it walks from, where it walks to, what hitting it costs, and what it
## does when hit -- so landing the real one is a mesh swap and an
## [AnimationTree], not a redesign.
##
## [b]It is one rigid body, not a ragdoll.[/b] Walking, it is held upright by
## locking its two horizontal angular axes and its velocity is written every
## physics frame; struck, those locks come off and it is left to the solver with
## an impulse in it. A single capsule going over end for end is the placeholder
## for a skeleton going limp, and it is deliberately the same [i]switch[/i]: the
## real version replaces what [method knock_down] turns on, not when it is
## called.
##
## [b]It is dynamic the whole time[/b] rather than frozen kinematic the way
## [NpcDriver]'s cars are. A frozen body has infinite mass, so a car hitting one
## stops dead against it for the frame before anything can react -- which is
## exactly wrong here: seventy kilos should barely slow a car and should leave
## the lot at speed. A car is the thing with right of way in the physics even
## when it is in the wrong in the scoring.

## Every pedestrian joins this, so a round can clear the lot of them whatever
## state they are in. Declared in [code]project.godot[/code].
const GROUP := &"npc_living"

## What a pedestrian is. The two differ in where they are going and how they get
## there, not only in what they look like -- a person walks from a car to the
## building, a goose crosses the aisle with its friends.
enum Species {
	PERSON, ## Somebody who parked and is walking in.
	WILDLIFE, ## A goose. It has nowhere to be and is in the way regardless.
}

enum State {
	WALKING, ## Under its own power, following a path.
	DOWN, ## Hit. The solver has it now.
}

## Got where it was going, or gave up trying. Either way it is done and the
## spawner frees it. [b]Not[/b] emitted when it is hit: a body on the tarmac is
## evidence, and stays until the round ends.
signal finished(pedestrian: Pedestrian)
## A car reached it. The round is told what it hit by the car, not by this --
## see [method PlayerCar._on_body_entered] -- so this is for anything that wants
## to watch rather than to score.
signal struck(pedestrian: Pedestrian)

## Metres per second the body is thrown at when a car reaches it, on top of half
## of whatever the car was doing. A pedestrian a stationary car nudges still
## goes over, which is the read the player needs: the grade was lost either way.
const KNOCKDOWN_SPEED := 4.0
## ...and upward, which is what makes it a tumble rather than a shove. Enough to
## clear a bonnet: a body that only slides goes under the car instead of over
## it, which reads as the car having driven through a crate.
const KNOCKDOWN_LIFT := 3.5
## Where above the body's middle the impulse lands. Off-centre is the whole
## reason it topples.
const KNOCKDOWN_HEIGHT := 0.7

## How much nearer its destination a pedestrian has to get to count as making
## progress, and how long it may fail to before it gives up and is taken away.
##
## [b]The navigation mesh does not know where the parked cars are.[/b] It is
## baked into [code]Lot.tscn[/code] from the empty lot, so a path can run
## straight through a bay that a car is sitting in, and the pedestrian walks
## into the car and stays there. Rather than leave one leaning on a bumper for
## the rest of the round, a walker that is getting nowhere leaves. The real fix
## is a [NavigationObstacle3D] on every parked car, which is a change to
## [TrafficSpawner] and wants the real navigation agents to test it against.
const PROGRESS_STEP := 0.25
const STUCK_SECONDS := 5.0

@export_group("Walking")
## What this is, which decides what hitting it is worth and where the spawner
## sends it.
@export var species: Species = Species.PERSON
## Metres per second on foot. A person walks at 1.4; a goose is in no hurry.
@export var walk_speed: float = 1.4
## Radians per second it will turn to face where it is going.
@export var turn_speed: float = 6.0

@export_group("Nodes")
## The path finder. Its own node so the real model can keep it exactly as it is.
@export var agent: NavigationAgent3D

var state: State = State.WALKING

## Where it is walking to, in world space. Infinite until it is given somewhere
## to be.
var _destination := Vector3.INF
## Set once the navigation map has had a frame to build itself. An agent asked
## for a path before that gets a straight line to the target and walks through
## whatever is in the way.
var _paths_ready: bool = false
## The velocity [method _integrate_forces] is to write, computed from the path.
var _desired := Vector3.ZERO
var _yaw_rate: float = 0.0
## The closest it has been to its destination, and how long since that improved.
var _closest: float = INF
var _stuck_for: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(Obstacle.GROUP)
	# Upright, and free to turn on the spot. The two locks that are on are what
	# stand in for a skeleton holding itself up; [method knock_down] takes them
	# off and that is the whole of the ragdoll.
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	axis_lock_angular_y = false
	# A body whose velocity is written every frame must not be allowed to fall
	# asleep. One that has been knocked over should, and [method knock_down]
	# hands it back.
	can_sleep = false
	set_physics_process(false)
	if agent == null:
		push_error("Pedestrian %s: no NavigationAgent3D set." % name)
		return
	# The navigation map is built by the server on the first physics frame of
	# the lot's existence. Asking before then answers with the straight line.
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_paths_ready = true
	_start_walking()


## Sends it to [param target]. Called before or after it enters the tree; a
## destination handed over early is taken up as soon as the navigation map is
## ready for it.
func walk_to(target: Vector3) -> void:
	if not target.is_finite():
		return
	_destination = target
	_closest = INF
	_stuck_for = 0.0
	if _paths_ready:
		_start_walking()


## What this is to a car that hits it. Both kinds cost the same rank; the score
## card counts them together as living things and [RoundData] does not care
## which.
func obstacle_kind() -> Obstacle.Kind:
	return Obstacle.Kind.PERSON if species == Species.PERSON else Obstacle.Kind.WILDLIFE


## A car reached it. Called by the car itself -- see [constant
## Obstacle.STRUCK_METHOD] -- in the same frame the car scores the hit, so a
## pedestrian is never both down and still worth points.
##
## [param by] is whatever hit it, which is not always the player: a car an
## [NpcDriver] is taking out of a bay knocks a goose over just as well, and
## costs the player nothing because nothing is listening to that car's
## [signal PlayerCar.hit_obstacle].
func struck_by(by: Node) -> void:
	knock_down(_push_from(by))


## Goes over, and stays over. [param impulse] is the shove, applied above the
## middle so the body turns as it goes.
func knock_down(impulse: Vector3) -> void:
	if state == State.DOWN:
		return
	state = State.DOWN
	# Out of the obstacle group the moment it is down: a car that carries a body
	# along on its bumper would otherwise score it again every time the two part
	# and touch. It stays in [constant GROUP], because the round still has to
	# clear it away.
	remove_from_group(Obstacle.GROUP)
	set_physics_process(false)
	_desired = Vector3.ZERO
	_yaw_rate = 0.0
	# The locks are the skeleton. Off, it is a loose body with an impulse in it.
	axis_lock_angular_x = false
	axis_lock_angular_z = false
	# Nothing writes its velocity any more, so let it come to rest and stop
	# costing the solver anything.
	can_sleep = true
	apply_impulse(impulse, Vector3.UP * KNOCKDOWN_HEIGHT)
	struck.emit(self)


## Stops it where it stands, for good: the round is over and the lot holds still
## while the score card is up.
func hold() -> void:
	_desired = Vector3.ZERO
	_yaw_rate = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if state != State.WALKING or agent == null:
		return
	if agent.is_navigation_finished():
		_leave()
		return
	var next := agent.get_next_path_position()
	var direction := _flat(next - global_position)
	# A zero-length or straight-up direction is the one thing that makes the
	# facing maths error out. It means the path's next point is underfoot, which
	# the agent will have moved on from by the next frame.
	if direction == Vector3.ZERO:
		_desired = Vector3.ZERO
		_yaw_rate = 0.0
		return
	_desired = direction * walk_speed
	var facing := _flat(-global_basis.z)
	if facing == Vector3.ZERO:
		_yaw_rate = 0.0
	else:
		_yaw_rate = clampf(
				facing.signed_angle_to(direction, Vector3.UP) / maxf(delta, 0.0001),
				-turn_speed, turn_speed)
	_watch_progress(delta)


## Velocity is written here rather than in [method _physics_process] because
## that is where a rigid body's velocity belongs: the solver is handed the
## number it is about to integrate, instead of having one poked into it between
## steps.
##
## The vertical component is left alone, so a pedestrian is still subject to
## gravity and still falls the last few centimetres onto the tarmac it was
## spawned above.
func _integrate_forces(physics_state: PhysicsDirectBodyState3D) -> void:
	if state != State.WALKING:
		return
	physics_state.linear_velocity = Vector3(
			_desired.x, physics_state.linear_velocity.y, _desired.z)
	physics_state.angular_velocity = Vector3(0.0, _yaw_rate, 0.0)


## Hands the destination to the agent, once there is both a destination and a
## navigation map to look it up in.
func _start_walking() -> void:
	if agent == null or not _destination.is_finite() or state != State.WALKING:
		return
	agent.target_position = _destination
	set_physics_process(true)


## Gives up on a destination it is not getting closer to. See
## [constant STUCK_SECONDS].
##
## A target the agent cannot reach at all counts as no progress rather than an
## immediate departure: it answers "no" for the frame or two before its first
## path comes back, and a walker that left on that would never take a step.
func _watch_progress(delta: float) -> void:
	var remaining := _flat_distance(global_position, _destination)
	if remaining < _closest - PROGRESS_STEP and agent.is_target_reachable():
		_closest = remaining
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for >= STUCK_SECONDS:
		_leave()


## Done walking, one way or the other. The spawner frees it.
func _leave() -> void:
	if state != State.WALKING:
		return
	_desired = Vector3.ZERO
	_yaw_rate = 0.0
	set_physics_process(false)
	finished.emit(self)


## Which way, and how hard, [param by] sends it. Away from whatever hit it, with
## half of that thing's speed added on -- and upward, because a body that only
## slides looks like a crate.
##
## [b]Asked of the geometry, not of the velocity.[/b] A car an [NpcDriver] is
## driving is frozen and moved by its transform, so its
## [member RigidBody3D.linear_velocity] is zero however fast it is crossing the
## lot; only the player's car reports a real one.
func _push_from(by: Node) -> Vector3:
	var away := Vector3.ZERO
	var source := by as Node3D
	if source != null:
		away = _flat(global_position - source.global_position)
		if away == Vector3.ZERO:
			away = _flat(-source.global_basis.z)
	if away == Vector3.ZERO:
		away = Vector3.FORWARD
	var carried := 0.0
	if source != null and source.has_method(&"ground_speed"):
		carried = absf(source.call(&"ground_speed")) * 0.5
	return (away * (KNOCKDOWN_SPEED + carried) + Vector3.UP * KNOCKDOWN_LIFT) * mass


## Metres between two points, ignoring height: the lot is flat where anything
## walks, and a destination on the navigation mesh sits above the tarmac it
## stands for.
static func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


## [param vector] flattened onto the ground plane, as a unit vector.
static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z).normalized()
