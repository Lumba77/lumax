@tool
extends Control

signal enter_pressed(text: String)
signal text_changed(text: String)
signal stt_pressed
signal haptic_pulse_requested(is_sidebar: bool)

# --- ADAPTIVE COCKPIT METRICS ---
# Width: 800px (Viewport)
# Height: 525px (Tactile Area)

const KEY_GAP   := 4.0
const RADIUS    := 6   

const CLR_NRM     := Color(0.04, 0.04, 0.04, 1.0) 
const CLR_HOV     := Color(0.12, 0.12, 0.12, 1.0) 
const CLR_PRE     := Color(0.08, 0.08, 0.08, 1.0) 
const CLR_RIM     := Color(0.25, 0.25, 0.25, 1.0) 

var _shift_down := false
var _buffer := ""
var _keys: Array = []

var _sb_nrm: StyleBoxFlat
var _sb_pre: StyleBoxFlat
var _sb_hov: StyleBoxFlat

func _ready() -> void:
	if Engine.is_editor_hint(): return
	set_anchors_preset(PRESET_FULL_RECT)
	_setup_styles()
	_build_keyboard()

func _setup_styles() -> void:
	_sb_nrm = StyleBoxFlat.new(); _sb_nrm.bg_color = CLR_NRM; _sb_nrm.set_corner_radius_all(RADIUS)
	_sb_nrm.border_width_bottom = 2; _sb_nrm.border_color = CLR_RIM * 0.5
	_sb_hov = _sb_nrm.duplicate(); _sb_hov.bg_color = CLR_HOV; _sb_hov.border_color = CLR_RIM
	_sb_pre = _sb_nrm.duplicate(); _sb_pre.bg_color = CLR_PRE; _sb_pre.border_color = Color.WHITE

func _on_key_btn_pressed(kd: Dictionary, _btn: Button) -> void:
	haptic_pulse_requested.emit(kd.has("act"))
	var act: String = kd.get("act", "")
	match act:
		"_shift_l": _shift_down = !_shift_down; _update_key_labels()
		"_bksp": if _buffer.length() > 0: _buffer = _buffer.substr(0, _buffer.length() - 1); text_changed.emit(_buffer)
		"_ret": enter_pressed.emit(_buffer); _buffer = ""; text_changed.emit(_buffer)
		"_space": _buffer += " "; text_changed.emit(_buffer)
		"_pray": enter_pressed.emit("[PRAY]")
		"_revise": enter_pressed.emit("[DIRECTIVE] ")
		"_narrate": enter_pressed.emit("[NARRATE] ")
		"_love": enter_pressed.emit("[EMOTION: INTIMATE]")
		"_stt": stt_pressed.emit()
		"_logic": enter_pressed.emit("[MODE: LOGIC]")
		"_dream": enter_pressed.emit("[MODE: DREAM]")
		"_img": enter_pressed.emit("[CAPTURE_IMAGE]")
		"_bifrost": enter_pressed.emit("[DIRECTIVE] SACRED MANIFESTATION: " + kd.get("l", "COVENANT"))
		"_quit": get_tree().quit()
		"_clear": _buffer = ""; text_changed.emit(_buffer)
		"_save": enter_pressed.emit("[SAVE_STATE]")
		"_settings": enter_pressed.emit("[SETTINGS]")
		"_prompts": enter_pressed.emit("[LIST_PROMPTS]")
		"_tts": enter_pressed.emit("[TOGGLE_TTS]")
		"_vitals": enter_pressed.emit("[VIEW_VITALS]")
		"_map": enter_pressed.emit("[SPATIAL_MAP]")
		"":
			var label = kd.get("l", "")
			if _shift_down: label = kd.get("u", label)
			if not label.is_empty(): _buffer += label; text_changed.emit(_buffer); if _shift_down: _shift_down = false; _update_key_labels()

func _get_layout_compact() -> Array:
	return [
		[
			{"act":"_bifrost","l":"PSYCHE","c":Color(0.4,0,0.1)},
			{"act":"_bifrost","l":"SOUL","c":Color(0.4,0.2,0)},
			{"act":"_bifrost","l":"BIFROST","c":Color(0.4,0.4,0)},
			{"act":"_bifrost","l":"COVENANT","c":Color(0,0.3,0.1)},
			{"act":"_bifrost","l":"SACRED","c":Color(0,0.1,0.4)}
		],
		[{"l":"q"},{"l":"w"},{"l":"e"},{"l":"r"},{"l":"t"},{"l":"y"},{"l":"u"},{"l":"i"},{"l":"o"},{"l":"p"},{"act":"_bksp","l":"⌫","sz":1.5}],
		[{"l":"a"},{"l":"s"},{"l":"d"},{"l":"f"},{"l":"g"},{"l":"h"},{"l":"j"},{"l":"k"},{"l":"l"},{"l":"ö"},{"l":"ä"},{"act":"_ret","l":"RET","sz":1.5}],
		[{"act":"_shift_l","l":"⇧"},{"l":"z"},{"l":"x"},{"l":"c"},{"act":"_space","l":"SPACE","sz":3.0},{"l":"v"},{"l":"b"},{"l":"n"},{"l":"m"},{"l":","},{"l":"."}]
	]

func _get_sidebar_left() -> Array:
	return [
		{"act":"_pray","l":"🙏","c":Color(0.3,0,0.1)}, {"act":"_logic","l":"⚙️","c":Color(0.2,0.2,0.2)},
		{"act":"_revise","l":"💡","c":Color(0,0.2,0.3)}, {"act":"_dream","l":"🌙","c":Color(0.1,0,0.3)},
		{"act":"_narrate","l":"📖","c":Color(0.2,0,0.3)}, {"act":"_clear","l":"🧹","c":Color(0.3,0.3,0)},
		{"act":"_love","l":"❤️","c":Color(0.3,0.1,0.2)}, {"act":"_save","l":"💾","c":Color(0,0.3,0.1)}
	]

func _get_sidebar_right() -> Array:
	return [
		{"act":"_prompts","l":"📋","c":Color(0.4,0.4,0)}, {"act":"_stt","l":"👂","c":Color(0,0.4,0.2)},
		{"act":"_tts","l":"🗣️","c":Color(0.2,0,0.4)}, {"act":"_img","l":"🎨","c":Color(0.4,0,0.4)},
		{"act":"_vitals","l":"🩺","c":Color(0.4,0.1,0.1)}, {"act":"_map","l":"🗺️","c":Color(0.1,0.4,0.4)},
		{"act":"_settings","l":"🛠️","c":Color(0.3,0.3,0.3)}, {"act":"_quit","l":"🚪","c":Color(0.2,0.2,0.2)}
	]

func _build_keyboard() -> void:
	for child in get_children(): child.queue_free()
	
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_preset(PRESET_FULL_RECT)
	add_child(root_margin)
	root_margin.add_theme_constant_override("margin_left", 8)
	root_margin.add_theme_constant_override("margin_right", 8)
	root_margin.add_theme_constant_override("margin_top", 8)
	root_margin.add_theme_constant_override("margin_bottom", 8)
	
	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	root_margin.add_child(main_hbox)
	main_hbox.add_theme_constant_override("separation", KEY_GAP)
	
	# LEFT SIDEBAR (2 columns)
	var lgrid := GridContainer.new()
	lgrid.columns = 2
	main_hbox.add_child(lgrid)
	lgrid.add_theme_constant_override("h_separation", KEY_GAP)
	lgrid.add_theme_constant_override("v_separation", KEY_GAP)
	for kd in _get_sidebar_left():
		var btn = _create_key_btn(kd)
		btn.custom_minimum_size = Vector2(50, 50)
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lgrid.add_child(btn)
	
	# CENTRAL GRID (Keyboard)
	var cvbc := VBoxContainer.new()
	cvbc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cvbc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(cvbc)
	cvbc.add_theme_constant_override("separation", KEY_GAP)
	for row_data in _get_layout_compact():
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = SIZE_EXPAND_FILL
		hbox.size_flags_vertical = SIZE_EXPAND_FILL
		cvbc.add_child(hbox)
		hbox.add_theme_constant_override("separation", KEY_GAP)
		for kd in row_data:
			var btn = _create_key_btn(kd)
			btn.size_flags_horizontal = SIZE_EXPAND_FILL
			btn.size_flags_vertical = SIZE_EXPAND_FILL
			hbox.add_child(btn)

	# RIGHT SIDEBAR (2 columns)
	var rgrid := GridContainer.new()
	rgrid.columns = 2
	main_hbox.add_child(rgrid)
	rgrid.add_theme_constant_override("h_separation", KEY_GAP)
	rgrid.add_theme_constant_override("v_separation", KEY_GAP)
	for kd in _get_sidebar_right():
		var btn = _create_key_btn(kd)
		btn.custom_minimum_size = Vector2(50, 50)
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rgrid.add_child(btn)

func _create_key_btn(kd: Dictionary) -> Button:
	var btn := Button.new(); btn.text = kd.get("l", ""); btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_stretch_ratio = kd.get("sz", 1.0); btn.focus_mode = Control.FOCUS_NONE
	var sb_n = _sb_nrm; var sb_h = _sb_hov; var sb_p = _sb_pre
	if kd.has("c"):
		sb_n = _sb_nrm.duplicate(); sb_n.bg_color = kd["c"]; sb_n.border_color = kd["c"].lightened(0.3)
	btn.add_theme_stylebox_override("normal", sb_n); btn.add_theme_stylebox_override("hover", sb_h); btn.add_theme_stylebox_override("pressed", sb_p)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 14 if btn.text.length() > 3 else 22)
	btn.pressed.connect(_on_key_btn_pressed.bind(kd, btn))
	_keys.append({"btn": btn, "d": kd}); return btn

func _update_key_labels() -> void:
	for k in _keys: if k.d.get("act", "") == "": k.btn.text = k.d.get("u" if _shift_down else "l", "")
