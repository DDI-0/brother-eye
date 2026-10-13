extends SceneTree
var failures: Array[String]=[]
var city: Node3D
var nav: Node3D
var person: CharacterBody3D
var blocked_observed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func frames(count: int) -> void:
	for i in count:await physics_frame
func travel(target: Vector3,limit:=1800) -> bool:
	blocked_observed=false
	person.go_to(target)
	for i in limit:
		await physics_frame
		if person.state=="WAITING FOR ROUTE":blocked_observed=true
		if "--trace" in OS.get_cmdline_user_args() and i%120==0:
			print("TRACE ",i," pos=",person.position," vel=",person.velocity," yaw=",person.model.rotation.y," state=",person.state," ready=",nav.ready_for_paths," stalled=",person.progress_elapsed," active=",person.active)
		if not person.active:return person.position.distance_to(target)<.95
	print("OBSTACLE_STUCK position=",person.position," state=",person.state," floor=",person.is_on_floor()," velocity=",person.velocity," next=",person.agent.get_next_path_position())
	return false
func obstacle(pos: Vector3,size: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.position=pos
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box
	body.add_child(shape);city.add_child(body);return body
func reset_person(pos: Vector3,running:=false) -> void:
	person.active=false;person.position=pos;person.velocity=Vector3.ZERO;person.running=running
	person.model.rotation.y=0;person.state="IDLE";person.rebuild_cooldown=0
	await frames(10)
func run() -> void:
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	nav=preload("res://scripts/pedestrian_navigation.gd").new();city.add_child(nav);nav.setup(city);nav.automatic=false
	await nav.rebuilt
	person=nav.pedestrian
	# Exact persisted position from the reported Sector 07 curb blockage.
	person.position=Vector3(12.210466384887695,-.09978044033050537,82.59980773925781)
	person.model.rotation.y=-1.5713804960250854;person.velocity=Vector3.ZERO
	await frames(3)
	if "--trace" in OS.get_cmdline_user_args():
		var raised: Transform3D=person.global_transform;raised.origin.y+=.26
		var hit:=KinematicCollision3D.new()
		var collides: bool=person.test_move(raised,Vector3(.02,0,0),hit)
		print("RAISED_TEST ",raised.origin," collision=",collides," normal=",hit.get_normal() if collides else Vector3.ZERO)
	check(await travel(Vector3(18,.12,90)),"reported saved curb position recovers and reaches home")
	check(person.step_count>0,"reported curb uses supported stepping")
	for running in [false,true]:
		await reset_person(Vector3(0,-.099,90),running)
		var strip:=obstacle(Vector3(0,0,87),Vector3(4,.20,.12))
		await frames(3)
		var count: int=person.step_count
		check(await travel(Vector3(0,-.1,84)),("run" if running else "walk")+" crosses a thin 20 cm obstacle")
		check(person.step_count>count,"low strip crossed by stepping")
		strip.queue_free();await frames(3)
	# A blocked step with insufficient headroom must not move through a ceiling.
	await reset_person(Vector3(0,-.099,90))
	var curb:=obstacle(Vector3(0,0,89.55),Vector3(4,.20,.25))
	var ceiling:=obstacle(Vector3(0,1.77,90),Vector3(4,.1,2))
	await frames(3)
	check(not person.try_step(Vector3(0,0,-.02)),"low step rejects insufficient headroom")
	curb.queue_free();ceiling.queue_free();await frames(3)
	var platform:=obstacle(Vector3(0,3.9,90),Vector3(2,.2,.8))
	var lip:=obstacle(Vector3(0,4.1,89.55),Vector3(2,.2,.1))
	await reset_person(Vector3(0,4.001,89.95))
	check(not person.try_step(Vector3(0,0,-.02)),"step rejects a landing with no footing beyond the edge")
	platform.queue_free();lip.queue_free();await frames(3)
	await reset_person(Vector3(0,-.099,90))
	var tall_curb:=obstacle(Vector3(0,.075,87),Vector3(4,.35,1))
	await frames(3)
	var high_steps: int=person.step_count
	check(await travel(Vector3(0,-.1,84),9000),"35 cm obstruction is routed around")
	check(person.step_count==high_steps,"obstacle over step limit is not climbed")
	tall_curb.queue_free();await frames(3);nav.rebuild();await nav.rebuilt
	# A large unexpected obstacle needs a fresh route, never a step through it.
	await reset_person(Vector3(18,.13,90))
	var start_steps: int=person.step_count
	await nav.toggle_barrier(false)
	check(await travel(Vector3(18,.12,68),9000),"large obstacle triggers a physical detour")
	check(blocked_observed,"stalled travel reports waiting while finding a detour")
	check(person.step_count==start_steps,"large obstacle is not climbed")
	await nav.toggle_barrier();await nav.rebuilt
	# Reject an unreachable goal with a stable waiting state and idle animation.
	person.go_to(Vector3(46,6,7));await frames(180)
	check(person.state=="WAITING FOR ROUTE" and person.player.current_animation=="idle","unreachable route waits with idle animation")
	# Await any bake before destroying its geometry to avoid worker teardown races.
	while nav.baking:await process_frame
	print("OBSTACLE_QA failures=",failures.size());quit(0 if failures.is_empty() else 1)
