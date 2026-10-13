extends SceneTree
var city: Node3D
var bridge: Node
var failures: Array[String]=[]
var phase:="write"
var probe:=""
var capture:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures.append(label)
func idle() -> bool:return bridge.restored and bridge.connected and bridge.pending.is_empty() and city.population.restored
func until(predicate: Callable, seconds:=40.0) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe=arg.trim_prefix("--probe=")
	capture="--capture-stage6d" in OS.get_cmdline_user_args()
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation
	check(await until(func():return idle() and city.population.navigation.ready_for_paths),"retired sequence, compact legacy receipt and fresh pending request reconcile through the real journal")
	if not idle():print("BRIDGE_ERROR ",bridge.last_error);quit(1);return
	bridge.last_view=bridge.now()+3600
	check(bridge.world.citizens.size()==50 and bridge.world.paused and bridge.world.clock_seconds==0,"retention preserves all 50 people and advances no offline/paused time")
	check(city.command_feedback.pulse_count==0,"historical compacted acknowledgement never pulses Brother Eye")
	var inspector: CanvasLayer=city.inspector
	inspector.open_control_room()
	var room: VBoxContainer=inspector.control_room
	check(await until(func():return room.request_id.is_empty() and not room.entries.is_empty()),"retained audit loads through the real paged query")
	check(room.retention_notice.text.contains("Older audit entries were pruned"),"control room explains the retained-history boundary")
	if capture:
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../docs/previews/stage6d/retention-notice.png")
	if phase=="write":
		var serial: int=int(bridge.world.command_serial)
		var command: String=bridge.queue_command("save",{})
		check(not command.is_empty() and int(bridge.pending[-1].serial)==serial+1,"fresh command continues the saved sequence after old journal reconciliation")
		check(await until(idle),"fresh sequenced command is durably acknowledged")
		check(int(bridge.world.command_serial)==serial+1,"sequence watermark advances exactly once")
		var old_pid: int=bridge.backend_pid
		OS.execute("/bin/kill",PackedStringArray(["-KILL",str(old_pid)]))
		check(await until(func():return idle() and bridge.backend_pid!=old_pid),"retention metadata and sequence survive an owned-backend crash")
		# Disconnect recovery intentionally queues a final physical progress batch.
		check(int(bridge.world.command_serial)>=serial+1 and bridge.last_serial==int(bridge.world.command_serial),"crash recovery preserves the committed sequence and reconciles queued movement")
		var f:=FileAccess.open(probe,FileAccess.WRITE)
		f.store_string(JSON.stringify({"world_id":bridge.world.world_id,"clock":bridge.world.clock_seconds,"serial":bridge.world.command_serial,"fresh_command":command,"identities":bridge.world.citizens.map(func(c):return c.id)},"",true,true));f.close()
	else:
		var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe))
		check(bridge.world.world_id==saved.world_id and bridge.world.clock_seconds==saved.clock,"app relaunch preserves city and clock after retention")
		check(int(bridge.world.command_serial)>=int(saved.serial) and bridge.world.citizens.map(func(c):return c.id)==saved.identities,"sequenced shutdown/relaunch preserves watermark and identities")
	print("STAGE6D_CHECK ",phase," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
