extends Node
## Signal-only bus. The one place systems are allowed to talk to each other.
##
## The full set is declared up front so later phases connect rather than edit.
## Rule of thumb: gameplay emits, the HUD only ever listens. If a HUD script
## reaches into a gameplay node, that is a bug in the HUD.

# --- Section lifecycle (SectionManager, SectionTimer) ---

## Camera has arrived and the section is live. [param time_limit] is in seconds.
signal section_started(index: int, time_limit: float)
## Every target car at this stop is coned.
signal section_cleared(index: int, time_remaining: float)
## The clock hit zero at this stop.
signal section_timeout(index: int)

# --- Camera rail (CameraRig) ---

## Rig has left a stop. [param from_index] is -1 when travelling in from the start.
signal travel_started(from_index: int, to_index: int)
## Rig has parked. [param index] is -1 when the rail has run off its last stop.
signal travel_finished(index: int)

# --- Targets (TargetCar) ---

## A cone has settled on a car and been counted.
signal cone_landed(car: Node3D, on_roof: bool)
## A counted cone was knocked off again. ScoreManager reverses its award.
signal cone_unlanded(car: Node3D, on_roof: bool)
## A car has reached its required cone count. Fires once per car per run.
signal car_coned(car: Node3D)

# --- Throwing and the magazine (ConeThrower) ---

signal cone_thrown(remaining: int)
signal magazine_changed(remaining: int, capacity: int)
## [param duration] lets the magazine widget pace its refill against the real
## reload time instead of hardcoding one.
signal reload_started(duration: float)
signal reload_finished()

# --- Score and clock (ScoreManager, SectionTimer) ---

## [param delta] is carried so the HUD can float a "+250" at the hit location.
signal score_changed(total: int, delta: int)
signal timer_tick(seconds_remaining: float)
## One-shot as the clock crosses into the danger zone, so the HUD and audio do
## not each re-derive the threshold.
signal timer_warning()
