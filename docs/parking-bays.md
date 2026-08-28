# Parking bays: innocent cars and randomised streets

Every car on the street used to be a target. Now most of them are parked correctly, the
badly parked ones are picked fresh each run, and coning the wrong car costs points. This
is how that works and where to tune it.

## The idea

A `ParkingSpace` is a painted bay in the road. It owns two things that have to agree:

- **the generator** — the pose a car is placed at, either inside the bay's tolerance or
  clear of it;
- **the rule** — `is_legally_parked(transform)`, which measures a pose and says whether
  the car in it is parked properly.

`ParkingLot` places a car and then *measures* it, rather than labelling it and assuming.
`TargetCar.is_violator` comes from that measurement, so the car the player judges by eye
and the car the game scores are always the same car. If a tuning change ever made the two
disagree, the lot says so in the Output panel instead of scoring a car the player had no
way to read.

## What makes a car guilty

Three faults, measured in the bay's own frame:

| Fault | What it looks like | Bounded by |
|---|---|---|
| Sticking out | nose or tail hanging out of the bay | nothing — there is never a car in front |
| Sideways | straddling a painted line | the room beside the bay |
| Crooked | slewed across the bay | the room beside the bay |

A violator gets one of these, plus a 35% chance of also sticking out. Sideways and crooked
are never combined: both eat the same room beside the bay, and a car doing both at once
ends up standing inside its neighbour.

Backing into a bay is not an offence. `yaw_error_degrees` folds at 90 degrees, so a car
turned end for end reads as square.

### Why the room matters

A 4.5 m car in a 2.4 m bay runs out of angle fast, and the row in `level.tscn` is tight:
the bays sit at a 2.26–2.66 m pitch, so a 1.8 m car has only about 0.23 m of gap each side
before it is inside the car next to it — and half of that once the neighbour's own drift is
allowed for. `ParkingLot` measures that room per bay, taking **both** cars' widths out of
the gap, treating a bay it has not rolled yet as occupied, and halving what is left because
that neighbour may be drifting this way too. It hands the result to the bay, which turns it
into an angle. A bay with a car hard against both sides can only offend by sticking out.

Those widths come from each vehicle's `VehicleProfile`, not from one number for the whole
street — see [vehicle-variety.md](vehicle-variety.md). That is the reason the lot draws
every vehicle in a section *before* it places any of them: the room beside a bay depends on
how wide its neighbour is, and a neighbour that has not been drawn yet has no width to ask
about.

The upshot: violations stay unmistakable and no two cars ever share the same patch of road.

## Rolling a street

`SectionManager` rolls the whole street once on load (so the title screen has something to
look at) and again at the start of every run. Per stop:

1. Bays pinned to a role by hand are taken first.
2. The violator count is rolled between the stop's `min_violators` and `max_violators`,
   capped so `min_innocents` can still be met — but never below `min_violators`, because a
   section with nothing illegally parked cannot be cleared at all, while one with nothing
   correctly parked is merely a duller section.
3. `min_innocents` bays are held back.
4. Whatever is left is occupied on a roll against each bay's `occupancy_chance`.
5. Every occupied bay draws a vehicle from `ParkingLot.vehicles`, weighted, filtered to
   what fits that bay, and preferring not to repeat the car parked beside it.

Set `ParkingLot.random_seed` to anything non-zero to replay one exact street while tuning.

## Scoring

| Event | Award |
|---|---|
| Cone settles on a violator | `points_cone_body` (or `points_cone_roof`), times the combo |
| Violator fully coned | `points_car_coned` |
| Cone settles on an innocent car | `-penalty_innocent_cone`, and the combo breaks |
| Innocent car fully coned | `-penalty_innocent_car` on top |

The score floors at zero, so a penalty near the bottom takes less than its face value.
`ScoreManager` remembers what was actually applied, not what was nominally worth, so a
cone knocked back off a car hands back exactly what it took.

Only violator landings count towards accuracy on the run-over screen. Innocents hit are
reported separately.

## What the HUD gives away

Which cars are guilty is the whole puzzle, so the brackets do not say. Every car at a stop
gets the same neutral bracket, and it only takes a colour once a cone has settled on that
car — green for a violator, red for an innocent. The section label carries how *many* cars
in the area are illegally parked, because a player who cannot count them cannot tell a
finished area from a stuck one.

`TargetMarkers.reveal_violators` colours the brackets from the moment a section arms. It is
for tuning bay tolerances, where seeing what the game thinks is the point. Leave it off.

## Authoring bays

`ParkingSpace` extends `Marker3D` and draws itself: the painted lines show up in game, and
in the editor it also outlines the bay, the legal tolerance band a car's centre may sit in,
and an arrow for the direction a nosed-in car faces.

The node sits where a parked car's **origin** sits — a few centimetres above the road, not
on it — so a bay dragged around the editor never needs its cars re-levelled afterwards.
`marking_height` is the offset back down to the tarmac.

Point a `CameraStop` at its bays through `parking_spaces`, and set `min_violators`,
`max_violators` and `min_innocents` on the same stop. `target_cars` still works for a car
authored straight into the level; every one of those is a target, which is what a
hand-placed car in this game has always meant.
