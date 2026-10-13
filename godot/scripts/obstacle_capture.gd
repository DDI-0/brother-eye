extends SceneTree
func _initialize() -> void:call_deferred("capture")
func capture() -> void:
	var city=load("res://scenes/city.tscn").instantiate();root.add_child(city);city.hud.hide()
	var nav=preload("res://scripts/pedestrian_navigation.gd").new();city.add_child(nav);nav.setup(city);nav.automatic=false;nav.status.hide()
	await nav.rebuilt
	var person=nav.pedestrian
	person.position=Vector3(12.210466384887695,-.09978044033050537,82.59980773925781)
	person.model.rotation.y=-PI/2
	var camera:=Camera3D.new();camera.fov=55;city.add_child(camera);camera.make_current()
	camera.position=person.position+Vector3(2.5,1.8,3)
	camera.look_at(person.position+Vector3(0,.8,0))
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/obstacle-fix/before-curb.png")
	person.go_to(Vector3(18,.12,90))
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/obstacle-fix/after-curb.png")
	print("OBSTACLE_CAPTURE position=",person.position," steps=",person.step_count)
	quit()
