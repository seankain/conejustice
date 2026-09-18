# Parking Game: the round, the grade, and the cars

The second Parkade cabinet. Pick a car, drive it around a lot against a countdown, and put
it between the lines. The round is graded A to F on how square you are, how centred, what
you crossed and what you hit. Park well and the next level gives you less time, more cars
to park between, and more going on between them — spaces opening up as parked cars leave,
and rivals driving in to take the one you were going for. Park badly and you run the same
level again.

It is a GDScript port of [ParkingThings](https://github.com/seankain/parkingthings/tree/main/ParkingThings),
which is the same engine written in C# — and a .NET build does not run on the web at all.
[`docs/parking-game-port.md`](parking-game-port.md) is the plan the port followed, including
which of the prototype's defects were fixed on the way rather than carried across. This
file is about the game that came out of it.

## The loop

```
vehicle select ──> round ──> graded ──> pass: next level, less time, fuller lot,
                     ^                        and more going on in it
                     │                  fail: the same level again
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

## What the lot does while you park

The source's lot is filled once at the start of a level and then holds perfectly still,
which makes its level twenty a level one with less time on it. `LotEvents` rolls two dice
every `ParkingRules.RANDOM_EVENT_SECONDS`, and what they can do gets likelier every level:

- **A car leaves.** One of the parked cars backs out of its bay, drives down the aisle and
  goes. It opens a space that was not there when the round started — and puts a moving car
  across the aisle while you are lining up somewhere else.
- **A rival arrives.** A car comes in off the road looking for a space and takes one. Near
  the top of the lot, where there were two spaces left, it takes one of yours.

|  | Level 1 | Level 3 | Level 5 | Ceiling |
|---|---|---|---|---|
| a parked car leaves | 0.20 | 0.36 | 0.52 | 0.75 |
| a rival arrives | 0.15 | 0.35 | 0.55 | 0.85 |
| …and goes for the space nearest the player | 0.25 | 0.55 | 0.85 | 0.90 |
| cars under their own power at once | 1 | 2 | 3 | 3 |

A round is five or six rolls long, so level one is about one car leaving per round and a
rival every second round; from level eight it is both, most rolls, up to three at a time.
`ParkingRound.lot_events_enabled` turns the whole thing off and gives the source's lot
back — which is what the round-flow test wants while it measures a park.

**A rival goes for the space nearest the player** as often as the third row says, and any
free space the rest of the time. Uniformly random is the honest choice and the boring one:
in a lot with eighteen free bays a rival takes one the player was never going to reach,
and the event goes unnoticed. That fraction is the difference between a competitor and
scenery, so it climbs with the rest.

### The cars that drive themselves

`NpcDriver` moves the car rather than simulating it. The car is frozen, the same as every
other parked car, and its transform is written each physics frame —
`FREEZE_MODE_KINEMATIC` rather than the static freeze a parked car gets, so it still
shoves the player's car around instead of standing through it.

Three reasons, in the order they matter. A lot full of live `VehicleBody3D`s is the first
thing to sink the web build, and a driving car has no better claim on a suspension
simulation than a parked one. A car parking itself has to end up *between the lines*,
which is the one thing the round measures, and a steering controller ends up wherever the
physics leaves it. What it costs is a car that cannot be shoved out of its bay, which is
the right loss to take.

What it drives like is a bicycle: a heading, a speed, and a turn rate that is the speed
divided by the tightest circle a car can hold. That is the right way round — a car's
steering lock fixes its *circle*, not how fast it comes round one, so a crawling car takes
its time getting through a turn it could not take any tighter at speed. Two details fall
out of that being a car rather than a dot:

- **It backs out of a bay in a straight line first**, and only starts turning once its far
  end is clear of the paint. A car that turns any earlier sweeps that end through the cars
  parked next door.
- **It swings its tail away from where it is going**, which reads backwards and is how a
  real car leaves a perpendicular bay: back out swinging right to drive away left. A car
  that was *backed* into its bay noses out and does the opposite.

**A car with nobody in it yields to the car with somebody in it.** Collisions are scored
on the player's own `hit_obstacle`, which does not ask who drove into whom, so a rival
that ran into the player would be taking a grade off them for it. A driver that finds the
player's car in the piece of lot it was about to occupy stops and waits.

The ride height is measured, never assumed. `TrafficSpawner` drops its parked cars onto
their own suspension and writes down where each chassis came to rest; a car that is being
moved rather than simulated is driven at that height, and a rival turns up in a chassis
the lot has already measured. The lot is flat where cars drive, which is the assumption
that lets the height be a number rather than a ground query — a lot with a ramp in it
would need one.

### Where the lanes are

`LotGeometry` works the lanes out from the bays rather than having them authored onto
them; twenty inspector overrides that have to be right and that nothing checks is the
alternative. A bay's way out is the side its own middle looks at when it looks at the
middle of the lot, the lanes run `LANE_OFFSET` out from the paint, and the gate — where
rivals come in and leaving cars stop mattering — is past the run-up to the last bay in the
row, at the end of the lot the player's own respawn marker is at. Past the *run-up* rather
than past the bay, because the first version put the gate inside the run-up to the end bay:
a rival came in already past the point it was meant to turn, could not reach a space a
car's length behind it, and drove a slow circle in the aisle before coming back for it.
`Tools/test_lot_events.tscn` checks all of it against the real lot, because it is derived
rather than drawn.

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
| `ParkingRules` | round length, the decrement per level and its floor, cars per level, the grade boundaries, the pass mark, and the odds of everything the lot does per level |
| `LotGeometry` | how far out the lanes run, where a car starts turning, where the gate is |
| `NpcDriver` | how fast a car with nobody in it drives, how tightly it turns, how much room it leaves the player |
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
godot --headless Tools/test_lot_events.tscn                 a car leaving, a rival arriving, the odds
godot --headless Tools/test_pause_flow.tscn -- round         Escape, pause, resume
godot --headless Tools/test_pause_flow.tscn -- select        Escape with no menu in the way
godot --headless Tools/test_audio_cues.tscn                  the cues and the engine note
```

The last four are scenes rather than `--script` tools for a reason worth remembering: a
script run with `--script` replaces the main loop, so autoloads are never registered and
any script naming `Parkade` or `SfxPlayer` fails to compile. Anything touching the shell,
the round or the audio has to be tested by running a scene.

## Not here yet

- **Pedestrians.** The source's ragdolling NPC is the riskiest part of it and the least
  load-bearing. `ParkingRound.pedestrians_enabled` is the gate, off by default. Its mesh is a
  free Sketchfab download under the **Sketchfab Standard licence** — which is not one of the
  Creative Commons grants the lot and the office building carry: it asks for the author to be
  credited and does not, on its face, grant redistribution of the model file itself. Shipping
  it inside a build is what it is for; committing the raw mesh to a public repository is the
  part to check against the licence text before it comes across, and the licence and the
  credit belong beside it in `ThirdParty/` when it does.
- **An end to the run.** The source escalates forever, and so does this. An arcade cabinet
  probably wants a last level and a run-over screen.
- **A remembered car.** The cabinet reloads from scratch each launch, so it always starts
  back at select. Persisting the choice needs a `user://` config file, which nothing in
  this repo has yet — worth doing once for both games or not at all.
