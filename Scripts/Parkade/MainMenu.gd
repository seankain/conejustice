extends Control
## Parkade's front screen: pick a cabinet.
##
## The rows are built from [member Parkade.games] rather than authored in the
## scene, so adding a game is one entry in that list and nothing here changes.
## A game that is not [member ArcadeGame.available] yet still gets a row, greyed
## and unclickable, because a cabinet with a sheet over it reads as "soon" while
## a missing one reads as "never".

@export_group("Colours")
## Only the generated rows are styled here; the title block is authored in the
## scene, where it can be seen while it is edited.
@export var tagline_colour: Color = Color(0.85, 0.85, 0.88)
@export var controls_colour: Color = Color(1, 0.85, 0.35)
@export var pending_colour: Color = Color(0.55, 0.55, 0.60)

@export_group("Text")
## Shown under an unfinished game in place of its controls.
@export var pending_note: String = "COMING SOON"

@onready var _games_box: VBoxContainer = $Root/Games
@onready var _quit_button: Button = $Root/QuitButton


func _ready() -> void:
	# Whatever the last game did with the tree and the cursor, the menu needs
	# them back. Parkade does this on the way out too; doing it here as well
	# covers the launch case, where nothing was running to clean up after.
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var first_button: Button = null
	for game in Parkade.games:
		var button := _add_row(game)
		if first_button == null and game.available:
			first_button = button

	# The web build has no window to close, and quitting it just leaves a dead
	# canvas on the page.
	_quit_button.visible = not OS.has_feature("web")
	_quit_button.pressed.connect(func() -> void: get_tree().quit())

	if first_button != null:
		first_button.grab_focus()


## One cabinet: a button with the game's name, its pitch under it, and either
## its controls or a note that it is not ready. Returns the button so the caller
## can hand it the initial focus.
func _add_row(game: ArcadeGame) -> Button:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var button := Button.new()
	button.text = game.title
	button.custom_minimum_size = Vector2(420, 60)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override(&"font_size", 30)
	button.disabled = not game.available
	button.pressed.connect(_on_game_pressed.bind(game.id))
	row.add_child(button)

	row.add_child(_make_label(
			game.tagline, 18, tagline_colour if game.available else pending_colour))
	row.add_child(_make_label(
			game.controls if game.available else pending_note,
			16,
			controls_colour if game.available else pending_colour))

	_games_box.add_child(row)
	return button


func _make_label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	return label


func _on_game_pressed(id: StringName) -> void:
	Parkade.launch(id)
