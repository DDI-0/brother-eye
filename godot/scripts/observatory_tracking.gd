extends Node3D
## Deterministic presentation driven by the saved city clock, never wall-clock time.
var telescope: Node3D
var hour := 8.0
func set_hour(value: float) -> void:
	hour = fposmod(value,24.0)
	rotation.y = fposmod((hour-8.0)/24.0,1.0)*TAU
	if telescope != null:
		var altitude := deg_to_rad(45.0+20.0*sin((hour-6.0)*TAU/24.0))
		telescope.rotation.x = atan2(.67,.74)-altitude
func _process(_delta: float) -> void:
	var city := get_parent()
	var bridge: Node = city.simulation
	if bridge != null and bridge.connected and bridge.restored and not bridge.world.is_empty():
		# The HUD defines day one as 08:00 plus the authoritative elapsed seconds.
		set_hour(8.0+float(bridge.world.get("clock_seconds",0.0))/3600.0)
