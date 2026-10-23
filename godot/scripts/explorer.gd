extends CharacterBody3D

signal mode_changed
signal capture_changed
const WALK_SPEED := 5.2
const RUN_SPEED := 10.0
const SENSITIVITY := 0.0022
var ground_camera: Camera3D
var observer_camera: Camera3D
var observing := true
var mouse_active := false
var controls_open := false
var binding_pending := false
var flight_speed := 28.0
var bindings: Dictionary = {}
var paused_input := false
var external_camera_active := false

func _ready() -> void:
	load_controls()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(48)
	ground_camera = Camera3D.new()
	ground_camera.position = Vector3(0,1.7,0)
	ground_camera.fov = 74
	ground_camera.far = 800
	add_child(ground_camera)
	observer_camera = Camera3D.new()
	observer_camera.name = "ObserverCamera"
	observer_camera.fov = 65
	observer_camera.far = 1800
	get_parent().add_child(observer_camera)
	position = Vector3(0,0.3,91)
	set_view(0)

func load_controls() -> void:
	var cfg := ConfigFile.new()
	cfg.load("res://config/controls.cfg")
	var saved := ConfigFile.new()
	if saved.load("user://controls.cfg") != OK:
		# Project rename: retain existing key bindings from the former app folder.
		var legacy := OS.get_user_data_dir().get_base_dir().path_join("Brother Eye/controls.cfg")
		saved.load(legacy)
	for action in cfg.get_section_keys("bindings"):
		var value: String = saved.get_value("bindings",action,cfg.get_value("bindings",action))
		bind_action(action,value,false)

func bind_action(action: String, description: String, save := true) -> void:
	var parts := description.split("+")
	var event := InputEventKey.new()
	event.physical_keycode = OS.find_keycode_from_string(parts[parts.size()-1])
	event.ctrl_pressed = "Ctrl" in parts
	event.shift_pressed = "Shift" in parts and parts.size()>1
	event.alt_pressed = "Alt" in parts
	event.meta_pressed = "Meta" in parts
	if not InputMap.has_action(action): InputMap.add_action(action)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action,event)
	bindings[action] = description
	if save:
		var cfg := ConfigFile.new()
		for key in bindings: cfg.set_value("bindings",key,bindings[key])
		cfg.save("user://controls.cfg")
	mode_changed.emit()

func _unhandled_input(event: InputEvent) -> void:
	# Follow camera owns movement/look without changing the saved explorer view.
	if external_camera_active and not (event is InputEventKey and event.keycode == KEY_F11):return
	if binding_pending and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_CTRL,KEY_SHIFT,KEY_ALT,KEY_META]: return
		binding_pending = false
		if event.keycode != KEY_ESCAPE:
			var description := ""
			if event.ctrl_pressed: description += "Ctrl+"
			if event.shift_pressed: description += "Shift+"
			if event.alt_pressed: description += "Alt+"
			if event.meta_pressed: description += "Meta+"
			description += OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
			bind_action("toggle_mode",description)
		mode_changed.emit()
		get_viewport().set_input_as_handled()
		return
	if paused_input:
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			return
		if event is InputEventKey and event.keycode not in [KEY_ESCAPE, KEY_F1, KEY_F11]:
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			set_capture(false)
			controls_open = false
			capture_changed.emit()
		elif event.keycode == KEY_F1:
			controls_open = not controls_open
			set_capture(false)
		elif event.keycode == KEY_F11:
			var mode := DisplayServer.window_get_mode()
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.is_action_pressed("toggle_mode",false,true):
			toggle_mode()
		elif event.keycode in [KEY_1,KEY_2,KEY_3] and not controls_open:
			set_view(event.keycode-KEY_1)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not controls_open:
			set_capture(true)
		elif mouse_active and observing and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: flight_speed = minf(flight_speed*1.2,140)
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: flight_speed = maxf(flight_speed/1.2,3)
	if event is InputEventMouseMotion and mouse_active:
		if observing:
			observer_camera.rotation.y -= event.relative.x*SENSITIVITY
			observer_camera.rotation.x = clampf(observer_camera.rotation.x-event.relative.y*SENSITIVITY,-1.5,1.5)
		else:
			rotation.y -= event.relative.x*SENSITIVITY
			ground_camera.rotation.x = clampf(ground_camera.rotation.x-event.relative.y*SENSITIVITY,-1.45,1.45)

func set_capture(value: bool) -> void:
	mouse_active = value
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE
	capture_changed.emit()

func toggle_mode() -> void:
	observing = not observing
	ground_camera.current = not observing
	observer_camera.current = observing
	mode_changed.emit()

func enter_ground() -> void:
	observing = false
	ground_camera.make_current()
	controls_open = false
	set_capture(true)
	mode_changed.emit()

func set_view(index: int) -> void:
	if index == 0:
		observing = true
		observer_camera.position = Vector3(64,112,185)
		observer_camera.look_at(Vector3(0,59,-62))
		observer_camera.make_current()
	elif index == 1:
		observing = false
		position = Vector3(0,0.3,-17)
		rotation = Vector3.ZERO
		ground_camera.rotation = Vector3(0.25,0,0)
		ground_camera.make_current()
	else:
		observing = false
		position = Vector3(0,12.4,20)
		rotation = Vector3.ZERO
		ground_camera.rotation = Vector3(0.1,0,0)
		ground_camera.make_current()
	velocity = Vector3.ZERO
	mode_changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mouse_active:
		set_capture(false)

func _physics_process(delta: float) -> void:
	if paused_input or external_camera_active: return
	var input := Input.get_vector("left","right","forward","back") if mouse_active and not controls_open else Vector2.ZERO
	if observing:
		if mouse_active and not controls_open:
			var fly_direction := observer_camera.global_basis*Vector3(input.x,0,input.y)
			fly_direction.y += Input.get_action_strength("up")-Input.get_action_strength("down")
			observer_camera.position += fly_direction.normalized()*flight_speed*(3 if Input.is_action_pressed("sprint") else 1)*delta
			observer_camera.position.y = clampf(observer_camera.position.y,2,330)
			observer_camera.position.x = clampf(observer_camera.position.x,-400,400)
			observer_camera.position.z = clampf(observer_camera.position.z,-420,420)
		return
	var direction := transform.basis*Vector3(input.x,0,input.y)
	var speed := RUN_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	velocity.x = direction.x*speed
	velocity.z = direction.z*speed
	if not is_on_floor(): velocity.y -= 22*delta
	elif mouse_active and Input.is_action_just_pressed("jump"): velocity.y = 7.5
	else: velocity.y = 0
	# Small curb assist only: never climb building walls or railings.
	if is_on_floor() and direction.length()>0.01:
		var motion := direction*speed*delta
		if test_move(global_transform,motion):
			var raised := global_transform
			raised.origin.y += 0.26
			if not test_move(raised,motion): position.y += 0.26
	move_and_slide()
	if position.y < -10:
		position = Vector3(0,0.3,91)
		velocity = Vector3.ZERO

func saved_view() -> Dictionary:
	return {"position": [position.x, position.y, position.z], "yaw": rotation.y,
		"ground_pitch": ground_camera.rotation.x, "observing": observing,
		"observer_position": [observer_camera.position.x, observer_camera.position.y, observer_camera.position.z],
		"observer_rotation": [observer_camera.rotation.x, observer_camera.rotation.y, observer_camera.rotation.z],
		"flight_speed": flight_speed}

func restore_view(view: Dictionary) -> void:
	position = Vector3(view.position[0], view.position[1], view.position[2])
	rotation = Vector3(0, view.yaw, 0)
	ground_camera.rotation = Vector3(view.ground_pitch, 0, 0)
	observer_camera.position = Vector3(view.observer_position[0], view.observer_position[1], view.observer_position[2])
	observer_camera.rotation = Vector3(view.observer_rotation[0], view.observer_rotation[1], view.observer_rotation[2])
	observing = view.observing
	flight_speed = view.flight_speed
	velocity = Vector3.ZERO
	if observing: observer_camera.make_current()
	else: ground_camera.make_current()
	mode_changed.emit()
