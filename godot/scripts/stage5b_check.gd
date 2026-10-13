extends SceneTree
const Model=preload("res://scripts/inspection_model.gd")
var city: Node3D
var bridge: Node
var pop: Node3D
var inspector: CanvasLayer
var failures: Array[String]=[]
var phase:="write"
var legacy_path:=""
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
func agents() -> Array:return bridge.world.citizens.filter(func(c):return c.kind=="exceptional")
func issue(c: Dictionary,action: String,place) -> void:
	bridge.queue_command("intervene",{"world_id":bridge.world.world_id,"citizen_id":c.id,"expected_goal_id":c.goal.id,"expected_intervention_id":c.intervention.id if c.intervention is Dictionary else null,"action":action,"place":place,"reason":"Stage 5B foundation review"})
func shot(name: String) -> void:
	if not capture:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage5b/"+name+".png")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe_path=arg.trim_prefix("--probe=")
		if arg.begins_with("--legacy="):legacy_path=arg.trim_prefix("--legacy=")
	capture="--capture-stage5b" in OS.get_cmdline_user_args()
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	bridge=city.simulation;pop=city.population;inspector=city.inspector
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"migration and journal replay restore the physical city")
	if not idle():quit(1);return
	bridge.last_view=bridge.now()+3600
	check(bridge.world.citizens.size()==34 and pop.units.size()==34 and pop.navigation.people.size()==34,"34 people share one navigation map without duplicate bodies")
	check(bridge.assessment.summary.population==34,"evaluation counts all 34 actual people")
	inspector.refresh()
	check(inspector.is_open() and inspector.kind.selected==4 and inspector.rows.size()==4,"Exceptional Agent launcher opens the four-person filter")
	var walk_ids: Dictionary={};var armor: Dictionary={};var missing: Array=[]
	for c in agents():
		var actor: CharacterBody3D=pop.units[c.id].person
		check(actor.model_path.ends_with("exceptional_agent.glb") and actor.body_height==2.0 and actor.agent.height==2.0 and actor.crowd,"astronaut model and physical crowd support: "+c.name)
		for clip in ["idle","walk","run","sit_down","sit_idle","stand_up"]:
			if not actor.player.has_animation(clip):missing.append(c.name+" / "+clip)
		walk_ids[actor.player.get_animation("walk").get_instance_id()]=true
		for mesh in actor.model.find_children("*","MeshInstance3D",true,false):
			for surface in mesh.mesh.get_surface_count():
				var mat: Material=mesh.get_active_material(surface)
				if mat.resource_name.begins_with("Helmet_Slate"):armor[mat.albedo_color.to_html()]=true
		inspector.select_person(c.id);inspector.tabs.current_tab=0;inspector.refresh()
		check(inspector.body.text.contains(c.exceptional.core) and inspector.body.text.contains(str(c.exceptional.behavior_stage).to_upper()+" · LOCAL"),"inspection distinguishes immutable core from unfinished behavior: "+c.name)
	check(missing.is_empty() and walk_ids.size()==1 and armor.size()==4,"six existing clips, shared astronaut animation and four armor palettes")
	inspector.kind.select(1);inspector.refresh();check(inspector.rows.size()==25,"civilian filter still has 25 residents")
	inspector.kind.select(2);inspector.refresh();check(inspector.rows.size()==5,"police filter still has five residents")
	inspector.kind.select(4);inspector.select_person(agents()[0].id);inspector.tabs.current_tab=0;inspector.refresh()
	await shot("inspection")
	if phase=="write":
		var legacy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(legacy_path))
		var preserved:=true
		for i in 30:
			if bridge.world.citizens[i]!=legacy.citizens[i]:preserved=false
		check(preserved and bridge.world.world_id==legacy.world_id and bridge.world.clock_seconds==legacy.clock_seconds,"migration preserves every original resident field and city clock")
		check(bridge.world.revision>legacy.revision and city.command_feedback.pulse_count==0,"old journal receipt cannot overwrite migrated population or replay a pulse")
		var map: RID=pop.navigation.get_world_3d().navigation_map
		var paths_ok:=true
		for c in agents():
			var origin:=Vector3(c.position[0],c.position[1],c.position[2])
			for place in c.known_places.values():
				var target:=Vector3(place.position[0],place.position[1],place.position[2])
				var nearest:=NavigationServer3D.map_get_closest_point(map,target)
				var path:=NavigationServer3D.map_get_path(map,origin,nearest,true)
				if nearest.distance_to(target)>.8 or path.is_empty() or path[-1].distance_to(nearest)>.6:paths_ok=false
		check(paths_ok,"all 16 Exceptional Agent destinations have physical routes")
		var cores: Dictionary={};var starts: Dictionary={}
		for c in agents():
			cores[c.id]=c.exceptional.duplicate(true);starts[c.id]=pop.units[c.id].person.position
			issue(c,"assign_destination","home")
		check(await until(idle),"four destination overrides durably accepted")
		check(agents().all(func(c):return c.goal.reason=="intervention" and c.exceptional==cores[c.id]),"paused authority leaves immutable cores and relationships unchanged")
		inspector.select_person(agents()[0].id);inspector.follow_selected()
		check(pop.follow and pop.navigation.can_control_follow(),"Exceptional Agent follow camera supports unlocked controls")
		var offset: Vector3=pop.navigation.follow_offset
		pop.navigation.orbit_follow(Vector2(20,5));check(offset!=pop.navigation.follow_offset,"touchpad orbit works with the astronaut")
		pop.navigation.reset_follow_view()
		bridge.set_clock(false,1)
		check(await until(func():return agents().all(func(c):return c.intervention.status=="completed"),80),"all four physically arrive before override completion")
		check(agents().all(func(c):return pop.units[c.id].person.position.distance_to(starts[c.id])>2 and c.exceptional==cores[c.id]),"astronauts move physically without altering their cores or directed bonds")
		bridge.set_clock(true,1);check(await until(func():return idle() and bridge.world.paused),"34-person physical progress and clock saved")
		if capture:
			inspector.close();pop.navigation.set_follow(false);pop.follow=false
			var camera:=Camera3D.new();camera.position=Vector3(-21,3.2,96);camera.fov=65;camera.far=1800;city.add_child(camera);camera.look_at(Vector3(-21,1.1,90));camera.make_current()
			pop.panel.hide();city.hud.hide()
			await shot("four-agents")
			city.hud.show()
			camera.queue_free();pop.navigation.set_follow(true);pop.follow=true
		# Release one, held completed overrides on the others must survive restore.
		issue(agents()[0],"release",null);check(await until(idle),"release restores a fresh foundation routine")
		check(agents()[0].intervention==null and agents()[0].exceptional==cores[agents()[0].id],"release changes task without changing identity/core")
		var backend: int=bridge.backend_pid
		OS.execute("/bin/kill",PackedStringArray(["-KILL",str(backend)]))
		check(await until(func():return idle() and bridge.backend_pid!=backend),"backend restart restores all 34 people")
		check(city.command_feedback.pulse==0,"historical overrides do not pulse after reconnect")
		pop.capture_progress();check(await until(idle),"final physical records acknowledged")
		var file:=FileAccess.open(probe_path,FileAccess.WRITE);file.store_string(JSON.stringify({"world_id":bridge.world.world_id,"clock":bridge.world.clock_seconds,"agents":agents()},"",true,true));file.close()
	else:
		var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe_path))
		var restored:=true
		for i in 4:
			var current: Dictionary=agents()[i].duplicate(true);var old: Dictionary=saved.agents[i]
			current.erase("motion_seq");old.erase("motion_seq");current.erase("physical_at");old.erase("physical_at")
			if current!=old:restored=false
		check(restored and bridge.world.world_id==saved.world_id and bridge.world.clock_seconds==saved.clock,"app relaunch preserves identities, cores, bonds, needs, goals and held overrides with no offline time")
		check(city.command_feedback.pulse_count==0,"app relaunch does not replay intervention effects")
	print("STAGE5B_CHECK ",phase," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
