extends Node
## End-to-end movement checks use the real controller and physics world.
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	print(("PASS " if condition else "FAIL ")+message)
	if not condition: failures.append(message)

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func run(city: Node3D) -> void:
	await frames(5)
	var p = city.explorer
	p.set_capture(true)
	p.observing = false
	p.ground_camera.make_current()
	p.position = Vector3(0,1,90)
	await frames(60)
	check(p.is_on_floor(),"ground spawn settles on road")
	var start: Vector3 = p.position
	Input.action_press("forward")
	await frames(120)
	Input.action_release("forward")
	check(start.z-p.position.z > 9,"W moves character forward at walking speed")
	var saved: Vector3 = p.position
	p.toggle_mode()
	check(p.observer_camera.current and p.observing,"observer camera activates")
	Input.action_press("up")
	var old_height: float = p.observer_camera.position.y
	await frames(30)
	Input.action_release("up")
	check(p.observer_camera.position.y > old_height+5,"free-fly ascent works")
	p.toggle_mode()
	check(p.position.distance_to(saved)<0.05 and p.ground_camera.current,"mode switch preserves ground location")
	# Probe the current facade rather than assuming the original rectangular footprint.
	p.position = Vector3(48,1,91)
	p.rotation = Vector3.ZERO
	p.velocity = Vector3.ZERO
	await frames(30)
	var facade_ray := PhysicsRayQueryParameters3D.create(Vector3(48,1.1,91), Vector3(48,1.1,64))
	var facade_hit: Dictionary = city.get_world_3d().direct_space_state.intersect_ray(facade_ray)
	var approach_start: Vector3 = p.position
	Input.action_press("forward")
	# The narrower wave tower is farther from the street than the old facade.
	await frames(420)
	var stopped: Vector3 = p.position
	await frames(90)
	Input.action_release("forward")
	var facade_blocks := false
	if not facade_hit.is_empty():
		var wall: Vector3 = facade_hit.position
		facade_blocks = wall.z > 64 and wall.z < 83 \
			and approach_start.z - stopped.z > 2 \
			and p.position.z > wall.z + 0.15 and p.position.z < wall.z + 0.8 \
			and p.position.distance_to(stopped) < 0.08
	print("FACADE_FINAL ", p.position, " hit=", facade_hit.get("position", "none"))
	check(facade_blocks,"building collision stops walking through facade")
	# Full stair ascent from ground to the skywalk; requires physical access opening.
	p.position = Vector3(24,0.5,68)
	p.velocity = Vector3.ZERO
	await frames(30)
	Input.action_press("forward")
	Input.action_press("sprint")
	await frames(310)
	Input.action_release("forward")
	Input.action_release("sprint")
	await frames(10)
	print("STAIR_FINAL ",p.position)
	check(p.position.y>11.8 and p.position.z<24,"stairs reach the skywalk without jumping")
	# Terrace opening is reachable from the east side of the skywalk.
	p.position = Vector3(34,12.3,20)
	p.velocity = Vector3.ZERO
	await frames(30)
	Input.action_press("forward")
	await frames(150)
	Input.action_release("forward")
	check(p.position.z<9 and p.position.y>11.5,"skywalk opens onto accessible rooftop terrace")
	# Walk across bridge, then deliberately into its north railing.
	p.position = Vector3(24,12.3,20)
	p.velocity = Vector3.ZERO
	await frames(30)
	Input.action_press("left")
	await frames(270)
	Input.action_release("left")
	check(p.position.x<2 and p.position.y>11.8,"skywalk supports crossing above boulevard")
	Input.action_press("forward")
	await frames(90)
	Input.action_release("forward")
	check(p.position.z>16.4 and p.position.y>11.8,"skywalk railing prevents falling north")
	p.position = Vector3(0,0.3,90)
	p.velocity = Vector3.ZERO
	await frames(30)
	Input.action_press("jump")
	await frames(10)
	Input.action_release("jump")
	check(p.position.y>0.6,"ground jump works")
	await frames(70)
	check(p.is_on_floor(),"jump returns to ground")
	var binding: String = p.bindings.toggle_mode
	p.bind_action("toggle_mode","F8",false)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F8
	event.keycode = KEY_F8
	event.pressed = true
	var was_observer: bool = p.observing
	p._unhandled_input(event)
	check(p.observing != was_observer,"rebound mode key activates mode switch")
	p.bind_action("toggle_mode",binding,false)
	p.set_capture(false)
	print("STAGE1_QA ",JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
