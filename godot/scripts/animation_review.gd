extends Node3D
## Isolated Stage 3B review. No backend, city save, navigation or crowd.
const CLIPS := ["idle", "walk", "run", "sit_down", "sit_idle", "stand_up"]
var characters: Array[Node3D] = []
var players: Array[AnimationPlayer] = []
var benches: Array[Node3D] = []
var camera: Camera3D
var status: Label
var clip := "idle"
var paused := false
var yaw := 0.35
var distance := 5.8
var dragging := false
var pending := ""
var elapsed := 0.0

func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("111e2c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b6c9db")
	world.environment.ambient_light_energy = .65
	world.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	add_child(world)
	for item in [[Vector3(-35,-25,0),Color("fff2df"),1.8], [Vector3(-25,145,0),Color("9edcf3"),.7]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = item[0]
		light.light_color = item[1]
		light.light_energy = item[2]
		add_child(light)
	for index in 2:
		var model: Node3D = load("res://models/animated/" + ["civilian", "exceptional_agent"][index] + ".glb").instantiate()
		model.position.x = -1.0 if index == 0 else 1.0
		add_child(model)
		characters.append(model)
		var player: AnimationPlayer = model.find_child("AnimationPlayer",true,false)
		players.append(player)
		player.animation_finished.connect(_finished.bind(index))
		for name in CLIPS:
			var animation := player.get_animation(name)
			animation.loop_mode = Animation.LOOP_LINEAR if name in ["idle","walk","run","sit_idle"] else Animation.LOOP_NONE
		var platform := box(Vector3(1.65,.04,2.0),Vector3(model.position.x,-.02,0),Color("294457"))
		add_child(platform)
		# Contact reference is a simple seat, not furniture added to the city.
		var bench := Node3D.new()
		bench.position = Vector3(model.position.x,0,.28)
		bench.add_child(box(Vector3(.64,.06,.52),Vector3(0,.46 if index == 0 else .56,0),Color("537182")))
		for x in [-.25,.25]:bench.add_child(box(Vector3(.045,.43 if index == 0 else .53,.045),Vector3(x,.215 if index == 0 else .265,.15),Color("253a48")))
		add_child(bench)
		benches.append(bench)
		var label := Label3D.new()
		label.text = ["CIVILIAN", "EXCEPTIONAL AGENT"][index]
		label.font_size = 40
		label.pixel_size = .0018
		label.position = Vector3(model.position.x,2.12,0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
	camera = Camera3D.new()
	camera.fov = 40
	add_child(camera)
	camera.make_current()
	update_camera()
	var hud := CanvasLayer.new()
	add_child(hud)
	status = Label.new()
	status.position = Vector2(30,25)
	status.add_theme_font_size_override("font_size",20)
	hud.add_child(status)
	var help := Label.new()
	help.position = Vector2(30,810)
	help.text = "1 IDLE   2 WALK   3 RUN   4 SIT DOWN   5 STAND UP   SPACE PAUSE\nDRAG TO ORBIT   SCROLL TO ZOOM   TAB SIDE VIEW   ESC CLOSE\nIN-PLACE MOTION REVIEW · TRAVEL AND OBSTACLE AVOIDANCE COME IN STEP 3C"
	hud.add_child(help)
	play_clip("idle",true)

func box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .85
	node.material_override = mat
	return node

func update_camera() -> void:
	camera.position = Vector3(sin(yaw)*distance,1.65,-cos(yaw)*distance)
	camera.look_at(Vector3(0,1.0,0))

func play_clip(name: String, immediate := false) -> void:
	# Finish standing before locomotion, so a seated person cannot snap straight into a run.
	if not immediate and clip in ["sit_down","sit_idle"] and name in ["walk","run","idle"]:
		pending = name
		play_clip("stand_up",true)
		return
	pending = "" if name != "stand_up" else pending
	clip = name
	elapsed = 0
	for bench in benches:bench.visible = name in ["sit_down","sit_idle","stand_up"]
	for player in players:
		player.speed_scale = 0 if paused else 1
		player.play(name,0 if immediate else .18)
		if immediate:player.advance(0)

func _finished(name: StringName, index: int) -> void:
	if index != 0:return
	if name == "sit_down":play_clip("sit_idle",true)
	elif name == "stand_up":play_clip(pending if pending != "" else "idle",true)

func _process(delta: float) -> void:
	if not paused:elapsed += delta
	if is_instance_valid(status):status.text = "BROTHER EYE  /  STAGE 3B MOTION REVIEW\n%s  ·  %.2f s  %s" % [clip.to_upper(),elapsed,"PAUSED" if paused else "PLAYING"]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5]:
			var name: String = ["idle","walk","run","sit_down","stand_up"][event.keycode-KEY_1]
			if name == "sit_down" and clip in ["sit_down","sit_idle"]:return
			if name == "stand_up" and clip not in ["sit_down","sit_idle"]:return
			play_clip(name)
		elif event.keycode == KEY_SPACE:
			paused = not paused
			for player in players:player.speed_scale = 0 if paused else 1
		elif event.keycode == KEY_TAB:yaw = PI/2 if yaw < 1 else .35;update_camera()
		elif event.keycode == KEY_ESCAPE:get_tree().quit()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance*(.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1),3,9)
			update_camera()
	if event is InputEventMouseMotion and dragging:yaw += event.relative.x*.01;update_camera()
