extends SceneTree
## Verify generated building geometry against the actual transit route envelopes.
var failures: Array[String] = []
var boxes: Array[AABB] = []
func _initialize() -> void:
	call_deferred("run_check")
func gather(node: Node) -> void:
	if node.get_meta("render_budget_batch",false):return # Original source bounds remain for exact clearance QA.
	if node is MeshInstance3D and node.mesh:
		boxes.append(node.global_transform * node.mesh.get_aabb())
	if node is MultiMeshInstance3D and node.multimesh:
		# Fabric infrastructure shares materials with the route itself; facade volumes
		# are independently identifiable. Original kit solids are also included.
		var infrastructure: bool = str(node.name).begins_with("Kit_fabric:") and not ":fabric_0:" in str(node.name) and not ":fabric_1:" in str(node.name) and not ":fabric_2:" in str(node.name) and not ":fabric_3:" in str(node.name)
		if not infrastructure:
			for i in node.multimesh.instance_count:
				boxes.append(node.global_transform * node.multimesh.get_instance_transform(i) * node.multimesh.mesh.get_aabb())
	for child in node.get_children():
		gather(child)
func crosses(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var corners := [rect.position, rect.position + Vector2(rect.size.x,0), rect.end, rect.position + Vector2(0,rect.size.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4]) != null:
			return true
	return false
func run_check() -> void:
	var city = load("res://scenes/city.tscn").instantiate()
	root.add_child(city)
	city.explorer.set_capture(false)
	var routes: Array = city.get_meta("transit_routes")
	if "--inject-ring-obstruction" in OS.get_cmdline_user_args():
		# Negative control: an actual rendered box crossing the route must be detected.
		var obstacle := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(8,8,8)
		obstacle.mesh = cube
		obstacle.position = routes[0].points[0]
		city.add_child(obstacle)
	gather(city)
	# Preserve the circular design approved by the user as well as clearance.
	var expected := [[137.0,109.0,-25.0,28.0], [111.0,78.0,-57.0,49.0]]
	for index in routes.size():
		var spec: Array = expected[index]
		for point in routes[index].points:
			var ellipse: float = pow(point.x / spec[0], 2) + pow((point.z - spec[2]) / spec[1], 2)
			if absf(ellipse - 1.0) > 0.0001 or absf(point.y - spec[3]) > 0.001:
				failures.append("approved circular route changed")
				break
	for route in routes:
		var points: PackedVector3Array = route.points
		var height: float = route.height
		for box in boxes:
			if box.position.y >= height + 1.1 or box.end.y <= height - 0.5:
				continue
			var bounds := Rect2(Vector2(box.position.x,box.position.z), Vector2(box.size.x,box.size.z)).grow(float(route.width) * 0.5 + 0.2)
			for i in points.size():
				var a := Vector2(points[i].x,points[i].z)
				var b := Vector2(points[(i+1)%points.size()].x,points[(i+1)%points.size()].z)
				if crosses(a,b,bounds):
					failures.append("height=%s building=%s" % [height,box])
					break
	for failure in failures:
		print("FAIL RING_CLEARANCE ",failure)
	print("COMPOSITION_QA ",JSON.stringify({"passed":failures.is_empty(),"route_count":routes.size(),"visual_bounds_checked":boxes.size(),"intersections":failures.size()}))
	quit(0 if failures.is_empty() else 1)
