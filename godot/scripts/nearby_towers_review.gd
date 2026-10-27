extends SceneTree
## Offline skyline/facade comparison with a collision-envelope regression check.
func _initialize() -> void: call_deferred("run")
func moving_visible(node: Node) -> bool:
	if node is MeshInstance3D and node.layers == 0: return false
	for child in node.get_children():
		if not moving_visible(child): return false
	return true
func run() -> void:
	var tag := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-tag="): tag = arg.trim_prefix("--review-tag=")
	var folder := ProjectSettings.globalize_path("res://../docs/previews/nearby-towers/"+tag)
	DirAccess.make_dir_recursive_absolute(folder)
	var city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	city.hud.hide()
	city.explorer.set_capture(false)
	var camera := Camera3D.new()
	camera.far = 1800
	city.add_child(camera)
	camera.make_current()
	var views := [
		["skyline",Vector3(64,112,185),Vector3(0,59,-62),65.0],
		["wave",Vector3(73,25,101),Vector3(48,28,64),52.0],
		["blade",Vector3(-20,32,97),Vector3(-48,30,64),58.0],
		["inverted",Vector3(-80,19,44),Vector3(-100,23,12),58.0],
		["helix",Vector3(16,48,-7),Vector3(48,43,-48),56.0],
		["fork",Vector3(-25,65,-66),Vector3(-48,55,-110),62.0],
		["disc",Vector3(146,60,-66),Vector3(119,53,-110),60.0]
	]
	for view in views:
		camera.position = view[1]
		camera.fov = view[3]
		camera.look_at(view[2])
		for i in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/"+view[0]+".png")
	if tag != "before":
		var day = load("res://scripts/day_cycle_review.gd").new()
		day.city = city
		day.caption = Label.new()
		day.progress = ProgressBar.new()
		day.apply_hour(10)
		for index in [0,1,3,4]:
			var view: Array = views[index]
			camera.position = view[1]
			camera.fov = view[3]
			camera.look_at(view[2])
			for i in 12: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/day-"+view[0]+".png")
		day.caption.free()
		day.progress.free()
		day.free()
	var shapes: Array[String] = []
	for child in city.kit.solid.get_children():
		shapes.append(str(child.transform)+":"+child.shape.get_class()+":"+str(child.shape.get_debug_mesh().get_aabb()))
	var report := {"collision_count":shapes.size(),"collision_digest":"\n".join(shapes).sha256_text(),"captures":views.size()+(4 if tag != "before" else 0)}
	var rig = city.get_node("ObservatoryTrackingRig")
	report["animated_landmark_visible"] = moving_visible(rig)
	var original: Basis = rig.basis
	rig.set_hour(14)
	report["animated_landmark_rotates"] = not rig.basis.is_equal_approx(original)
	if not report.animated_landmark_visible or not report.animated_landmark_rotates:
		push_error("Static facade batching affected the Observatory tracking rig")
		quit(1)
		return
	var before := folder.get_base_dir()+"/before/verification.json"
	if tag != "before" and FileAccess.file_exists(before):
		var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(before))
		report["collision_unchanged"] = report.collision_digest == baseline.collision_digest
		if not report.collision_unchanged:
			push_error("Tower upgrade changed collision envelopes")
			quit(1)
			return
	var out := FileAccess.open(folder+"/verification.json",FileAccess.WRITE)
	out.store_string(JSON.stringify(report,"  ")+"\n")
	print("NEARBY_TOWERS_REVIEW ",JSON.stringify(report))
	quit()
