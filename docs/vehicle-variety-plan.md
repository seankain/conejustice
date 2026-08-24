# Vehicle variety: a plan for randomising the parked cars

Today every bay on the street gets the same SUV. `ParkingLot.car_scenes` is already an
array, so dropping a second scene into it *almost* works — but one number downstream is
wrong the moment the cars stop being identical:

```gdscript
@export var car_footprint := Vector2(1.8, 4.5)
```

That single footprint is used for two different things — how much room a car's *neighbour*
eats out of the gap beside a bay, and how far *this* car may slew before its corners swing
into that gap. With one model those are the same number. With a truck next to a hatchback
they are not, and the failure mode is quiet: cars intersecting, or a violator that reads as
legal because it never got the angle it was promised.

So the work is not "add a list" — the list exists. The work is teaching the placement path
which car it is placing.

## The dividing line

There are two kinds of per-vehicle parameter, and the split between them is the whole
design:

- **What the lot must know *before* the car exists** — width, length, how high its origin
  sits, whether it fits a bay at all. The lot needs these to work out the room beside a bay
  and to reject a vehicle too big for it, and it needs them for *neighbouring* bays that
  have not been instanced yet. These go in a resource file.
- **What only matters *once* the car exists** — the cone catcher volume, the roof zone, the
  collision shape, where its HUD bracket hangs. These are already authored in the vehicle's
  `.tscn`, next to the mesh they are shaped around, and they should stay there.

Put another way: the resource is the vehicle's *silhouette on the road*; the scene is the
vehicle. Anything you can only get right by looking at the mesh in the editor belongs in
the scene.

This is the split that answers "do I need resource files?" — yes, but a small one, and only
for the handful of numbers the lot needs in advance.

## The measurement rule still applies

`ParkingLot` already generates a pose and then *measures* it rather than trusting the label
(see [parking-bays.md](parking-bays.md)). Footprints get the same treatment: the profile is
authored, and the lot checks it against the instanced car's actual visual AABB behind a
`verify_footprints` flag, the way `verify_poses` works now. An authored number that has
drifted from the mesh it describes then says so in the Output panel instead of producing a
street where cars overlap for reasons nobody can see.

## Phases

### 1. `VehicleProfile`

New `Scripts/Gameplay/VehicleProfile.gd`, a `Resource` with a `class_name` so it can be
made from the editor's *New Resource* dialog:

| Property | What it is |
|---|---|
| `scene: PackedScene` | The vehicle scene. Must instantiate a `TargetCar`. |
| `footprint: Vector2` | Width across, length along. The number the room maths runs on. |
| `bay_height_offset: float` | Metres this vehicle's origin sits above the bay marker. Zero for the SUV, because the bays were authored at the SUV's resting height. |
| `spawn_weight: float` | Relative frequency. 1.0 default; drop a rare vehicle to 0.2. |
| `max_lean: float` (optional) | Reserved for later; leave out of the first cut. |

One `.tres` per vehicle in a new `Assets/Vehicles/` directory — `SUV.tres` first, so the
existing behaviour is expressed in the new form before anything changes.

### 2. The pool replaces `car_scenes`

`ParkingLot.car_scenes: Array[PackedScene]` and `car_footprint: Vector2` both go, replaced
by `vehicles: Array[VehicleProfile]`. `Scenes/level.tscn` is updated in the same commit —
there is exactly one caller, so a clean break beats a deprecation shim, and leaving both
fields around invites a street configured half in each.

`_pick_scene()` becomes a weighted `_pick_profile(space, exclude)` drawing from the lot's
own `_rng`, never `Array.pick_random()`, so a seeded run still replays exactly.

### 3. Push the real footprint through the placement path

Three call sites change:

- `_lateral_room()` currently subtracts `car_footprint.x` for whatever is parked next door.
  It should subtract the *neighbour's* width: read it from the neighbour's profile when the
  bay has been rolled, and fall back to the widest footprint in the pool for a bay that has
  not been rolled yet. The existing code already treats an un-rolled bay as occupied for
  exactly this reason — assuming the widest is the same conservatism carried one step
  further.
- `_park()` passes the chosen profile's footprint to `space.pose()` instead of the lot-wide
  one.
- `ParkingSpace.pose()` and `_yaw_ceiling()` drop their `Vector2(1.8, 4.5)` default
  argument. A magic default that silently disagrees with the pool is the bug this whole
  change is meant to remove; make the caller say what it is placing.

To do this the lot needs to know which vehicle goes in which bay *before* it places any of
them. That is a small restructure of `populate()`: it already decides every bay's role
before placing a single car (so a straddle knows whether the bay beside it is about to be
filled). Assigning profiles in the same pass — role first, then vehicle, then poses — keeps
that guarantee and extends it to size.

### 4. Bays that a vehicle does not fit

Adding a `ParkingSpace.fits(footprint) -> bool` gives the pool a filter: a vehicle whose
width leaves no room to be legally parked in a bay is simply not a candidate there.

Worth knowing before you import anything wide: **the current row is tight.** The bays in
`level.tscn` sit at a 2.26–2.66 m pitch with `bay_width` at 2.4 m, so the painted bays
already overlap slightly at the tight end, and the 1.8 m SUV leaves roughly 0.23 m of gap.
A 2.0 m vehicle leaves about 0.13 m each side once halved for a neighbour that may be
drifting too — enough to place, not enough to slew. Anything wider than about 2.0 m will
either need the row re-spaced or will only ever offend by sticking out of its bay, which is
the one fault that costs no lateral room. Fitting still *works* at that size; it just gets
duller. If the imported meshes are vans or pickups, budget a pass on bay spacing.

If the filter empties a bay's candidate list, place nothing and warn — an empty bay is a
gap in the row, which the design already tolerates.

### 5. Variety rules

Two knobs on the lot, both cheap:

- `avoid_adjacent_repeats: bool` — when picking for a bay, drop the profile used by the bay
  immediately before it from the candidate list, unless that would leave nothing. A row of
  alternating models reads as a street; a run of four identical SUVs reads as a spawner.
- Weighted selection from `spawn_weight`, so a distinctive vehicle can be made rare without
  removing it.

### 6. Scene-side per-vehicle tuning

- `TargetCar` gains `@export var marker_height: float = 1.1`, and `TargetMarkers` reads it
  per car instead of using its own single value. A truck's bracket currently hangs through
  its windscreen.
- The `ConeCatcher` and `RoofZone` boxes stay hand-authored per scene. There is no
  substitute for shaping them against the actual mesh, and getting them wrong changes what
  counts as a landing — the one thing in this game that should never be derived from a
  guess.

### 7. An authoring aid, not an authoring requirement

`Tools/derive_vehicle_footprint.gd`, an `EditorScript` run from the editor: instantiate a
vehicle scene, union the AABBs of its `MeshInstance3D` children, and print the footprint
and origin height in the exact form the `.tres` wants. This is how a new profile gets its
first numbers in ten seconds instead of by trial and error; the numbers are still authored,
still tunable by hand, and still checked at runtime by `verify_footprints`.

### 8. Docs and the import checklist

`docs/parking-bays.md` gets a short section pointing at the profile, and this file grows
the checklist for adding a vehicle:

1. Import the mesh under `ThirdParty/Models/`.
2. Duplicate `Scenes/SUV.tscn`, swap the mesh and collision shape, reshape `ConeCatcher`
   and `RoofZone` around the new body, set `marker_height`.
3. Run the footprint tool, make an `Assets/Vehicles/<name>.tres` from its output.
4. Add the profile to `ParkingLot.vehicles`.
5. Run once with `random_seed` pinned and `verify_poses` / `verify_footprints` on; the
   Output panel should be clean.

## Verification

There is no test harness in this repo, so the check is a seeded run: pin `random_seed`,
turn on `TargetMarkers.reveal_violators`, and walk the rail. What you are looking for is
the two failures this change exists to prevent — cars sharing a patch of road, and a car
whose bracket colour disagrees with how it looks parked. Both already surface as warnings
when the tolerances contradict; the footprint check extends that to size.

## Scope notes

- `cones_required` stays per-section on `CameraStop`. Scaling it by vehicle size is a
  gameplay change, not a variety change, and it would make the same section harder or
  easier depending on a random roll.
- Bay markers stay where they are. Re-baselining them to road level and giving every
  profile a true ground offset is tidier, but it moves fourteen hand-placed nodes to fix a
  problem that `bay_height_offset` solves with one number per vehicle.
- Colour variation on a single mesh is a separate, cheaper source of variety and is not in
  this plan.
