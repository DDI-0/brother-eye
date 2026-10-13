extends Node
var timings: Array[float] = []
var measuring := false
var previous_tick := 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if measuring and previous_tick > 0: timings.append((now-previous_tick)/1000.0)
	previous_tick = now

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func run(city: Node3D) -> void:
	var destination := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): destination = arg.trim_prefix("--capture-dir=")
	if destination.is_empty():
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	city.explorer.set_capture(false)
	await frames(90)
	measuring = true
	await frames(240)
	measuring = false
	timings.sort()
	var report := {"frames":timings.size(),"median_ms":timings[timings.size()/2],"p95_ms":timings[int(timings.size()*0.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"static_memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,"render_video_memory_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,"renderer":RenderingServer.get_current_rendering_method(),"driver":RenderingServer.get_current_rendering_driver_name(),"resolution":str(get_viewport().get_visible_rect().size)}
	for index in 3:
		city.explorer.set_view(index)
		city.hud.menu.visible = index == 0
		await frames(30)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(destination+"/"+["skyline","plaza","skywalk"][index]+".png")
	city.explorer.controls_open = true
	city.hud.refresh()
	await frames(5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(destination+"/controls.png")
	var file := FileAccess.open(destination+"/performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	print("STAGE1_CAPTURE ",JSON.stringify(report))
	get_tree().quit()
