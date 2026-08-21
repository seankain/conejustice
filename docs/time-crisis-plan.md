# Cone Justice — Rails Shooter Implementation Plan

A parody of *Time Crisis*: instead of a gun and bullets, the player has a truck full of
traffic cones. The camera rides a fixed rail between stops. At each stop a set of illegally
parked cars must be "coned" inside 60 seconds. Cones are real rigid bodies, so the throw is
the whole game.

## Current state

The repo is scene-only — **there is no GDScript in the project yet**:

- `Scenes/level.tscn` — street block: ground `StaticBody3D`, building, six trees, one SUV,
  one loose `Cone`, one static `Camera3D`.
- `Scenes/Cone.tscn` — `RigidBody3D` with mesh + two convex collision shapes.
- `Scenes/SUV.tscn` — `StaticBody3D` car with collision hull.
- Godot 4.7, GDScript, GL Compatibility renderer, Jolt 3D physics, Web/HTML5 export target.

Playable ground plane is roughly `x ∈ [-27, 0.5]`, `z ∈ [-22.7, 10.5]` at `y ≈ 0`, which is
the space available for authoring rail stops.

## Target architecture

```
Main (Node3D)                       Scenes/Main.tscn — new game root
├── Level                           existing level.tscn, instanced
│   ├── CameraTrack (Node3D)        ordered rail
│   │   ├── Stop0 (CameraStop)      Marker3D + section config
│   │   ├── Stop1 (CameraStop)
│   │   └── …
│   └── Targets                     TargetCar instances, referenced by stops
├── CameraRig (Node3D)              owns the Camera3D, tweens along the track
├── ConeThrower (Node)              spawn + impulse, magazine, reload
├── SectionManager (Node)           per-stop lifecycle: arm → play → clear/timeout
└── HUD (CanvasLayer)               score, timer, cone magazine, transitions
```

Cross-system communication goes through two autoloads:

- `GameState` — score, current section index, run state enum (`TRAVELLING`,
  `ENGAGED`, `SECTION_CLEAR`, `TIMEOUT`, `RUN_OVER`).
- `EventBus` — signals: `section_started`, `section_cleared`, `section_timeout`,
  `car_coned`, `cone_landed`, `cone_thrown`, `magazine_changed`, `reload_started`,
  `reload_finished`, `score_changed`, `timer_tick`.

HUD and gameplay never call each other directly; the HUD only listens.

## Key mechanics

**Camera rail.** `CameraStop` is a `Marker3D` carrying its own section config: look target,
target car list, cones required per car, time limit (default 60s), travel time and easing for
the *approach* to that stop. `CameraRig` tweens with a single `0 → 1` progress value fed into
`Transform3D.interpolate_with()`, which slerps the basis properly instead of lerping Euler
angles. Input is locked and the timer is paused while travelling.

**Coning a car.** A `TargetCar` owns a `ConeCatcher` `Area3D` hugging the body plus a smaller
`RoofZone` `Area3D`. A cone counts once it has been overlapping the catcher with
`linear_velocity.length() < settle_speed` continuously for `settle_time` (~0.5s) — so cones
that merely graze the car and roll off do not score. Roof landings score a bonus. When a car
reaches `cones_required`, it emits `car_coned`; when every car at the stop is coned, the
section clears and the rig departs for the next stop.

**Magazine.** `mag_size` cones (6). Primary mouse throws; secondary reloads over
`reload_time` (~0.9s) during which throwing is blocked. Reserve is infinite — the reload is a
timing cost, exactly as in Time Crisis. The HUD magazine is a row of cone icons that empty
left-to-right and refill on reload.

**Scoring.** Cone landed on a car `+100`, roof landing `+250`, section cleared `+1000`, plus
`remaining_seconds × 10` as a time bonus. A timeout ends the run.

## Phases

| Phase | Issues | Outcome |
|---|---|---|
| 0 — Foundation | Scaffolding, main scene, autoloads, input map | Project boots into a runnable shell |
| 1 — Camera rail | `CameraStop`, `CameraRig`, authored stops | Camera tweens stop to stop |
| 2 — Throwing | Throw + impulse, cone lifetime | Clicking throws physical cones |
| 3 — Targets | `TargetCar` settle detection, `SectionManager` | Coning cars advances the rail |
| 4 — Timer & score | 60s section timer, `ScoreManager` | Win/lose conditions exist |
| 5 — HUD | Score/timer, cone magazine, reload, transitions | Full Time Crisis-style HUD |
| 6 — Polish | Audio, web export perf pass | Shippable browser build |

Each phase is small enough to land as one PR and leave the game runnable.

## Deliberate non-goals (for now)

Cover/duck mechanic, enemies shooting back, multiple levels, save data, mobile touch input,
and networked leaderboards. Ticket them separately once the core loop is fun.
