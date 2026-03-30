extends CanvasLayer

# Spectral HUD Overlay - Reactive Feedback System
# Handles 2D translucent elements and "1-up" style counters.

var _container_top: HBoxContainer
var _container_bottom: HBoxContainer
var _container_left: VBoxContainer
var _container_right: VBoxContainer

var _color_positive = Color(0, 1, 0.5, 0.8) # Glowing Mint
var _color_negative = Color(1, 0, 0.3, 0.8) # Glowing Rose

func _ready():
	add_to_group("hud_overlay") # Required for WebUI._find_hud()
	layer = 100 # High layer to ensure it's on top
	
	# Layout Setup
	var root = Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(root)
	
	# Top (Header)
	_container_top = HBoxContainer.new(); _container_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_container_top.alignment = BoxContainer.ALIGNMENT_CENTER; root.add_child(_container_top)
	_container_top.position.y = 20
	
	# Bottom (Footer)
	_container_bottom = HBoxContainer.new(); _container_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_container_bottom.alignment = BoxContainer.ALIGNMENT_CENTER; root.add_child(_container_bottom)
	_container_bottom.position.y -= 40
	
	# Left/Right (Lateral)
	_container_left = VBoxContainer.new(); _container_left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_container_left.alignment = BoxContainer.ALIGNMENT_CENTER; root.add_child(_container_left)
	_container_left.position.x = 20
	
	_container_right = VBoxContainer.new(); _container_right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_container_right.alignment = BoxContainer.ALIGNMENT_CENTER; root.add_child(_container_right)
	_container_right.position.x -= 120 # Width offset

func show_counter(delta: int, label: String = ""):
	var color = _color_positive if delta > 0 else _color_negative
	var signpatch = "+" if delta > 0 else ""
	
	var pulse = Label.new()
	pulse.text = signpatch + str(delta) + " " + label
	pulse.add_theme_font_size_override("font_size", 32)
	pulse.add_theme_color_override("font_color", color)
	add_child(pulse)
	
	# Position near center but offset
	pulse.position = Vector2(get_viewport().size.x / 2 + randf_range(-100, 100), get_viewport().size.y / 2)
	
	# Animate: Float up and Fade out
	var tween = create_tween()
	tween.tween_property(pulse, "position:y", pulse.position.y - 150, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(pulse, "modulate:a", 0.0, 1.5)
	tween.tween_callback(pulse.queue_free)
	
	# Sound stub
	print("[SFX]: Bring! (Peak Waters Sync: " + str(delta) + ")")

func toggle_widget(id: String, active: bool, type: String = "SQUARE"):
	var target = _container_left # Default
	if type.contains("FOOTER"): target = _container_bottom
	elif type.contains("HEADER"): target = _container_top
	elif type.contains("RIGHT"): target = _container_right
	
	var existing = target.get_node_or_null(id)
	if active:
		if existing: return
		var p = PanelContainer.new(); p.name = id; target.add_child(p)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.05, 0.08, 0.15) # ULTRA GHOST ALPHA
		style.border_width_all = 1; style.border_color = Color(0, 0.9, 1.0, 0.05)
		p.add_theme_stylebox_override("panel", style)
		
		var l = Label.new(); l.text = id; p.add_child(l)
		l.add_theme_color_override("font_color", Color(0, 0.9, 1.0, 0.7)) # Cyan Glow
		l.add_theme_font_size_override("font_size", 14)
	else:
		if existing: existing.queue_free()

var _live_tick: float = 0.0

func _process(delta):
	_live_tick += delta
	if _live_tick < 1.5: return # Update every 1.5 sec — low overhead
	_live_tick = 0.0
	
	var mem_mb = snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1)
	var uptime_s = int(Time.get_ticks_msec() / 1000)
	var fps = Engine.get_frames_per_second()
	# CPU: Godot doesn't expose native CPU%, use render time as proxy
	var cpu_ms = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01)
	
	_update_widget_value("CPU_LOAD",  "%.2f ms/frame" % cpu_ms)
	_update_widget_value("MEM_USAGE", "%.1f MB" % mem_mb)
	_update_widget_value("UPTIME",    "%02d:%02d" % [uptime_s / 60, uptime_s % 60])
	_update_widget_value("IO_FLOW",   "%d FPS" % fps)
	_update_widget_value("UPLOAD_FLUX", "%.1f Kbps" % randf_range(10, 50))
	_update_widget_value("NET_SYNC", "STABLE")

func _update_widget_value(id: String, value: String):
	# Search all containers for a panel named `id`
	for container in [_container_top, _container_bottom, _container_left, _container_right]:
		if not container: continue
		var p = container.get_node_or_null(id)
		if p:
			var l = p.get_child(0) as Label
			if l: l.text = id + ": " + value

func set_resonance(score: float):
	# Call from SkeletonKey / soul_updated signal
	var pct = int(score * 100)
	_update_widget_value("RESONANCE", str(pct) + "%")
	if pct >= 80:
		show_counter(5, "RESONANCE") # Peak waters
	elif pct <= 30:
		show_counter(-3, "RESONANCE") # Out of peak
