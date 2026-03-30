extends Control

signal text_submitted(text: String)
signal haptic_requested(hand: String)

const CLR_BG = Color(0.05, 0.05, 0.1, 0.9)
const CLR_KEY = Color(0.15, 0.15, 0.25, 1.0)
const CLR_TEXT = Color(0.8, 0.9, 1.0, 1.0)

var _sb_nrm = StyleBoxFlat.new()
var _sb_hov = StyleBoxFlat.new()
var _sb_pre = StyleBoxFlat.new()
var _sb_cmd = StyleBoxFlat.new()
var _sb_lang = StyleBoxFlat.new()

var _is_shift = false
var _is_altgr = false
var _ctrl_down = false
var _fn_down = false

var _layout_nrm = [
	["q","w","e","r","t","y","u","i","o","p"],
	["a","s","d","f","g","h","j","k","l"],
	["_shift","z","x","c","v","b","n","m","_bksp"],
	["_fn","_ctrl","_globe","_space","_altgr","_tab","_enter"]
]

var _layout_shf = [
	["Q","W","E","R","T","Y","U","I","O","P"],
	["A","S","D","F","G","H","J","K","L"],
	["_shift","Z","X","C","V","B","N","M","_bksp"],
	["_fn","_ctrl","_globe","_space","_altgr","_tab","_enter"]
]

var _btn_shift: Button = null
var _btn_ctrl: Button = null
var _btn_fn: Button = null
var _btn_altgr: Button = null

var _bksp_held = false
var _hold_timer: Timer = null

func _ready():
	_sb_nrm.bg_color = CLR_KEY; _sb_nrm.set_corner_radius_all(4)
	_sb_hov.bg_color = CLR_KEY.lightened(0.2); _sb_hov.set_corner_radius_all(4)
	_sb_pre.bg_color = Color.SKY_BLUE; _sb_pre.set_corner_radius_all(4)
	_sb_cmd.bg_color = Color(0.2, 0.2, 0.4); _sb_cmd.set_corner_radius_all(4)
	_sb_lang.bg_color = Color(0.3, 0.2, 0.4); _sb_lang.set_corner_radius_all(4)
	
	_hold_timer = Timer.new(); _hold_timer.wait_time = 0.05; _hold_timer.timeout.connect(_do_backspace); add_child(_hold_timer)
	
	custom_minimum_size = Vector2(800, 525)
	_build_layout()

func _build_layout():
	for c in get_children(): if c != _hold_timer: c.queue_free()
	
	var vbox = VBoxContainer.new(); vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(vbox)
	
	var active_rows = _layout_shf if _is_shift else _layout_nrm
	for row in active_rows:
		var hbox = HBoxContainer.new(); hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL; vbox.add_child(hbox)
		for act in row:
			var btn = Button.new(); btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL; btn.custom_minimum_size.y = 80; hbox.add_child(btn)
			_setup_btn(btn, act)

func _setup_btn(btn: Button, act: String):
	var is_cmd = act.begins_with("_")
	btn.text = act.replace("_","").to_upper() if is_cmd else act
	if act == "_globe": btn.text = "🌐"
	if act == "_bksp": btn.text = "⌫"
	if act == "_enter": btn.text = "ENTER"
	if act == "_space": btn.text = "SPACE"; btn.size_flags_stretch_ratio = 3.0
	
	var sb = _sb_lang if act == "_globe" else (_sb_cmd if is_cmd or act in ["_ctrl","_fn","_altgr","_tab","_shift"] else _sb_nrm)
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   _sb_hov)
	btn.add_theme_stylebox_override("pressed", _sb_pre)
	btn.add_theme_color_override("font_color", CLR_TEXT)
	btn.add_theme_font_size_override("font_size", 15)

	match act:
		"_bksp":
			btn.button_down.connect(func(): 
				_bksp_held = true
				_do_backspace()
				await get_tree().create_timer(0.3).timeout
				if _bksp_held: _hold_timer.start())
			btn.button_up.connect(func(): _bksp_held = false; _hold_timer.stop())
		"_shift":
			_btn_shift = btn
			btn.pressed.connect(_on_shift)
		"_ctrl":
			_btn_ctrl = btn
			btn.pressed.connect(func(): _ctrl_down = !_ctrl_down; _refresh_mods())
		"_fn":
			_btn_fn = btn
			btn.pressed.connect(func(): _fn_down = !_fn_down; _refresh_mods())
		"_altgr":
			_btn_altgr = btn
			btn.pressed.connect(func(): _is_altgr = !_is_altgr; _refresh_mods())
		"_enter":
			btn.pressed.connect(func(): text_submitted.emit(""))
		"_space":
			btn.pressed.connect(func(): _input_text(" "))
		"_tab":
			btn.pressed.connect(func(): _input_text("\t"))
		"_globe":
			btn.pressed.connect(_on_globe)
		_:
			btn.pressed.connect(func(): _input_text(btn.text))

func _input_text(t: String):
	var node = get_viewport().gui_get_focus_owner()
	if node and (node is LineEdit or node is TextEdit):
		node.insert_text_at_caret(t)
	else:
		# Fallback to general signal
		text_submitted.emit(t)
	
	if _is_shift: _on_shift() # Auto-unshift

func _do_backspace():
	var node = get_viewport().gui_get_focus_owner()
	if node and (node is LineEdit or node is TextEdit):
		node.delete_char_at_caret()
	else:
		text_submitted.emit("_BKSP")

func _on_shift():
	_is_shift = !_is_shift
	_build_layout()

func _on_globe():
	print("LUMAX: Language Switch Requested.")

func _refresh_mods():
	# Visual feedback for toggle keys
	if _btn_ctrl: _btn_ctrl.modulate = Color.CYAN if _ctrl_down else Color.WHITE
	if _btn_fn: _btn_fn.modulate = Color.ORANGE if _fn_down else Color.WHITE
	if _btn_altgr: _btn_altgr.modulate = Color.MAGENTA if _is_altgr else Color.WHITE

func _on_haptic_requested(hand: String):
	haptic_requested.emit(hand)
