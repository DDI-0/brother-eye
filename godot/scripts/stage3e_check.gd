extends SceneTree
var city: Node3D
var bridge: Node
var pop: Node3D
var failures: Array[String]=[]
var phase:="write"
var probe:=""
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func until(predicate: Callable,timeout:=25.0) -> bool:
	var end:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func idle() -> bool:return bridge.connected and bridge.restored and pop.restored and bridge.pending.is_empty()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--probe="):probe=arg.trim_prefix("--probe=")
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation;pop=city.population
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"population and shared navigation restored")
	if not idle():quit(1);return
	check(pop.units.size()==34 and pop.navigation.people.size()==34,"34 bodies use one navigation map")
	var police:=0
	var meshes: Dictionary={}
	var animation_ids: Dictionary={}
	for c in bridge.world.citizens:
		if c.kind=="police":police+=1
		var actor: CharacterBody3D=pop.units[c.id].person
		check(actor.crowd and actor.agent.avoidance_enabled,"crowd avoidance enabled: "+c.name)
		animation_ids[actor.player.get_animation("walk").get_instance_id()]=true
		for mesh in actor.model.find_children("*","MeshInstance3D",true,false):meshes[mesh.mesh.get_instance_id()]=true
	check(police==5,"25 civilians and 5 police")
	check(animation_ids.size()==2 and meshes.size()<=60,"animation and mesh resources shared within civilian and astronaut models")
	if phase=="write":
		var map: RID=pop.navigation.get_world_3d().navigation_map
		var bad: Array=[]
		for c in bridge.world.citizens:
			var origin:=Vector3(c.position[0],c.position[1],c.position[2])
			for key in c.known_places:
				var p: Array=c.known_places[key].position
				var target:=Vector3(p[0],p[1],p[2])
				var nearest:=NavigationServer3D.map_get_closest_point(map,target)
				var path:=NavigationServer3D.map_get_path(map,origin,nearest,true)
				if nearest.distance_to(target)>.8 or path.is_empty() or path[-1].distance_to(nearest)>.6:bad.append(c.name+" / "+key)
		check(bad.is_empty(),"every local destination has a complete physical route: "+str(bad))
		bridge.set_clock(false,1)
		check(await until(func():return not bridge.world.paused and idle()),"population resumes")
		var start: Dictionary={}
		for id in pop.order:start[id]=pop.units[id].person.position
		# Fixed-FPS headless mode accelerates physics, while networking remains real.
		var moving_gap:=100.0
		var arrived_once: Dictionary={}
		for i in 12000:
			await physics_frame
			if i%60==0:
				for a in pop.order.size():
					for b in range(a+1,pop.order.size()):
						var pa: Vector3=pop.units[pop.order[a]].person.position
						var pb: Vector3=pop.units[pop.order[b]].person.position
						if absf(pa.y-pb.y)<1:moving_gap=minf(moving_gap,Vector2(pa.x-pb.x,pa.z-pb.z).length())
				# Autonomous agents may begin a new visit before the last resident
				# arrives. Require a real completed trip per person, not simultaneity.
				for id in pop.order:
					if pop.units[id].person.state=="ARRIVED" and pop.units[id].person.position.distance_to(start[id])>1:arrived_once[id]=true
				if arrived_once.size()==34:break
		var moved:=0;var arrived:=0;var min_gap:=100.0
		for id in pop.order:
			var actor: CharacterBody3D=pop.units[id].person
			if actor.position.distance_to(start[id])>1:moved+=1
			if arrived_once.has(id):arrived+=1
			else:print("STILL_TRAVELLING ",pop.units[id].record.name," state=",actor.state," position=",actor.position," target=",actor.destination)
			for other_id in pop.order:
				if other_id==id:continue
				var other: CharacterBody3D=pop.units[other_id].person
				if absf(other.position.y-actor.position.y)<1:min_gap=minf(min_gap,Vector2(other.position.x-actor.position.x,other.position.z-actor.position.z).length())
		check(moved>=20,"residents travel throughout the district (%d moved)"%moved)
		check(arrived==34,"each resident completes a physical trip (%d arrived)"%arrived)
		check(min_gap>.42,"residents remain separated (minimum %.3f m)"%min_gap)
		check(moving_gap>.42,"crowd keeps body clearance throughout travel (minimum %.3f m)"%moving_gap)
		print("POPULATION_METRICS moved=",moved," arrived=",arrived," min_gap=",min_gap)
		bridge.set_clock(true,1)
		check(await until(func():return idle() and bridge.world.paused),"population pause acknowledged")
		await create_timer(.1).timeout
		pop.capture_progress();bridge.save_now();check(await until(idle),"all 34 movement states saved atomically")
		var file:=FileAccess.open(probe,FileAccess.WRITE);file.store_string(JSON.stringify(bridge.world,"",true,true));file.close()
		pop.select_relative(29);check(pop.record.kind=="police","follow selection reaches police")
		pop.select_relative(5);check(pop.selected==0,"selection wraps back to Alex")
	elif phase=="read":
		var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(probe))
		check(bridge.world.world_id==saved.world_id and bridge.world.clock_seconds==saved.clock_seconds,"same world and clock restored with no offline time")
		var all_restored:=true
		for c in saved.citizens:
			var current: Dictionary=pop.units[c.id].record
			# JSON decimal conversion can change the last binary bit; compare spatial values below at submillimetre tolerance.
			for key in ["id","kind","appearance","goal","needs","memory","schedule","known_places"]:
				if current[key]!=c[key]:all_restored=false;print("RESTORE_DIFF ",c.name," ",key," saved=",c[key]," actual=",current[key])
			if absf(current.yaw-c.yaw)>.000001:all_restored=false
			for axis in 3:
				if absf(current.position[axis]-c.position[axis])>.000001:all_restored=false
			var actor: CharacterBody3D=pop.units[c.id].person
			if actor.position.distance_to(Vector3(c.position[0],c.position[1],c.position[2]))>.001:all_restored=false
		check(all_restored,"all 34 identities, positions, appearance, needs and routines restore")
		pop.capture_progress()
		var request_id: String=bridge.pending[-1].id
		var pid: int=bridge.backend_pid
		OS.execute("/bin/kill",PackedStringArray(["-KILL",str(pid)]));await create_timer(.3).timeout
		check(await until(func():return idle() and bridge.backend_pid!=pid),"population batch replays after backend interruption")
		check(pop.units.size()==34 and pop.navigation.people.size()==34,"recovery creates no duplicate bodies")
		print("REPLAYED_COMMAND ",request_id)
	elif phase=="journal":
		pop.capture_progress()
		var file:=FileAccess.open(probe+".seq",FileAccess.WRITE);file.store_string(str(pop.motion_seq));file.close()
		quit(0);return
	elif phase=="replay":
		check(pop.motion_seq==int(FileAccess.get_file_as_string(probe+".seq")),"population journal survives frontend interruption")
	print("STAGE3E_CHECK ",phase," failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
