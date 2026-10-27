extends RefCounted
## Continuous structural ribbons, glazed occupied floors and supported ring decks.
## All dimensions are metres relative to the tower's requested height.
var kit: RefCounted
var origin: Vector3
var h: float
var distant: bool
var root: Node3D

func _init(city_kit: RefCounted, pos: Vector3, height: float, far_tower: bool) -> void:
	kit = city_kit
	origin = pos
	h = height
	distant = far_tower
	root = Node3D.new()
	root.name = "HelixSpire"
	root.position = pos
	root.set_meta("height_m", height)
	kit.root.add_child(root)
	_prepare_materials()
	_build()

func _prepare_materials() -> void:
	if kit.materials.has("helix_titanium"):
		return
	kit.material("helix_titanium", Color("9cabb6"), 0.68, 0.32)
	kit.material("helix_trim", Color("344959"), 0.82, 0.36)
	kit.material("helix_deck", Color("172832"), 0.55, 0.46)
	kit.material("helix_light", Color("62d8e9"), 0.35, 0.28, 1.15)
	kit.material("helix_room", Color("b6cbd2"), 0.15, 0.6, 0.35)
	kit.material("helix_warm", Color("c2ab87"), 0.1, 0.65, 0.3)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.14, 0.24, 0.29, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	glass.metallic = 0.15
	glass.roughness = 0.18
	glass.cull_mode = BaseMaterial3D.CULL_BACK
	kit.materials["helix_glazing"] = glass

func _radius(t: float) -> float:
	return h * (0.145 * pow(1.0 - t, 0.72) + 0.012)

func _point(t: float, phase: float, offset: float, radial_offset: float) -> Vector3:
	var angle: float = phase + t * TAU * 0.72 + offset
	var radius := _radius(t) + radial_offset
	return Vector3(cos(angle) * radius, t * h * 0.98, sin(angle) * radius)

func _ribbon(phase: float, center: float, half_width: float, thickness: float, mat: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 160 if not distant else 64
	# Separate smoothing groups preserve crisp edges along the broad curved faces.
	for face in 4:
		st.set_smooth_group(face)
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var corners: Array[Vector3] = []
			for t in [t0, t1]:
				corners.append(_point(t, phase, center - half_width, thickness * 0.5))
				corners.append(_point(t, phase, center + half_width, thickness * 0.5))
				corners.append(_point(t, phase, center + half_width, -thickness * 0.5))
				corners.append(_point(t, phase, center - half_width, -thickness * 0.5))
			var next := (face + 1) % 4
			for index in [face, next, face + 4, next, next + 4, face + 4]:
				st.set_uv(Vector2(float(index % 4) / 3.0, t0 if index < 4 else t1))
				st.add_vertex(corners[index])
	st.generate_normals()
	st.index()
	var node: MeshInstance3D = kit.mesh(st.commit(), Vector3.ZERO, mat, Vector3.ZERO, root)
	node.name = "Ribbon_" + mat

func _annulus(y: float, inner: float, outer: float, depth: float, mat: String) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 128 if not distant else 48
	# Closed rectangular section gives the halos flat decks and machined sidewalls.
	for face in 4:
		st.set_smooth_group(face)
		for i in segments:
			var points: Array[Vector3] = []
			for angle in [float(i) * TAU / segments, float(i + 1) * TAU / segments]:
				for section in [Vector2(outer, depth * 0.5), Vector2(inner, depth * 0.5), Vector2(inner, -depth * 0.5), Vector2(outer, -depth * 0.5)]:
					points.append(Vector3(cos(angle) * section.x, y + section.y, sin(angle) * section.x))
			var next := (face + 1) % 4
			for index in [face, face + 4, next, next, face + 4, next + 4]:
				st.add_vertex(points[index])
	st.generate_normals()
	st.index()
	kit.mesh(st.commit(), Vector3.ZERO, mat, Vector3.ZERO, root)

func _ring(y: float, radius: float, thickness: float, mat: String) -> void:
	kit.torus_ring(origin + Vector3(0, y, 0), radius - thickness * 0.5, radius + thickness * 0.5, mat, 128 if not distant else 48, 8)

func _beam(a: Vector3, b: Vector3, width: float, mat := "helix_trim") -> void:
	var direction := b - a
	var basis := Basis()
	basis.y = direction.normalized()
	basis.x = basis.y.cross(Vector3.FORWARD).normalized()
	if basis.x.length() < 0.1:
		basis.x = Vector3.RIGHT
	basis.z = basis.x.cross(basis.y).normalized()
	_box(origin + (a + b) * 0.5, Vector3(width, direction.length(), width), mat, false, basis.get_euler())

func _box(pos: Vector3, size: Vector3, mat: String, collision := false, rotation := Vector3.ZERO) -> void:
	mat = kit.material_aliases.get(mat,mat)
	# Scale in each member's local axes so angled braces retain their thickness.
	var basis := Basis.from_euler(rotation)
	var key := "%s:%d:%d" % [mat, floori(pos.x / 64.0), floori(pos.z / 64.0)]
	if not kit.batches.has(key):
		kit.batches[key] = {"mat": mat, "transforms": []}
	var scaled := Basis(basis.x * size.x, basis.y * size.y, basis.z * size.z)
	kit.batches[key].transforms.append(Transform3D(scaled, pos))
	kit.box_count += 1
	if collision:
		var shape := BoxShape3D.new()
		shape.size = size
		kit.collider(shape, Transform3D(basis, pos))

func _build() -> void:
	var core_h := h * 0.84
	var core_r := h * 0.072
	var segments := 64 if not distant else 24
	# A solid service spine surrounded by real floor plates, then transparent glazing.
	kit.cylinder(origin + Vector3(0, core_h * 0.5, 0), h * 0.014, core_h, "helix_trim", h * 0.009, null, false, segments)
	kit.cylinder(origin + Vector3(0, core_h * 0.5, 0), core_r, core_h, "helix_glazing", h * 0.026, null, false, segments)
	var floors := int(core_h / 3.8)
	for floor_i in range(1, floors):
		var y := floor_i * 3.8
		var r := lerpf(core_r, h * 0.026, y / core_h)
		kit.cylinder(origin + Vector3(0, y, 0), r, 0.3, "helix_deck", -1, null, false, segments)
		_ring(y, r + 0.02, 0.13, "helix_titanium")
		if distant:
			continue
		for room in 8:
			var angle := room * TAU / 8.0
			var tangent := Vector3(-sin(angle), 0, cos(angle))
			var radial := Vector3(cos(angle), 0, sin(angle))
			var at := origin + radial * (r * 0.65) + Vector3(0, y + 2.8, 0)
			_box(at, Vector3(0.1, 0.06, r * 0.65), "helix_warm" if (floor_i + room) % 5 == 0 else "helix_room", false, Vector3(0, angle, 0))
			# Interior partitions and desks stay inside the glazing, leaving clear bays.
			if room % 2 == 0:
				_box(origin + radial * (r * 0.42) + Vector3(0, y + 1.35, 0), Vector3(r * 0.45, 2.4, 0.09), "helix_trim", false, Vector3(0, -angle, 0))
				_box(origin + radial * (r * 0.67) + tangent * 0.5 + Vector3(0, y + 0.8, 0), Vector3(0.8, 0.12, 1.4), "helix_titanium", false, Vector3(0, angle, 0))
	for column in 16:
		var angle := column * TAU / 16.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		_beam(radial * core_r, radial * (h * 0.026) + Vector3(0, core_h, 0), 0.12)

	for phase in [0.3, PI + 0.3]:
		_ribbon(phase, 0, 0.29, h * 0.009, "helix_titanium")
		for side in [-1.0, 1.0]:
			_ribbon(phase, side * 0.27, 0.012, h * 0.010, "helix_trim")
			_ribbon(phase, side * 0.26, 0.0035, h * 0.011, "helix_light")

	# Foundation transfers the twisting ribs into a visible stepped podium.
	kit.cylinder(origin + Vector3(0, 0.6, 0), h * 0.16, 1.2, "helix_trim", h * 0.155, null, not distant, segments)
	kit.cylinder(origin + Vector3(0, 1.45, 0), h * 0.153, 0.5, "helix_titanium", -1, null, false, segments)
	if not distant:
		var shape := CylinderShape3D.new()
		shape.radius = core_r
		shape.height = core_h
		kit.collider(shape, Transform3D(Basis(), origin + Vector3(0, core_h * 0.5, 0)))
		# Collision follows the actual solid ribbon roots rather than blocking the whole halo footprint.
		for phase in [0.3, PI + 0.3]:
			for i in 12:
				var t := (i + 0.5) / 12.0
				var angle: float = phase + t * TAU * 0.72
				var shape_rib := BoxShape3D.new()
				shape_rib.size = Vector3(h * 0.016, h * 0.1, _radius(t) * 0.58)
				kit.collider(shape_rib, Transform3D(Basis(Vector3.UP, angle), origin + _point(t, phase, 0, 0)))

	_halo(h * 0.81, h * 0.222, h * 0.246)
	_halo(h * 0.825, h * 0.142, h * 0.163)
	for pad in 3:
		_platform(h * [0.28, 0.46, 0.64][pad], [0.8, 2.9, 4.7][pad], pad)
	# Slender multi-stage aerial; the reference beacon remains a point light.
	kit.cylinder(origin + Vector3(0, h * 0.96, 0), h * 0.021, h * 0.22, "helix_titanium", 0.035, null, false, segments)
	kit.cylinder(origin + Vector3(0, h * 1.075, 0), 0.12, h * 0.06, "helix_trim", 0.025, null, false, 16)
	kit.cylinder(origin + Vector3(0, h * 1.104, 0), 0.16, 0.22, "helix_light", -1, null, false, 16)

func _halo(y: float, inner: float, outer: float) -> void:
	_annulus(y, inner, outer, h * 0.007, "helix_titanium")
	_annulus(y + h * 0.0037, inner + 0.35, outer - 0.35, 0.06, "helix_deck")
	for r in [inner + 0.15, outer - 0.15]:
		_ring(y + h * 0.0035 + 0.06, r, 0.09, "helix_light")
		_ring(y + h * 0.008, r, 0.07, "helix_trim")
	for spoke in 8:
		var angle := spoke * TAU / 8.0 + 0.3
		var radial := Vector3(cos(angle), 0, sin(angle))
		_beam(radial * h * 0.027 + Vector3(0, y, 0), radial * outer + Vector3(0, y, 0), h * 0.003)
		_beam(radial * h * 0.044 + Vector3(0, y - h * 0.075, 0), radial * (inner + 0.4) + Vector3(0, y - 0.3, 0), h * 0.003)
	if not distant:
		for segment in 48:
			var angle := segment * TAU / 48.0
			var radial := Vector3(cos(angle), 0, sin(angle))
			_beam(radial * (inner + 0.15) + Vector3(0, y + 0.3, 0), radial * (outer - 0.15) + Vector3(0, y + 0.3, 0), 0.055)
			for r in [inner + 0.15, outer - 0.15]:
				_beam(radial * r + Vector3(0, y + 0.3, 0), radial * r + Vector3(0, y + h * 0.008, 0), 0.045)

func _platform(y: float, angle: float, index: int) -> void:
	var radial := Vector3(cos(angle), 0, sin(angle))
	var center := radial * h * 0.183 + Vector3(0, y, 0)
	var radius := h * 0.055
	kit.cylinder(origin + center, radius, 0.5, "helix_titanium", radius * 0.85, null, not distant, 64 if not distant else 24)
	kit.cylinder(origin + center + Vector3(0, 0.28, 0), radius * 0.92, 0.07, "helix_deck", -1, null, false, 64 if not distant else 24)
	kit.torus_ring(origin + center, radius - 0.12, radius, "helix_light", 64 if not distant else 24, 8)
	for side in [-0.6, 0.6]:
		var tangent: Vector3 = Vector3(-sin(angle), 0, cos(angle)) * radius * side
		_beam(radial * h * 0.045 + Vector3(0, y - h * 0.045, 0), center + tangent + Vector3(0, -0.25, 0), 0.32)
		_beam(radial * h * 0.04 + Vector3(0, y, 0), center + tangent, 0.22, "helix_titanium")
	if not distant:
		for mark in 12:
			var a := mark * TAU / 12.0
			_box(origin + center + Vector3(cos(a) * radius * 0.77, 0.34, sin(a) * radius * 0.77), Vector3(0.12, 0.04, 0.4), "helix_room", false, Vector3(0, -a, 0))
		var display_pos := origin + center + Vector3(0, 1.2, 0)
		_box(display_pos, Vector3(2.0, 0.85, 0.1), "helix_deck")
		kit.label("%02d / ARRIVAL" % (index + 1), display_pos + Vector3(0, 0, 0.07), 24, 0.009)
