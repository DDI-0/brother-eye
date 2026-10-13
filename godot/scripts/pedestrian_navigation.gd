extends Node3D
## Bounded navigation proof over the actual district's static collision shapes.
signal rebuilt
const Pedestrian = preload("res://scripts/pedestrian.gd")
var city: Node3D
var region: NavigationRegion3D
var pedestrian: CharacterBody3D
var people: Array[CharacterBody3D]=[]
var ready_for_paths := false
var baking := false
var revision := 0
var bake_ms := 0
var previous_iteration := 0
var status: Label
var barrier: StaticBody3D
var automatic := true
var route_index := 0
var pause_at_stop := 0.0
var follow := false
var follow_camera: Camera3D
var follow_offset := Vector3(3.4,2.5,5)
var looking := false
var points := [Vector3(18,.12,90),Vector3(18,.12,68),Vector3(24,.12,65),Vector3(24,12.08,20),Vector3(34,12,8),Vector3(-24,12.08,20),Vector3(-24,.12,65),Vector3(-18,.12,90)]

func setup(owner_city: Node3D) -> void:
	city = owner_city
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map,.05)
	region = NavigationRegion3D.new()
	add_child(region)
	pedestrian = Pedestrian.new()
	pedestrian.name = "NavigationCivilian"
	pedestrian.navigator = self
	pedestrian.position = Vector3(18,.3,90)
	add_child(pedestrian)
	people.append(pedestrian)
	pedestrian.arrived.connect(func():pause_at_stop=1.5)
	follow_camera = Camera3D.new()
	follow_camera.fov = 55
	follow_camera.far = 1800
	add_child(follow_camera)
	reset_follow_view()
	var hud := CanvasLayer.new()
	add_child(hud)
	status = Label.new()
	status.position = Vector2(30,150)
	status.add_theme_font_size_override("font_size",18)
	hud.add_child(status)
	if "--navigation-review" in OS.get_cmdline_user_args():
		set_follow(true)
		city.hud.visible = false
	rebuild()

func rebuild() -> void:
	if baking:return
	baking = true
	ready_for_paths = false
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.cell_size = .25
	mesh.cell_height = .05
	mesh.agent_radius = .5
	mesh.agent_height = 2.0 # Shared map also reserves clearance for the 1.95 m astronaut.
	mesh.agent_max_climb = Pedestrian.MAX_STEP_HEIGHT
	mesh.agent_max_slope = 40
	mesh.filter_baking_aabb = AABB(Vector3(-70,-1,-65),Vector3(140,18,175))
	var data := NavigationMeshSourceGeometryData3D.new()
	var started := Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(mesh,data,city)
	NavigationServer3D.bake_from_source_geometry_data_async(mesh,data,func():
		previous_iteration = NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)
		region.navigation_mesh = mesh
		bake_ms = Time.get_ticks_msec()-started
		call_deferred("_synchronize"))

func _synchronize() -> void:
	var map: RID = get_world_3d().navigation_map
	# Region registration and the navigation server synchronize on different frames.
	# Never release a waiting pedestrian against an empty or stale map.
	var probe := Vector3(18,.12,90)
	while NavigationServer3D.map_get_iteration_id(map)<=previous_iteration or NavigationServer3D.map_get_closest_point(map,probe).distance_to(probe)>1.0:
		await get_tree().process_frame
		await get_tree().physics_frame
	baking = false
	ready_for_paths = true
	revision += 1
	for person in people:
		if person.active:person.refresh_path()
	rebuilt.emit()
	print("NAVIGATION_READY polygons=%d bake_ms=%d revision=%d" % [region.navigation_mesh.get_polygon_count(),bake_ms,revision])

func command_destination(index: int) -> void:
	automatic = false
	pedestrian.go_to(points[index])

func toggle_barrier(refresh_routes := true) -> void:
	if is_instance_valid(barrier):
		barrier.queue_free()
		barrier = null
		await get_tree().physics_frame
	else:
		barrier = StaticBody3D.new()
		barrier.name = "TemporaryNavigationObstruction"
		# Ground promenade: enough clearance remains on both sides to detour.
		barrier.position = Vector3(18,.9,78)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new();box.size = Vector3(3,1.6,2)
		shape.shape = box;barrier.add_child(shape)
		var visual := MeshInstance3D.new();var geometry := BoxMesh.new();geometry.size = box.size;visual.mesh = geometry
		var mat := StandardMaterial3D.new();mat.albedo_color = Color("da9a40");visual.material_override = mat;barrier.add_child(visual)
		city.add_child(barrier)
	if refresh_routes:rebuild()

func _process(delta: float) -> void:
	if automatic and ready_for_paths and not pedestrian.active:
		pause_at_stop -= delta
		if pause_at_stop <= 0:
			route_index = (route_index+1)%points.size()
			pedestrian.go_to(points[route_index])
	if follow:
		city.explorer.external_camera_active=follow_camera.current
		if can_control_follow():
			var move := Input.get_vector("left","right","forward","back")
			var direction := follow_camera.global_basis*Vector3(move.x,0,move.y)
			direction.y += Input.get_action_strength("up")-Input.get_action_strength("down")
			follow_offset += direction.limit_length()*4.0*(3 if Input.is_action_pressed("sprint") else 1)*delta
		follow_camera.position=pedestrian.global_position+follow_offset
		follow_camera.look_at(pedestrian.global_position+Vector3(0,1,0))
	if is_instance_valid(status):
		status.text = "STAGE 3C · ONE CIVILIAN / NAVIGATION\n%s · %s · %.2f m/s\nF3 FOLLOW · F4 WALK/RUN · F5 OBSTRUCTION · F6 AUTO ROUTE\nF7 PROMENADE · F8 SKYWALK · F9 TERRACE · F10 WEST STAIRS\nFOLLOW: WASD / E Q MOVE · CLICK-DRAG / TWO-FINGER SCROLL ORBIT · R RESET" % ["BAKING ROUTES" if baking else pedestrian.state,"RUN" if pedestrian.running else "WALK",Vector2(pedestrian.velocity.x,pedestrian.velocity.z).length()]

func can_control_follow() -> bool:
	if city.inspector!=null and city.inspector.is_open():return false
	return follow and follow_camera.current and not city.explorer.controls_open and (city.simulation==null or (not city.simulation.panel.is_open() and not city.simulation.quitting))

func reset_follow_view() -> void:
	follow_offset=Vector3(3.4,2.5,5)
	follow_camera.position=pedestrian.global_position+follow_offset
	follow_camera.look_at(pedestrian.global_position+Vector3(0,1,0))

func orbit_follow(amount: Vector2) -> void:
	var relative:=follow_offset-Vector3(0,1,0)
	var radius:=maxf(relative.length(),1.2)
	var yaw:=atan2(relative.x,relative.z)-amount.x*.006
	var pitch:=clampf(asin(clampf(relative.y/radius,-1,1))+amount.y*.006,-1.35,1.35)
	follow_offset=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*radius+Vector3(0,1,0)

func set_follow(enabled: bool) -> void:
	follow=enabled;looking=false
	city.explorer.set_capture(false)
	city.explorer.external_camera_active=enabled
	if enabled:follow_camera.make_current();city.hud.visible=false
	else:
		if city.explorer.observing:city.explorer.observer_camera.make_current()
		else:city.explorer.ground_camera.make_current()
		city.hud.visible=true

func _input(event: InputEvent) -> void:
	if not follow:return
	if not can_control_follow():
		looking=false
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if event.pressed and get_viewport().gui_get_hovered_control()!=null:return
		looking=event.pressed;city.explorer.set_capture(looking)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and looking and city.explorer.mouse_active:
		orbit_follow(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture and get_viewport().gui_get_hovered_control()==null:
		orbit_follow(event.delta*12)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT] and get_viewport().gui_get_hovered_control()==null:
		var amount:=Vector2.ZERO
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:amount.y=-12*event.factor
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:amount.y=12*event.factor
		elif event.button_index==MOUSE_BUTTON_WHEEL_LEFT:amount.x=-12*event.factor
		else:amount.x=12*event.factor
		orbit_follow(amount)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_R:reset_follow_view();get_viewport().set_input_as_handled()
		elif event.keycode==KEY_ESCAPE:looking=false;city.explorer.set_capture(false);get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	match event.keycode:
		KEY_F3:
			set_follow(not follow)
		KEY_F4:pedestrian.running = not pedestrian.running
		KEY_F5:toggle_barrier()
		KEY_F6:automatic = not automatic
		KEY_F7:command_destination(0)
		KEY_F8:command_destination(3)
		KEY_F9:command_destination(4)
		KEY_F10:command_destination(6)
