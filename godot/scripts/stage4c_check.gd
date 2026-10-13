extends SceneTree
var city: Node3D
var bridge: Node
var pop: Node3D
var inspector: CanvasLayer
var failures: Array[String]=[]
var phase:="write"
var probe_path:=""
var capture:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func idle() -> bool:return bridge.connected and bridge.restored and pop.restored and bridge.pending.is_empty()
func until(predicate: Callable,timeout:=30.0) -> bool:
	var end:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func c() -> Dictionary:return bridge.world.citizens[0]
func payload(place: String) -> Dictionary:
	var active = c().get("intervention")
	return {"world_id":bridge.world.world_id,"citizen_id":c().id,"expected_goal_id":c().goal.id,
		"expected_intervention_id":active.id if active is Dictionary else null,"action":"assign_destination","place":place,"reason":"Isolated Stage 4C review"}
func shot(name: String) -> void:
	if not capture:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage4c/"+name+".png")
func save_probe(data: Dictionary) -> void:
	var file:=FileAccess.open(probe_path,FileAccess.WRITE);file.store_string(JSON.stringify(data,"",true,true));file.close()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe_path=arg.trim_prefix("--probe=")
	capture="--capture-interventions" in OS.get_cmdline_user_args()
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation;pop=city.population;inspector=city.inspector
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"live city and intervention journal restore")
	if not idle():quit(1);return
	check(inspector.is_open() and inspector.tabs.current_tab==5 and not inspector.city_mode,"intervention launcher opens command controls")
	bridge.last_view=bridge.now()+3600
	inspector.open();inspector.city_mode=false;inspector.select_person(c().id);inspector.tabs.current_tab=5;inspector.refresh()
	var controls: VBoxContainer=inspector.interventions
	if phase=="write":
		check(controls.visible and controls.assign_button.disabled,"explicit reason required before command")
		var before: Dictionary=c().duplicate(true)
		bridge.connected=false;controls.reason.text="Review market access";inspector.refresh()
		check(controls.assign_button.disabled and controls.release_button.disabled,"offline action controls disabled")
		bridge.connected=true;inspector.refresh()
		controls.destination.select(controls.place_keys.find("food"));controls.issue("assign_destination")
		check(controls.has_pending() and controls.result.text.contains("PENDING"),"one-shot intervention durably queued with pending status")
		check(await until(idle),"override acknowledgement received")
		check(c().goal.reason=="intervention" and c().goal.place=="food" and c().position==before.position and c().needs==before.needs,"paused command changes goal without teleporting or resetting needs")
		inspector.refresh();await shot("destination-override")
		var stale:=payload("home")
		bridge.queue_command("intervene",payload("park"));check(await until(idle),"replacement accepted")
		var replacement: String=c().goal.id
		bridge.queue_command("intervene",stale);check(await until(idle),"stale command acknowledged as rejection")
		check(bridge.intervention_result.outcome=="rejected" and not bridge.fatal and c().goal.id==replacement,"conflict rejects cleanly without freezing service")
		inspector.refresh();await shot("rejected-command")
		controls.reason.text="Release reviewed override";controls.issue("release");check(await until(idle),"release acknowledged")
		check(c().intervention==null and c().goal.reason!="intervention","autonomy restored with a fresh goal")
		bridge.queue_command("intervene",payload("food"));check(await until(idle),"physical travel override accepted")
		var command: String=c().intervention.id
		var backend: int=bridge.backend_pid
		OS.execute("/bin/kill",PackedStringArray(["-KILL",str(backend)]))
		check(await until(func():return idle() and bridge.backend_pid!=backend),"backend interruption restores durable override")
		check(c().intervention.id==command,"override identity survives backend restart")
		var start: Vector3=pop.units[c().id].person.position
		bridge.set_clock(false,60)
		check(await until(func():return c().intervention.status=="completed"),"physical route arrives and completes destination task")
		bridge.set_clock(true,60);check(await until(func():return idle() and bridge.world.paused),"completed override paused and saved")
		var actor: CharacterBody3D=pop.units[c().id].person
		check(actor.position.distance_to(start)>2 and c().activity=="eating","actual body movement precedes eating and completion")
		check(c().intervention.id==command and c().goal.reason=="intervention","completed override remains held until release")
		inspector.refresh();await shot("completed-override")
		save_probe({"world_id":bridge.world.world_id,"command":command,"goal":c().goal.id,"clock":bridge.world.clock_seconds})
	elif phase=="read":
		var probe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe_path))
		check(bridge.world.world_id==probe.world_id and c().intervention.id==probe.command and c().goal.id==probe.goal,"same city and completed override restored after app close")
		check(c().intervention.status=="completed" and bridge.world.clock_seconds==probe.clock,"no offline time or override expiry")
		check(inspector.body.text.contains("COMPLETED") and inspector.body.text.contains("RECENT COMMAND"),"saved outcomes visible in intervention history")
	elif phase=="journal":
		var request:=payload("park")
		var id: String=bridge.queue_command("intervene",request)
		save_probe({"command":id})
		check(FileAccess.get_file_as_string(bridge.journal_path).contains(id),"intervention written to pending journal before frontend interruption")
		print("STAGE4C_CHECK ",phase," failures=",failures.size());quit(0 if failures.is_empty() else 1);return
	elif phase=="replay":
		var probe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe_path))
		check(c().intervention.id==probe.command and c().goal.place=="park","frontend interruption replays the same command identity")
		check(bridge.pending.is_empty(),"replayed intervention removed only after acknowledgement")
		controls.reason.text="Return to routine";controls.issue("release");check(await until(idle),"replayed override can be released")
		check(c().intervention==null,"autonomy restored after journal recovery")
	print("STAGE4C_CHECK ",phase," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
