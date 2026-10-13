extends SceneTree
const Evaluation=preload("res://scripts/evaluation_view.gd")
var city: Node3D
var bridge: Node
var pop: Node3D
var inspector: CanvasLayer
var failures: Array[String]=[]
var capture:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func idle() -> bool:return bridge.connected and bridge.restored and pop.restored and bridge.pending.is_empty()
func until(predicate: Callable,timeout:=25.0) -> bool:
	var end:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false
func shot(name: String) -> void:
	if not capture:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../docs/previews/stage4b/"+name+".png")
func finding(id: String,code: String) -> Dictionary:
	for f in bridge.assessment.get("findings",[]):
		if f.citizen_id==id and f.code==code:return f
	return {}
func run() -> void:
	capture="--capture-evaluation" in OS.get_cmdline_user_args()
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);bridge=city.simulation;pop=city.population;inspector=city.inspector
	check(await until(func():return idle() and pop.navigation.ready_for_paths),"live city and evaluation restore")
	if not idle():quit(1);return
	bridge.last_view=bridge.now()+3600
	var alex: String=bridge.world.citizens[0].id
	check(inspector.is_open() and inspector.city_mode,"evaluation launcher opens city assessment")
	check(Evaluation.matches(bridge.assessment,bridge.world),"assessment is bound to the exact authoritative world revision and tick")
	check(bridge.assessment.summary.population==34 and bridge.assessment.engine=="deterministic_rules","city totals and reasoning engine are explicit")
	var f:=finding(alex,"high_hunger")
	check(not f.is_empty() and f.priority=="urgent" and f.evidence.value==92,"urgent finding includes actual need value and rule evidence")
	check(f.response=="travelling_to_recovery","assessment recognizes the existing recovery destination")
	var before: Dictionary=bridge.world.duplicate(true)
	inspector.refresh();await shot("city-evaluation")
	inspector.kind.select(3);inspector.refresh()
	check(inspector.rows.size()==bridge.assessment.summary.residents_flagged,"flagged filter selects distinct residents rather than finding count")
	inspector.inspect_priority()
	check(not inspector.city_mode and inspector.tabs.current_tab==4 and inspector.selected_id==alex,"highest-priority finding opens the correct resident assessment")
	check(inspector.body.text.contains("92.0%") and inspector.body.text.contains("Monitor arrival"),"resident assessment explains evidence and suggested next step")
	await shot("resident-assessment")
	check(bridge.world==before and bridge.pending.is_empty(),"evaluation and priority selection do not modify simulation state")
	var report: Dictionary=bridge.assessment
	bridge.assessment=report.duplicate(true);bridge.assessment.source.tick=-1;inspector.refresh()
	check(inspector.body.text.contains("unavailable"),"mismatched report cannot be shown as current evaluation")
	bridge.assessment=report
	bridge.connected=false;inspector.open_evaluation();inspector.refresh()
	check(inspector.status.text.contains("LAST KNOWN") and inspector.priority_button.disabled,"offline evaluation is marked last known and priority action disabled")
	bridge.connected=true;inspector.refresh()
	bridge.set_clock(false,60)
	check(await until(func():return bridge.world.citizens[0].activity=="eating"),"resident physically arrives and starts recovery")
	check(await until(func():return finding(alex,"high_hunger").get("response")=="recovering"),"live evaluation updates to confirmed recovery")
	bridge.set_clock(true,60)
	check(await until(func():return idle() and bridge.world.paused),"city pause acknowledged")
	inspector.select_person(alex);inspector.tabs.current_tab=4;inspector.refresh();await shot("recovery-assessment")
	check(inspector.body.text.contains("Recovery is active") and inspector.body.text.contains("Allow recovery"),"recovery finding recommends monitoring existing care")
	print("STAGE4B_CHECK failures=",failures.size())
	if failures.is_empty():bridge.request_quit()
	else:quit(1)
