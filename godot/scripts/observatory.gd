extends RefCounted
## Exterior observatory and instrument deck; preserves the raised pedestrian route.
const X := 46.0
var kit: RefCounted
var tracking: Node3D
var telescope: Node3D
func _init(geometry: RefCounted) -> void:
	kit = geometry
	for spec in [["obs_shell",Color("697a83"),.65,.42],["obs_cladding",Color("3e505b"),.45,.54],["obs_deck",Color("53646a"),.12,.72]]:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/command_facade.gdshader")
		m.set_shader_parameter("tint",spec[1])
		m.set_shader_parameter("metal",spec[2])
		m.set_shader_parameter("roughness",spec[3])
		kit.materials[spec[0]] = m
	kit.material("obs_frame",Color("81959b"),.7,.35)
	kit.material("obs_dark",Color("111e29"),.25,.6)
	kit.material("obs_glass",Color("183a4d"),.6,.2)
	kit.material("obs_signal",Color("4cabbf"),.1,.4,.55)
	kit.material("obs_lamp",Color("a6c6d0"),.1,.5,.5)
	kit.material("obs_warning",Color("ae8749"),.1,.65)
	# The slotted dome has a visible inner skin as well as an outer surface.
	var shell: ShaderMaterial = kit.materials.obs_shell.duplicate()
	var double_shader := Shader.new()
	double_shader.code = shell.shader.code.replace("shader_type spatial;","shader_type spatial;\nrender_mode cull_disabled;")
	# Dome panels must turn with the shell instead of sliding in world space.
	double_shader.code = double_shader.code.replace("(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz","VERTEX").replace("normalize(MODEL_NORMAL_MATRIX*NORMAL)","normalize(NORMAL)")
	shell.shader = double_shader
	kit.materials["obs_dome"] = shell

func box(p: Vector3, size: Vector3, mat: String, collision := false) -> void:
	kit.box(p+Vector3(X,0,0),size,mat,collision)

func rod(a: Vector3, b: Vector3, radius: float, mat: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 12
	return kit.mesh(mesh,(a+b)*.5,mat,Quaternion(Vector3.UP,(b-a).normalized()).get_euler())

func dome_point(a: float, elevation: float) -> Vector3:
	return Vector3(sin(a)*6*cos(elevation),4.2*sin(elevation),cos(a)*6*cos(elevation))

func dome() -> void:
	var origin := Vector3(X,13.2,-2)
	kit.cylinder(Vector3(X,12.6,-2),6.35,1.2,"obs_dark",-1,null,true,64)
	kit.torus_ring(Vector3(X,13.15,-2),6.16,6.36,"obs_frame",96,8)
	kit.torus_ring(Vector3(X,12.18,-2),6.16,6.36,"obs_frame",96,8)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two 30-degree open shutter sectors form a continuous meridian slit.
	for section in [Vector2(PI/12,PI-PI/12),Vector2(PI+PI/12,TAU-PI/12)]:
		for j in 40:
			var a0 := lerpf(section.x,section.y,float(j)/40)
			var a1 := lerpf(section.x,section.y,float(j+1)/40)
			for k in 16:
				var e0 := k*PI/32
				var e1 := (k+1)*PI/32
				var points := [dome_point(a0,e0),dome_point(a1,e0),dome_point(a1,e1),dome_point(a0,e1)]
				for index in [0,1,2,0,2,3]: st.add_vertex(points[index])
	st.generate_normals()
	var shell: MeshInstance3D = kit.mesh(st.commit(),origin,"obs_dome")
	shell.name = "ObservatorySlottedDome"
	shell.reparent(tracking,true)
	# Continuous tubular shutter edges follow the ellipsoid, lifted above its skin.
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [PI/12,PI-PI/12,PI+PI/12,TAU-PI/12]:
		for k in 32:
			var p0 := dome_point(a,k*PI/64)*1.012
			var p1 := dome_point(a,(k+1)*PI/64)*1.012
			var direction := (p1-p0).normalized()
			var side := direction.cross(Vector3.RIGHT).normalized()*.065
			var up := direction.cross(side).normalized()*.065
			for n in 6:
				var q0 := side*cos(n*TAU/6)+up*sin(n*TAU/6)
				var q1 := side*cos((n+1)*TAU/6)+up*sin((n+1)*TAU/6)
				for p in [p0+q0,p1+q0,p1+q1,p0+q0,p1+q1,p0+q1]: frame.add_vertex(p)
	frame.generate_normals()
	var tracks: MeshInstance3D = kit.mesh(frame.commit(),origin,"obs_frame")
	tracks.name = "DomeShutterTracks"
	tracks.reparent(tracking,true)
	# The observation chamber is an exterior instrument enclosure, not a walkable interior.
	var shape := SphereMesh.new()
	shape.radius = 6
	shape.height = 12
	shape.radial_segments = 32
	shape.rings = 16
	kit.collider(shape.create_convex_shape(),Transform3D(Basis.from_scale(Vector3(1,.7,1)),origin))
	kit.cylinder(Vector3(X,13.6,-2),.9,.8,"obs_frame")
	for side in [-1,1]:
		var fork_mesh := BoxMesh.new()
		fork_mesh.size = Vector3(.22,1.8,.5)
		var fork: MeshInstance3D = kit.mesh(fork_mesh,Vector3(X+side*.85,14.5,-2),"obs_dark")
		fork.reparent(tracking,true)
	var pivot := Vector3(X,14.8,-2)
	telescope = Node3D.new()
	telescope.name = "TelescopeElevation"
	tracking.add_child(telescope)
	telescope.global_position = pivot
	tracking.telescope = telescope
	var aim := Vector3(0,.67,.74).normalized()
	var barrel := rod(pivot-aim*1.0,pivot+aim*2.9,.46,"obs_dark")
	barrel.name = "ObservatoryTelescope"
	barrel.reparent(telescope,true)
	for t in [-.8,.1,2.45,2.85]:
		rod(pivot+aim*t,pivot+aim*(t+.14),.52,"obs_frame").reparent(telescope,true)
	rod(pivot+aim*2.98,pivot+aim*3.02,.39,"obs_glass").reparent(telescope,true)
	tracking.set_hour(8.0)

func build(city: Node3D) -> void:
	tracking = preload("res://scripts/observatory_tracking.gd").new()
	tracking.name = "ObservatoryTrackingRig"
	tracking.position = Vector3(X,13.2,-2)
	tracking.set_meta("animated_landmark",true)
	city.add_child(tracking)
	box(Vector3(0,5.8,7),Vector3(34,11.6,34),"obs_cladding",true)
	box(Vector3(0,11.8,7),Vector3(36,.4,36),"obs_deck",true)
	# Recessed horizontal instrument-floor windows, framed by projecting ribs.
	box(Vector3(0,5.8,24.12),Vector3(32,9.8,.2),"obs_dark")
	for x in [-12.0,-6.0,6.0,12.0]:
		for y in [3.8,7.0]:
			box(Vector3(x,y,24.27),Vector3(5.2,2.5,.15),"obs_glass")
			box(Vector3(x,y-1.4,24.5),Vector3(5.5,.18,.65),"obs_frame")
			for dx in [-1.7,0.0,1.7]:
				box(Vector3(x+dx,y,24.42),Vector3(.09,2.5,.3),"obs_frame")
	for x in [-16.5,-9.0,-3.1,3.1,9.0,16.5]:
		box(Vector3(x,5.8,24.55),Vector3(.5,10.5,.9),"obs_shell")
	box(Vector3(0,10.1,25.04),Vector3(33,1.7,.4),"obs_dark")
	kit.label("OBSERVATORY",Vector3(X,10.2,25.27),40,.025)
	kit.label("NEON PROVIDENCE  /  RESEARCH & TELEMETRY",Vector3(X,9.48,25.27),20,.018)
	# A metal entry portal, task lights and restrained status markers.
	for side in [-1,1]:
		box(Vector3(side*1.3,2.2,24.5),Vector3(2.45,4.3,.15),"obs_glass")
		box(Vector3(side*.22,2.0,24.65),Vector3(.07,.75,.12),"obs_frame")
		box(Vector3(side*2.8,2.3,24.6),Vector3(.2,4.6,.65),"obs_frame")
		box(Vector3(side*3.6,2.5,24.6),Vector3(.12,.9,.12),"obs_signal")
	box(Vector3(0,2.2,24.65),Vector3(.12,4.4,.2),"obs_frame")
	box(Vector3(0,4.7,25.0),Vector3(7,.35,2.1),"obs_shell",true)
	box(Vector3(0,4.48,25.2),Vector3(5.8,.06,.8),"obs_lamp")
	box(Vector3(0,6.5,24.55),Vector3(5.4,2.7,.25),"obs_shell")
	kit.label("RESEARCH\nACCESS",Vector3(X,6.6,24.76),25,.022)
	# Louvers, pipework and technical panels on both side walls.
	for side in [-1,1]:
		for z in [-6.0,2.0,10.0]:
			box(Vector3(side*17.1,5.9,z),Vector3(.15,7.6,6.4),"obs_dark")
			for y in range(3,10):
				box(Vector3(side*17.32,y,z),Vector3(.45,.13,5.9),"obs_frame")
		for z in [-8.5,13.0]:
			box(Vector3(side*17.5,5.7,z),Vector3(.2,9.9,.2),"obs_frame")
	# Original terrace rails and inner skywalk opening are retained.
	for edge_x in [-18.0,18.0]:
		var inner: bool = edge_x<0
		box(Vector3(edge_x,12.55,2.5 if inner else 6.5),Vector3(.15,1.1,27 if inner else 35),"obs_frame",true)
		box(Vector3(edge_x,13.12,2.5 if inner else 6.5),Vector3(.23,.08,27 if inner else 35),"obs_frame")
	box(Vector3(0,12.55,-11),Vector3(36,1.1,.15),"obs_frame",true)
	dome()
	# Service plant stays on the outer/eastern deck, away from the pedestrian approach.
	for z in [2.0,6.0]:
		box(Vector3(12.5,13.0,z),Vector3(3.6,1.9,2.5),"obs_shell",true)
		for slat in 8:
			box(Vector3(12.5,12.4+slat*.16,z+1.3),Vector3(3.0,.055,.12),"obs_dark")
		box(Vector3(12.5,14.0,z),Vector3(3.3,.12,2.2),"obs_frame")
	for x in [11.5,13.5]:
		box(Vector3(x,12.17,4),Vector3(.14,.16,10),"obs_frame")
	# Compact radio dish and weather mast provide recognizable instrument silhouettes.
	kit.cylinder(Vector3(X+12.5,13.1,-6),.45,2.1,"obs_frame",-1,null,true)
	var dish := SphereMesh.new()
	dish.radius = 1.5
	dish.height = 1.0
	dish.radial_segments = 32
	dish.rings = 12
	var dish_node: MeshInstance3D = kit.mesh(dish,Vector3(X+12.5,14.4,-6),"obs_shell",Vector3(.42,0,.22))
	dish_node.name = "ObservatoryTelemetryDish"
	rod(Vector3(X+12.5,14.6,-6),Vector3(X+12.5,15.8,-5.4),.045,"obs_frame")
	box(Vector3(-12,14.6,-7),Vector3(.16,5.2,.16),"obs_frame",true)
	box(Vector3(-12,16.7,-7),Vector3(2.1,.09,.09),"obs_frame")
	kit.cylinder(Vector3(X-12,17.4,-7),.26,.35,"obs_signal",-1,null,false,12)
	# Calibration pad and cabinets are visible without filling the circulation area.
	box(Vector3(8,12.06,11),Vector3(4,.035,3),"obs_dark")
	for side in [-1,1]:
		box(Vector3(8+side*1.8,12.09,11),Vector3(.08,.03,2.8),"obs_warning")
	box(Vector3(-11,13.0,-6.5),Vector3(3.1,1.9,2.4),"obs_cladding",true)
	kit.label("TELEMETRY  /  07",Vector3(X-11,13.1,-5.26),20,.016)
	var light := OmniLight3D.new()
	light.name = "ObservatoryEntryLight"
	light.position = Vector3(X,4,25.2)
	light.light_color = Color("bfd8df")
	light.light_energy = .6
	light.omni_range = 7
	city.add_child(light)
