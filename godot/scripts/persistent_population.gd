extends Node3D
## Backend owns needs and decisions. This adapter owns physical travel and reports progress.
var city: Node3D
var bridge: Node
var navigation: Node3D
var person: CharacterBody3D
var restored := false
var was_live := false
var goal_id := ""
var citizen_id := ""
var motion_seq := 0
var last_capture := 0.0
var last_navigation := ""
var panel: PanelContainer
var detail: Label
var follow := false
var record: Dictionary = {}
var units: Dictionary = {}
var order: Array[String] = []
var selected := 0
var last_snapshot := ""

func setup(owner_city: Node3D, owner_bridge: Node) -> void:
	city=owner_city;bridge=owner_bridge
	navigation=preload("res://scripts/pedestrian_navigation.gd").new()
	add_child(navigation);navigation.setup(city)
	navigation.automatic=false
	navigation.set_process_unhandled_input(false)
	navigation.status.hide()
	person=navigation.pedestrian
	person.simulation_frozen=true
	person.visible=false
	var hud := CanvasLayer.new();hud.layer=3;add_child(hud)
	panel=PanelContainer.new();panel.position=Vector2(30,130);panel.custom_minimum_size=Vector2(350,0)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.065,.10,.94);style.set_content_margin_all(18);panel.add_theme_stylebox_override("panel",style)
	hud.add_child(panel)
	detail=Label.new();detail.add_theme_font_size_override("font_size",16);panel.add_child(detail)
	panel.hide()
	if "--behavior-review" in OS.get_cmdline_user_args():
		panel.show();follow=true;navigation.set_follow(true)

func capture_progress() -> void:
	if not restored or units.is_empty():return
	var reports: Array=[]
	for id in units:
		var unit: Dictionary=units[id]
		var actor: CharacterBody3D=unit.person
		unit.seq+=1
		var p: Vector3=actor.global_position
		reports.append({"citizen_id":id,"goal_id":unit.goal_id,"seq":unit.seq,
			"position":[p.x,p.y,p.z],"yaw":actor.model.rotation.y,"navigation":actor.state})
		unit.last_navigation=actor.state
	bridge.queue_command("set_population_progress",{"citizens":reports})
	last_capture=bridge.now()
	update_selection()

func apply_record(c: Dictionary) -> void:
	var id: String=c.id
	if not units.has(id):
		var actor: CharacterBody3D
		if units.is_empty():actor=person
		else:
			actor=preload("res://scripts/pedestrian.gd").new();actor.navigator=navigation
			if c.kind=="exceptional":
				actor.model_path="res://models/animated/exceptional_agent.glb";actor.body_height=2.0
			navigation.add_child(actor);navigation.people.append(actor)
		actor.simulation_frozen=true;actor.visible=false
		actor.enable_crowd()
		if c.kind=="exceptional":preload("res://scripts/exceptional_appearance.gd").apply(actor,int(c.appearance))
		else:preload("res://scripts/population_appearance.gd").apply(actor,int(c.appearance),c.kind=="police")
		units[id]={"person":actor,"goal_id":"","seq":0,"last_navigation":"","record":c}
		order.append(id)
	var unit: Dictionary=units[id]
	var actor: CharacterBody3D=unit.person
	unit.record=c
	var target_pose: String = c.goal.get("pose", "stand") if c.has("goal") and c.goal is Dictionary else "stand"
	var target_yaw: Variant = c.goal.get("yaw", null) if c.has("goal") and c.goal is Dictionary else null
	actor.set_goal_posture(target_pose, target_yaw)
	if not restored:
		unit.seq=int(c.motion_seq)
		actor.position=Vector3(c.position[0],c.position[1],c.position[2])
		actor.model.rotation.y=float(c.yaw);actor.velocity=Vector3.ZERO
		actor.agent.set_velocity_forced(Vector3.ZERO)
		actor.visible=true;unit.goal_id=""
		if target_pose == "sit" and c.navigation == "ARRIVED":
			actor.snap_seated(target_yaw if target_yaw != null else c.yaw)
	if str(c.goal.id)!=unit.goal_id:
		unit.goal_id=str(c.goal.id)
		if c.navigation!="ARRIVED":actor.go_to(Vector3(c.goal.position[0],c.goal.position[1],c.goal.position[2]))
		else:actor.active=false;actor.state="ARRIVED"
		unit.last_navigation=actor.state

func update_selection() -> void:
	if order.is_empty():return
	selected=posmod(selected,order.size())
	citizen_id=order[selected]
	var unit: Dictionary=units[citizen_id]
	person=unit.person;record=unit.record;goal_id=unit.goal_id;motion_seq=unit.seq
	navigation.pedestrian=person

func select_relative(offset: int) -> void:
	selected+=offset;update_selection();panel.show()

func select_person(id: String) -> void:
	var index:=order.find(id)
	if index<0:return
	selected=index;update_selection()

func _process(_delta: float) -> void:
	if bridge==null:return
	var live: bool=bridge.connected and bridge.restored and not bridge.quitting
	if not live:
		if was_live and not bridge.quitting:capture_progress()
		for unit in units.values():unit.person.simulation_frozen=true
		person.simulation_frozen=true
		if not bridge.restored:restored=false
		was_live=false
	else:
		var stamp: String=str(bridge.world.get("revision",0))+":"+str(bridge.world.get("tick",0))
		if not restored or stamp!=last_snapshot:
			for c in bridge.world.get("citizens",[]):apply_record(c)
			restored=not units.is_empty();last_snapshot=stamp;update_selection()
		var frozen: bool=bool(bridge.world.get("paused",false)) or not navigation.ready_for_paths
		var changed_state:=false
		for unit in units.values():
			unit.person.simulation_frozen=frozen
			if unit.person.state!=unit.last_navigation:changed_state=true
		if restored and not frozen and (bridge.now()-last_capture>1 or (changed_state and bridge.now()-last_capture>.25)):capture_progress()
		was_live=true
	if panel.visible:
		if record.is_empty():detail.text="Restoring population…"
		else:
			var n: Dictionary=record.needs
			var place: Dictionary=record.known_places.get(record.goal.place,{"name":"Local meeting"})
			var memory: String=record.memory[-1].detail if not record.memory.is_empty() else "No observations yet"
			if record.kind=="exceptional":memory=str(record.exceptional.behavior_stage).to_upper()+" · local ideological decisions"
			var n_pol := 0
			var n_exc := 0
			var n_civ := 0
			for u in units.values():
				var k: String = u.record.get("kind", "civilian")
				if k == "police": n_pol += 1
				elif k == "exceptional": n_exc += 1
				else: n_civ += 1
			var navigation_text: String = "BLOCKED · WAITING FOR ROUTE" if person.state == "WAITING FOR ROUTE" else person.state
			detail.text="%d CIVILIANS · %d POLICE · %d EXCEPTIONAL   |   %d / %d\n%s · %s\n\n%s → %s\n%s · %s\n\nHunger %d%%   Energy %d%%   Social need %d%%\nKnown places: %d · Memories: %d\nLast: %s\n\nF2 TIME / SAVE · F3 FOLLOW · F4 DETAILS\n[ / ] PREVIOUS / NEXT PERSON\nWASD / E Q CAMERA · SHIFT FASTER\nCLICK-DRAG / TWO-FINGER SCROLL ORBIT · R RESET" % [n_civ,n_pol,n_exc,selected+1,order.size(),record.name,record.role,str(record.activity).capitalize(),place.name,navigation_text,"PAUSED" if person.simulation_frozen else "ACTIVE",n.hunger,n.energy,n.social,record.known_places.size(),record.memory.size(),memory]

func _unhandled_input(event: InputEvent) -> void:
	if city.inspector!=null and city.inspector.is_open():return
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_BRACKETLEFT:select_relative(-1)
	elif event.keycode==KEY_BRACKETRIGHT:select_relative(1)
	elif event.keycode==KEY_F4:panel.visible=not panel.visible
	elif event.keycode==KEY_F3:
		follow=not follow;navigation.set_follow(follow)
		if follow:panel.show()
