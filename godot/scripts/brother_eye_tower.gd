extends RefCounted
## Headquarters facade upgrade within the existing structural/collision footprint.
var kit: RefCounted
func _init(geometry: RefCounted) -> void:
	kit = geometry
	panel_material("command_graphite",Color("303d47"),.64,.43)
	panel_material("command_frame",Color("5b6a73"),.72,.36)
	panel_material("command_podium",Color("4c555b"),.18,.68)
	kit.material("command_recess",Color("0a141e"),.35,.48)
	kit.material("command_glass",Color("173746"),.6,.21)
	kit.material("command_window",Color("4e777f"),.25,.4,.3)
	kit.material("command_warm",Color("ac9b79"),.1,.5,.45)
	kit.material("command_signal",Color("00c9ec"),.2,.3,1.6)
	kit.material("command_letter",Color("c3d9db"),.35,.4,.25)

func panel_material(id: String, color: Color, metal: float, roughness: float) -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/command_facade.gdshader")
	material.set_shader_parameter("tint",color)
	material.set_shader_parameter("metal",metal)
	material.set_shader_parameter("roughness",roughness)
	kit.materials[id] = material

func build(city: Node3D) -> MeshInstance3D:
	# Original tower, buttresses and podium retain their collision envelopes.
	kit.box(Vector3(0,4,-96),Vector3(42,8,40),"command_podium",true)
	kit.box(Vector3(0,70,-96),Vector3(24,132,25),"command_graphite",true)
	for side in [-1,1]:
		kit.fin(Vector3(side*13,8,-91),8,148,17,"command_graphite")
		kit.fin(Vector3(side*18,0,-100),5,94,30,"command_frame")
		# Deep vertical observation bays framed by load-bearing ribs.
		kit.box(Vector3(side*6.4,71,-83.22),Vector3(6.6,122,.36),"command_recess")
		for edge in [-1,1]:
			kit.box(Vector3(side*6.4+edge*3.45,71,-82.9),Vector3(.32,123,.85),"command_frame")
		for floor_index in 29:
			var y := 14.0+floor_index*4.0
			kit.box(Vector3(side*6.4,y,-82.96),Vector3(6.1,2.4,.18),"command_glass")
			# Partial occupancy gives windows variation without a blinking facade.
			if floor_index%5 == (1 if side>0 else 3) or floor_index%11 == 0:
				kit.box(Vector3(side*6.4+.9,y-.5,-82.82),Vector3(2.0,.32,.06),"command_warm")
			else:
				kit.box(Vector3(side*6.4-1.6,y-.7,-82.82),Vector3(.7,.12,.06),"command_window")
			kit.box(Vector3(side*6.4,y-1.5,-82.68),Vector3(6.4,.22,1.05),"command_frame")
			for x in [-1.05,1.05]:
				kit.box(Vector3(side*6.4+x,y,-82.8),Vector3(.075,2.45,.24),"command_frame")
		# Narrow outer ribs break up the broad blade faces without neon outlines.
		for x in [10.0,12.7,15.4]:
			kit.box(Vector3(side*x,72,-82.36),Vector3(.18,121,.32),"command_frame")
		# Side service facade; louvers and floor belts provide readable depth.
		kit.box(Vector3(side*20.55,46,-100),Vector3(.18,77,20),"command_recess")
		for y in range(12,85,4):
			kit.box(Vector3(side*20.7,y,-100),Vector3(.45,.22,20),"command_frame")
		for z in range(-108,-90,3):
			kit.box(Vector3(side*20.8,46,z),Vector3(.55,77,.14),"command_frame")
		# Ground level: paneled podium, recessed service grilles and corner piers.
		for x in [8.5,14.0,19.0]:
			kit.box(Vector3(side*x,3.7,-75.84),Vector3(4.5,6.7,.3),"command_graphite")
			kit.box(Vector3(side*x,2.5,-75.61),Vector3(3.6,1.6,.16),"command_recess")
			for slat in 6:
				kit.box(Vector3(side*x,1.9+slat*.24,-75.45),Vector3(3.5,.09,.28),"command_frame")
		for x in [5.4,11.2,17.0,20.6]:
			kit.box(Vector3(side*x,3.9,-75.5),Vector3(.32,7.6,.8),"command_frame")
	# Center seam recessed between slim metallic cheeks; preserve feedback handle.
	kit.box(Vector3(0,76,-83.06),Vector3(1.65,133,.6),"command_recess")
	for x in [-.72,.72]:
		kit.box(Vector3(x,76,-82.7),Vector3(.16,133,.5),"command_frame")
	var axis := BoxMesh.new()
	axis.size = Vector3(.32,133,.16)
	var signal_mesh: MeshInstance3D = kit.mesh(axis,Vector3(0,76,-82.68),"command_signal")
	# Mechanical belts at three structural zones; no silhouette height change.
	for y in [38.0,78.0,118.0]:
		for side in [-1,1]:
			kit.box(Vector3(side*6.4,y,-82.35),Vector3(7.3,.75,1.5),"command_frame")
			kit.box(Vector3(side*6.4,y+.65,-82.62),Vector3(6.3,.45,.35),"command_recess")
	# Roof mechanical crown stays behind the original high blades.
	for x in [-7.0,7.0]:
		kit.box(Vector3(x,137.2,-96),Vector3(6,2.4,14),"command_recess")
		for z in range(-101,-90,2):
			kit.box(Vector3(x,138.5,z),Vector3(5.5,.12,.45),"command_frame")
	# Entrance: double doors, deep jambs, canopy, and grounded lettering.
	kit.box(Vector3(0,2.15,-75.73),Vector3(8.4,4.2,.35),"command_recess")
	for side in [-1,1]:
		kit.box(Vector3(side*1.65,2.0,-75.48),Vector3(3.1,3.8,.12),"command_glass")
		kit.box(Vector3(side*3.6,2.25,-75.3),Vector3(.28,4.4,.7),"command_frame")
		kit.box(Vector3(side*.24,1.85,-75.3),Vector3(.065,.65,.1),"command_letter")
		kit.box(Vector3(side*4.15,2.2,-75.35),Vector3(.12,1.5,.12),"command_signal")
	kit.box(Vector3(0,2,-75.32),Vector3(.12,4,.2),"command_frame")
	kit.box(Vector3(0,4.45,-75.0),Vector3(9.8,.35,2),"command_frame")
	kit.box(Vector3(0,4.25,-74.55),Vector3(7.2,.05,.15),"command_letter")
	kit.box(Vector3(0,6.1,-75.25),Vector3(19,2,.45),"command_recess")
	var title: Label3D = kit.label("N E O N   P R O V I D E N C E",Vector3(0,6.35,-74.99),39,.025)
	title.modulate = Color("b5cacc")
	kit.label("C E N T R A L   A U T H O R I T Y",Vector3(0,5.55,-74.99),24,.021)
	var entry_light := OmniLight3D.new()
	entry_light.name = "HeadquartersEntryLight"
	entry_light.position = Vector3(0,3.9,-74.3)
	entry_light.light_color = Color("c4dbdf")
	entry_light.light_energy = .7
	entry_light.omni_range = 7
	city.add_child(entry_light)
	return signal_mesh
