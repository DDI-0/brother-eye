extends SceneTree
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
func until(predicate: Callable, timeout:=35.0) -> bool:
	var end:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func idle() -> bool:return bridge.connected and bridge.restored and bridge.pending.is_empty() and pop.restored
func actor(index: int) -> Dictionary:return bridge.world.citizens[index]
func outcome(index: int, kind: String, subject: Variant=null) -> bool:
	return bridge.world.agent_history.any(func(e):return e.agent_id==actor(index).id and e.outcome==kind and (subject==null or e.subject_id==subject))
func shot(name: String) -> void:
	if not capture:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage5d/"+name+".png")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe=arg.trim_prefix("--probe=")
	capture="--capture-stage5d" in OS.get_cmdline_user_args()
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation;pop=city.population
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"real city restores all 34 bodies with four active policies")
	if not idle():quit(1);return
	bridge.last_view=bridge.now()+3600
	var inspector: CanvasLayer=city.inspector
	if phase=="write":
		var cores: Array=[]
		for c in bridge.world.citizens.slice(30):cores.append(c.exceptional.core)
		var starts: Dictionary={}
		for i in [30,31,32,33]:starts[i]=pop.units[actor(i).id].person.position
		bridge.set_clock(false,1)
		check(await until(func():return actor(32).exceptional.project is Dictionary and actor(32).exceptional.project.status=="delegated" and outcome(31,"verified",actor(0).id) and outcome(33,"completed",actor(1).id),50),"Martyr physically meets a voluntary helper and delegates one project request")
		bridge.set_clock(true,1);check(await until(func():return idle() and bridge.world.paused),"delegated project and helper claim durably paused")
		check(outcome(31,"verified",actor(0).id),"Attendant physically verifies information without social assistance")
		check(outcome(33,"completed",actor(1).id) and not outcome(33,"completed",actor(2).id),"Sovereign physically assists companion ahead of a more severe stranger")
		check(pop.units[actor(31).id].person.position.distance_to(starts[31])>2 and pop.units[actor(33).id].person.position.distance_to(starts[33])>2,"information and companion policies move actual bodies")
		var saved_project: Dictionary=actor(32).exceptional.project.duplicate(true) if actor(32).exceptional.project is Dictionary else {}
		var saved_action: Variant=actor(30).exceptional.action.duplicate(true) if actor(30).exceptional.action is Dictionary else null
		var frozen: float=bridge.world.clock_seconds
		# Viewers may close the inspector to watch the scene. Refresh intentionally
		# does nothing while hidden, so establish the UI state for each assertion.
		inspector.close()
		inspector.open_exceptional();inspector.select_person(actor(32).id);inspector.refresh()
		check(inspector.is_open() and inspector.selected_id==actor(32).id,"project inspection reopens after viewer closes the panel")
		check(inspector.body.text.contains("MARTYR · LOCAL POLICY") and inspector.body.text.contains("CIVIC PROJECT") and inspector.body.text.contains("Voluntary partner"),"inspection explains persistent project and voluntary partner")
		await shot("project")
		inspector.close()
		inspector.open_exceptional();inspector.select_person(actor(31).id);inspector.refresh()
		check(inspector.is_open() and inspector.selected_id==actor(31).id,"information inspection reopens with the correct resident")
		check(inspector.body.text.contains("ATTENDANT · LOCAL POLICY") and inspector.body.text.contains("VERIFIED INFORMATION"),"information strategy and verified facts are inspectable")
		await shot("information")
		var backend: int=bridge.backend_pid;OS.execute("/bin/kill",PackedStringArray(["-KILL",str(backend)]))
		check(await until(func():return idle() and bridge.backend_pid!=backend),"backend crash recovers coordinated work")
		check(actor(32).exceptional.project==saved_project and actor(30).exceptional.action==saved_action and bridge.world.clock_seconds==frozen,"project, helper claim and clock restore exactly without offline time")
		bridge.set_clock(false,1)
		check(await until(func():return outcome(30,"completed",actor(3).id),50),"voluntary helper physically arrives and completes the delegated task")
		check(await until(func():return actor(32).exceptional.project.outcomes.values().has("completed"),5),"project records real helper completion")
		bridge.set_clock(true,1);check(await until(func():return idle() and bridge.world.paused),"policy outcomes and project saved")
		check(pop.units[actor(30).id].person.position.distance_to(starts[30])>2,"accepted coordination requires actual helper travel")
		var stable:=true
		for i in 4:
			if actor(30+i).exceptional.core!=cores[i]:stable=false
		check(stable,"all four canonical cores remain unchanged through learning and restart")
		if capture:
			inspector.close();pop.follow=false;pop.navigation.set_follow(false)
			var camera:=Camera3D.new();camera.position=Vector3(-24,3,-28);camera.fov=65;city.add_child(camera);camera.look_at(Vector3(-18,1,-32));camera.make_current();pop.panel.hide();city.hud.hide();await shot("helper");camera.queue_free()
		pop.capture_progress();check(await until(idle),"final physical movement reports acknowledged")
		var file:=FileAccess.open(probe,FileAccess.WRITE);file.store_string(JSON.stringify({"clock":bridge.world.clock_seconds,"world_id":bridge.world.world_id,"agents":bridge.world.citizens.slice(30).map(func(c):return c.exceptional),"history":bridge.world.agent_history},"",true,true));file.close()
	else:
		var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe))
		check(bridge.world.world_id==saved.world_id and bridge.world.clock_seconds==saved.clock,"app relaunch preserves world and advances no offline time")
		check(bridge.world.citizens.slice(30).map(func(c):return c.exceptional)==saved.agents and bridge.world.agent_history==saved.history,"relaunch preserves facts, projects, relationships, policy state and unique outcomes")
	print("STAGE5D_CHECK %s failures=%d"%[phase,failures.size()])
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
