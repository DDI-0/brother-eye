extends CanvasLayer
var player: CharacterBody3D
var mode_label: Label
var stats: Label
var hint: Label
var title: Label
var subtitle: Label
var menu: PanelContainer
var controls: PanelContainer
var binding_button: Button
var controls_text: Label
var timer := 0.0
var simulation: Node
var clock_label: Label

func setup(explorer: CharacterBody3D) -> void:
	player = explorer
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var theme := Theme.new()
	theme.default_font_size = 15
	theme.set_color("font_color","Label",Color("b9cbd7"))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.018,0.04,0.065,0.94)
	panel_style.border_color = Color("294657")
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(22)
	theme.set_stylebox("panel","PanelContainer",panel_style)
	for state in ["normal","hover","pressed","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("163749") if state in ["hover","focus"] else Color("0b202f")
		style.border_color = Color("49adca") if state in ["hover","focus"] else Color("305166")
		style.set_border_width_all(1)
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		theme.set_stylebox(state,"Button",style)
	theme.set_color("font_color","Button",Color("caedf6"))
	ui.theme = theme
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 32
	top.offset_right = -32
	top.offset_top = 26
	ui.add_child(top)
	var brand := Label.new()
	brand.text = "◉   N E O N   P R O V I D E N C E"
	brand.add_theme_font_size_override("font_size",21)
	brand.add_theme_color_override("font_color",Color("d7f3fc"))
	top.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	mode_label = Label.new()
	top.add_child(mode_label)
	var rule := ColorRect.new()
	rule.color = Color(0.2,0.6,0.75,0.45)
	rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	rule.offset_left = 32
	rule.offset_right = -32
	rule.offset_top = 66
	rule.offset_bottom = 67
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(rule)
	var chapter := Label.new()
	chapter.text = "SECTOR 07     /     CIVIC DISTRICT"
	chapter.position = Vector2(34,81)
	chapter.add_theme_font_size_override("font_size",12)
	chapter.add_theme_color_override("font_color",Color("75b8cb"))
	ui.add_child(chapter)
	menu = PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	menu.offset_left = 32
	menu.offset_top = -313
	menu.offset_right = 462
	menu.offset_bottom = -65
	ui.add_child(menu)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	menu.add_child(content)
	title = Label.new()
	title.text = "Beneath the watchful sky."
	title.add_theme_font_size_override("font_size",25)
	title.add_theme_color_override("font_color",Color("e1f5fb"))
	content.add_child(title)
	subtitle = Label.new()
	subtitle.text = "Explore the boulevard, ascend the skywalk,\nand approach the central authority."
	subtitle.add_theme_font_size_override("font_size",14)
	content.add_child(subtitle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	content.add_child(row)
	button(row,"Enter streets",func(): player.enter_ground())
	button(row,"Free fly",func():
		if not player.observing: player.toggle_mode()
		player.set_capture(true))
	button(row,"Controls",func():
		player.controls_open = true
		refresh())
	var locations := HBoxContainer.new()
	locations.add_theme_constant_override("separation",8)
	content.add_child(locations)
	for item in [["1  Skyline",0],["2  Plaza",1],["3  Skywalk",2]]:
		var index: int = item[1]
		button(locations,item[0],func(): player.set_view(index))
	controls = PanelContainer.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	controls.offset_left = -255
	controls.offset_right = 255
	controls.offset_top = -300
	controls.offset_bottom = 300
	ui.add_child(controls)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation",16)
	controls.add_child(cv)
	var heading := Label.new()
	heading.text = "EXPLORATION CONTROLS"
	heading.add_theme_font_size_override("font_size",22)
	cv.add_child(heading)
	controls_text = Label.new()
	cv.add_child(controls_text)
	binding_button = button(cv,"",func():
		player.binding_pending = true
		binding_button.text = "Press a new key combination…  Esc cancels"
		binding_button.release_focus())
	button(cv,"Restore default mode shortcut",func(): player.bind_action("toggle_mode","Ctrl+Shift+B"))
	button(cv,"Return to district",func():
		player.controls_open = false
		player.binding_pending = false
		player.set_capture(true))
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 34
	hint.offset_top = -39
	hint.offset_bottom = -16
	hint.add_theme_font_size_override("font_size",12)
	ui.add_child(hint)
	stats = Label.new()
	stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	stats.offset_left = -350
	stats.offset_right = -32
	stats.offset_top = -61
	stats.offset_bottom = -17
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats.add_theme_font_size_override("font_size",12)
	ui.add_child(stats)
	player.mode_changed.connect(refresh)
	player.capture_changed.connect(refresh)
	refresh()

func button(parent: Node, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		b.release_focus()
		action.call())
	parent.add_child(b)
	return b

func refresh() -> void:
	mode_label.text = "OBSERVER   /   FREE FLIGHT" if player.observing else "EXPLORER   /   STREET LEVEL"
	menu.visible = not player.mouse_active and not player.controls_open
	controls.visible = player.controls_open
	controls_text.text = "W A S D     Move\nMouse        Look around\nShift            Move faster\nSpace          Jump on foot\nE / Q           Ascend / descend in free flight\nScroll           Adjust flight speed\n1 / 2 / 3      Skyline / plaza / skywalk\nF1                Controls       •       F11  Fullscreen\nEsc               Release mouse and show menu\n\nGround position is preserved when switching modes."
	if simulation != null and simulation.city.population != null:
		controls_text.text += "\nF2 City time / save    F3 Follow civilian\nF4 Person details    F5 Neon Providence inspection\nF6 City evaluation    F7 Control room\n[ / ] Previous / next person\nFollow: WASD / E Q move camera, Shift faster\nClick-drag / two-finger scroll orbit, R reset view"
	binding_button.text = "Mode switch: " + player.bindings.get("toggle_mode","") + "   ·   Change"
	hint.text = ("WASD  MOVE     SHIFT  FASTER     %s  SWITCH MODE     ESC  MENU" % player.bindings.get("toggle_mode","")) if player.mouse_active else "CLICK THE CITY TO LOOK AROUND     /     F1  CONTROLS"

func _process(delta: float) -> void:
	if player == null: return
	timer += delta
	if timer < 0.4: return
	timer = 0
	var pos: Vector3 = player.observer_camera.position if player.observing else player.position
	if simulation != null:
		clock_label.text = simulation.clock_text()
	var population_active: bool = simulation != null and simulation.city.population != null
	var count: int = simulation.world.get("citizens",[]).size() if population_active else 0
	stats.text = ("STAGE 4D  /  NEON PROVIDENCE CONTROL" if population_active else ("STAGE 02  /  PERSISTENT CITY" if simulation != null else "STAGE 01B  /  CITY COMPOSITION")) + "\n%d FPS    ·    ALT %03d M    ·    %d RESIDENTS" % [Engine.get_frames_per_second(),roundi(pos.y),count]

func attach_simulation(bridge: Node) -> void:
	simulation = bridge
	var ui := menu.get_parent()
	clock_label = Label.new()
	clock_label.position = Vector2(34, 105)
	clock_label.add_theme_font_size_override("font_size", 12)
	clock_label.add_theme_color_override("font_outline_color", Color("071525"))
	clock_label.add_theme_constant_override("outline_size", 4)
	clock_label.modulate = Color("90c7ce")
	ui.add_child(clock_label)
	menu.offset_top = -535
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	menu.get_child(0).add_child(actions)
	button(actions, "City time  /  F2", func(): simulation.panel.toggle())
	button(actions, "Save & Quit", func(): simulation.request_quit())
	button(menu.get_child(0),"Inspect residents  /  F5",func():
		if simulation.city.inspector!=null:simulation.city.inspector.open())
	button(menu.get_child(0),"City evaluation  /  F6",func():
		if simulation.city.inspector!=null:simulation.city.inspector.open_evaluation())
	button(menu.get_child(0),"Control room  /  F7",func():
		if simulation.city.inspector!=null:simulation.city.inspector.open_control_room())
