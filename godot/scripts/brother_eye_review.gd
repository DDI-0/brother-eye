extends SceneTree
## Offline building study. Uses normal city lighting and does not open world saves.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var tag := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-tag="): tag = arg.trim_prefix("--review-tag=")
	var folder := ProjectSettings.globalize_path("res://../docs/previews/brother-eye-tower/"+tag)
	DirAccess.make_dir_recursive_absolute(folder)
	var city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	city.hud.hide()
	city.explorer.set_capture(false)
	var camera := Camera3D.new()
	camera.far = 1800
	city.add_child(camera)
	camera.make_current()
	var views := [
		["tower",Vector3(65,73,45),Vector3(0,72,-96),60.0],
		["skyline",Vector3(82,91,112),Vector3(0,90,-96),54.0],
		["overview",Vector3(64,112,185),Vector3(0,59,-62),65.0],
		["facade",Vector3(36,48,-30),Vector3(0,50,-92),55.0],
		["entrance",Vector3(13,2.0,-54),Vector3(0,4,-76),65.0]
	]
	for view in views:
		camera.position = view[1]
		camera.fov = view[3]
		camera.look_at(view[2])
		for i in 24: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+view[0]+".png")
	# Live acknowledgement feedback duplicates this material as StandardMaterial3D.
	assert(city.command_signal.material_override is StandardMaterial3D)
	assert(city.command_signal.material_override.emission_enabled)
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0,2,-70),Vector3(0,2,-80))
	var hit: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(ray)
	assert(not hit.is_empty() and absf(hit.position.z+76.0)<.05,"Podium collision changed")
	print("BROTHER_EYE_REVIEW captured=5 feedback_material=passed entrance_collision=passed collision_shapes=",city.kit.collision_count)
	quit()
