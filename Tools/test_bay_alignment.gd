extends SceneTree
## Checks the lot's bays against the lot's own paint.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless --script Tools/test_bay_alignment.gd
## [/codeblock]
##
## The bays are [Area3D]s floating over a model that knows where its lines are,
## and nothing but the eye connected the two: a bay placed a hand's width off is
## a bay that grades a car against a middle the player cannot see, and a line
## area a hand's width off the paint is a line the player is booked for crossing
## before they reach it. So this reads the stripes straight out of the parking
## lot mesh -- flat, thin, six-and-a-half metres long, lying on the tarmac --
## and asks of every bay: is your middle the middle of the paint, and are your
## two line volumes sitting on the two painted lines?
##
## A bay at the end of a row has paint on one side only; the lot simply stops on
## the other. Those edges are allowed to have nothing under them, but only where
## there is genuinely no stripe further out in that row.

## How far a bay or a line may sit from the paint it stands for.
const TOLERANCE := 0.05
## A stripe further than this from a line area is a different stripe, not the
## one that line is meant to be on.
const SAME_STRIPE := 0.8
## Volumes are shrunk by this before they are asked whether they overlap. The
## bay ends exactly where its lines begin, and two boxes that share a face
## overlap by every floating point measure and by no useful one.
const TOUCHING := 0.001

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(condition: bool, description: String) -> void:
	print("  %-4s %s" % ["ok" if condition else "FAIL", description])
	if not condition:
		_failures.append(description)


## Every painted bay divider in the lot model, as a world-space AABB. Found by
## shape rather than by name or material: the stripes are the only thing on the
## tarmac that is long, thin and flat.
func _stripes(lot: Node3D) -> Array[AABB]:
	var found: Array[AABB] = []
	for node in lot.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		var size := box.size
		if size.x < 5.0 or size.x > 8.0 or size.z > 0.5 or size.y > 0.2:
			continue
		if absf(box.get_center().y) > 0.5:
			continue
		found.append(box)
	return found


## The world-space box of an area's one collision shape.
func _volume(area: Area3D) -> AABB:
	var shape := area.get_node(^"CollisionShape3D") as CollisionShape3D
	var box := (shape.shape as BoxShape3D).size
	return AABB(shape.global_position - box * 0.5, box)


func _run() -> void:
	var lot := (load("res://Scenes/ParkingGame/Lot.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lot)
	# One frame, so the lot is in the tree and every node in it has a global
	# transform to be asked for.
	await process_frame
	var stripes := _stripes(lot)
	var stripe_z: Array[float] = []
	for stripe in stripes:
		stripe_z.append(stripe.get_center().z)
	print("%d painted bay dividers in the lot model" % stripes.size())

	var bays := lot.find_children("*", "Node3D", true, false)
	var spaces: Array[ScoredParkingSpace] = []
	for node in bays:
		var space := node as ScoredParkingSpace
		if space != null:
			spaces.append(space)
	print("%d bays\n" % spaces.size())

	var volumes: Array[AABB] = []
	for space in spaces:
		var centre := space.bay_centre()
		var volume := _volume(space.bay)
		volumes.append(volume)
		# The stripes of this row: the ones this bay's paint would run parallel
		# to, picked by the row's x rather than by index.
		var row: Array[float] = []
		for stripe in stripes:
			if absf(stripe.get_center().x - centre.x) < 1.0:
				row.append(stripe.get_center().z)
		row.sort()
		var problems: Array[String] = []
		if row.is_empty():
			problems.append("sits over no painted row at all")
		else:
			var below := -INF
			var above := INF
			for z in row:
				if z < centre.z:
					below = maxf(below, z)
				else:
					above = minf(above, z)
			if below > -INF and above < INF:
				var middle := (below + above) * 0.5
				if absf(centre.z - middle) > TOLERANCE:
					problems.append("middle is %.3f m off the middle of its two lines" % (centre.z - middle))
		for line in [space.left_line, space.right_line]:
			var line_z := _volume(line).get_center().z
			var nearest := INF
			for z in row:
				if absf(z - line_z) < absf(nearest - line_z):
					nearest = z
			if absf(nearest - line_z) <= SAME_STRIPE:
				if absf(nearest - line_z) > TOLERANCE:
					problems.append("%s is %.3f m off its stripe" % [line.name, line_z - nearest])
				continue
			# No stripe under it: allowed only at the end of a row, where the
			# paint runs out and the bay's edge is the lot's edge.
			var outward := signf(line_z - centre.z)
			for z in row:
				if signf(z - centre.z) == outward and absf(z - centre.z) > absf(line_z - centre.z):
					problems.append("%s is on no stripe, and is not the end of the row" % line.name)
					break
		for line in [space.left_line, space.right_line]:
			if volume.grow(-TOUCHING).intersects(_volume(line).grow(-TOUCHING)):
				problems.append("bay volume swallows %s, so the paint is inside the bay" % line.name)
		_check(problems.is_empty(), "%s: %s" % [
			space.name, "on the paint" if problems.is_empty() else ", ".join(problems)])

	print("")
	var overlaps := 0
	for i in volumes.size():
		for j in range(i + 1, volumes.size()):
			if volumes[i].grow(-TOUCHING).intersects(volumes[j].grow(-TOUCHING)):
				overlaps += 1
	_check(overlaps == 0, "no two bay volumes overlap, so a car is only ever in the bays it is really in")

	if _failures.is_empty():
		print("PASS")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: ", failure)
	quit(1)
