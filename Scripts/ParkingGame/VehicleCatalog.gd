@tool
class_name VehicleCatalog
extends Resource
## The cars the cabinet offers, in the order the carousel shows them.
##
## One resource so that the order is authored in one place: the round's default
## car is the first entry, and the select screen's plates are built from the
## same list in the same order. Adding a car is a [DrivableVehicle] appended
## here.

## Ordered. Unusable entries are skipped by [method usable] rather than removed,
## so a half-authored car in the inspector does not silently renumber the rest.
@export var vehicles: Array[DrivableVehicle] = []


## Every entry that can actually be spawned.
func usable() -> Array[DrivableVehicle]:
	var out: Array[DrivableVehicle] = []
	for vehicle in vehicles:
		if vehicle != null and vehicle.is_usable():
			out.append(vehicle)
	return out


## The car a round starts in when nothing was picked: the first usable entry.
func first() -> DrivableVehicle:
	var list := usable()
	if list.is_empty():
		push_error("VehicleCatalog: no usable vehicles in %s." % resource_path)
		return null
	return list[0]
