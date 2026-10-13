extends VBoxContainer
## One selected, throttled viewport of the actual city; queries never mutate the world.
const Model=preload("res://scripts/inspection_model.gd")
const FEEDS=[
	["Promenade / north",Vector3(15.5,5.8,42.15),Vector3(18,1,20)],
	["Market promenade",Vector3(15.5,5.8,-9.85),Vector3(18,1,-22)],
	["Uplink plaza",Vector3(-15.5,5.8,-35.85),Vector3(10,1,-40)],
	["Authority tower / district",Vector3(0,140,-78),Vector3(0,0,65)]]
var inspector: CanvasLayer
var bridge: Node
var viewport: SubViewport
var camera: Camera3D
var feed: OptionButton
var feed_status: Label
var feed_image: TextureRect
var scope: OptionButton
var list: ItemList
var details: RichTextLabel
var history_status: Label
var retention_notice: Label
var refresh_button: Button
var older_button: Button
var entries: Array=[]
var request_id:=""
var request_at:=0.0
var pending_append:=false
var cursor: Dictionary={}
var has_more:=false
var selected_event:=""
var last_target:=""
var feed_elapsed:=0.0
var ui_elapsed:=0.0
var history_error:=""
var render_requests:=0
var feed_ready:=false
var last_frame_tick:=-1
var last_history_stamp:=""
var loaded_world_id:=""

func setup(owner_inspector: CanvasLayer) -> void:
	inspector=owner_inspector;bridge=inspector.bridge;size_flags_vertical=Control.SIZE_EXPAND_FILL
	var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",16);add_child(row)
	var left:=VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(left)
	feed=OptionButton.new()
	for item in FEEDS:feed.add_item(item[0])
	left.add_child(feed);feed.item_selected.connect(func(index):set_feed(index))
	feed_image=TextureRect.new();feed_image.custom_minimum_size=Vector2(384,216);feed_image.size_flags_vertical=Control.SIZE_EXPAND_FILL
	feed_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;feed_image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;left.add_child(feed_image)
	feed_status=Label.new();feed_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;left.add_child(feed_status)
	viewport=SubViewport.new();viewport.size=Vector2i(640,360);viewport.world_3d=inspector.city.get_world_3d()
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;viewport.handle_input_locally=false;add_child(viewport)
	camera=Camera3D.new();camera.fov=65;camera.far=1800;viewport.add_child(camera);camera.make_current()
	feed_image.texture=viewport.get_texture();set_feed(0)
	var right:=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.custom_minimum_size.x=370;row.add_child(right)
	var actions:=HBoxContainer.new();right.add_child(actions)
	scope=OptionButton.new();scope.add_item("All command events");scope.add_item("Selected resident");actions.add_child(scope)
	scope.item_selected.connect(func(_index):load_history(false))
	refresh_button=inspector.button(actions,"Refresh",func():load_history(false))
	older_button=inspector.button(actions,"Older",func():load_history(true))
	history_status=Label.new();history_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;right.add_child(history_status)
	retention_notice=Label.new();retention_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;right.add_child(retention_notice)
	list=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;list.custom_minimum_size.y=180;right.add_child(list)
	list.item_selected.connect(func(index):selected_event=entries[index].id;show_details())
	details=RichTextLabel.new();details.selection_enabled=true;details.size_flags_vertical=Control.SIZE_EXPAND_FILL;details.custom_minimum_size.y=140;add_child(details)
	bridge.history_received.connect(receive_history)

func live() -> bool:return bridge.connected and bridge.restored and not bridge.quitting and not bridge.fatal
func target() -> String:return inspector.selected_id if scope.selected==1 else ""
func set_feed(index: int) -> void:
	camera.position=FEEDS[index][1];camera.look_at(FEEDS[index][2]);feed_elapsed=1.0;feed_ready=false
	if is_visible_in_tree():inspector.city.set_meta("detail_feed_position",camera.global_position)

func activate() -> void:
	show();inspector.city.set_meta("detail_feed_position",camera.global_position);load_history(false)
func suspend() -> void:
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	if inspector.city.has_meta("detail_feed_position"):inspector.city.remove_meta("detail_feed_position")

func load_history(append: bool) -> void:
	if not live():return
	pending_append=append;last_target=target();request_at=bridge.now();history_error=""
	request_id=bridge.query_history(last_target,cursor if append else {})
	history_status.text="Loading committed audit…"

func receive_history(payload: Dictionary, id: String) -> void:
	if id!=request_id:return
	request_id=""
	loaded_world_id=str(bridge.world.get("world_id",""))
	if payload.has("error"):
		history_error="History unavailable: "+str(payload.error);history_status.text=history_error;return
	if payload.get("world_id")!=bridge.world.get("world_id") or payload.get("citizen_id")!=target():return
	retention_notice.text="Older audit entries were pruned; showing retained history." if int(payload.get("retention",{}).get("pruned_audit_entries",0))>0 else ""
	var kept_id:=selected_event
	if not pending_append:entries.clear()
	var known: Dictionary={}
	for event in entries:known[event.id]=true
	for event in payload.entries:
		if not known.has(event.id):entries.append(event);known[event.id]=true
	cursor=payload.next_cursor if payload.next_cursor is Dictionary else {};has_more=payload.has_more
	list.clear()
	for event in entries:list.add_item(str(event.outcome).to_upper()+" · "+resident_name(event.citizen_id)+" · "+str(event.action).replace("_"," "))
	selected_event=kept_id
	var index: int=entries.find_custom(func(event):return event.id==selected_event)
	if index<0 and not entries.is_empty():index=0;selected_event=entries[0].id
	if index>=0:list.select(index)
	last_history_stamp=JSON.stringify(bridge.world.get("intervention_history",[]))
	history_status.text="%d committed events loaded%s"%[entries.size()," · older available" if has_more else " · end of history"]
	show_details()

func resident_name(id: String) -> String:
	for person in bridge.world.get("citizens",[]):
		if person.id==id:return person.name
	return id if not id.is_empty() else "Unknown target"
func state_text(value) -> String:
	if not value is Dictionary:return "None"
	var goal: Dictionary=value.get("goal",{})
	var active = value.get("intervention")
	return str(goal.get("place","—"))+" · "+str(goal.get("reason","—"))+" · "+(str(active.get("status","—")) if active is Dictionary else "autonomous")
func show_details() -> void:
	if entries.is_empty():details.text="No committed intervention events in this view. Pending commands are not completed actions.";return
	for event in entries:
		if event.id!=selected_event:continue
		details.text="%s · %s · %s\n%s · Actor: %s\n%s\nReason: %s\nBefore: %s\nAfter: %s\nCommand: %s\nAudit event: %s · record %d/%d"%[resident_name(event.citizen_id),str(event.action).replace("_"," "),str(event.outcome).to_upper(),Model.city_time(event.at),event.actor,event.message,event.reason,state_text(event.before),state_text(event.after),event.command_id,event.id,event.event_seq,event.event_index]
		return

func refresh() -> void:
	feed.disabled=not live();refresh_button.disabled=not live();older_button.disabled=not live() or not has_more or not request_id.is_empty()
	if not request_id.is_empty() and bridge.now()-request_at>4:
		bridge.queries.erase(request_id);request_id="";history_error="History query timed out. Refresh to retry.";history_status.text=history_error
	if live() and request_id.is_empty() and (loaded_world_id!=str(bridge.world.get("world_id","")) or (scope.selected==1 and last_target!=target())):load_history(false)
	if not live():
		feed_status.text="LAST FRAME · CONNECTION UNAVAILABLE" if feed_ready else "FEED UNAVAILABLE · CONNECTION UNAVAILABLE"
		history_status.text="LAST KNOWN HISTORY · Connection unavailable";suspend()
	else:
		feed_status.text=("PAUSED CITY" if bridge.world.get("paused",true) else "LIVE SIMULATED FEED")+" · 640 × 360 · up to 10 updates/s\nActual scene · last confirmed tick %d · no recording"%last_frame_tick
		if request_id.is_empty():
			if not history_error.is_empty():history_status.text=history_error
			elif last_history_stamp!=JSON.stringify(bridge.world.get("intervention_history",[])):history_status.text="%d events loaded · new events available — Refresh"%entries.size()
			else:history_status.text="%d committed events loaded%s"%[entries.size()," · older available" if has_more else " · end of history"]

func _process(delta: float) -> void:
	if not is_visible_in_tree():suspend();return
	ui_elapsed+=delta
	if ui_elapsed>=.25:ui_elapsed=0;refresh()
	if not live():suspend();return
	feed_elapsed+=delta
	if live() and feed_elapsed>=.1:
		inspector.city.set_meta("detail_feed_position",camera.global_position)
		feed_elapsed=0;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;render_requests+=1
		feed_ready=true;last_frame_tick=int(bridge.world.get("tick",0))
