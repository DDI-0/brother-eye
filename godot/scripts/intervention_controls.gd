extends VBoxContainer
## Explicit actions only: rendering inspection/evaluation never sends commands.
var inspector: CanvasLayer
var bridge: Node
var destination: OptionButton
var reason: LineEdit
var assign_button: Button
var release_button: Button
var result: Label
var place_keys: Array[String]=[]
var target_id:=""
var citizen: Dictionary={}

func setup(owner_inspector: CanvasLayer, owner_bridge: Node) -> void:
	inspector=owner_inspector;bridge=owner_bridge
	var warning:=Label.new();warning.text="A destination override takes priority over needs and schedule until you release it, even after arrival.";warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;warning.modulate=Color("edbf78");add_child(warning)
	var row:=HBoxContainer.new();add_child(row)
	destination=OptionButton.new();destination.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(destination)
	assign_button=inspector.button(row,"Issue destination override",func():issue("assign_destination"))
	release_button=inspector.button(row,"Release to autonomy",func():issue("release"))
	reason=LineEdit.new();reason.placeholder_text="Reason for this command (required)";reason.max_length=240;add_child(reason)
	reason.text_changed.connect(func(_text):refresh_buttons())
	result=Label.new();result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(result)

func has_pending() -> bool:
	for request in bridge.pending:
		if request.type=="intervene" and request.payload.get("citizen_id")==target_id:return true
	return false

func refresh_buttons() -> void:
	var live: bool=bridge.connected and bridge.restored and not bridge.quitting and not bridge.fatal
	var disabled: bool=not live or citizen.is_empty() or has_pending() or reason.text.strip_edges().is_empty()
	assign_button.disabled=disabled or place_keys.is_empty()
	release_button.disabled=disabled or citizen.get("intervention")==null

func refresh(record: Dictionary) -> void:
	citizen=record
	if str(record.get("id",""))!=target_id:
		target_id=str(record.get("id",""));reason.text="";destination.clear();place_keys.clear()
		for key in record.get("known_places",{}):
			place_keys.append(key);destination.add_item(record.known_places[key].name)
	refresh_buttons()
	var outcome: Dictionary=bridge.intervention_result
	if has_pending():result.text="PENDING · Waiting for durable acknowledgement."
	elif outcome.get("citizen_id")==target_id:result.text=("RECORDED RESULT · " if outcome.get("recorded",false) else "")+str(outcome.outcome).to_upper()+" · "+str(outcome.message)
	else:result.text="No command pending. Review the destination and enter a reason before issuing."

func issue(action: String) -> void:
	refresh_buttons()
	if (action=="release" and release_button.disabled) or (action=="assign_destination" and assign_button.disabled):return
	var active = citizen.get("intervention")
	var payload: Dictionary={"world_id":bridge.world.world_id,"citizen_id":target_id,
		"expected_goal_id":citizen.goal.id,"expected_intervention_id":active.id if active is Dictionary else null,
		"action":action,"place":place_keys[destination.selected] if action=="assign_destination" else null,"reason":reason.text.strip_edges()}
	bridge.queue_command("intervene",payload)
	refresh(citizen)

func page(world: Dictionary, record: Dictionary) -> String:
	if record.is_empty():return "Waiting for a confirmed resident."
	var text:="DESTINATION AUTHORITY\n"
	if record.kind=="exceptional":text+="Immediate travel only: immutable ideology and relationships cannot be edited. Each agent resumes their own local policy on release; held overrides take priority.\n\n"
	var active = record.get("intervention")
	if active is Dictionary:
		text+="%s · %s\nReason: %s\nOverride ID: %s\nHeld until explicit release.\n"%[str(active.status).replace("_"," ").to_upper(),record.known_places[active.place].name,active.reason,active.id]
	else:text+="AUTONOMOUS · Needs and daily routine choose destinations.\n"
	text+="\nRECENT COMMAND & TRAVEL HISTORY\n"
	var found:=false
	var history: Array=world.get("intervention_history",[]).duplicate();history.reverse()
	for event in history:
		if event.citizen_id!=record.id:continue
		found=true
		text+="\n%s · %s · %s\n%s\nReason: %s\nCommand: %s\n"%[preload("res://scripts/inspection_model.gd").city_time(event.at),str(event.action).replace("_"," "),str(event.outcome).to_upper(),event.message,event.reason,event.command_id]
	if not found:text+="No recorded interventions for this resident."
	return text
