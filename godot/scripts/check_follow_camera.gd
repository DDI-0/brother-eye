extends SceneTree
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures+=1
func frames(count: int) -> void:
	for i in count:await process_frame
func run() -> void:
	var city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	var nav=city.pedestrian_navigation
	nav.automatic=false;nav.pedestrian.simulation_frozen=true
	await frames(3)
	var explorer: Dictionary=city.explorer.saved_view()
	var citizen_position: Vector3=nav.pedestrian.position
	for action in ["forward","back","left","right","up","down"]:
		var start: Vector3=nav.follow_camera.position
		Input.action_press(action);await frames(5);Input.action_release(action)
		check(nav.follow_camera.position.distance_to(start)>.01,action+" moves follow camera")
	check(city.explorer.saved_view()==explorer,"follow controls preserve saved explorer view")
	check(nav.pedestrian.position==citizen_position,"camera controls do not move civilian")
	var button:=InputEventMouseButton.new();button.button_index=MOUSE_BUTTON_RIGHT;button.pressed=true
	Input.parse_input_event(button);await frames(2)
	var rotation_before: Vector3=nav.follow_camera.rotation
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(40,20)
	Input.parse_input_event(motion);await frames(2)
	check(nav.follow_camera.rotation.distance_to(rotation_before)>.02,"right mouse drag changes camera look")
	button.pressed=false;Input.parse_input_event(button);await frames(2)
	check(not city.explorer.mouse_active,"releasing right mouse releases pointer")
	button.button_index=MOUSE_BUTTON_LEFT;button.pressed=true
	Input.parse_input_event(button);await frames(2)
	var orbit_before: Vector3=nav.follow_offset
	Input.parse_input_event(motion);await frames(2)
	button.pressed=false;Input.parse_input_event(button);await frames(2)
	check(nav.follow_offset.distance_to(orbit_before)>.1,"touchpad click-drag orbits around civilian")
	var radius_before: float=(nav.follow_offset-Vector3(0,1,0)).length()
	var pan:=InputEventPanGesture.new();pan.delta=Vector2(2,1)
	orbit_before=nav.follow_offset
	Input.parse_input_event(pan);await frames(2)
	check(nav.follow_offset.distance_to(orbit_before)>.1,"two-finger pan orbits around civilian")
	check(is_equal_approx((nav.follow_offset-Vector3(0,1,0)).length(),radius_before),"orbit preserves distance from civilian")
	var to_civilian: Vector3=(nav.pedestrian.position+Vector3(0,1,0)-nav.follow_camera.position).normalized()
	check((-nav.follow_camera.global_basis.z).dot(to_civilian)>.999,"orbit keeps civilian centered")
	var offset: Vector3=nav.follow_offset
	var heading: Vector3=nav.follow_camera.rotation
	nav.pedestrian.position+=Vector3(2,0,-3);await frames(2)
	check(nav.follow_camera.position.is_equal_approx(nav.pedestrian.position+offset) and nav.follow_camera.rotation.is_equal_approx(heading),"camera tracks civilian movement while keeping custom view")
	var reset:=InputEventKey.new();reset.keycode=KEY_R;reset.pressed=true
	Input.parse_input_event(reset);await frames(2)
	check(nav.follow_offset.is_equal_approx(Vector3(3.4,2.5,5)),"R resets follow position")
	var facing: Vector3=(nav.pedestrian.position+Vector3(0,1,0)-nav.follow_camera.position).normalized()
	check((-nav.follow_camera.global_basis.z).dot(facing)>.999,"R resets look toward civilian")
	nav.set_follow(false)
	check(not city.explorer.external_camera_active and city.explorer.observer_camera.current,"leaving follow restores explorer control and camera")
	nav.set_follow(true)
	check(city.explorer.external_camera_active and nav.follow_camera.current,"follow can be entered again")
	print("FOLLOW_CAMERA_CHECK failures=",failures);quit(0 if failures==0 else 1)
