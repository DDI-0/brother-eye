extends SceneTree

var city: Node3D

func _initialize() -> void:
	call_deferred("run")

func until(predicate: Callable) -> bool:
	var end := Time.get_ticks_msec() + 35000
	while Time.get_ticks_msec() < end:
		if predicate.call():
			return true
		await create_timer(.05).timeout
	return false

func sample_frames(n: int) -> Array[float]:
	for i in range(6):
		await process_frame
	var samples: Array[float] = []
	var prev := Time.get_ticks_usec()
	for i in range(n):
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - prev) / 1000.0)
		prev = now
	samples.sort()
	return samples

func run() -> void:
	city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	var bridge: Node = city.simulation
	if not await until(func(): return bridge.restored and city.population.restored and city.population.navigation.ready_for_paths):
		print("TIMEOUT: restored=%s pop_restored=%s paths=%s" % [
			bridge.restored, city.population.restored if city.population else "null",
			city.population.navigation.ready_for_paths if (city.population and city.population.navigation) else "null"
		])
		push_error("Stage6B restore timeout")
		quit(1)
		return

	bridge.last_view = bridge.now() + 3600
	bridge.set_clock(false, 1)
	if not await until(func(): return bridge.pending.is_empty() and not bridge.world.paused):
		print("TIMEOUT: pending=%d paused=%s" % [bridge.pending.size(), bridge.world.get("paused")])
		quit(1)
		return

	var people: Array = bridge.world.citizens
	print("RESTORED CITIZENS COUNT: ", people.size())
	if people.size() != 50:
		print("Expected 50 residents, found %d" % people.size())
		quit(1)
		return

	var civ_count := 0
	var pol_count := 0
	var exc_count := 0
	for c in people:
		var k: String = c.get("kind", "civilian")
		if k == "police": pol_count += 1
		elif k == "exceptional": exc_count += 1
		else: civ_count += 1

	if civ_count != 41 or pol_count != 5 or exc_count != 4:
		push_error("Demographic mismatch: civ=%d pol=%d exc=%d" % [civ_count, pol_count, exc_count])
		quit(1)
		return

	# Warmup so simulation advances and positions settle into their organic spots
	await create_timer(3.0).timeout
	var camera := Camera3D.new()
	city.add_child(camera)
	camera.make_current()

	DirAccess.make_dir_absolute("res://../docs/previews/stage6b")

	if is_instance_valid(city.hud):
		city.hud.visible = false

	# View 1: Dispersed street crowd view
	camera.position = Vector3(-16, 3.8, -12)
	camera.look_at(Vector3(0, 1.0, -38))
	await process_frame; await RenderingServer.frame_post_draw
	var street_samples := await sample_frames(40)
	var street_draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	root.get_texture().get_image().save_png("res://../docs/previews/stage6b/street_tier1_50.png")

	# View 2: Uplink monument and plaza crowd
	camera.position = Vector3(0, 3.5, -24)
	camera.look_at(Vector3(0, 1.2, -40))
	await process_frame; await RenderingServer.frame_post_draw
	var plaza_samples := await sample_frames(40)
	var plaza_draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	root.get_texture().get_image().save_png("res://../docs/previews/stage6b/plaza_crowd_50.png")

	# View 3: Broad district skyline view
	camera.position = Vector3(0, 38.0, 140.0)
	camera.look_at(Vector3(0, 8.0, 15.0))
	await process_frame; await RenderingServer.frame_post_draw
	var skyline_samples := await sample_frames(40)
	var skyline_draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	root.get_texture().get_image().save_png("res://../docs/previews/stage6b/skyline_tier1_50.png")

	# Audit distance-based LOD distribution
	var lod_counts := {0: 0, 1: 0, 2: 0}
	var avoidance_disabled_at_far := 0
	var seated_count := 0
	for id in city.population.units:
		var unit: Dictionary = city.population.units[id]
		var actor: CharacterBody3D = unit.person
		lod_counts[actor.lod_level] = lod_counts.get(actor.lod_level, 0) + 1
		if actor.lod_level == 2 and not actor.agent.avoidance_enabled:
			avoidance_disabled_at_far += 1
		if actor.pose == "sit" or (actor.player != null and actor.player.current_animation in ["sit_idle", "sit_down"]):
			seated_count += 1

	var median_street: float = street_samples[street_samples.size() / 2]
	var p95_street: float = street_samples[int(street_samples.size() * 0.95)]

	var metrics: Dictionary = {
		"population": people.size(),
		"demographics": {"civilians": civ_count, "police": pol_count, "exceptional": exc_count},
		"seated_actors_observed": seated_count,
		"lod_distribution": lod_counts,
		"far_avoidance_throttled_actors": avoidance_disabled_at_far,
		"benchmarks": {
			"street": {"median_ms": median_street, "p95_ms": p95_street, "draw_calls": street_draw_calls},
			"plaza": {"median_ms": plaza_samples[plaza_samples.size() / 2], "draw_calls": plaza_draw_calls},
			"skyline": {"median_ms": skyline_samples[skyline_samples.size() / 2], "draw_calls": skyline_draw_calls}
		},
		"clock_seconds": bridge.world.clock_seconds
	}

	var file := FileAccess.open("res://../docs/previews/stage6b/tier1_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "  "))
	file.close()

	print("STAGE6B_CHECK failures=0 population=%d seated=%d lod=%s street_median=%.2fms" % [
		people.size(), seated_count, str(lod_counts), median_street
	])
	bridge.request_quit()
