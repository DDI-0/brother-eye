extends SceneTree
## Exercises the live clock interface with a disposable bridge, never a backend/save.
class ClockFixture extends Node:
	var connected := true
	var restored := true
	var world := {"clock_seconds":0.0,"paused":false,"time_scale":1.0}
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
func moving_geometry(node: Node) -> void:
	if node is MeshInstance3D: check(node.layers != 0,"Moving geometry was baked into static batches: "+str(node.name))
	for child in node.get_children(): moving_geometry(child)
func run() -> void:
	var city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	city.hud.hide()
	city.explorer.set_capture(false)
	var rig = city.get_node("ObservatoryTrackingRig")
	moving_geometry(rig)
	var bridge := ClockFixture.new()
	city.add_child(bridge)
	city.simulation = bridge
	var folder := ProjectSettings.globalize_path("res://../docs/previews/observatory/rotation")
	DirAccess.make_dir_recursive_absolute(folder)
	var camera := Camera3D.new()
	city.add_child(camera)
	camera.position = Vector3(40,22,17)
	camera.fov = 52
	camera.look_at(Vector3(46,15,-2))
	camera.make_current()
	if "--rotation-movie" in OS.get_cmdline_user_args():
		var day = load("res://scripts/day_cycle_review.gd").new()
		day.city = city
		day.caption = Label.new()
		day.progress = ProgressBar.new()
		for i in 192:
			var hour := 8.0+float(i)/192.0*24.0
			bridge.world.clock_seconds = (hour-8.0)*3600.0
			day.apply_hour(hour)
			await process_frame
		day.caption.free()
		day.progress.free()
		day.free()
		city.simulation = null
		print("OBSERVATORY_ROTATION_MOVIE frames=192")
		quit()
		return
	var samples: Array = []
	for hour in [8.0,14.0,20.0,26.0,32.0]:
		bridge.world.clock_seconds = (hour-8.0)*3600.0
		for i in 12: await process_frame
		var expected: float = fposmod((hour-8.0)/24.0,1.0)*TAU
		check(absf(angle_difference(rig.rotation.y,expected))<.0001,"Clock rotation mismatch")
		samples.append({"hour":fposmod(hour,24),"yaw":rig.rotation.y,"pitch":rig.telescope.rotation.x})
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+"/hour-%02d.png"%int(fposmod(hour,24)))
	check(absf(angle_difference(samples[0].yaw,samples[4].yaw))<.0001,"Day does not close smoothly")
	check(absf(samples[0].pitch-samples[2].pitch)>.1,"Telescope elevation did not change")
	bridge.world.paused = true
	var paused: Basis = rig.basis
	for i in 12: await process_frame
	check(rig.basis.is_equal_approx(paused),"Paused clock drifted")
	bridge.connected = false
	bridge.world.clock_seconds += 7200
	for i in 12: await process_frame
	check(rig.basis.is_equal_approx(paused),"Disconnected clock drifted")
	bridge.connected = true
	bridge.world.paused = false
	bridge.world.time_scale = 20
	bridge.world.clock_seconds = 3600
	for i in 12: await process_frame
	check(absf(angle_difference(rig.rotation.y,TAU/24))<.0001,"Restored clock did not set absolute pose")
	rig.set_hour(23.999)
	var before: Quaternion = rig.basis.get_rotation_quaternion()
	rig.set_hour(24.001)
	check(before.angle_to(rig.basis.get_rotation_quaternion())<.002,"Midnight causes a discontinuity")
	city.simulation = null
	var report := {"passed":failures.is_empty(),"samples":samples,"failures":failures,"clock":"authoritative snapshots; no wall-clock accumulation"}
	var file := FileAccess.open(folder+"/verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")+"\n")
	print("OBSERVATORY_ROTATION ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
