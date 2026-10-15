extends SceneTree
## Offline visual and motion checks, without backend or world saves.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var destination := ProjectSettings.globalize_path("res://../docs/previews/uplink")
	DirAccess.make_dir_recursive_absolute(destination)
	var city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	city.explorer.set_capture(false)
	city.hud.hide()
	var uplink: Node3D = city.get_node("CityUplink")
	assert(uplink.point_count > 2000,"Expected dense continental data")
	assert(uplink.gyros.size() == 3 and uplink.pulses.size() == 3)
	var camera := Camera3D.new()
	camera.fov = 48
	city.add_child(camera)
	camera.position = Vector3(6,8.6,-27)
	camera.look_at(Vector3(0,6.6,-40))
	camera.make_current()
	uplink.set_process(false)
	if "--uplink-movie" in OS.get_cmdline_user_args():
		uplink.update_animation(0)
		for i in 24: await process_frame
		for i in 240:
			uplink.update_animation(float(i)/24.0)
			await process_frame
		print("UPLINK_MOVIE frames=240 fps=24")
		quit()
		return
	for frame in 3:
		uplink.update_animation(float(frame)*2.0)
		for i in 16: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(destination+"/detail-%d.png"%frame)
	# Verify motion direction rather than only the presence of geometry.
	uplink.update_animation(0.2)
	var pulse_y: float = uplink.pulses[0].position.y
	var gyro_a: float = uplink.gyros[0].rotation.y
	var gyro_b: float = uplink.gyros[1].rotation.y
	uplink.update_animation(0.3)
	assert(uplink.pulses[0].position.y > pulse_y)
	assert(uplink.gyros[0].rotation.y > gyro_a and uplink.gyros[1].rotation.y < gyro_b)
	var original: Vector3 = uplink.planet.rotation
	uplink.update_animation(10)
	assert(not original.is_equal_approx(uplink.planet.rotation))
	for ring in uplink.pulses:
		assert(is_finite(ring.scale.x) and ring.scale.x > 0)
	# Eye-level approach: the monument must read from the pedestrian plaza.
	camera.position = Vector3(4,2.0,-23)
	camera.look_at(Vector3(0,6.0,-40))
	for i in 16: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination+"/approach.png")
	city.explorer.set_view(1)
	city.explorer.observer_camera.make_current()
	for i in 16: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(destination+"/plaza.png")
	print("UPLINK_QA passed points=",uplink.point_count," gyros=3 pulses=3 animation=passed")
	quit()
