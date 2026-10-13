extends SceneTree
var city: Node3D
var bridge: Node
var failures: Array[String]=[]
var phase:="write"
var probe:=""
var target_id:=""
var seat_id:=""
var tier:=2
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:
		failures.append(label)
		if bridge!=null:print("BRIDGE_DIAGNOSTIC connected=",bridge.connected," fatal=",bridge.fatal," status=",bridge.status," error=",bridge.last_error)
func idle() -> bool:return bridge.restored and bridge.connected and bridge.pending.is_empty() and city.population.restored
func until(predicate: Callable, seconds:=35.0) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func save_json(path: String,value: Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value,"  ",true,true));file.close()
func record() -> Dictionary:return city.population.units[target_id].record
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage6e/"+str(tier)+"-"+label+".png")
func sample(label: String) -> Dictionary:
	await create_timer(2).timeout
	var start_clock: float=bridge.world.clock_seconds
	var frames: Array[float]=[];var physics: Array[float]=[];var calls: Array[float]=[]
	var previous:=Time.get_ticks_usec();var end:=Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<end:
		await process_frame
		if bridge.fatal:
			push_error("benchmark bridge failure: "+bridge.last_error);quit(1);return {}
		var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000);previous=now
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	frames.sort();physics.sort();calls.sort()
	check(bridge.connected and bridge.world.clock_seconds>start_clock+5,"simulation stays live throughout "+label+" sample")
	var lod: Array[int]=[0,0,0];var states: Dictionary={}
	for unit in city.population.units.values():
		lod[unit.person.lod_level]+=1
		states[unit.person.state]=states.get(unit.person.state,0)+1
	return {"view":label,"frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*.95)],"p99_ms":frames[int(frames.size()*.99)],"max_ms":frames[-1],"physics_p95_ms":physics[int(physics.size()*.95)],"draw_calls_median":calls[calls.size()/2],"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"lod":lod,"physical_states":states,"pending_commands":bridge.pending.size()}
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe=arg.trim_prefix("--probe=")
		if arg.begins_with("--target-id="):target_id=arg.trim_prefix("--target-id=")
		if arg.begins_with("--seat-id="):seat_id=arg.trim_prefix("--seat-id=")
		if arg.begins_with("--review-tier="):tier=int(arg.trim_prefix("--review-tier="))
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation
	check(await until(func():return idle() and city.population.navigation.ready_for_paths),"population and actual district navigation restore")
	if not idle():push_error("restore failed: "+bridge.last_error);quit(1);return
	bridge.last_view=bridge.now()+3600;city.hud.hide();city.explorer.set_capture(false)
	check(bridge.world.citizens.size()==[34,50,100][tier] and city.population.units.size()==[34,50,100][tier],"one physical body per saved resident")
	check(city.kit.collision_count==657,"all 657 city collision shapes retained")
	var cores: Array=bridge.world.citizens.filter(func(c):return c.kind=="exceptional").map(func(c):return c.exceptional.core)
	if phase=="read":
		var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe))
		print("RESTORE_CLOCK ",JSON.stringify({"actual":bridge.world.clock_seconds,"expected":saved.clock,"difference":bridge.world.clock_seconds-saved.clock,"paused":bridge.world.paused},"",true,true))
		check(bridge.world.paused and bridge.world.clock_seconds==saved.clock and bridge.world.world_id==saved.world_id,"app relaunch preserves paused world/clock without offline time")
		check(bridge.world.citizens.map(func(c):return c.id)==saved.ids and cores==saved.cores,"all identities and canonical cores restore")
		check(record().intervention.id==saved.override_id and record().intervention.status=="completed","completed held authority restores")
		check(city.command_feedback.pulse_count==0,"restore produces no historical command pulse")
	else:
		var navmap: RID=city.get_world_3d().navigation_map
		var missed: Array=[];var routes:=0
		for c in bridge.world.citizens:
			for place in c.known_places.values():
				for spot in place.get("spots",[]):
					var point:=Vector3(spot.position[0],spot.position[1],spot.position[2])
					var nearest:=NavigationServer3D.map_get_closest_point(navmap,point)
					var path:=NavigationServer3D.map_get_path(navmap,Vector3(18,.12,60),nearest,true)
					routes+=1
					if nearest.distance_to(point)>.8 or path.size()<2 or path[-1].distance_to(nearest)>.3:missed.append({"name":c.name,"point":str(point),"offset":nearest.distance_to(point)})
		print("VENUE_NAVIGATION routes=",routes," missed=",JSON.stringify(missed))
		check(missed.is_empty(),"all retained and new venue spots have connected nearby navigation")
		var starts: Dictionary={}
		for id in city.population.units:starts[id]=city.population.units[id].person.position
		var inspector: CanvasLayer=city.inspector
		inspector.open_interventions();inspector.select_person(target_id)
		var controls: VBoxContainer=inspector.interventions
		controls.reason.text="Stage 6E: verify physical market access at target population"
		controls.destination.select(controls.place_keys.find("food"));controls.issue("assign_destination")
		check(await until(idle) and record().intervention!=null,"real intervention controls accept held destination")
		bridge.set_clock(false,1);check(await until(func():return idle() and not bridge.world.paused),"active population resumes at normal time")
		inspector.close()
		check(await until(func():return record().intervention.status=="completed",30),"directed resident physically reaches destination in the live crowd")
		var target_actor: CharacterBody3D=city.population.units[target_id].person
		check(target_actor.position.distance_to(starts[target_id])>1,"completed command requires actual body displacement")
		var seated: CharacterBody3D=city.population.units[seat_id].person
		check(await until(func():return seated.player.current_animation=="sit_idle",20),"bench resident physically arrives and sits at target population")
		var camera:=Camera3D.new();city.add_child(camera);camera.make_current()
		var views: Array=[["street",Vector3(-16,3.8,-12),Vector3(0,1,-38)],["plaza",Vector3(0,3.5,-24),Vector3(0,1.2,-40)],["skyline",Vector3(0,38,140),Vector3(0,8,15)]]
		var samples: Array=[]
		for view in views:
			camera.position=view[1];camera.look_at(view[2]);samples.append(await sample(view[0]));await shot(view[0])
		inspector.open_control_room();samples.append(await sample("control room"));await shot("control-room")
		check(await until(func():return inspector.control_room.request_id.is_empty() and not inspector.control_room.entries.is_empty()),"live camera and actual committed audit load")
		inspector.close()
		var moved:=0
		for id in starts:
			if city.population.units[id].person.position.distance_to(starts[id])>1:moved+=1
		check(moved>20,"independent residents make measurable physical progress")
		check(cores==bridge.world.citizens.filter(func(c):return c.kind=="exceptional").map(func(c):return c.exceptional.core),"four immutable cores remain unchanged")
		bridge.set_clock(true,1);check(await until(idle),"final paused state acknowledged")
		city.population.capture_progress();check(await until(idle),"final physical batch durably acknowledged")
		var saved:={"world_id":bridge.world.world_id,"clock":bridge.world.clock_seconds,"ids":bridge.world.citizens.map(func(c):return c.id),"cores":cores,"override_id":record().intervention.id}
		save_json(probe,saved)
		save_json("res://../docs/previews/stage6e/performance-"+str(tier)+".json",{"population":bridge.world.citizens.size(),"viewport":str(root.size),"samples":samples,"moved_over_1m":moved,"venue_routes":routes,"navigation_bake_ms":city.population.navigation.bake_ms,"scope":"Four active native 8-second samples after 2-second warmups; uncapped scripted review, recording disabled. Engine memory counters exclude full process RSS. No thermal or worst-case guarantee."})
	print("STAGE6E_CHECK ",phase," tier=",tier," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
