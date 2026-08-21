class_name ConeMagazine
extends VBoxContainer
## The Time Crisis magazine, holding cones instead of bullets.
##
## The row is built from the capacity the thrower reports, never from icons
## placed in the scene. Hardcoding six slots would silently desync the display
## from the real magazine the moment mag_size changed.

@onready var _row: HBoxContainer = $Row
@onready var _prompt: Label = $ReloadPrompt

var _icons: Array[ConeIcon] = []
var _capacity: int = 0
var _remaining: int = 0
var _reloading: bool = false

var _reload_tween: Tween
var _pulse_tween: Tween


func _ready() -> void:
	_prompt.visible = false
	_prompt.text = "RELOAD  %s" % _reload_hint()
	EventBus.magazine_changed.connect(_on_magazine_changed)
	EventBus.reload_started.connect(_on_reload_started)
	EventBus.reload_finished.connect(_on_reload_finished)


func _on_magazine_changed(remaining: int, capacity: int) -> void:
	if capacity != _capacity:
		_build_row(capacity)
	_remaining = remaining
	# A reload owns the icons while it runs; letting this repaint them would
	# snap the row full the instant the magazine value changed.
	if not _reloading:
		_apply_state()


func _on_reload_started(duration: float) -> void:
	_reloading = true
	_stop_pulse()
	_prompt.visible = false
	_kill_reload_tween()
	if _icons.is_empty():
		return

	for icon in _icons:
		icon.set_loaded(false, false)

	# Refill one slot at a time across the real reload duration, so the row
	# reads as a reload rather than as a value that jumped.
	_reload_tween = create_tween()
	var step := duration / float(_icons.size())
	for icon in _icons:
		_reload_tween.tween_interval(step)
		_reload_tween.tween_callback(icon.set_loaded.bind(true))


func _on_reload_finished() -> void:
	_reloading = false
	_kill_reload_tween()
	_apply_state()


func _build_row(capacity: int) -> void:
	_kill_reload_tween()
	for icon in _icons:
		icon.queue_free()
	_icons.clear()

	_capacity = maxi(capacity, 0)
	for _i in _capacity:
		var icon := ConeIcon.new()
		_row.add_child(icon)
		_icons.append(icon)


func _apply_state() -> void:
	for i in _icons.size():
		_icons[i].set_loaded(i < _remaining)
	if _remaining <= 0 and _capacity > 0:
		_prompt.visible = true
		_start_pulse()
	else:
		_prompt.visible = false
		_stop_pulse()


func _start_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "modulate:a", 0.45, 0.35)
	_pulse_tween.tween_property(self, "modulate:a", 1.0, 0.35)


func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	modulate.a = 1.0


func _kill_reload_tween() -> void:
	if _reload_tween != null and _reload_tween.is_valid():
		_reload_tween.kill()
	_reload_tween = null


## Names the button actually bound to the reload action, so the prompt cannot
## drift from the input map.
func _reload_hint() -> String:
	for event in InputMap.action_get_events(&"reload"):
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			if button.button_index == MOUSE_BUTTON_RIGHT:
				return "[RIGHT CLICK]"
			return "[MOUSE %d]" % button.button_index
		if event is InputEventKey:
			return "[%s]" % (event as InputEventKey).as_text_physical_keycode()
	return ""
