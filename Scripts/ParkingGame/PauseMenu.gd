class_name PauseMenu
extends CanvasLayer
## Escape, mid-round: stops the clock, shows two buttons, and gets out of the
## way again.
##
## Ported from [code]Menu.cs[/code], keeping its play/resume duality -- the same
## menu is the thing you resume from -- and dropping its Quit button. Quitting
## is not a thing a cabinet does: the web build has no window to close, and the
## way out of a game here is back to the Parkade menu, which is what that button
## became.
##
## [b]Escape.[/b] [Parkade] takes Escape as [i]unhandled[/i] input, and a scene
## gets unhandled input before an autoload does, so consuming it here is all it
## takes to keep Escape from dropping the player out of a round they are in the
## middle of. Escape again closes this menu; Escape on the vehicle select
## screen, where this node does not exist, still leaves the cabinet.
##
## The source's [code]Game._Input[/code] polls
## [code]Input.IsActionPressed("Pause")[/code] inside an event handler, so its
## pause fires on any key held while Escape is down. This asks the event.

## Raised when the player asks to carry on. The game root puts the mouse back
## the way the round wants it.
signal resumed

@onready var _resume_button: Button = $Root/Box/ResumeButton
@onready var _menu_button: Button = $Root/Box/MenuButton

## Whether the round is paused right now.
var paused: bool = false


func _ready() -> void:
	# The menu has to keep running while the tree it paused is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume_button.pressed.connect(resume)
	_menu_button.pressed.connect(Parkade.return_to_menu)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"menu_back"):
		return
	# Consumed either way: an Escape that opens this menu must not also reach
	# the shell and leave the cabinet.
	get_viewport().set_input_as_handled()
	if paused:
		resume()
	else:
		pause()


## Stops the round and shows the menu.
func pause() -> void:
	paused = true
	visible = true
	get_tree().paused = true
	# The round captured the pointer to look around with. A menu you cannot
	# click is not a menu.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_resume_button.grab_focus()


## Hands the round back.
func resume() -> void:
	paused = false
	visible = false
	get_tree().paused = false
	resumed.emit()
