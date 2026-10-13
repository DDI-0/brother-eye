extends Node
## Only a matching live ACK can pulse. Welcome history establishes a silent baseline.
var city: Node3D
var bridge: Node
var seen: Dictionary={}
var pulse:=0.0
var pulse_count:=0
var last_result: Dictionary={}
var message_until:=0.0
var recorded_result:=false
var banner: Label
var materials: Array[StandardMaterial3D]=[]
var base_energy: Array[float]=[]

func setup(owner_city: Node3D) -> void:
	city=owner_city;bridge=city.simulation
	for mesh in [city.satellite_signal,city.command_signal]:
		var material: StandardMaterial3D=mesh.material_override.duplicate()
		mesh.material_override=material;materials.append(material);base_energy.append(material.emission_energy_multiplier)
	var layer:=CanvasLayer.new();layer.layer=4;add_child(layer)
	banner=Label.new();banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	banner.offset_left=-520;banner.offset_right=-32;banner.offset_top=80;banner.offset_bottom=125
	banner.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;banner.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	banner.add_theme_color_override("font_outline_color",Color("071525"));banner.add_theme_constant_override("outline_size",5);layer.add_child(banner)
	bridge.session_observed.connect(baseline);bridge.intervention_acknowledged.connect(acknowledged)

func baseline(world: Dictionary) -> void:
	for event in world.get("intervention_history",[]):seen[event.command_id]=true
	# Silence in-flight feedback across recovery; no replayed celebratory effect.
	pulse=0.0;last_result={};message_until=0.0

func acknowledged(result: Dictionary, current: bool) -> void:
	var id: String=result.get("id","")
	var fresh: bool=not seen.has(id)
	seen[id]=true
	recorded_result=not current or not fresh
	bridge.intervention_result["recorded"]=recorded_result
	last_result=result.duplicate(true);message_until=bridge.now()+5.0
	if not current or not fresh:return
	if result.outcome=="rejected":pulse=0.0
	if result.outcome=="accepted":
		# Require an actual committed audit entry, never just a success-shaped response.
		for event in bridge.world.get("intervention_history",[]):
			if event.command_id==id and event.outcome=="accepted":pulse=1.0;pulse_count+=1;break

func _process(delta: float) -> void:
	if bridge==null:return
	var live: bool=bridge.connected and bridge.restored and not bridge.quitting and not bridge.fatal
	if not live:pulse=0.0
	else:pulse=maxf(0,pulse-delta/1.4)
	for i in materials.size():materials[i].emission_energy_multiplier=base_energy[i]+pulse*1.6
	var pending:=0
	for request in bridge.pending:
		if request.type=="intervene":pending+=1
	if not live:
		banner.text="BROTHER EYE · OFFLINE / LAST KNOWN" if not bridge.world.is_empty() else "BROTHER EYE · CONNECTING"
		banner.modulate=Color("edbf78")
	elif pending>0:
		banner.text="BROTHER EYE · %d COMMAND%s PENDING"%[pending,"S" if pending!=1 else ""]
		banner.modulate=Color("edbf78")
	elif bridge.now()<message_until and not last_result.is_empty():
		banner.text=("BROTHER EYE · RECORDED RESULT · " if recorded_result else "BROTHER EYE · ")+str(last_result.outcome).to_upper()+"\n"+str(last_result.message)
		banner.modulate=Color("92dbeb") if last_result.outcome=="accepted" else Color("edbf78")
	else:banner.text=""
