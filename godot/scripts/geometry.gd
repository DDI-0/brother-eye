extends RefCounted
## Procedural kit. Decorative boxes are instanced per material and district cell.
## Collision uses independent simple shapes, so visuals can later be replaced.
var root: Node3D
var materials: Dictionary = {}
# Scoped aliases resolve before batching so landmark palettes never leak.
var material_aliases: Dictionary = {}
var batches: Dictionary = {}
var solid: StaticBody3D
var box_count := 0
var collision_count := 0

var base_tex: Texture2D
var mr_tex: Texture2D

static func _load_tex(rel_path: String) -> Texture2D:
	var abs_path := ProjectSettings.globalize_path(rel_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img := Image.load_from_file(abs_path)
	if img != null:
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img)
	return null

func _init(parent: Node3D) -> void:
	root = parent
	solid = StaticBody3D.new()
	solid.name = "CityCollision"
	root.add_child(solid)
	base_tex = _load_tex("res://textures/Metal_main_baseColor.jpg")
	if base_tex == null:
		base_tex = _load_tex("res://textures/Metal_main_baseColor.jpeg")
	mr_tex = _load_tex("res://textures/Metal_main_metallicRoughness.png")
	material("navy", Color("1a2936"), 0.75, 0.4)
	material("steel", Color("334e63"), 0.85, 0.35)
	material("edge", Color("4d6e85"), 0.9, 0.3)
	material("road", Color("0e1822"), 0.4, 0.65)
	material("paving", Color("1b2a38"), 0.3, 0.7)
	material("glass", Color("0c263f"), 0.65, 0.23)
	material("cyan", Color("00e5ff"), 0.25, 0.2, 3.0)
	material("blue", Color("0088ff"), 0.25, 0.2, 2.0)
	material("red", Color("ff1d38"), 0.25, 0.2, 3.5)
	material("ice", Color("a6e1f0"), 0.2, 0.4, 1.8)
	material("window", Color("34738d"), 0.2, 0.4, 0.8)
	material("warm", Color("cba879"), 0.2, 0.4, 0.8)

func material(id: String, color: Color, metal: float, rough: float, emission := 0.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if emission > 0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	materials[id] = m
	if id in ["navy","steel","edge","paving","road"]:
		var architectural := ShaderMaterial.new()
		architectural.shader = preload("res://shaders/architecture.gdshader")
		architectural.set_shader_parameter("tint", color)
		architectural.set_shader_parameter("metal", metal)
		architectural.set_shader_parameter("rough", rough)
		if base_tex != null:
			architectural.set_shader_parameter("albedo_texture", base_tex)
		if mr_tex != null:
			architectural.set_shader_parameter("metallic_roughness_texture", mr_tex)
		architectural.set_shader_parameter("pavement", id in ["paving","road"])
		materials[id] = architectural

func box(pos: Vector3, size: Vector3, mat := "navy", collision := false, rotation := Vector3.ZERO) -> void:
	mat = material_aliases.get(mat,mat)
	var basis := Basis.from_euler(rotation)
	var detail: bool = not collision and size[size.max_axis_index()] < 4.0
	var key := "%s:%d:%d:%s" % [mat, floori(pos.x / 64.0), floori(pos.z / 64.0), "detail" if detail else "structure"]
	if not batches.has(key):
		batches[key] = {"mat": mat, "transforms": [], "detail":detail}
	batches[key].transforms.append(Transform3D(basis.scaled(size), pos))
	box_count += 1
	if collision:
		var shape := BoxShape3D.new()
		shape.size = size
		collider(shape, Transform3D(basis, pos))

func collider(shape: Shape3D, transform: Transform3D) -> void:
	var c := CollisionShape3D.new()
	c.shape = shape
	c.transform = transform
	solid.add_child(c)
	collision_count += 1

func mesh(mesh_resource: Mesh, pos: Vector3, mat: String, rotation := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	mat = material_aliases.get(mat,mat)
	var m := MeshInstance3D.new()
	m.mesh = mesh_resource
	m.material_override = materials[mat]
	m.position = pos
	m.rotation = rotation
	(parent if parent != null else root).add_child(m)
	return m

func cylinder(pos: Vector3, radius: float, height: float, mat := "steel", top := -1.0, parent: Node3D = null, collision := false, segments := 32) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0 else top
	c.height = height
	c.radial_segments = segments
	if collision:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		collider(shape,Transform3D(Basis(),pos))
	return mesh(c, pos, mat, Vector3.ZERO, parent)

func beam(a: Vector3, b: Vector3, thickness: float, mat := "edge") -> void:
	var direction := b - a
	var basis := Basis()
	basis.y = direction.normalized()
	basis.x = basis.y.cross(Vector3.FORWARD).normalized()
	if basis.x.length() < 0.1:
		basis.x = Vector3.RIGHT
	basis.z = basis.x.cross(basis.y).normalized()
	box((a+b)*0.5, Vector3(thickness,direction.length(),thickness), mat, false, basis.get_euler())

func fin(pos: Vector3, width: float, height: float, depth: float, mat := "steel") -> void:
	# Six-faced blade with an asymmetric sloping crown, matching the references.
	var p := [Vector3(-width/2,0,-depth/2),Vector3(width/2,0,-depth/2),Vector3(width/2,height*0.84,-depth/2),Vector3(-width/2,height,-depth/2),Vector3(-width/2,0,depth/2),Vector3(width/2,0,depth/2),Vector3(width/2,height*0.84,depth/2),Vector3(-width/2,height,depth/2)]
	var ids := [0,2,1,0,3,2,4,5,6,4,6,7,0,4,7,0,7,3,1,2,6,1,6,5,3,7,6,3,6,2,0,1,5,0,5,4]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in ids:
		st.add_vertex(p[i])
	st.generate_normals()
	mesh(st.commit(), pos, mat)
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(p)
	collider(shape,Transform3D(Basis(),pos))

func label(text: String, pos: Vector3, size := 48, pixel := 0.018, rotation := Vector3.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = Color("b1e7ef")
	l.outline_size = 2
	l.outline_modulate = Color("071525")
	l.position = pos
	l.rotation = rotation
	root.add_child(l)
	return l

func torus_ring(pos: Vector3, inner_r: float, outer_r: float, mat := "steel", segments := 32, ring_segs := 8, rotation := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = inner_r
	t.outer_radius = outer_r
	t.rings = segments
	t.ring_segments = ring_segs
	return mesh(t, pos, mat, rotation, parent)

func helix_beam(center: Vector3, radius: float, height: float, thickness: float, turns: float, segments_per_turn := 12, mat := "cyan", phase := 0.0) -> void:
	var total_segments := int(turns * segments_per_turn)
	if total_segments < 1:
		return
	for i in total_segments:
		var t0 := float(i) / total_segments
		var t1 := float(i + 1) / total_segments
		var a0 := t0 * turns * TAU + phase
		var a1 := t1 * turns * TAU + phase
		var p0 := center + Vector3(cos(a0) * radius, t0 * height, sin(a0) * radius)
		var p1 := center + Vector3(cos(a1) * radius, t1 * height, sin(a1) * radius)
		beam(p0, p1, thickness, mat)

func flush() -> void:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for key in batches:
		var batch: Dictionary = batches[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = unit
		mm.instance_count = batch.transforms.size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, batch.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Kit_" + key.replace(":", "_")
		instance.multimesh = mm
		instance.material_override = materials[batch.mat]
		instance.visibility_range_end = 220.0 if batch.get("detail",false) else batch.get("range_end", 650.0)
		instance.visibility_range_end_margin = 20.0 if batch.get("detail",false) else 0.0
		instance.set_meta("decorative_detail",batch.get("detail",false))
		instance.set_meta("full_range",batch.get("range_end",650.0))
		if batch.mat in ["cyan", "blue", "ice", "window", "warm", "red"]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(instance)
	batches.clear()
