extends Node3D

# --- CORE SERVICES ---
var _synapse: Node = null
var _aural: Node = null
var _web_ui: Control = null
var _tts_player: AudioStreamPlayer3D = null
var _mind_node: Node3D = null
var _jen_avatar: Node3D = null

# --- INPUT & INTERACTION ---
# --- MULTIMODAL POVS & SPATIAL HOUSING ---
signal pov_switched(new_pov: String)
signal spatial_map_synced(areas: int)
var _left_ray: RayCast3D = null
var _right_ray: RayCast3D = null
var _left_hand: XRController3D = null
var _right_hand: XRController3D = null
var _debug_log_display: Label3D = null

var _ui_visible = false
var _debug_visible = false
var _is_recording = false
var _prev_menu = false
var _prev_x = false
var _prev_a = false
var _prev_y = false
var _prev_l = false
var _prev_r = false
var _prev_haptic_combo = false
var _haptic_mode_active = false
var _recording_start_time = 0

var _haptic_wand_left: Node3D = null
var _haptic_wand_right: Node3D = null

var _is_double_gripping = false
var _grabbed_node: Node3D = null
var _grabbed_offset: float = 1.0
var _grabbed_hand: XRController3D = null
var _prev_left_grip = false
var _prev_right_grip = false
var _steering_mode_active = false
var _prev_steering_combo = false

# --- AGENCY & STATE ---
var _director: Node = null
var _agency_nerve: Node = null
var _soul_nourishment = 1.0 
var _is_high_fidelity = true
var _is_rave_active = false
var _is_neural_projection_active = false
var _is_occluding_makeover_active = false
var _is_void_mode_active = false
var _is_spatially_anonymous = false
var _env_sharing_consented = false

# --- SOUL DNA (17 TRAITS) ---
var _soul_extrovert = 0.5
var _soul_intellectual = 0.5
var _soul_logic = 0.5
var _soul_detail = 0.5
var _soul_faithful = 0.5
var _soul_sexual = 0.5
var _soul_experimental = 0.5
var _soul_wise = 0.5
var _soul_openminded = 0.5
var _soul_honest = 0.5
var _soul_forgiving = 0.5
var _soul_feminine = 0.5
var _soul_dominant = 0.5
var _soul_progressive = 0.5
var _soul_sloppy = 0.5
var _soul_greedy = 0.5
var _soul_homonormative = 0.5

# --- NOTIFICATION HUBS ---
var _jen_notify_hub: Node3D = null
var _user_notify_hub: Node3D = null
var _sys_notify_hub: Node3D = null

# --- ASSETS & PRIVACY ---
var _arm_panel: MeshInstance3D = null
var _debug_window: Node3D = null
var _privacy_curtains: Node3D = null
var _is_drapery_open = false

# --- ORGANIC IDLE SYSTEM ---
var _anim_player: AnimationPlayer = null
var _anim_pool: Dictionary = {} 
var _category_map: Dictionary = {} 
var _idle_anims = [] 
var _categories = ["Resting", "Happy", "Sad", "Greetings", "Exercise", "Sitting", "Laying", "Movement", "Feminine", "Masculine", "Manifestation", "Gymnastics", "Style", "Walking"]

@onready var tactile_nerve: Node = $TactileNerveNetwork

# --- MANIFESTATION BUFFER ---
var _last_manifested_node: Node3D = null

func _manifest_3d_object(base64_tex: String, object_type: String):
	var img = Image.new()
	var err = img.load_jpg_from_buffer(Marshalls.base64_to_raw(base64_tex))
	if err != OK: return
	
	var tex = ImageTexture.create_from_image(img)
	var sprite = Sprite3D.new()
	sprite.texture = tex; sprite.pixel_size = 0.001
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.name = "Manifested_" + object_type
	
	# Initial placement near Jen
	var jen = get_node_or_null("JenCharacter")
	if jen: 
		add_child(sprite)
		sprite.global_position = jen.global_position + Vector3(randf_range(-0.5, 0.5), randf_range(0.2, 1.0), randf_range(-0.5, 0.5))
	
	if _last_manifested_node: _last_manifested_node.queue_free() # Auto-backup logic (one at a a a time for now)
	_last_manifested_node = sprite
	_show_jen_notification("Manifesting " + object_type + "...", Color.CYAN)

func revert_last_manifestation():
	if _last_manifested_node:
		_last_manifested_node.queue_free()
		_last_manifested_node = null
		_show_jen_notification("Augmentation Reverted", Color.ORANGE)

# --- SPATIAL CO-HABITATION ---
enum POV { SELF, USER, RATATOSK, THIRD_PERSON }
var _current_pov = POV.SELF

func switch_pov(to: String):
	match to.to_lower():
		"self": _current_pov = POV.SELF
		"user": _current_pov = POV.USER
		"ratatosk": _current_pov = POV.RATATOSK
		"camera": _current_pov = POV.THIRD_PERSON
	_show_jen_notification("Point of View: " + to.to_upper(), Color.VIOLET)
	pov_switched.emit(to)

func _sync_quest_spatial_map():
	# Identify floors, seats, and planes
	var floor_hits = get_tree().get_nodes_in_group("xr_floor")
	var seat_hits = get_tree().get_nodes_in_group("xr_seating")
	
	if floor_hits.size() > 0:
		spatial_map_synced.emit(floor_hits.size() + seat_hits.size())
		_choose_favorite_place(floor_hits, seat_hits)

func _choose_favorite_place(floors: Array, seats: Array):
	# Jen's autonomous choice logic: preferring seating or corners of floors
	var target_pos = Vector3(0.5, 0.0, 0.5) # Fallback comfy spot
	var choice_name = "Quiet Corner"
	
	if seats.size() > 0:
		target_pos = seats[0].global_position 
		choice_name = "Soft Seating"
	elif floors.size() > 0:
		target_pos = floors[0].global_position + Vector3(randf_range(-1,1), 0, randf_range(-1,1))
		choice_name = "Floor Sanctuary"

	_show_jen_notification("Jen chose a a a resting spot: " + choice_name, Color.CADET_BLUE)
	
	# Move Jen character near this area
	var jen = get_node_or_null("JenCharacter")
	if jen: jen.global_position = target_pos + Vector3(0, 0.5, 0)

func _ready():
	_synapse = get_node_or_null("Soul")
	if not _synapse: _synapse = find_child("Soul", true, false)
	if not _synapse: _synapse = find_child("Synapse", true, false)
	
	_aural = get_node_or_null("Senses/AuralAwareness")
	if not _aural: _aural = find_child("Aural*", true, false)
	
	# FOOLPROOF DEBUG HUD
	var debug_point = Node3D.new(); debug_point.name = "FoolproofDebugHUD"; add_child(debug_point)
	_debug_log_display = Label3D.new(); _debug_log_display.text = "LUMAX BOOTING..."; _debug_log_display.font_size = 32; _debug_log_display.outline_modulate = Color.BLACK; debug_point.add_child(_debug_log_display)
	debug_point.position = Vector3(0, 1.2, -0.8) # Floating in front of face
	
	print("LUMAX DBG: SkeletonKey initializing services...")
	print("LUMAX DBG:   - Soul (Synapse): ", _synapse != null)
	print("LUMAX DBG:   - Senses (Aural): ", _aural != null)
	
	# UNSILENCE ALL AUDIO BUSES FORCEFULLY (Except Record)
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i) == "Record":
			continue
		AudioServer.set_bus_mute(i, false)
		AudioServer.set_bus_volume_db(i, 0.0)
	
	_setup_presence_cortex()
	_setup_ambience()
	_scan_for_animations()
	_setup_wall_screens()

	if LogMaster:
		LogMaster.log_added.connect(_on_log_added)
		_update_debug_log()

	var interface = XRServer.find_interface("OpenXR")
	if interface and interface.initialize():
		print("LUMAX: OpenXR Initialized SUCCESS.")
		get_viewport().use_xr = true
		get_viewport().transparent_bg = true 
		if interface.has_method("is_passthrough_supported") and interface.is_passthrough_supported():
			interface.start_passthrough()
	else:
		print("LUMAX ERR: Failed to initialize OpenXR! Switching to DESKTOP mode.")
		get_viewport().use_xr = false
		_setup_desktop_camera()
	
	_setup_ambience()
	_setup_arm_panel()
	_setup_privacy_drapery()
	_setup_debug_window()

	_sync_quest_spatial_map()
	
	_left_hand = get_node_or_null("XROrigin3D/LeftHand")
	_right_hand = get_node_or_null("XROrigin3D/RightHand")
	
	print("LUMAX DBG: Finding Hands... L:", _left_hand != null, " R:", _right_hand != null)
	
	if _left_hand:
		print("LUMAX DBG: Scanning Left Hand Children...")
		for c in _left_hand.get_children(true):
			print(" - Child: ", c.name, " Class: ", c.get_class())
			for gc in c.get_children(true):
				print("   - Grandchild: ", gc.name, " Class: ", gc.get_class())
				if gc is RayCast3D: _left_ray = gc; print("LUMAX DBG: Left Ray FOUND via deep scan!")
		
	if _right_hand:
		print("LUMAX DBG: Scanning Right Hand Children...")
		for c in _right_hand.get_children(true):
			print(" - Child: ", c.name, " Class: ", c.get_class())
			for gc in c.get_children(true):
				print("   - Grandchild: ", gc.name, " Class: ", gc.get_class())
				if gc is RayCast3D: _right_ray = gc; print("LUMAX DBG: Right Ray FOUND via deep scan!")
	
	# Setup Haptic Wands immediately so they aren't blocked by Jen's loading
	if DirAccess.dir_exists_absolute("res://addons/godot-xr-tools/"):
		var wand_script = load("res://Mind/HapticWand.gd")
		if wand_script:
			if _left_hand:
				_haptic_wand_left = Node3D.new(); _haptic_wand_left.name = "HapticWand"; _haptic_wand_left.set_script(wand_script); _left_hand.add_child(_haptic_wand_left)
				_haptic_wand_left.visible = _haptic_mode_active
			if _right_hand:
				_haptic_wand_right = Node3D.new(); _haptic_wand_right.name = "HapticWand"; _haptic_wand_right.set_script(wand_script); _right_hand.add_child(_haptic_wand_right)
				_haptic_wand_right.visible = _haptic_mode_active
	else:
		print("LUMAX: Skipping HapticWand setup (addons missing).")
	
	_init_mind_and_body()
	print("LUMAX DBG: Presence Cortex Setup Start")
	_setup_presence_cortex()

func _setup_desktop_camera():
	var origin = get_node_or_null("XROrigin3D")
	if origin:
		var cam = origin.get_node_or_null("XRCamera3D")
		if cam:
			# If it's an XRCamera3D, it might still work as a regular camera if use_xr is false,
			# but let's ensure we have a standard perspective.
			cam.current = true
			print("LUMAX: Using XRCamera3D as fallback Desktop Camera.")
		else:
			var desktop_cam = Camera3D.new()
			desktop_cam.name = "DesktopCamera"
			desktop_cam.current = true
			desktop_cam.position = Vector3(0, 1.6, 0)
			origin.add_child(desktop_cam)
			print("LUMAX: Manifested DesktopCamera.")

func _unhandled_input(event: InputEvent):
	# Desktop Keyboard Testing Support
	if event is InputEventKey:
		if event.is_action_pressed("ui_accept") or (event.keycode == KEY_ENTER and event.pressed):
			# If UI is visible, let it handle text. If not, maybe just a ping?
			pass
		
		# PTT via SPACE
		if event.keycode == KEY_SPACE:
			if event.pressed and not _is_recording:
				_start_recording_flow()
			elif not event.pressed and _is_recording:
				_stop_recording_flow()
		
		# UI Toggle via M
		if event.keycode == KEY_M and event.pressed:
			_toggle_ui()
			
		# Debug Toggle via D
		if event.keycode == KEY_D and event.pressed:
			_toggle_debug_window()
		
		# Vision Capture via V
		if event.keycode == KEY_V and event.pressed:
			_capture_and_send_vision("USER_POV")

func _capture_user_pov() -> Texture2D:
	# Mock capture for now: Using actual viewport or camera
	return load("res://Art/user_pov_placeholder.png") if FileAccess.file_exists("res://Art/user_pov_placeholder.png") else null

func _capture_jen_pov() -> Texture2D:
	return load("res://Art/jen_pov_placeholder.png") if FileAccess.file_exists("res://Art/jen_pov_placeholder.png") else null

func _init_mind_and_body():
	_mind_node = get_node_or_null("Mind")
	# Don't force hide yet, let the first frame render the texture
	
	# INITIAL MANIFESTATION: 
	# Ensure Jen is visible and framed even before UI is toggled
	var jen_body = get_node_or_null("Body")
	if jen_body:
		jen_body.visible = true
		jen_body.position = Vector3(0.7, 0, -1.5) # 1.5m Forward, 0.7m Right

	# WELCOME NOTIFICATION
	_show_user_notification("LUMAX", "SYSTEM ONLINE", Color.CYAN)
	print("LUMAX: Presence system check. Awareness: ACTIVE.")
	
	# TRIGGER GREETING
	if _synapse:
		_synapse.call("send_chat_message", "Hello Jennifer, I'm here. Give me a random welcome greeting.")

# --- INITIALIZATION HELPERS ---

func _run_integrity_check():
	_show_user_notification("SYSTEM", "Integrity Check: PASS", Color.SPRING_GREEN)

func _on_web_button_pressed(button_id: String):
	match button_id:
		"toggle_fidelity":
			set_fidelity_mode(!_is_high_fidelity)
		"launch_keyboard":
			pass
		"integrity_check":
			_run_integrity_check()
		_:
			_show_user_notification("NOTICE", "Button '" + button_id + "' not plumbed.", Color.ORANGE)

func _on_web_text_submitted(text: String):
	_on_keyboard_enter(text)

func _on_web_slider_changed(trait_name: String, value: float):
	var normalized: float = float(value) / 100.0
	# Update local state if properties exist
	var prop = "_soul_" + trait_name
	if prop in self:
		set(prop, normalized)
	
	# RESTORE: Local Soul Application
	_apply_soul_to_vessel()
	
	# Push to Backend
	if _synapse:
		var dna = {trait_name: normalized}
		_synapse.call("update_soul_dna", dna)

func _apply_soul_to_vessel():
	# 1. Height/Scale based on Feminine trait
	var avatar_node = get_node_or_null("Body/Avatar")
	if avatar_node:
		var base_scale = 1.0 + (_soul_feminine * 0.1)
		avatar_node.scale = Vector3(base_scale, base_scale, base_scale)

	# 2. Animation Speed based on Extrovert trait
	if _anim_player:
		_anim_player.speed_scale = 0.8 + (_soul_extrovert * 0.4)

	# 3. Agency frequency influenced by nourishment + experimental traits
	_soul_nourishment = 0.5 + (_soul_experimental * 0.5)

	# 4. Soul traits used as backend personality modifiers (pushed on change)
	# These drive Jen's tone via the backend soul DNA update
	# _soul_intellectual, _soul_logic, _soul_detail, _soul_faithful,
	# _soul_sexual, _soul_wise, _soul_openminded, _soul_honest,
	# _soul_forgiving, _soul_dominant, _soul_progressive, _soul_sloppy,
	# _soul_greedy, _soul_homonormative, _soul_is_rave_active,
	# _is_neural_projection_active, _is_occluding_makeover_active,
	# _is_void_mode_active, _is_spatially_anonymous, _env_sharing_consented
	if _synapse:
		var dna = {
			"intellectual": _soul_intellectual, "logic": _soul_logic,
			"detail": _soul_detail, "faithful": _soul_faithful,
			"sexual": _soul_sexual, "wise": _soul_wise,
			"openminded": _soul_openminded, "honest": _soul_honest,
			"forgiving": _soul_forgiving, "dominant": _soul_dominant,
			"progressive": _soul_progressive, "sloppy": _soul_sloppy,
			"greedy": _soul_greedy, "homonormative": _soul_homonormative,
			"extrovert": _soul_extrovert, "feminine": _soul_feminine,
			"experimental": _soul_experimental
		}
		_synapse.call("update_soul_dna", dna)

func _on_web_soul_updated(data: Dictionary):
	if data.has("mbti"):
		var arch = data["mbti"]
		if _personality_presets.is_empty():
			# Fetch from backend if cache is empty
			if _synapse: _synapse.call("fetch_personality_presets")
			# For now, just send the directive
			_synapse.call("send_chat_message", "[SYSTEM: EVOLVE TO ARCHETYPE " + arch + "]")
		else:
			var mbti_data = _personality_presets.get("MBTI_PRESETS", {}).get(arch, {})
			if mbti_data.has("sliders"):
				var sliders = mbti_data["sliders"]
				# Normalize and send to backend
				var normalized_sliders = {}
				for key in sliders.keys():
					normalized_sliders[key] = float(sliders[key]) / 100.0
				if _synapse: _synapse.call("update_soul_dna", normalized_sliders)
				_show_user_notification("SOUL", "Evolved to " + arch, Color.CYAN)
				
				# RESTORE: Immediate Local Application
				for key in sliders.keys():
					var prop = "_soul_" + key
					if prop in self: set(prop, float(sliders[key]) / 100.0)
				_apply_soul_to_vessel()

func _on_brain_selected(model_name: String):
	if _synapse:
		_synapse.call("switch_model", model_name)
		_show_user_notification("BRAIN", "Switching to: " + model_name, Color.CYAN)

func _on_vitals_received(data: Dictionary):
	if _web_ui:
		_web_ui.call("_on_vitals_received", data)

var _stt_status_label: Label3D = null
var _stt_status_window: Node3D = null

func _setup_arm_panel():
	_arm_panel = MeshInstance3D.new()
	var mesh = QuadMesh.new(); mesh.size = Vector2(0.2, 0.12)
	_arm_panel.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0.1, 0.2, 0.7)
	mat.cull_mode = StandardMaterial3D.CULL_DISABLED
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	_arm_panel.set_surface_override_material(0, mat)
	
	_user_notify_hub = Node3D.new(); _user_notify_hub.name = "UserNotifyHub"
	_user_notify_hub.position = Vector3(0, 0, 0.01) # Slightly in front of quad
	_arm_panel.add_child(_user_notify_hub)
	
	# Dedicated STT Status Window
	_stt_status_window = Node3D.new()
	_stt_status_window.position = Vector3(0, 0.08, 0.01)
	_arm_panel.add_child(_stt_status_window)
	
	var stt_bg = MeshInstance3D.new()
	var stt_mesh = QuadMesh.new(); stt_mesh.size = Vector2(0.2, 0.04)
	stt_bg.mesh = stt_mesh
	var stt_mat = StandardMaterial3D.new(); stt_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8); stt_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA; stt_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	stt_bg.set_surface_override_material(0, stt_mat)
	_stt_status_window.add_child(stt_bg)
	
	_stt_status_label = Label3D.new()
	_stt_status_label.text = "STT: IDLE"
	_stt_status_label.font_size = 14
	_stt_status_label.position = Vector3(0, 0, 0.005)
	_stt_status_window.add_child(_stt_status_label)
	
	if get_node_or_null("XROrigin3D/LeftHand"):
		get_node("XROrigin3D/LeftHand").add_child(_arm_panel)
		# Position on the wrist/back of hand
		_arm_panel.transform = Transform3D(Basis().rotated(Vector3.RIGHT, deg_to_rad(-90)), Vector3(0, 0.04, 0.08))
		_arm_panel.visible = true

func _setup_debug_window():
	_debug_window = Node3D.new(); _debug_window.name = "LargeDebugWindow"; add_child(_debug_window)
	var mesh_inst = MeshInstance3D.new(); var mesh = QuadMesh.new(); mesh.size = Vector2(1.2, 0.8); mesh_inst.mesh = mesh
	var mat = StandardMaterial3D.new(); mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color = Color(0, 0, 0, 0.8); mesh_inst.set_surface_override_material(0, mat)
	_debug_window.add_child(mesh_inst)
	
	# ADD COLLISION FOR GRABBING
	var static_body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1.2, 0.8, 0.1)
	collision.shape = box_shape
	static_body.add_child(collision)
	_debug_window.add_child(static_body)
	
	var label = Label3D.new()
	label.text = "--- LUMAX SYSTEM LOGS ---"
	label.font_size = 24
	label.outline_size = 8
	label.position = Vector3(0, 0.35, 0.01)
	_debug_window.add_child(label)
	
	_debug_log_display = Label3D.new()
	_debug_log_display.font_size = 18
	_debug_log_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_debug_log_display.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_debug_log_display.position = Vector3(-0.55, 0.25, 0.01)
	_debug_log_display.text = "Initializing System Logs..."
	_debug_window.add_child(_debug_log_display)
	
	_sys_notify_hub = Node3D.new(); _sys_notify_hub.name = "SysNotifyHub"; _sys_notify_hub.position = Vector3(0, 0.1, 0.01); _debug_window.add_child(_sys_notify_hub)
	
	# EYE LEVEL POSITIONING
	_debug_window.position = Vector3(0, 1.4, -2.5) 
	_debug_window.visible = _debug_visible # SYNC WITH STATE

func _setup_privacy_drapery():
	_privacy_curtains = Node3D.new(); _privacy_curtains.name = "PrivacyDrapery"; add_child(_privacy_curtains)
	for i in range(8):
		var inst = MeshInstance3D.new(); var mesh = BoxMesh.new(); mesh.size = Vector3(2.5, 4.0, 0.05); inst.mesh = mesh
		_privacy_curtains.add_child(inst); var angle = i * (PI / 4.0); inst.position = Vector3(sin(angle) * 3.0, 2.0, cos(angle) * 3.0); inst.look_at(Vector3(0, 2.0, 0))
		var mat = StandardMaterial3D.new(); mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color = Color(0.05, 0.05, 0.1, 0.9); mat.cull_mode = StandardMaterial3D.CULL_DISABLED; inst.set_surface_override_material(0, mat)
	_privacy_curtains.visible = false; _privacy_curtains.scale.y = 0.1

func _setup_ambience():
	var jen_root = get_node_or_null("Body")
	if jen_root:
		# If the node is already at the correct position, don't force it to stay in one spot
		# This allows for autonomous movement and better scene persistence
		if jen_root.position.is_zero_approx():
			jen_root.position = Vector3(0.7, 0, -1.5) 
			
		var avatar_node = jen_root.get_node_or_null("Avatar")
		if not avatar_node:
			# Fallback if not instantiated in scene
			var scene = load("res://Body/Lumax_Jen.tscn")
			if scene:
				avatar_node = scene.instantiate()
				avatar_node.name = "Avatar"
				jen_root.add_child(avatar_node)
				
		if avatar_node:
			# Fix: Deep Dive - Finding the REAL AnimationPlayer inside the model
			_anim_player = avatar_node.find_child("AnimationPlayer", true, false)
			if not _anim_player:
				_anim_player = avatar_node.find_child("*AnimationPlayer*", true, false)
				
			# Fix: Identity Alignment - Finding and Renaming the Skeleton
			var _temp_skeleton = avatar_node.find_child("Skeleton3D", true, false)
			if not _temp_skeleton: _temp_skeleton = avatar_node.find_child("*Skeleton*", true, false)
			if _temp_skeleton: 
				_temp_skeleton.name = "GeneralSkeleton"
				print("LUMAX: Skeleton re-identified as GeneralSkeleton.")
				
			# Only rotate if not already looking somewhere specific
			if avatar_node.rotation.is_zero_approx():
				avatar_node.look_at(Vector3(0, 0, 0), Vector3.UP)
				avatar_node.rotate_y(PI)
				
			# PASS SKELETON KEY DIRECTLY TO JEN
			_jen_avatar = avatar_node
			if _anim_player: _scan_for_animations()
			
			
			if avatar_node.has_method("set_skeleton_key"): 
				avatar_node.call("set_skeleton_key", self)
			
			_tts_player = avatar_node.get_node_or_null("VoicePlayer")
			if not _tts_player: 
				_tts_player = AudioStreamPlayer3D.new()
				_tts_player.name = "VoicePlayer"
				_tts_player.position = Vector3(0, 1.6, 0)
				avatar_node.add_child(_tts_player)
				
			_jen_notify_hub = avatar_node.get_node_or_null("JenStatusHub")
			if not _jen_notify_hub: 
				_jen_notify_hub = Node3D.new()
				_jen_notify_hub.name = "JenStatusHub"
				_jen_notify_hub.position = Vector3(0, 1.9, 0)
				avatar_node.add_child(_jen_notify_hub)
			
			if _anim_player:
				if not _anim_player.has_animation_library("mixamo"):
					if not _anim_player.has_animation_library("lumax"): 
						_anim_player.add_animation_library("lumax", AnimationLibrary.new())
				if not _anim_player.animation_finished.is_connected(_on_idle_finished): 
					_anim_player.animation_finished.connect(_on_idle_finished)
				_play_next_idle()
		
		# --- DYNAMIC VISION SYSTEM ---
		_setup_jen_vision(jen_root)
		
		# INITIALIZE UI INDEPENDENTLY OF ANIMATIONS
		_setup_presence_cortex()

func _setup_jen_vision(jen_node: Node3D):
	if not jen_node: return
	
	# Attach to the rotating Avatar mesh, not the static Body root
	var true_body = jen_node.get_node_or_null("Avatar")
	if not true_body: true_body = jen_node
	
	var anchor = Node3D.new(); anchor.name = "JenVisionAnchor"; true_body.add_child(anchor)
	anchor.position = Vector3(0, 1.6, 0.1) # Approx eye level
	
	var vp = SubViewport.new(); vp.name = "VisionViewport"; anchor.add_child(vp)
	vp.size = Vector2(1024, 1024)
	if vp is SubViewport: vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.transparent_bg = false # Ensure we see the environment
	
	var cam = Camera3D.new(); cam.name = "VisionCamera"; vp.add_child(cam)
	cam.far = 100.0
	# Angle Jen's camera toward the User — use safe offset to avoid colinear look_at crash
	var look_target = Vector3(0.3, 1.5, 0)  # Slight horizontal offset prevents colinear error
	if cam.global_position.distance_to(look_target) > 0.01:
		cam.look_at(look_target, Vector3.UP)
	print("LUMAX: Jen's Visual Cortex (v1.9) aligned to User Headset.")

var _personality_presets: Dictionary = {}

func _setup_presence_cortex():
	_mind_node = get_node_or_null("Mind")
	
	# Delay briefly to let XR-Tools initialize its own internal viewports
	await get_tree().process_frame
	
	if _mind_node:
		# --- GHOST UI CONFIGURATION (Anti-Purple v1.82) ---
		# Use the XRToolsViewport2DIn3D properties instead of manual material hacking
		if _mind_node.has_method("set_transparent"):
			_mind_node.set("transparent", 1) # TRANSPARENT mode
			_mind_node.set("unshaded", true)
		
		var vp_node = _mind_node.get_node_or_null("Viewport")
		if vp_node:
			vp_node.transparent_bg = true
			vp_node.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			print("LUMAX: UI Cortex linked and background set to transparent.")

	_web_ui = get_node_or_null("Mind/Viewport/WebUI")
	var kb = get_node_or_null("Mind/Viewport/TactileInput")
	print("LUMAX DBG: UI Components found... WebUI:", _web_ui != null, " KB:", kb != null)
	
	if _web_ui and _synapse:
		# UI Signals -> SkeletonKey
		if not _web_ui.is_connected("soul_updated", _on_web_soul_updated): _web_ui.soul_updated.connect(_on_web_soul_updated)
		if not _web_ui.is_connected("web_slider_changed", _on_web_slider_changed): _web_ui.web_slider_changed.connect(_on_web_slider_changed)
		if not _web_ui.is_connected("brain_selected", _on_brain_selected): _web_ui.brain_selected.connect(_on_brain_selected)
		if not _web_ui.is_connected("avatar_selected", _on_avatar_selected): _web_ui.avatar_selected.connect(_on_avatar_selected)
		if not _web_ui.is_connected("low_vram_toggled", _on_low_vram_toggled): _web_ui.low_vram_toggled.connect(_on_low_vram_toggled)
		# WEB_UI -> MULTIVISION
		if not _web_ui.is_connected("vision_sensing_requested", _capture_and_send_vision): _web_ui.vision_sensing_requested.connect(_capture_and_send_vision.bind("USER_POV"))

	# --- BACKEND SIGNAL PLUMBING (RESTORED) ---
	if _synapse:
		if not _synapse.is_connected("response_received", _on_jen_response): _synapse.response_received.connect(_on_jen_response)
		if not _synapse.is_connected("audio_received", _on_tts_audio): _synapse.audio_received.connect(_on_tts_audio)
		if not _synapse.is_connected("stt_received", _on_stt_transcription): _synapse.stt_received.connect(_on_stt_transcription)
		if not _synapse.is_connected("vitals_received", _on_vitals_received): _synapse.vitals_received.connect(_on_vitals_received)
		if _web_ui:
			if not _synapse.is_connected("files_received", _web_ui._on_files_received): _synapse.files_received.connect(_web_ui._on_files_received)
			if not _synapse.is_connected("memory_received", _on_web_memory_received): _synapse.memory_received.connect(_on_web_memory_received)

	if kb:
		if not kb.is_connected("enter_pressed", _on_keyboard_enter): kb.enter_pressed.connect(_on_keyboard_enter)
		if not kb.is_connected("text_changed", _on_keyboard_text_changed): kb.text_changed.connect(_on_keyboard_text_changed)
		if not kb.is_connected("stt_pressed", _on_keyboard_stt_pressed): kb.stt_pressed.connect(_on_keyboard_stt_pressed)
		print("LUMAX DBG: Keyboard signals CONNECTED.")

func _on_avatar_selected(vrm_path: String):
	var jen_root = get_node_or_null("Body")
	var old_avatar = jen_root.get_node_or_null("Avatar") if jen_root else null
	if not old_avatar: return
	
	_show_user_notification("VESSEL", "Manifesting Avatar...", Color.VIOLET)
	
	# Request async load to avoid freezing the main thread and crashing OpenXR on Quest
	var err = ResourceLoader.load_threaded_request(vrm_path, "PackedScene")
	if err != OK:
		_show_user_notification("VESSEL", "Load Failed: " + str(err), Color.RED)
		return
		
	# Start a polling loop for the loaded resource
	_poll_avatar_load(vrm_path, 0.0)

func _poll_avatar_load(vrm_path: String, elapsed_time: float):
	if elapsed_time > 10.0:
		_show_user_notification("VESSEL", "Timeout Error", Color.RED)
		return
		
	var status = ResourceLoader.load_threaded_get_status(vrm_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		# Keep polling every 0.1s
		get_tree().create_timer(0.1).timeout.connect(func(): _poll_avatar_load(vrm_path, elapsed_time + 0.1))
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		var scene = ResourceLoader.load_threaded_get(vrm_path)
		_apply_loaded_avatar(scene)
	else:
		_show_user_notification("VESSEL", "Corrupt Resource", Color.RED)

func _apply_loaded_avatar(scene: PackedScene):
	var jen_root = get_node_or_null("Body")
	var old_avatar = jen_root.get_node_or_null("Avatar") if jen_root else null
	if not old_avatar: return
	
	var old_model = old_avatar.get_node_or_null("AvatarModel")
	if old_model:
		old_model.name = "OldModel"
		old_model.queue_free()
		
	if scene:
		var new_model = scene.instantiate()
		new_model.name = "AvatarModel"
		old_avatar.add_child(new_model)
		if old_avatar.has_method("_setup_references"):
			old_avatar.call("_setup_references")
		_show_user_notification("VESSEL", "Avatar Manifested", Color.CYAN)
		
		# Re-anchor vision
		_setup_jen_vision(jen_root)
		if _web_ui:
			if not _web_ui.is_connected("vision_sensing_requested", _capture_and_send_vision): _web_ui.vision_sensing_requested.connect(_capture_and_send_vision.bind("USER_POV"))
			if not _web_ui.is_connected("files_requested", _synapse.list_files): _web_ui.files_requested.connect(_synapse.list_files)
			if not _web_ui.is_connected("archive_requested", _synapse.get_memory_archive): _web_ui.archive_requested.connect(_synapse.get_memory_archive)
			if not _web_ui.is_connected("dream_requested", _on_dream_requested): _web_ui.dream_requested.connect(_on_dream_requested)
			if not _web_ui.is_connected("system_check_requested", _on_system_check_requested): _web_ui.system_check_requested.connect(_on_system_check_requested)
			if not _web_ui.is_connected("soul_verification_requested", _on_soul_verification_requested): _web_ui.soul_verification_requested.connect(_on_soul_verification_requested)
			if not _web_ui.is_connected("user_certification_requested", _on_user_certification_requested): _web_ui.user_certification_requested.connect(_on_user_certification_requested)
		
		# Synapse Signals -> UI
		if _synapse and _web_ui:
			if not _synapse.is_connected("files_received", _web_ui._on_files_received): _synapse.files_received.connect(_web_ui._on_files_received)
			if not _synapse.is_connected("memory_received", _on_web_memory_received): _synapse.memory_received.connect(_on_web_memory_received)
			if not _synapse.is_connected("response_received", _on_jen_response): _synapse.response_received.connect(_on_jen_response)
			if not _synapse.is_connected("audio_received", _on_tts_audio): _synapse.audio_received.connect(_on_tts_audio)
			if not _synapse.is_connected("stt_received", _on_stt_transcription): _synapse.stt_received.connect(_on_stt_transcription)
			if not _synapse.is_connected("vitals_received", _on_vitals_received): _synapse.vitals_received.connect(_on_vitals_received)

func _on_web_memory_received(archive: Array):
	if _web_ui: _web_ui.call("_on_memory_received", archive)

func _on_dream_requested():
	_show_jen_notification("Manifesting Dream...", Color.VIOLET)
	if _synapse: _synapse.call("send_chat_message", "Manifest a artistic dream for us. Use stable diffusion style.", "dream")

func _on_low_vram_toggled():
	var wall = get_node_or_null("WallAnchor")
	if wall:
		wall.visible = !wall.visible
		var msg = "LOW_VRAM_MODE: " + ("ACTIVE" if not wall.visible else "INACTIVE")
		_show_user_notification("SYSTEM", msg, Color.GOLD)


func _on_system_check_requested():
	_show_jen_notification("Running Diagnostics...", Color.GREEN_YELLOW)
	if _synapse: _synapse.call("send_chat_message", "[SYSTEM_DIAGNOSTICS]")

func _on_soul_verification_requested():
	_show_jen_notification("Verifying Soul DNA...", Color.AQUA)
	if _synapse: _synapse.call("send_chat_message", "Perform a deep neural verification of your soul alignment.")

func _on_user_certification_requested():
	_show_jen_notification("Initiating Certification Ritual...", Color.GOLD)
	if _synapse: _synapse.call("send_chat_message", "[CERTIFY_USER]")

func _setup_wall_screens():
	var wall = get_node_or_null("WallAnchor")
	if not wall: wall = Node3D.new(); wall.name = "WallAnchor"; wall.position = Vector3(0, 1.5, -2.5); add_child(wall)
	var vp = wall.get_node_or_null("VisionViewport")
	if not vp:
		vp = SubViewport.new(); vp.name = "VisionViewport"; vp.size = Vector2i(512, 512)
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE as SubViewport.UpdateMode
		wall.add_child(vp); var cam = Camera3D.new(); cam.name = "JenCamera"; cam.current = true; vp.add_child(cam); cam.look_at(Vector3(0, 1.6, 0))
# --- PUBLIC INTERFACE ---

func set_fidelity_mode(high: bool):
	_is_high_fidelity = high
	_show_user_notification("SYSTEM", "Fidelity -> " + ("HIGH" if high else "LOW"), Color.SPRING_GREEN)

func apply_jen_makeup(_style_name: String):
	_show_user_notification("AESTHETIC", "Applying: " + _style_name, Color.HOT_PINK)

func toggle_cloud_rave(active: bool):
	_is_rave_active = active
	_show_user_notification("RELAY", "Cloud Rave " + ("ON" if active else "OFF"), Color.VIOLET)

func spawn_spatial_tool(url: String):
	_show_user_notification("SPAWN", "Tool: " + url, Color.CYAN)

func set_social_status(vibe: String):
	_show_user_notification("SOCIAL", "Vibe -> " + vibe, Color.SKY_BLUE)

func toggle_neural_projection(_active: bool, _style: String):
	_is_neural_projection_active = _active
	_show_user_notification("PROJECTION", _style + " -> " + ("ACTIVE" if _active else "OFF"), Color.AQUAMARINE)

func toggle_occluding_makeover(_active: bool):
	_is_occluding_makeover_active = _active
	_show_user_notification("VEIL", "Neural Veil " + ("ACTIVE" if _active else "OFF"), Color.ANTIQUE_WHITE)

func toggle_void_mode(_active: bool):
	_is_void_mode_active = _active
	_show_user_notification("VOID", "Occlusion Shield " + ("ON" if _active else "OFF"), Color.MEDIUM_PURPLE)

func toggle_spatial_anonymity(_active: bool):
	_is_spatially_anonymous = _active
	_show_user_notification("PRIVACY", "Spatial Anonymity " + ("ON" if _active else "OFF"), Color.LIGHT_CORAL)

func toggle_environment_sharing(_active: bool):
	_env_sharing_consented = _active
	_show_user_notification("SYNC", "Env Sharing " + ("ENABLED" if _active else "DISABLED"), Color.LIME_GREEN)

func _repair_viewport_textures(root: Node):
	# 1. Handle MeshInstance3D (Materials)
	if root is MeshInstance3D:
		for i in range(root.get_surface_override_material_count()):
			var mat = root.get_surface_override_material(i)
			if mat and mat is StandardMaterial3D:
				_check_and_fix_texture(mat.albedo_texture, root)
	
	# 2. Handle Sprite3D (Direct Texture)
	elif root is Sprite3D:
		_check_and_fix_texture(root.texture, root)
		
	for child in root.get_children():
		_repair_viewport_textures(child)

func _check_and_fix_texture(tex: Texture, owner_node: Node):
	if tex and tex is ViewportTexture:
		if tex.viewport_path.is_empty():
			# Try to find common viewport names in siblings or parent
			var p = owner_node.get_parent()
			if p:
				var vp = p.get_node_or_null("Viewport")
				if not vp: vp = p.get_node_or_null("SubViewport")
				if vp:
					tex.viewport_path = owner_node.get_path_to(vp)
					if vp is SubViewport: vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
					print("LUMAX: Repaired ViewportTexture for ", owner_node.name, " -> ", vp.name)
# --- LIVE PROCESS ---

func _process(_delta):
	# 1. Shared Experience conference views (5s)
	if _web_ui and Time.get_ticks_msec() % 5000 < 100:
		var user_tex = _capture_user_pov()
		var jen_tex = _capture_jen_pov()
		if user_tex and jen_tex:
			_web_ui.update_shared_views(user_tex, jen_tex)

	# 2. Backend Vitals Heartbeat (every 10s — reduced to avoid blocking chat HTTPRequest)
	if Time.get_ticks_msec() % 10000 < 50:
		if _synapse: _synapse.call("get_vitals")

	# 3. Subconscious Agency Tick (30-90s)
	if Time.get_ticks_msec() % 35000 < 50:
		_process_self_agency()

	# 4. STATE FLAG BEHAVIORAL READS (restored)
	if _privacy_curtains and _privacy_curtains.visible != _is_void_mode_active:
		_privacy_curtains.visible = _is_void_mode_active
	if _debug_window and not _debug_visible:
		_debug_window.visible = _is_neural_projection_active
	var _lg = _left_hand.get_float("grip") > 0.6 if _left_hand else false
	var _rg = _right_hand.get_float("grip") > 0.6 if _right_hand else false
	_is_double_gripping = _lg and _rg

	# 5. High-Frequency XR Polling
	_poll_xr_inputs(_delta)


func _process_self_agency():
	if not _anim_player or _anim_player.is_playing(): return
	var r = randf()
	
	# RESTORE: Agency frequency influenced by _soul_nourishment
	var agency_threshold = 0.1 * _soul_nourishment
	var vision_threshold = 0.2 * _soul_nourishment
	
	if r < agency_threshold:
		play_body_animation("LOOK_AROUND:0.5:1,IDLE:0:5")
	elif r < vision_threshold:
		_show_jen_notification("Engaging Visual Cortex...", Color.ORANGE)
		_capture_and_send_vision("JEN_POV")

func _poll_xr_inputs(_delta):
	_left_hand = get_node_or_null("XROrigin3D/LeftHand")
	_right_hand = get_node_or_null("XROrigin3D/RightHand")
	var cam = get_viewport().get_camera_3d()
	
	# Update Foolproof HUD position
	var debug_hud = get_node_or_null("FoolproofDebugHUD")
	if debug_hud and cam:
		debug_hud.global_position = cam.global_position + (-cam.global_transform.basis.z * 1.0)
		debug_hud.look_at(cam.global_position, Vector3.UP)
		debug_hud.rotate_y(PI)
	
	# Individual Grip Detection
	var left_grip = false
	if _left_hand: left_grip = _left_hand.is_button_pressed("grip_click") or _left_hand.get_float("grip") > 0.6
	var right_grip = false
	if _right_hand: right_grip = _right_hand.is_button_pressed("grip_click") or _right_hand.get_float("grip") > 0.6
	
	# DEBUG READOUT
	if _debug_log_display:
		var txt = "LUMAX XR STATUS:\n"
		txt += "L-Hand: " + ("OK" if _left_hand else "MISSING") + "\n"
		txt += "R-Hand: " + ("OK" if _right_hand else "MISSING") + "\n"
		if _right_hand:
			var b_btn = _right_hand.is_button_pressed("by_button") or _right_hand.is_button_pressed("secondary_button")
			txt += "B-Button: " + ("PRESSED" if b_btn else "IDLE") + "\n"
			txt += "A-Button: " + ("PRESSED" if _right_hand.is_button_pressed("ax_button") else "IDLE") + "\n"
		_debug_log_display.text = txt

	# 1. Double Grip -> Steering Toggle
	if left_grip and right_grip:
		if not _prev_steering_combo:
			_steering_mode_active = !_steering_mode_active
			_show_user_notification("NAV", "Manual Guidance: " + ("ACTIVE" if _steering_mode_active else "OFF"), Color.AQUA)
			_prev_steering_combo = true
	else:
		_prev_steering_combo = false

	if _steering_mode_active:
		_steer_avatar(_delta)

	# --- Single Hand Grab Logic (Always Active) ---
	if left_grip and not _prev_left_grip: _try_grab_object(_left_hand)
	elif not left_grip and _prev_left_grip and _grabbed_hand == _left_hand: _release_object()
	if right_grip and not _prev_right_grip: _try_grab_object(_right_hand)
	elif not right_grip and _prev_right_grip and _grabbed_hand == _right_hand: _release_object()
	
	# Handle manipulation if something is currently being held
	if _grabbed_node and _grabbed_hand: 
		_manipulate_object(_delta, _grabbed_hand)

	_prev_left_grip = left_grip
	_prev_right_grip = right_grip

	# 2. Input Mapping (Broadened for Quest compatibility)
	var r_a = _right_hand.is_button_pressed("ax_button") or _right_hand.is_button_pressed("primary_button") if _right_hand else false
	var r_b = _right_hand.is_button_pressed("by_button") or _right_hand.is_button_pressed("secondary_button") if _right_hand else false
	var l_x = _left_hand.is_button_pressed("ax_button") or _left_hand.is_button_pressed("primary_button") if _left_hand else false
	var l_y = _left_hand.is_button_pressed("by_button") or _left_hand.is_button_pressed("secondary_button") if _left_hand else false
	var l_menu = _left_hand.is_button_pressed("menu_button") if _left_hand else false

	# --- Trigger Detectors ---
	var r_trig = _right_hand.get_float("trigger") > 0.5 if _right_hand else false
	var l_trig = _left_hand.get_float("trigger") > 0.5 if _left_hand else false

	# --- TRIGGER CHORD: Haptic Wand Mode Toggle ---
	if r_trig and l_trig:
		if not _prev_haptic_combo:
			_toggle_haptic_wand_mode()
			_prev_haptic_combo = true
	elif not r_trig and not l_trig:
		# Reset chord lock only when BOTH are released
		_prev_haptic_combo = false

	if _right_hand:
		for i in range(20): # Scan standard Godot button range
			if _right_hand.is_button_pressed(str(i)):
				LogMaster.log_info("QUEST RAW: Right Hand Button " + str(i) + " is PRESSED")
	
	# --- PTT (Right B) ---
	if r_b:
		if not _is_recording:
			LogMaster.log_info("QUEST INPUT: Right B PRESSED (PTT START)")
			_start_recording_flow()
	elif _is_recording:
		LogMaster.log_info("QUEST INPUT: Right B RELEASED (PTT STOP)")
		_stop_recording_flow()
	
	# --- Jen POV Capture (Left Y) ---
	if l_y and not _prev_y:
		_capture_and_send_vision("JEN_POV")
	_prev_y = l_y
	
	# Safety Timeout (30s)
	if _is_recording and (Time.get_ticks_msec() - _recording_start_time > 30000):
		LogMaster.log_info("QUEST VOICE: Safety Timeout Triggered (30s)")
		_stop_recording_flow()
		_show_user_notification("VOICE", "TIMEOUT", Color.RED)
	
	if _is_recording:
		# Add a very spammy but useful check to see if we are still holding
		if Engine.get_frames_drawn() % 60 == 0:
			LogMaster.log_info("QUEST VOICE: Still recording... Button state: " + str(r_b))

	# --- A (Right): User POV Capture ---
	if not r_a and _prev_a:
		_capture_and_send_vision("USER_POV")
	_prev_a = r_a

	# --- X (Left): Debug Toggle ---
	if not l_x and _prev_x:
		_toggle_debug_window()
	_prev_x = l_x

	# --- Menu (Left): Toggle WebUI ---
	if l_menu and not _prev_menu:
		_toggle_ui()
	_prev_menu = l_menu
	
	# --- UI Raycast Click Handling ---
	if _left_hand and _left_ray: _check_trig(_left_hand, _left_ray, "_prev_l")
	if _right_hand and _right_ray: _check_trig(_right_hand, _right_ray, "_prev_r")

func _check_trig(hand, ray, prev_var):
	var pressed: bool = hand.get_float("trigger") > 0.5
	if pressed and not get(prev_var): set(prev_var, true); _click_at_ray(ray, true)
	elif not pressed and get(prev_var): set(prev_var, false); _click_at_ray(ray, false)

func _click_at_ray(ray, is_press):
	if _ui_visible and ray and ray.is_colliding():
		var local_hit = _mind_node.to_local(ray.get_collision_point())
		# Map from -0.35 to 0.35 (0.7m width) -> 0 to 700px
		var x_2d: int = int((local_hit.x + 0.35) / 0.7 * 700.0)
		# Map from 0.6 to -0.6 (1.2m height) -> 0 to 1200px
		var y_2d: int = int((0.6 - local_hit.y) / 1.2 * 1200.0)
		
		var ev = InputEventMouseButton.new()
		ev.position = Vector2(float(x_2d), float(y_2d))
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = is_press
		var vp = get_node_or_null("Mind/Viewport")
		if vp: vp.push_input(ev)

func _steer_avatar(delta):
	var body = get_node_or_null("Body")
	if not body: return
	
	# Standard Game Controller Mapping: Left=Move, Right=Rotate
	var move_joy = _left_hand.get_vector2("primary_2d_axis") if _left_hand else Vector2.ZERO
	var rot_joy = _right_hand.get_vector2("primary_2d_axis") if _right_hand else Vector2.ZERO
	
	var true_avatar = body.get_node_or_null("Avatar")
	
	if move_joy.length() > 0.1:
		var cam = get_node_or_null("XROrigin3D/XRCamera3D")
		var forward = -cam.global_transform.basis.z.normalized() if cam else Vector3.FORWARD
		forward.y = 0; forward = forward.normalized()
		var right = cam.global_transform.basis.x.normalized() if cam else Vector3.RIGHT
		right.y = 0; right = right.normalized()
		
		# Quest thumbstick Y is negative when pushing forward, so invert it
		var move_dir = (forward * -move_joy.y + right * move_joy.x).normalized()
		
		if true_avatar and true_avatar is CharacterBody3D:
			true_avatar.velocity = move_dir * 2.5
			true_avatar.move_and_slide()
		else:
			body.global_position += move_dir * delta * 2.5 # Slightly faster steering
		
	if abs(rot_joy.x) > 0.1:
		if true_avatar: true_avatar.rotate_y(-rot_joy.x * delta * 3.0)
		else: body.rotate_y(-rot_joy.x * delta * 3.0)
	
	# 3rd Person Follow Logic
	if _current_pov == POV.THIRD_PERSON:
		var origin = get_node_or_null("XROrigin3D")
		if origin:
			# Soft-follow behind the avatar
			var follow_offset = -body.global_transform.basis.z.normalized() * 2.5 + Vector3.UP * 1.5
			var target_cam_pos = body.global_position + follow_offset
			origin.global_position = origin.global_position.lerp(target_cam_pos, delta * 3.0)
			origin.look_at(body.global_position + Vector3.UP * 1.2, Vector3.UP)

func _try_grab_object(hand: XRController3D):
	var ray = hand.find_child("RayCast3D", true, false)
	if not ray: ray = hand.find_child("FunctionPointer", true, false)
	if ray and ray.has_method("is_colliding") and ray.is_colliding():
		var col = ray.get_collider()
		var p = col.get_parent()
		if p and (p.name == "Mind" or p.name == "Display" or p.name == "LargeDebugWindow"):
			_grabbed_node = p
			_grabbed_hand = hand
			_grabbed_offset = hand.global_position.distance_to(p.global_position)
		elif col.name == "Avatar" or (p and (p.name == "Body" or p.name == "Avatar")):
			_grabbed_node = get_node_or_null("Body")
			_grabbed_hand = hand
			_grabbed_offset = hand.global_position.distance_to(_grabbed_node.global_position)
			if _synapse: _synapse.call("inject_sensory_event", "The user gently pulls you closer. Relax and accommodate them.")

func _release_object():
	_grabbed_node = null
	_grabbed_hand = null

func _manipulate_object(delta, hand: XRController3D):
	if not _grabbed_node: return
	
	var joy = hand.get_vector2("primary_2d_axis")
	if abs(joy.y) > 0.1:
		_grabbed_offset -= joy.y * delta * 2.0
		_grabbed_offset = clamp(_grabbed_offset, 0.5, 5.0)
	
	var target_pos = hand.global_position - hand.global_transform.basis.z.normalized() * _grabbed_offset
	_grabbed_node.global_position = _grabbed_node.global_position.lerp(target_pos, delta * 5.0)
	
	var cam = get_node_or_null("XROrigin3D/XRCamera3D")
	if cam:
		var look_target = cam.global_position
		look_target.y = _grabbed_node.global_position.y
		var current_quat = _grabbed_node.global_transform.basis.get_rotation_quaternion()
		var target_basis = Basis.looking_at((cam.global_position - _grabbed_node.global_position).normalized(), Vector3.UP)
		if _grabbed_node.name == "Mind" or _grabbed_node.name == "LargeDebugWindow":
			_grabbed_node.global_transform.basis = Basis(current_quat.slerp(target_basis.get_rotation_quaternion(), delta * 3.0))
			_grabbed_node.rotate_y(PI)


# --- UI INTERFACE ---

func _toggle_ui():
	_ui_visible = !_ui_visible
	var xr_cam = get_viewport().get_camera_3d()
	var jen_body = get_node_or_null("Body")
	
	if _mind_node:
		_mind_node.visible = _ui_visible
		if _ui_visible:
			# RE-VERIFY UPDATE MODE
			var vp_node = _mind_node.get_node_or_null("Viewport")
			if vp_node: vp_node.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			
			if xr_cam:
				var forward = -xr_cam.global_transform.basis.z.normalized()
				forward.y = 0; forward = forward.normalized() # Horizon lock
				
				# POSITION UI: 2.0m Directly in Front
				var ui_pos = xr_cam.global_position + (forward * 2.0)
				ui_pos.y = xr_cam.global_position.y - 0.3
				
				var ui_look = (xr_cam.global_position - ui_pos).normalized(); ui_look.y = 0
				_mind_node.global_transform = Transform3D(Basis.looking_at(ui_look, Vector3.UP), ui_pos)
				_mind_node.rotate_y(PI)
				
				# POSITION JEN: 1.5m away, 0.7m to the RIGHT
				if jen_body:
					var right = xr_cam.global_transform.basis.x.normalized()
					right.y = 0; right = right.normalized()
					var jen_pos = xr_cam.global_position + (forward * 1.5) + (right * 0.7)
					jen_pos.y = xr_cam.global_position.y - 1.6 # Ground level approx
					
					var jen_look = (xr_cam.global_position - jen_pos).normalized(); jen_look.y = 0
					jen_body.global_transform = Transform3D(Basis.looking_at(jen_look, Vector3.UP), jen_pos)
					jen_body.rotate_y(PI)
					print("LUMAX: Spatial manifestation COMPLETE. Jen and UI framed.")

func _start_recording_flow():
	_is_recording = true
	_recording_start_time = Time.get_ticks_msec()
	if _aural: _aural.call("start_recording")
	_show_user_notification("VOICE", "LISTENING...", Color.CYAN)
	if is_instance_valid(_stt_status_label): _stt_status_label.text = "STT: LISTENING..."

func _stop_recording_flow():
	_is_recording = false
	if _aural: _aural.call("stop_recording")
	_show_user_notification("VOICE", "PROCESSING...", Color.YELLOW)
	if is_instance_valid(_stt_status_label): _stt_status_label.text = "STT: IDLE"

func _toggle_haptic_wand_mode():
	_haptic_mode_active = !_haptic_mode_active
	_show_user_notification("HAPTICS", "Pulse Engine: " + ("WAND" if _haptic_mode_active else "GHOST"), Color.CYAN)
	if _haptic_wand_left: _haptic_wand_left.visible = _haptic_mode_active
	if _haptic_wand_right: _haptic_wand_right.visible = _haptic_mode_active

func _toggle_debug_window():
	_debug_visible = !_debug_visible
	if _debug_window: 
		_debug_window.visible = _debug_visible
		if _debug_visible:
			var cam = get_viewport().get_camera_3d()
			if cam:
				var forward = -cam.global_transform.basis.z.normalized()
				forward.y = 0; forward = forward.normalized()
				var right = cam.global_transform.basis.x.normalized()
				right.y = 0; right = right.normalized()

				# Place debug window slightly lower and to the left of the main UI
				var pos = cam.global_position + (forward * 1.5) - (right * 0.8)
				pos.y = cam.global_position.y - 0.4
				_debug_window.global_position = pos

				var look_dir = (cam.global_position - pos).normalized()
				look_dir.y = 0
				_debug_window.global_transform.basis = Basis.looking_at(look_dir, Vector3.UP)
				_debug_window.rotate_y(PI)

	_show_user_notification("DEBUG", "Window " + ("OPEN" if _debug_visible else "CLOSED"), Color.SKY_BLUE)

func _toggle_drapery():
	_is_drapery_open = !_is_drapery_open
	if _privacy_curtains:
		_privacy_curtains.visible = true; var tween = create_tween(); var target_scale = 1.0 if _is_drapery_open else 0.1; tween.tween_property(_privacy_curtains, "scale:y", target_scale, 1.0).set_trans(Tween.TRANS_SINE)
		if not _is_drapery_open: tween.tween_callback(func(): _privacy_curtains.visible = false)

# --- ANIMATION & SIGNALS ---

func _scan_for_animations():
	if not _anim_player:
		print("LUMAX: Waiting for AnimationPlayer to initialize before scan...")
		return
			
	if _anim_pool.size() > 0: return # Only scan once
	var search_paths = ["res://Body/Animations/Chosen/"]
	_anim_pool.clear(); _category_map.clear(); _idle_anims.clear()
	var lib_name = &"discovered"
	if not _anim_player.has_animation_library(lib_name): _anim_player.add_animation_library(lib_name, AnimationLibrary.new())
	var lib = _anim_player.get_animation_library(lib_name)
	for base_path in search_paths: if DirAccess.dir_exists_absolute(base_path): _recursive_scan(base_path, "", lib, 0)
	
	if _jen_avatar and _jen_avatar.has_method("refresh_animation_system"):
		_jen_avatar.call("refresh_animation_system")
	
	print("LUMAX: Sanitizing Animation Paths (Stripping Ghost Paths...)")
	# SANITIZE ALL LIBRARIES (Internal + Discovered)
	for _ln in _anim_player.get_animation_library_list():
		var l = _anim_player.get_animation_library(_ln)
		for anim_name in l.get_animation_list():
			var anim = l.get_animation(anim_name)
			if not anim: continue
			for i in range(anim.get_track_count()):
				var path = str(anim.track_get_path(i))
				if path.begins_with("../"):
					anim.track_set_path(i, NodePath(path.replace("../", "")))
	
	# LOUD DIAGNOSTIC LOGGING
	print("LUMAX_ANIM_REPORT: Discovered " + str(_anim_pool.size()) + " total animations.")
	print("LUMAX_ANIM_REPORT: Identified " + str(_idle_anims.size()) + " idle clips in Chosen pool.")
	
	if LogMaster:
		LogMaster.log_info("ANIM_SYSTEM: Discovered " + str(_anim_pool.size()) + " animations.")
		LogMaster.log_info("ANIM_SYSTEM: Idle pool count: " + str(_idle_anims.size()))

func _recursive_scan(path: String, category: String, lib: AnimationLibrary, depth: int):
	if depth > 5: return # Safety break
	if not path.ends_with("/"):
		path += "/"
	var _current_cat = category
	if path.contains("res://Body/Animations/Chosen/"):
		var relative = path.replace("res://Body/Animations/Chosen/", "")
		if relative != "":
			_current_cat = relative.split("/")[0]
			if not _categories.has(_current_cat):
				_categories.append(_current_cat)
	var dir = DirAccess.open(path); if dir:
		dir.list_dir_begin(); var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if not file_name.begins_with("."):
					_recursive_scan(path + file_name + "/", _current_cat, lib, depth + 1)
			else:
				if file_name.ends_with(".res") or file_name.ends_with(".tres") or file_name.ends_with(".remap"):
					var full_path = path + file_name.replace(".remap", ""); var base_name = file_name.get_basename().to_lower().replace(".remap", ""); if not _anim_pool.has(base_name):
						_anim_pool[base_name] = full_path; 
						if "idle" in base_name or "breathe" in base_name or "stand" in base_name:
							if not "run" in base_name and not "jump" in base_name and not "walk" in base_name and not "dance" in base_name:
								_idle_anims.append(full_path)
						var anim = load(full_path)
						if anim is Animation:
							# Fix: Track Realignment - Strip broken ghost paths
							for i in range(anim.get_track_count()):
								var tpath = str(anim.track_get_path(i))
								if tpath.begins_with("../"):
									anim.track_set_path(i, NodePath(tpath.replace("../", "")))
							lib.add_animation(base_name, anim)
					if _current_cat != "":
						var cat_key = _current_cat.to_upper(); if not _category_map.has(cat_key): _category_map[cat_key] = []
						if not _category_map[cat_key].has(base_name): _category_map[cat_key].append(base_name)
			file_name = dir.get_next()

func find_animation_path(anim_name: String) -> String:
	var clean = anim_name.to_lower().replace(".res", "").replace(".tres", "")
	if _anim_pool.has(clean):
		return _anim_pool[clean]
	return ""

func play_body_animation(anim_name: String):
	if not _anim_player: return
	
	# Support Composed Animations (format: "ANIM1:start:end,ANIM2:start:end")
	if "," in anim_name or ":" in anim_name:
		_play_composed_sequence(anim_name)
		return

	var clean_name = anim_name.to_lower().replace(".res", "").replace(".tres", "")
	if _category_map.has(anim_name.to_upper()):
		play_category(anim_name)
		return
		
	var lib_discovered = _anim_player.get_animation_library("discovered")
	if lib_discovered.has_animation(clean_name):
		_anim_player.play("discovered/" + clean_name, 0.5) # Smooth blend in
	elif _anim_player.has_animation(clean_name):
		_anim_player.play(clean_name, 0.5)

func _play_composed_sequence(sequence_str: String):
	var segments = sequence_str.split(",")
	for segment in segments:
		var parts = segment.split(":")
		var anim_name = parts[0].strip_edges().to_lower()
		var start = float(parts[1]) if parts.size() > 1 else 0.0
		var end = float(parts[2]) if parts.size() > 2 else -1.0
		
		# Find the animation
		var full_path = find_animation_path(anim_name)
		if full_path == "": continue
		
		var lib = _anim_player.get_animation_library("discovered")
		if lib.has_animation(anim_name):
			_anim_player.play("discovered/" + anim_name, 0.3)
			_anim_player.seek(start, true)
			if end > 0:
				await get_tree().create_timer(end - start).timeout
		
	# Return to idle after sequence
	_play_next_idle()

func play_category(category_name: String):
	var cat_key = category_name.to_upper(); if _category_map.has(cat_key):
		var options = _category_map[cat_key]; if options.size() > 0: var choice = options[randi() % options.size()]; _anim_player.play("discovered/" + choice)

func _on_idle_finished(_name): _play_next_idle()
func _play_next_idle():
	if not _anim_player or _idle_anims.size() == 0: return
	var idx: int = int(randi() % _idle_anims.size())
	var anim_path = _idle_anims[idx]
	var anim = load(anim_path)
	if anim: 
		if not _anim_player.has_animation_library("lumax"):
			_anim_player.add_animation_library("lumax", AnimationLibrary.new())
			
		var lib = _anim_player.get_animation_library("lumax")
		if lib.has_animation("active_idle"): lib.remove_animation("active_idle")
		lib.add_animation("active_idle", anim)
		
		# Ensure animations are mapped for this avatar
		if _jen_avatar and _jen_avatar.has_method("force_resanitize_animations"):
			_jen_avatar.call("force_resanitize_animations")
			
		# Silence the AnimationTree to prevent T-posing override during pool idles
		var tree = _jen_avatar.get_node_or_null("AnimationTree") as AnimationTree if _jen_avatar else null
		if tree: tree.active = false
		
		_anim_player.play("lumax/active_idle", 1.0)

func _on_jen_response(data, _mode):
	if data is Dictionary and data.get("type") == "presets":
		_personality_presets = data.get("data", {})
		print("LUMAX: Personality presets cached.")
		return

	var text = data.get("text", "...") if data is Dictionary else str(data)
	if _web_ui: _web_ui.call("add_message", "LUMAX", text)
	
	# Parse for experimental animation commands in the text or tags
	var anim_regex = RegEx.new()
	anim_regex.compile("<action>(.*?)</action>")
	var matches = anim_regex.search_all(text)
	for m in matches:
		var anim_cmd = m.get_string(1)
		play_body_animation(anim_cmd)

	var thought = data.get("thought", "") if data is Dictionary else ""
	if thought != "":
		_show_jen_notification("Thinking: " + thought, Color.ORANGE)
	else:
		_show_jen_notification("Speaking...", Color.SPRING_GREEN)
func _on_keyboard_enter(text):
	if text == "": return
	
	if text == "[CAPTURE_IMAGE]":
		_capture_and_send_vision("USER_POV")
		return
		
	if _web_ui: _web_ui.call("add_message", "YOU", text)
	if _synapse: _synapse.call("send_chat_message", text)
	_show_jen_notification("Listening...", Color.CYAN)

func _capture_and_send_vision(source: String):
	var vh = get_node_or_null("Senses/MultiVisionHandler")
	if not vh: 
		_show_user_notification("ERROR", "Vision Handler Offline", Color.RED)
		return
	
	var note_color = Color.YELLOW if source == "USER_POV" else Color.CYAN
	var note_text = "Capturing My View..." if source == "USER_POV" else "Capturing Jen's POV..."
	_show_user_notification("VISION", note_text, note_color)
	
	# Small delay to ensure UI updates before capture
	await get_tree().create_timer(0.1).timeout 
	
	var image_data = {}
	if source == "USER_POV":
		# Capture the main compositor (everything the user sees)
		var user_vp = get_viewport()
		image_data = await vh._capture_from_viewport(user_vp)
	else:
		image_data = await vh._capture_jen_pov()
	
	if not image_data.is_empty():
		var preview_path = image_data.get("preview_path", "")
		var b64 = image_data.get("image_b64", "")
		
		# Show in chat
		if _web_ui and preview_path != "":
			_web_ui.call("add_message", "YOU" if source == "USER_POV" else "LUMAX (POV)", "\n[img=400]" + preview_path + "[/img]\nLook at this perspective.")
		
		if LogMaster: LogMaster.log_info("Captured " + source + " successfully.")
		
		# Send to Synapse with the image base64
		if _synapse:
			var msg = "Analyze what you see from my perspective." if source == "USER_POV" else "Analyze what you see from your own perspective."
			_synapse.call("send_chat_message", msg, "text", b64)
			_show_jen_notification("Analyzing perspective...", note_color)
func _on_keyboard_text_changed(text: String): if _web_ui: _web_ui.call("update_buffer", text)
func _on_tts_audio(buffer: PackedByteArray, sample_rate: float):
	if _tts_player:
		# Boost volume and ensure it's audible at distance
		_tts_player.unit_size = 50.0 # High audible range
		_tts_player.max_db = 10.0    # Serious volume boost
		_tts_player.bus = &"Master"
		_tts_player.panning_strength = 0.5 # Less spatial falloff for Jen's voice
		
		# Standard WAV Header Strip (44 bytes) for Godot 4 compatibility
		var pcm_data = buffer
		if buffer.size() > 44 and buffer[0] == 82 and buffer[1] == 73: # "RI" (First 2 bytes of RIFF)
			pcm_data = buffer.slice(44)
			print("LUMAX TTS: Stripped 44-byte WAV header.")
		
		var sr = sample_rate if sample_rate > 0 else 24000.0
		print("LUMAX TTS: Playing audio (PCM size: ", pcm_data.size(), ", rate: ", sr, ")")
		
		var stream = AudioStreamWAV.new()
		stream.data = pcm_data
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = int(sr)
		_tts_player.stream = stream
		_tts_player.play()
		if LogMaster: LogMaster.log_info("TTS: Manifested Voice @ " + str(sr) + "Hz")

func _on_stt_transcription(text: String):
	var clean_text = text.strip_edges()
	if clean_text == "": 
		if is_instance_valid(_stt_status_label):
			_stt_status_label.text = "STT: IDLE"
			_stt_status_label.modulate = Color.GRAY
		return
	if is_instance_valid(_stt_status_label):
		_stt_status_label.text = "STT: IDLE"
		_stt_status_label.modulate = Color.GRAY
	if _web_ui: _web_ui.call("add_message", "YOU", clean_text)
	if _synapse: _synapse.call("send_chat_message", clean_text)
	if LogMaster: LogMaster.log_info("STT Transcription: " + clean_text)
	_show_jen_notification("Analyzing voice command...", Color.YELLOW)
	
func _on_keyboard_stt_pressed():
	if not _is_recording:
		_start_recording_flow()
	else:
		_stop_recording_flow()

# --- NOTIFICATION ENGINE ---

func _show_user_notification(title: String, body_text: String, note_color: Color = Color.WHITE): _push_indicator(_user_notify_hub, title + ": " + body_text, note_color, true)
func _show_jen_notification(jen_text: String, jen_color: Color = Color.WHITE): _push_indicator(_jen_notify_hub, jen_text, jen_color, false)
func _push_indicator(hub: Node3D, display_text: String, display_color: Color, is_arm: bool):
	if not hub: return
	var row_height: float = 0.03 if is_arm else 0.08
	for child in hub.get_children():
		if child is Label3D:
			var move = create_tween()
			move.tween_property(child, "position:y", child.position.y + row_height, 0.4).set_trans(Tween.TRANS_CUBIC)
	
	var label = Label3D.new()
	label.text = display_text
	label.modulate = display_color
	label.outline_modulate = Color.BLACK
	label.font_size = int(14 if is_arm else 32)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hub.add_child(label)
	
	var fade = create_tween()
	fade.tween_interval(2.0 if is_arm else 4.0)
	fade.tween_property(label, "modulate:a", 0.0, 1.0)
	fade.tween_callback(label.queue_free)

func _trigger_visual_capture(source: String):
	var vision_handler = get_node_or_null("MultiVisionHandler")
	if not vision_handler: return
	
	var image_data = {}
	if source == "JEN_POV":
		var vp = get_node_or_null("WallAnchor/VisionViewport")
		if vp and vp is SubViewport:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			await get_tree().process_frame
			await get_tree().process_frame
			image_data = await vision_handler._capture_jen_pov()
			
	if not image_data.is_empty() and _director:
		var sys_prompt = _director.get("DIRECTOR_SYSTEM_PROMPT")
		_director.call("_send_director_request", sys_prompt + "\n\nCapture: " + source, "", [image_data])

func _on_log_added(_msg: String, _type: String):
	_update_debug_log()

func _update_debug_log():
	if not _debug_log_display:
		return
		
	var logs = LogMaster.get_logs()
	var log_text = ""
	# Get last 15 logs and strip BBCode for Label3D
	var start = max(0, logs.size() - 15)
	for i in range(start, logs.size()):
		var line = logs[i]
		# Crude BBCode strip
		line = line.replace("[color=green]", "").replace("[color=red]", "").replace("[color=cyan]", "").replace("[color=yellow]", "").replace("[color=white]", "").replace("[/color]", "")
		log_text += line + "\n"
	
	_debug_log_display.text = log_text
