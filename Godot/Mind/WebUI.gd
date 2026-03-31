extends Control

signal avatar_selected(name: String)
signal soul_updated(dna: Dictionary)
signal web_slider_changed(trait_name: String, value: float)
signal brain_selected(model_name: String)
signal low_vram_toggled()
signal vision_sensing_requested()
signal files_requested()
signal archive_requested()
signal dream_requested()
signal system_check_requested()
signal soul_verification_requested()
signal user_certification_requested()

var current_tab = "NEURAL"
@onready var chat_log: RichTextLabel = null
@onready var input_display: Label = null
var _main_vbox: VBoxContainer = null
var _content_stack: Control = null
var _floating_panel: PanelContainer = null
var _submenu_container: VBoxContainer = null
var _active_hub_btn: Button = null
var _audio: AudioStreamPlayer = null
var _log_display: RichTextLabel = null
var _vitals_data: Dictionary = {}

var _log_lines: Array = ["[color=green]OS_LOAD_OK[/color]", "[color=cyan]VRAM: 8GB ACTIVE[/color]", "[color=white]NEURAL_FLUX: STABLE[/color]"]
const KEY_GAP := 10.0

var _hubs = {
	"MIND": ["PSYCHE", "SOUL", "BRAINS", "MEMORY", "EMOTIONS"],
	"BODY": ["VESSEL", "AGENCY", "VITALS", "SENTRY"],
	"MANIFEST": ["IMAGEN", "VIDGEN", "MEDIA"],
	"CORE": ["CHAT", "LOGS", "SETTINGS", "FILES"]
}

var _traits = [
	"extrovert", "intellectual", "logic", "detail", "faithful", "sexual", 
	"experimental", "wise", "openminded", "honest", "forgiving", "feminine", 
	"dominant", "progressive", "sloppy", "greedy", "homonormative"
]

func _ready():
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	
	if LogMaster:
		LogMaster.log_added.connect(_on_log_added)
	
	# --- ROOT FRAME: Full Viewport Fill ---
	var root_margin = MarginContainer.new()
	root_margin.set_anchors_preset(PRESET_FULL_RECT)
	add_child(root_margin)
	
	root_margin.add_theme_constant_override("margin_left", 8)
	root_margin.add_theme_constant_override("margin_right", 8)
	root_margin.add_theme_constant_override("margin_top", 8)
	root_margin.add_theme_constant_override("margin_bottom", 8)
	
	_main_vbox = VBoxContainer.new()
	_main_vbox.set_anchors_preset(PRESET_FULL_RECT)
	root_margin.add_child(_main_vbox)
	_main_vbox.add_theme_constant_override("separation", 8)

	# --- TOP RIBBON ---
	var ribbon_bg = PanelContainer.new()
	_main_vbox.add_child(ribbon_bg)
	var style_ribbon = StyleBoxFlat.new()
	style_ribbon.bg_color = Color(0.95, 0.95, 1.0, 0.25) # Light Ghost White (Glassmorphism)
	style_ribbon.border_width_bottom = 2; style_ribbon.border_color = Color(1, 1, 1, 0.5)
	style_ribbon.set_corner_radius_all(15)
	ribbon_bg.add_theme_stylebox_override("panel", style_ribbon)
	
	var ribbon_h_box = HBoxContainer.new()
	ribbon_bg.add_child(ribbon_h_box)
	ribbon_h_box.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var style_btn = StyleBoxFlat.new()
	style_btn.bg_color = Color(0.12, 0.12, 0.12, 0.9)
	style_btn.set_corner_radius_all(5)
	style_btn.content_margin_left = 10
	style_btn.content_margin_right = 10
	
	for hub in ["MIND", "BODY", "MANIFEST", "CORE"]:
		var btn = Button.new()
		btn.text = hub
		btn.custom_minimum_size.y = 50
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		ribbon_h_box.add_child(btn)
		btn.add_theme_stylebox_override("normal", style_btn)
		btn.pressed.connect(_on_ribbon_pressed.bind(hub, btn))

	# --- DYNAMIC CONTENT STACK ---
	_content_stack = Control.new()
	_content_stack.size_flags_vertical = SIZE_EXPAND_FILL
	_main_vbox.add_child(_content_stack)

	# --- TALL CHAT LOG (Default content) ---
	chat_log = RichTextLabel.new()
	chat_log.set_anchors_preset(PRESET_FULL_RECT)
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.add_theme_font_size_override("normal_font_size", 18)
	_content_stack.add_child(chat_log)
	chat_log.text = "[center][color=#00f3ff]... LUMAX NEXUS ONLINE ...[/color][/center]"

	# --- SHARED EXPERIENCE CONFERENCE (NEW) ---
	var conf_vbox = VBoxContainer.new()
	conf_vbox.name = "ConferencePanel"
	conf_vbox.set_anchors_preset(PRESET_TOP_WIDE)
	conf_vbox.custom_minimum_size.y = 280
	# conf_vbox.hide() # Keep hidden by default
	_content_stack.add_child(conf_vbox)
	
	var conf_panel = PanelContainer.new()
	var style_conf = StyleBoxFlat.new()
	style_conf.bg_color = Color(0, 0, 0, 0.4); style_conf.set_corner_radius_all(15)
	style_conf.border_width_bottom = 2; style_conf.border_color = Color(1,1,1,0.05)
	conf_panel.add_theme_stylebox_override("panel", style_conf)
	conf_vbox.add_child(conf_panel)

	var h_grid = HBoxContainer.new()
	h_grid.add_theme_constant_override("separation", 5)
	conf_panel.add_child(h_grid)
	
	var user_v = TextureRect.new(); user_v.name = "UserPOV"; user_v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; user_v.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	user_v.custom_minimum_size = Vector2(390, 220); user_v.size_flags_horizontal = SIZE_EXPAND_FILL
	var jen_v = TextureRect.new(); jen_v.name = "JenPOV"; jen_v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; jen_v.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	jen_v.custom_minimum_size = Vector2(390, 220); jen_v.size_flags_horizontal = SIZE_EXPAND_FILL
	
	h_grid.add_child(user_v); h_grid.add_child(jen_v)
	
	var conf_btns = HBoxContainer.new(); conf_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	conf_vbox.add_child(conf_btns)
	var save_b = Button.new(); save_b.text = "[ SAVE EXPERIENCE ]"; save_b.custom_minimum_size = Vector2(250, 40)
	conf_btns.add_child(save_b)
	
	# Adjust Chat Log to be below conference
	chat_log.set_anchors_preset(PRESET_FULL_RECT)
	chat_log.offset_top = 280
	chat_log.add_theme_color_override("default_color", Color(1, 1, 1, 0.9)) # WHITE TEXT FOR READABILITY
	chat_log.add_theme_font_size_override("normal_font_size", 20)

	var input_area = PanelContainer.new()
	var style_input = StyleBoxFlat.new()
	style_input.bg_color = Color(1.0, 1.0, 1.0, 0.6)
	style_input.set_corner_radius_all(10)
	style_input.border_width_left = 1; style_input.border_width_top = 1; style_input.border_width_right = 1; style_input.border_width_bottom = 1
	style_input.border_color = Color(0, 0, 0, 0.1)
	input_area.add_theme_stylebox_override("panel", style_input)
	input_area.custom_minimum_size.y = 60
	_main_vbox.add_child(input_area)
	
	input_display = Label.new()
	input_display.text = "> _"
	input_display.add_theme_font_size_override("font_size", 24)
	input_display.add_theme_color_override("font_color", Color.CYAN)
	input_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	input_area.add_child(input_display)
	input_display.custom_minimum_size.x = 650
	input_display.position.x = 20

	# --- FLOATING SUBMENU LAYER ---
	_floating_panel = PanelContainer.new()
	add_child(_floating_panel)
	_floating_panel.visible = false
	_floating_panel.top_level = true
	
	var style_float = StyleBoxFlat.new()
	style_float.bg_color = Color(0.01, 0.01, 0.02, 0.7)
	style_float.border_width_left = 1; style_float.border_width_top = 1; style_float.border_width_right = 1; style_float.border_width_bottom = 1
	style_float.border_color = Color(0, 0.9, 1.0, 0.3) # Cyan Glow Border
	style_float.set_corner_radius_all(10)
	_floating_panel.add_theme_stylebox_override("panel", style_float)
	_submenu_container = VBoxContainer.new()
	_floating_panel.add_child(_submenu_container)
	
func _play_sfx(sfx_name: String):
	if not _audio: return
	var path = "res://Mind/Sfx/" + sfx_name + ".wav"
	if FileAccess.file_exists(path):
		_audio.stream = load(path)
		_audio.play()

func _on_ribbon_pressed(hub_name: String, btn: Button):
	if _floating_panel.visible and _active_hub_btn == btn: 
		_floating_panel.visible = false
		return
	_active_hub_btn = btn
	_floating_panel.global_position = btn.global_position + Vector2(0, btn.size.y + 5)
	_floating_panel.size.x = btn.size.x
	_floating_panel.visible = true
	
	for child in _submenu_container.get_children(): child.queue_free()
	_play_sfx("shuff")
	for sub in _hubs.get(hub_name, []):
		var s_btn = Button.new()
		s_btn.text = " " + sub
		s_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		s_btn.custom_minimum_size.y = 40
		_submenu_container.add_child(s_btn)
		s_btn.pressed.connect(func(): 
			_play_sfx("pop")
			_floating_panel.visible = false
			_on_tab_pressed(sub))

func _find_hud() -> Node:
	return get_tree().get_first_node_in_group("hud_overlay")

func _on_tab_pressed(tab_name: String):
	_clear_content_stack()
	
	match tab_name:
		"CHAT":
			chat_log.visible = true
		"SOUL":
			_show_soul_panel()
		"SETTINGS":
			_show_settings_panel()
		"WIDGETS":
			_show_widgets_settings()
		"LOGS":
			_show_logs_panel()
		"SENTRY":
			_show_sentry_matrix()
		"VITALS":
			_show_vitals_monitors()
		"MEMORY":
			_show_memory_panel()
		"BRAINS":
			_show_brains_panel()
		"VESSEL":
			_show_vessel_panel()
		"AGENCY":
			_show_agency_panel()
		"PSYCHE":
			_show_soul_panel()
		"IMAGEN", "VIDGEN", "MEDIA":
			_show_manifest_placeholder(tab_name)
		"FILES":
			_show_files_panel()
		"EMOTIONS":
			_show_emotions_panel()
		_:
			add_message("SYSTEM", "PROTO [" + tab_name + "] INITIALIZED")
			chat_log.visible = true

func _clear_content_stack():
	for child in _content_stack.get_children():
		if child == chat_log: 
			child.visible = false
		else:
			child.queue_free() # Clean memory, recreate on demand

func _show_soul_panel():
	var panel = _content_stack.get_node_or_null("SoulPanel")
	if not panel:
		panel = ScrollContainer.new()
		panel.name = "SoulPanel"
		panel.set_anchors_preset(PRESET_FULL_RECT)
		_content_stack.add_child(panel)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		panel.add_child(vbox)
		
		var title = Label.new()
		title.text = "MBTI ARCHETYPES"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title)
		
		var mbti_grid = GridContainer.new()
		mbti_grid.columns = 4
		vbox.add_child(mbti_grid)
		
		var archetypes = ["INTJ", "INTP", "ENTJ", "ENTP", "INFJ", "INFP", "ENFJ", "ENFP", "ISTJ", "ISFJ", "ESTJ", "ESFJ", "ISTP", "ISFP", "ESTP", "ESFP"]
		for arch in archetypes:
			var btn = Button.new()
			btn.text = arch
			btn.custom_minimum_size = Vector2(80, 40)
			mbti_grid.add_child(btn)
			btn.pressed.connect(func(): _on_mbti_selected(arch))
			
		var pop_l = Label.new(); pop_l.text = "3 POP ARCHETYPES // FEATURED"; pop_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vbox.add_child(pop_l)
		var pop_h = HBoxContainer.new(); pop_h.alignment = BoxContainer.ALIGNMENT_CENTER; vbox.add_child(pop_h)
		for p in ["INFJ", "ENFP", "INTJ"]:
			var b = Button.new(); b.text = p; b.custom_minimum_size = Vector2(100, 50); pop_h.add_child(b); b.pressed.connect(func(): _on_mbti_selected(p))
		
		vbox.add_child(HSeparator.new())
		
		var tuner_title = Label.new()
		tuner_title.text = "MANUAL NEURAL TUNING"
		tuner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(tuner_title)
		
		for t in _traits:
			var hbox = HBoxContainer.new()
			vbox.add_child(hbox)
			var label = Label.new()
			label.text = t.capitalize()
			label.custom_minimum_size.x = 150
			hbox.add_child(label)
			
			var slider = HSlider.new()
			slider.min_value = 0; slider.max_value = 100; slider.value = 50
			slider.size_flags_horizontal = SIZE_EXPAND_FILL
			hbox.add_child(slider)
			slider.value_changed.connect(func(v): web_slider_changed.emit(t, v))
			
	panel.visible = true

func _show_settings_panel():
	var panel = _content_stack.get_node_or_null("SettingsPanel")
	if not panel:
		panel = VBoxContainer.new()
		panel.name = "SettingsPanel"
		panel.set_anchors_preset(PRESET_FULL_RECT)
		_content_stack.add_child(panel)
		
	var scroll = panel.get_node_or_null("SettingsScroll")
	if not scroll:
		scroll = ScrollContainer.new(); scroll.name = "SettingsScroll"; scroll.size_flags_vertical = SIZE_EXPAND_FILL; panel.add_child(scroll)
		var settings_list = VBoxContainer.new(); settings_list.name = "SettingsList"; settings_list.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(settings_list)
		
		_populate_settings_list(settings_list)

	panel.visible = true

func _populate_settings_list(settings_list: VBoxContainer):
	
	var controls = [
		{"n": "MASTER_VOLUME", "t": "SLIDER", "v": 80},
		{"n": "MUSIC_VOLUME", "t": "SLIDER", "v": 50},
		{"n": "SFX_VOLUME", "t": "SLIDER", "v": 70},
		{"n": "NIGHT_FILTER", "t": "TOGGLE", "v": false},
		{"n": "LOW_VRAM_MODE", "t": "TOGGLE", "v": false},
		{"n": "GHOST_INTERFACE", "t": "TOGGLE", "v": true},
		{"n": "NEURAL_PRECISION", "t": "LIST", "v": ["LOW", "BALANCED", "ULTRA"]}
	]
	
	for c in controls:
		var h = HBoxContainer.new(); settings_list.add_child(h)
		var label = Label.new(); label.text = c.n; label.custom_minimum_size.x = 200; h.add_child(label)
		
		if c.t == "SLIDER":
			var s = HSlider.new(); s.size_flags_horizontal = SIZE_EXPAND_FILL; s.value = c.v; h.add_child(s)
			s.value_changed.connect(func(v): _on_manual_setting_changed(c.n, v))
		elif c.t == "TOGGLE":
			var b = CheckButton.new(); b.button_pressed = c.v; h.add_child(b)
			b.toggled.connect(func(v): _on_manual_setting_changed(c.n, v))
		elif c.t == "LIST":
			var ob = OptionButton.new(); h.add_child(ob)
			for item in c.v: ob.add_item(item)
			ob.item_selected.connect(func(idx): _on_manual_setting_changed(c.n, c.v[idx]))

	var l_tools = Label.new(); l_tools.text = "ENGINE_TOOLS // UTILITIES"; l_tools.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; settings_list.add_child(l_tools)
	var quick_grid = GridContainer.new(); quick_grid.columns = 2; settings_list.add_child(quick_grid)
	
	var tools = [
		{"n": "FLUSH_MEMORY", "c": Color.AQUAMARINE},
		{"n": "RECALIBRATE_IK", "c": Color.GOLD},
		{"n": "PURGE_CACHE", "c": Color.HOT_PINK},
		{"n": "SYSTEM_DIAG", "c": Color.SKY_BLUE}
	]
	
	for t in tools:
		var b = Button.new(); b.text = t.n; b.custom_minimum_size = Vector2(200, 45); quick_grid.add_child(b)
		b.pressed.connect(func(): add_message("SYSTEM", "EXEC: " + t.n))
		

func _on_manual_setting_changed(setting: String, value: Variant):
	_play_sfx("pop")
	add_message("SYSTEM", "SETTING: " + setting + " -> " + str(value))
	# Internal logic for toggles
	if setting == "NIGHT_FILTER": 
		_on_quick_setting_pressed("NIGHT_MODE")
	elif setting == "GHOST_INTERFACE":
		_on_quick_setting_pressed("GHOST_UI")
	elif setting == "LOW_VRAM_MODE":
		low_vram_toggled.emit()

func _show_widgets_settings():
	var panel = _content_stack.get_node_or_null("WidgetsPanel")
	if not panel:
		panel = VBoxContainer.new()
		panel.name = "WidgetsPanel"
		panel.set_anchors_preset(PRESET_FULL_RECT)
		_content_stack.add_child(panel)
		
		var l = Label.new()
		l.text = "HUD_INGREDIENTS // SPECTRAL_ARRAY"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(l)
		
		var grid = GridContainer.new(); grid.columns = 2; panel.add_child(grid)
		var stubs = [
			{"n": "CPU_LOAD", "t": "HEADER_RECT"}, {"n": "MEM_USAGE", "t": "LATERAL_SQUARE"},
			{"n": "NET_SYNC", "t": "LATERAL_SQUARE"}, {"n": "RESONANCE", "t": "HEADER_RECT"},
			{"n": "THERMALS", "t": "LATERAL_SQUARE"}, {"n": "UPTIME", "t": "FOOTER_WIDE"},
			{"n": "IO_FLOW", "t": "LATERAL_SQUARE"}, {"n": "NEURAL_FLUX", "t": "HEADER_RECT"},
			{"n": "VRAM_WIDGET", "t": "LATERAL_SQUARE"}, {"n": "QUOTA_MONITOR", "t": "FOOTER_WIDE"}
		]
		
		for s in stubs:
			var btn = CheckButton.new()
			btn.text = s.n
			grid.add_child(btn)
			btn.toggled.connect(func(active):
				var hud = _find_hud()
				if hud: hud.toggle_widget(s.n, active, s.t)
				add_message("SYSTEM", "WIDGET " + s.n + " -> " + ("ON" if active else "OFF"))
			)
			
	panel.visible = true

func _show_logs_panel():
	var panel = _content_stack.get_node_or_null("LogsPanel")
	if not panel:
		panel = VBoxContainer.new(); panel.name = "LogsPanel"; _content_stack.add_child(panel)
		_log_display = RichTextLabel.new(); _log_display.size_flags_vertical = SIZE_EXPAND_FILL; _log_display.bbcode_enabled = true; panel.add_child(_log_display)
		for line in LogMaster.get_logs(): _log_display.append_text(line + "\n")
	panel.visible = true

func _show_sentry_matrix():
	var panel = _content_stack.get_node_or_null("SentryMatrix")
	if not panel:
		panel = GridContainer.new(); panel.columns = 2; panel.name = "SentryMatrix"; _content_stack.add_child(panel)
		var metrics = ["VRAM_BUFF", "CORE_SYNC", "NET_LATENCY", "DISK_I/O", "THERMAL_STATE", "UPLOAD_FLUX", "DOWN_FLUX", "RESONANCE", "USER_IDLE", "MIND_DEPTH"]
		for m in metrics:
			var p = PanelContainer.new(); panel.add_child(p)
			var sb = StyleBoxFlat.new(); sb.bg_color = Color(1,1,1,0.05); sb.set_corner_radius_all(5); p.add_theme_stylebox_override("panel", sb)
			var v = VBoxContainer.new(); p.add_child(v); v.alignment = BoxContainer.ALIGNMENT_CENTER
			var l = Label.new(); l.text = m; l.add_theme_font_size_override("font_size", 12); v.add_child(l)
			var val = Label.new(); val.text = "---"; val.name = m + "_VAL"; val.add_theme_font_size_override("font_size", 20); v.add_child(val)
			_vitals_data[m] = val
	panel.visible = true

func _on_log_added(msg: String, _type: String):
	if _log_display and is_instance_valid(_log_display):
		_log_display.append_text(msg + "\n")

func _show_vitals_monitors():
	var panel = VBoxContainer.new()
	panel.name = "VitalsPanel"
	panel.set_anchors_preset(PRESET_FULL_RECT)
	_content_stack.add_child(panel)
	
	var l = Label.new()
	l.text = "ACCESSING VITALS // BIOMETRIC_HUD"
	panel.add_child(l)
	
	var vitals = [
		{"l": "HEART_RATE", "v": "72 BPM", "c": Color.RED},
		{"l": "SYNC_LEVEL", "v": "98.4%", "c": Color.CYAN},
		{"l": "NERVOUS_TEMP", "v": "36.8°C", "c": Color.YELLOW},
		{"l": "CORE_PULSE", "v": "ACTIVE", "c": Color.GREEN},
		{"l": "SYS_STRESS", "v": "LOW", "c": Color.ORANGE},
		{"l": "SYS_ERRORS", "v": "0 DEAD", "c": Color.INDIAN_RED},
		{"l": "DATA_QUOTA", "v": "UNLIMITED", "c": Color.VIOLET}
	]
	
	for v in vitals:
		var h = HBoxContainer.new(); panel.add_child(h)
		var label = Label.new(); label.text = "[ " + v.l + " ]: "; h.add_child(label)
		var val = Label.new(); val.text = v.v; val.add_theme_color_override("font_color", v.c); h.add_child(val)
		_vitals_data[v.l] = val
	
	panel.visible = true

func _process(_delta):
	# Update vitals once a second
	if Time.get_ticks_msec() % 1000 < 50:
		_update_vitals_monitors()

func _update_vitals_monitors():
	if _vitals_data.is_empty(): return
	
	var fps = Engine.get_frames_per_second()
	var mem = snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1)
	
	if _vitals_data.has("HEART_RATE"): _vitals_data["HEART_RATE"].text = str(60 + int(fps/10)) + " BPM"
	if _vitals_data.has("CORE_PULSE"): _vitals_data["CORE_PULSE"].text = "%.0f FPS" % fps
	if _vitals_data.has("SYNC_LEVEL"): _vitals_data["SYNC_LEVEL"].text = "%.1f MB" % mem

func _on_vitals_received(data: Dictionary):
	for key in data.keys():
		if _vitals_data.has(key):
			_vitals_data[key].text = str(data[key])

func _show_manifest_placeholder(type: String):
	var panel = _content_stack.get_node_or_null("ManifestPanel")
	if not panel:
		panel = VBoxContainer.new(); panel.name = "ManifestPanel"; _content_stack.add_child(panel)
		
		# Top Title
		var title = Label.new(); title.name = "TitleLabel"; title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(title)
		panel.add_child(HSeparator.new())
		
		# Viewport / Output Display Area
		var display_box = PanelContainer.new()
		display_box.custom_minimum_size = Vector2(0, 250)
		var db_style = StyleBoxFlat.new(); db_style.bg_color = Color(0,0,0,0.5); db_style.border_width_bottom = 2; db_style.border_color = Color(0, 0.9, 1.0, 0.4)
		display_box.add_theme_stylebox_override("panel", db_style)
		panel.add_child(display_box)
		
		var viewport_label = Label.new(); viewport_label.name = "StateLabel"; viewport_label.text = "[ MEDIA_BUFFER_EMPTY ]"; viewport_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; viewport_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		display_box.add_child(viewport_label)
		
		# Prompt / Command Entry
		var input_box = HBoxContainer.new()
		input_box.custom_minimum_size = Vector2(0, 45)
		input_box.add_theme_constant_override("separation", 10)
		panel.add_child(input_box)
		
		var prompt_input = LineEdit.new()
		prompt_input.name = "PromptInput"
		prompt_input.placeholder_text = "Enter manifestation request (e.g. \"A cyberpunk city looking over a cliff\")"
		prompt_input.size_flags_horizontal = SIZE_EXPAND_FILL
		var pi_style = StyleBoxFlat.new(); pi_style.bg_color = Color(0.1,0.1,0.1,0.8); pi_style.set_corner_radius_all(5); prompt_input.add_theme_stylebox_override("normal", pi_style)
		input_box.add_child(prompt_input)
		
		var _gen_btn = Button.new(); _gen_btn.name = "GenButton"; _gen_btn.text = "MANIFEST"
		_gen_btn.custom_minimum_size = Vector2(140, 0)
		input_box.add_child(_gen_btn)
		
		# Attachment / Hardware Strip
		var bottom_strip = HBoxContainer.new()
		panel.add_child(bottom_strip)
		
		var action_panel = GridContainer.new()
		action_panel.name = "ActionsGrid"; action_panel.columns = 3; action_panel.size_flags_horizontal = SIZE_EXPAND_FILL
		action_panel.add_theme_constant_override("h_separation", 10)
		bottom_strip.add_child(action_panel)
		
	panel.visible = true
	var p_title = panel.get_node("TitleLabel")
	var p_state = panel.get_node_or_null("PanelContainer/StateLabel")
	var p_actions = panel.get_node_or_null("HBoxContainer/ActionsGrid")
	var gen_btn = panel.get_node_or_null("HBoxContainer2/GenButton")
	var p_input = panel.get_node_or_null("HBoxContainer2/PromptInput")
	
	p_title.text = "NEURAL EXTENSION // " + type
	if p_state: p_state.text = "[ " + type + "_BUFFER_EMPTY ]"
	
	# Clear old buttons
	for child in p_actions.get_children(): child.queue_free()
	if get_node_or_null("ManifestBtnHelper"): get_node_or_null("ManifestBtnHelper").queue_free()
	
	var logic_helper = Node.new(); logic_helper.name = "ManifestBtnHelper"; add_child(logic_helper)
	
	# Populate based on type
	var btns = []
	if type == "IMAGEN":
		btns = ["CAPTURE_POV", "ANALYZE_SURROUNDINGS", "UPLOAD_REF", "SD_TURBO", "ABSYNTH_V2"]
	elif type == "VIDGEN":
		btns = ["SVD_MODEL", "CLIP_LATEST", "FRAME_INTERPOLATE", "EXPORT_MP4", "LOOP_PLAYBACK"]
	elif type == "MEDIA":
		btns = ["MUSIC_DJ", "OPEN_BROWSER", "YOUTUBE_RELAY", "VISUALIZER", "HAPTIC_SYNC"]
		
	for b in btns:
		var btn = Button.new(); btn.text = b; btn.size_flags_horizontal = SIZE_EXPAND_FILL; btn.custom_minimum_size = Vector2(0, 35)
		p_actions.add_child(btn)
		btn.pressed.connect(func(): _play_sfx("pop"); add_message("SYSTEM", "TRAPPED " + type + " ACTION: " + b))

# --- STUBS FOR OTHER TABS ---
func _show_memory_panel():
	var panel = _content_stack.get_node_or_null("MemoryPanel")
	if not panel:
		panel = VBoxContainer.new(); panel.name = "MemoryPanel"; _content_stack.add_child(panel)
		panel.set_anchors_preset(PRESET_FULL_RECT)
		var l = Label.new(); l.text = "TEMPORAL_ARCHIVE // SOUL_RECALL"; panel.add_child(l)
		var scroll = ScrollContainer.new(); scroll.size_flags_vertical = SIZE_EXPAND_FILL; panel.add_child(scroll)
		var v = VBoxContainer.new(); v.name = "ArchiveList"; scroll.add_child(v)
	
	panel.visible = true
	archive_requested.emit()

func _on_memory_received(archive: Array):
	var panel = _content_stack.get_node_or_null("MemoryPanel")
	if panel:
		var list = panel.get_node("ArchiveList")
		for c in list.get_children(): c.queue_free()
		for item in archive:
			if item.get("is_image", false):
				var rect = TextureRect.new()
				var img = Image.new(); img.load_jpg_from_buffer(Marshalls.base64_to_raw(item.content))
				rect.texture = ImageTexture.create_from_image(img)
				rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE; rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				rect.custom_minimum_size = Vector2(0, 200); list.add_child(rect)
			else:
				var l = RichTextLabel.new(); l.bbcode_enabled = true; l.fit_content = true
				var role_color = "#00f3ff" if item.role == "user" else "#ff007f"
				l.append_text("[color=" + role_color + "][b]" + item.role.to_upper() + ":[/b][/color] " + item.content)
				list.add_child(l)
func _show_brains_panel():
	var panel = _content_stack.get_node_or_null("BrainsPanel")
	if not panel:
		panel = VBoxContainer.new()
		panel.name = "BrainsPanel"
		panel.set_anchors_preset(PRESET_FULL_RECT)
		_content_stack.add_child(panel)
		
		var l = Label.new()
		l.text = "COGNITIVE_CORES // LLM_SELECTOR"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(l)
		
		# RADIAL BRAIN SELECTOR (2-col grid)
		var rgrid = GridContainer.new()
		rgrid.columns = 2
		panel.add_child(rgrid)
		rgrid.add_theme_constant_override("h_separation", KEY_GAP)
		rgrid.add_theme_constant_override("v_separation", KEY_GAP)
		
		var models = [
			{"id": "nexus_v1", "n": "NEXUS_CORE_V1 (GGUF)"},
			{"id": "soul_4b_q6", "n": "SOUL-4B-Q6 (Llama)"},
			{"id": "ratatosk_tiny", "n": "RATATOSK-1B (Tiny)"},
			{"id": "ollama_fallback", "n": "OLLAMA_RELAY"}
		]
		
		for m in models:
			var btn = Button.new()
			btn.text = m.n
			btn.custom_minimum_size = Vector2(200, 50)
			rgrid.add_child(btn)
			btn.pressed.connect(func():
				brain_selected.emit(m.id)
				add_message("SYSTEM", "MANIFESTING COGNITIVE_CORE: " + m.id)
			)
			
	panel.visible = true
func _show_vessel_panel(): 
	var panel = ScrollContainer.new()
	panel.name = "VesselPanel"
	panel.set_anchors_preset(PRESET_FULL_RECT)
	_content_stack.add_child(panel)
	
	var vbox = VBoxContainer.new(); vbox.size_flags_horizontal = SIZE_EXPAND_FILL; panel.add_child(vbox)
	
	var lbl = Label.new(); lbl.text = "MANIFEST // AVATAR_GALLERY"; lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vbox.add_child(lbl)
	
	var grid = GridContainer.new(); grid.columns = 3; grid.add_theme_constant_override("h_separation", 15); grid.add_theme_constant_override("v_separation", 15); vbox.add_child(grid)
	
	# Scan for avatars recursively
	var found_avatars = []
	_recursive_vrm_scan("res://", found_avatars)
	
	for av in found_avatars:
		var btn = Button.new()
		btn.text = av.get_file().get_basename()
		btn.custom_minimum_size = Vector2(250, 120)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.add_child(btn)
		
		# Add tooltip with path
		btn.tooltip_text = av
		
		btn.pressed.connect(func():
			_play_sfx("pop")
			add_message("SYSTEM", "LOAD_VESSEL: " + av)
			avatar_selected.emit(av)
		)
	
	panel.visible = true

func _recursive_vrm_scan(path: String, out_list: Array):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if not file_name.begins_with("."):
					_recursive_vrm_scan(path + file_name + "/", out_list)
			else:
				if file_name.ends_with(".vrm"):
					out_list.append(path + file_name)
			file_name = dir.get_next()
func _show_agency_panel(): chat_log.visible = true; add_message("AGENCY", "Autonomous intent engaged.")

func _on_mbti_selected(mbti: String):
	add_message("SYSTEM", "EVOLVING SOUL TO ARCHETYPE: " + mbti)
	_play_sfx("pop")
	soul_updated.emit({"mbti": mbti})
	
	# Visual Sync: Shuffle sliders to reflect archetype "baseline" (aesthetic only)
	var panel = _content_stack.get_node_or_null("SoulPanel")
	if panel:
		var vbox = panel.get_child(0)
		for child in vbox.get_children():
			if child is HBoxContainer:
				var slider = child.get_child(1) as HSlider
				if slider: slider.value = randf_range(20, 80)

func _on_quick_setting_pressed(setting: String):
	add_message("SYSTEM", "TOGGLING_PROTOCOL: " + setting)
	match setting:
		"NIGHT_MODE":
			var filter = get_node_or_null("NightFilter")
			if not filter:
				filter = ColorRect.new(); filter.name = "NightFilter"; filter.set_anchors_preset(PRESET_FULL_RECT)
				filter.mouse_filter = Control.MOUSE_FILTER_IGNORE; filter.color = Color(0.1, 0, 0, 0.2); add_child(filter)
			else: filter.visible = !filter.visible
		"GHOST_UI":
			var alpha = 0.05 if Input.is_key_pressed(KEY_SHIFT) else 0.1
			for child in _content_stack.get_children():
				if child is PanelContainer:
					var sb = child.get_theme_stylebox("panel") as StyleBoxFlat
					if sb: sb.bg_color.a = alpha
		"LOW_VRAM":
			low_vram_toggled.emit()

func add_message(who: String, text: String):
	var color = "#00f3ff" if who.begins_with("YOU") or who == "USER" or who == "ME" else "#ff007f"
	if not chat_log: return
	
	chat_log.append_text("\n[color=" + color + "][b]" + who + ":[/b][/color] ")
	
	# IMPROVED IMAGE HANDLING: Check for [img] tags and load them properly
	if "[img]" in text or "[img=" in text:
		var regex = RegEx.new()
		regex.compile("\\[img.*?\\](.*?)\\[/img\\]")
		var result = regex.search(text)
		if result:
			var path = result.get_string(1)
			if path.begins_with("user://") and FileAccess.file_exists(path):
				var img = Image.load_from_file(path)
				if img:
					# Resize for display if too large
					var max_w = 400
					if img.get_width() > max_w:
						var img_scale = float(max_w) / img.get_width()
						img.resize(max_w, int(img.get_height() * img_scale), Image.INTERPOLATE_LANCZOS)
					
					var tex = ImageTexture.create_from_image(img)
					chat_log.add_image(tex)
			
			# Strip the tag from the text so it doesn't show as a broken string
			text = regex.sub(text, "", true)
	
	chat_log.append_text(text)

# --- ADDITIONAL PANELS ---
func _show_files_panel():
	var panel = _content_stack.get_node_or_null("FilesPanel")
	if not panel:
		panel = VBoxContainer.new(); panel.name = "FilesPanel"; _content_stack.add_child(panel)
		var l = Label.new(); l.text = "LOCAL_FS // PROJECT_ARCHIVES"; panel.add_child(l)
		var list = ItemList.new(); list.name = "FileList"; list.size_flags_vertical = SIZE_EXPAND_FILL; panel.add_child(list)
		list.item_activated.connect(func(idx): add_message("SYSTEM", "ACCESS_DENIED: " + list.get_item_text(idx)))
	
	panel.visible = true
	files_requested.emit()

func _on_files_received(files: Array):
	var panel = _content_stack.get_node_or_null("FilesPanel")
	if panel:
		var list = panel.get_node("FileList") as ItemList
		list.clear()
		for f in files: list.add_item(f)

func _show_emotions_panel():
	var panel = _content_stack.get_node_or_null("EmotionsPanel")
	if not panel:
		panel = GridContainer.new(); panel.name = "EmotionsPanel"; panel.columns = 3; _content_stack.add_child(panel)
		panel.add_theme_constant_override("h_separation", KEY_GAP)
		panel.add_theme_constant_override("v_separation", KEY_GAP)
		
		var ems = ["AWE", "MELANCHOLY", "INTENT", "CONTEMPLATE", "CURIOUS", "PRAYING", "THINKING", "ZEN", "SENSE_ENV", "DREAM", "DIAGNOSTIC"]
		for e in ems:
			var b = Button.new(); b.text = e; b.custom_minimum_size = Vector2(120, 120); panel.add_child(b)
			if e == "SENSE_ENV":
				b.add_theme_color_override("font_color", Color.ORANGE)
				b.pressed.connect(func(): vision_sensing_requested.emit())
			elif e == "DREAM":
				b.add_theme_color_override("font_color", Color.VIOLET)
				b.pressed.connect(func(): dream_requested.emit())
			elif e == "DIAGNOSTIC":
				b.add_theme_color_override("font_color", Color.GREEN_YELLOW)
				b.pressed.connect(func(): system_check_requested.emit())
			elif e == "ZEN": # Re-purpose some buttons for verification
				b.text = "VERIFY_SOUL"
				b.add_theme_color_override("font_color", Color.AQUA)
				b.pressed.connect(func(): soul_verification_requested.emit())
			elif e == "INTENT":
				b.text = "CERTIFY_USER"
				b.add_theme_color_override("font_color", Color.GOLD)
				b.pressed.connect(func(): user_certification_requested.emit())
			else:
				b.pressed.connect(func(): add_message("SYSTEM", "STIMULATING_EMOTION: " + e))
	panel.visible = true

func update_shared_views(user_tex: Texture2D, jen_tex: Texture2D):
	var panel = _content_stack.get_node_or_null("ConferencePanel")
	if panel:
		var grid = panel.get_node("PanelContainer/HBoxContainer")
		grid.get_node("UserPOV").texture = user_tex
		grid.get_node("JenPOV").texture = jen_tex
		panel.show()

func update_buffer(text: String): 
	if input_display: input_display.text = "> " + text + "_"
