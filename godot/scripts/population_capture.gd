extends SceneTree
## Native renderer population review using an isolated save supplied on the command line.
var city: Node3D
func _initialize() -> void:call_deferred("capture")
func capture() -> void:
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	var bridge: Node=city.simulation
	var pop: Node3D=city.population
	var deadline:=Time.get_ticks_msec()+30000
	while not (bridge.restored and pop.restored and pop.navigation.ready_for_paths):
		if bridge.fatal or Time.get_ticks_msec()>deadline:quit(1);return
		await process_frame
	city.explorer.set_capture(false);city.explorer.external_camera_active=true;city.hud.hide();pop.panel.hide()
	var camera:=Camera3D.new();city.add_child(camera);camera.fov=65;camera.far=1800
	camera.position=Vector3(0,8,96);camera.look_at(Vector3(0,3,12));camera.make_current()
	bridge.set_clock(false,1)
	await create_timer(3).timeout
	var frames: Array[float]=[]
	var last:=Time.get_ticks_usec()
	var end:=last+12000000
	while Time.get_ticks_usec()<end:
		await process_frame
		var now:=Time.get_ticks_usec();frames.append((now-last)/1000.0);last=now
	frames.sort()
	var metrics:={"residents":pop.units.size(),"frames":frames.size(),"median_frame_ms":frames[frames.size()/2],"p95_frame_ms":frames[int(frames.size()*.95)],"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"viewport":str(root.size),"renderer":RenderingServer.get_current_rendering_method()}
	var file:=FileAccess.open("res://../docs/previews/stage3e/performance.json",FileAccess.WRITE);file.store_string(JSON.stringify(metrics,"\t"));file.close();print("POPULATION_PERFORMANCE ",JSON.stringify(metrics))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage3e/district.png")
	pop.select_relative(25);pop.follow=true;pop.navigation.set_follow(true);pop.panel.show()
	await create_timer(2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage3e/police.png")
	pop.select_relative(8)
	await create_timer(2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage3e/civilian.png")
	bridge.request_quit()
