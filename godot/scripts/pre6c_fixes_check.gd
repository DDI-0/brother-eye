extends SceneTree
var city: Node3D
var bridge: Node
var failures: Array[String]=[]
var seat_id:=""
var stroll_id:=""
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures.append(label)
func until(predicate: Callable, seconds:=30.0) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func snap(name: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/pre6c-fixes/"+name+".png")
func sample(label: String) -> Dictionary:
	await create_timer(2).timeout
	var frames: Array[float]=[];var physics: Array[float]=[]
	var previous:=Time.get_ticks_usec();var end:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<end:
		await process_frame
		var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000);previous=now
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	frames.sort();physics.sort()
	var counts: Array[int]=[0,0,0]
	for unit in city.population.units.values():counts[unit.person.lod_level]+=1
	return {"view":label,"frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[int(frames.size()*.95)],"p99_ms":frames[int(frames.size()*.99)],"max_ms":frames[-1],"physics_p95_ms":physics[int(physics.size()*.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"lod_distribution":counts}
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seat-id="):seat_id=arg.trim_prefix("--seat-id=")
		if arg.begins_with("--stroll-id="):stroll_id=arg.trim_prefix("--stroll-id=")
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation
	if not await until(func():return bridge.restored and city.population.restored and city.population.navigation.ready_for_paths):push_error("restore timeout");quit(1);return
	bridge.last_view=bridge.now()+3600
	city.hud.hide()
	var actor: CharacterBody3D=city.population.units[seat_id].person
	var stroll: CharacterBody3D=city.population.units[stroll_id].person
	var start: Vector3=actor.position;var stroll_start: Vector3=stroll.position
	var camera:=Camera3D.new();city.add_child(camera);camera.position=actor.position+Vector3(-signf(actor.position.x)*4,1.7,2.5);camera.look_at(actor.position+Vector3(0,.85,0));camera.make_current()
	bridge.set_clock(false,1)
	check(await until(func():return actor.state=="ARRIVED" and actor.player.current_animation=="sit_idle",20),"physical walk reaches bench and sit-down finishes in seated idle")
	check(actor.position.distance_to(start)>1,"bench arrival requires actual body travel")
	check(await until(func():return stroll.position.distance_to(stroll_start)>.8,10),"venue stroll moves despite retaining socializing activity")
	await snap("bench-seated")
	var record: Dictionary=city.population.units[seat_id].record
	bridge.queue_command("intervene",{"world_id":bridge.world.world_id,"citizen_id":seat_id,"expected_goal_id":record.goal.id,"expected_intervention_id":null,"action":"assign_destination","place":"food","reason":"Verify physical standing and departure"})
	check(await until(func():return actor.player.current_animation=="stand_up",8),"directed departure plays stand-up")
	var seated_position: Vector3=actor.position
	check(await until(func():return actor.pose=="stand" and actor.position.distance_to(seated_position)>1,15),"standing finishes and walking resumes without teleport")
	print("DEPARTURE state=",actor.state," pose=",actor.pose," clip=",actor.player.current_animation," active=",actor.active," pending=",actor.has_pending_destination," distance=",actor.position.distance_to(seated_position))
	if not failures.is_empty():print("PRE6C_FIXES failures=",failures.size());quit(1);return
	# Sample real counters at near and far camera distances, with collisions still enabled.
	camera.position=actor.position+Vector3(-5,2,3);camera.look_at(actor.position);await create_timer(.4).timeout
	var before: int=actor.animation_updates
	var probes_before: int=actor.step_probe_updates
	await create_timer(1.2).timeout
	var near_updates: int=actor.animation_updates-before
	var near_probes: int=actor.step_probe_updates-probes_before
	camera.position=actor.position+Vector3(0,15,95);camera.look_at(actor.position);await create_timer(.4).timeout
	before=actor.animation_updates
	probes_before=actor.step_probe_updates
	await create_timer(1.2).timeout
	var far_updates: int=actor.animation_updates-before
	var far_probes: int=actor.step_probe_updates-probes_before
	check(actor.lod_level==2 and near_updates>far_updates*2,"far animation budget reduces actual evaluations")
	check(near_probes>far_probes*2 and far_probes>0,"far step-probe budget reduces queries while walking")
	check(actor.collision_mask==3 and actor.agent.avoidance_enabled,"distance budget preserves body collision and crowd avoidance")
	var samples: Array=[]
	camera.position=Vector3(-16,3.8,-12);camera.look_at(Vector3(0,1,-38));samples.append(await sample("street"));await snap("street")
	camera.position=Vector3(0,3.5,-24);camera.look_at(Vector3(0,1.2,-40));samples.append(await sample("plaza"));await snap("plaza")
	camera.position=Vector3(0,38,140);camera.look_at(Vector3(0,8,15));samples.append(await sample("skyline"));await snap("skyline")
	var metrics: Dictionary={"population":bridge.world.citizens.size(),"viewport":str(root.size),"near_animation_updates":near_updates,"far_animation_updates":far_updates,"near_step_probes":near_probes,"far_step_probes":far_probes,"samples":samples,"scope":"Three 10-second native samples after 2-second view warmups; no thermal telemetry or throttling guarantee."}
	var file:=FileAccess.open("res://../docs/previews/pre6c-fixes/performance.json",FileAccess.WRITE);file.store_string(JSON.stringify(metrics,"  "));file.close()
	print("PRE6C_FIXES failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
