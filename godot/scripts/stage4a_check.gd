extends SceneTree
const Model=preload("res://scripts/inspection_model.gd")
var failures: Array[String]=[]
var city: Node3D
var bridge: Node
var pop: Node3D
var inspector: CanvasLayer
var phase:="write"
var probe:=""
var capture:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func until(predicate: Callable, timeout:=25.0) -> bool:
	var end:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func idle() -> bool:return bridge.connected and bridge.restored and bridge.pending.is_empty() and pop.restored
func screenshot(name: String) -> void:
	if not capture:return
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage4a/"+name+".png")
func key(code: Key) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=true;Input.parse_input_event(event)
	await process_frame
	var release:=InputEventKey.new();release.keycode=code;release.pressed=false;Input.parse_input_event(release)
	await process_frame
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe=arg.trim_prefix("--probe=")
		if arg=="--capture-inspection":capture=true
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation;pop=city.population;inspector=city.inspector
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"inspection and 34 residents restore from the actual service")
	if not idle():quit(1);return
	check(inspector.is_open(),"inspection review launcher opens the resident inspector")
	inspector.close()
	city.explorer.set_capture(false)
	var alex_id: String=bridge.world.citizens[0].id
	if phase=="write":
		bridge.set_clock(false,60)
		check(await until(func():return bridge.world.citizens[0].activity=="eating"),"physical arrival creates an inspectable memory")
		bridge.set_clock(true,60)
		check(await until(func():return idle() and bridge.world.paused),"city pause acknowledged")
		bridge.save_now();check(await until(idle),"inspection fixture saved")
	else:
		var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe))
		var current: Dictionary=Model.inspect(bridge.world,alex_id).citizen
		var restored:=true
		for field in ["id","name","role","kind","appearance","needs","known_places","schedule","goal","activity","navigation","memory","last_decision_at"]:
			if current[field]!=saved[field]:restored=false;print("RESTORE_DIFF ",field)
		for axis in 3:
			if absf(current.position[axis]-saved.position[axis])>.000001:restored=false
		check(restored,"inspection restores the same resident, knowledge, schedule and history")
	# Isolate read-only inspection from the existing periodic explorer autosave.
	bridge.last_view=bridge.now()+3600
	var before: Dictionary=bridge.world.duplicate(true)
	var detached:=Model.inspect(bridge.world,alex_id)
	detached.citizen.needs.energy=0;detached.citizen.known_places.clear();detached.citizen.memory.clear()
	check(bridge.world==before,"inspection projection cannot mutate nested simulation state")
	check(Model.inspect(bridge.world,"missing").is_empty() and Model.roster({}).is_empty(),"unknown identity and empty snapshot are handled")
	await key(KEY_F5)
	check(inspector.is_open() and city.explorer.paused_input,"F5 opens inspection and suspends camera movement")
	check(inspector.rows.size()==34 and inspector.view.citizen.id==alex_id,"roster contains all 34 residents with stable identity selection")
	var camera_before: Vector3=city.explorer.observer_camera.position
	Input.action_press("forward");await create_timer(.1).timeout;Input.action_release("forward")
	check(city.explorer.observer_camera.position==camera_before,"holding movement keys while inspecting leaves the explorer camera still")
	check(inspector.view.citizen==bridge.world.citizens[0],"all displayed resident data comes from the confirmed snapshot")
	await screenshot("overview")
	inspector.tabs.current_tab=1;inspector.refresh()
	check(inspector.body.text.contains("4 PLACES") and inspector.body.text.contains("Residential promenade"),"civilian knowledge page contains their four actual places")
	await screenshot("knowledge")
	inspector.tabs.current_tab=2;inspector.refresh()
	check(inspector.body.text.contains("08:00") and inspector.body.text.contains("Observatory terrace"),"schedule shows recorded hours and destinations")
	inspector.tabs.current_tab=3;inspector.refresh()
	check(inspector.body.text.contains("ARRIVAL") and inspector.body.text.contains("Go to food (need)"),"history shows recorded arrival and destination decisions")
	await screenshot("history")
	inspector.decisions.button_pressed=true;inspector.refresh()
	check(not inspector.body.text.contains("ARRIVAL") and inspector.body.text.contains("DECISION"),"decision filter excludes other memory kinds")
	inspector.kind.select(2);inspector.refresh()
	check(inspector.rows.size()==5,"police filter returns five officers")
	var officer_id: String=inspector.rows[0].id
	inspector.select_person(officer_id);inspector.tabs.current_tab=1;inspector.refresh()
	check(inspector.view.citizen.kind=="police" and inspector.body.text.contains("7 PLACES"),"police selection shows their additional local patrol knowledge")
	await screenshot("police")
	inspector.kind.select(0);inspector.search.text="observatory technician";inspector.refresh()
	check(inspector.rows.size()==1 and inspector.rows[0].id==alex_id,"search matches role without changing identity")
	inspector.search.text="no such resident";inspector.refresh()
	check(inspector.rows.is_empty() and inspector.count.text.contains("No matches") and inspector.view.citizen.id==officer_id,"empty search preserves the inspected resident")
	inspector.search.text="";inspector.refresh()
	inspector.select_person(alex_id);inspector.tabs.current_tab=0;inspector.refresh()
	check(bridge.pending.is_empty() and bridge.world==before,"browsing and filtering inspection issues no simulation commands")
	var connected: bool=bridge.connected
	bridge.connected=false;inspector.refresh()
	check(inspector.status.text.contains("LAST KNOWN") and inspector.follow_button.disabled,"disconnection marks retained data stale and disables follow")
	bridge.connected=connected;inspector.refresh()
	inspector.follow_selected()
	check(not inspector.is_open() and pop.follow and pop.navigation.pedestrian==pop.units[alex_id].person,"follow opens the selected resident's existing camera")
	await key(KEY_F5)
	check(not pop.navigation.can_control_follow(),"inspection blocks follow orbit and movement")
	var offset: Vector3=pop.navigation.follow_offset
	var pan:=InputEventPanGesture.new();pan.delta=Vector2(20,20);Input.parse_input_event(pan);await process_frame
	check(pop.navigation.follow_offset==offset,"touchpad scrolling in inspection does not orbit the camera")
	await key(KEY_ESCAPE)
	check(not inspector.is_open() and pop.navigation.can_control_follow(),"Escape closes inspection and restores follow controls")
	await key(KEY_F5);await key(KEY_F2)
	check(not inspector.is_open() and bridge.panel.is_open(),"City time opens cleanly from inspection")
	bridge.panel.panel.hide()
	check(bridge.world==before and bridge.pending.is_empty(),"inspection and camera controls leave the saved simulation untouched")
	if phase=="write":
		var file:=FileAccess.open(probe,FileAccess.WRITE);file.store_string(JSON.stringify(bridge.world.citizens[0],"",true,true));file.close()
	print("STAGE4A_CHECK ",phase," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
