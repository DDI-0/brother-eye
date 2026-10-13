@tool
extends SceneTree

func _init() -> void:
	var shaded: PackedScene = load("res://models/helix_spire/3ae9fb35-bf18-4829-8132-fbcf536eb7bf/base_basic_shaded.glb")
	if not shaded:
		print("FAILED LOAD SHADED")
		quit(1)
		return
	var inst: Node3D = shaded.instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var m: Mesh = node.mesh
			print("Shaded surfaces: ", m.get_surface_count())
			for s in m.get_surface_count():
				var mat: Material = m.surface_get_material(s)
				if mat is BaseMaterial3D:
					print("  albedo_color: ", mat.albedo_color)
					print("  albedo_texture: ", mat.albedo_texture != null)
					if mat.albedo_texture:
						var img: Image = mat.albedo_texture.get_image()
						if img:
							print("  texture size: ", img.get_size(), " format: ", img.get_format())
		for child in node.get_children():
			stack.push_back(child)
	quit(0)
