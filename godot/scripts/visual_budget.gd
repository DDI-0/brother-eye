extends RefCounted
## Merge immutable opaque mesh surfaces per material and spatial cell.
## Originals stay hidden for QA/reference; collision and moving landmarks are untouched.
var sources: Array[MeshInstance3D]=[]
var outputs: Array[MeshInstance3D]=[]
var enabled:=true
var merged_surfaces:=0
var source_layers: Dictionary={}
var details: Array[MultiMeshInstance3D]=[]
func collect(node: Node, city: Node) -> void:
	if node==city.satellite or node==city.command_signal or node.get_meta("animated_landmark",false):return
	if node is MultiMeshInstance3D and node.get_meta("decorative_detail",false):details.append(node)
	if node is MeshInstance3D and node.mesh and node.mesh.get_surface_count()==1 and node.is_visible_in_tree() and node.skin==null:
		sources.append(node)
	for child in node.get_children():collect(child,city)
func setup(city: Node3D) -> void:
	collect(city,city)
	var groups: Dictionary={}
	for source in sources:
		var source_mesh: ArrayMesh
		if source.mesh is ArrayMesh:source_mesh=source.mesh
		else:
			source_mesh=ArrayMesh.new();source_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.mesh.surface_get_arrays(0))
		for surface in source.mesh.get_surface_count():
			if source_mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:continue
			var material: Material=source.get_active_material(surface)
			# World-space architecture shader is merge-safe; custom hologram and
			# transparent glass need their own draw/sorting and remain separate.
			var opaque: bool=material is BaseMaterial3D and material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED
			if material is ShaderMaterial:opaque=material.shader==preload("res://shaders/architecture.gdshader")
			if not opaque:continue
			# Only fully compatible opaque meshes can be hidden as one unit.
			var all_opaque:=true
			for other in source.mesh.get_surface_count():
				var m: Material=source.get_active_material(other)
				if not ((m is BaseMaterial3D and m.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED) or (m is ShaderMaterial and m.shader==preload("res://shaders/architecture.gdshader"))):all_opaque=false
			if not all_opaque:continue
			var p: Vector3=source.global_transform*source.mesh.get_aabb().get_center()
			var key: String="%d:%d:%d:%d:%d:%d:%s"%[material.get_instance_id(),floori(p.x/48),floori(p.y/48),floori(p.z/48),source_mesh.surface_get_format(surface),source.cast_shadow,str(source.visibility_range_end)]
			if not groups.has(key):groups[key]={"material":material,"parts":[],"origin":Vector3((floori(p.x/48)+.5)*48,(floori(p.y/48)+.5)*48,(floori(p.z/48)+.5)*48),"shadow":source.cast_shadow,"range":source.visibility_range_end}
			groups[key].parts.append([source,surface])
	var hidden: Dictionary={}
	for key in groups:
		var g: Dictionary=groups[key]
		if g.parts.size()<2:continue
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in g.parts:
			var transform: Transform3D=city.global_transform.affine_inverse()*part[0].global_transform
			transform.origin-=g.origin
			st.append_from(part[0].mesh,part[1],transform)
		var mesh:=st.commit()
		if mesh==null:continue
		# Baking strips imported LOD indices; regenerate screen-error LODs so
		# distant batches do not force every full-resolution triangle to render.
		var importer:=ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,mesh.surface_get_arrays(0))
		importer.generate_lods(60.0,25.0,[])
		mesh=importer.get_mesh()
		var output:=MeshInstance3D.new();output.name="StaticVisualBatch";output.mesh=mesh;output.material_override=g.material
		output.position=g.origin;output.cast_shadow=g.shadow;output.visibility_range_end=g.range
		output.set_meta("render_budget_batch",true);city.add_child(output);outputs.append(output)
		for part in g.parts:hidden[part[0]]=true
		merged_surfaces+=g.parts.size()
	# A source with any unmerged surface must stay intact to avoid lost geometry.
	# Current sources are single-surface; exclude multi-surface meshes up front.
	for source in hidden:
		source_layers[source]=source.layers;source.layers=0
	sources.assign(hidden.keys())
	print("VISUAL_BUDGET sources=",sources.size()," batches=",outputs.size()," surfaces=",merged_surfaces)
func set_enabled(value: bool) -> void:
	enabled=value
	for source in sources:source.layers=0 if value else source_layers[source]
	for output in outputs:output.visible=value
	for detail in details:
		detail.visibility_range_end=220.0 if value else float(detail.get_meta("full_range",650.0))
		detail.visibility_range_end_margin=20.0 if value else 0.0
