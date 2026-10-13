extends SceneTree
var city: Node3D
func _initialize() -> void:call_deferred("run")
func until(predicate: Callable) -> bool:
	var end:=Time.get_ticks_msec()+35000
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func run() -> void:
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	var bridge: Node=city.simulation
	if not await until(func():return bridge.restored and city.population.restored and city.population.navigation.ready_for_paths):
		push_error("Stage6A restore timeout");quit(1);return
	bridge.last_view=bridge.now()+3600
	bridge.set_clock(false,1)
	if not await until(func():return bridge.pending.is_empty() and not bridge.world.paused):quit(1);return

	# Warmup so simulation advances and positions settle into their organic spots
	await create_timer(3.0).timeout
	var camera:=Camera3D.new();city.add_child(camera);camera.make_current()

	DirAccess.make_dir_absolute("res://../docs/previews/stage6a")

	# Hide HUD for clean cinematic screenshots
	if is_instance_valid(city.hud):
		city.hud.visible = false

	# View 1: Dispersed boulevard / plaza view
	camera.position = Vector3(-16, 3.8, -12)
	camera.look_at(Vector3(0, 1.0, -38))
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage6a/street_dispersed.png")

	# View 2: Uplink monument and conversation circles
	camera.position = Vector3(0, 3.5, -24)
	camera.look_at(Vector3(0, 1.2, -40))
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage6a/plaza_circles.png")

	# View 3: Close view of promenade with pedestrian traffic
	camera.position = Vector3(14, 1.8, 60)
	camera.look_at(Vector3(18, 1.2, 75))
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage6a/promenade_life.png")

	# Count seated residents and verify non-overlapping positions
	var people: Array=bridge.world.citizens
	var seated_count: int=0
	for id in city.population.units:
		var unit: Dictionary=city.population.units[id]
		var actor: CharacterBody3D=unit.person
		if actor.pose=="sit" or (actor.player!=null and actor.player.current_animation in ["sit_idle","sit_down"]):
			seated_count+=1

	var positions: Array=[]
	for c in people:
		positions.append(c.position)

	var metrics: Dictionary={
		"population": people.size(),
		"seated_actors_observed": seated_count,
		"clock_seconds": bridge.world.clock_seconds,
		"exceptional_agents": people.slice(30).map(func(c):return {"name":c.name,"role":c.role,"goal_place":c.goal.place,"activity":c.activity,"position":c.position})
	}
	var file:=FileAccess.open("res://../docs/previews/stage6a/dispersal_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics,"  "))
	file.close()

	print("STAGE6A_CHECK failures=0 seated=%d" % seated_count)
	bridge.request_quit()
