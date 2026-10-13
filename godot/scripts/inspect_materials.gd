@tool
extends SceneTree

func _init() -> void:
	var packed: PackedScene = load("res://models/helix_spire/helix_spire.glb")
	if not packed:
		print("FAILED TO LOAD MODEL")
		quit(1)
		return
	var inst: Node3D = packed.instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		print("Node: ", node.name, " type: ", node.get_class())
		if node is MeshInstance3D:
			var mesh: Mesh = node.mesh
			print("  Mesh surfaces: ", mesh.get_surface_count())
			for s in mesh.get_surface_count():
				var mat: Material = node.get_surface_override_material(s)
				if not mat:
					mat = mesh.surface_get_material(s)
				if mat:
					print("    Surface ", s, " mat name: ", mat.resource_name, " class: ", mat.get_class())
					if mat is BaseMaterial3D:
						print("      albedo_color: ", mat.albedo_color)
						print("      albedo_texture: ", mat.albedo_texture != null)
						print("      roughness: ", mat.roughness)
						print("      metallic: ", mat.metallic)
						print("      metallic_texture: ", mat.metallic_texture != null)
						print("      roughness_texture: ", mat.roughness_texture != null)
						print("      normal_enabled: ", mat.normal_enabled)
						print("      normal_texture: ", mat.normal_texture != null)
						print("      emission_enabled: ", mat.emission_enabled)
						print("      emission: ", mat.emission)
						print("      emission_energy: ", mat.emission_energy_multiplier)
		for child in node.get_children():
			stack.push_back(child)
	quit(0)
