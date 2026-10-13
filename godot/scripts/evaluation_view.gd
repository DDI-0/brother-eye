extends RefCounted
## Presentation of authoritative rule findings. Never infers findings locally.
static func matches(report: Dictionary, world: Dictionary) -> bool:
	var source: Dictionary=report.get("source",{})
	if report.get("v",0)!=1 or source.is_empty():return false
	for key in ["world_id","revision","tick","clock_seconds","paused"]:
		if source.get(key)!=world.get(key):return false
	return true

static func page(report: Dictionary, world: Dictionary, id: String="") -> String:
	if not matches(report,world):return "Assessment unavailable for this snapshot.\nWaiting for a matching evaluation from the city service."
	var summary: Dictionary=report.summary
	var lines: PackedStringArray=[]
	if id.is_empty():
		lines.append("CITY EVALUATION\n%d residents · %d with flagged conditions\nFindings: %d urgent · %d attention · %d notices"%[summary.population,summary.residents_flagged,summary.priorities.urgent,summary.priorities.attention,summary.priorities.notice])
		var activities: PackedStringArray=[]
		for key in summary.activities:activities.append(str(key).capitalize()+": "+str(int(summary.activities[key])))
		lines.append("RECORDED ACTIVITIES\n"+" · ".join(activities))
		if not summary.mean_needs.is_empty():
			var n: Dictionary=summary.mean_needs
			lines.append("POPULATION AVERAGES\nHunger %.1f%% · Energy %.1f%% · Social need %.1f%%"%[n.hunger,n.energy,n.social])
	else:lines.append("RESIDENT ASSESSMENT")
	if report.coverage!="complete":lines.append("Incomplete observation coverage. An all-clear conclusion is unavailable.")
	var count:=0
	for finding in report.findings:
		if not id.is_empty() and finding.citizen_id!=id:continue
		count+=1
		lines.append("%s · %s%s\n%s\nResponse: %s\nSuggested next step: %s"%[str(finding.priority).to_upper(),finding.title," · "+str(finding.name) if id.is_empty() else "",finding.explanation,str(finding.response).replace("_"," "),finding.recommendation])
	if count==0 and report.coverage=="complete":lines.append("No conditions flagged by the current rules. This assessment covers recorded needs and reported navigation waits.")
	lines.append("HOW THIS IS EVALUATED\nAttention: hunger >70%, energy <20%, social need >75%.\nUrgent: hunger ≥90%, energy ≤10%, social need ≥95%.\nRoute waits require attention; crowd waits are notices.\nStanding idle at an arrived destination is expected. A single snapshot cannot establish a prolonged stall.\n\nThese are rule-based observations and suggestions. Evaluation does not issue commands.")
	return "\n\n".join(lines)
