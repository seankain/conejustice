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


## Returns the run to its pre-launch state. Called on run start and on retry,
## so a second run behaves identically to a fresh launch.
func reset_run() -> void:
	run_state = RunState.IDLE
	score = 0
	section_index = -1
