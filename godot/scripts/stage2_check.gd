extends SceneTree
## Real frontend/service acceptance check. Run twice with the same isolated DB.
var city: Node3D
var bridge: Node
var failures: Array[String] = []
var phase := "write"
var probe_path := ""
var preview_path := ""

func _initialize() -> void:
	call_deferred("run_check")

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func until(predicate: Callable, timeout := 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(0.05).timeout
	return false

func idle() -> bool:
	return bridge.connected and bridge.restored and bridge.pending.is_empty()

func run_check() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="): probe_path = arg.trim_prefix("--probe=")
		if arg.begins_with("--preview="): preview_path = arg.trim_prefix("--preview=")
	city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	bridge = city.simulation
	if not await until(func(): return idle() or bridge.fatal):
		check(false, "frontend connects within deadline")
		quit(1)
		return
	check(idle(), "frontend connects and restores: " + bridge.status)
	if not idle(): quit(1); return
	city.explorer.set_capture(false)
	if phase == "write":
		city.explorer.position = Vector3(0, 0.3, 80)
		city.explorer.rotation.y = 0.2
		city.explorer.ground_camera.rotation.x = -0.1
		city.explorer.observer_camera.position = Vector3(90, 140, 170)
		city.explorer.observer_camera.rotation = Vector3(-0.3, 0.5, 0)
		city.explorer.flight_speed = 42
		city.explorer.observing = true
		city.explorer.observer_camera.make_current()
		bridge.set_clock(true, 10)
		bridge.save_now()
		check(await until(idle), "clock and explorer edits acknowledged")
		var file := FileAccess.open(probe_path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"world": bridge.world, "pid": bridge.backend_pid}))
		file.close()
	elif phase == "journal":
		city.explorer.rotation.y = 0.12345678901234567
		bridge.set_clock(true, 10)
		bridge.queue_command("set_explorer", city.explorer.saved_view())
		check(FileAccess.file_exists(bridge.journal_path), "unacknowledged edits journaled before sending")
		print("STAGE2_CHECK journal failures=", failures.size())
		# Abrupt frontend exit deliberately bypasses Save & Quit.
		quit(0 if failures.is_empty() else 1)
		return
	elif phase == "replay":
		check(bridge.world.time_scale == 10 and bridge.world.paused, "new app replays prior app's pending clock edit")
		check(abs(city.explorer.rotation.y - 0.12345678901234567) < 0.000001, "pending camera edit survives frontend interruption")
		var journal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bridge.journal_path))
		check(journal.commands.is_empty(), "acknowledged journal drained after replay")
	elif phase == "ground":
		check(not city.explorer.observing and city.explorer.ground_camera.current, "ground mode restored on third launch")
		check(is_equal_approx(city.explorer.rotation.y, 0.2) and is_equal_approx(city.explorer.ground_camera.rotation.x, -0.1), "ground look direction restored")
		check(bridge.world.paused and bridge.world.time_scale == 60, "recovered clock setting persists on third launch")
	else:
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(probe_path)).world
		check(bridge.world.world_id == saved.world_id, "relaunch preserves world identity")
		check(is_equal_approx(bridge.world.clock_seconds, saved.clock_seconds), "closed application adds no simulation time")
		check(bridge.world.paused and bridge.world.time_scale == 10, "pause and speed restored")
		check(city.explorer.position.distance_to(Vector3(0,0.3,80)) < 0.02, "ground position restored while observing")
		check(city.explorer.observing and city.explorer.observer_camera.current, "observer mode restored")
		check(city.explorer.observer_camera.position.distance_to(Vector3(90,140,170)) < 0.02 and city.explorer.flight_speed == 42, "flight position and speed restored")
		var pid: int = bridge.backend_pid
		bridge.socket.close(1000, "Reconnect test")
		await create_timer(0.2).timeout
		check(await until(idle), "frontend reconnects after socket interruption")
		check(bridge.backend_pid == pid and bridge.world.world_id == saved.world_id, "reconnect reuses the same service and world")
		# Journal an edit, kill before it is sent, recover and replay exactly once.
		bridge.set_clock(true, 60)
		var request_id: String = str(bridge.pending[-1].id)
		# External failure leaves Godot's child tracking intact, like a real crash.
		OS.execute("/bin/kill", PackedStringArray(["-KILL", str(bridge.backend_pid)]))
		await create_timer(0.3).timeout
		check(await until(func(): return idle() and bridge.world.time_scale == 60), "service crash recovers queued edit")
		check(bridge.backend_pid != pid and bridge.world.world_id == saved.world_id, "crash recovery retains one world")
		print("REPLAYED_COMMAND ", request_id)
		# Restore a ground view too; the third launch verifies that camera mode.
		city.explorer.observing = false
		city.explorer.ground_camera.make_current()
		bridge.save_now()
		check(await until(idle), "ground camera saved")
	if not preview_path.is_empty():
		city.explorer.set_view(0)
		bridge.panel.toggle()
		await create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preview_path)
	print("STAGE2_CHECK ", phase, " failures=", failures.size())
	if not failures.is_empty():
		quit(1)
	else:
		bridge.request_quit()
