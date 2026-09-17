extends SceneTree
## The grade table: every rule in [method RoundData.rank], and both sides of
## every boundary.
##
## Run it headless, from the project root:
## [codeblock]
## godot --headless --script Tools/test_grade_table.gd
## [/codeblock]
##
## It exists because the grade is the game's whole output and the source
## computes it twice, in two functions that disagree. A table is the only honest
## way to say what the one surviving implementation does -- and to notice when a
## tuning change moves a boundary nobody meant to move.
##
## Every expectation below is the source's behaviour unless the comment says
## otherwise.

## angle degrees, centre distance, over left, over right, collisions, expected letter, why
const CASES := [
	[0.0, 0.0, false, false, 0, "A", "square and centred"],
	[0.0, 0.5, false, false, 0, "A", "on the A distance boundary"],
	[0.0, 0.51, false, false, 0, "A", "just past it: rank 1 halves back to 0"],
	[0.0, 0.9, false, false, 0, "A", "on the B distance boundary"],
	[0.0, 0.91, false, false, 0, "B", "past it: rank 2 halves to 1"],
	[0.0, 1.5, false, false, 0, "B", "on the C distance boundary"],
	[0.0, 1.51, false, false, 0, "B", "past it: the worst distance rank halves to 1"],
	[0.0, 2.0, false, false, 0, "B", "the source's '> 2.5 F' comment is not implemented"],
	[0.0, 9.0, false, false, 0, "B", "distance alone never gets worse than this"],
	[0.9, 0.0, false, false, 0, "A", "under a degree off is square"],
	[1.0, 0.0, false, false, 0, "A", "one degree: rank 1 halves back to 0"],
	[2.0, 0.0, false, false, 0, "B", "two degrees"],
	[3.0, 0.0, false, false, 0, "B", "the angle rank caps here"],
	[45.0, 0.0, false, false, 0, "B", "and stays capped, however sideways"],
	[3.0, 2.0, false, false, 0, "D", "worst angle and worst distance"],
	[3.0, 2.0, true, false, 0, "F", "a line crossing costs a whole rank"],
	[0.0, 0.0, true, false, 0, "B", "square, centred, but on a line"],
	[0.0, 0.0, true, true, 0, "C", "straddling both lines"],
	[0.0, 0.0, false, false, 1, "B", "one collision costs a rank"],
	[0.0, 0.0, false, false, 4, "F", "four collisions"],
	[0.0, 0.0, false, false, 9, "F", "and it never gets worse than F"],
]


func _initialize() -> void:
	var failures := 0
	print("angle  dist   lines  hits  grade  expected")
	for case in CASES:
		var data := RoundData.new()
		data.parked_in_space = true
		data.parking_angle = case[0]
		data.centre_distance = case[1]
		data.over_left_line = case[2]
		data.over_right_line = case[3]
		for i in int(case[4]):
			data.collisions.append(Obstacle.Kind.VEHICLE)
		var got := data.grade_letter()
		var want: String = case[5]
		var mark := "ok" if got == want else "FAIL"
		if got != want:
			failures += 1
		print("%5.1f  %4.2f  %-5s  %4d  %s      %s  %-4s  %s" % [
			case[0], case[1],
			"%s%s" % ["L" if case[2] else "-", "R" if case[3] else "-"],
			case[4], got, want, mark, case[6]])

	# Parking outside a bay is a failure however tidy the car is.
	var missed := RoundData.new()
	missed.parked_in_space = false
	if missed.grade_letter() != "F":
		printerr("FAIL: a round that ended outside a bay graded ", missed.grade_letter())
		failures += 1

	# The pass mark decides the next level or a re-run of this one. The source
	# advances on GradeAsNumeric <= 2, so a C is the worst park that counts.
	var boundary := RoundData.new()
	boundary.parked_in_space = true
	boundary.over_left_line = true
	boundary.over_right_line = true
	if boundary.grade_letter() != "C" or not boundary.passed():
		printerr("FAIL: a C (%s) did not count as a pass" % boundary.grade_letter())
		failures += 1
	boundary.centre_distance = 2.0
	boundary.parking_angle = 3.0
	boundary.over_right_line = false
	if boundary.grade_letter() != "F" or boundary.passed():
		printerr("FAIL: an F (%s) counted as a pass" % boundary.grade_letter())
		failures += 1
	var dee := RoundData.new()
	dee.parked_in_space = true
	dee.centre_distance = 2.0
	dee.parking_angle = 3.0
	if dee.grade_letter() != "D" or dee.passed():
		printerr("FAIL: a D (%s) counted as a pass" % dee.grade_letter())
		failures += 1

	if failures == 0:
		print("\nPASS: %d cases" % CASES.size())
		quit(0)
		return
	printerr("\n%d case(s) failed" % failures)
	quit(1)
