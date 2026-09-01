# Vehicle variety: adding a model to the street

Which car parks in which bay is rolled per run, out of `ParkingLot.vehicles`. Adding a
model to that list is all it takes to stop every area being a row of identical SUVs. This
is how the pieces fit together and what a new vehicle needs.

## Why a resource, and what goes in it

`ParkingLot.car_scenes` was already an array — the list is not the hard part. The hard part
was one number:

```gdscript
@export var car_footprint := Vector2(1.8, 4.5)   # gone
```

That single footprint was doing two different jobs: how much of the gap beside a bay the
*neighbouring* car eats, and how far *this* car may slew before its own corners swing into
that gap. With one model those are the same number. With a truck beside a hatchback they
are not, and the failure is silent — cars intersecting, or a violator that reads as legal
because it never got the angle it was promised.

So there are two kinds of per-vehicle parameter, and the split between them is the design:

- **What the lot must know *before* the car exists** — width, length, how high its origin
  sits. The lot works out the room beside a bay while the layout is still being decided,
  including for neighbours it has not instanced yet, so these have to be readable off a
  file. They live in a [`VehicleProfile`](../Scripts/Gameplay/VehicleProfile.gd) resource,
  one `.tres` per vehicle under [`Assets/Vehicles/`](../Assets/Vehicles).
- **What only matters *once* the car exists** — the cone catcher volume, the roof zone, the
  collision shape, where its HUD bracket hangs. These are authored in the vehicle's `.tscn`,
  next to the mesh they are shaped around.

The rule of thumb: if getting a number right means looking at the model in the editor, it
belongs in the scene. The profile is the vehicle's silhouette on the road; the scene is the
vehicle.

## What a profile holds

| Property | What it is |
|---|---|
| `scene` | The vehicle scene. Must instantiate a `TargetCar`. |
| `footprint` | Width across, length along, in metres. The number the room maths runs on. |
| `bay_height_offset` | Metres this vehicle's origin sits above the bay marker. Zero for the SUV, because the bays were authored at its resting height. |
| `spawn_weight` | Relative frequency. Halve it for something that should show up but not be the street's default. |

## Authored, then checked

`ParkingLot` has always generated a pose and then *measured* it rather than trusting the
label it was placed for. Footprints get the same treatment: `verify_footprints` measures the
instanced car's real mesh bounds and warns when the profile disagrees with them by more than
`FOOTPRINT_TOLERANCE` (0.25 m). Once per profile per run, not once per car.

The check matters because the room maths cannot measure the car it is making room for —
that car does not exist yet. A footprint that has drifted from its model is otherwise a
failure with no visible cause until you are looking straight at it.

## How a bay picks a car

Per occupied bay, in the section's own bay order:

1. **Filter.** `ParkingSpace.fits()` drops any vehicle wider than `bay_width` or longer than
   `bay_length`. A body that hangs out of its own paint reads as badly parked however
   carefully it is placed, which would make it a violator by mesh rather than by pose — and
   the player would have no way to read it.
2. **Vary.** With `avoid_adjacent_repeats` on, the vehicle parked in the previous bay is
   dropped from the draw — unless it is the only thing that fits, because a gap in the row
   is a worse outcome than a repeat.
3. **Weight.** What survives is drawn against `spawn_weight`, from the lot's own generator
   so a seeded run still replays exactly.

If nothing fits a bay, it stays empty and says so in the Output panel. An empty bay is a gap
in the row, which the design already tolerates.

## What the current bays will take

The row in `level.tscn` is tight. Bays are 2.4 m wide and 5.2 m long at a 2.26–2.66 m pitch,
so the painted bays already overlap slightly at the tight end.

- **Hard ceiling:** 2.4 m wide, 5.2 m long. Past either, `fits()` rejects the vehicle and
  the bay stays empty.
- **Practical ceiling:** about 2.0 m wide. Above that there is almost no room left beside
  the bay once the gap is shared with a neighbour, so the vehicle can still be parked but
  can only ever offend by sticking out — the one fault that costs no lateral room — and the
  correctly parked cars beside a wide violator start being crowded out of their bays
  altogether. Everything still works; the street just gets duller and gappier. See
  [parking-bays.md](parking-bays.md) for what happens to a car with nowhere to park.

If the models you are importing are vans or pickups, budget a pass on bay spacing rather
than fighting the room maths.

## Adding a vehicle

1. Import the mesh under `ThirdParty/Models/`.
2. Duplicate `Scenes/SUV.tscn`. Swap the mesh and the collision shape, then reshape
   `ConeCatcher` and `RoofZone` around the new body. There is no substitute for doing this
   against the actual model: those two volumes decide what counts as a landing, which is the
   one thing in this game that should never be derived from a guess.
3. Set `marker_height` and `marker_size` on the scene's `TargetCar`, so its HUD bracket
   hangs at mid-body rather than through the windscreen.
4. Run `Tools/derive_vehicle_profile.gd` from the editor (**File → Run** with the script
   open). It measures every `TargetCar` scene it finds and prints a ready-to-paste block —
   footprint, height offset, a suggested `marker_height`, and whether the vehicle fits the
   bays in the scene you have open.
5. Make an `Assets/Vehicles/<name>.tres` from that output.
6. Add the profile to `ParkingLot.vehicles` on the `ParkingLot` node in `Scenes/level.tscn`.

## Checking it

There is no test harness here, so the check is a seeded run: pin `ParkingLot.random_seed` to
anything non-zero, turn on `TargetMarkers.reveal_violators`, and walk the rail. The Output
panel should be clean — `verify_poses` and `verify_footprints` both report there — and what
you are looking for by eye is the two failures this exists to prevent: cars sharing a patch
of road, and a car whose bracket colour disagrees with how it looks parked.

## Deliberately not done

- **`cones_required` does not scale with vehicle size.** It stays per-section on
  `CameraStop`. Scaling it by what got rolled would make the same section harder or easier
  depending on a random draw.
- **The bay markers were not re-baselined to road level.** Giving every profile a true
  ground offset is tidier than measuring against the SUV, but it moves fourteen hand-placed
  nodes to fix what `bay_height_offset` solves with one number per vehicle.
- **Colour variation on a single mesh** is a separate and cheaper source of variety.
