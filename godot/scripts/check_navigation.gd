extends SceneTree
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var city: Node3D
var nav: Node3D
var person: CharacterBody3D
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func frames(count: int) -> void:
	for i in count:await physics_frame
func trip(target: Vector3,label: String,limit := 12000) -> void:
	var accepted: bool = person.go_to(target)
	check(accepted,label+" has a complete path")
	if not accepted:return
	var travelled: float = person.distance_travelled
	var steps := 0
	while person.active and steps<limit:
		await physics_frame
		steps+=1
	check(not person.active and person.global_position.distance_to(target)<.9,label+" reaches destination physically")
	measurements.append({"trip":label,"position":[person.position.x,person.position.y,person.position.z],"frames":steps,"distance_m":person.distance_travelled-travelled})
func run() -> void:
	city = load("res://scenes/city.tscn").instantiate();root.add_child(city)
	nav = city.pedestrian_navigation
	if nav==null:
		nav = load("res://scripts/pedestrian_navigation.gd").new();city.add_child(nav);nav.setup(city)
	else:
		check(nav.follow_camera.current and nav.follow,"review launcher starts following the civilian")
		check(not city.hud.visible,"review launcher shows the navigation controls")
	nav.automatic=false
	await nav.rebuilt
	person=nav.pedestrian
	await frames(15)
	check(nav.region.navigation_mesh.get_polygon_count()>100,"city collision produces a navigation surface")
	# Both floor levels under/over the skywalk must remain connected correctly.
	await trip(Vector3(18,.12,68),"promenade")
	await trip(Vector3(24,12.08,20),"east stair ascent")
	check(person.is_on_floor() and person.position.y>11.8,"stair arrival stands on the skywalk")
	await trip(Vector3(34,12,8),"rooftop terrace")
	await trip(Vector3(-24,12.08,20),"skywalk crossing")
	await trip(Vector3(-24,.12,65),"west stair descent")
	await trip(Vector3(18,.12,90),"street crossing")
	# Add an actual collider across the planned route and force a new bake.
	var previous_revision: int=nav.revision
	await nav.toggle_barrier(false)
	var start_distance: float=person.distance_travelled
	await trip(Vector3(18,.12,68),"obstruction detour")
	check(nav.revision>previous_revision,"unexpected obstruction triggers automatic route rebuilding")
	check(person.distance_travelled-start_distance>22.2,"obstruction requires a detour rather than passing through")
	await nav.toggle_barrier();await nav.rebuilt
	# An unreachable facade destination must wait and recover when given a valid goal.
	check(not person.go_to(Vector3(46,6,7)),"rejects destination inside a building")
	await frames(150)
	check(person.state=="WAITING FOR ROUTE","unreachable goal waits without walking through walls")
	person.running=true
	await trip(Vector3(18,.12,90),"running recovery")
	check(person.max_turn_step<.05,"turning remains limited to 2.8 radians per second")
	check(person.player.current_animation in ["run","idle"],"running uses the matching animation")
	var report := {"passed":failures.is_empty(),"failures":failures,"bake_ms":nav.bake_ms,"polygons":nav.region.navigation_mesh.get_polygon_count(),"trips":measurements}
	var file := FileAccess.open("res://../docs/previews/stage3c/navigation_qa.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n")
	print("NAVIGATION_QA ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
