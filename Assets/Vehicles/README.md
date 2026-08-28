# Vehicle profiles

One `.tres` per vehicle the street can be filled with. Each is a
[`VehicleProfile`](../../Scripts/Gameplay/VehicleProfile.gd): the scene to spawn, plus the
handful of numbers `ParkingLot` needs *before* that scene exists — footprint, height
offset, spawn weight.

Add a profile to `ParkingLot.vehicles` in `Scenes/level.tscn` and it starts appearing on
the street. See [docs/vehicle-variety.md](../../docs/vehicle-variety.md) for the full
checklist, and run `Tools/derive_vehicle_profile.gd` from the editor to get a new
vehicle's numbers instead of guessing them.
