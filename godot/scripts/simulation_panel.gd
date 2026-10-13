extends CanvasLayer
var bridge: Node
var panel: PanelContainer
var summary: Label
var detail: Label
var pause_button: Button
var save_button: Button
var speeds: Array[Button] = []
var timer := 0.0

func setup(owner_bridge: Node) -> void:
	bridge = owner_bridge
	layer = 5
	panel = PanelContainer.new()
	panel.theme = bridge.city.hud.menu.get_parent().theme
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -255
	panel.offset_right = 255
	panel.offset_top = -175
	panel.offset_bottom = 175
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b1d2b")
	style.border_color = Color("366175")
	style.set_border_width_all(1)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = "CITY TIME & SAVE"
	heading.add_theme_font_size_override("font_size", 23)
	content.add_child(heading)
	summary = Label.new()
	summary.add_theme_font_size_override("font_size", 18)
	content.add_child(summary)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 450
	content.add_child(detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	pause_button = add_button(row, "Pause city", func(): bridge.set_clock(not bridge.world.get("paused", false), float(bridge.world.get("time_scale", 1))))
	for speed in [1, 10, 60]:
		var value: int = speed
		speeds.append(add_button(row, "%d×" % value, func(): bridge.set_clock(bool(bridge.world.get("paused", false)), value)))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	save_button = add_button(actions, "Save now", func(): bridge.save_now())
	add_button(actions, "Retry connection", func(): bridge.retry())
	add_button(actions, "Return", func(): panel.hide(); bridge.player.set_capture(not bridge.player.external_camera_active))
	bridge.changed.connect(refresh)
	bridge.player.capture_changed.connect(func():
		if bridge.player.mouse_active: panel.hide())
	panel.hide()
	refresh()

func add_button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(func(): button.release_focus(); action.call())
	parent.add_child(button)
	return button

func toggle() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		bridge.player.set_capture(false)
	refresh()

func is_open() -> bool:
	return panel != null and panel.visible

func refresh() -> void:
	if bridge == null: return
	var seconds := int(float(bridge.world.get("clock_seconds", 0))) + 8 * 3600
	summary.text = "DAY %03d   /   %02d:%02d:%02d" % [seconds / 86400 + 1, (seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60]
	detail.text = bridge.status + "\nYour city saves automatically. Time stops when the app closes."
	if not bridge.last_error.is_empty(): detail.text = bridge.last_error
	pause_button.text = "Resume city" if bridge.world.get("paused", false) else "Pause city"
	pause_button.disabled = not bridge.connected or not bridge.restored
	save_button.disabled = pause_button.disabled
	for button in speeds: button.disabled = pause_button.disabled

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		panel.hide()

func _process(delta: float) -> void:
	timer += delta
	if timer > 0.25:
		timer = 0
		refresh()
