extends SceneTree
var city: Node3D
func _initialize() -> void:call_deferred("run")
func until(predicate: Callable) -> bool:
	var end:=Time.get_ticks_msec()+35000
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func sample(label: String) -> Dictionary:
	await create_timer(2).timeout
	var times: Array[float]=[]
	var physics: Array[float]=[]
	var previous:=Time.get_ticks_usec()
	var end:=Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<end:
		await process_frame
		var now:=Time.get_ticks_usec();times.append(float(now-previous)/1000);previous=now
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	times.sort();physics.sort()
	return {"view":label,"frames":times.size(),"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*.95)],"p99_ms":times[int(times.size()*.99)],"max_ms":times[-1],"physics_p95_ms":physics[int(physics.size()*.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"engine_static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}
func run() -> void:
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	var bridge: Node=city.simulation
	if not await until(func():return bridge.restored and city.population.restored and city.population.navigation.ready_for_paths):
		push_error("Stage5E restore timeout");quit(1);return
	bridge.last_view=bridge.now()+3600
	bridge.set_clock(false,1)
	if not await until(func():return bridge.pending.is_empty() and not bridge.world.paused):quit(1);return
	var cores: Array=bridge.world.citizens.slice(30).map(func(c):return c.exceptional.core)
	var start: float=bridge.world.clock_seconds
	var camera:=Camera3D.new();city.add_child(camera);camera.position=Vector3(-24,4,-24);camera.look_at(Vector3(0,2,0));camera.make_current()
	var results: Array=[]
	results.append(await sample("street, simulation running"))
	camera.position=Vector3(35,32,85);camera.look_at(Vector3(0,8,0))
	results.append(await sample("district skyline, simulation running"))
	city.inspector.open_control_room()
	results.append(await sample("control room open, simulation running"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage5e/control-room.png")
	city.inspector.close();camera.position=Vector3(-24,4,-24);camera.look_at(Vector3(0,2,0))
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage5e/street.png")
	var valid: bool=bridge.world.citizens.size()==34 and bridge.world.clock_seconds>start+20 and cores==bridge.world.citizens.slice(30).map(func(c):return c.exceptional.core)
	var result: Dictionary={"population":34,"viewport":str(root.size),"simulated_seconds":bridge.world.clock_seconds-start,"samples":results,"scope":"Three 8-second samples after 2-second warmups, native running scene. Not a worst-case or scaling guarantee."}
	var file:=FileAccess.open("res://../docs/previews/stage5e/performance.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("STAGE5E_CHECK failures="+str(0 if valid else 1))
	if valid:bridge.request_quit()
	else:quit(1)
