extends SceneTree
## Offline, fixed-frame lighting study; no simulation/save mutation.
const FPS:=24
const DAY_FRAMES:=1440
var city: Node3D
var caption: Label
var progress: ProgressBar
var frame:=0
var samples: Array=[]
var start_frame:=0
var evidence:=""
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):evidence=arg.trim_prefix("--evidence-dir=")
	city=load("res://scenes/city.tscn").instantiate();root.add_child(city);city.hud.hide()
	city.explorer.set_capture(false)
	var camera:=Camera3D.new();camera.far=1800;camera.position=Vector3(64,112,185);city.add_child(camera)
	camera.look_at(Vector3(0,59,-62));camera.make_current()
	var layer:=CanvasLayer.new();layer.layer=30;root.add_child(layer)
	var panel:=PanelContainer.new();panel.position=Vector2(24,14);panel.custom_minimum_size=Vector2(1392,0);layer.add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.015,.035,.06,.94);style.set_content_margin_all(14);panel.add_theme_stylebox_override("panel",style)
	var content:=VBoxContainer.new();panel.add_child(content)
	caption=Label.new();caption.add_theme_font_size_override("font_size",25);content.add_child(caption)
	var detail:=Label.new();detail.text="24-HOUR LIGHTING STUDY · 24 hours in 60 seconds · City layout unchanged · No gameplay time or save advanced"
	detail.add_theme_font_size_override("font_size",16);content.add_child(detail)
	progress=ProgressBar.new();progress.show_percentage=false;progress.max_value=24;progress.custom_minimum_size.y=6;content.add_child(progress)
	apply_hour(6)
	# Two seconds for temporal accumulation before the exported day begins.
	for i in range(48):await process_frame
	start_frame=Engine.get_frames_drawn()
	for i in range(DAY_FRAMES+1):
		frame=i
		var hour:=6.0+24.0*float(i)/DAY_FRAMES
		apply_hour(hour)
		await process_frame
		if i%180==0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(evidence+"/hour-%02d.png"%int(fmod(hour,24)))
			samples.append({"frame":i,"hour":fmod(hour,24),"energy":city.get_node("TwilightKey").light_energy,"zenith":str(city.world_environment.environment.sky.sky_material.get_shader_parameter("zenith_color"))})
	var out:=FileAccess.open(evidence+"/capture.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"start_frame":start_frame,"day_frames":DAY_FRAMES,"fps":FPS,"samples":samples,"scope":"Offline fixed-frame lighting review from 06:00 to next-day 06:00. Population/time simulation absent; no saves/journals opened. Normal game sky retains blue-hour defaults."},"  "));out.close()
	print("DAY_CYCLE_VIDEO failures=0 frames=",DAY_FRAMES," start_frame=",start_frame)
	quit()
func apply_hour(hour: float) -> void:
	var h:=fmod(hour,24)
	var elevation:=sin((h-6)*TAU/24)
	var daylight:=smoothstep(-.10,.25,elevation)
	var dusk:=exp(-pow(elevation/.20,2))
	var mat: ShaderMaterial=city.world_environment.environment.sky.sky_material
	var zenith:=Color("030916").lerp(Color("167bd0"),daylight)
	var horizon:=Color("101d37").lerp(Color("89c9ed"),daylight).lerp(Color("e89a68"),dusk*.6)
	mat.set_shader_parameter("zenith_color",Vector3(zenith.r,zenith.g,zenith.b))
	mat.set_shader_parameter("horizon_color",Vector3(horizon.r,horizon.g,horizon.b))
	var glow:=Color("172039").lerp(Color("eeb783"),dusk)
	mat.set_shader_parameter("horizon_afterglow",Vector3(glow.r,glow.g,glow.b))
	mat.set_shader_parameter("moon_visibility",1-daylight*.97)
	mat.set_shader_parameter("star_visibility",1-daylight)
	var env: Environment=city.world_environment.environment
	env.ambient_light_energy=lerpf(.24,.9,daylight)
	env.fog_light_color=Color("1c2e4d").lerp(Color("8fbace"),daylight)
	env.volumetric_fog_albedo=env.fog_light_color
	var key: DirectionalLight3D=city.get_node("TwilightKey")
	key.light_energy=lerpf(.12,1.65,daylight)
	key.light_color=Color("9eb9df").lerp(Color("fff2d2"),daylight).lerp(Color("ffc184"),dusk*.65)
	# Southern solar arc stays separate from Neon Providence's northwest sky position.
	var direction:=Vector3(cos((h-6)*TAU/24),maxf(.07,elevation),.4).normalized()
	key.look_at(key.global_position-direction,Vector3.UP)
	city.get_node("SoftSkyFill").light_energy=lerpf(.14,.45,daylight)
	var stage:="DAY"
	if h<6 or h>=20:stage="NIGHT"
	elif h<8:stage="MORNING"
	elif h>=17:stage="SUNSET / DUSK"
	caption.text="NEON PROVIDENCE · %02d:%02d · %s"%[int(h),int((h-floor(h))*60),stage]
	progress.value=hour-6
