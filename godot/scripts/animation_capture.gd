extends SceneTree
func _initialize() -> void:call_deferred("capture")
func capture() -> void:
	var review = load("res://scenes/animation_review.tscn").instantiate()
	root.add_child(review)
	if "--movie" in OS.get_cmdline_user_args():
		await movie(review)
		quit()
		return
	var destination := ProjectSettings.globalize_path("res://../docs/previews/stage3b")
	for item in [["idle",.8],["walk",.35],["walk",.75],["run",.12],["run",.4],["sit_down",.95],["sit_idle",.1],["stand_up",.95]]:
		review.play_clip(item[0],true)
		review.paused = true
		for player in review.players:
			player.speed_scale = 0
			player.seek(item[1],true)
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(destination+"/"+item[0]+"-"+str(item[1])+".png")
	# Side views reveal knees, shoe contact and seat alignment more clearly.
	review.yaw = PI/2
	review.update_camera()
	for item in [["walk",.35],["run",.12],["sit_idle",.1]]:
		review.play_clip(item[0],true)
		for player in review.players:player.speed_scale = 0;player.seek(item[1],true)
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(destination+"/side-"+item[0]+".png")
	# Individual views avoid the other character hiding the wrist or foot contact.
	for index in 2:
		review.characters[1-index].visible = false
		for item in [["sit_idle",.1],["idle",.8],["run",.12]]:
			review.play_clip(item[0],true)
			for player in review.players:player.speed_scale = 0;player.seek(item[1],true)
			var center: Vector3 = review.characters[index].position + Vector3(0,.85,0)
			review.camera.position = center + Vector3(2.4,.35,-1.2)
			review.camera.look_at(center)
			for frame in 3:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(destination+"/fix-"+str(index)+"-"+item[0]+".png")
		review.characters[1-index].visible = true
	print("ANIMATION_CAPTURE_COMPLETE")
	quit()

func movie(review: Node3D) -> void:
	# Fixed-FPS native movie writer captures the viewport; advance real transitions.
	for item in [["idle",1.5],["walk",2.8],["run",1.6],["sit_down",1.94],["sit_idle",1.5],["stand_up",1.94]]:
		review.play_clip(item[0],true)
		var frames := int(ceil(item[1]*24))
		for frame in frames:await process_frame
	print("ANIMATION_MOVIE_COMPLETE")
