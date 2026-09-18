@tool
class_name PedestrianCatalog
extends Resource
## The living things a lot can have crossing it, in two lists because the two
## behave differently rather than only looking different.
##
## The same idea as [VehicleCatalog]: adding a species is a resource and a
## scene, not code. [PedestrianSpawner] picks out of these lists and never names
## a scene itself, so swapping the placeholder capsule for a rigged model --
## which is the one thing this whole system is waiting on -- is an edit to this
## file and to nothing else.

## People on foot. One is spawned at a parked car and walks to the building.
@export var people: Array[PackedScene] = []
## Wildlife. A gaggle of these crosses the aisle together and has nowhere to be.
@export var wildlife: Array[PackedScene] = []


## One of [member people], or null if there are none.
func a_person(rng: RandomNumberGenerator) -> PackedScene:
	return _pick(people, rng)


## One of [member wildlife], or null if there is none.
func an_animal(rng: RandomNumberGenerator) -> PackedScene:
	return _pick(wildlife, rng)


## Whether this catalog can produce anything at all. An empty one is not an
## error: it is a lot with nobody in it.
func is_empty() -> bool:
	return _usable(people).is_empty() and _usable(wildlife).is_empty()


func _pick(from: Array[PackedScene], rng: RandomNumberGenerator) -> PackedScene:
	var usable := _usable(from)
	if usable.is_empty():
		return null
	if rng == null:
		return usable[0]
	return usable[rng.randi_range(0, usable.size() - 1)]


## The entries that are actually set. A half-authored list is skipped over
## rather than renumbering the rest of it.
func _usable(from: Array[PackedScene]) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for scene in from:
		if scene != null:
			out.append(scene)
	return out
