extends SceneTree
## Offline visual and real-controller access checks. No simulation or save access.
var city: Node3D
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
func run() -> void:
	var folder := ProjectSettings.globalize_path("res://../docs/previews/observatory")
	DirAccess.make_dir_recursive_absolute(folder)
	city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	city.explorer.set_capture(false)
	city.hud.hide()
	var camera := Camera3D.new()
	camera.far = 1800
	city.add_child(camera)
	camera.make_current()
	var views := [
		["entrance",Vector3(31,3,43),Vector3(46,6,24),62.0],
		["terrace",Vector3(23,25,35),Vector3(46,13.2,1),58.0],
		["dome",Vector3(40,20,15),Vector3(46,15,-2),48.0]
	]
	for view in views:
		camera.position = view[1]
		camera.fov = view[3]
		camera.look_at(view[2])
		await capture(folder+"/"+view[0]+".png")
	var day = load("res://scripts/day_cycle_review.gd").new()
	day.city = city
	day.caption = Label.new()
	day.progress = ProgressBar.new()
	day.apply_hour(10)
	for view in views:
		camera.position = view[1]
		camera.fov = view[3]
		camera.look_at(view[2])
		await capture(folder+"/day-"+view[0]+".png")
	day.caption.free()
	day.progress.free()
	day.free()
	var player = city.explorer
	player.set_capture(true)
	player.observing = false
	player.controls_open = false
	player.position = Vector3(24,12.3,20)
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	for i in 20: await physics_frame
	Input.action_press("right")
	for i in 78:
		player.mouse_active = true
		await physics_frame
	Input.action_release("right")
	check(player.position.x > 29 and player.position.y > 11.8,"Observatory skywalk entry blocked")
	Input.action_press("forward")
	for i in 95:
		player.mouse_active = true
		await physics_frame
	Input.action_release("forward")
	check(player.position.z < 14 and player.position.y > 11.8,"Observatory inner deck aisle blocked")
	# Service cabinets and dome chamber must block walking; the entrance remains closed.
	var space := city.get_world_3d().direct_space_state
	for sample in [
		["entrance",Vector3(46,2,28),Vector3(46,2,22)],
		["service equipment",Vector3(58.5,13,10),Vector3(58.5,13,5)],
		["instrument drum",Vector3(46,12.6,7),Vector3(46,12.6,0)]
	]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(sample[1],sample[2]))
		check(not hit.is_empty(),"Missing collision: "+sample[0])
	var report := {"passed":failures.is_empty(),"captures":6,"failures":failures,"player_final":str(player.position),"renderer":RenderingServer.get_current_rendering_method()}
	var out := FileAccess.open(folder+"/verification.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  ")+"\n")
	print("OBSERVATORY_REVIEW ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
func capture(path: String) -> void:
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
