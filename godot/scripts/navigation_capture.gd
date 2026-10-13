extends SceneTree
var city: Node3D
var nav: Node3D
var camera: Camera3D
var phase := ""
func _initialize() -> void:call_deferred("capture")
func frames(count: int) -> void:
	for i in count:await process_frame
func view(offset: Vector3) -> void:
	var target: Vector3=nav.pedestrian.global_position+Vector3(0,1,0)
	camera.position = target+offset
	camera.look_at(target)
func save(name: String) -> void:
	await frames(3);await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage3c/"+name+".png")
func capture() -> void:
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	city.hud.visible=false
	nav=load("res://scripts/pedestrian_navigation.gd").new();city.add_child(nav);nav.setup(city);nav.automatic=false
	camera=Camera3D.new();camera.fov=55;camera.far=1600;city.add_child(camera);camera.make_current()
	while not nav.ready_for_paths:await process_frame
	nav.pedestrian.go_to(Vector3(18,.12,68))
	for i in 150:
		view(Vector3(3,1.2,-2));await process_frame
	await save("promenade")
	# Position a review shot on the same physical ramp already traversed by QA.
	nav.pedestrian.position=Vector3(24,5.9,44)
	nav.pedestrian.velocity=Vector3.ZERO
	nav.pedestrian.go_to(Vector3(24,12.08,20))
	for i in 90:
		view(Vector3(4,1,3));await process_frame
	await save("stairs")
	nav.pedestrian.position=Vector3(24,12.2,20);nav.pedestrian.velocity=Vector3.ZERO
	nav.pedestrian.go_to(Vector3(34,12,8))
	for i in 90:
		view(Vector3(3,1.3,4));await process_frame
	await save("skywalk")
	nav.pedestrian.position=Vector3(18,.3,90);nav.pedestrian.velocity=Vector3.ZERO
	await nav.toggle_barrier()
	while not nav.ready_for_paths:await process_frame
	nav.pedestrian.go_to(Vector3(18,.12,68))
	for i in 210:
		view(Vector3(5,3,-5));await process_frame
	await save("obstruction")
	print("NAVIGATION_CAPTURE_COMPLETE");quit()
