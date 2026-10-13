extends SceneTree
const Evaluation=preload("res://scripts/evaluation_view.gd")
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
func finding(code: String) -> Dictionary:
	for item in bridge.assessment.get("findings",[]):
		if item.citizen_id==c().id and item.code==code:return item
	return {}
func shot(name: String) -> void:
	if not capture:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage4e/"+name+".png")
func wall(pos: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.position=pos
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box
	body.add_child(shape);city.add_child(body);return body
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe_path=arg.trim_prefix("--probe=")
	capture="--capture-stage4e" in OS.get_cmdline_user_args()
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	bridge=city.simulation;pop=city.population;inspector=city.inspector
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"authoritative city and physical population restored")
	if not idle():quit(1);return
	bridge.last_view=bridge.now()+3600
	inspector.open_evaluation();inspector.select_person(c().id);inspector.refresh()
	if phase=="write":
		check(Evaluation.matches(bridge.assessment,bridge.world) and finding("high_hunger").get("priority")=="urgent","observe and evaluate actual urgent resident need")
		var report: Dictionary=bridge.assessment
		bridge.assessment=report.duplicate(true);bridge.assessment.source.tick=-1
		check(not Evaluation.matches(bridge.assessment,bridge.world),"stale assessment cannot stand in for current evidence")
		bridge.assessment=report
		inspector.city_mode=false;inspector.tabs.current_tab=5;inspector.refresh()
		var controls: VBoxContainer=inspector.interventions
		controls.reason.text="Stage 4E: verify safe market access"
		controls.destination.select(controls.place_keys.find("food"))
		var before: Dictionary=c().duplicate(true)
		controls.issue("assign_destination")
		check(controls.has_pending() and city.command_feedback.pulse_count==0,"explicit UI command is pending before acknowledged effect")
		check(await until(idle),"intervention durably accepted")
		check(c().position==before.position and c().needs==before.needs and city.command_feedback.pulse_count==1,"paused assignment preserves body and needs and pulses once")
		var command: String=c().intervention.id
		var request:={"world_id":bridge.world.world_id,"citizen_id":c().id,"expected_goal_id":before.goal.id,"expected_intervention_id":null,"action":"assign_destination","place":"park","reason":"Stale context must reject"}
		bridge.queue_command("intervene",request);check(await until(idle),"conflicting request acknowledged")
		check(bridge.intervention_result.outcome=="rejected" and c().intervention.id==command and not bridge.fatal,"conflict preserves the active override")
		var actor: CharacterBody3D=pop.units[c().id].person
		var start: Vector3=actor.position
		# Temporary fixture walls enclose the starting body, not a fake navigation report.
		var walls: Array[StaticBody3D]=[]
		walls.append(wall(start+Vector3(0,1,-1.5),Vector3(4,3,.4)))
		walls.append(wall(start+Vector3(0,1,1.5),Vector3(4,3,.4)))
		walls.append(wall(start+Vector3(-1.5,1,0),Vector3(.4,3,4)))
		walls.append(wall(start+Vector3(1.5,1,0),Vector3(.4,3,4)))
		await physics_frame;pop.navigation.rebuild();await pop.navigation.rebuilt
		inspector.close();pop.select_person(c().id);pop.follow=true;pop.navigation.set_follow(true)
		bridge.set_clock(false,1)
		check(await until(func():return c().intervention.status=="waiting_for_route"),"blocked live override reports physical route wait")
		check(c().activity!="eating" and actor.position.distance_to(start)<1 and not finding("route_wait").is_empty(),"blocked resident neither arrives falsely nor recovers; evaluation explains wait")
		await shot("blocked-follow")
		for body in walls:
			city.remove_child(body)
			body.queue_free()
		await process_frame;await physics_frame
		while pop.navigation.baking:await process_frame
		pop.navigation.rebuild();await pop.navigation.rebuilt
		check(await until(func():return c().intervention.status=="completed",50),"cleared obstruction permits real destination completion")
		check(actor.position.distance_to(start)>2 and c().activity=="eating","physical movement precedes the recovery activity")
		check(await until(func():return finding("high_hunger").get("response")=="recovering" and c().needs.hunger<92),"evaluation recognizes arrival and measured need recovery")
		bridge.set_clock(true,1);check(await until(func():return idle() and bridge.world.paused),"completed task paused durably")
		inspector.open_control_room();var room: VBoxContainer=inspector.control_room
		room.load_history(false);check(await until(func():return room.request_id.is_empty() and not room.entries.is_empty()),"control room retrieves committed consequence history")
		var outcomes: Array=[]
		for event in room.entries:outcomes.append(event.outcome)
		check("accepted" in outcomes and "rejected" in outcomes and "waiting_for_route" in outcomes and "completed" in outcomes,"audit connects command, conflict, route wait and physical completion")
		check(await until(func():return room.last_frame_tick==bridge.world.tick),"control-room feed confirms the paused city tick")
		room.refresh();await shot("completed-audit")
		bridge.connected=false;room.refresh();inspector.refresh()
		check(room.history_status.text.contains("LAST KNOWN") and room.feed.disabled,"offline control room marks retained evidence and freezes its camera")
		bridge.connected=true
		var backend: int=bridge.backend_pid
		OS.execute("/bin/kill",PackedStringArray(["-KILL",str(backend)]))
		check(await until(func():return idle() and bridge.backend_pid!=backend),"backend interruption restores held completed task")
		check(c().intervention.id==command and c().intervention.status=="completed" and city.command_feedback.pulse==0,"recovery preserves completed identity without historical pulse")
		pop.capture_progress();check(await until(idle),"final physical progress acknowledged before restore comparison")
		var file:=FileAccess.open(probe_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"world_id":bridge.world.world_id,"citizen":c().duplicate(true),"clock":bridge.world.clock_seconds},"",true,true));file.close()
	else:
		var probe: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe_path))
		var restored: Dictionary=c().duplicate(true);var saved: Dictionary=probe.citizen
		# Graceful close sends one final physical report with a new sequence number.
		restored.erase("motion_seq");saved.erase("motion_seq")
		check(bridge.world.world_id==probe.world_id and restored==saved,"close/relaunch preserves identity, needs, physical position, goal and held override")
		check(bridge.world.clock_seconds==probe.clock and bridge.world.paused,"relaunch advances no offline time")
		check(city.command_feedback.pulse_count==0,"relaunch does not replay historical landmark effects")
	print("STAGE4E_CHECK ",phase," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
