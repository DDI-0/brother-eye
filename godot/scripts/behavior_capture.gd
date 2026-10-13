extends SceneTree
## Native review of an isolated, live backend-owned civilian.
var city: Node3D
func _initialize() -> void:call_deferred("capture")
func capture() -> void:
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	var bridge: Node=city.simulation
	var population: Node3D=city.population
	var deadline:=Time.get_ticks_msec()+20000
	while not (bridge.restored and population.restored and population.navigation.ready_for_paths):
		if bridge.fatal or Time.get_ticks_msec()>deadline:quit(1);return
		await process_frame
	city.explorer.set_capture(false);city.hud.hide()
	population.panel.show();population.navigation.follow=true;population.navigation.follow_camera.make_current()
	bridge.set_clock(false,60)
	await create_timer(3).timeout
	bridge.set_clock(true,60)
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage3d/behavior.png")
	print("BEHAVIOR_CAPTURE_COMPLETE")
	bridge.request_quit()
