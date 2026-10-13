@tool
extends SceneTree

func _init() -> void:
	var glb: PackedScene = load("res://models/helix_spire/helix_spire.glb")
	if not glb:
		quit(1)
		return
	var inst: Node3D = glb.instantiate()
	var mesh_inst: MeshInstance3D = inst.get_node("model") as MeshInstance3D
	var mat: BaseMaterial3D = mesh_inst.mesh.surface_get_material(0) as BaseMaterial3D
	if mat:
		print("Mat: ", mat.resource_name)
		print("Albedo color: ", mat.albedo_color)
		if mat.albedo_texture:
			var img: Image = mat.albedo_texture.get_image()
			print("Albedo texture size: ", img.get_size(), " format: ", img.get_format())
			img.save_png("res://pbr_albedo.png")
		if mat.normal_texture:
			var nimg: Image = mat.normal_texture.get_image()
			print("Normal texture size: ", nimg.get_size())
		if mat.metallic_texture:
			var mimg: Image = mat.metallic_texture.get_image()
			print("Metallic texture size: ", mimg.get_size())
		if mat.roughness_texture:
			var rimg: Image = mat.roughness_texture.get_image()
			print("Roughness texture size: ", rimg.get_size())
	quit(0)
