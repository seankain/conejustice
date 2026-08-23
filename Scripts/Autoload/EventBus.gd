extends Node
## Signal-only bus. The one place systems are allowed to talk to each other.
##
## The full set is declared up front so later phases connect rather than edit.
## Rule of thumb: gameplay emits, the HUD only ever listens. The HUD may read
## a node it was handed for display -- markers need car positions -- but it
## never drives gameplay.

# --- Section lifecycle (SectionManager, SectionTimer) ---

## Something asked for a run to start: the title screen, the retry button, or
## the restart key. UI raises the intent, SectionManager acts on it, so the
## screens never reach into gameplay to drive it themselves.
signal start_run_requested()
## A fresh run has begun. Score, combo and per-run state reset here.
signal run_started()
## The run is finished. [param won] separates clearing the last stop from
## running out of clock.
signal run_over(won: bool)

## The cars for this section, armed and reset, just before it goes live -- every
## car parked at the stop, not only the illegally parked ones, because telling
## those apart is the player's job. [param violators] is how many of them are
## actually in the wrong, which is the one hint the HUD is allowed to give.
## Held as a plain Array so this autoload does not depend on the TargetCar class.
signal section_armed(cars: Array, violators: int)
## Camera has arrived and the section is live. [param time_limit] is in seconds.
signal section_started(index: int, time_limit: float)
## Every target car at this stop is coned.
signal section_cleared(index: int, time_remaining: float)
## The clock hit zero at this stop.
signal section_timeout(index: int)

# --- Camera rail (CameraRig) ---

## Rig has left a stop. [param from_index] is -1 when travelling in from the start.
## [param duration] lets a transition finish exactly on arrival instead of
## guessing at a length that desyncs the moment a stop's travel_time changes.
signal travel_started(from_index: int, to_index: int, duration: float)
## Rig has parked. [param index] is -1 when the rail has run off its last stop.
signal travel_finished(index: int)

# --- Targets (TargetCar) ---

## A cone has settled on a car and been counted. [param on_violator] is false
## when the car was parked correctly, which is a mistake rather than a hit, and
## it travels on the signal so listeners never have to reach into the car to ask.
signal cone_landed(car: Node3D, on_roof: bool, on_violator: bool)
## A counted cone was knocked off again. ScoreManager reverses its award, which
## for an innocent car means handing the penalty back.
signal cone_unlanded(car: Node3D, on_roof: bool, on_violator: bool)
## A thrown cone came to rest without landing on a car. Breaks the combo.
signal cone_missed()
## A cone struck something hard enough to be worth hearing. Rate limited at the
## cone before it ever reaches the bus.
signal cone_impact(position: Vector3, speed: float, on_car: bool)
## An illegally parked car has reached its required cone count. Fires once per
## car per run, and means justice: only violators get here.
signal car_coned(car: Node3D)
## A correctly parked car has reached that same count. Separated from
## [signal car_coned] rather than flagged on it so that nothing scoring, counting
## or celebrating a coned car can forget to check which kind it was.
signal innocent_coned(car: Node3D)

# --- Throwing and the magazine (ConeThrower) ---

## [param cooldown] lets the crosshair show the recovery rather than guessing
## at a duration that would drift the moment the cooldown is retuned.
signal cone_thrown(remaining: int, cooldown: float)
signal magazine_changed(remaining: int, capacity: int)
## [param duration] lets the magazine widget pace its refill against the real
## reload time instead of hardcoding one.
## A throw was refused because the magazine is empty. The click that answers it
## is the game telling the player why nothing happened.
signal throw_refused_empty()
signal reload_started(duration: float)
## Reloading has stopped, either by completing or by being cancelled when a
## section ended under it. Either way, nothing is reloading now.
signal reload_finished()

# --- Score and clock (ScoreManager, SectionTimer) ---

signal score_changed(total: int, delta: int)
## An award worth showing where it was earned. Emitted by ScoreManager, which
## is the only place that knows both the amount and the car it came from.
signal score_popup(amount: int, world_position: Vector3)
## The clear award, broken out so a transition can count it up without knowing
## the scoring rules. Emitted by ScoreManager, which owns them.
signal section_bonus(seconds_left: int, points: int)
signal timer_tick(seconds_remaining: float)
## One-shot as the clock crosses into the danger zone, so the HUD and audio do
## not each re-derive the threshold.
signal timer_warning()
