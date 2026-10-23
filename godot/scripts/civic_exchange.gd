extends RefCounted
## Civic landmark: exterior facade and usable terrace, within the existing footprint.
var kit: RefCounted
const CENTER := -46.0
func _init(geometry: RefCounted) -> void:
	kit = geometry
	for spec in [["civic_stone",Color("92968e"),.06,.72],["civic_frame",Color("52676d"),.65,.38],["civic_deck",Color("626c69"),.05,.78]]:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/command_facade.gdshader")
		m.set_shader_parameter("tint",spec[1])
		m.set_shader_parameter("metal",spec[2])
		m.set_shader_parameter("roughness",spec[3])
		kit.materials[spec[0]] = m
	kit.material("civic_shadow",Color("15282d"),.15,.65)
	kit.material("civic_glass",Color("294d58"),.5,.22)
	kit.material("civic_wood",Color("625547"),.0,.77)
	kit.material("civic_green",Color("344e3b"),.0,.9)
	kit.material("civic_lamp",Color("c8b48c"),.1,.5,.7)
	kit.material("civic_signal",Color("429ca4"),.15,.4,.7)

func box(p: Vector3, size: Vector3, mat: String, collision := false) -> void:
	kit.box(p+Vector3(CENTER,0,0),size,mat,collision)

func build(city: Node3D) -> void:
	# Existing solid podium and roof retain their original support and height.
	box(Vector3(0,5.8,7),Vector3(34,11.6,34),"civic_stone",true)
	box(Vector3(0,11.8,7),Vector3(36,.4,36),"civic_deck",true)
	# Dark bays sit behind protruding stone piers and inset glass frames.
	box(Vector3(0,5.6,24.06),Vector3(32,9.3,.15),"civic_shadow")
	for x in [-12.0,-6.0,6.0,12.0]:
		box(Vector3(x,5.6,24.2),Vector3(5.4,8.6,.16),"civic_glass")
		for y in [2.7,5.6,8.5]:
			box(Vector3(x,y,24.36),Vector3(5.5,.14,.36),"civic_frame")
		for dx in [-1.8,0.0,1.8]:
			box(Vector3(x+dx,5.6,24.4),Vector3(.075,8.6,.34),"civic_frame")
	for x in [-16.4,-9.0,-3.1,3.1,9.0,16.4]:
		box(Vector3(x,5.6,24.45),Vector3(.7,10.4,1),"civic_stone")
	box(Vector3(0,10.6,24.35),Vector3(34,.7,.85),"civic_stone")
	box(Vector3(0,.5,24.3),Vector3(34,.7,.6),"civic_frame")
	# Closed entrance doors: no pretend walk-through into the solid podium.
	for side in [-1,1]:
		box(Vector3(side*1.35,2.1,24.45),Vector3(2.5,4.1,.16),"civic_glass")
		box(Vector3(side*.22,1.95,24.6),Vector3(.07,.8,.12),"civic_frame")
		box(Vector3(side*2.8,2.2,24.5),Vector3(.16,4.4,.5),"civic_frame")
		box(Vector3(side*3.55,2.2,24.7),Vector3(.12,1.2,.12),"civic_signal")
	box(Vector3(0,2.1,24.6),Vector3(.12,4.2,.2),"civic_frame")
	box(Vector3(0,4.6,25),Vector3(8,.35,2.4),"civic_frame",true)
	box(Vector3(0,4.39,25.25),Vector3(6.3,.06,1.3),"civic_lamp")
	box(Vector3(0,6.35,24.6),Vector3(5.6,2.5,.35),"civic_stone")
	kit.label("CIVIC\nEXCHANGE",Vector3(CENTER,6.5,24.81),36,.022)
	box(Vector3(0,9.8,24.9),Vector3(15,.8,.35),"civic_stone")
	kit.label("PUBLIC SERVICES  /  SECTOR 07",Vector3(CENTER,9.8,25.1),24,.023)
	# Side facades use a quiet rhythm of stone panels and recessed louvers.
	for side in [-1,1]:
		for z in [-6.0,0.0,6.0,12.0]:
			box(Vector3(side*17.08,5.7,z),Vector3(.16,8.5,5.4),"civic_shadow")
			for y in range(2,10):
				box(Vector3(side*17.25,y,z),Vector3(.4,.14,5.0),"civic_frame")
	# Keep the existing skywalk entrance open along the inner edge at z=16..24.
	for edge_x in [-18.0,18.0]:
		var inner: bool = edge_x>0
		box(Vector3(edge_x,12.55,2.5 if inner else 6.5),Vector3(.15,1.1,27 if inner else 35),"civic_frame",true)
		box(Vector3(edge_x,13.12,2.5 if inner else 6.5),Vector3(.22,.09,27 if inner else 35),"civic_frame")
	box(Vector3(0,12.55,-11),Vector3(36,1.1,.15),"civic_frame",true)
	# Glazed rooftop skylight: same collision envelope as the former dome.
	var dome := SphereMesh.new()
	dome.radius = 6
	dome.height = 12
	dome.radial_segments = 48
	dome.rings = 20
	var d: MeshInstance3D = kit.mesh(dome,Vector3(CENTER,12,-2),"civic_glass")
	d.scale.y = .7
	kit.collider(dome.create_convex_shape(),Transform3D(Basis.from_scale(Vector3(1,.7,1)),Vector3(CENTER,12,-2)))
	for height in [.8,2.0,3.2,4.0]:
		var radius := 6.04*sqrt(1.0-pow(height/4.2,2.0))
		kit.torus_ring(Vector3(CENTER,12+height,-2),radius-.035,radius+.035,"civic_frame",64,6)
	kit.torus_ring(Vector3(CENTER,12.15,-2),5.92,6.08,"civic_frame",64,6)
	# Low stone planters, rounded shrubs and timber seating leave central paths clear.
	for x in [-12.5,12.5]:
		for z in [-7.0,9.5]:
			box(Vector3(x,12.4,z),Vector3(4.5,.7,1.8),"civic_stone",true)
			box(Vector3(x,12.78,z),Vector3(4.1,.12,1.4),"civic_shadow")
			for dx in [-1.25,0.0,1.25]:
				var shrub := SphereMesh.new()
				shrub.radius = .75
				shrub.height = 1.15
				shrub.radial_segments = 12
				shrub.rings = 6
				kit.mesh(shrub,Vector3(CENTER+x+dx,13.1,z),"civic_green")
		for z in [5.8,13.4]:
			box(Vector3(x,12.48,z),Vector3(3.6,.16,.9),"civic_wood",true)
			for dx in [-1.3,1.3]:
				box(Vector3(x+dx,12.25,z),Vector3(.15,.4,.65),"civic_frame")
	# Shaded seating on the western terrace; the eastern skywalk remains unobstructed.
	for x in [-16.0,-9.0]:
		for z in [1.8,7.5]:
			box(Vector3(x,14.1,z),Vector3(.18,4.1,.18),"civic_frame",true)
	for z in range(2,9):
		box(Vector3(-12.5,16.2,z),Vector3(7.6,.12,.28),"civic_wood")
	# Deck inlays lead from the skywalk to the terrace without new obstacles.
	for x in range(-14,16,3):
		box(Vector3(x,12.045,18),Vector3(.045,.015,9),"civic_frame")
	var light := OmniLight3D.new()
	light.name = "CivicExchangeEntryLight"
	light.position = Vector3(CENTER,4,25.3)
	light.light_color = Color("e2cfaa")
	light.light_energy = .65
	light.omni_range = 7
	city.add_child(light)
