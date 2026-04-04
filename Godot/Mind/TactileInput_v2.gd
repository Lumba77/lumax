@tool
extends Control

signal enter_pressed(text: String)
signal text_changed(text: String)
signal stt_pressed
signal haptic_pulse_requested(is_sidebar: bool)
signal bond_slider_changed(value: float)
signal trait_slider_changed(trait_name: String, value: float)

# --- ADAPTIVE COCKPIT METRICS ---
# Width: 800px (Viewport)
# Height: 525px (Tactile Area)

const KEY_GAP   := 4.0
const RADIUS    := 6   

const CLR_NRM     := Color(0.0, 0.0, 0.0, 1.0) # Black base
const CLR_HOV     := Color(0.1, 0.1, 0.1, 1.0) 
const CLR_PRE     := Color(0.2, 0.2, 0.2, 1.0) 
const CLR_RIM     := Color(0.2, 0.2, 0.2, 1.0)  

var _shift_down := false
var _buffer := ""
var _keys: Array = []
var _buffer_label: Label

var _sb_nrm: StyleBoxFlat
var _sb_pre: StyleBoxFlat
var _sb_hov: StyleBoxFlat
var _bg_style: StyleBoxFlat
var _buffer_style: StyleBoxFlat

var _user_preview: TextureRect
var _jen_preview: TextureRect

func _ready() -> void:
	if Engine.is_editor_hint(): return
	set_anchors_preset(PRESET_FULL_RECT)
	_setup_styles()
	_build_keyboard()

func _setup_styles() -> void:
	_sb_nrm = StyleBoxFlat.new(); _sb_nrm.bg_color = CLR_NRM; _sb_nrm.set_corner_radius_all(RADIUS)
	_sb_nrm.border_width_bottom = 2; _sb_nrm.border_color = CLR_RIM
	_sb_hov = _sb_nrm.duplicate(); _sb_hov.bg_color = CLR_HOV; _sb_hov.border_color = Color.WHITE
	_sb_pre = _sb_nrm.duplicate(); _sb_pre.bg_color = CLR_PRE; _sb_pre.border_color = Color.WHITE
	
	_bg_style = StyleBoxFlat.new()
	_bg_style.bg_color = Color(0, 0.01, 0.05, 0.9) 
	_bg_style.border_width_left = 4; _bg_style.border_color = Color(0.1, 0.1, 0.3, 0.5)

	_buffer_style = StyleBoxFlat.new()
	_buffer_style.bg_color = Color(0.1, 0.1, 0.1, 0.3)
	_buffer_style.set_corner_radius_all(5)

var _last_pulse_time := 0.0

func _on_key_btn_pressed(kd: Dictionary, _btn: Button) -> void:
	var now = Time.get_ticks_msec()
	if now - _last_pulse_time > 100:
		haptic_pulse_requested.emit(kd.has("act"))
		_last_pulse_time = now
	var act: String = kd.get("act", "")
	match act:
		"_shift_l": _shift_down = !_shift_down; _update_key_labels()
		"_bksp": if _buffer.length() > 0: _buffer = _buffer.substr(0, _buffer.length() - 1); _on_buffer_updated()
		"_ret": enter_pressed.emit(_buffer); _buffer = ""; _on_buffer_updated()
		"_space": _buffer += " "; _on_buffer_updated()
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
		"_clear": _buffer = ""; _on_buffer_updated()
		"_save": enter_pressed.emit("[SAVE_STATE]")
		"_settings": enter_pressed.emit("[SETTINGS]")
		"_prompts": enter_pressed.emit("[LIST_PROMPTS]")
		"_tts": enter_pressed.emit("[TOGGLE_TTS]")
		"_vitals": enter_pressed.emit("[VIEW_VITALS]")
		"_walk": enter_pressed.emit("[WALK]")
		"_map": enter_pressed.emit("[SPATIAL_MAP]")
		"":
			var label = kd.get("l", "")
			if _shift_down: label = kd.get("u", label)
			if not label.is_empty(): _buffer += label; _on_buffer_updated(); if _shift_down: _shift_down = false; _update_key_labels()

func _on_buffer_updated():
	if _buffer_label: _buffer_label.text = "> " + _buffer + "_"
	text_changed.emit(_buffer)

func _on_bond_value_changed(val: float) -> void:
	var t = (val + 100.0) / 200.0 
	var c_bg = Color(0, 0.01, 0.05).lerp(Color(0.05, 0.0, 0.02), t)
	var c_rim = Color(0, 0.8, 1.0).lerp(Color(1.0, 0.0, 0.4), t)
	
	_bg_style.bg_color = c_bg
	_bg_style.border_color = c_rim
	
	# Hue the buffer by slider
	_buffer_style.bg_color = c_bg.lightened(0.1)
	_buffer_style.bg_color.a = 0.4
	
	bond_slider_changed.emit(val)

func _on_slider_released(trait_name: String, val: float) -> void:
	if trait_name == "relationship_bond":
		trait_slider_changed.emit("relationship_bond", val)
		trait_slider_changed.emit("openness", val)
		trait_slider_changed.emit("experimental", val)
		trait_slider_changed.emit("polyamory", val)
		trait_slider_changed.emit("intellectual", val)
	else:
		trait_slider_changed.emit(trait_name, val)

func _add_dynamic_slider(root: Control, trait_name: String, l_text: String, r_text: String, l_color: Color, r_color: Color):
	var hbox = HBoxContainer.new(); hbox.alignment = BoxContainer.ALIGNMENT_CENTER; root.add_child(hbox)
	var l_l = Label.new(); l_l.text = "[" + l_text + "]"; l_l.add_theme_color_override("font_color", l_color); l_l.custom_minimum_size.x = 70; l_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; hbox.add_child(l_l)
	var s = HSlider.new(); s.min_value = -100; s.max_value = 100; s.value = 0; s.size_flags_horizontal = SIZE_EXPAND_FILL; hbox.add_child(s)
	
	# VISUALS (Live)
	if trait_name == "relationship_bond": 
		s.value_changed.connect(_on_bond_value_changed)
	
	# COGNITION (On Release)
	s.drag_ended.connect(func(changed): if changed: _on_slider_released(trait_name, s.value))
	
	var l_r = Label.new(); l_r.text = "[" + r_text + "]"; l_r.add_theme_color_override("font_color", r_color); l_r.custom_minimum_size.x = 70; l_r.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; hbox.add_child(l_r)

func _get_layout_compact() -> Array:
	return [
		[{"l":"1","u":"!"},{"l":"2","u":"@"},{"l":"3","u":"#"},{"l":"4","u":"$"},{"l":"5","u":"%"},{"l":"6","u":"&"},{"l":"7","u":"*"},{"l":"8","u":"("},{"l":"9","u":")"},{"l":"0","u":"="}],
		[
			{"act":"_bifrost","l":"PSYCHE","c":Color(0.4,0,0.1)},
			{"act":"_bifrost","l":"SOUL","c":Color(0.4,0.2,0)},
			{"act":"_bifrost","l":"BIFROST","c":Color(0.4,0.4,0)},
			{"act":"_bifrost","l":"COVENANT","c":Color(0,0.3,0.1)},
			{"act":"_bifrost","l":"SACRED","c":Color(0,0.1,0.4)}
		],
		[{"l":"q","u":"Q"},{"l":"w","u":"W"},{"l":"e","u":"E"},{"l":"r","u":"R"},{"l":"t","u":"T"},{"l":"y","u":"Y"},{"l":"u","u":"U"},{"l":"i","u":"I"},{"l":"o","u":"O"},{"l":"p","u":"P"},{"act":"_bksp","l":"⌫","sz":1.5}],
		[{"l":"a","u":"A"},{"l":"s","u":"S"},{"l":"d","u":"D"},{"l":"f","u":"F"},{"l":"g","u":"G"},{"l":"h","u":"H"},{"l":"j","u":"J"},{"l":"k","u":"K"},{"l":"l","u":"L"},{"l":"ö","u":"Ö"},{"l":"ä","u":"Ä"},{"act":"_ret","l":"RET","sz":1.5}],
		[{"act":"_shift_l","l":"⇧"},{"l":"z","u":"Z"},{"l":"x","u":"X"},{"l":"c","u":"C"},{"act":"_space","l":"SPACE","sz":3.0},{"l":"v","u":"V"},{"l":"b","u":"B"},{"l":"n","u":"N"},{"l":"m","u":"M"},{"l":",","u":"!"},{"l":".","u":"?"}]
	]

func _get_sidebar_left() -> Array:
	return [
		{"act":"_pray","l":"🙏","c":Color(0.3,0,0.1)}, {"act":"_logic","l":"⚙️","c":Color(0.2,0.2,0.2)},
		{"act":"_revise","l":"💡","c":Color(0,0.2,0.3)}, {"act":"_dream","l":"🌙","c":Color(0.1,0,0.3)},
		{"act":"_narrate","l":"📖","c":Color(0.2,0.2,0.3)}, {"act":"_clear","l":"🧹","c":Color(0.3,0.3,0)},
		{"act":"_love","l":"❤️","c":Color(0.3,0.1,0.2)}, {"act":"_save","l":"💾","c":Color(0,0.3,0.1)}
	]

func _get_sidebar_right() -> Array:
	return [
		{"act":"_prompts","l":"📋","c":Color(0.4,0.4,0)}, {"act":"_stt","l":"👂","c":Color(0,0.4,0.2)},
		{"act":"_tts","l":"🗣️","c":Color(0.2,0,0.4)}, {"act":"_img","l":"🎨","c":Color(0.4,0.4,0)},
		{"act":"_vitals","l":"🩺","c":Color(0.4,0.1,0.1)}, {"act":"_walk","l":"🚶","c":Color(0.1,0.4,0.4)},
		{"act":"_settings","l":"🛠️","c":Color(0.3,0.3,0.3)}, {"act":"_quit","l":"🚪","c":Color(0.2,0.2,0.2)}
	]

func _build_keyboard() -> void:
	for child in get_children(): child.queue_free()
	_keys.clear()
	
	# --- BACKGROUND PANEL (DYNAMIC) ---
	var bg = PanelContainer.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	bg.add_theme_stylebox_override("panel", _bg_style)
	
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_preset(PRESET_FULL_RECT)
	bg.add_child(root_margin)
	root_margin.add_theme_constant_override("margin_left", 8)
	root_margin.add_theme_constant_override("margin_right", 8)
	root_margin.add_theme_constant_override("margin_top", 4)
	root_margin.add_theme_constant_override("margin_bottom", 4)
	
	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = SIZE_EXPAND_FILL
	root_margin.add_child(root_vbox)
	root_vbox.add_theme_constant_override("separation", 4)
	
	# --- VISION COCKPIT (Triple Column) ---
	var cockpit_hbox := HBoxContainer.new()
	cockpit_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(cockpit_hbox)
	
	# 1. USER POV PREVIEW
	var u_bg = PanelContainer.new(); u_bg.custom_minimum_size = Vector2(60, 60); cockpit_hbox.add_child(u_bg)
	_user_preview = TextureRect.new()
	_user_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_user_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_user_preview.set_anchors_preset(PRESET_FULL_RECT)
	_user_preview.size_flags_horizontal = SIZE_EXPAND_FILL
	_user_preview.size_flags_vertical = SIZE_EXPAND_FILL
	u_bg.add_child(_user_preview)
	
	# 2. CONTROL CENTER (Slider & Buffer)
	var control_vbox := VBoxContainer.new()
	control_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	control_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cockpit_hbox.add_child(control_vbox)
	
	# 1. THE ONE SLIDER
	var slider_vbox = VBoxContainer.new(); control_vbox.add_child(slider_vbox)
	_add_dynamic_slider(slider_vbox, "relationship_bond", "AGENT", "COUPLE", Color.CYAN, Color.HOT_PINK)

	# 2. BUFFER DISPLAY
	var buffer_panel = PanelContainer.new(); control_vbox.add_child(buffer_panel)
	buffer_panel.add_theme_stylebox_override("panel", _buffer_style)
	_buffer_label = Label.new()
	_buffer_label.text = "> " + _buffer + "_"
	_buffer_label.add_theme_font_size_override("font_size", 18)
	_buffer_label.add_theme_color_override("font_color", Color.CYAN)
	_buffer_label.custom_minimum_size.y = 30
	_buffer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_buffer_label.clip_text = true
	buffer_panel.add_child(_buffer_label)
	
	# 3. JEN POV PREVIEW
	var j_bg = PanelContainer.new(); j_bg.custom_minimum_size = Vector2(60, 60); cockpit_hbox.add_child(j_bg)
	_jen_preview = TextureRect.new()
	_jen_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_jen_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_jen_preview.set_anchors_preset(PRESET_FULL_RECT)
	_jen_preview.size_flags_horizontal = SIZE_EXPAND_FILL
	_jen_preview.size_flags_vertical = SIZE_EXPAND_FILL
	j_bg.add_child(_jen_preview)

	# --- INTERACTION AREA ---
	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_horizontal = SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	root_vbox.add_child(main_hbox)
	main_hbox.add_theme_constant_override("separation", KEY_GAP)
	
	# LEFT SIDEBAR 
	var lgrid := GridContainer.new(); lgrid.columns = 2; main_hbox.add_child(lgrid)
	lgrid.add_theme_constant_override("h_separation", KEY_GAP); lgrid.add_theme_constant_override("v_separation", KEY_GAP)
	for kd in _get_sidebar_left():
		var btn = _create_key_btn(kd)
		btn.custom_minimum_size = Vector2(50, 50); btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lgrid.add_child(btn)
	
	# CENTRAL GRID
	var cvbc := VBoxContainer.new(); cvbc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cvbc.size_flags_vertical = Control.SIZE_EXPAND_FILL; main_hbox.add_child(cvbc)
	cvbc.add_theme_constant_override("separation", KEY_GAP)
	
	var layout = _get_layout_compact()
	
	# 3. COLORED LABELED BUTTONS (Row 1 of layout)
	var labeled_hbox := HBoxContainer.new(); labeled_hbox.size_flags_horizontal = SIZE_EXPAND_FILL; labeled_hbox.size_flags_vertical = SIZE_EXPAND_FILL; cvbc.add_child(labeled_hbox)
	labeled_hbox.add_theme_constant_override("separation", KEY_GAP)
	for kd in layout[1]:
		var btn = _create_key_btn(kd)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL; labeled_hbox.add_child(btn)

	# 4. BLACK NUMBERS AND SYMBOLS (Row 0 of layout)
	var num_hbox := HBoxContainer.new(); num_hbox.size_flags_horizontal = SIZE_EXPAND_FILL; num_hbox.size_flags_vertical = SIZE_EXPAND_FILL; cvbc.add_child(num_hbox)
	num_hbox.add_theme_constant_override("separation", KEY_GAP)
	for kd in layout[0]:
		var btn = _create_key_btn(kd)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL; num_hbox.add_child(btn)

	# 5. BLACK KEYBOARD ROWS (Rows 2, 3, 4)
	for i in range(2, 5):
		var hbox := HBoxContainer.new(); hbox.size_flags_horizontal = SIZE_EXPAND_FILL; hbox.size_flags_vertical = SIZE_EXPAND_FILL; cvbc.add_child(hbox)
		hbox.add_theme_constant_override("separation", KEY_GAP)
		for kd in layout[i]:
			var btn = _create_key_btn(kd)
			btn.size_flags_horizontal = SIZE_EXPAND_FILL; hbox.add_child(btn)

	# RIGHT SIDEBAR
	var rgrid := GridContainer.new(); rgrid.columns = 2; main_hbox.add_child(rgrid)
	rgrid.add_theme_constant_override("h_separation", KEY_GAP); rgrid.add_theme_constant_override("v_separation", KEY_GAP)
	for kd in _get_sidebar_right():
		var btn = _create_key_btn(kd)
		btn.custom_minimum_size = Vector2(50, 50); btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rgrid.add_child(btn)

func _create_key_btn(kd: Dictionary) -> Button:
	var btn := Button.new(); btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL; btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(40, 45) # Ensure keys have physical presence
	btn.size_flags_stretch_ratio = kd.get("sz", 1.0); btn.focus_mode = Control.FOCUS_NONE
	btn.text = "" 
	
	var sb_n = _sb_nrm; var sb_h = _sb_hov; var sb_p = _sb_pre
	if kd.has("c"):
		sb_n = _sb_nrm.duplicate(); sb_n.bg_color = kd["c"]; sb_n.border_color = kd["c"].lightened(0.3)
	btn.add_theme_stylebox_override("normal", sb_n); btn.add_theme_stylebox_override("hover", sb_h); btn.add_theme_stylebox_override("pressed", sb_p)

	var lbl_l = Label.new(); lbl_l.name = "LabelL"
	lbl_l.text = kd.get("l", "").to_upper() if kd.get("l", "").length() == 1 else kd.get("l", "")
	lbl_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lbl_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_l.set_anchors_preset(PRESET_FULL_RECT)
	lbl_l.add_theme_font_size_override("font_size", 22 if lbl_l.text.length() <= 2 else 14)
	btn.add_child(lbl_l)

	if kd.has("u") and not kd.get("u", "").is_empty():
		var banner = ColorRect.new(); banner.name = "Banner"; banner.color = Color(0, 0, 0, 0.4); banner.mouse_filter = Control.MOUSE_FILTER_IGNORE; banner.set_anchors_preset(PRESET_BOTTOM_WIDE); banner.custom_minimum_size.y = 18; btn.add_child(banner)
		var lbl_u = Label.new(); lbl_u.name = "LabelU"; lbl_u.text = kd.get("u", ""); lbl_u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; lbl_u.set_anchors_preset(PRESET_FULL_RECT); lbl_u.add_theme_font_size_override("font_size", 12); lbl_u.modulate = Color(0.6, 0.6, 0.6); banner.add_child(lbl_u)
		lbl_l.anchor_bottom = 0.7
	
	btn.pressed.connect(_on_key_btn_pressed.bind(kd, btn)); _keys.append({"btn": btn, "d": kd}); return btn

func _update_key_labels() -> void:
	for k in _keys:
		var lbl_l = k.btn.get_node_or_null("LabelL")
		var lbl_u = k.btn.get_node_or_null("Banner/LabelU")
		if k.d.get("act", "") == "":
			if _shift_down:
				if lbl_u: lbl_u.modulate = Color.WHITE
				if lbl_l: lbl_l.modulate = Color(0.5, 0.5, 0.5)
			else:
				if lbl_u: lbl_u.modulate = Color(0.6, 0.6, 0.6)
				if lbl_l: lbl_l.modulate = Color.WHITE

func update_previews(user_tex: Texture2D, jen_tex: Texture2D) -> void:
	if _user_preview and is_instance_valid(_user_preview):
		_user_preview.texture = user_tex
	if _jen_preview and is_instance_valid(_jen_preview):
		_jen_preview.texture = jen_tex
