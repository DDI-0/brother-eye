extends Node3D

const Kit = preload("res://scripts/geometry.gd")
const Composition = preload("res://scripts/city_composition.gd")
const Explorer = preload("res://scripts/explorer.gd")
const Interface = preload("res://scripts/interface.gd")
const BuildingAsset = preload("res://models/futuristic_building/scene.gltf")
const HelixTower = preload("res://scripts/helix_tower.gd")
var kit: RefCounted
var explorer: CharacterBody3D
var hud: CanvasLayer
var satellite: Node3D
var satellite_signal: MeshInstance3D
var command_signal: MeshInstance3D
var command_feedback: Node
var world_environment: WorldEnvironment
var rng := RandomNumberGenerator.new()
var elapsed := 0.0
var qa_mode := false
var simulation: Node
var pedestrian_navigation: Node3D
var population: Node3D
var inspector: CanvasLayer
var visual_budget: RefCounted

func _ready() -> void:
	qa_mode = "--qa" in OS.get_cmdline_user_args()
	rng.seed = 71026
	kit = Kit.new(self)
	build_environment()
	build_ground()
	build_district()
	build_command()
	build_bridge()
	build_street_detail()
	Composition.new(kit)
	build_satellite()
	kit.flush()
	visual_budget=preload("res://scripts/visual_budget.gd").new()
	visual_budget.setup(self)
	explorer = Explorer.new()
	explorer.name = "Explorer"
	add_child(explorer)
	hud = Interface.new()
	hud.name = "Interface"
	add_child(hud)
	hud.setup(explorer)
	var args := OS.get_cmdline_user_args()
	var tool_run := "--script" in OS.get_cmdline_args()
	if not qa_mode and not tool_run and not "--capture" in args:
		Engine.max_fps = 60
	if "--stage2-qa" in args or "--with-simulation" in args or (not qa_mode and not "--capture" in args and not tool_run and not "--no-simulation" in args):
		simulation = preload("res://scripts/simulation_bridge.gd").new()
		simulation.name = "Simulation"
		add_child(simulation)
		simulation.setup(self)
	if "--navigation-review" in args or "--navigation-qa" in args:
		pedestrian_navigation = preload("res://scripts/pedestrian_navigation.gd").new()
		add_child(pedestrian_navigation)
		pedestrian_navigation.setup(self)
	if simulation != null and not "--stage2-qa" in args:
		population = preload("res://scripts/persistent_population.gd").new()
		add_child(population)
		population.setup(self,simulation)
		command_feedback=preload("res://scripts/command_feedback.gd").new();add_child(command_feedback);command_feedback.setup(self)
		inspector=preload("res://scripts/inspection_panel.gd").new()
		add_child(inspector);inspector.setup(self)
	print("CITY_READY boxes=%d collision_shapes=%d" % [kit.box_count, kit.collision_count])
	if qa_mode:
		var qa = load("res://scripts/stage1_check.gd").new()
		add_child(qa)
		qa.run(self)
	elif "--capture" in OS.get_cmdline_user_args():
		var capture = load("res://scripts/capture.gd").new()
		add_child(capture)
		capture.run(self)

func build_environment() -> void:
	world_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var atmosphere := ShaderMaterial.new()
	atmosphere.shader = preload("res://shaders/city_sky.gdshader")
	# The quiet northeast crescent leaves the northwest satellite as the focal point.
	var moon_rotation := Vector3(deg_to_rad(-13), deg_to_rad(169), 0)
	atmosphere.set_shader_parameter("moon_direction", Basis.from_euler(moon_rotation).z)
	sky.sky_material = atmosphere
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.ambient_light_color = Color("8bafcf")
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.45
	env.glow_bloom = 0.06
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.3
	env.glow_hdr_scale = 1.0
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	# A light aerial haze keeps distant buildings readable without veiling the eye.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.00012
	env.volumetric_fog_albedo = Color("6885a2")
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_length = 1400.0
	env.fog_enabled = true
	env.fog_light_color = Color("6687a6")
	env.fog_density = 0.00012
	env.fog_sky_affect = 0.15
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 1.8
	world_environment.environment = env
	add_child(world_environment)
	# Diffuse twilight key: soft illumination without another visible celestial disc.
	var twilight_key := DirectionalLight3D.new()
	twilight_key.name = "TwilightKey"
	twilight_key.rotation_degrees = Vector3(-18, 169, 0)
	twilight_key.light_color = Color("bcd4ec")
	twilight_key.light_energy = 0.7
	twilight_key.light_specular = 0.35
	twilight_key.light_angular_distance = 0.7
	twilight_key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	twilight_key.shadow_enabled = true
	twilight_key.directional_shadow_max_distance = 350
	twilight_key.directional_shadow_blend_splits = true
	add_child(twilight_key)
	var rim_light := DirectionalLight3D.new()
	rim_light.name = "SoftSkyFill"
	rim_light.rotation_degrees = Vector3(-35,-32,0)
	rim_light.light_color = Color("b2d7f1")
	rim_light.light_energy = 0.5
	rim_light.shadow_enabled = false
	# Fill light contributes no second sun to the sky.
	rim_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(rim_light)

func build_ground() -> void:
	# Massive foundation plate extends 1600m to eliminate any void under skyline towers
	kit.box(Vector3(0,-1.0,0),Vector3(3200,1.2,3200),"road",true)
	kit.box(Vector3(0,-0.4,0),Vector3(420,0.6,420),"navy",true)
	# Raised block sidewalks with low curbs the controller can step onto.
	for x in [-105.0,-48.0,48.0,105.0]:
		for z in [-110.0,-48.0,64.0,124.0]:
			kit.box(Vector3(x,0, z),Vector3(44,0.24,46),"paving",true)
			for edge in [-1,1]:
				kit.box(Vector3(x+edge*21.8,0.16,z),Vector3(0.15,0.1,46),"edge")
	for x in [-17.0,17.0]:
		kit.box(Vector3(x,0,0),Vector3(9,0.24,320),"paving",true)
		kit.box(Vector3(x-sign(x)*4.3,0.15,0),Vector3(0.13,0.07,320),"window")
	for z in range(-150,161,10):
		kit.box(Vector3(-1.2,-0.07,z),Vector3(0.1,0.025,4),"edge")
		kit.box(Vector3(1.2,-0.07,z),Vector3(0.1,0.025,4),"edge")
	for z in [-76.0,-14.0,92.0]:
		for x in range(-11,12,2):
			kit.box(Vector3(x,-0.05,z),Vector3(0.8,0.025,3.5),"edge")
	kit.box(Vector3(0,0,-40),Vector3(40,0.24,37),"paving",true)
	# Border walls contain the playable district; distant towers form the skyline.
	for x in [-179.0,179.0]:
		kit.box(Vector3(x,2,0),Vector3(2,4,360),"steel",true)
	for z in [-179.0,179.0]:
		kit.box(Vector3(0,2,z),Vector3(360,4,2),"steel",true)

func _cylindrical_windows(pos: Vector3, radius: float, height: float, pitch: float, columns: int) -> void:
	for floor_i in range(1, int(height / pitch)):
		var y := floor_i * pitch
		for col in columns:
			if rng.randf() < 0.2:
				continue
			var angle := float(col) * TAU / columns
			var mat := "window" if rng.randf() < 0.7 else "ice"
			if rng.randf() < 0.035:
				mat = "warm"
			kit.box(pos + Vector3(cos(angle) * (radius + 0.12), y, sin(angle) * (radius + 0.12)), Vector3(0.12, 0.55, radius * 0.3), mat, false, Vector3(0, angle, 0))

func _tower_entrance(pos: Vector3, radius: float, label_text: String) -> void:
	kit.box(pos + Vector3(0, 1.7, radius + 0.5), Vector3(3, 3.3, 0.12), "glass")
	for x_off in [-1.6, 1.6]:
		kit.box(pos + Vector3(x_off, 1.8, radius + 0.6), Vector3(0.12, 3.6, 0.2), "cyan")
	kit.box(pos + Vector3(0, 4, radius + 0.8), Vector3(8, 0.4, 3.2), "navy")
	kit.label(label_text, pos + Vector3(0, 4.8, radius + 0.7), 40, 0.018)

func tower(pos: Vector3, width: float, depth: float, height: float, variant: int, distant := false) -> void:
	var base_r := (width + depth) * 0.25
	match variant % 7:
		0: tower_helix(pos, height, distant)
		1: tower_model(pos, height, distant)
		2: tower_pyramid(pos, base_r, height, variant, distant)
		3: tower_wave(pos, base_r, height, variant, distant)
		4: tower_fork(pos, base_r, height, variant, distant)
		5: tower_disc(pos, base_r, height, variant, distant)
		6: tower_blade(pos, base_r, height, variant, distant)

func tower_helix(pos: Vector3, height: float, distant := false) -> void:
	HelixTower.new(kit, pos, height, distant)

func tower_model(pos: Vector3, height: float, distant := false) -> void:
	var inst: Node3D = BuildingAsset.instantiate()
	inst.position = pos
	var scale_factor: float = height / 5.8
	inst.scale = Vector3(scale_factor, scale_factor, scale_factor)
	add_child(inst)
	if not distant:
		_model_collision(inst)

func _model_collision(node: Node) -> void:
	# Follow the imported building's stepped parts instead of filling the entire
	# tower footprint to its requested height with one oversized solid cylinder.
	if node is MeshInstance3D and node.mesh:
		var bounds: AABB = node.global_transform * node.mesh.get_aabb()
		if bounds.size.x > 0.001 and bounds.size.y > 0.001 and bounds.size.z > 0.001:
			var shape := BoxShape3D.new()
			shape.size = bounds.size
			kit.collider(shape, Transform3D(Basis(), bounds.get_center()))
	for child in node.get_children():
		_model_collision(child)

func tower_spire(pos: Vector3, base_r: float, height: float, variant: int, distant: bool) -> void:
	# 1. Main Octagonal Faceted Hull (8 segments)
	var body_h := height * 0.45
	kit.cylinder(pos + Vector3(0, body_h * 0.5, 0), base_r * 0.45, body_h, "navy", base_r * 0.42, null, not distant, 8)
	
	# 2. Stepped Beveled Base Plinth
	kit.cylinder(pos + Vector3(0, 1.2, 0), base_r * 0.55, 2.4, "steel", base_r * 0.48, null, not distant, 8)
	kit.cylinder(pos + Vector3(0, 2.8, 0), base_r * 0.5, 1.0, "edge", -1.0, null, not distant, 8)
	
	# 3. Recessed Horizontal Luminous Bands (Cyan & Red)
	kit.cylinder(pos + Vector3(0, body_h * 0.35, 0), base_r * 0.46, 0.4, "cyan", -1.0, null, false, 8)
	kit.cylinder(pos + Vector3(0, body_h * 0.65, 0), base_r * 0.44, 0.35, "red", -1.0, null, false, 8)
	kit.cylinder(pos + Vector3(0, body_h * 0.72, 0), base_r * 0.43, 0.35, "cyan", -1.0, null, false, 8)
	kit.cylinder(pos + Vector3(0, body_h * 0.79, 0), base_r * 0.42, 0.35, "red", -1.0, null, false, 8)

	# 4. Outrigger Stabilizer Legs with Foot Pads and Glowing Beacon Points
	for leg_i in 4:
		var leg_ang: float = float(leg_i) * TAU / 4.0 + PI / 4.0
		var leg_root := pos + Vector3(cos(leg_ang) * base_r * 0.48, 1.8, sin(leg_ang) * base_r * 0.48)
		var leg_foot := pos + Vector3(cos(leg_ang) * base_r * 0.95, 0.2, sin(leg_ang) * base_r * 0.95)
		kit.beam(leg_root, leg_foot, 0.35, "steel")
		kit.box(leg_foot, Vector3(0.8, 0.25, 0.8), "steel")
		var beacon_mat := "red" if leg_i % 2 == 0 else "cyan"
		kit.box(leg_foot + Vector3(0, 0.35, 0), Vector3(0.25, 0.45, 0.25), beacon_mat)

	# 5. Vertical Side Conduit Pipe (curves into the main hull)
	var pipe_x := -base_r * 0.46
	kit.cylinder(pos + Vector3(pipe_x, body_h * 0.45, 0), base_r * 0.08, body_h * 0.7, "steel", -1.0, null, false, 16)
	kit.cylinder(pos + Vector3(pipe_x, body_h * 0.3, 0), base_r * 0.1, 1.2, "cyan", -1.0, null, false, 16)
	kit.cylinder(pos + Vector3(pipe_x, body_h * 0.6, 0), base_r * 0.1, 1.2, "steel", -1.0, null, false, 16)
	kit.beam(pos + Vector3(pipe_x, body_h * 0.12, 0), pos + Vector3(pipe_x * 0.5, body_h * 0.08, 0), 0.18, "steel")

	# 6. Secondary Communication Antenna Mast linked by Horizontal Gantry
	var mast_x := base_r * 0.65
	var mast_h := height * 0.75
	kit.cylinder(pos + Vector3(mast_x, mast_h * 0.45, 0), base_r * 0.09, mast_h * 0.9, "steel", base_r * 0.04, null, false, 16)
	var gantry_y := height * 0.68
	kit.beam(pos + Vector3(0, gantry_y, 0), pos + Vector3(mast_x, gantry_y, 0), 0.25, "steel")
	kit.beam(pos + Vector3(0, gantry_y + 0.12, 0), pos + Vector3(mast_x, gantry_y + 0.12, 0), 0.08, "cyan")
	kit.box(pos + Vector3(mast_x, mast_h * 0.92, 0), Vector3(0.35, 0.65, 0.35), "red")
	kit.box(pos + Vector3(mast_x, mast_h * 0.55, 0), Vector3(0.3, 0.45, 0.3), "red")
	kit.box(pos + Vector3(mast_x, mast_h * 0.35, 0), Vector3(0.28, 0.45, 0.28), "cyan")

	# 7. Third Small Outrigger Antenna (front-right)
	var ant_z := base_r * 0.52
	kit.cylinder(pos + Vector3(base_r * 0.25, height * 0.2, ant_z), base_r * 0.05, height * 0.4, "steel", 0.02, null, false, 12)
	kit.box(pos + Vector3(base_r * 0.25, height * 0.42, ant_z), Vector3(0.2, 0.4, 0.2), "red")

	# 8. Mid Transition Neck & Upper Telescoping Spires
	kit.cylinder(pos + Vector3(0, body_h + 3, 0), base_r * 0.28, 6, "steel", base_r * 0.2, null, false, 8)
	kit.cylinder(pos + Vector3(0, body_h + 6, 0), base_r * 0.22, 1.2, "cyan", -1.0, null, false, 8)
	kit.cylinder(pos + Vector3(0, body_h + 10, 0), base_r * 0.18, 8, "navy", base_r * 0.14, null, false, 8)
	
	# 9. Top Needle Tip with Glowing Beacon
	kit.cylinder(pos + Vector3(0, height + 4, 0), base_r * 0.08, 12, "steel", 0.02, null, false, 16)
	kit.box(pos + Vector3(0, height + 10.2, 0), Vector3(0.22, 1.4, 0.22), "cyan")
	kit.box(pos + Vector3(0, height + 11.2, 0), Vector3(0.38, 0.6, 0.38), "red")
	
	if not distant:
		_tower_entrance(pos, base_r * 0.55, ["ARRAY / SPIRE", "MONITOR SPIRE", "BEACON TOWER", "DATA COMM"][variant % 4])

func tower_pyramid(pos: Vector3, base_r: float, height: float, variant: int, distant: bool) -> void:
	# Narrow stem widening into a dramatic inverted cone.
	kit.cylinder(pos + Vector3(0, height * 0.15, 0), base_r * 0.22, height * 0.3, "navy", base_r * 0.18, null, not distant)
	kit.cylinder(pos + Vector3(0, height * 0.52, 0), base_r * 0.28, height * 0.5, "navy", base_r * 0.82, null, not distant)
	kit.cylinder(pos + Vector3(0, height * 0.88, 0), base_r * 0.82, height * 0.2, "steel", base_r * 0.65)
	if not distant:
		kit.cylinder(pos + Vector3(0, height * 0.52, 0), base_r * 0.3, height * 0.46, "glass", base_r * 0.78)
	# Floating observation disc above the crown.
	kit.cylinder(pos + Vector3(0, height + 4, 0), base_r * 0.45, 1.5, "steel")
	kit.torus_ring(pos + Vector3(0, height + 4, 0), base_r * 0.4, base_r * 0.5, "cyan", 32, 8)
	# Structural buttress beams from base to crown.
	if not distant:
		for a in 4:
			var angle: float = float(a) * TAU / 4.0 + PI / 4.0
			var bot := pos + Vector3(cos(angle) * base_r * 0.35, height * 0.08, sin(angle) * base_r * 0.35)
			var top_pt := pos + Vector3(cos(angle) * base_r * 0.95, height * 0.72, sin(angle) * base_r * 0.95)
			kit.beam(bot, top_pt, 0.45, "edge")
			kit.beam(bot + Vector3(0, 0.4, 0), top_pt + Vector3(0, 0.4, 0), 0.1, "cyan")
	# Vertical energy seams.
	for side: float in [-1.0, 1.0]:
		kit.box(pos + Vector3(side * 0.15, height * 0.5, 0), Vector3(0.12, height * 0.85, 0.12), "cyan")
	# Antenna above observation disc with glowing red beacon.
	kit.cylinder(pos + Vector3(0, height + 8, 0), 0.15, 8, "steel", 0.0)
	kit.box(pos + Vector3(0, height + 12.2, 0), Vector3(0.2, 0.3, 0.2), "cyan")
	kit.box(pos + Vector3(0, height + 12.8, 0), Vector3(0.35, 0.45, 0.35), "red")
	# Base collar.
	kit.cylinder(pos + Vector3(0, 1.2, 0), base_r * 0.45, 2.4, "steel", -1.0, null, not distant)
	if not distant:
		_cylindrical_windows(pos + Vector3(0, height * 0.27, 0), base_r * 0.28, height * 0.5, 4.5, 6)
		_tower_entrance(pos, base_r * 0.45, ["APEX / INVERTED", "SKY ANCHOR", "GRAVITY WELL", "ASCENDANT"][variant % 4])

func tower_wave(pos: Vector3, base_r: float, height: float, variant: int, distant: bool) -> void:
	# Stacked offset cylinders create an organic S-curve profile.
	var sections := 7 if not distant else 4
	var section_h: float = height / float(sections)
	for i in sections:
		var t: float = float(i) / float(sections)
		var off_x: float = sin(t * TAU * 0.65 + float(variant) * 0.7) * base_r * 0.25
		var off_z: float = cos(t * TAU * 0.4 + float(variant) * 0.5) * base_r * 0.12
		var r: float = base_r * (0.32 + sin(t * PI) * 0.12)
		var sec_pos := pos + Vector3(off_x, section_h * (float(i) + 0.5), off_z)
		kit.cylinder(sec_pos, r, section_h * 1.04, "navy" if i % 2 == 0 else "steel", -1.0, null, not distant and i == 0)
		if i > 0:
			kit.cylinder(sec_pos - Vector3(0, section_h * 0.52, 0), r + 0.6, 0.7, "edge")
			if i % 2 == 0:
				kit.torus_ring(sec_pos - Vector3(0, section_h * 0.52, 0), r + 0.1, r + 0.7, "cyan", 32, 8)
	# Glass panels on the wider middle sections.
	if not distant:
		for gi in [2, 3, 4]:
			var gt: float = float(gi) / 7.0
			var gx: float = sin(gt * TAU * 0.65 + float(variant) * 0.7) * base_r * 0.25
			var gz: float = cos(gt * TAU * 0.4 + float(variant) * 0.5) * base_r * 0.12
			var gr: float = base_r * (0.32 + sin(gt * PI) * 0.12)
			kit.cylinder(pos + Vector3(gx, (height / 7.0) * (float(gi) + 0.5), gz), gr + 0.15, (height / 7.0) * 0.65, "glass", gr * 0.7)
	# Crown spire with beacon.
	kit.cylinder(pos + Vector3(0, height + 3, 0), base_r * 0.15, 8, "steel", 0.0)
	kit.box(pos + Vector3(0, height + 7.2, 0), Vector3(0.18, 1.2, 0.18), "cyan")
	kit.box(pos + Vector3(0, height + 8.1, 0), Vector3(0.32, 0.45, 0.32), "red")
	# Base.
	kit.cylinder(pos + Vector3(0, 1.5, 0), base_r * 0.55, 3, "steel", -1.0, null, not distant)
	if not distant:
		for wi in sections:
			var wt: float = float(wi) / float(sections)
			var wx: float = sin(wt * TAU * 0.65 + float(variant) * 0.7) * base_r * 0.25
			var wz: float = cos(wt * TAU * 0.4 + float(variant) * 0.5) * base_r * 0.12
			var wr: float = base_r * (0.32 + sin(wt * PI) * 0.12)
			_cylindrical_windows(pos + Vector3(wx, section_h * float(wi), wz), wr - 0.1, section_h, 4.0, 6)
		_tower_entrance(pos, base_r * 0.55, ["WAVE / ORGANIC", "FLOW TOWER", "UNDULATE", "BIO-FORM"][variant % 4])

func tower_fork(pos: Vector3, base_r: float, height: float, variant: int, distant: bool) -> void:
	# Single trunk for the lower 60% that splits into prongs.
	var trunk_h := height * 0.6
	kit.cylinder(pos + Vector3(0, trunk_h / 2, 0), base_r * 0.32, trunk_h, "navy", base_r * 0.28, null, not distant)
	if not distant:
		kit.cylinder(pos + Vector3(0, trunk_h * 0.5, 0), base_r * 0.35, trunk_h * 0.75, "glass", base_r * 0.26)
	# Prongs splitting outward from the fork point.
	var prong_h := height * 0.45
	var num_prongs := 2 + (variant % 2)
	for p_idx in num_prongs:
		var angle: float = float(p_idx) * TAU / float(num_prongs) + PI / 6.0
		var splay: float = base_r * 0.35
		var prong_pos := pos + Vector3(cos(angle) * splay, trunk_h, sin(angle) * splay)
		kit.fin(prong_pos, base_r * 0.15, prong_h, base_r * 0.12, "steel")
		if not distant:
			kit.box(prong_pos + Vector3(0, prong_h * 0.5, 0), Vector3(0.12, prong_h * 0.8, 0.12), "cyan")
	# Energy beam rising between the prongs.
	kit.box(pos + Vector3(0, height * 0.7, 0), Vector3(0.3, height * 0.45, 0.3), "cyan")
	# Junction rings at the fork point.
	kit.torus_ring(pos + Vector3(0, trunk_h, 0), base_r * 0.35, base_r * 0.55, "cyan", 32, 8)
	kit.torus_ring(pos + Vector3(0, trunk_h + 2, 0), base_r * 0.2, base_r * 0.35, "edge", 32, 8)
	# Spire above the fork with beacon.
	kit.cylinder(pos + Vector3(0, height + 3, 0), 0.2, 8, "steel", 0.0)
	kit.box(pos + Vector3(0, height + 7.2, 0), Vector3(0.2, 1.2, 0.2), "cyan")
	kit.box(pos + Vector3(0, height + 8.1, 0), Vector3(0.35, 0.45, 0.35), "red")
	# Base.
	kit.cylinder(pos + Vector3(0, 1.5, 0), base_r * 0.55, 3, "steel", -1.0, null, not distant)
	if not distant:
		_cylindrical_windows(pos, base_r * 0.33, trunk_h, 3.8, 8)
		_tower_entrance(pos, base_r * 0.55, ["FORK / TRIDENT", "PRONG SPIRE", "SCHISM TOWER", "DIVERGENT"][variant % 4])

func tower_disc(pos: Vector3, base_r: float, height: float, variant: int, distant: bool) -> void:
	# Narrow central spine with floating disc platforms.
	kit.cylinder(pos + Vector3(0, height / 2, 0), base_r * 0.12, height, "navy", -1.0, null, not distant)
	var num_discs := (5 + variant % 3) if not distant else 3
	for i in num_discs:
		var t: float = float(i + 1) / float(num_discs + 1)
		var disc_r: float = base_r * (0.75 - t * 0.25)
		var disc_y: float = t * height
		kit.cylinder(pos + Vector3(0, disc_y, 0), disc_r, 2.5, "steel")
		kit.torus_ring(pos + Vector3(0, disc_y, 0), disc_r - 0.3, disc_r + 0.1, "cyan", 32, 8)
		if not distant and i > 0:
			kit.cylinder(pos + Vector3(0, disc_y - 1.5, 0), disc_r * 0.8, 1.2, "glass", disc_r * 0.5)
	# Vertical energy core through the spine.
	kit.box(pos + Vector3(0, height * 0.5, 0), Vector3(0.15, height, 0.15), "blue")
	# Spire tip with beacon.
	kit.cylinder(pos + Vector3(0, height + 5, 0), base_r * 0.08, 10, "steel", 0.0)
	kit.box(pos + Vector3(0, height + 10.2, 0), Vector3(0.2, 1, 0.2), "cyan")
	kit.box(pos + Vector3(0, height + 11.0, 0), Vector3(0.32, 0.45, 0.32), "red")
	# Base platform (widest disc at ground level).
	kit.cylinder(pos + Vector3(0, 1.5, 0), base_r * 0.9, 3, "steel", -1.0, null, not distant)
	kit.torus_ring(pos + Vector3(0, 3.1, 0), base_r * 0.8, base_r * 0.95, "edge", 32, 8)
	if not distant:
		for di in num_discs:
			var dt: float = float(di + 1) / float(num_discs + 1)
			var dr: float = base_r * (0.75 - dt * 0.25)
			_cylindrical_windows(pos + Vector3(0, dt * height - 1.2, 0), dr * 0.7, 2.5, 2.5, 6)
		_tower_entrance(pos, base_r * 0.9, ["DISC / ORBITAL", "RING STATION", "PLATFORM SPIRE", "STACKED ARRAY"][variant % 4])

func tower_blade(pos: Vector3, base_r: float, height: float, variant: int, distant: bool) -> void:
	# Sweeping blade-fin silhouette with spiral energy bands.
	kit.fin(pos, base_r * 0.15, height * 1.05, base_r * 0.8, "navy")
	kit.fin(pos + Vector3(base_r * 0.2, 0, 0), base_r * 0.1, height * 0.85, base_r * 0.5, "steel")
	# Helical energy bands around the blade.
	var blade_turns := height / 30.0
	var seg := 8 if not distant else 5
	kit.helix_beam(pos, base_r * 0.55, height, 0.15, blade_turns, seg, "cyan", 0.0)
	# Floating torus rings.
	kit.torus_ring(pos + Vector3(0, height * 0.5, 0), base_r * 0.6, base_r * 0.8, "cyan", 32, 8)
	if not distant:
		kit.torus_ring(pos + Vector3(0, height * 0.75, 0), base_r * 0.4, base_r * 0.55, "blue", 32, 8)
	# Vertical energy seams on blade edges.
	for side: float in [-1.0, 1.0]:
		kit.box(pos + Vector3(0, height * 0.5, side * base_r * 0.41), Vector3(0.12, height * 0.9, 0.12), "cyan")
	# Spire tip with beacon.
	kit.cylinder(pos + Vector3(0, height + 4, 0), 0.15, 10, "steel", 0.0)
	kit.box(pos + Vector3(0, height + 9.2, 0), Vector3(0.2, 1.5, 0.2), "cyan")
	kit.box(pos + Vector3(0, height + 10.2, 0), Vector3(0.35, 0.5, 0.35), "red")
	# Base platform.
	kit.cylinder(pos + Vector3(0, 1.5, 0), base_r * 0.7, 3, "steel", -1.0, null, not distant)
	if not distant:
		# Windows on the flat blade faces.
		for floor_i in range(3, int(height / 4)):
			var y := floor_i * 4.0
			for col in range(-2, 3):
				if rng.randf() < 0.2:
					continue
				var mat := "window" if rng.randf() < 0.7 else "ice"
				if rng.randf() < 0.035:
					mat = "warm"
				for side: float in [-1.0, 1.0]:
					kit.box(pos + Vector3(base_r * 0.08 + 0.12, y, side * float(col) * base_r * 0.15), Vector3(0.12, 0.55, base_r * 0.08), mat)
		_tower_entrance(pos, base_r * 0.7, ["BLADE / EDGE", "RAZOR SPIRE", "MONOLITH FIN", "KEEN TOWER"][variant % 4])

func rooftop(pos: Vector3, variant: int) -> void:
	for x in [-4.0,3.0]:
		kit.box(pos+Vector3(x,1.2,0),Vector3(4,2.4,6),"steel")
		for z in range(-2,3):
			kit.box(pos+Vector3(x,2.44,z),Vector3(3.4,0.1,0.2),"edge")
	mast(pos+Vector3(3,2.5,-3),11+variant%4*2)
	if variant%2 == 0:
		for x in [-3.0,0.0,3.0]:
			kit.cylinder(pos+Vector3(x,2.2,5),1.15,4.4)
			for y in [1.0,3.2]:
				kit.cylinder(pos+Vector3(x,y,5),1.23,0.2,"edge")

func mast(pos: Vector3, height: float) -> void:
	for x in [-0.65,0.65]:
		kit.box(pos+Vector3(x,height/2,0),Vector3(0.15,height,0.15),"edge")
	for y in range(0,int(height)-2,2):
		kit.beam(pos+Vector3(-0.65,y,0),pos+Vector3(0.65,y+2,0),0.09)
	kit.box(pos+Vector3(0,height+1,0),Vector3(0.12,3,0.12),"steel")
	kit.box(pos+Vector3(0,height+2.6,0),Vector3(0.24,0.2,0.24),"cyan")
	var dish := SphereMesh.new()
	dish.radius = 1.5
	dish.height = 1.0
	dish.radial_segments = 12
	dish.rings = 6
	var m: MeshInstance3D = kit.mesh(dish,pos+Vector3(0,height*0.6,0.7),"edge",Vector3(PI/2,0,0))
	m.scale = Vector3(1,0.3,1)

func build_district() -> void:
	var i := 0
	for x in [-105.0,-48.0,48.0,105.0]:
		for z in [-110.0,-48.0,64.0,124.0]:
			var h := rng.randf_range(43,100)
			if z > 100: h *= 0.65
			var cur_variant := i
			if x == -48.0 and z == -48.0:
				cur_variant = 0
				h = 88.0
			elif x == 48.0 and z == -48.0:
				cur_variant = 0
				h = 96.0
			# Preserve the original transit circles; set conflicting towers back from them.
			var tower_x: float = x
			if x == -105.0 and z == -110.0: tower_x = -120.0
			elif x == -105.0 and z == 64.0: tower_x = -118.0
			elif x == 105.0 and z == -110.0: tower_x = 119.0
			elif x == 105.0 and z == 64.0: tower_x = 121.0
			elif x == 105.0 and z == -48.0: tower_x = 98.0
			elif x == -105.0 and z == -48.0: h *= 0.98
			if tower_x != x:
				kit.box(Vector3(tower_x,0,z),Vector3(34,0.24,34),"paving",true)
			tower(Vector3(tower_x,0.12,z),rng.randf_range(22,30),rng.randf_range(22,30),h,cur_variant)
			i += 1
	for x in [-105.0,105.0]:
		tower(Vector3(sign(x)*100,0.12,12),29,35,37,2)
	# Broad low-rise platforms make the raised route feel structurally supported.
	for x in [-46.0,46.0]:
		kit.box(Vector3(x,5.8,7),Vector3(34,11.6,34),"navy",true)
		kit.box(Vector3(x,11.8,7),Vector3(36,0.4,36),"paving",true)
		for y in [2.0,5.0,8.0]:
			kit.box(Vector3(x,y,24.1),Vector3(31,0.7,0.18),"window")
		kit.label("CIVIC EXCHANGE" if x<0 else "OBSERVATORY",Vector3(x,6.5,24.25),56,0.028)
		for edge_x in [-18.0,18.0]:
			# The inner rail stops at the skywalk so pedestrians can enter the terrace.
			var inner := absf(x+edge_x)<30
			kit.box(Vector3(x+edge_x,12.55,2.5 if inner else 6.5),Vector3(0.15,1.1,27 if inner else 35),"edge",true)
		kit.box(Vector3(x,12.55,-11),Vector3(36,1.1,0.15),"edge",true)
		# Geodesic-like roof dome and segmented frame.
		var dome := SphereMesh.new()
		dome.radius = 6
		dome.height = 12
		dome.radial_segments = 12
		dome.rings = 6
		var d: MeshInstance3D = kit.mesh(dome,Vector3(x,12,-2),"glass")
		d.scale.y = 0.7
		kit.collider(dome.create_convex_shape(),Transform3D(Basis.from_scale(Vector3(1,0.7,1)),Vector3(x,12,-2)))
		for n in 12:
			var a := n*TAU/12
			kit.beam(Vector3(x+cos(a)*6,12,sin(a)*6-2),Vector3(x,16.2,-2),0.13)

func build_command() -> void:
	var headquarters := preload("res://scripts/brother_eye_tower.gd").new(kit)
	command_signal = headquarters.build(self)
	# Plaza's concentric monument, low plinth and luminous axis.
	kit.cylinder(Vector3(0,0.3,-40),7,0.4,"steel",-1,null,true)
	for radius in [6.6,4.8]:
		var ring := TorusMesh.new()
		ring.inner_radius = radius-0.07
		ring.outer_radius = radius+0.07
		ring.rings = 48
		ring.ring_segments = 6
		kit.mesh(ring,Vector3(0,0.55,-40),"cyan")
	kit.cylinder(Vector3(0,2.2,-40),1.2,4,"navy",0.7,null,true)
	kit.cylinder(Vector3(0,4.4,-40),0.85,0.3,"cyan")
	var uplink := preload("res://scripts/planetary_uplink.gd").new()
	uplink.name = "CityUplink"
	uplink.position = Vector3(0,6.8,-40)
	add_child(uplink)
	kit.label("CITY UPLINK",Vector3(0,9.55,-39.8),30,0.022)
	var uplight := OmniLight3D.new()
	uplight.position = Vector3(0,4,-40)
	uplight.light_color = Color("00b5f0")
	uplight.light_energy = 2.5
	uplight.omni_range = 15
	add_child(uplight)
	for x in [-17.0,17.0]:
		kit.box(Vector3(x,0.2,-57),Vector3(0.12,0.08,33),"cyan")

func build_bridge() -> void:
	kit.box(Vector3(0,11.65,20),Vector3(128,0.7,8),"steel",true)
	kit.box(Vector3(0,12.04,20),Vector3(128,0.08,7.5),"paving")
	for side in [-1,1]:
		var z: float = 20+side*3.7
		var segments := [Vector2(0,56)] if side<0 else [Vector2(-45.25,37.5),Vector2(0,43),Vector2(45.25,37.5)]
		for segment in segments:
			kit.box(Vector3(segment.x,12.8,z),Vector3(segment.y,0.13,0.13),"edge")
			kit.box(Vector3(segment.x,12.9,z),Vector3(segment.y,0.045,0.16),"cyan")
			var rail_shape := BoxShape3D.new()
			rail_shape.size = Vector3(segment.y,1.2,0.2)
			kit.collider(rail_shape,Transform3D(Basis(),Vector3(segment.x,12.65,z)))
		for x in range(-64,65,4):
			if side == 1 and (abs(x-24)<=4 or abs(x+24)<=4): continue
			if side == -1 and abs(x)>28: continue
			kit.box(Vector3(x,12.5,z),Vector3(0.12,1,0.12),"edge")
		for x in range(-64,61,8):
			kit.beam(Vector3(x,9.7,z),Vector3(x+8,11.3,z),0.2)
			kit.beam(Vector3(x,11.3,z),Vector3(x+8,9.7,z),0.2)
		kit.box(Vector3(0,9.65,z),Vector3(128,0.22,0.3),"edge")
	for x in [-24.0,24.0]:
		build_stairs(x)
	for x in [-62.0,62.0]:
		kit.box(Vector3(x,5.7,20),Vector3(3,11.4,6),"steel",true)
	for x in [-64.0,64.0]:
		kit.box(Vector3(x,12.6,20),Vector3(0.2,1.2,8),"edge",true)
	kit.label("SKYWALK  /  12 M",Vector3(0,10.35,24.15),50,0.04)

func build_stairs(x: float) -> void:
	# 40 shallow treads over 40m; an invisible continuous incline avoids step jitter.
	for i in 40:
		var y := (i+1)*0.3
		kit.box(Vector3(x,y/2,63.5-i),Vector3(4.8,y,1),"steel")
		kit.box(Vector3(x,y+0.02,63.9-i),Vector3(4.6,0.025,0.08),"edge")
	var points := PackedVector3Array([
		Vector3(x-2.4,0,64),Vector3(x+2.4,0,64),Vector3(x-2.4,0,24),Vector3(x+2.4,0,24),Vector3(x-2.4,12,24),Vector3(x+2.4,12,24)])
	var slope := ConvexPolygonShape3D.new()
	slope.points = points
	kit.collider(slope,Transform3D.IDENTITY)
	for side in [-1,1]:
		var a := Vector3(x+side*2.45,1,64)
		var b := Vector3(x+side*2.45,13,24)
		kit.beam(a,b,0.12)
		kit.beam(a+Vector3(0,0.05,0),b+Vector3(0,0.05,0),0.05,"cyan")
		for i in range(0,41,4):
			kit.box(Vector3(x+side*2.45,i*0.3+0.5,64-i),Vector3(0.12,1,0.12),"edge")
		var length := a.distance_to(b)
		var rail := BoxShape3D.new()
		rail.size = Vector3(0.2,1.2,length)
		var rail_basis := Basis(Vector3.RIGHT,atan2(12.0,40.0))
		kit.collider(rail,Transform3D(rail_basis,(a+b)*0.5-Vector3(0,0.4,0)))
	kit.label("↑  SKYWALK",Vector3(x,1.7,66),40,0.025)

func build_street_detail() -> void:
	for x in [-16.0,16.0]:
		for z in range(-140,150,26):
			kit.box(Vector3(x,3.6,z),Vector3(0.2,7.2,0.2),"steel",true)
			kit.box(Vector3(x-sign(x),7.2,z),Vector3(2.4,0.18,0.6),"edge")
			kit.box(Vector3(x-sign(x),7.08,z),Vector3(2.1,0.07,0.4),"ice")
			kit.box(Vector3(x,0.55,z+2),Vector3(0.5,1.1,0.5),"steel",true)
			kit.box(Vector3(x,1.11,z+2),Vector3(0.5,0.07,0.5),"cyan")
			# Camera hardware under each lamp arm.
			kit.box(Vector3(x-sign(x)*0.5,5.8,z+0.15),Vector3(0.55,0.3,0.7),"navy")
			kit.box(Vector3(x-sign(x)*0.5,5.8,z+0.51),Vector3(0.17,0.15,0.04),"blue")
			if z%2 == 0:
				var light := OmniLight3D.new()
				light.position = Vector3(x,5.5,z)
				light.light_color = Color("73bfdc")
				light.light_energy = 1.3
				light.omni_range = 13
				light.distance_fade_enabled = true
				light.distance_fade_begin = 60
				light.distance_fade_length = 25
				add_child(light)
	for x in [-19.0,19.0]:
		for z in [-58.0,-25.0,82.0]:
			kit.box(Vector3(x,0.55,z),Vector3(1.1,0.25,3.5),"edge",true)
			kit.box(Vector3(x+sign(x)*0.5,1.05,z),Vector3(0.18,1,3.5),"steel",true)
			for dz in [-1.3,1.3]:
				kit.box(Vector3(x,0.25,z+dz),Vector3(0.8,0.5,0.2),"navy")
	# Street shops occupy the promenade, with canopies and layered door frames.
	for side in [-1,1]:
		for i in 3:
			var x: float = side*36.0
			var z := -20.0+i*9.5
			kit.box(Vector3(x,2.2,z),Vector3(12,4.4,8),"steel",true)
			kit.box(Vector3(x,2.1,z+4.08),Vector3(10.5,3.2,0.15),"glass")
			kit.box(Vector3(x,4.5,z+4),Vector3(12.5,0.3,2.4),"navy")
			kit.box(Vector3(x,4.2,z+4.12),Vector3(11,0.08,0.15),"cyan")
			kit.label(["NIGHT MARKET","RELAY / COFFEE","MEDICAL  08"][i] if side<0 else ["TRANSIT OFFICE","FABRICATION","PUBLIC TERMINAL"][i],Vector3(x,3.5,z+4.2),38,0.017)
	# Freestanding civic information pylons.
	for x in [-12.0,12.0]:
		kit.box(Vector3(x,1.7,73),Vector3(1.6,3.4,0.6),"navy",true)
		kit.box(Vector3(x,2,73.32),Vector3(1.35,2,0.04),"blue")
		kit.label("SECTOR\n07\n——\nNORTH ↑",Vector3(x,2,73.37),32,0.01)
	# Service plant in outer alleys, built from tanks and pipe runs.
	for side in [-1,1]:
		for z in [-80.0,91.0]:
			for i in 3:
				var x: float = side*147.0+i*3.0
				kit.cylinder(Vector3(x,4,z),1.3,8,"steel",-1,null,true)
				kit.box(Vector3(x,0.25,z+3),Vector3(2,0.5,5),"navy",true)
			kit.box(Vector3(side*150,0.6,z+5),Vector3(12,1.2,1.2),"edge",true)

func build_satellite() -> void:
	satellite = Node3D.new()
	satellite.name = "BrotherEyeOrbitalPresence"
	# Lift the orbital proxy clear of the headquarters crown in plaza views.
	satellite.position = Vector3(-110,285,-390)
	add_child(satellite)
	# A distant scenic proxy, not a physically simulated orbit in this milestone.
	var core := SphereMesh.new()
	core.radius = 16
	core.height = 20
	core.radial_segments = 12
	core.rings = 8
	kit.mesh(core,Vector3.ZERO,"navy",Vector3(PI/2,0,0),satellite)
	for radius in [12.0,17.0]:
		var ring := TorusMesh.new()
		ring.inner_radius = radius-0.5
		ring.outer_radius = radius+0.5
		ring.rings = 48
		ring.ring_segments = 8
		kit.mesh(ring,Vector3(0,0,8),"steel" if radius>13 else "blue",Vector3(PI/2,0,0),satellite)
	var eye := SphereMesh.new()
	eye.radius = 6
	eye.height = 12
	var lens: MeshInstance3D = kit.mesh(eye,Vector3(0,0,9),"cyan",Vector3.ZERO,satellite)
	lens.scale.z = 0.3
	satellite_signal=lens
	for side in [-1,1]:
		var wing := BoxMesh.new()
		wing.size = Vector3(31,3,9)
		kit.mesh(wing,Vector3(side*26,-2,0),"navy",Vector3(0,0,side*0.16),satellite)
		var slit := BoxMesh.new()
		slit.size = Vector3(23,0.2,0.2)
		kit.mesh(slit,Vector3(side*27,-1.5,4.6),"blue",Vector3(0,0,side*0.16),satellite)
		var blade := CylinderMesh.new()
		blade.bottom_radius = 3
		blade.top_radius = 0
		blade.height = 23
		blade.radial_segments = 4
		kit.mesh(blade,Vector3(side*17,12,0),"steel",Vector3(0,0,-side*0.3),satellite)

func _process(delta: float) -> void:
	elapsed += delta
	if satellite != null:
		satellite.rotation.z = sin(elapsed*0.035)*0.025
