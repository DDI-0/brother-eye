extends SceneTree
func _initialize() -> void:call_deferred("capture")
func settle() -> void:
	for i in 45:await process_frame
	await RenderingServer.frame_post_draw
func capture() -> void:
	var destination := ProjectSettings.globalize_path("res://../docs/previews/stage3a")
	var review = load("res://scenes/civilian_review.tscn").instantiate()
	root.add_child(review)
	for index in 4:
		review.set_view(index)
		await settle()
		root.get_texture().get_image().save_png(destination + "/godot-" + ["front","three-quarter","back","detail"][index] + ".png")
	review.queue_free()
	await process_frame
	var city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	city.hud.hide()
	city.explorer.paused_input = true
	var civilian = load("res://models/civilian/civilian.glb").instantiate()
	city.add_child(civilian)
	civilian.position = Vector3(17,0.24,65)
	civilian.rotation.y = PI
	var camera := Camera3D.new()
	city.add_child(camera)
	camera.position = Vector3(19.0,1.5,68.5)
	camera.fov = 42
	camera.look_at(Vector3(17,1.1,65))
	camera.make_current()
	await settle()
	root.get_texture().get_image().save_png(destination + "/city-context.png")
	print("CIVILIAN_REVIEW_CAPTURE complete; studio and isolated city context")
	quit()
