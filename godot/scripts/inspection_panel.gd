extends CanvasLayer
const Model=preload("res://scripts/inspection_model.gd")
const Evaluation=preload("res://scripts/evaluation_view.gd")
var control_room: VBoxContainer
var control_mode:=false
var select_exceptional_on_restore:=false
var interventions: VBoxContainer
var city_mode:=false
var priority_button: Button
var city: Node3D
var bridge: Node
var pop: Node3D
var overlay: Control
var panel: PanelContainer
var search: LineEdit
var kind: OptionButton
var roster: ItemList
var count: Label
var status: Label
var heading: Label
var identity: Label
var tabs: TabBar
var body: RichTextLabel
var needs_row: HBoxContainer
var needs: Array[ProgressBar]=[]
var need_labels: Array[Label]=[]
var decisions: CheckButton
var follow_button: Button
var selected_id:=""
var rows: Array[Dictionary]=[]
var view: Dictionary={}
var roster_stamp:=""
var timer:=0.0
var capture_before:=false
var details_before:=false
var page_key:=""

func setup(owner_city: Node3D) -> void:
	city=owner_city;bridge=city.simulation;pop=city.population;layer=6
	overlay=Control.new();overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(overlay)
	var shade:=ColorRect.new();shade.color=Color(0,.015,.025,.48);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.add_child(shade)
	panel=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left=32;panel.offset_right=-32;panel.offset_top=75;panel.offset_bottom=-35
	panel.theme=city.hud.menu.get_parent().theme
	var style:=StyleBoxFlat.new();style.bg_color=Color("081824");style.border_color=Color("427489");style.set_border_width_all(1);style.set_content_margin_all(24);panel.add_theme_stylebox_override("panel",style)
	overlay.add_child(panel)
	var content:=VBoxContainer.new();content.add_theme_constant_override("separation",14);panel.add_child(content)
	var top:=HBoxContainer.new();content.add_child(top)
	var title:=Label.new();title.text="◉  BROTHER EYE  /  INSPECTION & CONTROL";title.add_theme_font_size_override("font_size",23);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(title)
	button(top,"Control room  /  F7",open_control_room)
	button(top,"City evaluation  /  F6",open_evaluation)
	button(top,"Close  /  F5",close)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.modulate=Color("88c8d8");content.add_child(status)
	var columns:=HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_theme_constant_override("separation",24);content.add_child(columns)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=300;columns.add_child(left)
	search=LineEdit.new();search.placeholder_text="Search name, role or ID";search.clear_button_enabled=true;left.add_child(search)
	kind=OptionButton.new();kind.add_item("All residents");kind.add_item("Civilians");kind.add_item("Police");kind.add_item("Flagged residents");kind.add_item("Exceptional Agents");left.add_child(kind)
	count=Label.new();left.add_child(count)
	roster=ItemList.new();roster.size_flags_vertical=Control.SIZE_EXPAND_FILL;roster.custom_minimum_size.y=180;roster.fixed_column_width=300;left.add_child(roster)
	search.text_changed.connect(func(_text):refresh())
	kind.item_selected.connect(func(_index):refresh())
	roster.item_selected.connect(func(index):select_person(rows[index].id))
	var right:=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.add_theme_constant_override("separation",12);columns.add_child(right)
	heading=Label.new();heading.add_theme_font_size_override("font_size",27);right.add_child(heading)
	identity=Label.new();identity.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;identity.modulate=Color("98b7c6");right.add_child(identity)
	tabs=TabBar.new()
	for name in ["Overview","Known places","Schedule","Memory & decisions","Assessment","Interventions"]:tabs.add_tab(name)
	right.add_child(tabs);tabs.tab_changed.connect(func(_index):refresh())
	needs_row=HBoxContainer.new();needs_row.add_theme_constant_override("separation",20);right.add_child(needs_row)
	for name in ["Hunger","Energy","Social need"]:
		var group:=VBoxContainer.new();group.size_flags_horizontal=Control.SIZE_EXPAND_FILL;needs_row.add_child(group)
		var label:=Label.new();label.text=name;group.add_child(label);need_labels.append(label)
		var bar:=ProgressBar.new();bar.custom_minimum_size.y=8;bar.show_percentage=false;group.add_child(bar);needs.append(bar)
	decisions=CheckButton.new();decisions.text="Decisions only";right.add_child(decisions);decisions.toggled.connect(func(_pressed):refresh())
	interventions=preload("res://scripts/intervention_controls.gd").new();right.add_child(interventions);interventions.setup(self,bridge);interventions.hide()
	body=RichTextLabel.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.selection_enabled=true;body.add_theme_font_size_override("normal_font_size",16);right.add_child(body)
	control_room=preload("res://scripts/control_room.gd").new();right.add_child(control_room);control_room.setup(self);control_room.hide()
	var actions:=HBoxContainer.new();right.add_child(actions)
	follow_button=button(actions,"Follow selected resident  /  F3",follow_selected)
	priority_button=button(actions,"Inspect first finding",inspect_priority)
	button(actions,"Resident interventions",open_interventions)
	button(actions,"City time  /  F2",func():close();bridge.panel.toggle())
	var note:=Label.new();note.text="Inspection follows the city clock. Use City time to pause and examine a moment.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.modulate=Color("789bab");content.add_child(note)
	overlay.hide()
	if "--exceptional-review" in OS.get_cmdline_user_args():call_deferred("open_exceptional")
	elif "--control-room-review" in OS.get_cmdline_user_args():call_deferred("open_control_room")
	elif "--intervention-review" in OS.get_cmdline_user_args():call_deferred("open_interventions")
	elif "--evaluation-review" in OS.get_cmdline_user_args():call_deferred("open_evaluation")
	elif "--inspection-review" in OS.get_cmdline_user_args():call_deferred("open")

func button(parent: Node, text: String, action: Callable) -> Button:
	var b:=Button.new();b.text=text;b.pressed.connect(func():b.release_focus();action.call());parent.add_child(b);return b

func is_open() -> bool:return overlay!=null and overlay.visible

func open() -> void:
	if is_open():return
	capture_before=city.explorer.mouse_active;details_before=pop.panel.visible
	selected_id=pop.citizen_id
	city.explorer.set_capture(false);bridge.panel.panel.hide();pop.panel.hide();overlay.show();refresh()

func close() -> void:
	if not is_open():return
	control_room.suspend()
	overlay.hide();search.release_focus();roster.release_focus();pop.panel.visible=details_before
	city.explorer.set_capture(capture_before and not pop.follow and bridge.connected and bridge.restored)

func select_person(id: String) -> void:
	if not pop.order.has(id):return
	if city_mode:city_mode=false;tabs.current_tab=4
	selected_id=id;pop.select_person(id);refresh()

func open_exceptional() -> void:
	open();control_mode=false;city_mode=false;tabs.current_tab=0;kind.select(4)
	select_exceptional_on_restore=true;refresh()

func open_control_room() -> void:
	open();control_mode=true;city_mode=false;control_room.activate();refresh()

func open_interventions() -> void:
	open();control_mode=false;city_mode=false;tabs.current_tab=5;refresh()

func open_evaluation() -> void:
	open();control_mode=false;city_mode=true;refresh()

func inspect_priority() -> void:
	if Evaluation.matches(bridge.assessment,bridge.world) and not bridge.assessment.findings.is_empty():select_person(bridge.assessment.findings[0].citizen_id)

func follow_selected() -> void:
	if city_mode or view.is_empty():return
	pop.select_person(selected_id);capture_before=false;details_before=true;close()
	pop.follow=true;pop.navigation.set_follow(true);pop.panel.show()

func refresh() -> void:
	if not is_open():return
	if selected_id.is_empty() and not pop.order.is_empty():selected_id=pop.order[pop.selected]
	var filter_kind: String=["all","civilian","police","all","exceptional"][kind.selected]
	var next_rows:=Model.roster(bridge.world,search.text,filter_kind)
	if select_exceptional_on_restore and not next_rows.is_empty():
		selected_id=next_rows[0].id;pop.select_person(selected_id);select_exceptional_on_restore=false
	var report: Dictionary=bridge.assessment
	var matching:=Evaluation.matches(report,bridge.world)
	var flagged: Dictionary={}
	if matching:
		for finding in report.findings:flagged[finding.citizen_id]=true
	if kind.selected==3:next_rows=next_rows.filter(func(row):return flagged.has(row.id))
	var stamp:=JSON.stringify(next_rows)
	if stamp!=roster_stamp:
		roster_stamp=stamp;rows=next_rows;roster.clear()
		for row in rows:
			roster.add_item(row.name+("  ·  POLICE" if row.kind=="police" else ""))
			roster.set_item_tooltip(roster.item_count-1,row.name+" · "+row.role)
	for i in rows.size():
		if rows[i].id==selected_id:roster.select(i)
	count.text="%d / %d residents%s"%[rows.size(),bridge.world.get("citizens",[]).size()," · No matches" if rows.is_empty() else ""]
	view=Model.inspect(bridge.world,selected_id)
	var live: bool=bridge.connected and bridge.restored and not bridge.quitting
	status.text=("CONFIRMED SNAPSHOT · " if live else "LAST KNOWN SNAPSHOT · CONNECTION UNAVAILABLE · ")+Model.city_time(bridge.world.get("clock_seconds",0))+(" · PAUSED" if bridge.world.get("paused",true) else " · RUNNING")
	status.modulate=Color("88c8d8") if live else Color("edbf78")
	tabs.visible=not city_mode and not control_mode
	body.visible=not control_mode
	control_room.visible=control_mode
	needs_row.visible=not city_mode and not control_mode and tabs.current_tab==0 and not view.is_empty();decisions.visible=not city_mode and not control_mode and tabs.current_tab==3
	follow_button.visible=not city_mode;follow_button.disabled=view.is_empty() or not live
	priority_button.visible=city_mode;priority_button.disabled=not live or not matching or report.get("findings",[]).is_empty()
	if view.is_empty():heading.text="Restoring residents…";identity.text="Waiting for a confirmed city snapshot."
	else:
		var c: Dictionary=view.citizen
		heading.text=c.name;identity.text=c.role+" · "+str(c.kind).capitalize()
		var keys: Array=["hunger","energy","social"]
		for i in keys.size():needs[i].value=c.needs[keys[i]];need_labels[i].text=["Hunger","Energy","Social need"][i]+" · %.1f%%"%c.needs[keys[i]]
	interventions.visible=not city_mode and not control_mode and tabs.current_tab==5
	interventions.refresh(view.get("citizen",{}))
	var text:=Model.page(view,tabs.current_tab,decisions.button_pressed)
	if city_mode:
		heading.text="Civic district assessment";identity.text="Recorded needs and navigation · Explained rules · Suggestions for review"
		text=Evaluation.page(report,bridge.world)
	elif tabs.current_tab==4:text=Evaluation.page(report,bridge.world,selected_id)
	elif tabs.current_tab==5:text=interventions.page(bridge.world,view.get("citizen",{}))
	if not city_mode and tabs.current_tab==0 and not view.is_empty() and pop.units.has(selected_id):
		var actor: CharacterBody3D=pop.units[selected_id].person
		text+="\n\nLOCAL CHARACTER\n%s · %s\nPosition %.2f, %.2f, %.2f m"%[actor.state,"FROZEN" if actor.simulation_frozen else "ACTIVE",actor.position.x,actor.position.y,actor.position.z]
	if control_mode:
		heading.text="Brother Eye control room";identity.text="Simulated city cameras · Committed command audit · Select a resident to filter history"
		control_room.refresh()
	var next_page_key:=str(city_mode)+":"+selected_id+":"+str(tabs.current_tab)+":"+str(decisions.button_pressed)
	if body.text!=text:
		var scroll: float=body.get_v_scroll_bar().value if next_page_key==page_key else 0.0
		body.text=text
		body.get_v_scroll_bar().set_deferred("value",scroll)
	page_key=next_page_key

func _process(delta: float) -> void:
	if not is_open():return
	timer+=delta
	if timer>=.25:timer=0;refresh()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_F5:
		if is_open():close()
		else:open()
		get_viewport().set_input_as_handled()
	elif event.keycode==KEY_F7:open_control_room();get_viewport().set_input_as_handled()
	elif event.keycode==KEY_F6:open_evaluation();get_viewport().set_input_as_handled()
	elif is_open():
		if event.keycode==KEY_ESCAPE:close();get_viewport().set_input_as_handled()
		elif event.keycode==KEY_F3:follow_selected();get_viewport().set_input_as_handled()
		elif event.keycode==KEY_F2:close();bridge.panel.toggle();get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_F1,KEY_F4]:get_viewport().set_input_as_handled()
