extends Node
## Owns one local service process; durable requests survive disconnects and retries.
signal changed
signal session_observed(state: Dictionary)
signal intervention_acknowledged(result: Dictionary, current: bool)
signal history_received(payload: Dictionary, request_id: String)
var queries: Dictionary = {}
var city: Node3D
var assessment: Dictionary = {}
var intervention_result: Dictionary = {}
var player: CharacterBody3D
var world: Dictionary = {}
var status := "Starting city…"
var connected := false
var restored := false
var last_error := ""
var backend_pid := -1
var socket: WebSocketPeer
var token := ""
var ready_path := ""
var db_path := ""
var journal_path := ""
var python_path := ""
var population_tier := 0
var last_serial := 0
var service_path := ""
var pending: Array = []
var active_id := ""
var expected_world_id := ""
var journal_loaded := false
var journal_ok := true
var hello_sent := false
var fatal := false
var retries := 0
var next_connect := 0.0
var next_health := 0.0
var started_at := 0.0
var last_view := 0.0
var last_heartbeat := 0.0
var last_sent := 0.0
var quitting := false
var quit_started := 0.0
var shutdown_id := ""
var panel: CanvasLayer

func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func identifier() -> String:
	var raw := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [raw.substr(0,8), raw.substr(8,4), raw.substr(12,4), raw.substr(16,4), raw.substr(20,12)]

func setup(owner_city: Node3D) -> void:
	city = owner_city
	player = city.explorer
	var root_path := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	python_path = root_path.path_join(".venv/bin/python")
	service_path = root_path.path_join("backend/service.py")
	db_path = root_path.path_join("runtime/world.sqlite3")
	for arg in OS.get_cmdline_user_args():
		if arg=="--population-tier=1":population_tier=1
		if arg=="--population-tier=2":population_tier=2
		if arg.begins_with("--world-db="):
			db_path = arg.trim_prefix("--world-db=")
	DirAccess.make_dir_recursive_absolute(db_path.get_base_dir())
	token = Crypto.new().generate_random_bytes(32).hex_encode()
	ready_path = db_path.get_base_dir().path_join("session-" + identifier() + ".json")
	journal_path = db_path + ".pending.json"
	get_tree().auto_accept_quit = false
	panel = preload("res://scripts/simulation_panel.gd").new()
	add_child(panel)
	panel.setup(self)
	city.hud.attach_simulation(self)
	start_service()

func start_service() -> void:
	if not FileAccess.file_exists(python_path) or not FileAccess.file_exists(service_path):
		fail("Python setup is missing. See docs/STAGE_2.md.")
		return
	DirAccess.remove_absolute(ready_path)
	socket = null
	connected = false
	restored = false
	hello_sent = false
	active_id = ""
	shutdown_id = ""
	started_at = now()
	next_connect = now() + 0.2
	backend_pid = OS.create_process(python_path, PackedStringArray([service_path, "--db", db_path, "--ready", ready_path, "--owner-pid", str(OS.get_process_id()), "--token", token, "--population-tier", str(population_tier)]))
	if backend_pid < 0:
		fail("Could not start the city service.")
	else:
		status = "Starting city…" if world.is_empty() else "Recovering city…"
	changed.emit()

func fail(message: String) -> void:
	fatal = true
	connected = false
	last_error = message
	status = message
	changed.emit()

func retry() -> void:
	if backend_pid > 0 and OS.is_process_running(backend_pid):
		return
	fatal = false
	journal_loaded = false
	retries = 0
	last_error = ""
	start_service()

func _process(_delta: float) -> void:
	if city == null:
		return
	var time := now()
	player.paused_input = not connected or not restored or panel.is_open() or quitting or (city.inspector!=null and city.inspector.is_open())
	if socket != null:
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if not hello_sent:
				hello_sent = true
				send_message("hello", {"token": token}, identifier())
			while socket.get_available_packet_count() > 0:
				receive_message(socket.get_packet().get_string_from_utf8())
			if connected:
				if time - last_heartbeat > 1.0:
					send_message("heartbeat", {}, "")
					last_heartbeat = time
				if restored and not quitting and time - last_view > 1.0:
					queue_command("set_explorer", player.saved_view())
					last_view = time
				flush_pending()
		elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			if connected:
				status = "Reconnecting…"
				changed.emit()
			connected = false
			hello_sent = false
			active_id = ""
			socket = null
			next_connect = time + 0.5
	if quitting and time - quit_started > 6.0:
		# Unacknowledged edits remain in the atomic local journal for the next launch.
		if save_journal():
			get_tree().quit()
		return
	if time < next_health or fatal:
		return
	next_health = time + 0.2
	var service_running := backend_pid > 0 and OS.is_process_running(backend_pid)
	if FileAccess.file_exists(ready_path):
		var ready = JSON.parse_string(FileAccess.get_file_as_string(ready_path))
		if ready is Dictionary and int(ready.get("pid", -1)) == backend_pid:
			if ready.has("error"):
				fail(str(ready.error))
				return
			if socket == null and time >= next_connect and service_running:
				socket = WebSocketPeer.new()
				socket.inbound_buffer_size = 2097152
				socket.outbound_buffer_size = 262144
				var error := socket.connect_to_url("ws://127.0.0.1:%d" % int(ready.port))
				if error != OK:
					socket = null
					next_connect = time + 1.0
	if backend_pid > 0 and not service_running:
		backend_pid = -1
		connected = false
		if retries < 3 and not quitting:
			retries += 1
			start_service()
		else:
			fail("City service stopped. Retry to recover the saved city.")
	elif time - started_at > 15.0 and not connected:
		fail("City service did not connect. See runtime/service.log.")

func send_message(kind: String, payload: Dictionary, command_id: String, serial: Variant=null) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var message: Dictionary={"v":1,"type":kind,"id":command_id,"payload":payload}
		if serial!=null:message.serial=serial
		socket.send_text(JSON.stringify(message, "", true, true))

func receive_message(raw: String) -> void:
	var message = JSON.parse_string(raw)
	if not message is Dictionary or int(message.get("v", 0)) != 1:
		fail("Unsupported city service response.")
		return
	var kind: String = message.get("type", "")
	var payload: Dictionary = message.get("payload", {})
	if kind == "welcome":
		world = payload.state
		last_serial=maxi(last_serial,int(world.get("command_serial",0)))
		queries.clear()
		session_observed.emit(world)
		assessment=payload.get("assessment",{})
		if not journal_loaded:
			load_journal()
			journal_loaded = true
		if fatal:
			return
		if not expected_world_id.is_empty() and expected_world_id != str(world.world_id):
			fail("Pending changes belong to a different city. Existing saves are preserved.")
			return
		expected_world_id = str(world.world_id)
		connected = true
		last_error = ""
		status = "Restoring city…"
		active_id = ""
		restore_if_ready()
	elif kind == "snapshot":
		apply_world(payload.state,payload.get("assessment",{}))
	elif kind == "ack":
		if payload.has("intervention"):
			intervention_result=payload.intervention
		if str(message.id) == shutdown_id and quitting:
			if not pending.is_empty() and str(pending[0].id)==str(message.id):pending.pop_front()
			if not save_journal():return
			get_tree().quit()
			return
		apply_world(payload.state,payload.get("assessment",{}))
		if payload.has("intervention") and not pending.is_empty() and str(pending[0].id)==str(message.id) and pending[0].type=="intervene":
			intervention_acknowledged.emit(payload.intervention,payload.state==world and not payload.get("receipt_retired",false))
		if not pending.is_empty() and str(pending[0].id) == str(message.id):
			pending.pop_front()
			active_id = ""
			save_journal()
			status = "Saved"
			restore_if_ready()
	elif kind == "intervention_history":
		if queries.has(str(message.id)):
			queries.erase(str(message.id));history_received.emit(payload,str(message.id))
	elif kind == "error":
		if payload.get("code","")=="receipt_retired" and not pending.is_empty() and str(pending[0].id)==str(message.id) and payload.get("state",{}).get("world_id","")==expected_world_id and pending[0].has("serial") and int(pending[0].serial)<=int(payload.state.get("command_serial",0)):
			apply_world(payload.state,payload.get("assessment",{}));pending.pop_front();active_id=""
			if not save_journal():return
			status="Historical command reconciled with saved state; detailed receipt retired."
			if str(message.id)==shutdown_id and quitting:get_tree().quit();return
			restore_if_ready();changed.emit();return
		if queries.has(str(message.id)):
			queries.erase(str(message.id));history_received.emit({"error":payload.get("message","History unavailable")},str(message.id))
			return
		fail("City change could not be saved: " + str(payload.get("message", "Unknown error")))
	changed.emit()

func apply_world(state: Dictionary, evaluation: Dictionary={}) -> void:
	if world.is_empty() or int(state.revision) > int(world.revision) or (int(state.revision) == int(world.revision) and int(state.tick) >= int(world.tick)):
		world = state
		assessment=evaluation

func restore_if_ready() -> void:
	if not restored and pending.is_empty() and connected:
		if world.get("explorer") is Dictionary:
			player.restore_view(world.explorer)
		restored = true
		player.paused_input = false
		status = "Saved city restored" if world.get("explorer") is Dictionary else "City ready"
		changed.emit()

func queue_command(kind: String, payload: Dictionary) -> String:
	var command_id := ""
	# Coalesce unsent view/movement updates; never change a request already sent under an ID.
	if kind in ["set_explorer", "set_citizen_progress", "set_population_progress"] and not pending.is_empty() and pending[-1].type == kind and str(pending[-1].id) != active_id:
		pending[-1].payload = payload
		command_id = str(pending[-1].id)
	else:
		last_serial=maxi(last_serial,int(world.get("command_serial",0)))+1
		var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256)
		hashing.update((expected_world_id+":"+str(last_serial)).to_utf8_buffer())
		var bytes:=hashing.finish().slice(0,16);bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128
		var raw:=bytes.hex_encode()
		command_id="%s-%s-%s-%s-%s"%[raw.substr(0,8),raw.substr(8,4),raw.substr(12,4),raw.substr(16,4),raw.substr(20,12)]
		pending.append({"v": 1, "type": kind, "id": command_id, "serial":last_serial,"payload": payload})
	if not save_journal():
		return ""
	return command_id

func flush_pending() -> void:
	if not connected or fatal:
		return
	if not journal_ok and not save_journal():
		return
	if pending.is_empty():
		if quitting and shutdown_id.is_empty():
			shutdown_id=queue_command("shutdown",{"explorer":player.saved_view()})
		return
	if active_id.is_empty() or now() - last_sent > 2.0:
		var command: Dictionary = pending[0]
		active_id = str(command.id)
		send_message(str(command.type), command.payload, active_id,command.get("serial"))
		last_sent = now()

func save_journal() -> bool:
	journal_ok = false
	if expected_world_id.is_empty():
		journal_ok = true
		return true
	var temporary := journal_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Could not save pending changes. Check available disk space."
		status = last_error
		changed.emit()
		return false
	file.store_string(JSON.stringify({"world_id": expected_world_id, "last_serial":last_serial,"commands": pending}, "", true, true))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, journal_path) != OK:
		last_error = "Could not commit pending changes to disk."
		status = last_error
		changed.emit()
		return false
	journal_ok = true
	return true

func load_journal() -> void:
	if not FileAccess.file_exists(journal_path):
		return
	var stored = JSON.parse_string(FileAccess.get_file_as_string(journal_path))
	if not stored is Dictionary or not stored.get("commands") is Array or not stored.get("world_id") is String:
		fail("Pending changes could not be read. The journal has been preserved.")
		return
	var previous_serial:=0
	for command in stored.commands:
		if not command is Dictionary or command.get("v") != 1 or not command.get("id") is String or not command.get("payload") is Dictionary or not command.get("type") in ["set_explorer", "set_clock", "set_citizen_progress", "set_population_progress", "intervene", "save","shutdown"]:
			fail("Pending changes are invalid. The journal has been preserved.")
			return
		if command.has("serial"):
			if not command.serial is float and not command.serial is int:fail("Invalid pending command sequence.");return
			if command.serial!=floor(command.serial) or command.serial<=previous_serial or command.serial>9007199254740991:fail("Invalid pending command sequence.");return
			previous_serial=int(command.serial);last_serial=maxi(last_serial,previous_serial)
			command.serial=previous_serial
	if stored.has("last_serial"):
		if not (stored.last_serial is float or stored.last_serial is int) or stored.last_serial<0 or stored.last_serial!=floor(stored.last_serial) or stored.last_serial>9007199254740991:fail("Invalid journal sequence counter.");return
		last_serial=maxi(last_serial,int(stored.last_serial))
	expected_world_id = stored.world_id
	pending = stored.commands

func query_history(target: String, cursor: Dictionary={}) -> String:
	if not connected or not restored or quitting:return ""
	var id:=identifier()
	queries[id]=true
	send_message("query_interventions",{"citizen_id":target,"before_seq":cursor.get("before_seq",0),"before_index":cursor.get("before_index",0),"limit":25},id)
	return id

func set_clock(paused: bool, speed: float) -> void:
	if connected and restored:
		queue_command("set_clock", {"paused": paused, "time_scale": speed})

func save_now() -> void:
	if connected and restored:
		if city.population != null:city.population.capture_progress()
		queue_command("set_explorer", player.saved_view())
		queue_command("save", {})
		status = "Saving…"
		changed.emit()

func request_quit() -> void:
	if quitting:
		return
	if restored:
		if city.population != null:city.population.capture_progress()
		queue_command("set_explorer", player.saved_view())
	quitting = true
	quit_started = now()
	player.set_capture(false)
	status = "Saving and closing…"
	changed.emit()
	if fatal and pending.is_empty():
		get_tree().quit()

func clock_text() -> String:
	if world.is_empty():
		return "CITY CLOCK  ·  " + status
	var seconds := int(float(world.clock_seconds)) + 8 * 3600
	return "DAY %03d  /  %02d:%02d:%02d  ·  %s  ·  %s" % [seconds / 86400 + 1, (seconds / 3600) % 24, (seconds / 60) % 60, seconds % 60, "PAUSED" if world.paused else "%d×" % int(world.time_scale), status]

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and city != null:
		request_quit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		panel.toggle()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if socket != null:
		socket.close(1000, "Application closing")
	# The service watches this process; force-closing Godot cannot leave a daemon.
