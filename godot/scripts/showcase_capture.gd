extends SceneTree
## Live camera/caption orchestration only; backend owns all decisions and effects.
var city: Node3D
var bridge: Node
var camera: Camera3D
var title: Label
var subtitle: Label
var status: Label
var frames_dir:=""
var mode:="city"
var seat_id:=""
var recording:=false
var busy:=false
var frames: Array=[]
var samples: Array=[]
var started:=0
var chapter:=""
var next_sample:=0
func _initialize() -> void:call_deferred("run")
func idle() -> bool:return bridge.connected and bridge.restored and bridge.pending.is_empty() and city.population.restored
func until(predicate: Callable,seconds:=35.0) -> bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		if bridge.fatal:push_error(bridge.last_error);quit(1);return false
		await create_timer(.05).timeout
	return false
func heading(a: String,b: String) -> void:title.text=a;subtitle.text=b;chapter=a
func c(index: int) -> Dictionary:return bridge.world.citizens[index]
func body(index: int) -> CharacterBody3D:return city.population.units[c(index).id].person
func event(index: int,kind: String,subject: int) -> bool:
	return bridge.world.agent_history.any(func(e):return e.agent_id==c(index).id and e.outcome==kind and e.subject_id==c(subject).id)
func complete() -> bool:
	if mode=="arbiter":return event(30,"completed",0)
	if mode=="attendant":return event(31,"verified",0)
	if mode=="sovereign":return event(33,"completed",1)
	return c(32).exceptional.project is Dictionary and c(32).exceptional.project.outcomes.values().has("completed") and event(30,"completed",3)
func capture_frames() -> void:
	busy=true
	var next:=Time.get_ticks_usec()
	while recording:
		await process_frame
		if bridge.fatal:push_error("showcase stopped: "+bridge.last_error);quit(1);return
		if Time.get_ticks_usec()<next:continue
		await RenderingServer.frame_post_draw
		var timestamp:=Time.get_ticks_usec()
		var name:="frame-%06d.jpg"%frames.size()
		if root.get_texture().get_image().save_jpg(frames_dir+"/"+name,.9)!=OK:push_error("capture write failed");quit(1);return
		frames.append({"name":name,"time":float(timestamp-started)/1000000})
		next+=55556
		if timestamp-next>55556:next=timestamp+55556
		if timestamp>next_sample:
			next_sample=timestamp+1000000
			samples.append({"time":float(timestamp-started)/1000000,"clock":bridge.world.clock_seconds,"chapter":chapter,"history_count":bridge.world.agent_history.size(),"connected":bridge.connected})
	busy=false
func glide(position: Vector3,aim: Vector3,seconds: float,offset:=Vector3.ZERO) -> void:
	var begin:=Time.get_ticks_msec()
	while float(Time.get_ticks_msec()-begin)/1000<seconds:
		var t:=clampf(float(Time.get_ticks_msec()-begin)/1000/seconds,0,1)
		camera.position=position+offset*t;camera.look_at(aim)
		await process_frame
func follow(index: int,seconds: float) -> void:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		var actor:=body(index)
		camera.position=actor.position+Vector3(-signf(actor.position.x)*5,2.5,5)
		camera.look_at(actor.position+Vector3(0,1,0))
		await process_frame
func follow_crowd(seconds: float) -> void:
	var best:=0;var best_count:=-1
	for i in bridge.world.citizens.size():
		if c(i).kind!="civilian" or not body(i).active:continue
		var nearby:=0
		for unit in city.population.units.values():
			if absf(unit.person.position.y-body(i).position.y)<2 and unit.person.position.distance_to(body(i).position)<15:nearby+=1
		if nearby>best_count:best_count=nearby;best=i
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		var actor:=body(best)
		camera.position=actor.position+Vector3(signf(actor.position.x)*7,3.5,-7)
		camera.look_at(actor.position+Vector3(0,1,0))
		status.text="Following %s's physical commute · Independent crowd routines continue"%c(best).name
		await process_frame
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames-dir="):frames_dir=arg.trim_prefix("--frames-dir=")
		if arg.begins_with("--showcase-mode="):mode=arg.trim_prefix("--showcase-mode=")
		if arg.begins_with("--seat-id="):seat_id=arg.trim_prefix("--seat-id=")
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation
	if not await until(func():return idle() and city.population.navigation.ready_for_paths):push_error("showcase restore failed");quit(1);return
	Engine.max_fps=30;city.hud.hide();city.inspector.close();city.explorer.set_capture(false);bridge.last_view=bridge.now()+3600
	camera=Camera3D.new();camera.far=1800;camera.fov=65 if mode=="city" else 58;city.add_child(camera);camera.make_current()
	var layer:=CanvasLayer.new();layer.layer=30;root.add_child(layer)
	var panel:=PanelContainer.new();panel.position=Vector2(24,14);panel.custom_minimum_size=Vector2(1392,0);layer.add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.015,.035,.06,.93);style.set_content_margin_all(12);panel.add_theme_stylebox_override("panel",style)
	var content:=VBoxContainer.new();panel.add_child(content)
	title=Label.new();title.add_theme_font_size_override("font_size",24);content.add_child(title)
	subtitle=Label.new();subtitle.add_theme_font_size_override("font_size",16);content.add_child(subtitle)
	status=Label.new();status.add_theme_font_size_override("font_size",15);content.add_child(status)
	status.text="Live disposable review world · Existing models and local decision policies · Saved city untouched"
	var cores: Array=bridge.world.citizens.filter(func(p):return p.kind=="exceptional").map(func(p):return p.exceptional.core)
	var starts: Dictionary={}
	for id in city.population.units:starts[id]=city.population.units[id].person.position
	var clock_start: float=bridge.world.clock_seconds
	var actor_index: int={"arbiter":30,"attendant":31,"martyr":32,"sovereign":33}.get(mode,30)
	if mode=="city":
		heading("BROTHER EYE · A LIVING CITY","50 residents · Skyline, streets, elevated terraces and purposeful routines")
		camera.position=Vector3(64,112,185);camera.look_at(Vector3(0,59,-62))
	else:
		var names:={"arbiter":"ARBITER OF DAWN · FAIR LOCAL ASSISTANCE","attendant":"ATTENDANT OF MYSTERIES · VERIFYING LOCAL INFORMATION","martyr":"MARTYR OF PROVIDENCE · VOLUNTARY CIVIC COORDINATION","sovereign":"SOVEREIGN OF UNBOUND WILL · COMPANION PRIORITY"}
		heading(names[mode],"Staged 34-resident review world · Decisions, physical travel and outcomes run live at 1×")
		camera.position=body(actor_index).position+Vector3(signf(body(actor_index).position.x)*5,2.5,-5);camera.look_at(body(actor_index).position+Vector3(0,1,0))
	started=Time.get_ticks_usec();recording=true;capture_frames()
	await create_timer(3).timeout
	bridge.set_clock(false,1)
	if not await until(func():return idle() and not bridge.world.paused):quit(1);return
	if mode=="city":
		await glide(Vector3(64,112,185),Vector3(0,59,-62),15,Vector3(-28,2,0))
		heading("THE DISTRICT · LANDMARKS AND TRANSIT RINGS","Original city composition · Brother Eye satellite remains above the authority tower")
		await glide(Vector3(-70,65,130),Vector3(0,48,-40),15,Vector3(30,5,-10))
		heading("STREET LIFE · EVERYDAY RESIDENTS","Independent schedules, local needs, physical routes and crowd avoidance")
		await follow_crowd(12)
		heading("ELEVATED CITY · SKYWALK AND TERRACES","Ground-level streets connect to the elevated district through physical stairs")
		await glide(Vector3(34,18,45),Vector3(0,12,10),10,Vector3(-8,0,-5))
		var seated: CharacterBody3D=city.population.units[seat_id].person
		if not await until(func():return seated.player.current_animation=="sit_idle",15):push_error("seated routine missing");quit(1);return
		heading("PURPOSEFUL REST · BENCH LIFE","Resting residents use the supplied sitting animation while others continue their routines")
		await glide(seated.position+Vector3(-signf(seated.position.x)*4,1.7,2.5),seated.position+Vector3(0,.85,0),10)
		var police: int=bridge.world.citizens.find_custom(func(p):return p.kind=="police")
		heading("DISTRICT PATROL","Police follow district patrol routines · No crime-enforcement system is claimed")
		await follow(police,8)
		city.inspector.open_evaluation();heading("BROTHER EYE · CITY ASSESSMENT","Read-only needs assessment · Explicit destination commands follow later in this showcase")
		await create_timer(8).timeout;city.inspector.close()
	else:
		var began:=Time.get_ticks_msec();var end:=began+65000
		while Time.get_ticks_msec()<end and not complete():
			var focus:=actor_index
			if mode=="martyr" and c(32).exceptional.project is Dictionary and c(32).exceptional.project.status=="delegated":focus=30
			var actor:=body(focus)
			var goal: Dictionary=c(focus).goal
			var aim:=actor.position+Vector3(0,1,0)
			var action: Variant=c(focus).exceptional.action
			if action is Dictionary and action.subject_id!=null and city.population.units.has(action.subject_id):
				aim=(actor.position+city.population.units[action.subject_id].person.position)*.5+Vector3(0,1,0)
			camera.position=aim+Vector3(signf(aim.x)*5,1.8,-5);camera.look_at(aim)
			status.text="%s · %s · %s"%[c(focus).name,c(focus).navigation,str(action.kind if action is Dictionary else "observing").capitalize()]
			if mode=="martyr" and focus==30:status.text+=" · Voluntary helper travelling to the recipient"
			await process_frame
		if not complete():push_error("expected live policy outcome missing: "+mode);quit(1);return
		if mode=="arbiter" and body(30).position.distance_to(starts[c(30).id])<2:push_error("assistance did not require travel");quit(1);return
		bridge.set_clock(true,1)
		if not await until(idle):quit(1);return
		heading(title.text,"CONFIRMED OUTCOME · Physical approach and local interaction completed · Paused for inspection")
		status.text="Outcome below is read from the authoritative simulation, not a scripted reward"
		await create_timer(maxf(3.0,23.0-float(Time.get_ticks_msec()-began)/1000)).timeout
		city.inspector.open_exceptional();city.inspector.select_person(c(actor_index).id);city.inspector.refresh()
		await create_timer(7).timeout
	if cores!=bridge.world.citizens.filter(func(p):return p.kind=="exceptional").map(func(p):return p.exceptional.core):push_error("core changed");quit(1);return
	recording=false
	while busy:await process_frame
	var moved:=0
	for id in starts:
		if city.population.units[id].person.position.distance_to(starts[id])>1:moved+=1
	var file:=FileAccess.open(frames_dir+"/capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":frames,"samples":samples,"mode":mode,"population":bridge.world.citizens.size(),"clock_seconds":bridge.world.clock_seconds-clock_start,"moved_over_1m":moved,"expected_outcome_verified":mode=="city" or complete(),"cores_unchanged":true,"agent_history":bridge.world.agent_history,"agents":bridge.world.citizens.filter(func(p):return p.kind=="exceptional"),"scope":"Real-time rendered capture from a disposable staged world; backend policies and Godot bodies produce outcomes. No production save access."},"  ",true,true));file.close()
	print("SHOWCASE_CAPTURE ",mode," frames=",frames.size()," failures=0")
	bridge.request_quit()
