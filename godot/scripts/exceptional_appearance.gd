extends RefCounted
## Four cached material palettes; original astronaut meshes, rig and clips are shared.
static var materials: Dictionary={}
const ARMOR=["b5c3cc","344c68","8e6652","426057"]
const ACCENT=["d5bc75","8c8fdd","dfa66e","83c4b1"]
const TITLES=["I · ARBITER","II · ATTENDANT","III · MARTYR","IV · SOVEREIGN"]
static func apply(person: CharacterBody3D,variant: int) -> void:
	for node in person.model.find_children("*","MeshInstance3D",true,false):
		for surface in node.mesh.get_surface_count():
			var source: Material=node.get_active_material(surface)
			if not source is StandardMaterial3D:continue
			var key:=str(variant)+":"+source.resource_name
			if not materials.has(key):
				var mat: StandardMaterial3D=source.duplicate()
				if source.resource_name.begins_with("Helmet_Slate"):mat.albedo_color=Color(ARMOR[variant])
				elif source.resource_name.begins_with("Helmet_Detail"):mat.albedo_color=Color(ACCENT[variant])
				elif source.resource_name.begins_with("Suit_Graphite"):mat.albedo_color=Color(ARMOR[variant]).darkened(.55)
				materials[key]=mat
			node.set_surface_override_material(surface,materials[key])
	var label:=Label3D.new();label.text=TITLES[variant];label.position.y=2.2
	label.font_size=24;label.pixel_size=.003;label.modulate=Color(ACCENT[variant])
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;person.add_child(label)
