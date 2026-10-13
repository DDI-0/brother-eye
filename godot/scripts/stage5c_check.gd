extends SceneTree
const Model=preload("res://scripts/inspection_model.gd")
var failures: Array[String]=[]
var city: Node3D
var bridge: Node
var pop: Node3D
var phase:="write"
var probe:=""
var capture:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func until(predicate: Callable, timeout:=30.0) -> bool:
	var end:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func idle() -> bool:return bridge.connected and bridge.restored and bridge.pending.is_empty() and pop.restored
func arbiter() -> Dictionary:return bridge.world.citizens[30]
func completions() -> Array:return bridge.world.get("agent_history",[]).filter(func(e):return e.outcome=="completed")
func shot(name: String) -> void:
	if not capture:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage5c/"+name+".png")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe=arg.trim_prefix("--probe=")
	capture="--capture-stage5c" in OS.get_cmdline_user_args()
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation;pop=city.population
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"34 physical residents restore through the actual service")
	if not idle():quit(1);return
	bridge.last_view=bridge.now()+3600
	var inspector: CanvasLayer=city.inspector
	if phase=="write":
		var initial: Vector3=pop.units[arbiter().id].person.position
		var core: String=arbiter().exceptional.core
		bridge.set_clock(false,1)
		check(await until(func():return arbiter().exceptional.action is Dictionary and arbiter().exceptional.action.kind=="assist"),"local sensing creates and claims a real assistance request")
		var action: Dictionary=arbiter().exceptional.action if arbiter().exceptional.action is Dictionary else {}
		check(action.get("subject_id")==bridge.world.citizens[0].id,"Arbiter selects the most severe local recipient")
		check(not arbiter().exceptional.observations.any(func(o):return o.subject_id==bridge.world.citizens[2].id),"distant higher need does not enter local knowledge")
		check(await until(func():return arbiter().navigation=="ARRIVED" and arbiter().exceptional.action is Dictionary and arbiter().exceptional.action.elapsed>=1,45),"astronaut physically arrives and begins the five-second dwell")
		check(pop.units[arbiter().id].person.position.distance_to(initial)>2,"assistance requires actual body movement")
		bridge.set_clock(true,1);check(await until(func():return idle() and bridge.world.paused),"pause during interaction is durable")
		var paused_action: Dictionary=arbiter().exceptional.action.duplicate(true) if arbiter().exceptional.action is Dictionary else {}
		var frozen: float=bridge.world.clock_seconds
		await create_timer(.6).timeout
		check(arbiter().exceptional.action==paused_action and bridge.world.clock_seconds==frozen and completions().is_empty(),"paused dwell cannot award assistance")
		inspector.select_person(arbiter().id);inspector.tabs.current_tab=0;inspector.refresh()
		check(inspector.body.text.contains("ARBITER · LOCAL ASSISTANCE") and inspector.body.text.contains("evidence") and inspector.body.text.contains("physical state ARRIVED"),"inspection explains evidence, policy and physical action")
		await shot("inspection")
		var backend: int=bridge.backend_pid
		OS.execute("/bin/kill",PackedStringArray(["-KILL",str(backend)]))
		check(await until(func():return idle() and bridge.backend_pid!=backend),"backend crash restores the in-progress claim")
		check(arbiter().exceptional.action==paused_action and bridge.world.clock_seconds==frozen,"claim, partial dwell and paused clock survive restart exactly")
		bridge.set_clock(false,1)
		check(await until(func():return completions().size()==1,20),"resumed physical interaction completes once")
		bridge.set_clock(true,1);check(await until(func():return idle() and bridge.world.paused),"completed state saved")
		var event: Dictionary=completions()[0] if not completions().is_empty() else {}
		check(absf(event.get("before_social",0)-event.get("after_social",0)-5)<.000001,"one bounded social effect follows actual dwell")
		check(arbiter().exceptional.relationships.get(bridge.world.citizens[0].id,{}).get("trust")==1 and arbiter().exceptional.core==core,"cooperation learns trust without changing the core")
		check(bridge.world.citizens.slice(31).all(func(c):return c.exceptional.behavior_stage in ["attendant","martyr","sovereign"]),"other three have their own active policies")
		inspector.close();pop.follow=false;pop.navigation.set_follow(false)
		if capture:
			var camera:=Camera3D.new();camera.position=Vector3(23,3,-10);camera.fov=65;city.add_child(camera);camera.look_at(Vector3(18,1,-14));camera.make_current()
			pop.panel.hide();city.hud.hide();await shot("assistance");camera.queue_free()
		pop.capture_progress();check(await until(idle),"final physical state acknowledged")
		var file:=FileAccess.open(probe,FileAccess.WRITE);file.store_string(JSON.stringify({"clock":bridge.world.clock_seconds,"world_id":bridge.world.world_id,"exceptional":arbiter().exceptional,"history":bridge.world.agent_history},"",true,true));file.close()
	else:
		var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe))
		check(bridge.world.world_id==saved.world_id and bridge.world.clock_seconds==saved.clock,"relaunch restores identity with no offline time")
		check(arbiter().exceptional==saved.exceptional and bridge.world.agent_history==saved.history and completions().size()==1,"relaunch preserves evidence, learning and exactly one consequence")
		inspector.select_person(arbiter().id);inspector.refresh();check(inspector.body.text.contains("COMPLETED"),"completed outcome remains inspectable after relaunch")
	print("STAGE5C_CHECK %s failures=%d"%[phase,failures.size()])
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
