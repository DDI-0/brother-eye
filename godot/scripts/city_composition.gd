extends RefCounted
## City fabric around the existing landmarks; decorative outer districts stay inexpensive.
var kit: RefCounted
var rng := RandomNumberGenerator.new()
var count := 0

func _init(city_kit: RefCounted) -> void:
	kit = city_kit
	rng.seed = 442019
	_materials()
	_local_blocks()
	_outer_districts()
	_skyline_anchors()
	_elevated_network()
	print("CITY_COMPOSITION buildings=", count)

func _materials() -> void:
	for index in 4:
		var facade := ShaderMaterial.new()
		facade.shader = preload("res://shaders/city_facade.gdshader")
		facade.set_shader_parameter("body_color", [Color("1b3445"), Color("253946"), Color("142b3a"), Color("304658")][index])
		facade.set_shader_parameter("light_color", [Color("71afc8"), Color("659bcb"), Color("4ac4c8"), Color("91b8ca")][index])
		facade.set_shader_parameter("occupancy", 0.58 + index * 0.07)
		facade.set_shader_parameter("seed", float(index) * 21.3)
		kit.materials["fabric_%d" % index] = facade
	kit.material("fabric_frame", Color("304653"), 0.7, 0.38)
	kit.material("fabric_roof", Color("152630"), 0.4, 0.65)
	kit.material("fabric_walk", Color("233541"), 0.45, 0.5)
	kit.material("fabric_signal", Color("35bbd0"), 0.2, 0.35, 1.3)
	kit.material("fabric_amber", Color("b68f61"), 0.2, 0.5, 0.6)

func _box(pos: Vector3, size: Vector3, mat: String, collision := false, yaw := 0.0, far_block := false) -> void:
	var cell_size := 192.0 if far_block else 64.0
	var detail: bool = not far_block and not collision and size[size.max_axis_index()] < 4.0
	var key := "fabric:%s:%d:%d:%s:%s" % [mat, floori(pos.x / cell_size), floori(pos.z / cell_size), "far" if far_block else "near", "detail" if detail else "structure"]
	if not kit.batches.has(key):
		kit.batches[key] = {"mat": mat, "transforms": [], "range_end": 1800.0 if far_block else 750.0,"detail":detail}
	var basis := Basis(Vector3.UP, yaw)
	kit.batches[key].transforms.append(Transform3D(Basis(basis.x * size.x, basis.y * size.y, basis.z * size.z), pos))
	kit.box_count += 1
	if collision:
		var shape := BoxShape3D.new()
		shape.size = size
		kit.collider(shape, Transform3D(basis, pos))

func _building(pos: Vector3, width: float, depth: float, height: float, detail: bool, solid := false) -> void:
	count += 1
	var mat := "fabric_%d" % (count % 4)
	height = _clearance_height(pos, width, depth, height)
	var podium_h := minf(height * 0.3, 9.0)
	_box(pos + Vector3(0, podium_h * 0.5, 0), Vector3(width, podium_h, depth), mat, solid, 0, not detail)
	_box(pos + Vector3(0, height * 0.5 + podium_h * 0.5, 0), Vector3(width * 0.88, height - podium_h, depth * 0.88), mat, solid, 0, not detail)
	_box(pos + Vector3(width * 0.12, height + 1.3, 0), Vector3(width * 0.54, 2.6, depth * 0.65), "fabric_roof", false, 0, not detail)
	if not detail:
		if count % 4 == 0:
			_box(pos + Vector3(-width * 0.4, height * 0.62, depth * 0.44), Vector3(0.12, height * 0.7, 0.12), "fabric_signal", false, 0, true)
		return
	# A continuous inhabited base, slim vertical fins, inset glazing and rooftop services.
	for side in [-1, 1]:
		_box(pos + Vector3(side * width * 0.45, height * 0.55, 0), Vector3(0.35, height * 0.96, depth * 0.91), "fabric_frame")
		_box(pos + Vector3(side * width * 0.455, height * 0.57, depth * 0.455), Vector3(0.06, height * 0.72, 0.06), "fabric_signal")
	_box(pos + Vector3(0, podium_h + 0.2, 0), Vector3(width + 0.6, 0.4, depth + 0.6), "fabric_frame")
	for i in 3:
		var x := (i - 1) * width * 0.26
		_box(pos + Vector3(x, 2.0, depth * 0.5 + 0.04), Vector3(width * 0.2, 2.8, 0.08), "glass")
		_box(pos + Vector3(x, 3.7, depth * 0.5 + 0.4), Vector3(width * 0.24, 0.18, 1.2), "fabric_frame")
		_box(pos + Vector3(x, 3.55, depth * 0.5 + 1.0), Vector3(width * 0.18, 0.06, 0.06), "fabric_amber" if i == 1 else "fabric_signal")
	for i in 2:
		_box(pos + Vector3(-width * 0.16, height + 1.0, (i - 0.5) * depth * 0.3), Vector3(width * 0.2, 1.8, depth * 0.2), "fabric_frame")
	if count % 3 == 0:
		_box(pos + Vector3(width * 0.3, height + 4, -depth * 0.3), Vector3(0.12, 8, 0.12), "fabric_frame")
		_box(pos + Vector3(width * 0.3, height + 8, -depth * 0.3), Vector3(0.18, 0.3, 0.18), "fabric_signal")

func _local_blocks() -> void:
	# These streets and alleys wrap around the original playable route, rather than covering it.
	for side in [-1.0, 1.0]:
		for z in [-137.0, -102.0, -55.0, -5.0, 43.0, 96.0, 140.0]:
			_building(Vector3(side * 150, 0.12, z), 26, 28, rng.randf_range(22, 57), true, true)
		for z in [-124.0, -55.0, 68.0, 134.0]:
			_building(Vector3(side * 77, 0.12, z), 14, 32, rng.randf_range(25, 51), true, true)
		for z in [-135.0, -111.0, 108.0, 141.0]:
			_building(Vector3(side * 35.5, 0.12, z), 16, 19, rng.randf_range(15, 34), true, true)
		# Market/service blocks join the civic terraces to the outer neighborhood.
		for z in [-10.0, 12.0, 34.0]:
			_building(Vector3(side * 77, 0.12, z), 14, 17, rng.randf_range(12, 23), true, true)
		# Cross-streets distinguish blocks from the original uninterrupted base plate.
		for z in [-80.0, -28.0, 92.0]:
			_box(Vector3(side * 99, 0.025, z), Vector3(146, 0.08, 8), "road")
			for x in range(33, 168, 12):
				_box(Vector3(side * x, 0.075, z), Vector3(4, 0.025, 0.12), "edge")
		_box(Vector3(side * 130, 0.025, 0), Vector3(7, 0.08, 344), "road")
		for z in range(-165, 170, 16):
			_box(Vector3(side * 130, 0.075, z), Vector3(0.12, 0.025, 5), "edge")
		# Retaining arcade along the district boundary conceals the development limit.
		for z in range(-160, 170, 26):
			_building(Vector3(side * 191, -0.1, z), 27, 23, rng.randf_range(28, 65), true)
		for z in [-186.0, 186.0]:
			for x in [35.0, 76.0, 115.0, 151.0]:
				_building(Vector3(side * x, -0.1, z), 28, 26, rng.randf_range(30, 68), true)

func _outer_districts() -> void:
	# Four stepped volumes per urban parcel, separated by actual street-width gaps.
	# Nearest outskirts are mid-rise; clustered tall silhouettes recede into the haze.
	for gx in range(-16, 17):
		for gz in range(-16, 17):
			var center := Vector3(gx * 62.0, -0.1, gz * 62.0)
			if maxf(absf(center.x), absf(center.z)) < 218:
				continue
			var cluster := 0.5 + 0.5 * sin(gx * 0.63 + gz * 0.39)
			var near_ring := center.length() < 360
			for parcel in 4:
				var pos := center + Vector3(-15 if parcel % 2 == 0 else 15, 0, -15 if parcel < 2 else 15)
				var width := rng.randf_range(18, 25)
				var depth := rng.randf_range(19, 25)
				var height := rng.randf_range(26, 74) + cluster * rng.randf_range(10, 90)
				if near_ring:
					height *= 0.68
				if parcel == 0 and (gx + gz) % 5 == 0:
					height *= 1.45
				_building(pos, width, depth, height, false)

func _skyline_anchors() -> void:
	# Tall asymmetric crowns punctuate the mid-rise fabric in loose district clusters.
	for i in 28:
		var angle := i * TAU / 28.0 + 0.12
		var radius := 320.0 + float(i % 4) * 78.0
		var pos := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var height := rng.randf_range(145, 245)
		var width := rng.randf_range(13, 22)
		var depth := rng.randf_range(16, 26)
		_building(pos, width, depth, height * 0.82, false)
		# Two unequal blades extend above a recessed inhabited core.
		for side in [-1.0, 1.0]:
			var fin_h := height * (1.0 if side > 0 else 0.9)
			var x: float = side * width * 0.48
			var w := width * 0.19
			var d := depth * 0.9
			var base_y := height * 0.36
			var top_y := fin_h
			var points := [Vector3(x-w/2,base_y,-d/2), Vector3(x+w/2,base_y,-d/2), Vector3(x+w/2,top_y-8,-d/2), Vector3(x-w/2,top_y,-d/2), Vector3(x-w/2,base_y,d/2), Vector3(x+w/2,base_y,d/2), Vector3(x+w/2,top_y-8,d/2), Vector3(x-w/2,top_y,d/2)]
			var indices := [0,2,1,0,3,2,4,5,6,4,6,7,0,4,7,0,7,3,1,2,6,1,6,5,3,7,6,3,6,2,0,1,5,0,5,4]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for index in indices:
				st.add_vertex(points[index])
			st.generate_normals()
			var fin: MeshInstance3D = kit.mesh(st.commit(), pos, "fabric_frame")
			fin.visibility_range_end = 1800
			_box(pos + Vector3(x, (base_y + top_y) * 0.5 - 4, d * 0.5 + 0.04), Vector3(0.15, top_y - base_y - 8, 0.12), "fabric_signal", false, 0, true)
		if i % 4 == 0:
			_box(pos + Vector3(0, height + 14, 0), Vector3(0.09, 44, 0.09), "fabric_signal", false, 0, true)

func _member(a: Vector3, b: Vector3, width: float, depth: float, mat: String, solid := false) -> void:
	var direction := b - a
	var length := direction.length()
	# All network segments are horizontal; local Z follows the route.
	var yaw := atan2(direction.x, direction.z)
	_box((a + b) * 0.5, Vector3(width, depth, length + 0.08), mat, solid, yaw)

func _ring_route(center: Vector3, rx: float, rz: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in 112:
		var angle := i * TAU / 112.0
		points.append(center + Vector3(cos(angle) * rx, 0, sin(angle) * rz))
	return points

func _segment_hits_rect(a: Vector2, b: Vector2, bounds: Rect2) -> bool:
	var enter := 0.0
	var leave := 1.0
	var direction := b - a
	for axis in 2:
		if absf(direction[axis]) < 0.0001:
			if a[axis] < bounds.position[axis] or a[axis] > bounds.end[axis]:
				return false
		else:
			var t0 := (bounds.position[axis] - a[axis]) / direction[axis]
			var t1 := (bounds.end[axis] - a[axis]) / direction[axis]
			enter = maxf(enter, minf(t0, t1))
			leave = minf(leave, maxf(t0, t1))
			if enter > leave:
				return false
	return true

func _clearance_height(pos: Vector3, width: float, depth: float, requested: float) -> float:
	if absf(pos.x) > 143 + width * 0.5 or absf(pos.z + 25) > 115 + depth * 0.5:
		return requested
	var allowed := requested
	for route_spec in [[28.0,137.0,109.0,-25.0,5.5], [49.0,111.0,78.0,-57.0,4.5]]:
		var route := _ring_route(Vector3(0,route_spec[0],route_spec[3]), route_spec[1], route_spec[2])
		var bounds := Rect2(Vector2(pos.x - width * 0.5, pos.z - depth * 0.5), Vector2(width, depth)).grow(route_spec[4] * 0.5 + 1.0)
		for i in route.size():
			var a := Vector2(route[i].x, route[i].z)
			var b := Vector2(route[(i + 1) % route.size()].x, route[(i + 1) % route.size()].z)
			if _segment_hits_rect(a, b, bounds):
				# Include rooftop machinery, antenna tips and the full rail/deck envelope.
				allowed = minf(allowed, route_spec[0] - pos.y - 10.0)
				break
	return allowed

func _viaduct(center: Vector3, rx: float, rz: float, width: float) -> void:
	var route := _ring_route(center, rx, rz)
	var routes: Array = kit.root.get_meta("transit_routes", [])
	routes.append({"points": route, "width": width, "height": center.y})
	kit.root.set_meta("transit_routes", routes)
	for i in route.size():
		var start := route[i]
		var finish := route[(i + 1) % route.size()]
		_member(start, finish, width, 0.8, "fabric_frame")
		_member(start + Vector3(0, 0.45, 0), finish + Vector3(0, 0.45, 0), width - 0.5, 0.08, "fabric_roof")
		var direction := (finish - start).normalized()
		for side in [-1.0, 1.0]:
			var offset: Vector3 = Vector3(direction.z, 0, -direction.x) * side * (width * 0.5 - 0.1)
			_member(start + offset + Vector3(0, 0.8, 0), finish + offset + Vector3(0, 0.8, 0), 0.12, 0.12, "fabric_signal")
		if i % 14 == 0 and absf(start.x) > 110:
			_box(Vector3(start.x, center.y * 0.5, start.z), Vector3(1.4, center.y, 2.2), "fabric_frame", true)

func _skybridge(a: Vector3, b: Vector3, width: float) -> void:
	_member(a, b, width, 0.7, "fabric_frame", true)
	_member(a + Vector3(0, 0.4, 0), b + Vector3(0, 0.4, 0), width - 0.5, 0.12, "fabric_walk")
	var length := a.distance_to(b)
	var steps := int(length / 5.0)
	for side in [-1, 1]:
		for y in [0.9, 3.2]:
			_member(a + Vector3(0, y, side * width * 0.5), b + Vector3(0, y, side * width * 0.5), 0.15, 0.15, "fabric_frame")
		_member(a + Vector3(0, 0.6, side * width * 0.5), b + Vector3(0, 0.6, side * width * 0.5), 0.06, 0.06, "fabric_signal")
		for i in steps:
			var start := a.lerp(b, float(i) / steps) + Vector3(0, 0.9, side * width * 0.5)
			var end := a.lerp(b, float(i + 1) / steps) + Vector3(0, 3.2, side * width * 0.5)
			# Sloped truss members use a full orthonormal basis, scaled in local axes.
			var direction := end - start
			var basis := Basis.looking_at(direction.normalized(), Vector3.UP)
			var key := "fabric:trusses"
			if not kit.batches.has(key):
				kit.batches[key] = {"mat": "fabric_frame", "transforms": []}
			kit.batches[key].transforms.append(Transform3D(Basis(basis.x * 0.1, basis.y * 0.1, basis.z * direction.length()), (start + end) * 0.5))
			kit.box_count += 1

func _elevated_network() -> void:
	_viaduct(Vector3(0, 28, -25), 137, 109, 5.5)
	_viaduct(Vector3(0, 49, -57), 111, 78, 4.5)
	_skybridge(Vector3(-48, 37.8, -48), Vector3(48, 37.8, -48), 5)
	_skybridge(Vector3(-105, 54, -110), Vector3(105, 54, -110), 4.5)
	# Station platforms tie the curving network into occupied city blocks.
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 136, 27.8, -25), Vector3(13, 1.2, 25), "fabric_frame")
		_box(Vector3(side * 143, 30.6, -25), Vector3(3, 4.4, 20), "fabric_0")
		_box(Vector3(side * 137, 33.1, -25), Vector3(15, 0.3, 27), "fabric_frame")
