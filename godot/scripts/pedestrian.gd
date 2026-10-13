extends CharacterBody3D
## One collision-backed pedestrian, shared by the city and isolated navigation QA.
signal arrived
signal blocked
var navigator: Node3D
var agent: NavigationAgent3D
var body_height := 1.78
var model_path := "res://models/animated/civilian.glb"
var model: Node3D
var player: AnimationPlayer
var destination := Vector3.ZERO
var active := false
var running := false
var simulation_frozen := false
var state := "IDLE"
var retry_time := 0.0
var distance_travelled := 0.0
var last_position := Vector3.ZERO
var max_turn_step := 0.0
var progress_anchor := Vector3.ZERO
var progress_elapsed := 0.0
var rebuild_cooldown := 0.0
var step_count := 0
var crowd := false
var safe_velocity := Vector3.ZERO
var desired_pose := "stand"
var desired_yaw: Variant = null
var pose := "stand"
var pending_destination := Vector3.ZERO
var has_pending_destination := false
var lod_phase := 0
var lod_level := 0
var lod_timer := 0.0
var animation_elapsed := 0.0
var animation_updates := 0
var step_probe_updates := 0
var budget_frames := 0
var idle_elapsed := 0.0
const MAX_STEP_HEIGHT := .25
const WALK_STRIDE_SPEED := .739
const RUN_STRIDE_SPEED := 1.65

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = .4
	floor_max_angle = deg_to_rad(45)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = body_height-.13
	shape.shape = capsule
	# Rounded torso clearance with a flat foot support avoids the capsule's
	# rounded heel sliding back down a curb after an otherwise valid step.
	shape.position.y = (body_height+.13)/2
	add_child(shape)
	var feet:=CollisionShape3D.new()
	var sole:=BoxShape3D.new();sole.size=Vector3(.52,.28,.52)
	feet.shape=sole;feet.position.y=.14;add_child(feet)
	model = load(model_path).instantiate()
	add_child(model)
	player = model.find_child("AnimationPlayer",true,false)
	for clip in ["idle","walk","run","sit_idle"]:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for clip in ["sit_down","stand_up"]:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_NONE
	player.animation_finished.connect(_on_animation_finished)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play("idle")
	agent = NavigationAgent3D.new()
	agent.radius = .35
	agent.height = maxf(1.8,body_height)
	agent.path_desired_distance = .35
	agent.target_desired_distance = .45
	agent.path_max_distance = 1.5
	add_child(agent)
	last_position = global_position
	lod_phase = randi() % 4
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.visibility_range_end = 140.0

func set_goal_posture(target_pose: String, target_yaw: Variant) -> void:
	desired_pose = target_pose
	desired_yaw = target_yaw

func snap_seated(yaw_val: Variant) -> void:
	pose = "sit"
	desired_pose = "sit"
	if yaw_val != null:
		desired_yaw = yaw_val
		model.rotation.y = float(yaw_val)
	if player != null and player.has_animation("sit_idle"):
		player.play("sit_idle")

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "sit_down":
		player.play("sit_idle", 0.15)
	elif anim_name == "stand_up":
		pose = "stand"
		player.play("idle", 0.15)
		if has_pending_destination:
			has_pending_destination = false
			go_to(pending_destination)

func enable_crowd() -> void:
	crowd=true;collision_mask=3
	agent.avoidance_enabled=true
	agent.radius=.46;agent.neighbor_distance=4;agent.max_neighbors=12
	agent.time_horizon_agents=1.2;agent.time_horizon_obstacles=.5
	agent.velocity_computed.connect(func(value: Vector3):safe_velocity=value)

func go_to(point: Vector3) -> bool:
	if pose == "sit" or (player != null and player.current_animation in ["sit_down", "sit_idle"]):
		pending_destination = point
		has_pending_destination = true
		destination = point
		state = "TRAVELLING"
		active = false
		velocity = Vector3.ZERO
		player.play("stand_up", 0.18)
		return true
	destination = point
	active = true
	retry_time = 0
	return refresh_path()

func refresh_path() -> bool:
	if not navigator.ready_for_paths:return false
	var map: RID = get_world_3d().navigation_map
	var nearest := NavigationServer3D.map_get_closest_point(map,destination)
	var path := NavigationServer3D.map_get_path(map,global_position,nearest,true)
	if nearest.distance_to(destination) > 1.25 or path.is_empty() or path[-1].distance_to(nearest) > .6:
		print("ROUTE_REJECT target=",destination," nearest=",nearest," end=",path[-1] if not path.is_empty() else Vector3.INF)
		state = "WAITING FOR ROUTE"
		return false
	agent.target_position = nearest
	state = "TRAVELLING"
	progress_anchor=global_position;progress_elapsed=0
	return true

func try_step(motion: Vector3) -> bool:
	if not is_on_floor() or motion.length()<.00001:return false
	# Probe beyond the rounded capsule's toe, not only one tiny frame of travel.
	var forward:=motion.normalized()
	var contact:=KinematicCollision3D.new()
	if not test_move(global_transform,forward*.12,contact):return false
	if contact.get_normal().dot(Vector3.UP)>=cos(floor_max_angle):return false
	var toe:=global_position+forward*.60
	var ray:=PhysicsRayQueryParameters3D.create(toe+Vector3.UP*(MAX_STEP_HEIGHT+.03),toe-Vector3.UP*.04,collision_mask,[get_rid()])
	var support:=get_world_3d().direct_space_state.intersect_ray(ray)
	if support.is_empty() or support.normal.dot(Vector3.UP)<cos(floor_max_angle):return false
	# A narrow strip may end before the landing probe. Check its top too so it
	# can be crossed, while a bench/wall cannot be mistaken for a low curb.
	var lip: Vector3=contact.get_position()+forward*.02;lip.y=global_position.y
	ray.from=lip+Vector3.UP*(MAX_STEP_HEIGHT+.03);ray.to=lip-Vector3.UP*.04
	var obstacle:=get_world_3d().direct_space_state.intersect_ray(ray)
	if obstacle.is_empty() or obstacle.normal.dot(Vector3.UP)<cos(floor_max_angle):return false
	var rise: float=maxf(support.position.y,obstacle.position.y)-global_position.y
	if rise<.015 or rise>MAX_STEP_HEIGHT+.001:return false
	var raised:=global_transform
	if test_move(raised,Vector3.UP*(rise+.015)):return false
	raised.origin.y+=rise+.015
	if test_move(raised,motion):return false
	global_transform=raised
	step_count+=1
	return true

func _physics_process(delta: float) -> void:
	if simulation_frozen:
		velocity = Vector3.ZERO
		if crowd:agent.velocity=Vector3.ZERO;safe_velocity=Vector3.ZERO
		player.speed_scale = 0
		return
	var direction := Vector3.ZERO
	budget_frames += 1
	rebuild_cooldown=maxf(0,rebuild_cooldown-delta)
	lod_timer += delta
	if lod_timer >= 0.25:
		lod_timer = 0.0
		var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		if cam != null:
			var cam_dist: float = global_position.distance_to(cam.global_position)
			if navigator!=null and navigator.city.has_meta("detail_feed_position"):
				cam_dist=minf(cam_dist,global_position.distance_to(navigator.city.get_meta("detail_feed_position")))
			if cam_dist > 65.0:
				lod_level = 2
			elif cam_dist > 35.0:
				lod_level = 1
			else:
				lod_level = 0
		else:
			lod_level = 0
	if active and not navigator.ready_for_paths:state="WAITING FOR ROUTE"
	if active and navigator.ready_for_paths:
		retry_time += delta
		if state == "WAITING FOR SPACE":
			if retry_time>.5:retry_time=0;refresh_path()
		elif state == "WAITING FOR ROUTE":
			if retry_time > 5:retry_time = 0;refresh_path()
		elif agent.is_navigation_finished():
			# The navigation endpoint may be projected away from the assigned goal.
			# Backend arrival uses that original goal, never the projected endpoint.
			if global_position.distance_to(destination) < .75:
				active = false;state = "ARRIVED"
				velocity.x=0;velocity.z=0;safe_velocity=Vector3.ZERO
				if crowd:agent.set_velocity_forced(Vector3.ZERO)
				arrived.emit()
			elif global_position.distance_to(agent.target_position) > .1:
				# Finish the last safe approach despite the agent's path tolerance.
				direction=agent.target_position-global_position;direction.y=0;direction=direction.normalized()
			else:state = "WAITING FOR ROUTE"
		else:
			direction = agent.get_next_path_position()-global_position
			direction.y = 0
			direction = direction.normalized()
	var speed := 2.4 if running else 1.15
	if direction.length() > .1:
		var target_yaw := atan2(-direction.x,-direction.z)
		var turn := clampf(wrapf(target_yaw-model.rotation.y,-PI,PI),-2.8*delta,2.8*delta)
		model.rotation.y += turn
		max_turn_step = maxf(max_turn_step,absf(turn))
		# Slow for sharp turns instead of strafing or reversing the body.
		var facing := -model.global_basis.z
		speed *= clampf(facing.dot(direction),0,1)
	velocity.x = move_toward(velocity.x,direction.x*speed,4*delta)
	velocity.z = move_toward(velocity.z,direction.z*speed,4*delta)
	if crowd:
		agent.max_speed=speed if direction.length()>.1 else 1.15
		agent.avoidance_priority=.5 if active else 1.0
		agent.velocity=Vector3(velocity.x,0,velocity.z)
		if active and direction.length()>.1:
			velocity.x=safe_velocity.x;velocity.z=safe_velocity.z
	velocity.y = 0 if is_on_floor() else velocity.y-22*delta
	var before := global_position
	if direction.length() > .1 and (budget_frames + lod_phase) % (1 if lod_level==0 else (2 if lod_level==1 else 4)) == 0:
		step_probe_updates += 1
		try_step(Vector3(velocity.x, 0, velocity.z) * delta)
	move_and_slide()
	var displacement := global_position-before
	displacement.y = 0
	var measured_speed := displacement.length()/delta
	distance_travelled += displacement.length()
	if active and state=="TRAVELLING" and navigator.ready_for_paths:
		progress_elapsed+=delta
		var progress:=global_position-progress_anchor;progress.y=0
		if progress.length()>.15:
			progress_anchor=global_position;progress_elapsed=0
		if progress_elapsed>2:
			progress_elapsed=0;retry_time=0;state="WAITING FOR ROUTE";blocked.emit()
			var peer_block:=false
			if crowd:
				for other in navigator.people:
					if other!=self and absf(other.position.y-position.y)<1.5 and other.position.distance_to(position)<1.6:peer_block=true;break
			if peer_block:state="WAITING FOR SPACE"
			elif rebuild_cooldown<=0:rebuild_cooldown=8;navigator.rebuild()
	else:progress_elapsed=0
	if not active and desired_yaw != null:
		idle_elapsed += delta
		var target_y: float = float(desired_yaw) + (0.10*sin(idle_elapsed*.55+lod_phase) if pose=="stand" else 0.0)
		var turn := clampf(wrapf(target_y-model.rotation.y,-PI,PI),-2.2*delta,2.2*delta)
		model.rotation.y += turn
	var clip := ""
	if measured_speed < .05:
		if state == "ARRIVED" and desired_pose == "sit":
			if pose != "sit" and player.current_animation != "sit_down":
				pose = "sit"
				player.play("sit_down", .18)
			elif player.current_animation in ["sit_down", "sit_idle"]:
				clip = player.current_animation
			else:
				clip = "sit_idle"
		elif pose == "sit":
			clip = "sit_idle"
		else:
			clip = "idle"
	else:
		clip = "run" if running else "walk"
	if clip != "" and player.current_animation != clip and not player.current_animation in ["sit_down", "stand_up"]:
		player.play(clip, .16)
	if clip != "":
		player.speed_scale = 1 if clip in ["idle", "sit_idle", "sit_down", "stand_up"] else measured_speed/(RUN_STRIDE_SPEED if running else WALK_STRIDE_SPEED)
	animation_elapsed += delta
	var animation_interval := 0.0 if lod_level==0 else (0.05 if lod_level==1 else 0.1)
	# Transitions stay smooth at every distance and must finish before departure.
	if player.current_animation in ["sit_down", "stand_up"] or animation_elapsed >= animation_interval:
		player.advance(animation_elapsed)
		animation_elapsed = 0.0
		animation_updates += 1
	last_position = global_position
