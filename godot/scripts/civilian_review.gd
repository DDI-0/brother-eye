extends Node3D
## Isolated appearance review. No simulation, navigation or crowd is started here.
var character: Node3D
var camera: Camera3D
var yaw := 0.0
var distance := 3.2
var dragging := false

func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("111e2c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b6c9db")
	world.environment.ambient_light_energy = 0.65
	world.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.environment.ssao_enabled = true
	add_child(world)
	for item in [[Vector3(-35,-25,0),Color("fff2df"),1.8], [Vector3(-25,145,0),Color("9edcf3"),0.7]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = item[0]
		light.light_color = item[1]
		light.light_energy = item[2]
		light.shadow_enabled = false
		add_child(light)
	character = preload("res://models/civilian/civilian.glb").instantiate()
	character.name = "CivilianAppearance"
	add_child(character)
	var platform := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.68
	disc.bottom_radius = 0.7
	disc.height = 0.04
	platform.mesh = disc
	platform.position.y = -0.02
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color("1c3142")
	finish.roughness = 0.85
	platform.material_override = finish
	add_child(platform)
	camera = Camera3D.new()
	camera.fov = 39
	add_child(camera)
	camera.make_current()
	set_view(1)
	var hud := CanvasLayer.new()
	add_child(hud)
	var label := Label.new()
	label.position = Vector2(32,28)
	label.text = "BROTHER EYE  /  CIVILIAN APPEARANCE\nSTAGE 3A  ·  1.80 M  ·  UNRIGGED REVIEW"
	label.add_theme_font_size_override("font_size",18)
	hud.add_child(label)
	var help := Label.new()
	help.text = "1 FRONT    2 THREE-QUARTER    3 BACK    4 DETAIL\nDRAG TO ROTATE    SCROLL TO ZOOM    ESC TO CLOSE"
	help.position = Vector2(32,824)
	hud.add_child(help)

func set_view(index: int) -> void:
	character.rotation.y = [0.0,0.5,PI,0.2][index]
	distance = 3.2 if index != 3 else 1.1
	camera.position = Vector3(0,1.1,-distance) if index != 3 else Vector3(0,1.52,-distance)
	camera.look_at(Vector3(0,.90,0) if index != 3 else Vector3(0,1.48,0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:set_view(event.keycode-KEY_1)
		elif event.keycode == KEY_ESCAPE:get_tree().quit()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1),.7,5)
			camera.position.z = -distance
	if event is InputEventMouseMotion and dragging:character.rotation.y += event.relative.x*.01
