# Parking Game — port plan

[ParkingThings](https://github.com/seankain/parkingthings/tree/main/ParkingThings) is a Godot
project written in **C#**. This repo is GDScript-only and exports to the web, where a Mono/.NET
build does not run at all. The port is therefore a language port inside the same engine, not an
engine port: scenes, physics, the renderer and the asset pipeline all carry across as they are,
and every `.cs` file becomes a `.gd` file.

The game is the second cabinet in Parkade. Its menu entry already exists in
`Scripts/Autoload/Parkade.gd` marked unavailable, pointing at `res://Scenes/ParkingGame/Main.tscn`.
The last task in this plan is flipping that flag.

## The source, file by file

Version ported from: `seankain/parkingthings@main`, Godot 4.6, C#, GL Compatibility, Jolt.

| Source (`ParkingThings/`) | Does | Ports to |
| --- | --- | --- |
| `Scripts/Game.cs` | Root: owns the menu, loads the level, pause toggle | `ParkingGame.gd` + Parkade shell |
| `Scripts/Level.cs` | Round lifecycle, timers, grading hand-off, obstacle rolls | `ParkingRound.gd` |
| `Scripts/LevelData.cs` | Per-round tallies, rank/grade maths, tuning constants | `RoundData.gd`, `ParkingRules.gd` |
| `Scripts/Player.cs` | `VehicleBody3D` driving, respawn, collision reporting | `PlayerCar.gd` |
| `Scripts/CameraControl.cs` | Spring-arm freelook, snap-back, end-of-round spin | `ChaseCamera.gd` |
| `Scripts/ParkingSpace.cs` | Live parking score for the bay the player is in | `ParkingBay.gd` |
| `Scripts/ParkingSpaceArea.cs` | Entry/exit detection, "is a car already here" | folded into `ParkingBay.gd` |
| `Scripts/Spawner.cs` | Instances and frees NPC cars and pedestrians | `TrafficSpawner.gd` |
| `Scripts/NpcCar.cs` | Parked NPC car, random paint | `NpcCar.gd` |
| `Scenes/MobileNpc.cs` | Navigating pedestrian, ragdolls when hit | `Pedestrian.gd` |
| `Scripts/OffroadArea.cs` | Accumulates time spent off the tarmac | `OffroadZone.gd` |
| `Scripts/KillPlane.cs` | Respawns a car that fell out of the world | `KillPlane.gd` |
| `Scripts/IObstacleType.cs` | Marker interface for "what did I just hit" | `Obstacle.gd` (enum + group) |
| `Scripts/Hud.cs` | Clock, score, centre message | `ParkingHUD.gd` |
| `Scenes/LevelScoreHudElement.cs` | End-of-round score card | `ScoreCard.gd` |
| `Scripts/DebugHud.cs` | Three live scoring readouts | `DebugReadout.gd` |
| `Scripts/Menu.cs` | Play/resume/quit menu | `PauseMenu.gd` |
| `Scenes/NpcRagdoll.cs`, `Scripts/RagdollTest.cs`, `Scripts/TestHingeMover.cs`, `Scripts/SkeletonUtils.cs`, `Scripts/SpectatorCamera.cs`, `Scripts/NodePool.cs` | Scratch, dead or unused | not ported — see [Not being ported](#not-being-ported) |

Scenes: `level.tscn`, `simple_player.tscn`, `simple_npc.tscn`, `parking_space.tscn`, `hud.tscn`,
`debug_hud.tscn`, `Menu.tscn`, `Main.tscn`, `HumanNpc.tscn`. `player.tscn`, `nissan_sentra.tscn`,
`RagdollTest.tscn` and `test_hinge.tscn` are not reachable from `level.tscn` and are left behind.

## Where it lands

```
Scenes/ParkingGame/          Main.tscn (game root), Lot.tscn, PlayerCar.tscn, NpcCar.tscn,
                             ParkingBay.tscn, Pedestrian.tscn, UI/
Scripts/ParkingGame/         one .gd per row of the table above
ThirdParty/Models/ParkingLot/, OfficeBuilding/, Pedestrian/
ThirdParty/Fonts/            the two fonts the HUD uses
```

Cone Justice keeps `Scenes/Main.tscn` and `Scripts/{Gameplay,UI,Camera}/` where they are. Moving
them under `Scenes/ConeJustice/` would be tidier and is deliberately not part of this port: it
touches every scene in the repo and would bury the parking game's diff.

**Names must not collide.** `class_name` is global in GDScript, so two scripts claiming one name
is a hard parse error, and the two games overlap heavily in vocabulary. Cone Justice already owns
`ParkingSpace`, `ParkingLot`, `HUD`, `ScoreManager`, `SectionManager`, `SectionTimer`, `TargetCar`,
`CameraRig`, `CameraStop`, `CameraTrack`, `ConeThrower`, `ConeBody`, `RunStats`, `VehicleProfile`,
`Screens`, `Crosshair`, `TargetMarkers`, `SectionTransition`, `ConeIcon`, `ConeMagazine`. Hence
`ParkingBay` rather than `ParkingSpace`, and `ParkingHUD` rather than `Hud` — `Hud` and `HUD`
differing only in case would parse and would be a trap.

The two autoloads are Cone Justice's, not the arcade's: `GameState` holds cone counts and a run
state enum that means nothing here, and `EventBus` is a wall of cone signals. **The parking game
adds no autoload.** Its state lives on `ParkingRound`, which is what the source does anyway, and
its nodes talk over ordinary signals. `Parkade`, `SfxPlayer` and `MusicPlayer` are shared.

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

Two structural rules that are not mechanical:

- **Absolute node paths die.** The source reaches across the tree with strings like
  `"/root/Main/Level/Player/SpringArm3D"`, which break the moment the game is instanced under a
  different root — which is exactly what Parkade does to it. Every one becomes an `@export`
  reference or a group lookup, the way `SectionManager` resolves `CameraTrack` today.
- **Events fired from outside the class die.** `KillPlane.cs` invokes `player.PlayerRespawned`
  itself; C# allows it inside one assembly, GDScript does not let you emit another object's
  signal. The killer calls a method on the car, and the car emits.

## Assets

Only what `level.tscn` actually reaches is worth importing. The player and NPC cars are built from
primitive meshes, so the 30 MB `generic-passenger-car-pack` — which only the unused `player.tscn`
touches — stays out, and with it the duplicate of the car pack this repo already ships under
`ThirdParty/Models/GenericPassengerCarsPack/`.

| Asset | Size | Needed for |
| --- | --- | --- |
| `Models/auzrea_parking_final/` (glTF + textures) | 256 KB | the lot itself |
| `Models/low_rise_wall_to_wall_office_building/` | 1.2 MB | the building the pedestrians walk to |
| `Models/Npcs/` (`.res` mesh + `WalkPhone.res` + texture) | 4.5 MB | the pedestrian (T13 only) |
| `UI/Fonts/BasicHandwriting.ttf`, `ThreeDimRightwardsRound.ttf` | 71 KB | the HUD |

That is ~6 MB against a repo that already carries 116 MB under `ThirdParty/`, and ~1.5 MB of it if
T13 is deferred.

Licensing: the two Sketchfab models carry `license.txt` (attribution required) — both files come
across into `ThirdParty/` next to the model and both get a line in the README's Credits section,
the same treatment the existing third-party models get. **The fonts ship with no licence file**;
their licences have to be established before they go into a published build, or the HUD uses the
default theme font instead.

## Task breakdown

Sizes are relative: **S** one sitting, **M** half a day, **L** longer, and be suspicious of it.
Each task should end on a commit that at least imports and opens headlessly.

### T1 — Assets and third-party licensing
**Depends on:** nothing · **Size:** S

Copy the four asset groups above into `ThirdParty/`, rewrite the `res://Models/...` paths in their
`.import` files and in any scene that references them, let Godot regenerate UIDs, and add the
credits.

**Done when:** `godot --headless --import` is clean, every imported file has a `.uid`, both
`license.txt` files sit beside their model, and the README credits them.

### T2 — Skeleton, input map, groups
**Depends on:** T1 · **Size:** S

Create `Scenes/ParkingGame/` and `Scripts/ParkingGame/` with `Main.tscn` as a `Node3D` that loads
and shows an empty lot. Add the input actions — `drive_forward`, `drive_back`, `steer_left`,
`steer_right` (WASD) — using this repo's snake_case naming, not the source's `Forward`/`Left`. Add
the `NpcVehicle` and `NpcLiving` global groups. Write `Obstacle.gd`: the `ObstacleType` enum plus
the one group name that marks a node as hittable.

Do **not** add a `Pause` action: Escape belongs to Parkade. T11 decides what the parking game does
with it.

**Done when:** `Main.tscn` opens headless with no errors and the actions exist in `project.godot`.

### T3 — Player car
**Depends on:** T2 · **Size:** M

Port `Player.cs` → `PlayerCar.gd` and `simple_player.tscn` → `PlayerCar.tscn`, minus the camera
(T4). Steering via `move_toward` against `MAX_STEER`, engine force from the drive axis, `R`
respawns to the `Respawn` group marker, `body_entered` reports what was hit. Signals
`respawned` and `hit_obstacle(kind)` replace the two C# delegates. `_IntegrateForces`'s deferred
respawn flag is dead weight once respawn is a method — drop it.

**Done when:** the car drives, steers, and respawns to the marker with zeroed velocities.

### T4 — Chase camera
**Depends on:** T3 · **Size:** S

Port `CameraControl.cs` → `ChaseCamera.gd` on the `SpringArm3D`. Mouse look, idle snap-back after
`duration_to_snap`, `snap_to_default()`, `start_idle_rotation()` for the end-of-round spin.

The source's tilt clamp is wrong twice over: it clamps `Rotation.X` (radians) against `TiltMax`
(75, degrees), and it clamps the *old* value rather than the one it just computed, so the clamp
never does anything. Clamp the new pitch in radians against `deg_to_rad(tilt_max)`.

**Done when:** look works, pitch is actually limited, and the camera returns to centre on idle.

### T5 — The lot
**Depends on:** T3 · **Size:** M

Port `level.tscn` → `Lot.tscn`: geometry, static bodies, lighting, `WorldEnvironment`, respawn
marker, the twenty bay placements (as plain markers for now), `KillPlane` and `OffroadZone`.
Port `KillPlane.gd` and `OffroadZone.gd`. The `NavigationRegion3D` and `BuildingEntrance` come
across now even though nothing navigates until T13; baking navigation later against a changed lot
is worse than carrying two nodes.

**Done when:** the car drives the whole lot, falling off respawns it, and the offroad zone
accumulates time.

### T6 — Parking bay
**Depends on:** T5 · **Size:** M

Port `parking_space.tscn` → `ParkingBay.tscn` and merge `ParkingSpace.cs` with
`ParkingSpaceArea.cs` into one `ParkingBay.gd` — the source's own TODO says the sub-node is
needless, and one script removes the event relay entirely. Keep: entry/exit tracking, the left/right
line `Area3D`s, `has_npc_vehicle` from the overlapping bodies, and the settle check that ends the
round once the player's speed drops below the threshold.

The bay measures — angle to the bay's axis, distance to its centre, which lines are crossed — and
writes them to `RoundData`. It does **not** grade; that is T7. The four corner posts are unused in
the source; either wire them into the measurement or drop them, but do not port them as decoration.

**Done when:** driving into a bay starts scoring, leaving stops it, coming to rest ends the round,
and the three measurements read sanely in the debug readout.

### T7 — Grade model
**Depends on:** T6 · **Size:** S

Port `LevelData.cs` → `RoundData.gd` (per-round tallies) and `LevelDefaults` → `ParkingRules.gd`
(`const` block: 60 s default, 25 s floor, 5 s per level, +2 cars per level, 10 s event interval).

The rank maths exists twice in the source, in `LevelData.CalculateRank` and in
`ParkingSpace.CalculateCurrentParkingScore`, and the two have already drifted — only the second
counts line crossings into the live score. **One implementation**, in `RoundData`, called by both
the live readout and the score card.

**Done when:** a table of (angle, distance, lines, collisions) → grade is covered by a test scene
or a `_run` script, including the boundary values 0.5/0.9/1.5/2.0 m.

### T8 — Round lifecycle
**Depends on:** T7 · **Size:** L

Port `Level.cs` → `ParkingRound.gd`: the `ACTIVE → OVER → next/reset` state machine, the countdown,
the five-second post-round hold, `end_round()`, `reset_round()` and `next_round()`, plus the level
timer curve (default minus decrement per level, floored). Parked-outside-a-bay ends the round as a
failure.

`next_round` and `reset_round` are near-duplicates in the source, one of which builds `LevelData`
twice; write one `_start_round(advance: bool)`.

**Done when:** a full loop plays — drive, park, grade, hold, next round with less time and more
cars — and a failed park re-runs the same level.

### T9 — NPC cars
**Depends on:** T8 · **Size:** M

Port `Spawner.cs` → `TrafficSpawner.gd` and `NpcCar.cs` → `NpcCar.gd` (+ `simple_npc.tscn` →
`NpcCar.tscn`), including the random paint via a duplicated `StandardMaterial3D`.

Fill bays by shuffling the bay list and taking the first _n_ rather than the source's rejection
sampling, which redraws until a `HashSet` fills and gets slower the fuller the lot is. Free with
`queue_free()`, never `Free()`.

**Done when:** each round fills `level × 2` bays (clamped so at least one stays free), a reset
clears them with no leaked nodes, and no two cars spawn into the same bay.

### T10 — HUD and score card
**Depends on:** T8 · **Size:** M

Port `hud.tscn` + `Hud.cs` → `ParkingHUD.tscn`/`.gd`, `LevelScoreHudElement.cs` → `ScoreCard.gd`,
and `debug_hud.tscn` → `DebugReadout.tscn` behind an `@export var show_debug` that is off by
default.

The HUD listens to `ParkingRound` signals; it must not resolve the round by absolute path every
frame the way `Hud.cs` does. Clock formatting is explicit (`MM:SS`), not
`TimeSpan.ToString()`. Keep the score card's rollout animation.

**Done when:** clock, live score and grade card all read correctly through a full round, and the
debug readout is off in a default build.

### T11 — Pause, and the way back to Parkade
**Depends on:** T10 · **Size:** S

Port `Menu.cs`/`Menu.tscn` → `PauseMenu.gd`/`.tscn`, keeping the play/resume duality but dropping
`Quit` in favour of **PARKADE MENU**, which calls `Parkade.return_to_menu()`.

Escape opens this menu and Escape closes it. Parkade only sees Escape as *unhandled* input, so the
pause menu consuming it (`get_viewport().set_input_as_handled()`) is all it takes to keep Escape
from dropping the player out of the game mid-round. Verify both: Escape pauses, Escape resumes,
and the menu button leaves.

**Done when:** pausing stops the round and the clock, resuming continues it, and leaving returns to
a working Parkade menu with the cursor visible.

### T12 — Audio
**Depends on:** T11 · **Size:** S

Engine note, collisions, a round-over sting through the existing `SfxPlayer`; `MusicPlayer` already
runs across scene changes and needs nothing. New clips follow
`Tools/generate_placeholder_audio.py` and `Assets/Audio/README.md`.

**Done when:** the game is audible and the Music/SFX buses behave as they do in Cone Justice.

### T13 — Pedestrians and ragdolls *(optional, gated)*
**Depends on:** T9 · **Size:** L

The highest-risk part of the source and the least load-bearing. `HumanNpc.tscn` is 100 KB of
skeleton with a `PhysicalBoneSimulator3D`, `MobileNpc.cs` drives it with a `NavigationAgent3D`, and
the whole thing exists to be knocked over by the player. It needs the baked navigation mesh from
T5, the animation library, and it is the one part of the port whose physics behaviour on the GL
Compatibility web build is unknown.

Ship it behind `@export var pedestrians_enabled := false` on `ParkingRound` so the cabinet can go
live without it. `LookAt` on a zero-length or vertical direction errors — guard both.

**Done when:** a pedestrian walks from a bay to the building entrance, ragdolls on contact with the
player, is cleaned up on round reset, and the web build holds frame rate with several active.

### T14 — Web export and performance
**Depends on:** T12 · **Size:** M

Export the `Web` preset with the parking game included and play it in a browser. Watch the `.pck`
size delta, the load time, and physics cost with a full lot of `VehicleBody3D` NPCs — twenty parked
vehicle bodies is the thing most likely to fall over on a phone. Freeze parked NPC cars
(`freeze = true` / `PhysicsBody3D` sleep) unless they need to be pushable.

**Done when:** the preset exports, both games play from one build in a browser, and the size and
frame rate are recorded in this document.

### T15 — Open the cabinet
**Depends on:** T14 · **Size:** S

Flip `available` to `true` on the `parking_game` entry in `Scripts/Autoload/Parkade.gd`, check the
tagline and control hints against what shipped, update the README, and add a
`docs/parking-game.md` for the game the way `docs/parking-bays.md` documents Cone Justice.

**Done when:** the menu launches the parking game, Escape returns, and CI is green on `main`.

### Order

```
T1 ─ T2 ─ T3 ─ T4
          │
          └─ T5 ─ T6 ─ T7 ─ T8 ─┬─ T9 ──┬─ T13 (optional)
                                └─ T10 ─┴─ T11 ─ T12 ─ T14 ─ T15
```

T1–T5 is a drivable car in a lot and is worth doing in one go. T6–T8 is the actual game. Everything
after T11 is shippable-quality work that can slip without blocking the cabinet from opening,
except T14.

## Known defects in the source

Fix these on the way across rather than porting them faithfully and rediscovering them later.

- **`Spawner` frees with `Free()`, not `queue_free()`.** Immediate frees during a physics callback
  are how you get a crash that only happens when a car is touching something.
- **Rank maths is duplicated and has drifted** — `LevelData.CalculateRank` ignores line crossings
  while `ParkingSpace.CalculateCurrentParkingScore` counts them (T7).
- **`Hud.ShowMessage` starts its timer twice**, once with an explicit 3 s and once with the
  inspector value, so the message duration is whichever wins.
- **`CameraControl` tilt clamp is a no-op** and mixes degrees with radians (T4).
- **`Game._Input` polls `Input.IsActionPressed("Pause")` inside an event handler**, so pause fires
  on any key held while Escape is down. Use `event.is_action_pressed`.
- **`GenerateObstacles` rejection-samples** bay indices until a set fills (T9).
- **`KillPlane` invokes the player's delegate itself** — impossible in GDScript, and the wrong
  shape anyway (Translation rules).
- **Absolute `/root/Main/Level/...` paths everywhere** — they cannot survive being a cabinet in
  Parkade (Translation rules).
- **The parking angle is `|deg(angle) − 90|`**, which reads as a magic number: it falls out of
  comparing the car's `-Z` against the bay's `+Z`. Compare against the bay's forward axis directly
  and the 90 disappears.

## Not being ported

`RagdollTest.cs`/`.tscn`, `TestHingeMover.cs`/`test_hinge.tscn` (a generated test script),
`SpectatorCamera.cs` (`StartSpin` computes a position and discards it; `GetNode<Node3D>("Player")`
would not resolve), `NodePool.cs` (`Recall` always returns null and `Stow` is empty),
`SkeletonUtils.cs` (entirely commented out), `NpcRagdoll.cs` (a test harness for
`NpcRagdoll.tscn`), and `nissan_sentra.tscn`/`player.tscn` (unreferenced by the level, 5.7 MB and
30 MB of assets behind them).

If any of it turns out to be needed, it is one file in a repo that is not going anywhere.

## Open questions

1. **Does the parking game keep Cone Justice's street, or its own lot?** This plan ports the
   source's lot. Sharing one environment between both cabinets would be a bigger, better-looking
   change and a much larger port.
2. **Are the two fonts licensed for redistribution?** Blocking for T1 if the HUD is to use them.
3. **How many rounds is a run?** The source escalates forever. An arcade cabinet probably wants an
   end, and Cone Justice already has a run-over screen worth matching.
