extends SceneTree
## Live review capture; does not replace the separate performance benchmark.
var city: Node3D
var bridge: Node
var camera: Camera3D
var title: Label
var subtitle: Label
var frames_dir:=""
var target_id:=""
var seat_id:=""
var recording:=false
var capture_busy:=false
var frames: Array=[]
var chapter:=""
var chapters: Array=[]
var started:=0
func _initialize() -> void:call_deferred("run")
func until(predicate: Callable,seconds:=35.0) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func idle() -> bool:return bridge.restored and bridge.connected and bridge.pending.is_empty() and city.population.restored
func segment(label: String,detail: String) -> void:
	chapter=label;title.text=label;subtitle.text=detail
	chapters.append({"title":label,"elapsed_seconds":float(Time.get_ticks_usec()-started)/1000000})
func record_frames() -> void:
	capture_busy=true
	var next:=Time.get_ticks_usec()
	while recording:
		await process_frame
		if Time.get_ticks_usec()<next:continue
		await RenderingServer.frame_post_draw
		var timestamp:=Time.get_ticks_usec()
		var name:="frame-%06d.jpg"%frames.size()
		var error:=root.get_texture().get_image().save_jpg(frames_dir+"/"+name,.91)
		if error!=OK:push_error("video frame write failed");quit(1);return
		frames.append({"name":name,"time":float(timestamp-started)/1000000})
		next+=41667
		if timestamp-next>41667:next=timestamp+41667
	capture_busy=false
func hold(seconds: float) -> void:await create_timer(seconds).timeout
func glide(position: Vector3,aim: Vector3,seconds: float,offset:=Vector3.ZERO) -> void:
	var begin:=Time.get_ticks_msec()
	while float(Time.get_ticks_msec()-begin)/1000<seconds:
		var t:=clampf(float(Time.get_ticks_msec()-begin)/1000/seconds,0,1)
		camera.position=position+offset*t;camera.look_at(aim)
		await process_frame
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames-dir="):frames_dir=arg.trim_prefix("--frames-dir=")
		if arg.begins_with("--target-id="):target_id=arg.trim_prefix("--target-id=")
		if arg.begins_with("--seat-id="):seat_id=arg.trim_prefix("--seat-id=")
	if frames_dir.is_empty():push_error("frames directory required");quit(1);return
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation
	if not await until(func():return idle() and city.population.navigation.ready_for_paths):push_error("review restore failed");quit(1);return
	Engine.max_fps=30;city.hud.hide();city.explorer.set_capture(false);bridge.last_view=bridge.now()+3600
	camera=Camera3D.new();camera.far=1800;city.add_child(camera);camera.make_current()
	var hud:=CanvasLayer.new();hud.layer=30;root.add_child(hud)
	var panel:=PanelContainer.new();panel.position=Vector2(24,14);panel.custom_minimum_size=Vector2(1392,0);hud.add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.015,.035,.06,.94);style.set_content_margin_all(12);panel.add_theme_stylebox_override("panel",style)
	var text:=VBoxContainer.new();panel.add_child(text)
	title=Label.new();title.add_theme_font_size_override("font_size",23);text.add_child(title)
	subtitle=Label.new();subtitle.add_theme_font_size_override("font_size",16);text.add_child(subtitle)
	var clock_start: float=bridge.world.clock_seconds
	started=Time.get_ticks_usec();recording=true
	segment("NEON PROVIDENCE · STAGE 6E REVIEW","Disposable 100-resident city · 91 civilians / 5 police / 4 Exceptional Agents · Opening view paused")
	camera.position=Vector3(64,112,185);camera.look_at(Vector3(0,59,-62));record_frames()
	await glide(Vector3(64,112,185),Vector3(0,59,-62),5,Vector3(12,0,0))
	var inspector: CanvasLayer=city.inspector
	inspector.open_interventions();inspector.select_person(target_id)
	var controls: VBoxContainer=inspector.interventions
	controls.reason.text="Final review: direct resident to their known market destination"
	controls.destination.select(controls.place_keys.find("food"))
	segment("01 · NEON PROVIDENCE DESTINATION COMMAND","Existing intervention controls · Durable acknowledgement · Authority held until explicit release")
	await hold(2);controls.issue("assign_destination")
	if not await until(func():return idle() and city.population.units[target_id].record.intervention!=null):push_error("video intervention failed");quit(1);return
	await hold(3);inspector.close()
	bridge.set_clock(false,1)
	if not await until(func():return idle() and not bridge.world.paused):quit(1);return
	var actor: CharacterBody3D=city.population.units[target_id].person
	var begin_position:=actor.position
	segment("02 · PHYSICAL TRAVEL","Simulation running at 1× · Collision and navigation active · Camera follows the commanded resident")
	var end:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<end:
		camera.position=actor.position+Vector3(-signf(actor.position.x)*4,2.2,4.5);camera.look_at(actor.position+Vector3(0,1,0))
		await process_frame
	if not await until(func():return city.population.units[target_id].record.intervention.status=="completed",12):push_error("recorded command did not physically complete");quit(1);return
	if actor.position.distance_to(begin_position)<1:push_error("recorded travel had no displacement");quit(1);return
	segment("03 · COMMITTED RESULT AND LIVE CAMERA","Real scene camera feed · Accepted command and physical completion appear in the audit")
	inspector.open_control_room();inspector.control_room.feed.select(1);inspector.control_room.set_feed(1)
	await hold(7);inspector.close()
	segment("04 · RELEASE TO AUTONOMY","Explicit release ends the held override · The resident resumes their own needs and schedule")
	inspector.open_interventions();inspector.select_person(target_id)
	controls.reason.text="Final review: release the completed destination override"
	await hold(2);controls.issue("release")
	if not await until(func():return idle() and city.population.units[target_id].record.intervention==null):push_error("review release failed");quit(1);return
	await hold(2);inspector.close()
	segment("05 · DISTRICT LIFE","Residents follow independent schedules and local needs · Resting residents do not need to move continuously")
	await glide(Vector3(-16,3.8,-12),Vector3(0,1,-38),7,Vector3(0,0,-5))
	var seated: CharacterBody3D=city.population.units[seat_id].person
	segment("06 · PURPOSEFUL REST","A resident physically reaches a bench and uses the supplied seated animation")
	if not await until(func():return seated.player.current_animation=="sit_idle",15):push_error("review bench pose missing");quit(1);return
	await glide(seated.position+Vector3(-signf(seated.position.x)*4,1.7,2.5),seated.position+Vector3(0,.85,0),6)
	segment("07 · EXCEPTIONAL AGENTS","Four persistent identities · Independent local policies · Core ideologies stay immutable")
	inspector.open_exceptional();await hold(6);inspector.close()
	segment("STAGE 6E · NATIVE CITY REVIEW","100 physical residents · Current world persists across restart · Recording is separate from uncapped performance measurements")
	await glide(Vector3(76,112,185),Vector3(0,59,-62),7,Vector3(-12,3,0))
	recording=false
	while capture_busy:await process_frame
	var file:=FileAccess.open(frames_dir+"/frames.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":frames,"chapters":chapters,"elapsed_seconds":float(Time.get_ticks_usec()-started)/1000000,"simulated_seconds":bridge.world.clock_seconds-clock_start,"population":bridge.world.citizens.size(),"viewport":str(root.size),"scope":"Live rendered frames with wall-clock timestamps; silent review of a disposable acceptance fixture, real commands and body motion. Performance measured separately."},"  "));file.close()
	print("STAGE6E_VIDEO frames=",frames.size()," failures=0")
	bridge.request_quit()
