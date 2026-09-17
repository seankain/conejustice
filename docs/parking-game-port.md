# Parking Game — port plan

[ParkingThings](https://github.com/seankain/parkingthings/tree/main/ParkingThings) is a Godot
project written in **C#**. This repo is GDScript-only and exports to the web, where a Mono/.NET
build does not run at all. The port is therefore a language port inside the same engine, not an
engine port: scenes, physics, the renderer and the asset pipeline all carry across as they are,
and every `.cs` file becomes a `.gd` file.

The game is the second cabinet in Parkade. Its menu entry already exists in
`Scripts/Autoload/Parkade.gd` marked unavailable, pointing at `res://Scenes/ParkingGame/Main.tscn`.
The last task in this plan is flipping that flag.

The source is a prototype and reads like one: duplicated maths that has already drifted, absolute
node paths, dead scripts, a scoring rule implemented twice. **It is not ported faithfully.** Every
defect listed at the bottom is fixed on the way across, and the shared-code extractions below are
part of the work, not a follow-up.

## The source, file by file

Version ported from: `seankain/parkingthings@main`, Godot 4.6, C#, GL Compatibility, Jolt.

| Source (`ParkingThings/`) | Does | Ports to |
| --- | --- | --- |
| `Scripts/Game.cs` | Root: owns the menu, loads the level, pause toggle | `ParkingGame.gd` + Parkade shell |
| `Scripts/Level.cs` | Round lifecycle, timers, grading hand-off, obstacle rolls | `ParkingRound.gd` |
| `Scripts/LevelData.cs` | Per-round tallies, rank/grade maths, tuning constants | `RoundData.gd`, `ParkingRules.gd` |
| `Scripts/Player.cs` | `VehicleBody3D` driving, respawn, collision reporting | `PlayerCar.gd` |
| `Scripts/CameraControl.cs` | Spring-arm freelook, snap-back, end-of-round spin | `ChaseCamera.gd` |
| `Scripts/ParkingSpace.cs` | Live parking score for the space the player is in | `ScoredParkingSpace.gd` |
| `Scripts/ParkingSpaceArea.cs` | Entry/exit detection, "is a car already here" | folded into `ScoredParkingSpace.gd` |
| `Scripts/Spawner.cs` | Instances and frees NPC cars and pedestrians | `TrafficSpawner.gd` |
| `Scripts/NpcCar.cs` | Parked NPC car, random paint | `ParkedCar.gd` |
| `Scenes/MobileNpc.cs` | Navigating pedestrian, ragdolls when hit | `Pedestrian.gd` |
| `Scripts/OffroadArea.cs` | Accumulates time spent off the tarmac | `OffroadZone.gd` |
| `Scripts/KillPlane.cs` | Respawns a car that fell out of the world | `KillPlane.gd` |
| `Scripts/IObstacleType.cs` | Marker interface for "what did I just hit" | `Obstacle.gd` (enum + group) |
| `Scripts/Hud.cs` | Clock, score, centre message | `ParkingHUD.gd` |
| `Scenes/LevelScoreHudElement.cs` | End-of-round score card | `ScoreCard.gd` |
| `Scripts/DebugHud.cs` | Three live scoring readouts | `DebugReadout.gd` |
| `Scripts/Menu.cs` | Play/resume/quit menu | `PauseMenu.gd` |
| `Scenes/NpcRagdoll.cs`, `Scripts/RagdollTest.cs`, `Scripts/TestHingeMover.cs`, `Scripts/SkeletonUtils.cs`, `Scripts/SpectatorCamera.cs`, `Scripts/NodePool.cs` | Scratch, dead or unused | not ported — see [Not being ported](#not-being-ported) |

Scenes: `level.tscn`, `parking_space.tscn`, `hud.tscn`, `debug_hud.tscn`, `Menu.tscn`, `Main.tscn`,
`HumanNpc.tscn`. `simple_player.tscn` and `simple_npc.tscn` are box-primitive placeholder cars and
are **not** ported — see [Vehicles](#vehicles). `player.tscn`, `nissan_sentra.tscn`,
`RagdollTest.tscn` and `test_hinge.tscn` are not reachable from `level.tscn` and are left behind.

## Where it lands

```
Scenes/ParkingGame/          Main.tscn (game root), VehicleSelect.tscn, Lot.tscn,
                             ScoredParkingSpace.tscn, Pedestrian.tscn, UI/
Scenes/Vehicles/             drivable chassis shared by both cabinets' future needs
Assets/Vehicles/Drivable/    DrivableVehicle resources — the vehicle-select catalog
Scripts/ParkingGame/         one .gd per row of the table above
ThirdParty/Models/ParkingLot/, OfficeBuilding/, Pedestrian/
ThirdParty/Fonts/            the two fonts the HUD uses
```

`Main.tscn` is the cabinet's own root and owns a two-state flow: **select → play**. It shows
`VehicleSelect.tscn` first, frees it when the player confirms a car, then builds the lot and the
round with that car. Parkade swaps whole scenes *between* cabinets; inside one, the game root adds
and removes its own children.

Cone Justice keeps `Scenes/Main.tscn` and `Scripts/{Gameplay,UI,Camera}/` where they are. Moving
them under `Scenes/ConeJustice/` would be tidier and is deliberately not part of this port: it
touches every scene in the repo and would bury the parking game's diff.

### Naming

`class_name` is global in GDScript, so two scripts claiming one name is a hard parse error, and the
two games overlap heavily in vocabulary. Cone Justice already owns `ParkingSpace`, `ParkingLot`,
`HUD`, `ScoreManager`, `SectionManager`, `SectionTimer`, `TargetCar`, `CameraRig`, `CameraStop`,
`CameraTrack`, `ConeThrower`, `ConeBody`, `RunStats`, `VehicleProfile`, `Screens`, `Crosshair`,
`TargetMarkers`, `SectionTransition`, `ConeIcon`, `ConeMagazine`.

The collision that matters is the parking space, because both games have one and they are not the
same thing:

| | Cone Justice `ParkingSpace` | Parking Game `ScoredParkingSpace` |
| --- | --- | --- |
| What it is | A painted bay the lot parks a car into | A bay that watches the player park in it |
| Knows about | Its own pose and how much room is beside it | Angle, distance off centre, which lines are crossed, what is occupying it |
| Contains | A marker and its tolerances | Three `Area3D`s — the bay volume and the two painted lines |
| Decides | Whether the car in it looks legal, at spawn time | The player's grade, continuously, and when the round ends |

So the name says what the extra machinery is for: this is the space that **scores you**.
(`MeasuredParkingSpace` says the same about the `Area3D`s; `Scored` was picked because the grade,
not the measurement, is what the player sees.) The other renames follow the same rule —
`ParkingHUD` rather than `Hud`, since `Hud` and `HUD` differing only in case would parse and would
be a trap, and `ParkedCar` rather than `NpcCar`, since the NPC cars never drive.

### State

The two autoloads are Cone Justice's, not the arcade's: `GameState` holds cone counts and a run
state enum that means nothing here, and `EventBus` is a wall of cone signals. **The parking game
adds no autoload.** Its state lives on `ParkingRound`, which is what the source does anyway, and
its nodes talk over ordinary signals. `Parkade`, `SfxPlayer` and `MusicPlayer` are shared.

## Vehicles

The source drives a box. `simple_player.tscn` and `simple_npc.tscn` are `VehicleBody3D`s built from
primitive meshes, and the one scene with a real car on it — `player.tscn`, on the 30 MB
`generic-passenger-car-pack` — is not reachable from the level.

**This repo already has cars.** Cone Justice ships `ThirdParty/Models/GenericPassengerCarsPack/`
with `SUV_body.res`, `Minivan_body.res`, `Wheel.res` and `MinivanWheel.res`, mounted in
`Scenes/SUV.tscn` and `Scenes/Minivan.tscn`. The parking game uses those meshes, which means the
source's car pack is never imported, the primitives are never ported, and both cabinets show the
same vehicles — which is what makes the **vehicle select** screen (T10) worth having: picking a car
before the round is only interesting if the cars look like something.

What can and cannot be reused from those scenes:

- **The meshes and their transforms: reuse exactly.** The body mesh sits under a basis that is a
  permutation of the axes scaled by 100 — the `.res` files are authored in centimetres and not
  Y-forward. Copy the transform out of `Scenes/SUV.tscn` rather than re-deriving it.
- **The wheel placements: reuse as `VehicleWheel3D` positions.** The SUV's four wheel meshes sit at
  y ≈ 0.40, x ≈ ±0.72, z ≈ −1.69 and +1.42, at mesh scale 0.1 — a wheel radius near 0.40 m and a
  wheelbase near 3.1 m, which is the starting point for the wheel nodes rather than a guess.
- **The collision shape: cannot be reused.** `Scenes/SUV.tscn` collides with a
  `ConcavePolygonShape3D`, which Godot only supports on static bodies. A `VehicleBody3D` needs a
  convex hull or a box; the drivable chassis gets its own.
- **`ConeCatcher`, `RoofZone`, `collision_layer = 2` and `TargetCar.gd`: leave behind.** They are
  how a car receives a cone, and nothing in the parking game throws one.

So the mesh set is shared and the body is not: Cone Justice's cars stay `StaticBody3D` targets, the
parking game's are `VehicleBody3D` chassis, and neither scene changes when the other does.

`VehicleProfile` (Cone Justice's spawn-time footprint data) is left alone. The drivable side gets
its own `DrivableVehicle` resource in T4, because what the lot needs to know before a car exists
and what the select screen needs to show are different lists.

### One rule the chassis has to follow

**Every visual the chassis has — body mesh and all four wheel meshes — hangs off a single `Visuals`
node.** The select screen spins cars on turntables, and a `VehicleBody3D` parented to a rotating
node does not spin: it is a physics body, the engine owns its transform, and it will fight the
turntable and then fall over. The preview is therefore built from the `Visuals` subtree alone,
instanced without ever adding the body to the tree. One node in the chassis scene is all that
costs, and it is invisible at runtime — but retrofitting it after four scenes exist is not.

## Translation rules

Settle these once; every task below assumes them.

| C# | GDScript |
| --- | --- |
| `public delegate` + `event` + `Invoke` | `signal` + `emit` |
| `[Export] public T Field` | `@export var field: T` |
| `GetNode<T>("/root/Main/Level/X")` | `@export` node ref, or group lookup |
| `interface IObstacleType` | `obstacle_kind()` on the node + a group |
| `Random.Shared.Next(a, b)` | one `RandomNumberGenerator` per system, seeded once |
| `node.Free()` | `queue_free()` — see [Known defects](#known-defects-in-the-source) |
| `TimeSpan.FromSeconds(x).ToString()` | explicit `"%d:%02d"` formatting |
| `Mathf.MoveToward`, `Mathf.Clamp`, `Mathf.RadToDeg` | `move_toward`, `clampf`, `rad_to_deg` |
| `(int)(a / b)` on ints | `a / b` is already integer division; use `/` on ints, `floori()` otherwise |
| `LINQ .Where().Cast().ToList()` | `filter()`/`map()` on `Array`, or a plain loop |

Two engine facts the port ran into, both measured rather than assumed, and both
cheaper to know before a scene is authored than after:

- **Godot's `VehicleBody3D` drives towards +Z, not -Z.** Its wheels take their axle from local
  `-X`, so the forward they push along is `up.cross(axle)` = `+Z` — the opposite of the `-Z` that
  `look_at`, `ParkingSpace` and every car scene in this repo call forward. A chassis given `+2600`
  of engine force travels `+Z`. The port keeps `-Z` forward and applies the sign where input meets
  the engine (`PlayerCar.DRIVE_SIGN`, `STEER_SIGN`) rather than building one car backwards. The
  source sidesteps this by putting its steering wheels at `+Z`, which is why its box drives at all.
- **`engine_force` is applied at every wheel marked `use_as_traction`**, so a four-wheel-drive
  chassis multiplies it by four, and Godot's vehicle has no drag worth the name: without a power
  curve the car accelerates in a straight line until the lot runs out.
- **A hand-written `.tscn` needs `node_paths=PackedStringArray("field")` on the node header** for
  an `@export var field: Node3D` to resolve. Without it the `field = NodePath("Visuals")` line is
  silently dropped and the reference is null at runtime. Scenes saved from the editor get this for
  free; scenes written by hand — which is most of this port — do not.

Two structural rules that are not mechanical:

- **Absolute node paths die.** The source reaches across the tree with strings like
  `"/root/Main/Level/Player/SpringArm3D"`, which break the moment the game is instanced under a
  different root — which is exactly what Parkade does to it. Every one becomes an `@export`
  reference or a group lookup, the way `SectionManager` resolves `CameraTrack` today.
- **Events fired from outside the class die.** `KillPlane.cs` invokes `player.PlayerRespawned`
  itself; C# allows it inside one assembly, GDScript does not let you emit another object's
  signal. The killer calls a method on the car, and the car emits.

## Shared code, not copied code

The source's duplication is the main thing being fixed. Each of these is one implementation in the
port, and the task that owns it is named:

| Duplicated in the source | Becomes |
| --- | --- |
| Rank maths in both `LevelData.CalculateRank` and `ParkingSpace.CalculateCurrentParkingScore` — already drifted, only the second counts line crossings | one `RoundData.grade()` (T8) |
| `Level.ResetLevel` and `Level.NextLevel`, near-identical, one building `LevelData` twice | one `_start_round(advance: bool)` (T9) |
| `ParkingSpace` + `ParkingSpaceArea`, a two-node relay for one bay — the source's own TODO calls it needless | one `ScoredParkingSpace.gd` (T7) |
| `MAX_STEER`/`SteeringSpeed`/`ENGINE_POWER` on both `Player` and `NpcCar`, where `NpcCar` never drives (its `_PhysicsProcess` is entirely commented out) | one chassis scene; parked cars are the same scene, frozen, with no input (T10) |
| Seconds-to-clock formatting in both `Hud` and `LevelScoreHudElement` | one formatter (T11) |
| `Random.Shared` reached for from three files | one seeded `RandomNumberGenerator` per system (T9, T10) |

Across the two cabinets, share only what is genuinely the same thing: the vehicle **meshes**
(above), the `SfxPlayer`/`MusicPlayer` autoloads, and the Parkade shell. Do not merge the two
games' state, event or HUD code to save lines — they are different games that happen to both
involve parking, and the autoload section says why.

## Assets

Only what `level.tscn` actually reaches is worth importing, and the cars now come from this repo
rather than from the source, so the source's 30 MB `generic-passenger-car-pack` — and the duplicate
it would make of the car pack already under `ThirdParty/` — stays out entirely.

| Asset | Size | Needed for | Status |
| --- | --- | --- | --- |
| `Models/auzrea_parking_final/` (glTF + textures) | 256 KB | the lot itself | imported as `ThirdParty/Models/ParkingLot/` |
| `Models/low_rise_wall_to_wall_office_building/` | 1.2 MB | the building the pedestrians walk to | imported as `ThirdParty/Models/OfficeBuilding/` |
| `Models/Npcs/` (`.res` mesh + `WalkPhone.res` + texture) | 4.5 MB | the pedestrian (T15 only) | **not imported** — unlicensed, see below |
| `UI/Fonts/BasicHandwriting.ttf`, `ThreeDimRightwardsRound.ttf` | 71 KB | the HUD | **not imported** — unlicensed, see below |

That is ~1.5 MB against a repo that already carries 116 MB under `ThirdParty/`, and ~6 MB if the
pedestrian assets are ever cleared to come across.

### Licensing, as found

The two Sketchfab models carry `license.txt`: both are **CC-BY-4.0**, attribution required and
commercial use allowed. Each licence file sits beside its model in `ThirdParty/` and the credit
line the licence asks for is reproduced verbatim in the README's Credits section.

Nothing else in the source's asset set is licensed, so nothing else came across:

- **The fonts ship with no licence file, and their embedded metadata rules one of them out.**
  `ThreeDimRightwardsRound.ttf` carries `Copyright © 2002, m. klein. All rights reserved.` — a
  third-party font with no grant to redistribute. `BasicHandwriting.ttf` is family `MyNewFont2`,
  `Created with the help of MyScriptFont.com / Copyright belongs to the Creator`, which records no
  grant either, though it may well be first-party handwriting. Publishing either to GitHub Pages is
  redistribution, so the HUD (T12) uses the default theme font until provenance is established. If
  `BasicHandwriting.ttf` is the author's own hand, saying so in a `license.txt` beside it is all it
  takes to bring it across.
- **`Models/Npcs/` has no licence file at all**, and the mesh name (`Sketchfab_Scene_lpMaleG…`)
  points at a Sketchfab model whose terms are unrecorded. It is only needed by T15, which is
  optional and gated off by default, so the import decision belongs to T15 rather than blocking
  the lot. Its `.res` embeds an absolute `res://Models/Npcs/…png` texture path, which has to be
  rewritten when it moves — a second reason not to move it speculatively.

## Task breakdown

Sizes are relative: **S** one sitting, **M** half a day, **L** longer, and be suspicious of it.
Each task should end on a commit that at least imports and opens headlessly.

### T1 — Assets and third-party licensing
**Depends on:** nothing · **Size:** S

Copy the four asset groups above into `ThirdParty/`, rewrite the `res://Models/...` paths in their
`.import` files and in any scene that references them, let Godot regenerate UIDs, and add the
credits. No vehicle assets are imported.

**Done when:** `godot --headless --import` is clean, every imported file has a `.uid`, both
`license.txt` files sit beside their model, and the README credits them.

### T2 — Skeleton, input map, groups
**Depends on:** T1 · **Size:** S

Create `Scenes/ParkingGame/` and `Scripts/ParkingGame/` with `Main.tscn` as a `Node3D` under
`ParkingGame.gd`, which owns the select → play flow described in [Where it lands](#where-it-lands).
Until T10 exists it goes straight to an empty lot. Add the input actions — `drive_forward`,
`drive_back`, `steer_left`, `steer_right` (WASD) — using this repo's snake_case naming, not the
source's `Forward`/`Left`. Add the `NpcVehicle` and `NpcLiving` global groups. Write `Obstacle.gd`:
the `ObstacleType` enum plus the one group name that marks a node as hittable.

Do **not** add a `Pause` action: Escape belongs to Parkade. T12 decides what the parking game does
with it.

**Done when:** `Main.tscn` opens headless with no errors and the actions exist in `project.godot`.

### T3 — Drivable chassis
**Depends on:** T2 · **Size:** M

Build `Scenes/Vehicles/SuvDrivable.tscn`: a `VehicleBody3D` carrying a `Visuals` node — body mesh
plus four wheel meshes, per [One rule the chassis has to follow](#one-rule-the-chassis-has-to-follow)
— four `VehicleWheel3D`s placed from the numbers in [Vehicles](#vehicles), and a convex collision
shape of its own. Port `Player.cs` → `PlayerCar.gd` and put it on the chassis, minus the camera
(T5): steering via `move_toward` against `max_steer`, engine force from the drive axis, `R`
respawns to the `Respawn` group marker, `body_entered` reports what was hit. Signals `respawned`
and `hit_obstacle(kind)` replace the two C# delegates. `_IntegrateForces`'s deferred respawn flag
is dead weight once respawn is a method — drop it.

Tune mass, engine power, steering rate and suspension against the real body: the source's
`ENGINE_POWER = 300` was picked for a box.

**Done when:** the SUV drives, steers and brakes convincingly, does not roll over on a normal turn,
respawns to the marker with zeroed velocities, and `Visuals` instanced on its own renders a
complete, static car.

### T4 — Vehicle catalog
**Depends on:** T3 · **Size:** S

Make the chassis data-driven so that adding a car is a resource, not a code change.
`DrivableVehicle` (`Resource`): display name, chassis `PackedScene`, mass, engine power, max steer,
and the handful of numbers the select screen shows. Author `Assets/Vehicles/Drivable/Suv.tres` and
`Minivan.tres`, with `MinivanDrivable.tscn` built the same way as T3 from
`Minivan_body.res`/`MinivanWheel.res`. A `VehicleCatalog` resource holds the ordered list — that
order is the carousel's order. `ParkingRound` spawns the player's car from a catalog entry,
defaulting to the first.

While in the area: `Assets/Vehicles/SUV.tres` still carries the default 1.8 × 4.5 footprint and
Cone Justice warns about it at every launch — re-run `Tools/derive_vehicle_profile.gd` and fix it.

**Done when:** switching the catalog entry in the inspector changes which car the player drives,
and both cars drive without per-vehicle code.

### T5 — Chase camera
**Depends on:** T3 · **Size:** S

Port `CameraControl.cs` → `ChaseCamera.gd` on the `SpringArm3D`. Mouse look, idle snap-back after
`duration_to_snap`, `snap_to_default()`, `start_idle_rotation()` for the end-of-round spin.

The source's tilt clamp is wrong twice over: it clamps `Rotation.X` (radians) against `TiltMax`
(75, degrees), and it clamps the *old* value rather than the one it just computed, so the clamp
never does anything. Clamp the new pitch in radians against `deg_to_rad(tilt_max)`.

**Done when:** look works, pitch is actually limited, and the camera returns to centre on idle.

### T6 — The lot
**Depends on:** T3 · **Size:** M

Port `level.tscn` → `Lot.tscn`: geometry, static bodies, lighting, `WorldEnvironment`, respawn
marker, the twenty space placements (as plain markers for now), `KillPlane` and `OffroadZone`.
Port `KillPlane.gd` and `OffroadZone.gd`. The `NavigationRegion3D` and `BuildingEntrance` come
across now even though nothing navigates until T15; baking navigation later against a changed lot
is worse than carrying two nodes.

The parking game keeps its own lot; sharing Cone Justice's street is not on the table for this
port. The spaces were authored around a box roughly the size of the source's placeholder car —
check they still fit the real SUV before building anything on top of them, and move the markers,
not the car, if they do not.

**Done when:** the car drives the whole lot, falling off respawns it, the offroad zone accumulates
time, and the SUV fits a space with room to open an imaginary door.

### T7 — Scored parking space
**Depends on:** T6 · **Size:** M

Port `parking_space.tscn` → `ScoredParkingSpace.tscn` and merge `ParkingSpace.cs` with
`ParkingSpaceArea.cs` into one `ScoredParkingSpace.gd`. Keep: entry/exit tracking, the left/right
line `Area3D`s, `has_parked_car` from the overlapping bodies, and the settle check that ends the
round once the player's speed drops below the threshold.

The space measures — angle to its axis, distance to its centre, which lines are crossed — and
writes them to `RoundData`. It does **not** grade, and it does not write the round's score the way
`ParkingSpace.cs` does; that is T8 and T9. The four corner posts are unused in the source; either
wire them into the measurement or drop them, but do not port them as decoration.

**Done when:** driving into a space starts measuring, leaving stops it, coming to rest ends the
round, and the three measurements read sanely in the debug readout.

### T8 — Grade model
**Depends on:** T7 · **Size:** S

Port `LevelData.cs` → `RoundData.gd` (per-round tallies plus the single `grade()`) and
`LevelDefaults` → `ParkingRules.gd` (`const` block: 60 s default, 25 s floor, 5 s per level, +2
cars per level, 10 s event interval).

**One implementation**, called by both the live readout and the score card — see
[Shared code](#shared-code-not-copied-code).

**Done when:** a table of (angle, distance, lines, collisions) → grade is covered by a test scene
or a `_run` script, including the boundary values 0.5/0.9/1.5/2.0 m.

### T9 — Round lifecycle
**Depends on:** T8 · **Size:** L

Port `Level.cs` → `ParkingRound.gd`: the `ACTIVE → OVER → next/reset` state machine, the countdown,
the five-second post-round hold, `end_round()`, and one `_start_round(advance: bool)` in place of
the source's two near-identical methods, plus the level timer curve (default minus decrement per
level, floored). Parked outside a space ends the round as a failure. The round owns the score; the
space reports measurements to it.

**Done when:** a full loop plays — drive, park, grade, hold, next round with less time and more
cars — and a failed park re-runs the same level.

### T10 — Vehicle select
**Depends on:** T4, T9 · **Size:** M

The screen between picking the cabinet and driving it, in the San Francisco Rush shape: a scrolling
carousel of cars, each turning slowly on its own plate, stats beside the focused one.

It is a **3D scene, not a `Control`**. `VehicleSelect.tscn` holds a fixed camera, a dark
environment matched to the Parkade menu, a key light, and a rack of `VehicleTurntable` nodes spaced
along X — one per `VehicleCatalog` entry, built at `_ready()` from the catalog so adding a car adds
a plate. Each turntable instances only the chassis scene's `Visuals` subtree and rotates it about Y
at a constant rate; the chassis itself is never added to the tree, for the reason in
[One rule the chassis has to follow](#one-rule-the-chassis-has-to-follow).

- **Scrolling:** one tween on the rack's X (or the camera's) per step, short and eased, so a held
  key steps rather than slides. The focused plate is lit and full size; its neighbours are dimmed
  and set back, which is most of the arcade look for very little work.
- **Input:** `steer_left`/`steer_right` and the arrow keys step, `ui_accept` and a click on the
  focused car confirm, Escape leaves for Parkade — the pause menu does not exist here, so the
  shell's Escape handling is exactly right and nothing needs wiring.
- **Stats:** name plus the handful of numbers already on `DrivableVehicle`. Do not invent a
  handling stat that nothing reads.
- **Confirm:** `ParkingGame.gd` frees the select scene, builds the lot and starts the round with
  the chosen `DrivableVehicle`. The choice lives on the game root for the session; the cabinet is a
  fresh scene each time it is launched from Parkade, so a re-entry starts back at select.

**Done when:** launching the parking game lands on select, the carousel steps both ways without
running off either end, every catalog car appears and spins, confirming starts a round in the car
that was showing, Escape leaves to Parkade, and adding a third `.tres` needs no code.

### T11 — Parked cars
**Depends on:** T9, T4 · **Size:** M

Port `Spawner.cs` → `TrafficSpawner.gd` and `NpcCar.cs` → `ParkedCar.gd`, filling spaces from the
same catalog the player drives, with the random paint applied to a duplicated
`StandardMaterial3D` so one car's colour does not repaint the rest.

Parked cars are the drivable chassis with input off and `freeze = true` unless they need to be
shunted; twenty live `VehicleBody3D`s is the single most likely thing to sink the web build.
Fill spaces by shuffling the list and taking the first _n_ rather than the source's rejection
sampling, which redraws until a set fills and gets slower the fuller the lot is. Free with
`queue_free()`, never `Free()`.

**Done when:** each round fills `level × 2` spaces (clamped so at least one stays free), a reset
clears them with no leaked nodes, no two cars spawn into the same space, and a full lot holds frame
rate.

### T12 — HUD and score card
**Depends on:** T9 · **Size:** M

Port `hud.tscn` + `Hud.cs` → `ParkingHUD.tscn`/`.gd`, `LevelScoreHudElement.cs` → `ScoreCard.gd`,
and `debug_hud.tscn` → `DebugReadout.tscn` behind an `@export var show_debug` that is off by
default.

The HUD listens to `ParkingRound` signals; it must not resolve the round by absolute path every
frame the way `Hud.cs` does. One clock formatter, shared with the score card, not
`TimeSpan.ToString()`. Keep the score card's rollout animation.

**Done when:** clock, live score and grade card all read correctly through a full round, and the
debug readout is off in a default build.

### T13 — Pause, and the way back to Parkade
**Depends on:** T12 · **Size:** S

Port `Menu.cs`/`Menu.tscn` → `PauseMenu.gd`/`.tscn`, keeping the play/resume duality but dropping
`Quit` in favour of **PARKADE MENU**, which calls `Parkade.return_to_menu()`.

Escape opens this menu and Escape closes it. Parkade only sees Escape as *unhandled* input, so the
pause menu consuming it (`get_viewport().set_input_as_handled()`) is all it takes to keep Escape
from dropping the player out of the game mid-round. Verify all three: Escape pauses, Escape
resumes, and Escape on the select screen — where there is no pause menu — still leaves to Parkade.

**Done when:** pausing stops the round and the clock, resuming continues it, and leaving returns to
a working Parkade menu with the cursor visible.

### T14 — Audio
**Depends on:** T13 · **Size:** S

Engine note, collisions, a round-over sting through the existing `SfxPlayer`; `MusicPlayer` already
runs across scene changes and needs nothing. New clips follow
`Tools/generate_placeholder_audio.py` and `Assets/Audio/README.md`.

**Done when:** the game is audible and the Music/SFX buses behave as they do in Cone Justice.

### T15 — Pedestrians and ragdolls *(optional, gated)*
**Depends on:** T11 · **Size:** L

The highest-risk part of the source and the least load-bearing. `HumanNpc.tscn` is 100 KB of
skeleton with a `PhysicalBoneSimulator3D`, `MobileNpc.cs` drives it with a `NavigationAgent3D`, and
the whole thing exists to be knocked over by the player. It needs the baked navigation mesh from
T6, the animation library, and it is the one part of the port whose physics behaviour on the GL
Compatibility web build is unknown.

Ship it behind `@export var pedestrians_enabled := false` on `ParkingRound` so the cabinet can go
live without it. `LookAt` on a zero-length or vertical direction errors — guard both.

**Done when:** a pedestrian walks from a space to the building entrance, ragdolls on contact with
the player, is cleaned up on round reset, and the web build holds frame rate with several active.

### T16 — Web export and performance
**Depends on:** T14 · **Size:** M

Export the `Web` preset with the parking game included and play it in a browser. Watch the `.pck`
size delta, the load time, and physics cost with a full lot of frozen chassis. Reusing Cone
Justice's meshes means the delta should be dominated by the lot and the building, not the cars —
if it is not, something is importing the source's car pack by accident. Check the select screen
too: several spinning cars on screen at once is the first thing the player sees, and a bad first
frame rate reads as a broken game.

**Done when:** the preset exports, both games play from one build in a browser, and the size and
frame rate are recorded in this document.

### T17 — Open the cabinet
**Depends on:** T16 · **Size:** S

Flip `available` to `true` on the `parking_game` entry in `Scripts/Autoload/Parkade.gd`, check the
tagline and control hints against what shipped, update the README, and add a
`docs/parking-game.md` for the game the way `docs/parking-bays.md` documents Cone Justice.

**Done when:** the menu launches the parking game, Escape returns, and CI is green on `main`.

### Order

```
T1 ─ T2 ─ T3 ─┬─ T4 ─────────────────┐
              ├─ T5                  │
              └─ T6 ─ T7 ─ T8 ─ T9 ─┬┴─ T10 ─────────────┐
                                    ├─ T11 ─ T15 (opt.)  │
                                    └─ T12 ─ T13 ─ T14 ─ T16 ─ T17
```

T1–T6 is a real car driving around a real lot and is worth doing in one go. T7–T9 is the actual
game, and T10 is the front door to it. Everything after T13 is shippable-quality work that can slip
without blocking the cabinet from opening, except T16.

## Known defects in the source

Fix these on the way across rather than porting them faithfully and rediscovering them later. The
duplication ones are in [Shared code](#shared-code-not-copied-code) and are not repeated here.

- **`Spawner` frees with `Free()`, not `queue_free()`.** Immediate frees during a physics callback
  are how you get a crash that only happens when a car is touching something.
- **`Hud.ShowMessage` starts its timer twice**, once with an explicit 3 s and once with the
  inspector value, so the message duration is whichever wins.
- **`CameraControl` tilt clamp is a no-op** and mixes degrees with radians (T5).
- **`Game._Input` polls `Input.IsActionPressed("Pause")` inside an event handler**, so pause fires
  on any key held while Escape is down. Use `event.is_action_pressed`.
- **`GenerateObstacles` rejection-samples** space indices until a set fills (T11).
- **`KillPlane` invokes the player's delegate itself** — impossible in GDScript, and the wrong
  shape anyway (Translation rules).
- **`ParkingSpace` writes `level.Score` every frame** from inside the space. The round owns the
  score (T9).
- **Absolute `/root/Main/Level/...` paths everywhere** — they cannot survive being a cabinet in
  Parkade (Translation rules).
- **The parking angle is `|deg(angle) − 90|`**, which reads as a magic number: it falls out of
  comparing the car's `-Z` against the space's `+Z`. Compare against the space's forward axis
  directly and the 90 disappears.
- **`NpcCar._PhysicsProcess` is an empty override** around commented-out driving code, and the
  class carries three steering fields it never uses (T11).

## Not being ported

`RagdollTest.cs`/`.tscn`, `TestHingeMover.cs`/`test_hinge.tscn` (a generated test script),
`SpectatorCamera.cs` (`StartSpin` computes a position and discards it; `GetNode<Node3D>("Player")`
would not resolve), `NodePool.cs` (`Recall` always returns null and `Stow` is empty),
`SkeletonUtils.cs` (entirely commented out), `NpcRagdoll.cs` (a test harness for
`NpcRagdoll.tscn`), `simple_player.tscn`/`simple_npc.tscn` (placeholder box cars, replaced per
[Vehicles](#vehicles)), and `nissan_sentra.tscn`/`player.tscn` (unreferenced by the level, 5.7 MB
and 30 MB of assets behind them).

If any of it turns out to be needed, it is one file in a repo that is not going anywhere.

## Settled

- **The parking game keeps its own lot.** Sharing Cone Justice's street would be a bigger,
  better-looking change and a much larger port; not this one.
- **Vehicle select sits between the cabinet and the round** (T10), Rush-style: a carousel of cars
  spinning on plates, not a list of names.

## Open questions

1. **Are the two fonts licensed for redistribution?** Blocking for T1 if the HUD is to use them.
2. **How many rounds is a run?** The source escalates forever. An arcade cabinet probably wants an
   end, and Cone Justice already has a run-over screen worth matching.
3. **Does the select screen remember the last car?** It does not in T10 — the cabinet reloads from
   scratch each launch. Persisting it means a `user://` config file, which nothing in this repo has
   yet, so it is worth doing once for both games or not at all.
4. **Are all catalog cars available from the start?** Unlocking by grade is the obvious arcade
   move, and it is the one reason the carousel would need a locked state.
