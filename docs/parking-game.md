# Parking Game: the round, the grade, and the cars

The second Parkade cabinet. Pick a car, drive it around a lot against a countdown, and put
it between the lines. The round is graded A to F on how square you are, how centred, what
you crossed and what you hit. Park well and the next level gives you less time and more
cars to park between; park badly and you run the same level again.

It is a GDScript port of [ParkingThings](https://github.com/seankain/parkingthings/tree/main/ParkingThings),
which is the same engine written in C# — and a .NET build does not run on the web at all.
[`docs/parking-game-port.md`](parking-game-port.md) is the plan the port followed, including
which of the prototype's defects were fixed on the way rather than carried across. This
file is about the game that came out of it.

## The loop

```
vehicle select ──> round ──> graded ──> pass: next level, less time, more cars
                     ^                  fail: the same level again
                     └──────────────────┘
```

`ParkingGame` owns the cabinet: it shows `VehicleSelect`, frees it when a car is
confirmed, builds `Lot.tscn` and starts a `ParkingRound` in the chosen car. Nothing calls
`change_scene_to_file` — Parkade swaps scenes *between* cabinets, and inside one the game
root adds and removes its own children.

`ParkingRound` owns the clock, the car, the grade and what happens next. The bays report
what they measure and the round writes it down; the HUD listens to the round and reaches
into nothing.

## What the bay measures

A `ScoredParkingSpace` is a bay that watches you park in it. It runs along its own local X
axis, and a car parked properly points along ±X — **backing in is as legal as nosing in**,
so the angle folds at 90 degrees, the same rule Cone Justice's bays use.

| Measurement | What it is |
|---|---|
| `parking_angle` | degrees between the car and the bay's axis, folded at 90. Zero is square. |
| `centre_distance` | metres from the middle of the painted bay, measured flat |
| `over_left_line` / `over_right_line` | whether the car is sitting on either painted line |

The round ends when the car **stops** in a bay: ground speed under `settle_speed` for
`settle_time`. Ground speed, not total velocity, because a car standing still on this
chassis reports over a metre per second of vertical velocity for a second or two while its
springs settle. Sustained, not instantaneous, because a car passing through zero in the
middle of a three-point turn has not parked.

Settling is a state the bay holds, not an announcement it makes once. A car stopped astride
a line comes to rest in two bays at once and only one of them is being scored; a bay that
had said its piece and gone quiet would be a bay the round could never end in.

### Which bay is being scored

A car is in more than one bay more often than it looks: it swings in nose first and sweeps
its tail through the bay next door, and a car sitting on a line is in both. Of the bays the
car is inside, **the one being scored is the one whose middle it is nearest** — not the one
it entered most recently, which was the first rule and which is what made parking properly
do nothing. The last bay entered was as often as not the neighbour the tail had brushed, and
straightening up left that neighbour again and cleared the round's idea of where the car was.
Stopping on the line worked, because a car that stops on the line never leaves the bay it
entered last.

### Where the bays are

The bay volumes are not eyeballed onto the model. Every `ScoredParkingSpace` in `Lot.tscn`
sits at the middle of a painted bay, and its two line volumes sit on the painted lines
themselves: the bay is the tarmac between the stripes, each line volume is a stripe, and the
three tile the bay without overlapping. The numbers come from the lot mesh — 6.478 m of
paint, 0.162 m thick, 3.24 m between stripes, except the two bays at the far end of the long
row, which are 3.405 m and carry their own line offsets. The three bays at the ends of the
rows have paint on one side only, where the lot simply stops.

`Tools/test_bay_alignment.gd` reads the stripes back out of the model and checks every bay
against them, so this stays true rather than being true once:

```
godot --headless --script Tools/test_bay_alignment.gd
```

## The grade

One calculation, in `RoundData.rank()`, called by both the live readout and the score card.

```
distance rank  0 : within 0.5 m of the middle     angle rank  0 : under 1 degree off
               1 : 0.9 m                                      1 : 1 degree
               2 : 1.5 m                                      2 : 2 degrees
               3 : further                                    3 : 3 degrees or more

rank = (distance rank + angle rank) / 2      integer division
     + 1 per painted line crossed
     + 1 per collision
     capped at 4

0 = A, 1 = B, 2 = C, 3 = D, 4 = F.   A C or better takes the next level.
```

Two consequences worth knowing, both inherited deliberately:

- **The halving is generous about one bad number.** A square car 0.9 m off centre still
  gets an A, because rank 1 halves back to 0. It takes two mediocre numbers to lose a
  grade.
- **Distance alone never scores worse than a B.** The worst distance rank is 3, which
  halves to 1. Only lines and collisions take you past that.

Time spent off the tarmac is tallied and shown on the card but does not move the grade;
neither does it in the source, whose own comment calls that a to-do.

`Tools/test_grade_table.gd` is the table, with both sides of every boundary:

```
godot --headless --script Tools/test_grade_table.gd
```

## The cars

Adding a car is a resource and a chassis scene, not a code change. A `DrivableVehicle`
carries a display name, the chassis, and the four numbers that make a car handle like
itself; `VehicleCatalog` holds them in the order the carousel shows them, and the round
spawns whichever entry it was handed.

Godot omits a property equal to its default when it saves a resource, so the defaults on
`DrivableVehicle` are deliberately the SUV's: the reference car's `.tres` is nearly empty
and every other car lists exactly what makes it different.

**Every chassis follows one rule: every visual hangs off a single `Visuals` node.** The
select screen spins cars on turntables, and a `VehicleBody3D` parented to a rotating node
is owned by the physics engine — it fights the turntable and falls over. The turntable
instances the `Visuals` subtree alone, and the wheels under it follow the physics wheels
each frame, so steering and suspension come from the simulation rather than being animated
to look like it.

Three engine facts the chassis are built around, all measured:

- **Godot's `VehicleBody3D` drives towards +Z**, because its wheels take their axle from
  local `-X`. This repo keeps `-Z` forward and applies the sign where input meets the
  engine (`PlayerCar.DRIVE_SIGN`).
- **Steering takes no sign of its own**, which reads wrong and is right. The engine turns the
  car around its *steered* wheels, and these chassis put those at the `-Z` nose while the
  engine pushes along `+Z` — two reversals, which cancel, so a positive steering angle turns
  the car the way the player calls left. It first shipped with a second negation on top of
  that, and steered backwards. `Tools/test_drive_chassis.gd` measures which way the car
  actually went, because the sign of this one cannot be read off the code.
- **`engine_force` is applied at every traction wheel**, so four-wheel drive multiplies it
  by four, and the engine has no drag to speak of — `PlayerCar` fades its power towards
  `top_speed` so the car has one.

`Tools/test_drive_chassis.gd` measures what a chassis is worth:

```
godot --headless --script Tools/test_drive_chassis.gd
godot --headless --script Tools/test_drive_chassis.gd -- res://Scenes/Vehicles/MinivanDrivable.tscn
```

| | SUV | Minivan |
|---|---|---|
| Mass | 1400 kg | 1850 kg |
| 0–10 m/s | 3.6 s | 6.0 s |
| Stopping | 12.7 m/s in 1.7 s | 11.2 m/s in 1.9 s |
| Lean at full lock | 2.2° | 1.2° |

## The lot

`Lot.tscn` is the source's level without the prototype's furniture: the parking lot model,
the office building, road and grass bodies, a respawn marker, twenty bays, a navigation
region for pedestrians that do not exist yet, a kill plane and an offroad zone.

`TrafficSpawner` fills `level × 2` bays from the same catalog the player picks out of,
never filling the last one. Parked cars are the chassis the player drives with input off:
they are dropped the last 20 cm onto their own suspension and frozen where they land, so
nothing has to know the ride height of a chassis it has never seen, and a frozen car stops
processing entirely. Nineteen live `VehicleBody3D`s would be the first thing to sink the
web build.

A parked car and the player's car are the same class, so **"is this a `PlayerCar`?" is not
a useful question** anywhere in the lot. The player's car is the one in the `player_car`
group; the spawner's cars are marked `driven_by_player = false` and stay out of it, which
is what stops a bay measuring the traffic and ending the round the moment a parked car
settles.

## Controls

| | |
|---|---|
| `W` `A` `S` `D` | drive. Pushing against the way the car is moving brakes rather than reversing. |
| Mouse | look around. The camera recentres after a second of stillness. |
| `R` | put the car back on the marker — which restarts the attempt |
| `Escape` | pause, and again to resume. On the select screen it leaves for the Parkade menu. |

## Tuning

| Where | What |
|---|---|
| `ParkingRules` | round length, the decrement per level and its floor, cars per level, the grade boundaries, the pass mark |
| `DrivableVehicle` resources | mass, engine power, steering lock, top speed, per car |
| `ScoredParkingSpace` | settle speed and settle time |
| `PlayerCar` | brake strength, idle brake, steering rate |
| `ParkingHUD` | banner duration, the low-clock warning, and `show_debug` for the live measurements |

## Tests

```
godot --headless --script Tools/test_grade_table.gd          the grade table
godot --headless --script Tools/test_bay_alignment.gd        the bays against the lot's paint
godot --headless --script Tools/test_drive_chassis.gd        a chassis on a flat plane
godot --headless Tools/test_round_flow.tscn                  a whole round in the lot
godot --headless Tools/test_pause_flow.tscn -- round         Escape, pause, resume
godot --headless Tools/test_pause_flow.tscn -- select        Escape with no menu in the way
godot --headless Tools/test_audio_cues.tscn                  the cues and the engine note
```

The last three are scenes rather than `--script` tools for a reason worth remembering: a
script run with `--script` replaces the main loop, so autoloads are never registered and
any script naming `Parkade` or `SfxPlayer` fails to compile. Anything touching the shell,
the round or the audio has to be tested by running a scene.

## Not here yet

- **Pedestrians.** The source's ragdolling NPC is the riskiest part of it and the least
  load-bearing, and its mesh has no licence file. `ParkingRound.pedestrians_enabled` is the
  gate, off by default.
- **An end to the run.** The source escalates forever, and so does this. An arcade cabinet
  probably wants a last level and a run-over screen.
- **A remembered car.** The cabinet reloads from scratch each launch, so it always starts
  back at select. Persisting the choice needs a `user://` config file, which nothing in
  this repo has yet — worth doing once for both games or not at all.
