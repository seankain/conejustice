extends Node
## Run-wide state, readable from anywhere.
##
## Deliberately dumb: this holds values, it does not decide anything. Gameplay
## systems (SectionManager, ScoreManager, SectionTimer) own the rules, write
## their results here, and announce the change on [EventBus]. Nothing should
## ever need to connect to a signal on this node.

enum RunState {
	IDLE, ## Title screen. Nothing is running.
	TRAVELLING, ## Camera is tweening between stops. Throwing and the timer are locked.
	ENGAGED, ## Parked at a stop, timer running, the player can throw.
	SECTION_CLEAR, ## Every car at this stop is coned. Holding before departure.
	TIMEOUT, ## The clock hit zero.
	RUN_OVER, ## The run is finished, won or lost.
}

## Where the run currently is. Gameplay code gates on this rather than on its
## own booleans, so there is exactly one answer to "can the player throw?".
var run_state: RunState = RunState.IDLE

## Total score for the run so far. Written by ScoreManager only.
var score: int = 0

## Index of the camera stop being played, or -1 before the first one.
var section_index: int = -1

## Run tallies, written by RunStats and read by the run-over screen.
var cones_thrown: int = 0
var cones_landed: int = 0
var cars_coned: int = 0
## Correctly parked cars the player buried anyway. The run-over screen reports it
## because a high score built on top of it is not the same run.
var innocents_coned: int = 0


## Returns the run to its pre-launch state. Called on run start and on retry,
## so a second run behaves identically to a fresh launch.
func reset_run() -> void:
	run_state = RunState.IDLE
	score = 0
	section_index = -1
	cones_thrown = 0
	cones_landed = 0
	cars_coned = 0
	innocents_coned = 0


## Cones landed on illegally parked cars over cones thrown, 0.0 before the first
## throw. Cones dropped on the innocent count against this, not for it.
func accuracy() -> float:
	if cones_thrown <= 0:
		return 0.0
	return float(cones_landed) / float(cones_thrown)
