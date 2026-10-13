extends SceneTree
var city: Node3D
var bridge: Node
var pop: Node3D
var inspector: CanvasLayer
var room: VBoxContainer
var feedback: Node
var failures: Array[String]=[]
var capture:=false
var phase:="write"
var probe_path:=""
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func idle() -> bool:return bridge.connected and bridge.restored and pop.restored and bridge.pending.is_empty()
func until(predicate: Callable,timeout:=25.0) -> bool:
	var end:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func c() -> Dictionary:return bridge.world.citizens[0]
func payload(place: String) -> Dictionary:
	return {"world_id":bridge.world.world_id,"citizen_id":c().id,"expected_goal_id":c().goal.id,"expected_intervention_id":c().intervention.id if c().intervention is Dictionary else null,"action":"assign_destination","place":place,"reason":"Stage 4D presentation review"}
func shot(name: String) -> void:
	if not capture:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage4d/"+name+".png")
func measure(open_room: bool) -> Dictionary:
	if open_room:inspector.open_control_room()
	else:inspector.close()
	await create_timer(1.0).timeout
	var values: Array[float]=[]
	var end:=Time.get_ticks_msec()+4000
	var requests: int=room.render_requests
	var started:=Time.get_ticks_usec()
	var previous:=started
	while Time.get_ticks_msec()<end:
		await process_frame
		var now:=Time.get_ticks_usec();values.append(float(now-previous)/1000.0);previous=now
	values.sort()
	return {"frames":values.size(),"median_ms":values[values.size()/2],"p95_ms":values[int(values.size()*.95)],"feed_updates_per_second":float(room.render_requests-requests)/(float(Time.get_ticks_usec()-started)/1000000.0),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe_path=arg.trim_prefix("--probe=")
	capture="--capture-control-room" in OS.get_cmdline_user_args()
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation;pop=city.population;inspector=city.inspector;room=inspector.control_room;feedback=city.command_feedback
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"live city and control room restore")
	if not idle():quit(1);return
	bridge.last_view=bridge.now()+3600
	check(inspector.is_open() and inspector.control_mode,"F7 launcher opens the control room")
	check(await until(func():return room.request_id.is_empty() and not room.entries.is_empty()),"committed history loaded through read-only service query")
	check(feedback.pulse_count==0 and feedback.pulse==0,"historical welcome audit does not pulse landmarks")
	check(room.viewport.world_3d==city.get_world_3d() and room.camera.get_viewport()==room.viewport,"feed renders the actual city world in its own viewport")
	var main_camera: Camera3D=root.get_camera_3d()
	var before_view: Dictionary=city.explorer.saved_view()
	var before_world: Dictionary=bridge.world.duplicate(true)
	room.feed.select(1);room.set_feed(1);await create_timer(.35).timeout
	check(root.get_camera_3d()==main_camera and city.explorer.saved_view()==before_view,"switching feed preserves exploration and follow cameras")
	check(room.render_requests>0 and room.last_frame_tick==bridge.world.tick,"feed advances only from the current live scene")
	await shot("control-room")
	if capture:
		var texture: Image=room.viewport.get_texture().get_image()
		texture.save_png("res://../docs/previews/stage4d/market-feed.png")
		var min_l:=1.0;var max_l:=0.0
		for x in range(0,texture.get_width(),16):
			for y in range(0,texture.get_height(),16):
				var l: float=texture.get_pixel(x,y).get_luminance();min_l=minf(min_l,l);max_l=maxf(max_l,l)
		check(max_l-min_l>.05,"native camera feed contains rendered city detail")
	while room.has_more:
		room.load_history(true);check(await until(func():return room.request_id.is_empty()),"older audit page loads")
	var ids: Dictionary={}
	for event in room.entries:ids[event.id]=true
	check(room.entries.size()>64 and ids.size()==room.entries.size(),"paged history reaches beyond recent cache without duplicate events")
	if room.entries.is_empty():quit(1);return
	var older_id: String=room.entries[-1].id;room.selected_event=older_id;room.show_details()
	check(room.details.text.contains("Before:") and room.details.text.contains("After:") and room.details.text.contains("Command:"),"selected historical event explains actor, reason, before/after and identity")
	room.scope.select(1);inspector.select_person(bridge.world.citizens[1].id);room.load_history(false)
	check(await until(func():return room.request_id.is_empty() and room.entries.is_empty()),"selected-resident history filter excludes other residents' events")
	room.scope.select(0);inspector.select_person(c().id);room.load_history(false)
	check(await until(func():return room.request_id.is_empty() and not room.entries.is_empty()),"all-city history restored after filtering")
	var query_id: String=bridge.identifier();room.request_id=query_id;bridge.queries[query_id]=true
	bridge.send_message("query_interventions",{"limit":0},query_id)
	check(await until(func():return room.request_id.is_empty() and not room.history_error.is_empty()),"invalid read query returns a recoverable history error")
	check(not bridge.fatal and bridge.connected,"history query errors do not freeze the application")
	room.load_history(false);check(await until(func():return room.request_id.is_empty() and room.history_error.is_empty()),"history query can retry after rejection")
	var after_world: Dictionary=bridge.world.duplicate(true);before_world.erase("saved_at");after_world.erase("saved_at")
	check(after_world==before_world and bridge.pending.is_empty(),"browsing feeds and paged history does not mutate simulation state")
	bridge.connected=false
	var rendered: int=room.render_requests
	await create_timer(.3).timeout;room.refresh()
	check(room.render_requests==rendered and room.feed.disabled and room.feed_status.text.contains("LAST FRAME") and room.history_status.text.contains("LAST KNOWN"),"offline feed freezes and history is labelled retained")
	bridge.connected=true;room.refresh()
	check(not room.history_status.text.contains("LAST KNOWN"),"reconnected history clears its offline label")
	inspector.close();rendered=room.render_requests;await create_timer(.3).timeout
	check(room.render_requests==rendered and room.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"closed control room performs no feed rendering")
	inspector.open_evaluation();await create_timer(.15).timeout
	check(not inspector.control_mode and inspector.city_mode and not room.visible and inspector.body.text.contains("CITY EVALUATION"),"evaluation exits control-room mode and keeps its existing report")
	if phase=="write":
		inspector.open_control_room()
		var actor: CharacterBody3D=pop.units[c().id].person
		var start: Vector3=actor.position
		var tick: int=bridge.world.tick
		bridge.set_clock(false,1)
		check(await until(func():return bridge.world.tick>tick and actor.position.distance_to(start)>.05),"live feed shares physically moving residents and the advancing city")
		await create_timer(.3).timeout;room.refresh()
		check(room.feed_status.text.contains("LIVE SIMULATED"),"running feed is labelled live rather than paused or retained")
		await shot("live-camera")
		bridge.set_clock(true,60);check(await until(func():return idle() and bridge.world.paused),"pause restores a stable command review state")
		await create_timer(.45).timeout
		inspector.close()
		var request:=payload("food")
		var id: String=bridge.queue_command("intervene",request)
		feedback._process(0)
		check(feedback.pulse_count==0 and feedback.banner.text.contains("PENDING"),"pending command has interface status without a landmark pulse")
		check(await until(idle),"fresh intervention durably acknowledged")
		check(feedback.pulse_count==1 and feedback.pulse>0,"new accepted ACK pulses satellite lens and tower axis once")
		check(city.satellite_signal.material_override!=city.kit.materials.cyan and city.command_signal.material_override!=city.kit.materials.cyan,"pulse materials are isolated from city lights")
		await shot("accepted-feedback")
		var revision: int=bridge.world.revision
		bridge.queue_command("intervene",request) # Old task context under a new UUID rejects.
		check(await until(idle),"conflicting command returns its durable outcome")
		check(bridge.intervention_result.outcome=="rejected" and feedback.pulse_count==1 and feedback.pulse==0 and not bridge.fatal,"rejection has interface feedback without a success pulse")
		await shot("rejected-feedback")
		bridge.pending.append({"v":1,"type":"intervene","id":id,"payload":request});bridge.save_journal()
		check(await until(idle),"original accepted receipt replay acknowledged")
		check(feedback.pulse_count==1 and feedback.recorded_result and bridge.world.revision>revision,"replayed stale receipt neither pulses again nor overwrites newer state")
		var backend: int=bridge.backend_pid
		OS.execute("/bin/kill",PackedStringArray(["-KILL",str(backend)]))
		check(await until(func():return idle() and bridge.backend_pid!=backend),"backend reconnect restores command state")
		check(feedback.pulse_count==1 and feedback.pulse==0,"reconnect welcome remains silent")
		inspector.open_control_room();room.load_history(false)
		check(await until(func():return room.request_id.is_empty()),"audit refresh after recovery")
		await shot("audit-history")
		var file:=FileAccess.open(probe_path,FileAccess.WRITE);file.store_string(JSON.stringify({"world_id":bridge.world.world_id,"command":c().intervention.id},"",true,true));file.close()
		if capture:
			var baseline:=await measure(false);var enabled:=await measure(true)
			var measurements:={"renderer":RenderingServer.get_current_rendering_method(),"resolution":[root.size.x,root.size.y],"population":bridge.world.citizens.size(),"sample_seconds_each":4,"closed":baseline,"control_room":enabled}
			var out:=FileAccess.open("res://../docs/previews/stage4d/performance.json",FileAccess.WRITE);out.store_string(JSON.stringify(measurements,"  "));out.close()
			check(enabled.feed_updates_per_second<=10.5 and baseline.feed_updates_per_second==0,"measured feed work is capped and stops when closed")
	else:
		var probe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe_path))
		check(bridge.world.world_id==probe.world_id and c().intervention.id==probe.command,"app relaunch restores the same active intervention")
		check(feedback.pulse_count==0,"app relaunch does not replay landmark feedback")
	print("STAGE4D_CHECK ",phase," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
