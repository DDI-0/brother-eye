extends SceneTree
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures+=1
func frames(n: int) -> void:
	for i in n:await physics_frame
func run() -> void:
	var city: Node3D=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	var nav: Node3D=preload("res://scripts/pedestrian_navigation.gd").new();city.add_child(nav);nav.setup(city);nav.automatic=false
	await nav.rebuilt
	var person: CharacterBody3D=nav.pedestrian
	await frames(10)
	# Reproduce a finished projected endpoint over one metre from the real goal.
	person.destination=person.position+Vector3(0,0,1.1)
	person.agent.target_position=person.position;person.active=true;person.state="TRAVELLING"
	await frames(8)
	check(person.state!="ARRIVED" and person.active,"finished projected path cannot falsely acknowledge a distant assigned goal")
	check(person.state=="WAITING FOR ROUTE","unreached assigned destination reports a route wait")
	var goal:=Vector3(18,.12,85)
	check(person.go_to(goal),"valid replacement route accepted")
	var steps:=0
	while person.active and steps<900:await physics_frame;steps+=1
	check(person.state=="ARRIVED" and person.position.distance_to(goal)<.75,"physical arrival meets the original goal tolerance")
	var at:=person.position
	await frames(20)
	check(person.position.distance_to(at)<.05,"arrival stops residual horizontal drift")
	print("ARRIVAL_QA failures=",failures);quit(0 if failures==0 else 1)
