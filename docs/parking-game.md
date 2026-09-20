# Parking Game: the round, the grade, and the cars

The second Parkade cabinet. Pick a car, drive it around a lot against a countdown, and put
it between the lines. The round is graded A to F on how square you are, how centred, what
you crossed and what you hit. Park well and the next level gives you less time, more cars
to park between, and more going on between them — spaces opening up as parked cars leave,
rivals driving in to take the one you were going for, and people and geese crossing the
aisle in front of you. Park badly and you run the same level again.

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

Two buttons the prototype has no equivalent of:

- **Boost is the gas pedal on the floor, and nothing else.** It writes full forward
  throttle into the same axis the drive keys write, so everything downstream treats it as
  the throttle it is: it brakes rather than drives a car that is rolling backwards, the
  power fade still tapers it out at `top_speed`, and the engine note still hears it as
  load. On a keyboard, where that axis is already 0 or 1, holding boost is the same as
  holding `W` — measured at 27 N of 2200 apart, which is the two samples being a few
  frames apart rather than boost being worth anything. What it is for is the throttle that
  is not a key: an analog trigger, a stick or a touch button, where the axis sits below
  1.0 and "all the way down" is otherwise not something the player can ask for.
- **The handbrake outranks everything the throttle is doing**, boost included. It cuts the
  engine and puts `handbrake_strength` on every wheel — twice the brake the car gets for
  pressing against itself, and no more than that, because four times it reads less like
  braking than like the car hitting something. Steering is set before it is read, so the
  wheels still turn while it is held.

`Tools/test_drive_chassis.gd` measures what a chassis is worth:

```
godot --headless --script Tools/test_drive_chassis.gd
godot --headless --script Tools/test_drive_chassis.gd -- res://Scenes/Vehicles/MinivanDrivable.tscn
```

| | SUV | Minivan | Sedan |
|---|---|---|---|
| Mass | 1400 kg | 1850 kg | 1250 kg |
| 0–10 m/s | 3.6 s | 6.0 s | 2.4 s |
| Stopping | 12.7 m/s in 1.7 s | 11.2 m/s in 1.9 s | 13.8 m/s in 1.7 s |
| Stopping on the handbrake | 11.0 m/s in 0.78 s | 9.0 m/s in 0.83 s | 12.2 m/s in 0.78 s |
| Lean at full lock | 2.2° | 1.2° | 2.5° |

## The lot

`Lot.tscn` is the source's level without the prototype's furniture: the parking lot model,
the office building, road and grass bodies, a respawn marker, twenty bays, the navigation
region its pedestrians walk on, the marker they walk to, a kill plane and an offroad zone.

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
which makes its level twenty a level one with less time on it. `LotEvents` rolls three dice
every `ParkingRules.RANDOM_EVENT_SECONDS`, and what they can do gets likelier every level:

- **A car leaves.** One of the parked cars backs out of its bay, drives down the aisle and
  goes. It opens a space that was not there when the round started — and puts a moving car
  across the aisle while you are lining up somewhere else.
- **A rival arrives.** A car comes in off the road looking for a space and takes one. Near
  the top of the lot, where there were two spaces left, it takes one of yours.
- **Something living sets off across it.** Somebody gets out of a parked car and walks to
  the building, or a gaggle of geese crosses the aisle — see
  [What walks in front of you](#what-walks-in-front-of-you). This is the one roll that
  only adds to what is already there: the lot starts every round with people on it.

|  | Level 1 | Level 3 | Level 5 | Ceiling |
|---|---|---|---|---|
| a parked car leaves | 0.20 | 0.36 | 0.52 | 0.75 |
| a rival arrives | 0.15 | 0.35 | 0.55 | 0.85 |
| …and goes for the space nearest the player | 0.25 | 0.55 | 0.85 | 0.90 |
| something living sets off across the lot | 0.30 | 0.50 | 0.70 | 0.80 |
| cars under their own power at once | 1 | 2 | 3 | 3 |
| living things walking at the start of a round | 2 | 4 | 6 | 6 |

A round is five or six rolls long, so level one is about one car leaving per round and a
rival every second round; from level eight it is both, most rolls, up to three at a time.
`ParkingRound.lot_events_enabled` turns the whole thing off and gives the source's lot
back — which is what the round-flow test wants while it measures a park.

**A rival goes for the space nearest the player** as often as the third row says, and any
free space the rest of the time. Uniformly random is the honest choice and the boring one:
in a lot with eighteen free bays a rival takes one the player was never going to reach,
and the event goes unnoticed. That fraction is the difference between a competitor and
scenery, so it climbs with the rest.

### What walks in front of you

**Every level has people in it**, which is the one thing here that is not a die roll. The
lot is populated the moment a round starts — `WALKERS_AT_LEVEL_ONE` of them, one more per
level to a ceiling of six — and the roll above only decides whether *another* one sets off
while you are already parking. A lot with nobody in it is a lot you can take at speed, and
the whole point of a pedestrian is that you cannot.

Two kinds, and they differ in where they go rather than only in what they look like:

- **Somebody parked.** A person gets out of a car and walks to the building entrance,
  which means crossing at least one driving lane to get there.
- **A gaggle of geese.** Two to four of them cross the aisle together, from clear of one
  row's paint to clear of the other's — so the line they walk has both driving lanes on it
  and neither row's paint. They have nowhere to be and are in the way regardless.

Hitting one costs a **full grade**, the same as hitting a car, and the score card counts
them on their own row: `PERSON` and `WILDLIFE` are what `RoundData.collisions_of` adds up
for **LIVING THINGS**. Hitting the same body twice costs once — a body on the tarmac
leaves the `obstacles` group as it goes down, so carrying one along on your bumper is
free. It stays where it fell until the round ends.

**Where a crossing runs is read off the lot, not authored onto it**, the same way the
lanes are: `LotGeometry.clearance_point` is just clear of a bay's paint,
`LotGeometry.across_point` is twice the lane offset out, and a crossing between the two
spans the aisle. A second lot costs no authoring for this beyond its bays and a
`building_entrance` marker.

Two things it does not do. It **does not path around parked cars** — the navigation mesh
is baked from the empty lot, so a path can run through a bay a car is sitting in. A walker
that stops making progress for `Pedestrian.STUCK_SECONDS` leaves rather than standing
against a bumper for the rest of the round; the real fix is a `NavigationObstacle3D` per
parked car. And the agents' **avoidance is off**, so a gaggle going the same way jostles.
On a goose that reads as a goose.

`ParkingRound.pedestrians_enabled` empties the lot of them and keeps it empty, the same
way `lot_events_enabled` stills the cars.

### The placeholder bodies

**The meshes are a capsule and a box, and that is deliberate.** The source's pedestrian is
a rigged human under the **Sketchfab Standard licence** — not one of the Creative Commons
grants the lot and the office building carry — so it cannot be committed here until that
is cleared (see [Not here yet](#not-here-yet)). What is here is the behaviour with a
primitive standing in for the model, so landing the real one is a mesh swap rather than a
design.

A `Pedestrian` is one `RigidBody3D`. Walking, its two horizontal angular axes are locked
and its velocity is written every physics step from a `NavigationAgent3D` path; struck,
those locks come off and it is left to the solver with an impulse in it above its middle.
**A single capsule going over end for end is the placeholder for a skeleton going limp,
and it is deliberately the same switch** — the real version replaces what `knock_down`
turns on, not when it is called. A real model brings its own `AnimationTree` for the walk
and a `PhysicalBoneSimulator3D` for the fall; everything around it stays.

It is dynamic the whole time, rather than frozen kinematic the way `NpcDriver`'s cars are.
A frozen body has infinite mass, so a car hitting one would stop dead against it for the
frame before anything could react — exactly wrong here. Seventy kilos should barely slow a
car and should leave the lot at speed.

Adding a species is a scene plus an entry in `Assets/Pedestrians/Catalog.tres`, the same
way adding a car is a `DrivableVehicle`. No code knows how many there are.

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

## The camera

The camera is behind the car and is **not attached to it**, which is the whole of this
section. A camera parented to a `VehicleBody3D` inherits everything the suspension does:
the body pitches under braking, rolls into every turn, shakes over the paint and kicks
when a wheel finds a kerb — and a view bolted to it does all of that about a pivot a metre
and a half in front of the player's face. That is how you make somebody put the tab down.

`ChaseCamera` is a `SpringArm3D` that lives in the lot, beside the car rather than under
it, and follows it. It takes two things from the car and nothing else:

- **Where it is.** The rig eases toward a point above the car's origin — quickly across
  the ground (`follow_response`), slowly upwards (`height_response`). A slow vertical
  follow is a low-pass filter: suspension bounce is small and fast and does not survive
  it, while a kerb or a ramp is a height the car keeps and comes through. Measured: a car
  bounced half a metre at 4 Hz moves the camera 0.05 m.
- **Which way it is pointing**, flattened to a heading and eased at `yaw_response`.
  Flattening is where the pitch and the roll go — the nose of a car leaning into a turn
  flattens to the same heading as the nose of one sitting level. The rig's basis is then
  built from that heading and a pitch, and there is no third term in it, so the camera
  cannot roll however the car lands.

Speed is allowed to do one thing, and it is framing rather than rotation: the camera eases
back `distance_gain` metres and the lens widens by `fov_gain` degrees as the car
approaches `speed_reference`, so 14 m/s looks different from 4.

It is still a spring arm, so a wall between the camera and the car pulls the camera in
rather than letting it clip through. Being a sibling of the car rather than its child is
what makes that worth saying: the arm is cast from a pivot level with the car's own roof,
so the car is excluded from the cast by hand — otherwise the first thing the arm finds,
the moment you look down, is the car it is looking at.

**Mouse look holds still.** While you are looking around, the view keeps the heading you
left it at and the car turns underneath it; a second of stillness (`duration_to_snap`)
eases it back behind the car over `recentre_duration`, the short way round rather than
unwinding whatever you wound up. The camera is put back behind the car with no ease at all
whenever the car is *moved* rather than driven — a respawn, the kill plane, the start of a
round — and a car that gets more than `leash` metres from the rig is caught the same way
rather than chased across the lot.

The framing is authored in `Scenes/ParkingGame/ChaseCamera.tscn`, not in code: the rig's
`position.y` is how far above the car it sits, its `rotation.x` how far it looks down,
`spring_length` how far back, and the `Camera3D`'s `fov` the lens it sits behind. The
exports on `ChaseCamera` are how it *moves*.

### The lot is drawn between ticks

The lot is simulated 60 times a second and drawn as often as the machine will draw it,
which in a browser is whatever the tab is given. Those are different clocks, and a camera
that follows the car has to be told which one it is on — otherwise `global_position` is a
staircase that holds still for two or three drawn frames and then jumps a tick's travel
all at once, and a rig easing towards it every drawn frame draws the difference: the car
creeps forward in frame while it is standing still, snaps back when it moves, sixty times
a second. That reads as the car vibrating and blurring against a lot that is perfectly
steady. While the camera was parented to the car this was invisible, because the camera
was on the same staircase.

So `ParkingGame.use_physics_interpolation()` turns physics interpolation on before the lot
is built — the cars are drawn along the line between the last two ticks — and the rig asks
`get_global_transform_interpolated()` where the car *is being drawn* rather than where it
is. The rig itself is `PHYSICS_INTERPOLATION_MODE_OFF`, because it is drawn from
arithmetic it does at render time and interpolating that would hold the view a tick behind
its own mouse.

Measured with `Tools/test_camera_smoothness.tscn`, which samples the car's position on
screen every drawn frame at 60, 90 and 144 fps and takes the second difference — zero for
anything sweeping across the screen at a steady rate, the size of the step for a staircase:

| | 90 fps | 144 fps | in a turn |
|---|---|---|---|
| following `global_position` | 2.08 px | 2.10 px | 2.28 px |
| following what is drawn | 0.03 px | 0.02 px | 0.03 px |

At 60 fps there is nothing to see either way: the two clocks are the same one, so no frame
ever falls between two ticks. That is why this shipped.

**Anything that *puts* a body somewhere has to say so**, with
`reset_physics_interpolation()` — otherwise it is drawn for one frame somewhere on the way
there, which for a respawn across the lot is metres. `PlayerCar.respawn()`,
`TrafficSpawner`, `PedestrianSpawner` and `LotEvents` each do. A body an `NpcDriver` moves
needs nothing: it is driven, a tick at a time, which is exactly what interpolation is for.

It is turned on per cabinet rather than in `project.godot`: Cone Justice moves its camera
along a rail with a tween and has no simulation under it. `Parkade._reset_tree()` puts the
project's own setting back on the way out, the way it puts the pointer and the pause state
back.

## Controls

| | |
|---|---|
| `W` `A` `S` `D` | drive. Pushing against the way the car is moving brakes rather than reversing. |
| `Shift` | boost: the gas pedal all the way down, whatever the drive keys are doing. It adds no power of its own, so on a keyboard it is a second way to hold `W`. |
| `Space` | handbrake. Cuts the engine and locks every wheel — the hardest the car stops — and beats the throttle while it is held. You can still steer on it. |
| Mouse | look around. The view holds the heading you leave it at while the car turns under it, and eases back behind the car after a second of stillness. |
| `R` | put the car back on the marker — which restarts the attempt |
| `Escape` | pause, and again to resume. On the select screen it leaves for the Parkade menu. |

## Tuning

| Where | What |
|---|---|
| `ParkingRules` | round length, the decrement per level and its floor, cars per level, the grade boundaries, the pass mark, the odds of everything the lot does per level, and how many living things are on it |
| `LotGeometry` | how far out the lanes run, where a car starts turning, where the gate is |
| `NpcDriver` | how fast a car with nobody in it drives, how tightly it turns, how much room it leaves the player |
| `DrivableVehicle` resources | mass, engine power, steering lock, top speed, per car |
| `Pedestrian` | walk speed, how hard a car throws one, how long one keeps trying before it gives up |
| `PedestrianCatalog` resource | which scenes a person and a goose are |
| `ScoredParkingSpace` | settle speed and settle time |
| `PlayerCar` | brake strength, handbrake strength, idle brake, steering rate |
| `ChaseCamera` | how hard the camera follows the car and its heading, how much of the car's bounce reaches it, the speed framing, and mouse look |
| `ParkingHUD` | banner duration, the low-clock warning, and `show_debug` for the live measurements |

## Tests

```
godot --headless --script Tools/test_grade_table.gd          the grade table
godot --headless --script Tools/test_bay_alignment.gd        the bays against the lot's paint
godot --headless --script Tools/test_drive_chassis.gd        a chassis on a flat plane
godot --headless --script Tools/test_chase_camera.gd         what the camera takes from the car, and what it does not
godot --headless Tools/test_camera_smoothness.tscn           how steady the car is on screen, on every drawn frame
godot --headless Tools/test_round_flow.tscn                  a whole round in the lot
godot --headless Tools/test_lot_events.tscn                 a car leaving, a rival arriving, the odds
godot --headless Tools/test_pedestrians.tscn                 a crossing, a knock-down, and what it costs
godot --headless Tools/test_pause_flow.tscn -- round         Escape, pause, resume
godot --headless Tools/test_pause_flow.tscn -- select        Escape with no menu in the way
godot --headless Tools/test_audio_cues.tscn                  the cues and the engine note
```

The last five are scenes rather than `--script` tools for a reason worth remembering: a
script run with `--script` replaces the main loop, so autoloads are never registered and
any script naming `Parkade` or `SfxPlayer` fails to compile. Anything touching the shell,
the round or the audio has to be tested by running a scene.

## Not here yet

- **The real pedestrian models.** The lot has people and geese in it, but they are a
  capsule and a box — see [The placeholder bodies](#the-placeholder-bodies). The source's
  mesh is a free Sketchfab download under the **Sketchfab Standard licence**, which is not
  one of the Creative Commons grants the lot and the office building carry: it asks for the
  author to be credited and does not, on its face, grant redistribution of the model file
  itself. Shipping it inside a build is what it is for; committing the raw mesh to a public
  repository is the part to check against the licence text before it comes across, and the
  licence and the credit belong beside it in `ThirdParty/` when it does. What comes with a
  real model is an `AnimationTree` for the walk, a `PhysicalBoneSimulator3D` for the fall,
  and a per-parked-car `NavigationObstacle3D` so a path stops running through a bay that is
  full.
- **An end to the run.** The source escalates forever, and so does this. An arcade cabinet
  probably wants a last level and a run-over screen.
- **A remembered car.** The cabinet reloads from scratch each launch, so it always starts
  back at select. Persisting the choice needs a `user://` config file, which nothing in
  this repo has yet — worth doing once for both games or not at all.
