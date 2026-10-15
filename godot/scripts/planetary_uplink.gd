extends Node3D
## Batched vector geometry: no opaque sphere, per-point nodes, or frame-time rebuilds.
const RADIUS := 1.85
const HOLO = preload("res://shaders/hologram.gdshader")
# Simplified geographic coastlines in longitude/latitude degrees.
const LAND := [
	[-168,71,-145,70,-130,58,-124,49,-125,40,-117,32,-108,24,-98,16,-88,20,-82,25,-80,32,-74,40,-60,47,-55,53,-65,60,-80,63,-95,74,-120,75,-140,70],
	[-81,12,-71,11,-61,7,-51,3,-35,-6,-39,-18,-48,-28,-54,-36,-66,-55,-74,-48,-73,-31,-80,-8],
	[-52,60,-43,61,-24,75,-31,83,-49,82,-62,76],
	[-17,36,0,37,12,33,25,32,34,30,43,12,51,11,43,-12,35,-25,18,-35,11,-18,9,3,-4,5,-17,15],
	[-10,36,-9,44,-1,49,7,54,5,59,19,71,32,70,29,60,42,56,58,70,90,77,120,73,146,61,178,65,170,52,145,45,140,35,129,34,121,23,110,20,106,9,99,5,94,20,88,22,80,7,73,18,67,25,56,25,49,13,43,12,35,29,28,41,20,39,12,46,3,43],
	[113,-22,122,-18,131,-12,137,-15,145,-14,153,-25,151,-36,140,-39,130,-32,116,-35],
	[47,-13,50,-16,49,-25,44,-25,43,-18],
	[130,32,136,34,142,41,145,44,142,35,136,31],
	[95,5,106,-6,115,-8,119,-5,110,1,104,2],
	[120,-3,132,-3,141,-6,150,-10,140,-10,130,-7],
	[166,-34,178,-38,173,-46,166,-45],
	[-180,-73,-145,-75,-120,-73,-85,-73,-65,-64,-55,-67,-65,-77,-20,-80,20,-70,60,-67,100,-67,140,-69,180,-73]
]
var planet: Node3D
var gyros: Array[Node3D] = []
var pulses: Array[MeshInstance3D] = []
var material: ShaderMaterial
var scanner_material: ShaderMaterial
var elapsed := 0.0
var point_count := 0

func sphere(lon: float, lat: float, radius := RADIUS) -> Vector3:
	var a := deg_to_rad(lon)
	var b := deg_to_rad(lat)
	return Vector3(cos(b)*sin(a), sin(b), cos(b)*cos(a))*radius

func vertex(st: SurfaceTool, p: Vector3, color: Color) -> void:
	st.set_color(color)
	st.set_normal(p.normalized())
	st.add_vertex(p)

func tube(st: SurfaceTool, path: PackedVector3Array, width: float, color: Color) -> void:
	for i in range(path.size()-1):
		var a := path[i]
		var b := path[i+1]
		var tangent := (b-a).normalized()
		var side := tangent.cross((a+b).normalized()).normalized()*width
		var up := tangent.cross(side).normalized()*width
		for j in 4:
			var p := side*cos(j*PI/2)+up*sin(j*PI/2)
			var q := side*cos((j+1)*PI/2)+up*sin((j+1)*PI/2)
			for v in [a+p,b+p,b+q,a+p,b+q,a+q]: vertex(st,v,color)

func dot_mesh(st: SurfaceTool, p: Vector3, size: float, color: Color) -> void:
	var n := p.normalized()
	var x := n.cross(Vector3.UP).normalized()*size
	var y := n.cross(x).normalized()*size
	var top := n*size*.65
	for i in 4:
		var a := x*cos(i*PI/2)+y*sin(i*PI/2)
		var b := x*cos((i+1)*PI/2)+y*sin((i+1)*PI/2)
		for v in [p+top,p+a,p+b,p-top,p+b,p+a]: vertex(st,v,color)

func mesh_node(st: SurfaceTool, parent: Node3D, title: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = title
	node.mesh = st.commit()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = HOLO
	planet = Node3D.new()
	planet.name = "RotatingEarth"
	add_child(planet)
	var grid := surface()
	for lat in range(-75,76,15):
		var path := PackedVector3Array()
		for lon in range(0,361,3): path.append(sphere(lon,lat))
		tube(grid,path,.008 if lat == 0 else .0035,Color(.7 if lat == 0 else .17,0,.2,1))
	for lon in range(0,360,20):
		var path := PackedVector3Array()
		for lat in range(-90,91,3): path.append(sphere(lon,lat))
		tube(grid,path,.0035,Color(.17,0,.2,1))
		for lat in range(-75,76,15): dot_mesh(grid,sphere(lon,lat),.013,Color(.5,float(lon+lat)/360.0,1,1))
	mesh_node(grid,planet,"CoordinateGrid")
	var polygons: Array[PackedVector2Array] = []
	for outline in LAND:
		var polygon := PackedVector2Array()
		for i in range(0,outline.size(),2): polygon.append(Vector2(outline[i],outline[i+1]))
		polygons.append(polygon)
	var data := surface()
	var random := RandomNumberGenerator.new()
	random.seed = 14710
	for lat in range(-80,81,2):
		var step := 2.0/maxf(.24,cos(deg_to_rad(lat)))
		var lon := -179.0
		while lon < 180:
			var coordinate := Vector2(lon+random.randf_range(-.4,.4),lat+random.randf_range(-.4,.4))
			for polygon in polygons:
				if Geometry2D.is_point_in_polygon(coordinate,polygon):
					dot_mesh(data,sphere(coordinate.x,coordinate.y,RADIUS*1.006),random.randf_range(.008,.015),Color(random.randf_range(.38,.65),random.randf(),1,1))
					point_count += 1
					break
			lon += step
	# Recognizable communication hubs with short radial telemetry needles.
	var hubs := [Vector2(-74,41),Vector2(-118,34),Vector2(-.1,51),Vector2(2,49),Vector2(139,36),Vector2(104,1),Vector2(151,-34),Vector2(-46,-24),Vector2(31,30),Vector2(77,29)]
	for hub in hubs:
		var p := sphere(hub.x,hub.y,RADIUS*1.015)
		dot_mesh(data,p,.031,Color(.95,random.randf(),1,1))
		tube(data,PackedVector3Array([p,p*1.12]),.005,Color(.5,0,1,1))
	for index in range(hubs.size()-1):
		var a := sphere(hubs[index].x,hubs[index].y).normalized()
		var b := sphere(hubs[index+1].x,hubs[index+1].y).normalized()
		var path := PackedVector3Array()
		for i in 49:
			var t := float(i)/48
			path.append(a.slerp(b,t)*RADIUS*(1.025+.13*sin(t*PI)))
		tube(data,path,.004,Color(.25,0,1,1))
	mesh_node(data,planet,"ContinentsAndNetwork")
	var scanner := MeshInstance3D.new()
	scanner.name = "RadarSector"
	var shell := SphereMesh.new()
	shell.radius = RADIUS*1.008
	shell.height = RADIUS*2.016
	shell.radial_segments = 128
	shell.rings = 64
	scanner.mesh = shell
	scanner_material = ShaderMaterial.new()
	scanner_material.shader = preload("res://shaders/uplink_scanner.gdshader")
	scanner.material_override = scanner_material
	scanner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(scanner)
	for index in 3:
		var pivot := Node3D.new()
		pivot.name = "OrbitalGyro%d" % index
		add_child(pivot)
		gyros.append(pivot)
		var st := surface()
		var r := RADIUS+.25+index*.17
		var path := PackedVector3Array()
		for i in 181: path.append(Vector3(cos(i*TAU/180)*r,0,sin(i*TAU/180)*r))
		tube(st,path,.006,Color(.34,0,0,1))
		for i in 48:
			var a := i*TAU/48
			var p := Vector3(cos(a)*r,0,sin(a)*r)
			tube(st,PackedVector3Array([p,p*(1.035 if i%4 else 1.065)]),.009,Color(.75,0,0,1))
		mesh_node(st,pivot,"CircuitRing")
	for index in 3:
		var st := surface()
		var path := PackedVector3Array()
		for i in 129: path.append(Vector3(cos(i*TAU/128),0,sin(i*TAU/128)))
		tube(st,path,.009,Color(.6,0,0,1))
		pulses.append(mesh_node(st,self,"UplinkPulse%d" % index))
	# Cone remains subtle; it connects the floating data to the emitter.
	var cone := MeshInstance3D.new()
	cone.name = "ProjectorLight"
	var shape := CylinderMesh.new()
	shape.bottom_radius = .55
	shape.top_radius = 1.15
	shape.height = 1.8
	cone.mesh = shape
	cone.position.y = -1.5
	var light_material := ShaderMaterial.new()
	light_material.shader = preload("res://shaders/uplink_projector.gdshader")
	cone.material_override = light_material
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)
	update_animation(0)

func _process(delta: float) -> void:
	elapsed += delta
	update_animation(elapsed)

func update_animation(time: float) -> void:
	material.set_shader_parameter("clock",time)
	scanner_material.set_shader_parameter("clock",time)
	planet.rotation = Vector3(deg_to_rad(12),-.55+time*.12,deg_to_rad(-8))
	for i in gyros.size():
		gyros[i].rotation = Vector3(deg_to_rad([25,-35,65][i]),time*[.19,-.15,.09][i]+i,deg_to_rad([12,20,-25][i]))
	for i in pulses.size():
		var t := fposmod(time*.38+float(i)/3,1.0)
		var y := lerpf(-RADIUS,RADIUS,t)
		var r := sqrt(maxf(.001,RADIUS*RADIUS-y*y))+.025
		pulses[i].position.y = y
		pulses[i].scale = Vector3(r,1,r)
		pulses[i].transparency = 1.0-sin(t*PI)*.65
