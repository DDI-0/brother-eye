extends SceneTree
## Offline exterior and access review. No backend, simulation or production saves.
var city: Node3D
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var folder := ProjectSettings.globalize_path("res://../docs/previews/civic-exchange")
	DirAccess.make_dir_recursive_absolute(folder)
	city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	city.explorer.set_capture(false)
	city.hud.hide()
	var camera := Camera3D.new()
	camera.far = 1800
	city.add_child(camera)
	camera.make_current()
	var views := [
		["entrance",Vector3(-31,3,43),Vector3(-46,5.8,24),62.0],
		["terrace",Vector3(-22,24,33),Vector3(-46,12.5,3),60.0],
		["headquarters",Vector3(13,2,-54),Vector3(0,4,-76),65.0]
	]
	for view in views:
		camera.position = view[1]
		camera.fov = view[3]
		camera.look_at(view[2])
		await capture(folder+"/"+view[0]+".png")
	# Reuse the existing offline daylight study, without changing runtime lighting.
	var day = load("res://scripts/day_cycle_review.gd").new()
	day.city = city
	day.caption = Label.new()
	day.progress = ProgressBar.new()
	day.apply_hour(10)
	for view in views.slice(0,2):
		camera.position = view[1]
		camera.fov = view[3]
		camera.look_at(view[2])
		await capture(folder+"/day-"+view[0]+".png")
	day.caption.free()
	day.progress.free()
	day.free()
	# Real controller traverses the existing skywalk opening and inner roof aisle.
	var p = city.explorer
	p.set_capture(true)
	p.observing = false
	p.position = Vector3(-24,12.3,20)
	p.rotation = Vector3.ZERO
	p.velocity = Vector3.ZERO
	for i in 20: await physics_frame
	Input.action_press("left")
	for i in 78: await physics_frame
	Input.action_release("left")
	print("CIVIC_ENTRY_POSITION ",p.position)
	assert(p.position.x < -29 and p.position.y > 11.8,"Civic skywalk entry blocked")
	Input.action_press("forward")
	for i in 95: await physics_frame
	Input.action_release("forward")
	assert(p.position.z < 14 and p.position.y > 11.8,"Civic terrace aisle blocked")
	assert(ProjectSettings.get_setting("application/config/name") == "Neon Providence")
	assert(city.satellite.name == "NeonProvidenceOrbitalPresence")
	print("CIVIC_REVIEW captured=5 skywalk_entry=passed terrace_aisle=passed rename=passed position=",p.position)
	quit()
func capture(path: String) -> void:
	for i in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
