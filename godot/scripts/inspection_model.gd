extends RefCounted
## Read-only projection of a confirmed world snapshot. No decisions or inferred memories.
const VERSION := 1
static func roster(world: Dictionary, query: String="", kind: String="all") -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var needle:=query.strip_edges().to_lower()
	for c in world.get("citizens",[]):
		if kind!="all" and c.kind!=kind:continue
		if not needle.is_empty() and not (str(c.name)+" "+str(c.role)+" "+str(c.id)).to_lower().contains(needle):continue
		result.append({"id":c.id,"name":c.name,"role":c.role,"kind":c.kind})
	return result

static func inspect(world: Dictionary, citizen_id: String) -> Dictionary:
	for c in world.get("citizens",[]):
		if c.id==citizen_id:
			return {"v":VERSION,"world_id":world.get("world_id",""),"revision":world.get("revision",0),
				"tick":world.get("tick",0),"clock_seconds":world.get("clock_seconds",0),
				"paused":world.get("paused",true),"citizen":c.duplicate(true),
				"resident_names":resident_names(world),"agent_history":world.get("agent_history",[]).filter(func(event):return event.agent_id==citizen_id).duplicate(true)}
	return {}

static func resident_names(world: Dictionary) -> Dictionary:
	var names: Dictionary={}
	for person in world.get("citizens",[]):names[person.id]=person.name
	return names

static func city_time(seconds: float) -> String:
	var t:=int(seconds)+8*3600
	return "Day %03d · %02d:%02d:%02d"%[t/86400+1,(t/3600)%24,(t/60)%60,t%60]

static func position_text(p: Array) -> String:
	return "%.2f, %.2f, %.2f m"%[p[0],p[1],p[2]]

static func page(view: Dictionary, tab: int, decisions_only: bool=false) -> String:
	if view.is_empty():return "Select a resident to inspect."
	var c: Dictionary=view.citizen
	if tab==0:
		var goal: Dictionary=c.goal
		var explanation:="Scheduled destination" if goal.reason=="schedule" else "Needs take priority over the schedule"
		if goal.reason=="ideology":explanation=c.exceptional.decision.reason if c.exceptional.decision is Dictionary else "Local ideological choice"
		if goal.reason=="intervention":explanation="Brother Eye destination override takes priority until explicit release"
		var text:="CURRENT ACTIVITY\n%s · %s\n\nDESTINATION\n%s\n%s\nAssigned %s\n\nDECISION BASIS\n%s\nLast destination decision: %s\n\nLAST CONFIRMED POSITION\n%s\nHeading %.1f° · Movement report %d\n\nIDENTITY\n%s"%[str(c.activity).capitalize(),c.navigation,c.known_places.get(goal.place,{"name":"Local meeting"}).name,position_text(goal.position),city_time(goal.started_at),explanation,city_time(c.last_decision_at),position_text(c.position),rad_to_deg(c.yaw),c.motion_seq,c.id]
		if c.kind=="exceptional":
			var e: Dictionary=c.exceptional
			text="EXCEPTIONAL AGENT · FOUNDATION ROUTINES ONLY\nIdeological decisions and learning are not implemented yet.\n\nIMMUTABLE CORE\n%s\n\nEXPERIENCE & RELATIONSHIPS\nObservations: %d / 16 · Relationships: %d / 8 · Project: none\n\n"%[e.core,e.observations.size(),e.relationships.size()]+text
			if e.behavior_stage in ["arbiter","attendant","martyr","sovereign"]:
				text=text.replace("EXCEPTIONAL AGENT · FOUNDATION ROUTINES ONLY\nIdeological decisions and learning are not implemented yet.","%s · LOCAL %s\nLocal proximity sensing: 8 m, vertical ≤2 m; not optical line of sight."%[str(e.behavior_stage).to_upper(),"ASSISTANCE" if e.behavior_stage=="arbiter" else "POLICY"])
				text+="\n\nVERIFIED INFORMATION · %d / 16"%e.information.size()
				for target in e.information:
					var fact: Dictionary=e.information[target]
					text+="\n%s · social %.1f · verified %s"%[view.resident_names.get(target,target),fact.social,city_time(fact.at)]
				if e.project is Dictionary:
					text=text.replace("Project: none","Project: "+e.project.status)
					text+="\n\nCIVIC PROJECT\n%s · %s · recorded outcomes %d / %d"%[e.project.id,str(e.project.status).to_upper(),e.project.outcomes.size(),e.project.request_ids.size()]
					if e.project.partner_id!=null:text+="\nVoluntary partner: "+str(view.resident_names.get(e.project.partner_id,e.project.partner_id))
				if e.action is Dictionary:
					text+="\n\nCURRENT ACTION\n%s · physical state %s · dwell %.1f / %d simulated seconds"%[str(e.action.kind).to_upper(),c.navigation,e.action.elapsed,15 if e.action.kind=="observe" else 5]
				if e.decision is Dictionary:
					text+="\n\nLAST CHOICE\n"+e.decision.reason
					for candidate in e.decision.candidates:
						text+="\n%s · observed social %.1f · request %s · evidence %s"%[view.resident_names.get(candidate.subject_id,candidate.subject_id),candidate.severity,candidate.request_id,candidate.evidence_id]
				text+="\n\nLOCAL EVIDENCE · expires after 600 simulated seconds"
				for obs in e.observations:
					text+="\n%s · social %.1f · age %.1f s · %s"%[view.resident_names.get(obs.subject_id,obs.subject_id),obs.social,view.clock_seconds-obs.at,obs.source]
				text+="\n\nRECENT OUTCOMES · no effect until physical completion"
				for event in view.get("agent_history",[]).slice(-6):
					text+="\n%s · %s"%[str(event.outcome).to_upper(),event.detail]
			for target in e.relationships:
				var relation: Dictionary=e.relationships[target]
				var name: String=view.get("resident_names",{}).get(target,target)
				text+="\nKnown person: %s · trust %d · companion %s"%[name,relation.trust,str(relation.companion)]
		return text
	if tab==1:
		var lines: PackedStringArray=["LOCAL KNOWLEDGE · %d PLACES\nOnly places recorded for this resident are listed."%c.known_places.size()]
		for key in c.known_places:
			var place: Dictionary=c.known_places[key]
			lines.append("%s%s\n%s\n%s"%[str(key).replace("_"," ").capitalize()," · CURRENT DESTINATION" if key==c.goal.place else "",place.name,position_text(place.position)])
		return "\n\n".join(lines)
	if tab==2:
		var lines: PackedStringArray=["DAILY SCHEDULE\nCity time: "+city_time(view.clock_seconds)]
		for entry in c.schedule:
			lines.append("%02d:00   %s"%[entry.hour,c.known_places[entry.place].name])
		if c.kind=="police":lines.append("During work hours, patrol destinations rotate every ten simulated minutes.")
		lines.append("Needs can interrupt the schedule unless a Brother Eye override is held. Recovery begins after physical arrival.")
		return "\n\n".join(lines)
	var lines: PackedStringArray=["RECORDED HISTORY · NEWEST FIRST\nUp to 16 recent memories are retained per resident."]
	var found:=false
	for i in range(c.memory.size()-1,-1,-1):
		var entry: Dictionary=c.memory[i]
		if decisions_only and entry.kind!="decision":continue
		found=true
		lines.append("%s · %s\n%s"%[city_time(entry.at),str(entry.kind).to_upper(),entry.detail])
	if not found:lines.append("No recorded decisions yet." if decisions_only else "No recorded memories yet.")
	return "\n\n".join(lines)
