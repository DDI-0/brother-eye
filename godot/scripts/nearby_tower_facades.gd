extends RefCounted
## Scoped material palettes and shallow facade members for the playable towers.
## This layer uses no city RNG and adds no colliders, crowns or changes to tower massing.
var kit: RefCounted
const TONES := [
	["929a94","6e7d81","213a45"], # western helix: warm titanium
	["4b575f","928574","223442"], # stepped asset: graphite and champagne
	["7c796c","a49b86","25383f"], # inverted tower: champagne ceramic
	["3b626a","829696","173a48"], # wave: teal ceramic and smoked glass
	["354652","7b8c96","1c303f"], # fork: dark structural steel
	["96988c","5c747e","233d4c"], # discs: pale composite decks
	["756355","a5957a","20323e"], # blade: anodized bronze
	["667d88","a4b5bc","193743"]  # eastern helix: cool alloy
]
func _init(geometry: RefCounted) -> void:
	kit = geometry
	for style in TONES.size():
		var tone: Array = TONES[style]
		var prefix := "near_%d_" % style
		for spec in [["navy",tone[0],.50,.52],["steel",tone[0],.62,.42],["edge",tone[1],.66,.36]]:
			var material := ShaderMaterial.new()
			material.shader = preload("res://shaders/command_facade.gdshader")
			material.set_shader_parameter("tint",Color(spec[1]))
			material.set_shader_parameter("metal",spec[2])
			material.set_shader_parameter("roughness",spec[3])
			kit.materials[prefix+spec[0]] = material
		kit.material(prefix+"glass",Color(tone[2]),.58,.23)
		kit.material(prefix+"dark",Color("15232c"),.2,.65)
		kit.material(prefix+"cyan",Color("45b1c4"),.15,.4,.8)
		kit.material(prefix+"blue",Color("548ba5"),.15,.4,.55)
		kit.material(prefix+"red",Color("c14641"),.1,.5,1.1)
		kit.material(prefix+"window",Color("52747d"),.3,.4,.18)
		kit.material(prefix+"ice",Color("95aeb0"),.2,.45,.28)
		kit.material(prefix+"warm",Color("c1a67d"),.1,.6,.32)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(.16,.25,.29,.20)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		glass.roughness = .22
		kit.materials[prefix+"helix_glazing"] = glass

func aliases(style: int) -> Dictionary:
	var result := {}
	var prefix := "near_%d_" % style
	for key in ["navy","steel","edge","glass","cyan","blue","red","window","ice","warm"]:
		result[key] = prefix+key
	for pair in [["helix_titanium","steel"],["helix_trim","edge"],["helix_deck","dark"],["helix_light","cyan"],["helix_room","ice"],["helix_warm","warm"]]:
		result[pair[0]] = prefix+pair[1]
	result["helix_glazing"] = prefix+"helix_glazing"
	return result

func rod(a: Vector3, b: Vector3, radius: float, mat := "edge") -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	kit.mesh(mesh,(a+b)*.5,mat,Quaternion(Vector3.UP,(b-a).normalized()).get_euler())

func ring(pos: Vector3, radius: float, width := .07) -> void:
	kit.torus_ring(pos,radius-width*.5,radius+width*.5,"edge",48,6)

func dress(pos: Vector3, r: float, h: float, kind: int, variant: int) -> void:
	match kind:
		0:
			# Service doors and a lintel sit against the existing core inside the ribbons.
			var radius := h*.072
			kit.box(pos+Vector3(0,3.3,radius+.04),Vector3(2.8,3.0,.08),"glass")
			kit.box(pos+Vector3(0,4.9,radius+.12),Vector3(3.2,.18,.28),"edge")
			for x in [-1.4,0.0,1.4]:
				kit.box(pos+Vector3(x,3.3,radius+.12),Vector3(.055,3,.13),"edge")
		2:
			# Glazing, floor rings and mullions sit just outside the original tapered hull.
			kit.cylinder(pos+Vector3(0,h*.51,0),r*.3124+.035,h*.42,"glass",r*.766+.035,null,false,48)
			for floor_i in range(1,int(h*.46/4)):
				var y := h*.29+floor_i*4.0
				var t := (y-h*.29)/(h*.46)
				ring(pos+Vector3(0,y,0),r*lerpf(.3016,.7984,t)+.07)
			for i in 12:
				var a := i*TAU/12
				var radial := Vector3(cos(a),0,sin(a))
				rod(pos+radial*(r*.3016+.08)+Vector3(0,h*.29,0),pos+radial*(r*.7984+.08)+Vector3(0,h*.75,0),.04)
		3:
			for section in 7:
				var t := float(section)/7
				var center := pos+Vector3(sin(t*TAU*.65+variant*.7)*r*.25,h/7*(section+.5),cos(t*TAU*.4+variant*.5)*r*.12)
				var radius := r*(.32+sin(t*PI)*.12)
				# A cylindrical glazing veneer keeps the S-shaped stacked profile.
				kit.cylinder(center,radius+.035,h/7*.63,"glass",-1,null,false,48)
				for floor_i in range(1,int(h/7/3.3)+1):
					ring(center+Vector3(0,-h/14+floor_i*3.3,0),radius+.055,.06)
				for col in 10:
					var a := col*TAU/10
					var radial := Vector3(cos(a),0,sin(a))
					rod(center+radial*(radius+.08)-Vector3(0,h/7*.31,0),center+radial*(radius+.08)+Vector3(0,h/7*.31,0),.035)
		4:
			for floor_i in range(2,int(h*.55/3.8)):
				var y := floor_i*3.8
				var radius := r*lerpf(.32,.28,y/(h*.6))
				ring(pos+Vector3(0,y,0),radius+.05)
			for col in 8:
				var a := col*TAU/8
				var radial := Vector3(cos(a),0,sin(a))
				rod(pos+radial*r*.35+Vector3(0,h*.13,0),pos+radial*r*.29+Vector3(0,h*.55,0),.045)
		5:
			var count := 5+variant%3
			for i in count:
				var t := float(i+1)/(count+1)
				var radius := r*(.75-t*.25)
				var y := t*h
				ring(pos+Vector3(0,y+1.26,0),radius-.08,.055)
				for col in 8:
					var a := col*TAU/8
					var radial := Vector3(cos(a),0,sin(a))
					rod(pos+radial*r*.13+Vector3(0,y-2.1,0),pos+radial*radius*.72+Vector3(0,y-1.35,0),.06)
		6:
			for side in [-1.0,1.0]:
				var x: float = side*(r*.075+.025)
				kit.box(pos+Vector3(x,h*.42,0),Vector3(.035,h*.65,r*.54),"glass")
				for floor_i in range(3,int(h*.73/3.8)):
					kit.box(pos+Vector3(x+side*.03,floor_i*3.8,0),Vector3(.07,.08,r*.6),"edge")
				for z in [-.27,0.0,.27]:
					kit.box(pos+Vector3(x+side*.04,h*.42,r*z),Vector3(.08,h*.65,.065),"edge")

func tint_asset(node: Node, _style: int) -> void:
	# Keep the supplied model's texture maps and mesh hierarchy intact.
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var source: Material = node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D = source.duplicate()
				material.albedo_color = material.albedo_color*Color("c4c3b8")
				material.roughness = maxf(material.roughness,.4)
				node.set_surface_override_material(surface,material)
	for child in node.get_children(): tint_asset(child,_style)
