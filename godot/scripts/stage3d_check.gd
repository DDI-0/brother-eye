extends SceneTree
## End-to-end checks use an isolated fixture, never the user's city save.
var city: Node3D
var bridge: Node
var population: Node3D
var failures: Array[String] = []
var phase := "write"
var probe_path := ""
var preview_path := ""

func _initialize() -> void:
	call_deferred("run_check")

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:failures.append(message)

func until(predicate: Callable, timeout := 20.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false

func idle() -> bool:
	return bridge.connected and bridge.restored and bridge.pending.is_empty() and population.restored

func citizen() -> Dictionary:
	return bridge.world.citizens[0]

func pause_and_save() -> void:
	bridge.set_clock(true,60)
	check(await until(func():return idle() and bridge.world.paused),"pause acknowledged")
	await create_timer(.1).timeout
	bridge.save_now()
	check(await until(idle),"physical position and routine saved together")

func run_check() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe_path=arg.trim_prefix("--probe=")
		if arg.begins_with("--preview="):preview_path=arg.trim_prefix("--preview=")
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	bridge=city.simulation;population=city.population
	check(await until(func():return idle() and population.navigation.ready_for_paths),"service, civilian and collision routes ready")
	if not idle():quit(1);return
	city.explorer.set_capture(false)
	if phase=="write":
		var initial: Dictionary=citizen().duplicate(true)
		var start: Vector3=population.person.position
		await create_timer(.3).timeout
		check(population.person.position==start and citizen().needs==initial.needs and bridge.world.clock_seconds==17940,"pause freezes movement, needs and city clock")
		bridge.set_clock(false,60)
		check(await until(func():return citizen().activity=="eating"),"physical arrival starts eating at the known market")
		check(citizen().position[2]<-13 and population.person.position.distance_to(start)>1,"arrival follows actual walking rather than teleporting")
		check(await until(func():return citizen().needs.hunger<initial.needs.hunger-5),"eating reduces hunger using authoritative city time")
		check(await until(func():return citizen().goal.place=="work"),"recovery finishes then resumes the daily work routine")
		check(await until(func():return population.person.state=="TRAVELLING" and population.person.position.distance_to(Vector3(18,.12,-14))>1),"new routine destination drives physical navigation")
		await pause_and_save()
		var file:=FileAccess.open(probe_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"world":bridge.world,"position":[population.person.position.x,population.person.position.y,population.person.position.z]},"",true,true));file.close()
	elif phase=="read":
		var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe_path))
		var c: Dictionary=saved.world.citizens[0]
		check(bridge.world.world_id==saved.world.world_id and citizen().id==c.id,"relaunch restores one world and the same civilian identity")
		var restored_c: Dictionary=citizen().duplicate(true)
		# Orderly close captures one final movement report after the explicit save.
		restored_c.erase("motion_seq");var saved_c: Dictionary=c.duplicate(true);saved_c.erase("motion_seq")
		check(restored_c==saved_c and bridge.world.clock_seconds==saved.world.clock_seconds,"needs, routine, knowledge, memory and clock restore without offline advancement")
		check(population.person.position.distance_to(Vector3(saved.position[0],saved.position[1],saved.position[2]))<.001,"physical civilian position restores exactly")
		var pid: int=bridge.backend_pid
		bridge.socket.close(1000,"Civilian reconnect test")
		await create_timer(.3).timeout
		check(await until(idle),"socket interruption reconnects and drains movement journal")
		check(bridge.backend_pid==pid and citizen().id==c.id and population.get_child_count()>0,"reconnect preserves the existing citizen and service")
		population.capture_progress()
		var command_id: String=bridge.pending[-1].id
		OS.execute("/bin/kill",PackedStringArray(["-KILL",str(pid)]))
		await create_timer(.3).timeout
		check(await until(func():return idle() and bridge.backend_pid!=pid),"service crash recovers and replays pending civilian progress")
		check(citizen().id==c.id and citizen().goal==c.goal and citizen().needs==c.needs,"crash recovery retains identity, goal and needs")
		print("REPLAYED_COMMAND ",command_id)
	elif phase=="journal":
		population.capture_progress()
		var file:=FileAccess.open(probe_path+".seq",FileAccess.WRITE);file.store_string(str(population.motion_seq));file.close()
		check(FileAccess.file_exists(bridge.journal_path) and not bridge.pending.is_empty(),"civilian progress journaled before send")
		print("STAGE3D_CHECK journal failures=",failures.size())
		quit(0 if failures.is_empty() else 1);return
	elif phase=="replay":
		var seq:=int(FileAccess.get_file_as_string(probe_path+".seq"))
		check(citizen().motion_seq==seq,"interrupted frontend progress replays on next launch")
		check(bridge.pending.is_empty(),"civilian journal drains after acknowledgement")
	if not preview_path.is_empty():
		population.panel.show();population.navigation.follow=true;population.navigation.follow_camera.make_current();city.hud.hide()
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preview_path)
	print("STAGE3D_CHECK ",phase," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
