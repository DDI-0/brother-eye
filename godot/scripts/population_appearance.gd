extends RefCounted
## Palette overrides share meshes, skins, animations and cached materials.
static var materials: Dictionary={}
const COATS=["122840","284c50","485263","594345","68624d","34486b","4a3e61","53655d","142944"]
const SKIN=["ba9076","805943","c6a18a","6b4838","a97a58","d3ad91","91624d","b48c6b","ad856b"]
const HAIR=["16120f","29201b","17191c","32251a","423124","1e1713","302522","39302a","141719"]
static func apply(person: CharacterBody3D,variant: int,police: bool) -> void:
	for node in person.model.find_children("*","MeshInstance3D",true,false):
		for surface in node.mesh.get_surface_count():
			var source: Material=node.get_active_material(surface)
			if not source is StandardMaterial3D:continue
			var key:=str(variant)+":"+source.resource_name
			if not materials.has(key):
				var mat: StandardMaterial3D=source.duplicate()
				var name: String=source.resource_name
				if name.begins_with("Jacket_Midnight"):mat.albedo_color=Color(COATS[variant])
				elif name.begins_with("Jacket_Slate"):mat.albedo_color=Color("90abba") if police else Color(COATS[variant]).lightened(.13)
				elif name.begins_with("Skin_"):mat.albedo_color=Color(SKIN[variant])
				elif name.begins_with("Hair_"):mat.albedo_color=Color(HAIR[variant])
				elif police and name.begins_with("Details_"):mat.albedo_color=Color("e4c379")
				elif police and name.begins_with("Trousers_"):mat.albedo_color=Color("142336")
				materials[key]=mat
			node.set_surface_override_material(surface,materials[key])
	if police:
		var label:=Label3D.new();label.text="POLICE";label.position.y=2.05
		label.font_size=32;label.pixel_size=.004;label.modulate=Color("addce6")
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.no_depth_test=false
		person.add_child(label)
