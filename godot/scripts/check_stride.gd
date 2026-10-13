extends SceneTree
var passed := true
func verify(ok: bool,message: String) -> void:
	if not ok:passed=false;push_error(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var city=load("res://scenes/city.tscn").instantiate();root.add_child(city)
	var nav=load("res://scripts/pedestrian_navigation.gd").new();city.add_child(nav);nav.setup(city);nav.automatic=false
	await nav.rebuilt
	var p=nav.pedestrian
	var skeleton: Skeleton3D=p.model.find_children("*","Skeleton3D",true,false)[0]
	var report: Dictionary={}
	for running in [false,true]:
		p.position=Vector3(14,.3,90);p.velocity=Vector3.ZERO;p.running=running
		p.go_to(Vector3(14,.12,68))
		var previous: Dictionary={};var samples: Array[float]=[];var speeds: Array[float]=[]
		for i in 360:
			await physics_frame
			if i<60:continue
			for side in ["Left","Right"]:
				var foot: Vector3=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(side+"Foot")).origin
				if previous.has(side) and foot.y-p.position.y<.16 and previous[side].y-p.position.y<.16:
					var drift: Vector3=foot-previous[side];drift.y=0;samples.append(drift.length()*60)
				previous[side]=foot
			speeds.append(Vector2(p.velocity.x,p.velocity.z).length())
		var mean := 0.0
		for value in samples:mean+=value
		mean/=maxi(samples.size(),1)
		var travel_speed := 0.0
		for value in speeds:travel_speed+=value
		travel_speed/=speeds.size()
		report["run" if running else "walk"]={"stance_ankle_drift_mean_mps":mean,"stance_samples":samples.size(),"travel_speed_mps":travel_speed}
		verify(samples.size()>50,"Enough stance samples")
		verify(absf(travel_speed-(2.4 if running else 1.15))<.03,"Straight-line travel speed")
		verify(mean<(.30 if running else .40),"Excessive stance sliding")
		print("STRIDE_MEASURE ",report)
	report["passed"]=passed
	var file=FileAccess.open("res://../docs/previews/stage3c/stride_qa.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t")+"\n")
	quit(0 if passed else 1)
