extends SceneTree
var city: Node3D
var bridge: Node
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures.append(label)
func until(predicate: Callable, seconds:=35.0) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func shot(label: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage6c/"+label+".png")
func image_difference(label: String) -> float:
	var a:=Image.load_from_file("res://../docs/previews/stage6c/"+label+"-baseline.png")
	var b:=Image.load_from_file("res://../docs/previews/stage6c/"+label+"-optimized.png")
	a.convert(Image.FORMAT_RGB8);b.convert(Image.FORMAT_RGB8)
	var x:=a.get_data();var y:=b.get_data();var total:=0.0;var count:=0
	for i in range(0,x.size(),48):total+=absf(float(x[i])-float(y[i]));count+=1
	return total/maxi(1,count)
func sample(label: String) -> Dictionary:
	await create_timer(2).timeout
	var times: Array[float]=[];var calls: Array[float]=[];var physics: Array[float]=[];var primitives: Array[float]=[]
	var previous:=Time.get_ticks_usec();var end:=Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<end:
		await process_frame
		var now:=Time.get_ticks_usec();times.append(float(now-previous)/1000);previous=now
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME));physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	times.sort();calls.sort();physics.sort();primitives.sort()
	return {"view":label,"frames":times.size(),"median_ms":times[times.size()/2],"p95_ms":times[int(times.size()*.95)],"p99_ms":times[int(times.size()*.99)],"max_ms":times[-1],"draw_calls_median":calls[calls.size()/2],"render_primitives_median":primitives[primitives.size()/2],"physics_p95_ms":physics[int(physics.size()*.95)],"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}
func run() -> void:
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation
	if not await until(func():return bridge.restored and city.population.restored and city.population.navigation.ready_for_paths):push_error("restore timeout");quit(1);return
	bridge.last_view=bridge.now()+3600;city.hud.hide();city.inspector.close()
	var camera:=Camera3D.new();city.add_child(camera);camera.make_current()
	var collision_count: int=city.kit.collision_count
	var paused_clock: float=bridge.world.clock_seconds
	var baseline: Array=[];var optimized: Array=[]
	var visual_differences: Dictionary={}
	var views: Array=[["street",Vector3(-16,3.8,-12),Vector3(0,1,-38)],["plaza",Vector3(0,3.5,-24),Vector3(0,1.2,-40)],["skyline",Vector3(0,38,140),Vector3(0,8,15)]]
	for view in views:
		camera.position=view[1];camera.look_at(view[2])
		city.visual_budget.set_enabled(false)
		baseline.append(await sample(view[0]));await shot(view[0]+"-baseline")
		city.visual_budget.set_enabled(true)
		optimized.append(await sample(view[0]));await shot(view[0]+"-optimized")
		visual_differences[view[0]]=image_difference(view[0])
	check(visual_differences.street<12 and visual_differences.plaza<12,"near-view sampled image differences remain below 12/255 intensity")
	check(city.visual_budget.sources.size()>city.visual_budget.outputs.size(),"opaque source surfaces consolidated into fewer spatial batches")
	check(city.kit.collision_count==collision_count and collision_count==657,"visual budget preserves all 657 collision shapes")
	check(bridge.world.paused and bridge.world.clock_seconds==paused_clock,"visual comparison advances no paused city time")
	check(city.command_signal.layers!=0 and city.satellite_signal.layers!=0,"Brother Eye command/lens signals remain independently visible")
	check(optimized[2].draw_calls_median<baseline[2].draw_calls_median,"controlled skyline view reduces draw submissions")
	var preserved_cores: Array=bridge.world.citizens.filter(func(c):return c.kind=="exceptional").map(func(c):return c.exceptional.core)
	bridge.set_clock(false,1)
	check(await until(func():return bridge.pending.is_empty() and not bridge.world.paused),"50-person simulation resumes with optimized visuals")
	var actor: CharacterBody3D=city.population.units[city.population.order[0]].person
	camera.position=actor.position+Vector3(0,10,220);camera.look_at(actor.position)
	city.inspector.open_control_room()
	var room: VBoxContainer=city.inspector.control_room
	room.camera.position=actor.position+Vector3(0,3,5);room.camera.look_at(actor.position)
	check(await until(func():return actor.lod_level==0 and room.render_requests>0,5),"near control-room camera retains full animation detail while main camera is far")
	optimized.append(await sample("control room running"));await shot("control-room")
	city.inspector.close()
	check(await until(func():return actor.lod_level==2 and not city.has_meta("detail_feed_position"),5),"closing feed releases its animation-detail priority")
	check(preserved_cores==bridge.world.citizens.filter(func(c):return c.kind=="exceptional").map(func(c):return c.exceptional.core),"visual budgets preserve canonical cores")
	var out:=FileAccess.open("res://../docs/previews/stage6c/performance.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"population":50,"viewport":str(root.size),"baseline":baseline,"optimized":optimized,"sampled_image_difference":visual_differences,"merged_sources":city.visual_budget.sources.size(),"output_batches":city.visual_budget.outputs.size(),"collision_shapes":collision_count,"scope":"Same paused 50-person city, same camera per paired 8-second samples after 2-second warmups. Final optimized control-room sample runs simulation. Retained original meshes allow A/B; no thermal telemetry."},"  "));out.close()
	print("STAGE6C_CHECK failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
