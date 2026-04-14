extends Control

signal avatar_selected(name: String)
signal soul_updated(dna: Dictionary)
signal web_slider_changed(trait_name: String, value: float)
signal brain_selected(model_name: String)
signal low_vram_toggled()
signal vision_sensing_requested()
signal files_requested()
signal file_activation_requested(path: String)
signal archive_requested()
signal dream_requested()
signal system_check_requested()
signal soul_verification_requested()
signal user_certification_requested()
signal emotion_stimulus_requested(emotion_name: String)
## Indices match `SkeletonKey.QuestDisplayMode`: 0 Auto, 1 Pure passthrough, 2 XR mixed, 3 VR.
signal quest_display_mode_selected(mode_index: int)
## Indices match `SkeletonKey.XRFlowProfile`: 0 Off, 1 Balanced, 2 Performance.
signal xr_flow_profile_selected(mode_index: int)
## Match `MultiVisionHandler.UserVisionSource` / `JenVisionSource` enum ordinals.
signal user_vision_source_selected(mode_index: int)
signal jen_vision_source_selected(mode_index: int)

var current_tab = "NEURAL"
@onready var chat_log: RichTextLabel = null
## Live mirror of TactileInput buffer (typed on XR keyboard); bottom strip of CHAT column.
var input_display: Label = null
var _chat_column: VBoxContainer = null
var _main_vbox: VBoxContainer = null
var _content_stack: Control = null
var _floating_panel: PanelContainer = null
var _submenu_container: VBoxContainer = null
var _active_hub_btn: Button = null
var _audio: AudioStreamPlayer = null
var _log_display: RichTextLabel = null
var _vitals_data: Dictionary = {}
var _hub_buttons: Dictionary = {}
var _stress_banner: Label = null
var _stress_latched: bool = false
var _last_soul_cpu_pct: float = -1.0
var _last_host_cpu_pct: float = -1.0
const STRESS_HOT_PCT := 550.0
const STRESS_CLEAR_PCT := 300.0
var _quest_display_ob: OptionButton = null
var _xr_flow_ob: OptionButton = null
var _user_vision_ob: OptionButton = null
var _jen_vision_ob: OptionButton = null

## SYSTEM tab: soul runtime (GGUF path, mmproj, flags) — wired to Synapse group `lumax_synapse`.
var _system_preset_ob: OptionButton = null
var _system_model_path_edit: LineEdit = null
var _system_mmproj_path_edit: LineEdit = null
var _system_native_vision_cb: CheckButton = null
var _system_local_caption_cb: CheckButton = null
var _system_chat_provider_ob: OptionButton = null
var _system_status_label: Label = null
var _system_synapse_signals_done: bool = false
## SYSTEM tab: mouth TTS routing (:8002) — VR cannot call Docker; use PC Web UI for full GPU switch.
var _tts_backend_ob: OptionButton = null
var _tts_get_http: HTTPRequest = null
var _tts_put_http: HTTPRequest = null
const _PATH_GEMMA_HERETIC_DEFAULT := "D:/VR_AI_Forge_Data/models/Mind/Cognition/gemma-4-E2B-it-heretic-ara.Q4_K_M.gguf"
const _SYSTEM_PREFS_PATH := "user://lumax_soul_runtime_prefs.json"

var _log_lines: Array = ["[color=green]OS_LOAD_OK[/color]", "[color=cyan]VRAM: 8GB ACTIVE[/color]", "[color=white]NEURAL_FLUX: STABLE[/color]"]
const KEY_GAP := 10.0

## Hub id → submenu tab ids (internal). Display strings: `ribbon_labels` / `tab_labels` from lumax_ui_config (Godot/VR).
var _hubs: Dictionary = {
	"MIND": ["PSYCHE", "SOUL", "BRAINS", "MEMORY", "EMOTIONS"],
	"BODY": ["VESSEL", "AGENCY", "VITALS"],
	"MANIFEST": ["IMAGEN", "VIDGEN", "MEDIA"],
	"CORE": ["CHAT", "LOGS", "SETTINGS", "SYSTEM", "CHATTERBOX", "FILES"],
}
const _UI_CONFIG_CACHE := "user://lumax_ui_config_cache.json"
var _ribbon_labels: Dictionary = {}
var _tab_labels: Dictionary = {}
var _ui_http: HTTPRequest

var _traits = [
	"extrovert", "intellectual", "logic", "detail", "faithful", "sexual", 
	"experimental", "wise", "openminded", "honest", "forgiving", "feminine", 
	"dominant", "progressive", "sloppy", "greedy", "homonormative"
]

func _ready():
	_load_ui_config_cache_sync()
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_ui_http = HTTPRequest.new()
	add_child(_ui_http)
	_ui_http.request_completed.connect(_on_ui_config_http_done)
	_tts_get_http = HTTPRequest.new()
	add_child(_tts_get_http)
	_tts_get_http.request_completed.connect(_on_tts_get_http_done)
	_tts_put_http = HTTPRequest.new()
	add_child(_tts_put_http)
	_tts_put_http.request_completed.connect(_on_tts_put_http_done)
	
	if LogMaster:
		LogMaster.log_added.connect(_on_log_added)
	
	# --- BACKGROUND PANEL (V11.98 Deep Mix) ---
	var bg_panel = PanelContainer.new()
	bg_panel.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg_panel)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.01, 0.01, 0.04, 0.9) # Deep Midnight Blue
	bg_style.border_width_left = 4
	bg_style.border_color = Color(0.4, 0.0, 0.05, 0.5) # Dark Crimson Edge
	bg_style.set_corner_radius_all(10)
	bg_panel.add_theme_stylebox_override("panel", bg_style)

	# --- ROOT FRAME: Full Viewport Fill ---
	var root_margin = MarginContainer.new()
	root_margin.set_anchors_preset(PRESET_FULL_RECT)
	bg_panel.add_child(root_margin)
	
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
		btn.text = _ribbon_hub_text(hub)
		btn.custom_minimum_size.y = 50
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		ribbon_h_box.add_child(btn)
		btn.add_theme_stylebox_override("normal", style_btn)
		btn.pressed.connect(_on_ribbon_pressed.bind(hub, btn))
		_hub_buttons[hub] = btn

	_stress_banner = Label.new()
	_stress_banner.visible = false
	_stress_banner.text = "GUARDIAN: HARDWARE STRESS"
	_stress_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stress_banner.add_theme_font_size_override("font_size", 15)
	_stress_banner.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	_main_vbox.add_child(_stress_banner)

	# --- DYNAMIC CONTENT STACK ---
	_content_stack = Control.new()
	_content_stack.size_flags_vertical = SIZE_EXPAND_FILL
	_main_vbox.add_child(_content_stack)

	# --- CHAT COLUMN: draft line (keyboard buffer) + log ---
	_chat_column = VBoxContainer.new()
	_chat_column.name = "ChatColumn"
	_chat_column.set_anchors_preset(PRESET_FULL_RECT)
	_content_stack.add_child(_chat_column)

	input_display = Label.new()
	input_display.name = "KeyboardDraft"
	input_display.text = "> _"
	input_display.custom_minimum_size.y = 28
	input_display.add_theme_font_size_override("font_size", 15)
	input_display.add_theme_color_override("font_color", Color(0.5, 0.95, 1.0, 0.92))
	input_display.clip_text = true

	chat_log = RichTextLabel.new()
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.add_theme_font_size_override("normal_font_size", 18)
	_chat_column.add_child(chat_log)
	chat_log.text = "[center][color=#00f3ff]... LUMAX NEXUS ONLINE ...[/color][/center]"
	# Draft line under the log (mirrors TactileInput buffer)
	_chat_column.add_child(input_display)

	# --- SHARED EXPERIENCE CONFERENCE (NEW) ---
	var conf_vbox = VBoxContainer.new()
	conf_vbox.name = "ConferencePanel"
	conf_vbox.set_anchors_preset(PRESET_TOP_WIDE)
	conf_vbox.custom_minimum_size.y = 280
	# conf_vbox.hide() # Keep hidden by default
	_content_stack.add_child(conf_vbox)
	
	var conf_panel = PanelContainer.new()
	conf_panel.name = "ConfPanel"
	var style_conf = StyleBoxFlat.new()
	style_conf.bg_color = Color(0, 0, 0, 0.4); style_conf.set_corner_radius_all(15)
	style_conf.border_width_bottom = 2; style_conf.border_color = Color(1,1,1,0.05)
	conf_panel.add_theme_stylebox_override("panel", style_conf)
	conf_vbox.add_child(conf_panel)

	var h_grid = HBoxContainer.new()
	h_grid.name = "HGrid"
	h_grid.add_theme_constant_override("separation", 5)
	conf_panel.add_child(h_grid)
	
	var user_v = TextureRect.new(); user_v.name = "UserPOV"; user_v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; user_v.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	user_v.custom_minimum_size = Vector2(390, 220); user_v.size_flags_horizontal = SIZE_EXPAND_FILL
	var jen_v = TextureRect.new(); jen_v.name = "JenPOV"; jen_v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; jen_v.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	jen_v.custom_minimum_size = Vector2(390, 220); jen_v.size_flags_horizontal = SIZE_EXPAND_FILL
	
	# h_grid.add_child(user_v); h_grid.add_child(jen_v)
	
	var conf_btns = HBoxContainer.new(); conf_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	conf_vbox.add_child(conf_btns)
	# var save_b = Button.new(); save_b.text = "[ SAVE EXPERIENCE ]"; save_b.custom_minimum_size = Vector2(250, 40)
	# conf_btns.add_child(save_b)
	
	# chat_log.offset_top = 280
	chat_log.add_theme_color_override("default_color", Color(1, 1, 1, 0.9)) # WHITE TEXT FOR READABILITY
	chat_log.add_theme_font_size_override("normal_font_size", 20)

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
	call_deferred("_request_ui_config")

func _lumax_ui_base_url() -> String:
	var e: String = OS.get_environment("LUMAX_UI_CONFIG_URL")
	e = e.strip_edges()
	if e != "" and (e.begins_with("http://") or e.begins_with("https://")):
		return e.trim_suffix("/")
	return "http://127.0.0.1:8080"


func _ribbon_hub_text(hub: String) -> String:
	if _ribbon_labels.has(hub):
		return str(_ribbon_labels[hub])
	return hub


func _tab_display_name(tab_id: String) -> String:
	if _tab_labels.has(tab_id):
		return str(_tab_labels[tab_id])
	return tab_id


func _sanitize_hubs(raw: Variant) -> Dictionary:
	var fallback: Dictionary = {
		"MIND": ["PSYCHE", "SOUL", "BRAINS", "MEMORY", "EMOTIONS"],
		"BODY": ["VESSEL", "AGENCY", "VITALS"],
		"MANIFEST": ["IMAGEN", "VIDGEN", "MEDIA"],
		"CORE": ["CHAT", "LOGS", "SETTINGS", "SYSTEM", "CHATTERBOX", "FILES"],
	}
	if typeof(raw) != TYPE_DICTIONARY:
		return fallback
	var out: Dictionary = {}
	for k in raw.keys():
		var v = raw[k]
		if typeof(v) != TYPE_ARRAY:
			continue
		var arr: Array = []
		for x in v:
			arr.append(str(x))
		out[str(k)] = arr
	if out.size() == 0:
		return fallback
	for k in fallback.keys():
		if not out.has(k):
			out[k] = fallback[k]
	return out


func _apply_ui_config_dict(d: Dictionary) -> void:
	if not d.has("godot_vr"):
		return
	var gv = d["godot_vr"]
	if typeof(gv) != TYPE_DICTIONARY:
		return
	if gv.has("hubs"):
		_hubs = _sanitize_hubs(gv["hubs"])
	if gv.has("ribbon_labels") and typeof(gv["ribbon_labels"]) == TYPE_DICTIONARY:
		_ribbon_labels = {}
		for k in gv["ribbon_labels"].keys():
			_ribbon_labels[str(k)] = str(gv["ribbon_labels"][k])
	if gv.has("tab_labels") and typeof(gv["tab_labels"]) == TYPE_DICTIONARY:
		_tab_labels = {}
		for k in gv["tab_labels"].keys():
			_tab_labels[str(k)] = str(gv["tab_labels"][k])
	_refresh_ribbon_button_labels()


func _refresh_ribbon_button_labels() -> void:
	for hub in _hub_buttons.keys():
		var btn = _hub_buttons.get(hub)
		if btn:
			btn.text = _ribbon_hub_text(hub)


func _load_ui_config_cache_sync() -> void:
	if not FileAccess.file_exists(_UI_CONFIG_CACHE):
		return
	var txt := FileAccess.get_file_as_string(_UI_CONFIG_CACHE)
	if txt.is_empty():
		return
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return
	_apply_ui_config_dict(d)


func _request_ui_config() -> void:
	if _ui_http == null:
		return
	var url := _lumax_ui_base_url() + "/api/ui_config"
	var err: Error = _ui_http.request(url)
	if err != OK:
		push_warning("Lumax UI config: HTTP request failed err=%s url=%s" % [err, url])


func _on_ui_config_http_done(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		return
	if response_code != 200:
		return
	var txt := body.get_string_from_utf8()
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return
	var f := FileAccess.open(_UI_CONFIG_CACHE, FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()
	_apply_ui_config_dict(d)


func _play_sfx(sfx_name: String):
	if not _audio: return
	var path = "res://Mind/Sfx/" + sfx_name + ".wav"
	if FileAccess.file_exists(path):
		_audio.stream = load(path)
		# pop.wav: quiet UI tick (~10% linear); other SFX stay at default.
		_audio.volume_db = linear_to_db(0.1) if sfx_name == "pop" else 0.0
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
		s_btn.text = " " + _tab_display_name(str(sub))
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
			if _chat_column:
				_chat_column.visible = true
		"SOUL":
			_show_soul_panel()
		"SETTINGS":
			_show_settings_panel()
		"SYSTEM":
			_show_system_runtime_panel()
		"CHATTERBOX":
			_show_chatterbox_panel()
		"WIDGETS":
			_show_widgets_settings()
		"LOGS":
			_show_logs_panel()
		"SENTRY":
			_show_sentry_matrix()
		"VITALS":
			_show_sentry_matrix()
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
			if _chat_column:
				_chat_column.visible = true

func _clear_content_stack():
	for child in _content_stack.get_children():
		if child == _chat_column:
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
	_sync_quest_display_option_from_core()
	_sync_vision_feed_options_from_handler()

func _sync_quest_display_option_from_core() -> void:
	if _quest_display_ob == null:
		return
	var core: Node = get_tree().get_first_node_in_group("lumax_core")
	if core == null:
		return
	var qdm: Variant = core.get("quest_display_mode")
	if qdm == null:
		return
	_quest_display_ob.set_block_signals(true)
	_quest_display_ob.select(clampi(int(qdm), 0, _quest_display_ob.item_count - 1))
	_quest_display_ob.set_block_signals(false)


func _sync_vision_feed_options_from_handler() -> void:
	var vh: Node = get_tree().root.find_child("MultiVisionHandler", true, false)
	if vh == null:
		return
	if _user_vision_ob:
		var uvs: Variant = vh.get("user_vision_source")
		if uvs != null:
			_user_vision_ob.set_block_signals(true)
			_user_vision_ob.select(clampi(int(uvs), 0, _user_vision_ob.item_count - 1))
			_user_vision_ob.set_block_signals(false)
	if _jen_vision_ob:
		var jvs: Variant = vh.get("jen_vision_source")
		if jvs != null:
			_jen_vision_ob.set_block_signals(true)
			_jen_vision_ob.select(clampi(int(jvs), 0, _jen_vision_ob.item_count - 1))
			_jen_vision_ob.set_block_signals(false)


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

	var h_q := HBoxContainer.new(); settings_list.add_child(h_q)
	var l_q := Label.new(); l_q.text = "QUEST_DISPLAY_MODE"; l_q.custom_minimum_size.x = 200; h_q.add_child(l_q)
	var ob_q := OptionButton.new()
	ob_q.size_flags_horizontal = SIZE_EXPAND_FILL
	h_q.add_child(ob_q)
	ob_q.add_item("Auto (infer from OpenXR blend)")
	ob_q.add_item("Pure passthrough / AR")
	ob_q.add_item("XR mixed (additive + passthrough)")
	ob_q.add_item("VR immersive (opaque, PT off)")
	_quest_display_ob = ob_q
	ob_q.item_selected.connect(_on_quest_display_option_selected)

	var h_xrf := HBoxContainer.new(); settings_list.add_child(h_xrf)
	var l_xrf := Label.new(); l_xrf.text = "XR_FLOW_PROFILE"; l_xrf.custom_minimum_size.x = 200; h_xrf.add_child(l_xrf)
	var ob_xrf := OptionButton.new()
	ob_xrf.size_flags_horizontal = SIZE_EXPAND_FILL
	h_xrf.add_child(ob_xrf)
	ob_xrf.add_item("Off (no runtime XR tuning)")
	ob_xrf.add_item("Balanced (recommended)")
	ob_xrf.add_item("Performance (extra headroom)")
	ob_xrf.select(1)
	_xr_flow_ob = ob_xrf
	ob_xrf.item_selected.connect(_on_xr_flow_profile_option_selected)

	var h_uv := HBoxContainer.new(); settings_list.add_child(h_uv)
	var l_uv := Label.new(); l_uv.text = "USER_VISION_FEED"; l_uv.custom_minimum_size.x = 200; h_uv.add_child(l_uv)
	var ob_uv := OptionButton.new(); ob_uv.size_flags_horizontal = SIZE_EXPAND_FILL; h_uv.add_child(ob_uv)
	ob_uv.add_item("Auto (webcam if allowed, else headset)")
	ob_uv.add_item("PC screen / desktop")
	ob_uv.add_item("Webcam — user (primary feed)")
	ob_uv.add_item("Webcam — personal / 2nd cam")
	ob_uv.add_item("Headset / passthrough / XR / VR")
	_user_vision_ob = ob_uv
	ob_uv.item_selected.connect(_on_user_vision_option_selected)

	var h_jv := HBoxContainer.new(); settings_list.add_child(h_jv)
	var l_jv := Label.new(); l_jv.text = "JEN_VISION_FEED"; l_jv.custom_minimum_size.x = 200; h_jv.add_child(l_jv)
	var ob_jv := OptionButton.new(); ob_jv.size_flags_horizontal = SIZE_EXPAND_FILL; h_jv.add_child(ob_jv)
	ob_jv.add_item("Auto (webcam if allowed, else avatar head)")
	ob_jv.add_item("Personal / Jen-slot webcam")
	ob_jv.add_item("Avatar head in-world camera")
	_jen_vision_ob = ob_jv
	ob_jv.item_selected.connect(_on_jen_vision_option_selected)

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
		

func _on_quest_display_option_selected(idx: int) -> void:
	_play_sfx("pop")
	quest_display_mode_selected.emit(idx)
	add_message("SYSTEM", "QUEST_DISPLAY_MODE -> index " + str(idx))


func _on_xr_flow_profile_option_selected(idx: int) -> void:
	_play_sfx("pop")
	xr_flow_profile_selected.emit(idx)
	add_message("SYSTEM", "XR_FLOW_PROFILE -> index " + str(idx))


func _on_user_vision_option_selected(idx: int) -> void:
	_play_sfx("pop")
	user_vision_source_selected.emit(idx)
	add_message("SYSTEM", "USER_VISION_FEED -> " + str(idx))


func _on_jen_vision_option_selected(idx: int) -> void:
	_play_sfx("pop")
	jen_vision_source_selected.emit(idx)
	add_message("SYSTEM", "JEN_VISION_FEED -> " + str(idx))


func _load_system_runtime_prefs() -> Dictionary:
	if not FileAccess.file_exists(_SYSTEM_PREFS_PATH):
		return {}
	var raw := FileAccess.get_file_as_string(_SYSTEM_PREFS_PATH)
	var j = JSON.parse_string(raw)
	return j if j is Dictionary else {}


func _save_system_runtime_prefs() -> void:
	var d: Dictionary = {
		"model_path": _system_model_path_edit.text if _system_model_path_edit else "",
		"mmproj_path": _system_mmproj_path_edit.text if _system_mmproj_path_edit else "",
		"native_vision": _system_native_vision_cb.button_pressed if _system_native_vision_cb else false,
		"local_caption": _system_local_caption_cb.button_pressed if _system_local_caption_cb else true,
		"chat_provider": _system_chat_provider_ob.get_item_text(_system_chat_provider_ob.selected) if _system_chat_provider_ob else "local",
	}
	var f := FileAccess.open(_SYSTEM_PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func _wire_system_synapse_once() -> void:
	if _system_synapse_signals_done:
		return
	var syn: Node = get_tree().get_first_node_in_group("lumax_synapse")
	if syn == null:
		return
	if syn.has_signal("soul_runtime_config_received") and not syn.soul_runtime_config_received.is_connected(_on_soul_runtime_config_received):
		syn.soul_runtime_config_received.connect(_on_soul_runtime_config_received)
	if syn.has_signal("soul_runtime_status_received") and not syn.soul_runtime_status_received.is_connected(_on_soul_runtime_status_received):
		syn.soul_runtime_status_received.connect(_on_soul_runtime_status_received)
	_system_synapse_signals_done = true


func _on_soul_runtime_config_received(data: Dictionary) -> void:
	var ok: bool = bool(data.get("ok", true)) and str(data.get("mode", "")) != "ERROR"
	var msg: String = str(data.get("response", data.get("body", JSON.stringify(data))))
	if _system_status_label:
		_system_status_label.text = ("OK: " if ok else "ERR: ") + msg.substr(0, 220)
	add_message("SYSTEM", "SOUL_RUNTIME " + ("OK " if ok else "FAIL ") + msg.substr(0, 120))
	if ok:
		_save_system_runtime_prefs()


func _on_soul_runtime_status_received(data: Dictionary) -> void:
	if data.has("error"):
		if _system_status_label:
			_system_status_label.text = "Status: " + str(data)
		return
	if _system_model_path_edit and data.get("model_path"):
		_system_model_path_edit.text = str(data["model_path"])
	if _system_mmproj_path_edit:
		_system_mmproj_path_edit.text = str(data.get("LUMAX_MMPROJ_PATH", ""))
	if _system_native_vision_cb:
		_system_native_vision_cb.set_block_signals(true)
		_system_native_vision_cb.button_pressed = bool(data.get("LUMAX_GGUF_NATIVE_VISION", false))
		_system_native_vision_cb.set_block_signals(false)
	if _system_local_caption_cb:
		_system_local_caption_cb.set_block_signals(true)
		_system_local_caption_cb.button_pressed = bool(data.get("LUMAX_LOCAL_VISION_ENABLED", true))
		_system_local_caption_cb.set_block_signals(false)
	if _system_chat_provider_ob:
		var cp := str(data.get("LUMAX_CHAT_PROVIDER", "local"))
		for i in range(_system_chat_provider_ob.item_count):
			if _system_chat_provider_ob.get_item_text(i) == cp:
				_system_chat_provider_ob.select(i)
				break
	if _system_status_label:
		_system_status_label.text = "Synced: " + str(data.get("engine_type", "?")) + " mmproj=" + str(data.get("gguf_multimodal_ready", false))


func _apply_system_runtime_pressed() -> void:
	_wire_system_synapse_once()
	var syn: Node = get_tree().get_first_node_in_group("lumax_synapse")
	if syn == null or not syn.has_method("apply_soul_runtime_config"):
		add_message("SYSTEM", "SOUL_RUNTIME: no Synapse (lumax_synapse group)")
		return
	var payload: Dictionary = {}
	if _system_preset_ob == null:
		return
	var idx: int = _system_preset_ob.selected
	match idx:
		0:
			var p := _system_model_path_edit.text.strip_edges() if _system_model_path_edit else ""
			if p.is_empty():
				add_message("SYSTEM", "SOUL_RUNTIME: set Custom GGUF path or pick a preset")
				return
			payload["model_path"] = p
		1:
			payload["model_path"] = _PATH_GEMMA_HERETIC_DEFAULT
		2:
			payload["model"] = "nexus_v1"
		3:
			payload["model"] = "soul_4b_q6"
		4:
			payload["model"] = "ratatosk_tiny"
		5:
			payload["model"] = "ollama_fallback"
		_:
			add_message("SYSTEM", "SOUL_RUNTIME: invalid preset")
			return
	var mm := _system_mmproj_path_edit.text.strip_edges() if _system_mmproj_path_edit else ""
	if not mm.is_empty():
		payload["mmproj_path"] = mm
	if _system_native_vision_cb:
		payload["native_vision"] = _system_native_vision_cb.button_pressed
	if _system_local_caption_cb:
		payload["local_vision_caption"] = _system_local_caption_cb.button_pressed
	if _system_chat_provider_ob:
		payload["chat_provider"] = _system_chat_provider_ob.get_item_text(_system_chat_provider_ob.selected)
	_play_sfx("pop")
	syn.apply_soul_runtime_config(payload)


func _on_system_preset_selected(idx: int) -> void:
	if idx == 1 and _system_model_path_edit:
		_system_model_path_edit.text = _PATH_GEMMA_HERETIC_DEFAULT
	_play_sfx("pop")


func _show_system_runtime_panel() -> void:
	var panel: Control = _content_stack.get_node_or_null("SystemRuntimePanel")
	if not panel:
		panel = ScrollContainer.new()
		panel.name = "SystemRuntimePanel"
		panel.set_anchors_preset(PRESET_FULL_RECT)
		_content_stack.add_child(panel)
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		panel.add_child(vbox)
		var title := Label.new()
		title.text = "SOUL_RUNTIME // COGNITIVE_CONFIG"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title)
		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "Hot-reload local GGUF + vision flags (Docker soul :8000). Paths are sent to the PC host; map them to your container or run native."
		vbox.add_child(hint)
		var prefs := _load_system_runtime_prefs()
		var h_pre := HBoxContainer.new()
		vbox.add_child(h_pre)
		var l_pre := Label.new()
		l_pre.text = "PRESET"
		l_pre.custom_minimum_size.x = 120
		h_pre.add_child(l_pre)
		_system_preset_ob = OptionButton.new()
		_system_preset_ob.size_flags_horizontal = SIZE_EXPAND_FILL
		h_pre.add_child(_system_preset_ob)
		_system_preset_ob.add_item("Custom (path below)")
		_system_preset_ob.add_item("Gemma 4 E2B Heretic (Q4_K_M)")
		_system_preset_ob.add_item("Nexus v1 (GGUF in model dir)")
		_system_preset_ob.add_item("Soul 4B Q6")
		_system_preset_ob.add_item("Ratatosk 1B tiny")
		_system_preset_ob.add_item("Ollama relay (no GGUF reload)")
		_system_preset_ob.item_selected.connect(_on_system_preset_selected)
		var h_m := HBoxContainer.new()
		vbox.add_child(h_m)
		var l_m := Label.new()
		l_m.text = "GGUF_PATH"
		l_m.custom_minimum_size.x = 120
		h_m.add_child(l_m)
		_system_model_path_edit = LineEdit.new()
		_system_model_path_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		_system_model_path_edit.placeholder_text = "Absolute path to .gguf on the soul host"
		_system_model_path_edit.text = str(prefs.get("model_path", _PATH_GEMMA_HERETIC_DEFAULT))
		h_m.add_child(_system_model_path_edit)
		var h_mp := HBoxContainer.new()
		vbox.add_child(h_mp)
		var l_mp := Label.new()
		l_mp.text = "MMPROJ_PATH"
		l_mp.custom_minimum_size.x = 120
		h_mp.add_child(l_mp)
		_system_mmproj_path_edit = LineEdit.new()
		_system_mmproj_path_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		_system_mmproj_path_edit.placeholder_text = "Optional mmproj.gguf (native VL)"
		_system_mmproj_path_edit.text = str(prefs.get("mmproj_path", ""))
		h_mp.add_child(_system_mmproj_path_edit)
		var h_nv := HBoxContainer.new()
		vbox.add_child(h_nv)
		_system_native_vision_cb = CheckButton.new()
		_system_native_vision_cb.text = "LUMAX_GGUF_NATIVE_VISION (mmproj + Llava handler)"
		_system_native_vision_cb.button_pressed = bool(prefs.get("native_vision", false))
		h_nv.add_child(_system_native_vision_cb)
		var h_lc := HBoxContainer.new()
		vbox.add_child(h_lc)
		_system_local_caption_cb = CheckButton.new()
		_system_local_caption_cb.text = "Local caption helper (when not native VL)"
		_system_local_caption_cb.button_pressed = bool(prefs.get("local_caption", true))
		h_lc.add_child(_system_local_caption_cb)
		var h_cp := HBoxContainer.new()
		vbox.add_child(h_cp)
		var l_cp := Label.new()
		l_cp.text = "CHAT_PROVIDER"
		l_cp.custom_minimum_size.x = 120
		h_cp.add_child(l_cp)
		_system_chat_provider_ob = OptionButton.new()
		_system_chat_provider_ob.size_flags_horizontal = SIZE_EXPAND_FILL
		h_cp.add_child(_system_chat_provider_ob)
		for prov in ["local", "openai", "gemini", "extra", "rotate", "splice"]:
			_system_chat_provider_ob.add_item(prov)
		var cp := str(prefs.get("chat_provider", "local"))
		for i in range(_system_chat_provider_ob.item_count):
			if _system_chat_provider_ob.get_item_text(i) == cp:
				_system_chat_provider_ob.select(i)
				break
		var h_apply := HBoxContainer.new()
		vbox.add_child(h_apply)
		var apply_b := Button.new()
		apply_b.text = "APPLY + RELOAD SOUL"
		apply_b.custom_minimum_size = Vector2(280, 48)
		h_apply.add_child(apply_b)
		apply_b.pressed.connect(_apply_system_runtime_pressed)
		var refresh_b := Button.new()
		refresh_b.text = "Refresh status"
		refresh_b.pressed.connect(_refresh_system_runtime_status)
		h_apply.add_child(refresh_b)
		_system_status_label = Label.new()
		_system_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_system_status_label.text = "—"
		vbox.add_child(_system_status_label)
		var sep_tts := HSeparator.new()
		vbox.add_child(sep_tts)
		var tts_title := Label.new()
		tts_title.text = "TTS_STACK // MOUTH (:8002)"
		tts_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(tts_title)
		var tts_hint := Label.new()
		tts_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tts_hint.text = "Applies routing file only (turbo vs chatterbox HTTP). Full GPU Docker switch: PC Web UI port 8080 → Utils, or host script switch_gpu_tts_stack.ps1."
		vbox.add_child(tts_hint)
		var h_tts := HBoxContainer.new()
		vbox.add_child(h_tts)
		var l_tts := Label.new()
		l_tts.text = "BACKEND"
		l_tts.custom_minimum_size.x = 100
		h_tts.add_child(l_tts)
		_tts_backend_ob = OptionButton.new()
		_tts_backend_ob.size_flags_horizontal = SIZE_EXPAND_FILL
		h_tts.add_child(_tts_backend_ob)
		_tts_backend_ob.add_item("turbo (XTTS)")
		_tts_backend_ob.add_item("chatterbox (Resemble)")
		var tts_b := Button.new()
		tts_b.text = "Apply"
		tts_b.custom_minimum_size = Vector2(100, 36)
		h_tts.add_child(tts_b)
		tts_b.pressed.connect(_apply_tts_backend_vr)
	panel.visible = true
	_wire_system_synapse_once()
	_refresh_system_runtime_status()
	_refresh_tts_backend_select_vr()


func _refresh_system_runtime_status() -> void:
	_wire_system_synapse_once()
	var syn: Node = get_tree().get_first_node_in_group("lumax_synapse")
	if syn and syn.has_method("fetch_soul_runtime_status"):
		syn.fetch_soul_runtime_status()


func _mouth_base_url() -> String:
	var syn: Node = get_tree().get_first_node_in_group("lumax_synapse")
	if syn == null:
		return "http://127.0.0.1:8002"
	var ip := str(syn.get("server_ip")).strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	return "http://" + ip + ":8002"


## Resemble Chatterbox Web UI (host :8004). Override with LUMAX_CHATTERBOX_UI_URL; port with CHATTERBOX_UI_PORT.
func _chatterbox_ui_url() -> String:
	var o := str(OS.get_environment("LUMAX_CHATTERBOX_UI_URL")).strip_edges()
	if o != "" and (o.begins_with("http://") or o.begins_with("https://")):
		return o.trim_suffix("/") + "/"
	var port := str(OS.get_environment("CHATTERBOX_UI_PORT")).strip_edges()
	if port.is_empty():
		port = "8004"
	var syn: Node = get_tree().get_first_node_in_group("lumax_synapse")
	var ip := "127.0.0.1"
	if syn != null:
		var sip := str(syn.get("server_ip")).strip_edges()
		if not sip.is_empty():
			ip = sip
	return "http://" + ip + ":" + port + "/"


func _show_chatterbox_panel() -> void:
	var panel: Control = _content_stack.get_node_or_null("ChatterboxPanel")
	if not panel:
		panel = ScrollContainer.new()
		panel.name = "ChatterboxPanel"
		panel.set_anchors_preset(PRESET_FULL_RECT)
		_content_stack.add_child(panel)
		var vbox := VBoxContainer.new()
		vbox.name = "ChatterboxVBox"
		vbox.size_flags_horizontal = SIZE_EXPAND_FILL
		panel.add_child(vbox)
		var title := Label.new()
		title.text = "CHATTERBOX // TTS UI"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(title)
		var hint := Label.new()
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "VR cannot embed the Chatterbox web app. Use the PC Web UI (port 8080) CHATTERBOX tab for an embedded view, or open the URL below on your desktop."
		vbox.add_child(hint)
		var url_lbl := Label.new()
		url_lbl.name = "ChatterboxUrlLabel"
		url_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(url_lbl)
		var open_b := Button.new()
		open_b.text = "Open Chatterbox UI in browser"
		open_b.custom_minimum_size = Vector2(280, 48)
		open_b.pressed.connect(func():
			_play_sfx("pop")
			OS.shell_open(_chatterbox_ui_url()))
		vbox.add_child(open_b)
	var url_node: Label = panel.get_node_or_null("ChatterboxVBox/ChatterboxUrlLabel") as Label
	if url_node:
		url_node.text = "URL: " + _chatterbox_ui_url()
	panel.visible = true


func _refresh_tts_backend_select_vr() -> void:
	if _tts_get_http == null:
		return
	var url := _mouth_base_url() + "/tts/backend"
	var e := _tts_get_http.request(url)
	if e != OK:
		add_message("SYSTEM", "TTS_BACKEND GET err " + str(e))


func _on_tts_get_http_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _tts_backend_ob == null:
		return
	if code != 200:
		add_message("SYSTEM", "TTS_BACKEND GET HTTP " + str(code))
		return
	var j := JSON.new()
	if j.parse(body.get_string_from_utf8()) != OK:
		return
	var data = j.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	var b := str(data.get("backend", "turbo"))
	_tts_backend_ob.select(0 if b == "turbo" else 1)


func _apply_tts_backend_vr() -> void:
	if _tts_put_http == null or _tts_backend_ob == null:
		return
	var backend := "turbo" if _tts_backend_ob.selected == 0 else "chatterbox"
	var payload := JSON.stringify({"backend": backend})
	var url := _mouth_base_url() + "/tts/backend"
	var headers := PackedStringArray(["Content-Type: application/json"])
	var e := _tts_put_http.request(url, headers, HTTPClient.METHOD_PUT, payload)
	if e != OK:
		add_message("SYSTEM", "TTS_BACKEND PUT err " + str(e))


func _on_tts_put_http_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code == 200:
		add_message("SYSTEM", "TTS_BACKEND " + body.get_string_from_utf8().substr(0, 160))
	else:
		add_message("SYSTEM", "TTS_BACKEND PUT HTTP " + str(code) + " " + body.get_string_from_utf8().substr(0, 120))


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
		panel = VBoxContainer.new(); panel.name = "SentryMatrix"; _content_stack.add_child(panel)
		var title = Label.new()
		title.text = "VITALS // HW HEALTH"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 16)
		panel.add_child(title)
		var grid = GridContainer.new(); grid.columns = 2; grid.name = "VitalsGrid"; panel.add_child(grid)
		var metrics = ["VRAM_BUFF", "CORE_SYNC", "SOUL_CPU_PCT", "HOST_CPU_PCT", "SYS_STRESS", "NET_LATENCY", "DISK_I/O", "THERMAL_STATE", "UPLOAD_FLUX", "DOWN_FLUX", "RESONANCE", "USER_IDLE", "MIND_DEPTH"]
		for m in metrics:
			var p = PanelContainer.new(); grid.add_child(p)
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
	var soul_cpu = _to_float_vital(data.get("SOUL_CPU_PCT", -1.0))
	var host_cpu = _to_float_vital(data.get("HOST_CPU_PCT", -1.0))
	if soul_cpu >= 0.0:
		_last_soul_cpu_pct = soul_cpu
	if host_cpu >= 0.0:
		_last_host_cpu_pct = host_cpu
	_update_stress_ui_state()

func _to_float_vital(v: Variant) -> float:
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	var s := str(v).replace("%", "").strip_edges()
	if not s.is_valid_float():
		return -1.0
	return s.to_float()

func _update_stress_ui_state() -> void:
	var soul_cpu := _last_soul_cpu_pct
	if soul_cpu < 0.0:
		return
	if soul_cpu >= STRESS_HOT_PCT:
		_stress_latched = true
	elif _stress_latched and soul_cpu <= STRESS_CLEAR_PCT:
		_stress_latched = false
	if _stress_banner:
		_stress_banner.visible = _stress_latched
		if _stress_latched:
			var host_txt := ("%.0f%%" % _last_host_cpu_pct) if _last_host_cpu_pct >= 0.0 else "?"
			_stress_banner.text = "GUARDIAN ALERT: HIGH LOAD (Soul %.0f%% | Host %s)" % [soul_cpu, host_txt]
	if _vitals_data.has("SYS_STRESS"):
		var lab: Label = _vitals_data["SYS_STRESS"]
		if lab:
			lab.text = "HIGH" if _stress_latched else "NORMAL"
			lab.add_theme_color_override("font_color", Color(1.0, 0.32, 0.32) if _stress_latched else Color(0.5, 1.0, 0.7))
	_update_hub_tab_visuals()

func _update_hub_tab_visuals() -> void:
	for hub in _hub_buttons.keys():
		var btn: Button = _hub_buttons[hub]
		if btn == null:
			continue
		btn.remove_theme_color_override("font_color")
	if _stress_latched:
		if _hub_buttons.has("BODY") and _hub_buttons["BODY"]:
			(_hub_buttons["BODY"] as Button).add_theme_color_override("font_color", Color(1.0, 0.28, 0.28))
		if _hub_buttons.has("CORE") and _hub_buttons["CORE"]:
			(_hub_buttons["CORE"] as Button).add_theme_color_override("font_color", Color(1.0, 0.55, 0.18))

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
		display_box.name = "DisplayBox"
		display_box.custom_minimum_size = Vector2(0, 250)
		var db_style = StyleBoxFlat.new(); db_style.bg_color = Color(0,0,0,0.5); db_style.border_width_bottom = 2; db_style.border_color = Color(0, 0.9, 1.0, 0.4)
		display_box.add_theme_stylebox_override("panel", db_style)
		panel.add_child(display_box)
		
		var viewport_label = Label.new(); viewport_label.name = "StateLabel"; viewport_label.text = "[ MEDIA_BUFFER_EMPTY ]"; viewport_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; viewport_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		display_box.add_child(viewport_label)
		
		# Prompt / Command Entry
		var input_box = HBoxContainer.new()
		input_box.name = "InputBox"
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
		bottom_strip.name = "BottomStrip"
		panel.add_child(bottom_strip)
		
		var action_panel = GridContainer.new()
		action_panel.name = "ActionsGrid"; action_panel.columns = 3; action_panel.size_flags_horizontal = SIZE_EXPAND_FILL
		action_panel.add_theme_constant_override("h_separation", 10)
		bottom_strip.add_child(action_panel)
		
	panel.visible = true
	var p_title = panel.get_node("TitleLabel")
	var p_state = panel.get_node_or_null("DisplayBox/StateLabel")
	var p_actions = panel.get_node_or_null("BottomStrip/ActionsGrid")
	var gen_btn = panel.get_node_or_null("InputBox/GenButton")
	var p_input = panel.get_node_or_null("InputBox/PromptInput")
	
	p_title.text = "NEURAL EXTENSION // " + type
	if p_state: p_state.text = "[ " + type + "_BUFFER_EMPTY ]"
	
	# Clear old buttons
	if p_actions:
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
func _show_agency_panel():
	if _chat_column:
		_chat_column.visible = true
	add_message("AGENCY", "Autonomous intent engaged.")

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
	var who_upper = who.to_upper()
	var color = "#00f3ff" if who_upper.contains("YOU") or who_upper == "USER" or who_upper == "ME" else "#ff007f"
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
		var status = Label.new(); status.name = "FileStatus"; status.text = "Tap a file to request/open."; panel.add_child(status)
		var list = ItemList.new(); list.name = "FileList"; list.size_flags_vertical = SIZE_EXPAND_FILL; panel.add_child(list)
		list.item_activated.connect(func(idx):
			_on_file_activated(list.get_item_text(idx))
		)
	
	panel.visible = true
	var st: Label = panel.get_node_or_null("FileStatus") as Label
	if st:
		st.text = "Loading file list..."
	files_requested.emit()

func _on_files_received(files: Array):
	var panel = _content_stack.get_node_or_null("FilesPanel")
	if panel:
		var list = panel.get_node("FileList") as ItemList
		list.clear()
		for f in files: list.add_item(f)
		var st: Label = panel.get_node_or_null("FileStatus") as Label
		if st:
			st.text = "Loaded " + str(files.size()) + " entries."


func _on_file_activated(path: String) -> void:
	var clean := path.strip_edges()
	var panel = _content_stack.get_node_or_null("FilesPanel")
	var st: Label = null
	if panel:
		st = panel.get_node_or_null("FileStatus") as Label
	if clean.is_empty():
		if st:
			st.text = "No file selected."
		return
	file_activation_requested.emit(clean)
	if st:
		st.text = "Requested: " + clean
	# Lightweight local behavior: open obvious local paths/URLs directly when safe.
	var is_http := clean.begins_with("http://") or clean.begins_with("https://")
	if is_http:
		OS.shell_open(clean)
		add_message("SYSTEM", "OPEN_URL: " + clean)
		if st:
			st.text = "Opened URL."
		return
	var abs_path := clean
	if clean.begins_with("res://") or clean.begins_with("user://"):
		abs_path = ProjectSettings.globalize_path(clean)
	if clean.begins_with("res://") or clean.begins_with("user://") or clean.is_absolute_path():
		if FileAccess.file_exists(abs_path):
			OS.shell_open(abs_path)
			add_message("SYSTEM", "OPEN_FILE: " + clean)
			if st:
				st.text = "Opened local file."
			return
	add_message("SYSTEM", "FILE_REQUESTED: " + clean)

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
				b.tooltip_text = "Send your vision to Jen. Pick feed in CORE → SETTINGS: PC screen, user webcam, personal/2nd webcam, or headset (passthrough / XR / VR)."
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
			elif e == "AWE" or e == "CURIOUS" or e == "CONTEMPLATE":
				b.add_theme_color_override("font_color", Color(0.82, 0.96, 1.0))
				b.tooltip_text = "Wired to sensory channel."
				b.pressed.connect(_on_emotion_stimulus_pressed.bind(e))
			else:
				b.pressed.connect(func(): add_message("SYSTEM", "STIMULATING_EMOTION: " + e))
	panel.visible = true


func _on_emotion_stimulus_pressed(emotion_name: String) -> void:
	var em := emotion_name.strip_edges()
	if em.is_empty():
		return
	emotion_stimulus_requested.emit(em)
	add_message("SYSTEM", "EMOTION_STIMULUS_REQUESTED: " + em)

func update_shared_views(user_tex: Texture2D, jen_tex: Texture2D):
	var panel = _content_stack.get_node_or_null("ConferencePanel")
	if not panel:
		return
	var grid = panel.get_node_or_null("ConfPanel/HGrid")
	if not grid:
		return
	var user_pov = grid.get_node_or_null("UserPOV")
	var jen_pov = grid.get_node_or_null("JenPOV")
	if user_pov and jen_pov:
		user_pov.texture = user_tex
		jen_pov.texture = jen_tex
		panel.show()

func update_buffer(text: String): 
	if input_display: input_display.text = "> " + text + "_"
