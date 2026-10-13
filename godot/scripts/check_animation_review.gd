extends SceneTree
var checks := 0
func _initialize() -> void:call_deferred("run")
func verify(condition: bool, message: String) -> void:
	if not condition:push_error(message);quit(1)
	assert(condition,message)
	checks += 1
func run() -> void:
	var review = load("res://scenes/animation_review.tscn").instantiate()
	root.add_child(review)
	await process_frame
	verify(review.players.size()==2,"Two playable rigged characters")
	for player in review.players:
		var skeleton: Skeleton3D = player.get_parent().find_children("*","Skeleton3D",true,false)[0]
		verify(skeleton.get_bone_count()>=19,"Deforming biped skeleton")
		for clip in review.CLIPS:
			verify(player.has_animation(clip),"Required animation "+clip)
			review.play_clip(clip,true)
			var animation: Animation = player.get_animation(clip)
			verify(animation.length>0.7,"Nonempty baked clip")
			for index in 25:
				player.seek(animation.length*index/24.0,true)
				for bone in skeleton.get_bone_count():
					var pose := skeleton.get_bone_global_pose(bone)
					verify(pose.is_finite(),"Finite interpolated skeleton")
			if clip in ["idle","walk","run","sit_idle"]:
				player.seek(0,true)
				var start: Array[Vector3] = []
				for bone in skeleton.get_bone_count():start.append(skeleton.get_bone_global_pose(bone).origin)
				player.seek(animation.length-.0001,true)
				for bone in skeleton.get_bone_count():verify(start[bone].distance_to(skeleton.get_bone_global_pose(bone).origin)<.025,"Loop pose closure "+clip)
	# Check the actual AnimationPlayer finish events and review transition routing.
	review.play_clip("sit_down",true)
	for player in review.players:player.advance(player.current_animation_length+.05)
	await process_frame
	verify(review.clip=="sit_idle","Sit-down completes into seated idle")
	review.play_clip("run")
	verify(review.clip=="stand_up","Seated locomotion request stands first")
	for player in review.players:player.advance(player.current_animation_length+.05)
	await process_frame
	verify(review.clip=="run","Queued run starts after standing")
	review.play_clip("idle",true)
	for player in review.players:player.speed_scale=0
	var held: float = review.players[0].current_animation_position
	for frame in 3:await process_frame
	verify(is_equal_approx(held,review.players[0].current_animation_position),"Pause holds animation time")
	print("ANIMATION_REVIEW_QA_PASS checks=",checks)
	quit()
