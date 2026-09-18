class_name Obstacle
extends RefCounted
## What the player's car can hit, and how a node says which kind it is.
##
## The source declares an [code]IObstacleType[/code] interface and has three
## classes implement it. GDScript has no interfaces, so the same job is split in
## two: a node joins [constant GROUP] to say it is worth reporting a collision
## with, and answers [code]obstacle_kind() -> Obstacle.Kind[/code] to say what it
## is. Both halves are required -- the group alone is what makes the check cheap,
## and the method alone is what makes the answer specific.
##
## Never instantiated. This is a namespace for the enum, the group name and the
## one lookup that reads them.

## Nodes the car should report hitting join this. A node in the group that
## cannot answer [method kind_of] is a mistake, and [method kind_of] says so
## rather than silently scoring the hit as a parked car.
const GROUP := &"obstacles"

## The method a node in [constant GROUP] must implement.
const KIND_METHOD := &"obstacle_kind"

## The method a node in [constant GROUP] may implement to be told it was hit,
## and by what. Optional, unlike [constant KIND_METHOD]: a parked car has
## nothing to do about being hit, and a [Pedestrian] falls over.
##
## [b]Called by the car that hit it[/b], in the frame the hit is scored, so
## nothing can be both knocked down and still worth a grade.
const STRUCK_METHOD := &"struck_by"

enum Kind {
	NONE, ## Not an obstacle. Scenery, the road, the lot's own static bodies.
	VEHICLE, ## A parked car.
	PERSON, ## Somebody on foot.
	WILDLIFE, ## A goose. Costs the same as a person, and the score card counts the two together.
	CURB,
	TRAFFIC_CONTROL, ## Bollards, signs, cones.
}


## What [param body] is, or [constant Kind.NONE] if it is not an obstacle at all.
##
## The source reads [code]body is IObstacleType[/code] and leaves the collision
## kind at its default when the cast fails, which quietly grades a hit on
## scenery as a hit on a car. [constant Kind.NONE] exists so that case is
## distinguishable, and the round can drop it.
static func kind_of(body: Node) -> Kind:
	if body == null or not body.is_in_group(GROUP):
		return Kind.NONE
	if not body.has_method(KIND_METHOD):
		push_error("Obstacle: %s is in the '%s' group but has no %s()." % [
			body.name, GROUP, KIND_METHOD])
		return Kind.NONE
	return body.call(KIND_METHOD)
