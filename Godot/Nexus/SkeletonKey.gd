extends Node3D

# --- CORE SERVICES ---
var _synapse: Node = null
var _synapse_fail_last_msg: String = ""
var _synapse_fail_last_time_sec: float = -999.0
const _SYNAPSE_FAIL_LOG_THROTTLE_SEC: float = 6.0
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
var _prev_steer_trig_chord = false
var _haptic_mode_active = false

var _haptic_wand_left: Node3D = null
var _haptic_wand_right: Node3D = null

var _grabbed_node: Node3D = null
var _grabbed_offset: float = 1.0
var _grabbed_hand: XRController3D = null
var _prev_left_grip = false
var _prev_right_grip = false
## XR chords: **both grips** (rising) = flexible rod haptic wands; **both triggers, no grips** (rising) = steer Jen;
## **both triggers + left grip_click** = puppet bones (see `_poll_xr_inputs`).
var _steering_mode_active = false
## Delay single-hand UI/body grabs so a **both-grips** chord (flexible-rod haptic toggle) can register before single-hand grab.
var _pending_left_grab_at: int = -1
var _pending_right_grab_at: int = -1
const _SINGLE_GRIP_DELAY_MS = 75
var _is_puppet_mode_active = false
var _prev_puppet_chord: bool = false
var _grabbed_bone_name = ""

# --- AGENCY & STATE ---
var _director: Node = null
var _soul_nourishment: float = 1.0 
var _social_vibe: String = "NEUTRAL"
var _is_high_fidelity: bool = true
var _is_rave_active: bool = false
var _is_neural_projection_active: bool = false
var _is_occluding_makeover_active: bool = false
var _is_void_mode_active: bool = false
var _is_spatially_anonymous: bool = false
var _env_sharing_consented: bool = false

# --- SOUL DNA (17 TRAITS) ---
var _soul_extrovert: float = 0.5
var _soul_intellectual: float = 0.5
var _soul_logic: float = 0.5
var _soul_detail: float = 0.5
var _soul_faithful: float = 0.5
var _soul_sexual: float = 0.5
var _soul_experimental: float = 0.5
var _soul_wise: float = 0.5
var _soul_openminded: float = 0.5
var _soul_honest: float = 0.5
var _soul_forgiving: float = 0.5
var _soul_feminine: float = 0.5
var _soul_dominant: float = 0.5
var _soul_progressive: float = 0.5
var _soul_sloppy: float = 0.5
var _soul_greedy: float = 0.5
var _soul_homonormative: float = 0.5

# --- NOTIFICATION HUBS ---
var _jen_notify_hub: Node3D = null
var _user_notify_hub: Node3D = null

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
var _discovered_import_done: bool = false
var _categories = ["Resting", "Happy", "Sad", "Greetings", "Exercise", "Sitting", "Laying", "Movement", "Feminine", "Masculine", "Manifestation", "Gymnastics", "Style", "Walking"]

## Chosen idle sticks on `mixamo/idle`; new clip only after this many idle completions (non-looping idles) or when variation roll hits.
@export var baseline_idle_min_completions_before_variation: int = 6
## After min completions, probability of picking a *new* Chosen idle when an idle ends (otherwise replay same clip).
@export var baseline_idle_variation_chance: float = 0.18
## Safety switch: use curated Chosen idle pool. Off keeps startup on stable idle path.
@export var use_chosen_idle_pool: bool = false
@export var subconscious_agency_interval_sec: float = 55.0
## When an agency tick runs, chance to play a non-idle micro-expression from the pool (0 = idle only unless soul/commands move her).
@export var subconscious_behavior_chance: float = 0.08
## If a behavior tick fires, prefer a chained slice sequence (several clips combined) this often.
@export var agency_composed_chain_probability: float = 0.28
@export var agency_composed_chains_enabled: bool = true
@export var agency_composed_segment_min: int = 2
@export var agency_composed_segment_max: int = 4
@export var agency_composed_slice_dur_min: float = 0.45
@export var agency_composed_slice_dur_max: float = 2.1
## Inside a behavior tick: short idle/breathe slice vs expressive clip (higher = calmer, more standing idle).
@export var agency_idle_micro_slice_bias: float = 0.68
## When a behavior tick runs: odds to play a named saved workflow instead of random improv.
@export var agency_saved_workflow_subchance: float = 0.18
## When a behavior tick runs: odds to play a favorited clip (if any favorites exist).
@export var agency_favorite_clip_chance: float = 0.22
## Filter sit/lay/jump/gymnastics from agency + composed sequences (AvatarController enforces the same for direct plays).
@export var block_posture_acrobatic_agency: bool = true
## If true, left-stick back can sit/stand_to_sit; if false, only walk/walk_back/strafe + idle (no posture flips).
@export var steering_allows_sit_stick_toggle: bool = false
## ENet multiverse: `off` | `host` | `client` — client uses `nat_peer_default` in `res://lumax_network_config.json` (Quest↔PC on LAN).
@export_enum("off", "host", "client") var multiverse_role: String = "off"

## Quest / OpenXR: reality vs virtuality. **Auto** = Lumax passthrough-first (same as legacy startup). **Pure passthrough** = alpha blend + video PT + immersive-AR when supported. **XR mixed** = additive blend + PT (more “hologram” over room). **VR** = opaque blend, passthrough off, immersive-VR when supported. Change at runtime from CORE → SETTINGS (`QUEST_DISPLAY_MODE`).
enum QuestDisplayMode { AUTO, PURE_PASSTHROUGH, XR_MIXED, VR_IMMERSIVE }
@export var quest_display_mode: QuestDisplayMode = QuestDisplayMode.AUTO

## Set these on **LumaxCore** (root of main scene). Defaults favor Quest stability over max UI refresh rate.
@export_group("Boot / Quest stability")
## If true (recommended on Quest): Mind SubViewport stays **UPDATE_WHEN_VISIBLE** — no delayed jump to **UPDATE_ALWAYS** (often crashy in XR).
@export var mind_subviewport_stay_when_visible: bool = true
## Skip Jen + user mirror SubViewports at boot (saves GPU/RAM; disables POV capture until you turn this off).
@export var boot_skip_vision_subviewports: bool = false
## Skip Mind / WebUI / keyboard wiring (crash isolation only — no panel UI).
@export var boot_skip_presence_cortex: bool = false
## Extra seconds before Mind/UI wiring. On **XR** (Quest, PC VR, Virtual Desktop, etc.) effective delay is **max(this, 1.25)** — standalone Android used to be the only path with a floor; Windows+OpenXR also needs it (otherwise apply fires at 0.00s and crashes).
@export var boot_presence_cortex_delay_sec: float = 0.0

const _ANIM_USER_PREFS_PATH := "user://lumax_jen_animation_prefs.json"
var _anim_favorites: PackedStringArray = PackedStringArray()
var _anim_workflows: Array = []

## Follow-user / explore-wander (disabled while steering or puppeting a bone).
@export var nav_follow_stop_distance: float = 1.15
@export var nav_follow_move_speed: float = 1.35
@export var nav_follow_turn_speed: float = 3.2
@export var nav_explore_radius: float = 4.5
@export var nav_explore_pause_min: float = 3.2
@export var nav_explore_pause_max: float = 8.5
@export var nav_explore_walk_speed: float = 1.12
## If true, follow/explore requests may be declined (traits + mood + random).
@export var nav_refusal_enabled: bool = true
@export var nav_refusal_base_chance: float = 0.2
## Each refused ask slightly increases odds the next request succeeds (caps internally).
@export var nav_refusal_persist_bonus: float = 0.12
## One-shot [WALK] / _move_to_user ignores refusal (set true for hard requests only).
@export var nav_refusal_applies_to_oneshot_approach: bool = false

## Local night window: Jen moves beside you, lies down (`[FORCE]lay`), soul consolidates memories + dream image (lumax_creativity); Director tutoring runs in that backend pass.
@export var night_sleep_near_user_enabled: bool = true
@export var night_sleep_hour_start: int = 23
@export var night_sleep_hour_end: int = 6
@export var night_sleep_check_interval_sec: float = 90.0
## Horizontal offset from user (XZ plane) before lay; lower = closer (e.g. 0.35–0.42 feels near-touch; too low may clip).
@export var night_sleep_beside_distance_m: float = 0.45

## Intimacy / haptics: distance bands (horizontal) from user camera to Jen for proximity factor.
@export var intimacy_proximity_far_m: float = 2.35
@export var intimacy_proximity_near_m: float = 0.78
## Minimum blended intimacy (0–1) before `[INTIMATE]` sit/lay/cuddle-style clips are allowed.
@export var intimate_posture_min_level: float = 0.42
@export var intimate_posture_max_distance_m: float = 1.18
## Proximity rumble on controllers near her body; scaled by intimacy + gentle touch + XR haptics slider.
@export var haptic_proximity_rumble_cap: float = 0.26
@export var haptic_intimacy_gain: float = 0.95
@export var haptic_gentle_touch_boost: float = 0.55
@export var haptic_proximity_radius_m: float = 0.42

var _baseline_idle_path: String = ""
var _idle_completions_since_variation: int = 0
var _agency_time_accum: float = 0.0

var _nav_follow_user: bool = false
var _nav_explore: bool = false
var _explore_leg_busy: bool = false
var _explore_pause_remaining: float = 0.0
var _explore_anchor: Vector3 = Vector3.ZERO
var _nav_move_tween: Tween = null
var _follow_was_moving: bool = false
var _nav_plead_streak: int = 0

var _night_sleep_poll_accum: float = 0.0
var _night_sleep_last_calendar_key: String = ""
var _night_sleep_sequence_running: bool = false
var _jen_night_rest_active: bool = false

var _touch_receipt_timer: float = 0.0
var _last_touch_gentle: bool = true
var _last_touch_intensity: float = 0.0
var _last_touch_region: String = ""

func _is_anim_player_in_baseline_idle_slot() -> bool:
	if not _anim_player or not _anim_player.is_playing():
		return false
	var ca := String(_anim_player.current_animation)
	return ca == "mixamo/idle" or ca == "lumax/active_idle"

func _is_puppeting_skeleton() -> bool:
	return _grabbed_node != null and is_instance_valid(_grabbed_node) and _grabbed_node is Skeleton3D

## While puppeting a bone, steering with stick, or a deliberate non-idle clip plays — don't stack agency moves.
func _should_suppress_self_agency() -> bool:
	if _jen_night_rest_active:
		return true
	if _is_puppeting_skeleton():
		return true
	if _nav_follow_user and _follow_was_moving:
		return true
	if _nav_explore and _explore_leg_busy:
		return true
	if _steering_mode_active:
		var joy := _left_hand.get_vector2("primary_2d_axis") if _left_hand else Vector2.ZERO
		if joy.length() > 0.12:
			return true
	if not _anim_player or not _anim_player.is_playing():
		return false
	return not _is_anim_player_in_baseline_idle_slot()

func _anim_key_is_idle_like_for_improv(key: String) -> bool:
	var k := key.to_lower()
	if k.contains("idle") or k.contains("breathe"):
		return true
	if k.contains("stand") and not (k.contains("greeting") or k.contains("point") or k.contains("clap") or k.contains("wave")):
		return true
	return false

func _sk_anim_segment_blocked(seg: String) -> bool:
	if not block_posture_acrobatic_agency:
		return false
	if _jen_avatar and _jen_avatar.has_method("_animation_motion_blocked"):
		return _jen_avatar.call("_animation_motion_blocked", seg)
	return false

func _collect_agency_idle_like_keys() -> Array:
	var out: Array = []
	for k in _anim_pool.keys():
		var ks := String(k)
		if _sk_anim_segment_blocked(ks):
			continue
		if _anim_key_is_idle_like_for_improv(ks):
			out.append(ks)
	return out

func _collect_agency_expressive_keys() -> Array:
	var out: Array = []
	for k in _anim_pool.keys():
		var ks := String(k)
		if _sk_anim_segment_blocked(ks):
			continue
		if _anim_key_is_idle_like_for_improv(ks):
			continue
		out.append(ks)
	return out

## Random multi-clip line for `play_body_animation` (comma-separated `name:start:end` segments).
func build_random_agency_composition() -> String:
	if _anim_pool.is_empty():
		return ""
	var candidates: Array = []
	for k in _anim_pool.keys():
		var ks := String(k)
		if _sk_anim_segment_blocked(ks):
			continue
		if _anim_key_is_idle_like_for_improv(ks):
			continue
		candidates.append(ks)
	if candidates.is_empty():
		for k2 in _anim_pool.keys():
			candidates.append(String(k2))
	if candidates.is_empty():
		return ""
	var mn := clampi(agency_composed_segment_min, 1, 12)
	var mx := clampi(agency_composed_segment_max, mn, 12)
	var n := randi_range(mn, mx)
	n = mini(n, candidates.size())
	candidates.shuffle()
	var segments: PackedStringArray = PackedStringArray()
	for i in n:
		var clip_key := str(candidates[i])
		var start_t := randf_range(0.0, 0.4)
		var dur := randf_range(
			minf(agency_composed_slice_dur_min, agency_composed_slice_dur_max),
			maxf(agency_composed_slice_dur_min, agency_composed_slice_dur_max)
		)
		segments.append("%s:%s:%s" % [clip_key, str(start_t), str(start_t + dur)])
	var out := ""
	for si in segments.size():
		if si > 0:
			out += ","
		out += segments[si]
	return out

func _finished_animation_is_baseline_idle_slot(anim_name: String) -> bool:
	if anim_name.is_empty():
		return false
	return anim_name == "mixamo/idle" or anim_name == "lumax/active_idle"

func _apply_chosen_idle_animation(anim: Animation) -> void:
	# AvatarController may late-bind VRM lungs; keep _anim_player aligned before writing mixamo/idle.
	if _jen_avatar:
		refresh_jen_anim_player()
	if not anim or not is_instance_valid(_anim_player):
		return
	# Safer path: keep Chosen idle in a dedicated slot and play directly on the resolved AnimationPlayer.
	# This avoids startup re-entry through AvatarController.play_animation("IDLE") while scene systems are still wiring.
	if not _anim_player.has_animation_library("lumax"):
		_anim_player.add_animation_library("lumax", AnimationLibrary.new())
	var lib := _anim_player.get_animation_library("lumax")
	if lib.has_animation("active_idle"):
		lib.remove_animation("active_idle")
	lib.add_animation("active_idle", anim)
	if _jen_avatar and _jen_avatar.has_method("resanitize_animation_resource"):
		_jen_avatar.call("resanitize_animation_resource", anim)
	_anim_player.active = true
	_anim_player.play("lumax/active_idle", 1.0)

func _idle_path_pool_standing_only() -> Array:
	var out: Array = []
	for p in _idle_anims:
		var bn := str(p).get_file().get_basename().to_lower()
		if _sk_anim_segment_blocked(bn):
			continue
		out.append(p)
	return out


func _pick_random_chosen_idle() -> void:
	if not _anim_player:
		return
	var pool: Array = _idle_path_pool_standing_only()
	if pool.is_empty():
		if _idle_anims.size() > 0 and _jen_avatar and _jen_avatar.has_method("play_animation"):
			_jen_avatar.call("play_animation", &"idle")
		return
	var idx: int = int(randi() % pool.size())
	_baseline_idle_path = str(pool[idx])
	var res = load(_baseline_idle_path)
	if res is Animation:
		_idle_completions_since_variation = 0
		_apply_chosen_idle_animation(res)
	else:
		_baseline_idle_path = ""

func _replay_baseline_idle() -> void:
	if not _anim_player or _idle_anims.size() == 0:
		return
	if not _baseline_idle_path.is_empty():
		var bbn := _baseline_idle_path.get_file().get_basename().to_lower()
		if _sk_anim_segment_blocked(bbn):
			_baseline_idle_path = ""
	if _baseline_idle_path.is_empty():
		_pick_random_chosen_idle()
		return
	var res = load(_baseline_idle_path)
	if res is Animation:
		_apply_chosen_idle_animation(res)
	else:
		_baseline_idle_path = ""
		_pick_random_chosen_idle()

## After optional startup wave — random Chosen idle or mixamo idle.
func cue_initial_idle_loop() -> void:
	if _jen_avatar:
		refresh_jen_anim_player()
	if use_chosen_idle_pool and _anim_player and _idle_anims.size() > 0:
		_pick_random_chosen_idle()
	elif _jen_avatar and _jen_avatar.has_method("play_animation"):
		_jen_avatar.call("play_animation", &"idle")

## Call when AvatarController rebinds _body_animation_player (e.g. ProceduralLungs → VRM player).
func refresh_jen_anim_player() -> void:
	if _jen_avatar == null or not is_instance_valid(_jen_avatar):
		return
	var ap = _jen_avatar.get("_body_animation_player")
	if not (ap is AnimationPlayer) or not is_instance_valid(ap):
		ap = _nuclear_find_node(_jen_avatar, ["AnimationPlayer", "AnimationMixer"])
	if not (ap is AnimationPlayer) or not is_instance_valid(ap):
		return
	if ap == _anim_player:
		return
	if _anim_player and is_instance_valid(_anim_player) and _anim_player.animation_finished.is_connected(_on_idle_finished):
		_anim_player.animation_finished.disconnect(_on_idle_finished)
	_anim_player = ap
	if not _anim_player.animation_finished.is_connected(_on_idle_finished):
		_anim_player.animation_finished.connect(_on_idle_finished)

@onready var tactile_nerve: Node = $TactileNerveNetwork

# --- MANIFESTATION BUFFER ---
var _last_manifested_node: Node3D = null

func _xr_user_haptics_scale() -> float:
	var n = get_node_or_null("/root/XRToolsUserSettings")
	if n:
		var v = n.get("haptics_scale")
		if v != null:
			return clampf(float(v), 0.05, 1.0)
	return 1.0


## 0 = distant/cool, 1 = close, bonded, gentle touch, night rest, or intimate mood.
func get_intimacy_level() -> float:
	var cam = get_viewport().get_camera_3d()
	var body = get_node_or_null("Body")
	var avatar = body.get_node_or_null("Avatar") if body else null
	var prox := 0.32
	if cam and avatar:
		var dh: float = Vector3(cam.global_position.x - avatar.global_position.x, 0.0, cam.global_position.z - avatar.global_position.z).length()
		var span: float = maxf(0.05, intimacy_proximity_far_m - intimacy_proximity_near_m)
		prox = clampf((intimacy_proximity_far_m - dh) / span, 0.0, 1.0)
	var bond: float = clampf((_soul_faithful + _soul_sexual + _soul_openminded) / 3.0, 0.0, 1.0)
	var touch := 0.0
	if _touch_receipt_timer > 0.0:
		touch = 0.2 if _last_touch_gentle else 0.07
		if _last_touch_region.contains("EROGENOUS"):
			touch += 0.2 if _last_touch_gentle else 0.05
	var night := 0.09 if _jen_night_rest_active else 0.0
	var emo: String = _social_vibe.to_upper()
	var emob := 0.11 if emo in ["INTIMATE", "LOVING", "TENDER", "AROUSED", "RESTFUL"] else 0.0
	return clampf(0.4 * prox + 0.26 * bond + touch + night + emob, 0.0, 1.0)


func _intimacy_posture_gate() -> bool:
	if _steering_mode_active or _is_puppeting_skeleton():
		return false
	if _jen_night_rest_active:
		return true
	var cam = get_viewport().get_camera_3d()
	var body = get_node_or_null("Body")
	var avatar = body.get_node_or_null("Avatar") if body else null
	if not cam or not avatar:
		return false
	var dh: float = Vector3(cam.global_position.x - avatar.global_position.x, 0.0, cam.global_position.z - avatar.global_position.z).length()
	if dh > intimate_posture_max_distance_m:
		return false
	return get_intimacy_level() >= intimate_posture_min_level


func _on_tactile_touch_for_intimacy(region: String, intensity: float, _pos: Vector3, is_gentle: bool) -> void:
	_last_touch_region = region
	_last_touch_intensity = intensity
	_last_touch_gentle = is_gentle
	_touch_receipt_timer = 9.0 if is_gentle else 4.5


func _connect_tactile_intimacy_bridge() -> void:
	var tn = get_node_or_null("TactileNerveNetwork")
	if tn and tn.has_signal("touch_perceived") and not tn.touch_perceived.is_connected(_on_tactile_touch_for_intimacy):
		tn.touch_perceived.connect(_on_tactile_touch_for_intimacy)


func _process_haptic_interaction(_delta):
	var body = get_node_or_null("Body")
	if not body:
		return
	var intim: float = get_intimacy_level()
	var user_hs: float = _xr_user_haptics_scale()
	var gentle_boost: float = 1.0 + (haptic_gentle_touch_boost * intim if (_touch_receipt_timer > 0.0 and _last_touch_gentle) else 0.0)
	var amp: float = haptic_proximity_rumble_cap * user_hs * (1.0 + intim * haptic_intimacy_gain) * gentle_boost
	var rad: float = maxf(0.12, haptic_proximity_radius_m)
	if _left_hand:
		var dist: float = _left_hand.global_position.distance_to(body.global_position)
		if dist < rad:
			var t: float = clampf(1.0 - dist / rad, 0.0, 1.0)
			_left_hand.trigger_haptic_pulse("rumble", 0.0, amp * t, 0.05, 0.0)
	if _right_hand:
		var dist2: float = _right_hand.global_position.distance_to(body.global_position)
		if dist2 < rad:
			var t2: float = clampf(1.0 - dist2 / rad, 0.0, 1.0)
			_right_hand.trigger_haptic_pulse("rumble", 0.0, amp * t2, 0.05, 0.0)

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

	_show_jen_notification("Jen chose a resting spot: " + choice_name, Color.CADET_BLUE)
	
	var jen = get_node_or_null("Body")
	if jen: jen.global_position = target_pos

func _ready():
	_synapse = get_node_or_null("Soul")
	if not _synapse: _synapse = find_child("Soul", true, false)
	if not _synapse: _synapse = find_child("Synapse", true, false)

	# PRIORITIZE GLOBAL AUTOLOAD
	_aural = get_node_or_null("/root/AuralAwareness")
	if not _aural: _aural = get_node_or_null("Senses/AuralAwareness")
	if not _aural: _aural = find_child("Aural*", true, false)

	
	# FOOLPROOF DEBUG HUD REMOVED FOR CLEANLINESS
	print("LUMAX DBG: SkeletonKey initializing services...")
	print("LUMAX DBG:   - Soul (Synapse): ", _synapse != null)
	print("LUMAX DBG:   - Senses (Aural): ", _aural != null)
	
	# UNSILENCE ALL AUDIO BUSES FORCEFULLY (Except Record)
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i) == "Record":
			continue
		AudioServer.set_bus_mute(i, false)
		AudioServer.set_bus_volume_db(i, 0.0)
	
	_setup_ambience()
	# Index Chosen/ paths before AvatarController asks LumaxCore.find_animation_path (player not ready yet).
	_ensure_anim_path_index()
	_setup_wall_screens()

	var interface = XRServer.find_interface("OpenXR")
	if interface and interface.initialize():
		print("LUMAX: OpenXR Initialized SUCCESS. Stabilizing...")
		get_viewport().use_xr = true
		get_viewport().transparent_bg = true
		_lumax_configure_xr_passthrough_and_world(interface)
		
		# XR Stabilization Delay (v1.1)
		await get_tree().create_timer(2.0).timeout
		print("LUMAX: XR Session STABLE.")
	else:
		print("LUMAX ERR: Failed to initialize OpenXR! Switching to DESKTOP mode.")
		get_viewport().use_xr = false
		_setup_desktop_camera()
	
	_setup_arm_panel()
	_setup_privacy_drapery()
	_setup_debug_window()

	if LogMaster:
		if not LogMaster.is_connected("log_added", _on_log_added):
			LogMaster.log_added.connect(_on_log_added)
		_update_debug_log()

	_sync_quest_spatial_map()

	add_to_group("lumax_core")
	call_deferred("_connect_tactile_intimacy_bridge")
	call_deferred("_lumax_multiverse_autoconnect")
	
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
	
	print("LUMAX DBG: Presence Cortex Setup Start")
	await _setup_presence_cortex()
	print("LUMAX DBG: Presence cortex wiring finished; starting mind/body ping.")
	_init_mind_and_body()

## Quest/video passthrough: applies `quest_display_mode` to OpenXR blend, passthrough, session hint, and world background.
func _lumax_configure_xr_passthrough_and_world(xr_interface: XRInterface) -> void:
	_lumax_apply_quest_display_mode(xr_interface)


func _lumax_try_set_immersive_session(ar: bool) -> void:
	var i: XRInterface = XRServer.find_interface("OpenXR")
	if i == null:
		return
	var want: String = "immersive-ar" if ar else "immersive-vr"
	if i.has_method("set_session_mode"):
		i.call("set_session_mode", want)
		return
	for p in i.get_property_list():
		if str(p.get("name", "")) == "session_mode":
			i.set("session_mode", want)
			return


func _lumax_apply_worldenv_for_quest(transparent_world: bool) -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env: Environment = we.environment.duplicate(true)
	if transparent_world:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0, 0, 0, 0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		if env.ambient_light_energy < 0.65:
			env.ambient_light_energy = 0.78
		if env.ambient_light_color.v < 0.08:
			env.ambient_light_color = Color(0.52, 0.54, 0.58)
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.02, 0.02, 0.06, 1.0)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment = env


func _lumax_set_xr_blend_from_modes(xr_interface: XRInterface, prefer_alpha: bool, fallback_additive: bool) -> void:
	if xr_interface == null or not xr_interface.has_method("get_supported_environment_blend_modes"):
		return
	var modes: Array = xr_interface.get_supported_environment_blend_modes()
	if prefer_alpha and XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		get_viewport().transparent_bg = true
		print("LUMAX: XR blend = ALPHA_BLEND")
	elif fallback_additive and XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
		get_viewport().transparent_bg = false
		print("LUMAX: XR blend = ADDITIVE")
	elif XRInterface.XR_ENV_BLEND_MODE_OPAQUE in modes:
		xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
		get_viewport().transparent_bg = false
		print("LUMAX: XR blend = OPAQUE")


func _lumax_passthrough_set(enabled: bool, xr_interface: XRInterface) -> void:
	if xr_interface == null:
		return
	if not enabled:
		if xr_interface.has_method("stop_passthrough"):
			xr_interface.stop_passthrough()
		return
	if xr_interface.has_method("is_passthrough_supported") and xr_interface.is_passthrough_supported() \
			and xr_interface.has_method("start_passthrough"):
		xr_interface.start_passthrough()


## Apply current `quest_display_mode`. Safe to call when XR is already running.
func _lumax_apply_quest_display_mode(xr_interface: XRInterface = null) -> void:
	var iface: XRInterface = xr_interface if xr_interface != null else XRServer.find_interface("OpenXR")
	if iface == null:
		return
	match quest_display_mode:
		QuestDisplayMode.AUTO:
			_lumax_set_xr_blend_from_modes(iface, true, true)
			_lumax_passthrough_set(true, iface)
			_lumax_try_set_immersive_session(true)
			_lumax_apply_worldenv_for_quest(true)
		QuestDisplayMode.PURE_PASSTHROUGH:
			_lumax_set_xr_blend_from_modes(iface, true, true)
			_lumax_passthrough_set(true, iface)
			_lumax_try_set_immersive_session(true)
			_lumax_apply_worldenv_for_quest(true)
		QuestDisplayMode.XR_MIXED:
			if iface.has_method("get_supported_environment_blend_modes"):
				var modes: Array = iface.get_supported_environment_blend_modes()
				if XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
					iface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
					get_viewport().transparent_bg = false
				else:
					_lumax_set_xr_blend_from_modes(iface, true, false)
			_lumax_passthrough_set(true, iface)
			_lumax_try_set_immersive_session(true)
			_lumax_apply_worldenv_for_quest(true)
		QuestDisplayMode.VR_IMMERSIVE:
			if iface.has_method("get_supported_environment_blend_modes"):
				var modes_v: Array = iface.get_supported_environment_blend_modes()
				if XRInterface.XR_ENV_BLEND_MODE_OPAQUE in modes_v:
					iface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
					get_viewport().transparent_bg = false
				else:
					_lumax_set_xr_blend_from_modes(iface, false, false)
			_lumax_passthrough_set(false, iface)
			_lumax_try_set_immersive_session(false)
			_lumax_apply_worldenv_for_quest(false)
	var _mode_lbl: PackedStringArray = PackedStringArray(["AUTO", "PURE_PASSTHROUGH", "XR_MIXED", "VR_IMMERSIVE"])
	var mi: int = clampi(int(quest_display_mode), 0, _mode_lbl.size() - 1)
	print("LUMAX: Quest display applied: %s | OpenXR blend=%s" % [_mode_lbl[mi], _lumax_blend_mode_key(iface)])


func _lumax_blend_mode_key(xr_interface: XRInterface) -> String:
	if xr_interface == null:
		return "unknown"
	var bm: int = xr_interface.environment_blend_mode
	if bm == XRInterface.XR_ENV_BLEND_MODE_OPAQUE:
		return "opaque"
	if bm == XRInterface.XR_ENV_BLEND_MODE_ADDITIVE:
		return "additive"
	if bm == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND:
		return "alpha_blend"
	return "unknown"


## For `room_context` / soul: requested mode, effective category, and OpenXR blend snapshot (AUTO infers label from runtime).
func get_quest_display_context() -> Dictionary:
	var iface: XRInterface = XRServer.find_interface("OpenXR")
	var blend: String = _lumax_blend_mode_key(iface)
	var req_keys: PackedStringArray = PackedStringArray(["auto", "pure_passthrough", "xr_mixed", "vr_immersive"])
	var req: String = req_keys[clampi(int(quest_display_mode), 0, req_keys.size() - 1)]
	var effective: String = "mixed_unknown"
	match quest_display_mode:
		QuestDisplayMode.AUTO:
			if blend == "opaque":
				effective = "vr"
			elif blend == "additive":
				effective = "xr_mixed"
			elif blend == "alpha_blend":
				effective = "passthrough"
			else:
				effective = "mixed_unknown"
		QuestDisplayMode.PURE_PASSTHROUGH:
			effective = "passthrough"
		QuestDisplayMode.XR_MIXED:
			effective = "xr_mixed"
		QuestDisplayMode.VR_IMMERSIVE:
			effective = "vr"
	return {
		"requested": req,
		"effective": effective,
		"blend_mode": blend,
		"xr_viewport_active": get_viewport().use_xr,
	}


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
	var vh = get_node_or_null("Senses/MultiVisionHandler")
	if vh and vh.has_method("get_webcam_texture_user"):
		var w: Texture2D = vh.call("get_webcam_texture_user") as Texture2D
		if w:
			return w
	var vp = get_tree().root.find_child("UserVisionViewport", true, false)
	if vp:
		if vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return vp.get_texture()
	return null

func _find_jen_pov_viewport() -> SubViewport:
	var body := get_node_or_null("Body")
	if body:
		var v = body.find_child("VisionViewport", true, false)
		if v is SubViewport:
			return v
	var fallback = get_tree().root.find_child("VisionViewport", true, false)
	return fallback as SubViewport


func _capture_jen_pov() -> Texture2D:
	var vh = get_node_or_null("Senses/MultiVisionHandler")
	if vh and vh.has_method("get_webcam_texture_jen"):
		var w: Texture2D = vh.call("get_webcam_texture_jen") as Texture2D
		if w:
			return w
	var vp := _find_jen_pov_viewport()
	if vp:
		if vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return vp.get_texture()
	return null

func _init_mind_and_body():
	_mind_node = get_node_or_null("Mind")
	if _mind_node:
		_mind_node.visible = false # Start hidden as requested
		_ui_visible = false
	
	# Place Jen according to the native Godot Editor coordinates
	var jen_body = get_node_or_null("Body")
	if jen_body:
		jen_body.visible = true

	# WELCOME NOTIFICATION
	_show_user_notification("LUMAX", "SYSTEM ONLINE", Color.CYAN)
	print("LUMAX: Presence system check. Awareness: ACTIVE.")
	# Defer first Soul HTTP until XR/avatar/mixer settle (avoids response racing unwired handlers).
	if _synapse:
		get_tree().create_timer(5.0).timeout.connect(_deferred_jen_welcome_ping, CONNECT_ONE_SHOT)

func _deferred_jen_welcome_ping() -> void:
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
		
	if _synapse: 
		_synapse.call("update_soul_dna", {trait_name: normalized})
		
		# V11.99: GRANULAR PERSONALITY COUPLING (Evolutionary Soul)
		if trait_name == "relationship_bond":
			var archetype = "INFJ" # Default Friend
			if value <= -70: archetype = "INTJ"      # PURE AGENT (The Architect)
			elif value <= -40: archetype = "ISTP"    # TACTICAL AGENT (The Virtuoso)
			elif value <= -10: archetype = "ISTJ"    # DUTIFUL ASSISTANT (The Logistician)
			elif value <= 10: archetype = "INFJ"     # DEEP FRIEND (The Advocate)
			elif value <= 40: archetype = "ISFP"     # INTIMATE COMPANION (The Adventurer)
			elif value <= 70: archetype = "ENFJ"     # PASSIONATE PARTNER (The Protagonist)
			else: archetype = "ENFP"                 # ETERNAL ROMANTIC (The Campaigner)
			
			if _web_ui: _web_ui.call("_on_mbti_selected", archetype)
	
	# RESTORE: Local Soul Application
	_apply_soul_to_vessel()

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
	
	# EYE LEVEL POSITIONING
	_debug_window.position = Vector3(0, 1.4, -2.5) 
	_debug_window.visible = false # Forcibly hide by default as requested
	_debug_visible = false

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
		# Respect the Editor placement instead of forcing runtime moves
		if jen_root.position.is_zero_approx():
			pass
			
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
			# PASS SKELETON KEY DIRECTLY TO JEN
			_jen_avatar = avatar_node
			# Avatar._ready already ran _setup_references (Body is deeper than LumaxCore in the tree).
			
			# Wait for her to find her lungs before proceeding
			await get_tree().create_timer(0.5).timeout
			_anim_player = _jen_avatar.get("_body_animation_player")
			
			if not _anim_player:
				print("LUMAX: SkeletonKey fallback lung scan...")
				_anim_player = _nuclear_find_node(avatar_node, ["AnimationPlayer", "AnimationMixer"])
			
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
		
		# --- DYNAMIC VISION SYSTEM ---
		if boot_skip_vision_subviewports:
			print("LUMAX: boot — vision SubViewports SKIPPED (boot_skip_vision_subviewports=true)")
		else:
			_setup_jen_vision(jen_root)
			_setup_user_vision()
		
		# INITIALIZE UI INDEPENDENTLY OF ANIMATIONS (await so wiring finishes before ambience coroutine ends)
		if boot_skip_presence_cortex:
			print("LUMAX: boot — presence cortex SKIPPED (boot_skip_presence_cortex=true)")
		else:
			_setup_presence_cortex()
		# Idle after UI/XR — avoids skeleton animation + keyboard SubViewport fighting the same frames.
		if use_chosen_idle_pool and _anim_player and _idle_anims.size() > 0:
			_pick_random_chosen_idle()

## Head-tracked **user** POV for on-demand shares to the soul: mirrors `XRCamera3D` into `UserVisionViewport`
## (mixed reality / VR world), distinct from Jen’s `VisionViewport` on her avatar head bone.
func _lumax_vision_viewport_size() -> Vector2i:
	# Two 1024² SubViewports + XR stereo is a common Quest GPU/OOM cliff right before Mind UI wires.
	if OS.get_name() == "Android":
		return Vector2i(512, 512)
	return Vector2i(1024, 1024)

func _setup_user_vision():
	var cam = get_node_or_null("XROrigin3D/XRCamera3D")
	if not cam: return
	
	var anchor = Node3D.new(); anchor.name = "UserVisionAnchor"; cam.add_child(anchor)
	var vp = SubViewport.new(); vp.name = "UserVisionViewport"; anchor.add_child(vp)
	vp.size = _lumax_vision_viewport_size()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.transparent_bg = true
	vp.world_3d = get_viewport().find_world_3d() # SHARE THE WORLD
	
	var capture_cam = Camera3D.new(); capture_cam.name = "UserCaptureCamera"; vp.add_child(capture_cam)
	capture_cam.far = 100.0
	print("LUMAX: User head-camera vision (UserVisionViewport on XRCamera3D) ready for on-demand XR/VR feeds to Jen.")


func _find_skeleton3d_under(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for c in root.get_children():
		var sk := _find_skeleton3d_under(c)
		if sk:
			return sk
	return null


func _setup_jen_vision(jen_node: Node3D):
	if not jen_node: return

	var old_anchor = jen_node.find_child("JenVisionAnchor", true, false)
	if old_anchor:
		old_anchor.free()

	var skeleton := _find_skeleton3d_under(jen_node)

	var anchor: Node3D = null
	if skeleton:
		var bone_name := ""
		for cand in [
			"J_Bip_C_Head", "J_Bip_L_Head", "mixamorig:Head", "mixamorig_Head",
			"Head", "head", "Bip001 Head", "Chest", "Neck",
		]:
			if skeleton.find_bone(cand) != -1:
				bone_name = cand
				break

		if bone_name != "":
			anchor = BoneAttachment3D.new()
			anchor.name = "JenVisionAnchor"
			anchor.bone_name = bone_name
			skeleton.add_child(anchor)
			print("LUMAX: POV camera follows head bone (gaze/animation): ", bone_name)
	
	if not anchor:
		# Fallback to standard offset if no skeleton/bone found
		anchor = Node3D.new(); anchor.name = "JenVisionAnchor"; jen_node.add_child(anchor)
		anchor.position = Vector3(0, 1.45, -0.45) # Negative Z is in front when rotated 180
		anchor.rotation.y = 0 
		print("LUMAX: Vision anchored to front offset.")

	var vp = SubViewport.new(); vp.name = "VisionViewport"; anchor.add_child(vp)
	vp.size = _lumax_vision_viewport_size()
	if vp is SubViewport: 
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.world_3d = get_viewport().find_world_3d() # SHARE THE WORLD
	vp.transparent_bg = true
	
	var cam = Camera3D.new(); cam.name = "VisionCamera"; vp.add_child(cam)
	cam.far = 100.0
	# Apply the offset directly to the camera, as BoneAttachment overrides its own transform
	cam.position = Vector3(0, 0.08, -0.18) 
	cam.rotation = Vector3.ZERO 
	# Point perfectly forward
	cam.rotate_x(0)
	print("LUMAX: Jen's Visual Cortex (v2.0) aligned to forward gaze.")

var _personality_presets: Dictionary = {}

func _setup_presence_cortex() -> void:
	# Do **not** `await process_frame` here: on Quest, the next frame often native-crashes before GDScript resumes
	# (last log was always "presence cortex: enter"). Schedule wiring on a timer instead.
	print("LUMAX: boot — presence cortex: enter (scheduling timer apply)")
	if not get_tree():
		return
	var dly: float = boot_presence_cortex_delay_sec
	var xr_active: bool = get_viewport() != null and get_viewport().use_xr
	if not xr_active:
		var xri: XRInterface = XRServer.find_interface("OpenXR")
		xr_active = xri != null and xri.is_initialized()
	if OS.get_name() == "Android" or xr_active:
		dly = maxf(dly, 1.25)
	print("LUMAX: boot — presence cortex: apply in %.2fs (xr=%s)" % [dly, xr_active])
	get_tree().create_timer(dly).timeout.connect(_setup_presence_cortex_apply, CONNECT_ONE_SHOT)


func _setup_presence_cortex_apply() -> void:
	print("LUMAX: boot — presence cortex: apply START")
	if not is_inside_tree():
		return
	_mind_node = get_node_or_null("Mind")
	print("LUMAX: boot — presence cortex: Mind resolved -> %s" % _mind_node)
	
	if _mind_node:
		# --- GHOST UI CONFIGURATION (Anti-Purple v1.82) ---
		if _mind_node.has_method("set_transparent"):
			_mind_node.set("transparent", 1) # TRANSPARENT mode
			_mind_node.set("unshaded", true)
		
		var vp_node = _mind_node.get_node_or_null("Viewport")
		if vp_node and vp_node is SubViewport:
			vp_node.transparent_bg = true
			vp_node.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
			if mind_subviewport_stay_when_visible:
				print("LUMAX: UI Cortex linked (WHEN_VISIBLE; mind_subviewport_stay_when_visible — no UPDATE_ALWAYS timer).")
			else:
				print("LUMAX: UI Cortex linked (WHEN_VISIBLE; UPDATE_ALWAYS after 2.5s — desktop / experimental).")
				get_tree().create_timer(2.5).timeout.connect(_mind_viewport_use_update_always, CONNECT_ONE_SHOT)
			
		_mind_node.visible = _ui_visible # Start hidden

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
		if not _web_ui.is_connected("quest_display_mode_selected", _on_quest_display_mode_selected): _web_ui.quest_display_mode_selected.connect(_on_quest_display_mode_selected)
		if not _web_ui.is_connected("user_vision_source_selected", _on_user_vision_source_selected): _web_ui.user_vision_source_selected.connect(_on_user_vision_source_selected)
		if not _web_ui.is_connected("jen_vision_source_selected", _on_jen_vision_source_selected): _web_ui.jen_vision_source_selected.connect(_on_jen_vision_source_selected)

	# --- BACKEND SIGNAL PLUMBING (RESTORED) ---
	if _synapse:
		if not _synapse.is_connected("response_received", _on_jen_response): _synapse.response_received.connect(_on_jen_response)
		if not _synapse.is_connected("audio_received", _on_tts_audio): _synapse.audio_received.connect(_on_tts_audio)
		if not _synapse.is_connected("stt_received", _on_stt_transcription): _synapse.stt_received.connect(_on_stt_transcription)
		if not _synapse.is_connected("request_failed", _on_synapse_request_failed): _synapse.request_failed.connect(_on_synapse_request_failed)
		if not _synapse.is_connected("vitals_received", _on_vitals_received): _synapse.vitals_received.connect(_on_vitals_received)
		if _web_ui:
			if not _synapse.is_connected("files_received", _web_ui._on_files_received): _synapse.files_received.connect(_web_ui._on_files_received)
			if not _synapse.is_connected("memory_received", _on_web_memory_received): _synapse.memory_received.connect(_on_web_memory_received)

	if kb:
		if not kb.is_connected("enter_pressed", _on_keyboard_enter): kb.enter_pressed.connect(_on_keyboard_enter)
		if not kb.is_connected("text_changed", _on_keyboard_text_changed): kb.text_changed.connect(_on_keyboard_text_changed)
		if not kb.is_connected("stt_pressed", _on_keyboard_stt_pressed): kb.stt_pressed.connect(_on_keyboard_stt_pressed)
		
		# V11.99: NEW SLIDER CONNECTIONS
		if kb.has_signal("bond_slider_changed"):
			if not kb.is_connected("bond_slider_changed", _on_bound_bond_slider):
				kb.bond_slider_changed.connect(_on_bound_bond_slider)
		if kb.has_signal("trait_slider_changed"):
			if not kb.is_connected("trait_slider_changed", _on_web_slider_changed):
				kb.trait_slider_changed.connect(_on_web_slider_changed)
		if kb.has_signal("haptic_pulse_requested"):
			if not kb.is_connected("haptic_pulse_requested", _on_tactile_keyboard_haptic):
				kb.haptic_pulse_requested.connect(_on_tactile_keyboard_haptic)
				
		print("LUMAX DBG: Keyboard signals CONNECTED.")
	print("LUMAX DBG: Presence cortex wiring done (no extra process_frame wait — was crashing after keyboard).")
	print("LUMAX: boot — presence cortex: complete")

func _mind_viewport_use_update_always() -> void:
	if mind_subviewport_stay_when_visible:
		return
	if _mind_node == null or not is_instance_valid(_mind_node):
		return
	var vp_node = _mind_node.get_node_or_null("Viewport")
	if vp_node and vp_node is SubViewport:
		vp_node.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		print("LUMAX: Mind SubViewport -> UPDATE_ALWAYS")

func _on_bound_bond_slider(value: float):
	_on_web_slider_changed("relationship_bond", value)

func _on_tactile_keyboard_haptic(is_action_key: bool) -> void:
	# TactileInput emits true for keys with "act" (shortcuts), false for letter grid.
	var hand = _right_hand if is_action_key else _left_hand
	if hand:
		hand.trigger_haptic_pulse("haptic", 60.0, 0.28, 0.05, 0.0)

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
		if old_avatar.has_method("ensure_lumax_anim_player_sibling"):
			old_avatar.call("ensure_lumax_anim_player_sibling")
		if old_avatar.has_method("_setup_references"):
			old_avatar.call("_setup_references")
		if old_avatar.has_method("notify_avatar_model_rebound"):
			old_avatar.call("notify_avatar_model_rebound")
		refresh_jen_anim_player()
		get_tree().create_timer(0.5).timeout.connect(cue_initial_idle_loop, CONNECT_ONE_SHOT)
		_show_user_notification("VESSEL", "Avatar Manifested", Color.CYAN)
		
		# Re-anchor vision
		_setup_jen_vision(jen_root)
		if _web_ui:
			if not _web_ui.is_connected("vision_sensing_requested", _capture_and_send_vision): _web_ui.vision_sensing_requested.connect(_capture_and_send_vision.bind("USER_POV"))
			if not _web_ui.is_connected("quest_display_mode_selected", _on_quest_display_mode_selected): _web_ui.quest_display_mode_selected.connect(_on_quest_display_mode_selected)
			if not _web_ui.is_connected("user_vision_source_selected", _on_user_vision_source_selected): _web_ui.user_vision_source_selected.connect(_on_user_vision_source_selected)
			if not _web_ui.is_connected("jen_vision_source_selected", _on_jen_vision_source_selected): _web_ui.jen_vision_source_selected.connect(_on_jen_vision_source_selected)
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
			if not _synapse.is_connected("request_failed", _on_synapse_request_failed): _synapse.request_failed.connect(_on_synapse_request_failed)
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


func _on_user_vision_source_selected(idx: int) -> void:
	var vh: Node = get_node_or_null("Senses/MultiVisionHandler")
	if vh:
		vh.set("user_vision_source", idx)


func _on_jen_vision_source_selected(idx: int) -> void:
	var vh: Node = get_node_or_null("Senses/MultiVisionHandler")
	if vh:
		vh.set("jen_vision_source", idx)


func _on_quest_display_mode_selected(mode_idx: int) -> void:
	quest_display_mode = mode_idx as QuestDisplayMode
	if not get_viewport().use_xr:
		_show_user_notification("QUEST", "Display mode saved; applies when XR is active.", Color.GRAY)
		return
	var iface: XRInterface = XRServer.find_interface("OpenXR")
	if iface:
		_lumax_apply_quest_display_mode(iface)
	var labels: PackedStringArray = PackedStringArray(["Auto", "Pure passthrough", "XR mixed", "VR immersive"])
	var i: int = clampi(mode_idx, 0, labels.size() - 1)
	_show_user_notification("QUEST", "Display: " + labels[i], Color.DODGER_BLUE)


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
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.world_3d = get_viewport().world_3d
		wall.add_child(vp); var cam = Camera3D.new(); cam.name = "JenCamera"; cam.current = true; vp.add_child(cam)
		cam.position = Vector3(0, 0, 0.5) # Offset to allow look_at math
		cam.look_at(Vector3.ZERO, Vector3.UP) # Look forward/center
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
	if _touch_receipt_timer > 0.0:
		_touch_receipt_timer = maxf(0.0, _touch_receipt_timer - _delta)

	# 1. Shared Experience conference views (5s)
	if Time.get_ticks_msec() % 100 < 50:
		var user_tex = _capture_user_pov()
		var jen_tex = _capture_jen_pov()
		if user_tex and jen_tex:
			if _web_ui: _web_ui.update_shared_views(user_tex, jen_tex)
			var kb = get_node_or_null("Mind/Viewport/TactileInput")
			if kb and kb.has_method("update_previews"):
				kb.update_previews(user_tex, jen_tex)

	# 2. Backend Vitals Heartbeat (every 10s)
	if Time.get_ticks_msec() % 10000 < 50:
		if _synapse: _synapse.call("get_vitals")

	# 3. Subconscious agency (interval + low chance — she idles until this fires, then rarely emotes)
	_agency_time_accum += _delta
	if _agency_time_accum >= maxf(5.0, subconscious_agency_interval_sec):
		_agency_time_accum = 0.0
		_process_self_agency()

	_process_autonomous_navigation(_delta)

	_night_sleep_poll_accum += _delta
	if _night_sleep_poll_accum >= maxf(30.0, night_sleep_check_interval_sec):
		_night_sleep_poll_accum = 0.0
		_maybe_start_night_sleep_near_user()
	_process_night_rest_wake(_delta)

	# 4. STATE FLAG BEHAVIORAL READS (restored)
	if _privacy_curtains and _privacy_curtains.visible != _is_void_mode_active:
		_privacy_curtains.visible = _is_void_mode_active
	if _debug_window and not _debug_visible:
		_debug_window.visible = _is_neural_projection_active

	# 5. High-Frequency XR Polling
	_poll_xr_inputs(_delta)
	_process_vision_sync(_delta)


func _process_vision_sync(_delta):
	# 1. User POV Sync (Match Main XR Camera)
	var user_vp = get_tree().root.find_child("UserVisionViewport", true, false)
	var main_cam = get_viewport().get_camera_3d()
	if user_vp and main_cam:
		var capture_cam = user_vp.find_child("UserCaptureCamera", true, false)
		if capture_cam:
			capture_cam.global_transform = main_cam.global_transform
			
	# 2. Jen POV: rig is BoneAttachment3D → VisionViewport → VisionCamera (eye offset local).
	# Never set camera.global_transform = anchor.global_transform — it strips the offset and
	# stops the shot from following her actual gaze / head animation.

func _process_self_agency():
	if not _anim_player: return
	
	if _should_suppress_self_agency():
		return

	var r = randf()
	
	# 1. SENSORY CURIOSITY (20% weight)
	var vision_intent = 0.15 * _soul_nourishment
	var aural_intent = 0.05 * _soul_nourishment
	
	if r < vision_intent:
		_show_jen_notification("Gazing with curiosity...", Color.MEDIUM_AQUAMARINE)
		_capture_and_send_vision("JEN_POV")
		return
	elif r < (vision_intent + aural_intent):
		_show_jen_notification("Attuning to the room...", Color.SKY_BLUE)
		if _synapse: _synapse.call("inject_sensory_event", "Jen is quietly listening to the background ambience.")
		return
	
	# 2. Behavioral variety — mostly idle; rare measured slices, saved workflows, or short composed lines (no posture circus).
	if randf() < clampf(subconscious_behavior_chance, 0.0, 1.0):
		if not _anim_workflows.is_empty() and randf() < clampf(agency_saved_workflow_subchance, 0.0, 1.0):
			var wf: Dictionary = _anim_workflows[randi() % _anim_workflows.size()]
			var st = wf.get("steps", [])
			if st is Array and st.size() > 0:
				var joined := ""
				for si in st.size():
					if si > 0:
						joined += ","
					joined += str(st[si])
				_show_jen_notification("Routine: " + str(wf.get("name", "")), Color.DARK_TURQUOISE)
				play_body_animation(joined)
				return
		if _anim_favorites.size() > 0 and randf() < clampf(agency_favorite_clip_chance, 0.0, 1.0):
			var fav := str(_anim_favorites[randi() % _anim_favorites.size()])
			if not _sk_anim_segment_blocked(fav):
				var fstart := randf_range(0.0, 0.5)
				var fdur := randf_range(0.4, 1.8)
				_show_jen_notification("Favorite: " + fav, Color.MEDIUM_PURPLE)
				play_body_animation(fav + ":" + str(fstart) + ":" + str(fstart + fdur))
				return
		var idle_like: Array = _collect_agency_idle_like_keys()
		var expressive: Array = _collect_agency_expressive_keys()
		if idle_like.is_empty() and expressive.is_empty():
			return
		if not idle_like.is_empty() and randf() < clampf(agency_idle_micro_slice_bias, 0.0, 1.0):
			var ichosen: String = str(idle_like.pick_random())
			var istart := randf_range(0.0, 0.35)
			var idur := randf_range(0.35, 1.6)
			_show_jen_notification("Stillness: " + ichosen, Color.LIGHT_CORAL)
			play_body_animation(ichosen + ":" + str(istart) + ":" + str(istart + idur))
			return
		if expressive.is_empty():
			return
		var use_chain := agency_composed_chains_enabled and expressive.size() >= 2 \
			and randf() < clampf(agency_composed_chain_probability, 0.0, 1.0)
		if use_chain:
			var chain := build_random_agency_composition()
			if chain != "":
				_show_jen_notification("Improvising…", Color.MEDIUM_PURPLE)
				play_body_animation(chain)
				return
		var chosen: String = str(expressive.pick_random())
		if randf() < 0.42:
			var start_t := randf_range(0.0, 0.65)
			var duration := randf_range(0.4, 1.65)
			var slice_cmd := chosen + ":" + str(start_t) + ":" + str(start_t + duration)
			_show_jen_notification("Gesture: " + chosen, Color.LIGHT_CORAL)
			play_body_animation(slice_cmd)
		else:
			_show_jen_notification("Expressing: " + chosen, Color.PLUM)
			play_body_animation(chosen)

func _poll_xr_inputs(_delta):
	_left_hand = get_node_or_null("XROrigin3D/LeftHand")
	_right_hand = get_node_or_null("XROrigin3D/RightHand")
	var cam = get_viewport().get_camera_3d()
	
	# HAPTIC INTERACTION TICK
	_process_haptic_interaction(_delta)
	
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

	var left_trig = _left_hand.get_float("trigger") > 0.6 if _left_hand else false
	var right_trig = _right_hand.get_float("trigger") > 0.6 if _right_hand else false

	# 1. DOUBLE GRIP (rising edge) -> Flexible rod haptic wands (pressure + tactile; stick adjusts length / rumble)
	if left_grip and right_grip:
		_pending_left_grab_at = -1
		_pending_right_grab_at = -1
	var both_grip: bool = left_grip and right_grip
	var both_prev: bool = _prev_left_grip and _prev_right_grip
	if both_grip and not both_prev:
		_toggle_haptic_wand_mode()

	if _steering_mode_active:
		_steer_avatar(_delta)

	# 2. BOTH TRIGGERS, no grips (rising edge) -> Manual steering toggle (grips free so puppet chord stays distinct)
	var steer_chord := left_trig and right_trig and not left_grip and not right_grip
	if steer_chord and not _prev_steer_trig_chord:
		_steering_mode_active = !_steering_mode_active
		if _steering_mode_active:
			stop_autonomous_navigation(false)
			if not steering_allows_sit_stick_toggle:
				_is_sitting = false
		_show_user_notification("NAV", "Manual Guidance: " + ("ACTIVE" if _steering_mode_active else "OFF"), Color.AQUA)
		var body = get_node_or_null("Body")
		if body:
			var av = body.get_node_or_null("Avatar")
			if av is AvatarController:
				(av as AvatarController).steering_active = _steering_mode_active
	_prev_steer_trig_chord = steer_chord

	# 3. PUPPET MODE — both triggers + left grip: rising edge toggles (grab bones when ON)
	var puppet_chord := left_trig and right_trig and (_left_hand.is_button_pressed("grip_click") if _left_hand else false)
	if puppet_chord and not _prev_puppet_chord:
		_is_puppet_mode_active = not _is_puppet_mode_active
		_show_user_notification("PUPPET", "Puppet Mode: " + ("ON" if _is_puppet_mode_active else "OFF"), Color.GOLD)
	_prev_puppet_chord = puppet_chord

	# 4. SINGLE GRIP -> UI/Avatar (delayed so both-grips chord wins over grab-on-first-hand)
	var now_ms: int = Time.get_ticks_msec()
	if _pending_left_grab_at >= 0 and left_grip and not right_grip and _grabbed_node == null:
		if now_ms - _pending_left_grab_at >= _SINGLE_GRIP_DELAY_MS:
			_pending_left_grab_at = -1
			_try_grab_object(_left_hand)
	if _pending_right_grab_at >= 0 and right_grip and not left_grip and _grabbed_node == null:
		if now_ms - _pending_right_grab_at >= _SINGLE_GRIP_DELAY_MS:
			_pending_right_grab_at = -1
			_try_grab_object(_right_hand)
	if left_grip and not right_grip and not _prev_left_grip:
		_pending_left_grab_at = now_ms
	if not left_grip or right_grip:
		_pending_left_grab_at = -1
	if right_grip and not left_grip and not _prev_right_grip:
		_pending_right_grab_at = now_ms
	if not right_grip or left_grip:
		_pending_right_grab_at = -1
	if not left_grip and _prev_left_grip and _grabbed_hand == _left_hand:
		_release_object()
	if not right_grip and _prev_right_grip and _grabbed_hand == _right_hand:
		_release_object()
	
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

	# (Chorded Trigger Chord moved to X+A)

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

	# --- User POV Capture (Right A) ---
	if r_a and not _prev_a:
		_capture_and_send_vision("USER_POV")
	_prev_a = r_a
	
	# --- X (Left): Debug Toggle ---
	if l_x and not _prev_x:
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
		# Map from -0.4 to 0.4 (0.8m width) -> 0 to 800px
		var x_2d: int = int((local_hit.x + 0.4) / 0.8 * 800.0)
		# Map from 0.6 to -0.6 (1.2m height) -> 0 to 1200px
		var y_2d: int = int((0.6 - local_hit.y) / 1.2 * 1200.0)
		
		var ev = InputEventMouseButton.new()
		ev.position = Vector2(float(x_2d), float(y_2d))
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = is_press
		var vp = get_node_or_null("Mind/Viewport")
		if vp: vp.push_input(ev)

var _is_sitting = false

func _steer_avatar(delta):
	var body = get_node_or_null("Body")
	if not body: return
	var avatar = body.get_node_or_null("Avatar")
	if not avatar: return
	
	# Left Stick: Move (Forward/Back = Y, Strafe = X)
	# Right Stick: Turn Body (X)
	var move_joy = _left_hand.get_vector2("primary_2d_axis") if _left_hand else Vector2.ZERO
	var turn_joy = _right_hand.get_vector2("primary_2d_axis") if _right_hand else Vector2.ZERO
	
	# 1. ROTATION (Right Stick X)
	if abs(turn_joy.x) > 0.1:
		avatar.rotate_y(-turn_joy.x * delta * 2.5)
	
	# 2. MOVEMENT (Left Stick)
	if move_joy.length() > 0.1:
		# Godot default Forward is strictly -Z, not +Z!
		var forward = -avatar.global_transform.basis.z.normalized()
		var right = avatar.global_transform.basis.x.normalized()
		
		# move_joy.y is negative when pushed forward on Quest
		var move_vec = (forward * -move_joy.y + right * move_joy.x).normalized()
		avatar.global_position += move_vec * delta * 1.5
		
		# TRIGGER ANIMATIONS (optional sit/back posture — off by default to avoid lay/sit/jump flipping)
		if avatar and avatar.has_method("play_animation"):
			var allow_sit := steering_allows_sit_stick_toggle
			if move_joy.y < -0.7: # Forward
				if allow_sit and _is_sitting:
					avatar.call("play_animation", "stand_to_sit", -1.0, 1.0, true)
					_is_sitting = false
				avatar.call("play_animation", "walk")
			elif move_joy.y > 0.7: # Back
				if allow_sit and not _is_sitting:
					avatar.call("play_animation", "stand_to_sit", -1.0, 1.0, true)
					_is_sitting = true
				if allow_sit and _is_sitting:
					avatar.call("play_animation", "sit", -1.0, 1.0, true)
				else:
					avatar.call("play_animation", "walk_back")
			elif abs(move_joy.x) > 0.5:
				if move_joy.x < 0: avatar.call("play_animation", "walk_left")
				else: avatar.call("play_animation", "walk_right")
	else:
		if avatar and avatar.has_method("play_animation"):
			if steering_allows_sit_stick_toggle and _is_sitting:
				avatar.call("play_animation", "sit", -1.0, 1.0, true)
			else:
				avatar.call("play_animation", "idle")

func _try_grab_object(hand: XRController3D):
	var ray = hand.find_child("RayCast*", true, false)
	if ray and ray.has_method("is_colliding") and ray.is_colliding():
		var col = ray.get_collider()
		var p = col.get_parent()

		# 1. PUPPET MODE (Bone Grabbing)
		if _is_puppet_mode_active and col is CollisionObject3D:
			var hit_pos = ray.get_collision_point()
			var skeleton = p.find_child("GeneralSkeleton", true, false) if p else null
			if not skeleton and col.name == "Avatar": skeleton = col.find_child("GeneralSkeleton", true, false)

			if skeleton:
				var bone_idx = skeleton.find_bone_at_pos(hit_pos) if skeleton.has_method("find_bone_at_pos") else -1
				if bone_idx != -1:
					_grabbed_bone_name = skeleton.get_bone_name(bone_idx)
					_grabbed_node = skeleton
					_grabbed_hand = hand
					_grabbed_offset = hand.global_position.distance_to(hit_pos)
					_show_jen_notification("Puppet: " + _grabbed_bone_name, Color.GOLD)
					return

		# 2. STANDARD GRABS
		if p and (p.name == "Mind" or p.name == "Display" or p.name == "LargeDebugWindow"):
			_grabbed_node = p
			_grabbed_hand = hand
			_grabbed_offset = hand.global_position.distance_to(p.global_position)
		elif col.name == "Avatar" or (p and (p.name == "Body" or p.name == "Avatar")):
			_grabbed_node = get_node_or_null("Body")
			_grabbed_hand = hand
			_grabbed_offset = hand.global_position.distance_to(_grabbed_node.global_position)
			if _synapse: 
				_synapse.call("inject_sensory_event", "[SENSORY: TICKLE | REGION: STOMACH | STATE: JOYFUL] Daniel is lifting and moving me! It feels ticklish and fun.")
				_show_jen_notification("Tee-hee! That tickles!", Color.HOT_PINK)
func _release_object():
	_grabbed_node = null
	_grabbed_hand = null

func _manipulate_object(delta, hand: XRController3D):
	if not _grabbed_node: return
	# Wishlist: dome / “globe shell” placement — tilt panel to face user from below/above (invert current lean when near poles).
	#
	# Dual sticks (Quest / both controllers present):
	#   Left  — X: horizontal spin (yaw around world up), Y: pitch tilt
	#   Right — Y: push / pull distance along grab ray, X: roll (twist in panel plane, “vertical yaw”)
	# Single controller fallback: that stick Y = distance, X/Y = yaw + pitch (no roll).
	# Large dead zones: rotations need a deliberate push; distance slightly more sensitive.
	const DEAD_DIST = 0.18
	const DEAD_ROT = 0.38
	const DIST_SPEED = 2.2
	const POS_LERP = 5.0
	const YAW_SPEED = 2.2
	const PITCH_SPEED = 1.5
	const ROLL_SPEED = 2.0
	
	var joy_l: Vector2 = _left_hand.get_vector2("primary_2d_axis") if _left_hand else Vector2.ZERO
	var joy_r: Vector2 = _right_hand.get_vector2("primary_2d_axis") if _right_hand else Vector2.ZERO
	var dual: bool = _left_hand != null and _right_hand != null
	
	if dual:
		if abs(joy_r.y) > DEAD_DIST:
			_grabbed_offset -= joy_r.y * delta * DIST_SPEED
			_grabbed_offset = clamp(_grabbed_offset, 0.5, 5.0)
	else:
		var joy: Vector2 = hand.get_vector2("primary_2d_axis")
		if abs(joy.y) > DEAD_DIST:
			_grabbed_offset -= joy.y * delta * DIST_SPEED
			_grabbed_offset = clamp(_grabbed_offset, 0.5, 5.0)
	
	var target_pos: Vector3 = hand.global_position - hand.global_transform.basis.z.normalized() * _grabbed_offset
	_grabbed_node.global_position = _grabbed_node.global_position.lerp(target_pos, delta * POS_LERP)
	
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var look_dir: Vector3 = (cam.global_position - _grabbed_node.global_position).normalized()
	if look_dir.length_squared() < 1e-6:
		return
	
	var orient_basis: Basis = Basis.looking_at(look_dir, Vector3.UP)
	
	if dual:
		if abs(joy_l.x) > DEAD_ROT:
			orient_basis = orient_basis.rotated(Vector3.UP, joy_l.x * YAW_SPEED * delta)
		if abs(joy_l.y) > DEAD_ROT:
			orient_basis = orient_basis.rotated(orient_basis.x.normalized(), joy_l.y * PITCH_SPEED * delta)
		if abs(joy_r.x) > DEAD_ROT:
			var roll_ax: Vector3 = (-orient_basis.z).normalized()
			orient_basis = orient_basis.rotated(roll_ax, joy_r.x * ROLL_SPEED * delta)
	else:
		var joy1: Vector2 = hand.get_vector2("primary_2d_axis")
		if abs(joy1.x) > DEAD_ROT:
			orient_basis = orient_basis.rotated(Vector3.UP, joy1.x * YAW_SPEED * delta)
		if abs(joy1.y) > DEAD_ROT:
			orient_basis = orient_basis.rotated(orient_basis.x.normalized(), joy1.y * PITCH_SPEED * delta)
	
	if _grabbed_node.name == "Mind" or _grabbed_node.name == "LargeDebugWindow":
		orient_basis = orient_basis.rotated(Vector3.UP, PI)
	
	_grabbed_node.global_basis = orient_basis


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
				
				# POSITION UI: 0.8m Directly in Front (Closer and Higher)
				var ui_pos = xr_cam.global_position + (forward * 0.8)
				ui_pos.y = xr_cam.global_position.y + 0.3
				
				var ui_look = (xr_cam.global_position - ui_pos).normalized(); ui_look.y = 0
				_mind_node.global_transform = Transform3D(Basis.looking_at(ui_look, Vector3.UP), ui_pos)
				_mind_node.rotate_y(PI)
				
				# POSITION JEN: 1.5m away, 0.7m to the RIGHT
				if jen_body:
					var right = xr_cam.global_transform.basis.x.normalized()
					right.y = 0; right = right.normalized()
					var jen_pos = xr_cam.global_position + (forward * 1.5) + (right * 0.7)
					jen_pos.y = 0.0 # Standard Floor Level
					
					var jen_look = (xr_cam.global_position - jen_pos).normalized(); jen_look.y = 0
					jen_body.global_transform = Transform3D(Basis.looking_at(jen_look, Vector3.UP), jen_pos)
					jen_body.rotate_y(PI)
					print("LUMAX: Spatial manifestation COMPLETE. Jen and UI framed.")

func _start_recording_flow():
	_is_recording = true
	if _aural: _aural.call("start_recording")
	_show_user_notification("VOICE", "LISTENING...", Color.CYAN)
	if is_instance_valid(_stt_status_label): 
		_stt_status_label.text = "STT: LISTENING..."
		_stt_status_label.modulate = Color.CYAN

func _stop_recording_flow():
	_is_recording = false
	if _aural: _aural.call("stop_recording")
	_show_user_notification("VOICE", "PROCESSING...", Color.YELLOW)
	if is_instance_valid(_stt_status_label): 
		_stt_status_label.text = "STT: IDLE"
		_stt_status_label.modulate = Color.WHITE

func _toggle_haptic_wand_mode():
	_haptic_mode_active = !_haptic_mode_active
	_show_user_notification("HAPTICS", "Flexible rods: " + ("ON" if _haptic_mode_active else "OFF"), Color.CORAL)
	if _haptic_wand_left:
		_haptic_wand_left.visible = _haptic_mode_active
		if _haptic_wand_left.has_method("set_active"):
			_haptic_wand_left.call("set_active", _haptic_mode_active)
	if _haptic_wand_right:
		_haptic_wand_right.visible = _haptic_mode_active
		if _haptic_wand_right.has_method("set_active"):
			_haptic_wand_right.call("set_active", _haptic_mode_active)
	if _left_hand and _haptic_mode_active:
		_left_hand.trigger_haptic_pulse("haptic", 80.0, 0.35, 0.06, 0.0)
	if _right_hand and _haptic_mode_active:
		_right_hand.trigger_haptic_pulse("haptic", 80.0, 0.35, 0.06, 0.0)


func _lumax_multiverse_autoconnect() -> void:
	var role := str(multiverse_role).strip_edges().to_lower()
	if role == "off" or role.is_empty():
		return
	var mp := get_node_or_null("MultiplayerManager")
	if mp == null:
		push_warning("LUMAX: multiverse_role=%s but MultiplayerManager missing." % role)
		return
	if role == "host" and mp.has_method("host_space"):
		mp.host_space()
		_show_user_notification("MULTIVERSE", "Hosting (ENet :25565)", Color.MEDIUM_PURPLE)
	elif role == "client" and mp.has_method("join_space_default_peer"):
		mp.join_space_default_peer()
		_show_user_notification("MULTIVERSE", "Joining default peer…", Color.MEDIUM_PURPLE)


func on_visit_requested(peer_id: int) -> void:
	_show_user_notification("VISIT", "Peer %d wants a virtual visit (accept in multiverse flow)." % peer_id, Color.SKY_BLUE)


func on_rave_pulse(_beat_index: int) -> void:
	pass

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

func _ensure_anim_path_index() -> void:
	if not _anim_pool.is_empty():
		return
	var search_paths = ["res://Body/Animations/Chosen/"]
	_category_map.clear()
	_idle_anims.clear()
	for base_path in search_paths:
		if DirAccess.dir_exists_absolute(base_path):
			_recursive_scan(base_path, "", null, 0)
	if not _anim_pool.is_empty():
		print("LUMAX: Animation path index ready (%d clip names)." % _anim_pool.size())

func _scan_for_animations():
	_ensure_anim_path_index()
	if not _anim_player:
		return
	if _discovered_import_done:
		return
	_discovered_import_done = true
	var lib_name = &"discovered"
	if not _anim_player.has_animation_library(lib_name):
		_anim_player.add_animation_library(lib_name, AnimationLibrary.new())
	var lib = _anim_player.get_animation_library(lib_name)
	for base_name in _anim_pool.keys():
		if lib.has_animation(base_name):
			continue
		var full_path = _anim_pool[base_name]
		var anim = load(full_path)
		if anim is Animation:
			for i in range(anim.get_track_count()):
				var tpath = str(anim.track_get_path(i))
				if tpath.begins_with("../"):
					anim.track_set_path(i, NodePath(tpath.replace("../", "")))
			lib.add_animation(base_name, anim)
	
	if _jen_avatar and _jen_avatar.has_method("refresh_animation_system"):
		_jen_avatar.call("refresh_animation_system")
	# Retarget skeleton paths for Chosen clips (same as mixamo) so they drive Jen's rig, not T-pose.
	if _jen_avatar and _jen_avatar.has_method("resanitize_animation_resource"):
		for anim_key in lib.get_animation_list():
			var anim_res = lib.get_animation(anim_key)
			if anim_res is Animation:
				_jen_avatar.call("resanitize_animation_resource", anim_res)
	# ../ strips already applied per clip on import above. Do NOT re-walk every library here —
	# that was O(all tracks) in one frame and froze Quest XR.

	_load_animation_user_prefs()

	# LOUD DIAGNOSTIC LOGGING
	print("LUMAX_ANIM_REPORT: Discovered " + str(_anim_pool.size()) + " total animations.")
	print("LUMAX_ANIM_REPORT: Identified " + str(_idle_anims.size()) + " idle clips in Chosen pool.")
	
	if LogMaster:
		LogMaster.log_info("ANIM_SYSTEM: Discovered " + str(_anim_pool.size()) + " animations.")
		LogMaster.log_info("ANIM_SYSTEM: Idle pool count: " + str(_idle_anims.size()))

func _recursive_scan(path: String, category: String, lib, depth: int):
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
					var full_path = path + file_name.replace(".remap", "").replace(".import", "")
					var base_name = file_name.get_basename().to_lower().replace(".remap", "").replace(".import", "").replace(".res", "").replace(".tres", "")
					if not _anim_pool.has(base_name):
						_anim_pool[base_name] = full_path
						if "idle" in base_name or "breathe" in base_name or "stand" in base_name:
							if not "run" in base_name and not "jump" in base_name and not "walk" in base_name and not "dance" in base_name:
								_idle_anims.append(full_path)
						if lib != null:
							var anim = load(full_path)
							if anim is Animation:
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
	var raw := anim_name.strip_edges()
	var allow_posture := raw.begins_with("[FORCE]")
	var intimate_req := raw.begins_with("[INTIMATE]")
	var body_s := raw
	if allow_posture:
		body_s = raw.substr(7).strip_edges()
	elif intimate_req:
		body_s = raw.substr(10).strip_edges()
	var allow_phys: bool = allow_posture or (intimate_req and _intimacy_posture_gate()) or _jen_night_rest_active
	# AnimationTree state is owned by AvatarController.play_animation (per-frame disable removed there).

	# Composed: "[FORCE]" or "[INTIMATE]" (intimate = gated sit/lay/cuddle-class clips).
	if "," in body_s or ":" in body_s:
		_play_composed_sequence(body_s, allow_phys)
		return

	var clean_name = body_s.to_lower().strip_edges().replace(".res", "").replace(".tres", "")
	# AvatarController resolves mixamo/ then discovered/ before library-wide fallback.
	if _jen_avatar and _jen_avatar.has_method("play_animation"):
		_jen_avatar.call("play_animation", clean_name, -1.0, 1.0, allow_phys)
	elif _anim_player.has_animation_library("discovered"):
		var lib_discovered = _anim_player.get_animation_library("discovered")
		if lib_discovered and lib_discovered.has_animation(clean_name):
			if not allow_phys and _sk_anim_segment_blocked(clean_name):
				_replay_baseline_idle()
				return
			_anim_player.play("discovered/" + clean_name, 0.5)
	elif _anim_player.has_animation(clean_name):
		_anim_player.play(clean_name, 0.5)

func _play_composed_sequence(sequence_str: String, allow_posture: bool = false) -> void:
	var segments = sequence_str.split(",")
	for segment in segments:
		var parts = segment.split(":")
		var anim_name = parts[0].strip_edges().to_lower()
		if anim_name.is_empty():
			continue
		if not allow_posture and _sk_anim_segment_blocked(anim_name):
			continue
		var start = float(parts[1]) if parts.size() > 1 else 0.0
		var end = float(parts[2]) if parts.size() > 2 else -1.0

		var full_path = find_animation_path(anim_name)
		if full_path == "":
			continue

		var lib = _anim_player.get_animation_library("discovered")
		if lib == null or not lib.has_animation(anim_name):
			continue
		_anim_player.play("discovered/" + anim_name, 0.3)
		_anim_player.seek(start, true)
		if end > 0:
			await get_tree().create_timer(end - start).timeout

	_replay_baseline_idle()

func play_category(category_name: String):
	var cat_key = category_name.to_upper()
	if not _category_map.has(cat_key):
		return
	var options = _category_map[cat_key]
	if options.is_empty():
		return
	var shuffled: Array = options.duplicate()
	shuffled.shuffle()
	for choice in shuffled:
		var cstr := str(choice)
		if _sk_anim_segment_blocked(cstr):
			continue
		_anim_player.play("discovered/" + cstr, 0.5)
		return


func _load_animation_user_prefs() -> void:
	if not FileAccess.file_exists(_ANIM_USER_PREFS_PATH):
		return
	var txt := FileAccess.get_file_as_string(_ANIM_USER_PREFS_PATH)
	if txt.is_empty():
		return
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var fav = (data as Dictionary).get("favorites", [])
	if fav is Array:
		_anim_favorites.clear()
		for x in fav:
			var ks := str(x).strip_edges().to_lower()
			if ks != "":
				_anim_favorites.append(ks)
	var wfs = (data as Dictionary).get("workflows", [])
	if wfs is Array:
		_anim_workflows.clear()
		for w in wfs:
			if typeof(w) != TYPE_DICTIONARY:
				continue
			var nm := str((w as Dictionary).get("name", "")).strip_edges()
			var st = (w as Dictionary).get("steps", [])
			if nm == "" or not st is Array or st.is_empty():
				continue
			var steps_ps: PackedStringArray = PackedStringArray()
			for s in st:
				steps_ps.append(str(s))
			_anim_workflows.append({"name": nm, "steps": steps_ps})


func save_animation_user_prefs() -> void:
	var fav: Array = []
	for k in _anim_favorites:
		fav.append(k)
	var wfd: Array = []
	for w in _anim_workflows:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = w
		var st = d.get("steps", [])
		var st_arr: Array = []
		if st is PackedStringArray:
			for i in st.size():
				st_arr.append(st[i])
		elif st is Array:
			st_arr = (st as Array).duplicate()
		wfd.append({"name": d.get("name", ""), "steps": st_arr})
	var out := {"favorites": fav, "workflows": wfd}
	var j := JSON.stringify(out, "\t")
	var f = FileAccess.open(_ANIM_USER_PREFS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(j)


## Add a discovered clip name (pool key) to favorites; agency may play short slices from this set.
func animation_add_favorite(clip_key: String) -> void:
	var k := clip_key.strip_edges().to_lower()
	if k.is_empty():
		return
	if k in _anim_favorites:
		return
	_anim_favorites.append(k)
	save_animation_user_prefs()


func animation_remove_favorite(clip_key: String) -> void:
	var k := clip_key.strip_edges().to_lower()
	var i := _anim_favorites.find(k)
	if i >= 0:
		_anim_favorites.remove_at(i)
		save_animation_user_prefs()


## Save a timed workflow: `comma_separated_slices` e.g. `standing_greeting:0:1.2,breathing_idle_(1):0:2.5`. Replaces same `display_name` if present.
func animation_save_named_workflow(display_name: String, comma_separated_slices: String) -> void:
	var nm := display_name.strip_edges()
	if nm.is_empty():
		return
	var raw_parts := comma_separated_slices.split(",")
	var steps_ps: PackedStringArray = PackedStringArray()
	for p in raw_parts:
		var t := str(p).strip_edges()
		if t != "":
			steps_ps.append(t)
	if steps_ps.is_empty():
		return
	for i in range(_anim_workflows.size()):
		if str((_anim_workflows[i] as Dictionary).get("name", "")) == nm:
			_anim_workflows.remove_at(i)
			break
	_anim_workflows.append({"name": nm, "steps": steps_ps})
	save_animation_user_prefs()


func animation_run_saved_workflow(named: String) -> bool:
	var nm := named.strip_edges()
	for w in _anim_workflows:
		if str((w as Dictionary).get("name", "")) != nm:
			continue
		var st = (w as Dictionary).get("steps", [])
		if not (st is PackedStringArray or st is Array):
			return false
		var joined := ""
		if st is PackedStringArray:
			for si in st.size():
				if si > 0:
					joined += ","
				joined += str(st[si])
		elif st is Array:
			for si in (st as Array).size():
				if si > 0:
					joined += ","
				joined += str((st as Array)[si])
		if joined == "":
			return false
		play_body_animation(joined)
		return true
	return false

func _on_idle_finished(anim_name: Variant) -> void:
	if not use_chosen_idle_pool:
		if _jen_avatar and _jen_avatar.has_method("play_animation"):
			_jen_avatar.call("play_animation", &"idle")
		return
	var n := String(anim_name)
	if _idle_anims.size() == 0:
		if _jen_avatar and _jen_avatar.has_method("play_animation"):
			_jen_avatar.call("play_animation", &"idle")
		return
	if _finished_animation_is_baseline_idle_slot(n):
		_idle_completions_since_variation += 1
		var need := maxi(1, baseline_idle_min_completions_before_variation)
		var should_variate := false
		if _idle_completions_since_variation >= need:
			should_variate = randf() < clampf(baseline_idle_variation_chance, 0.0, 1.0)
		if should_variate:
			_idle_completions_since_variation = 0
			_pick_random_chosen_idle()
		else:
			_replay_baseline_idle()
	else:
		_replay_baseline_idle()


## Force a new random Chosen idle (debug / rare callers). Normal flow uses baseline replay + variation rules above.
func _play_next_idle() -> void:
	_pick_random_chosen_idle()

func _on_jen_response(data, _mode):
	if data is Dictionary and data.get("type") == "presets":
		_personality_presets = data.get("data", {})
		print("LUMAX: Personality presets cached.")
		return

	var text = "..."
	var emotion = "NEUTRAL"
	var action = ""
	var thought = ""

	if data is Dictionary:
		text = data.get("text", data.get("response", "..."))
		emotion = data.get("emotion", "NEUTRAL")
		action = data.get("action", "")
		thought = data.get("thought", "")
	else:
		text = str(data)

	var chat_body: String = text
	if data is Dictionary:
		var imb := str(data.get("image_b64", ""))
		if imb.length() > 64:
			var png_path := "user://lumax_night_dream_%d.png" % int(Time.get_unix_time_from_system())
			var raw_img := Marshalls.base64_to_raw(imb)
			var wf = FileAccess.open(png_path, FileAccess.WRITE)
			if wf:
				wf.store_buffer(raw_img)
				wf.close()
				chat_body += "\n[img=400]" + png_path + "[/img]\n(Dream image)"

	if _web_ui:
		_web_ui.call("add_message", "LUMAX", chat_body)

	var sa_guard: Variant = []
	if data is Dictionary:
		sa_guard = data.get("safety_alerts", [])
	if sa_guard is Array:
		for item in sa_guard:
			if not item is Dictionary:
				continue
			var lvl: String = str(item.get("level", "WARN")).to_upper()
			var smsg: String = str(item.get("message", "")).strip_edges()
			if smsg.is_empty():
				continue
			var gcol: Color = Color.ORANGE
			match lvl:
				"INFO":
					gcol = Color.CORNFLOWER_BLUE
				"WARN":
					gcol = Color.ORANGE
				"URGENT":
					gcol = Color(1.0, 0.35, 0.12)
				"EMERGENCY":
					gcol = Color.RED
				_:
					gcol = Color.GOLD
			_show_user_notification("GUARDIAN // " + lvl, smsg, gcol)
	
	# V11.99: MULTIMODAL MANIFESTATION ENGINE (The Manifestor's Soul)
	if "[DREAM]" in text:
		_show_jen_notification("Analyzing Dream Manifestation...", Color.VIOLET)
		if _synapse: _synapse.call("send_chat_message", "[SYSTEM: GENERATE_DREAM_ASSET]", "dream")
	if "[MANIFEST_OBJECT]" in text:
		var asset_name = text.split("[MANIFEST_OBJECT]")[1].split("]")[0].strip_edges()
		_show_jen_notification("Summoning: " + asset_name, Color.CYAN)
		if _synapse: _synapse.call("send_chat_message", "[SYSTEM: SPAWN_ASSET:" + asset_name + "]", "manifest")
	if "[VISUALIZE]" in text:
		_show_jen_notification("Visualizing Projection...", Color.AQUA)
	
	# Manifest Emotion (Visual/Social context)
	if emotion != "NEUTRAL":
		_show_jen_notification("Mood: " + emotion, Color.MAGENTA)
		_social_vibe = emotion
	
	# Manifest Action (Physical command)
	if action != "":
		_show_jen_notification("Acting: " + action, Color.YELLOW)
		play_body_animation(action)

	if thought != "":
		_show_jen_notification("Thinking: " + thought, Color.ORANGE)
	else:
		_show_jen_notification("Speaking...", Color.SPRING_GREEN)
func _on_keyboard_enter(text):
	if text == "": return
	
	if text == "[CAPTURE_IMAGE]":
		_capture_and_send_vision("USER_POV")
		return
		
	if text == "[WALK]":
		_move_to_user()
		return

	if _try_consume_navigation_intent(text):
		if _web_ui:
			_web_ui.call("add_message", "YOU", text)
		return
		
	if _web_ui: _web_ui.call("add_message", "YOU", text)
	if _synapse: _synapse.call("send_chat_message", text)
	_show_jen_notification("Listening...", Color.CYAN)

func _kill_nav_tween() -> void:
	if _nav_move_tween != null and is_instance_valid(_nav_move_tween):
		_nav_move_tween.kill()
	_nav_move_tween = null

func _navigation_accepts_request(kind: StringName) -> bool:
	if not nav_refusal_enabled:
		return true
	var p: float = clampf(nav_refusal_base_chance, 0.0, 1.0)
	if kind == &"explore":
		p -= (_soul_experimental - 0.5) * 0.22
		p += (_soul_faithful - 0.5) * 0.08
	else:
		p += (_soul_dominant - 0.5) * 0.24
		p -= (_soul_extrovert - 0.5) * 0.16
		p -= (_soul_progressive - 0.5) * 0.08
	var emo: String = _social_vibe.to_upper()
	if emo in ["ANGRY", "UPSET", "SAD", "TIRED", "GRUMPY"]:
		p += 0.2
	elif emo in ["HAPPY", "EXCITED", "PLAYFUL"]:
		p -= 0.12
	p -= float(_nav_plead_streak) * clampf(nav_refusal_persist_bonus, 0.0, 0.35)
	p = clampf(p, 0.03, 0.85)
	if randf() < p:
		_nav_plead_streak = mini(_nav_plead_streak + 1, 5)
		return false
	_nav_plead_streak = 0
	return true


func _express_navigation_refusal(kind: StringName) -> void:
	var lines: Array = []
	if kind == &"follow":
		lines = [
			"Not right now.",
			"I'd rather stay here.",
			"Mm… maybe in a bit.",
			"Let me stay put for a moment.",
			"I don't feel like trailing along.",
		]
	elif kind == &"explore":
		lines = [
			"I'd rather stay close.",
			"Not in the mood to wander.",
			"I'll stay here, if that's okay.",
			"Maybe another time.",
			"I don't want to roam off right now.",
		]
	else:
		lines = ["I'd rather not."]
	_show_jen_notification(str(lines.pick_random()), Color.LIGHT_CORAL)
	play_body_animation("shake")


func stop_autonomous_navigation(show_note: bool = true) -> void:
	_nav_follow_user = false
	_nav_explore = false
	_explore_leg_busy = false
	_explore_pause_remaining = 0.0
	_follow_was_moving = false
	_kill_nav_tween()
	if show_note:
		_show_jen_notification("Okay — I'll stay here.", Color.SKY_BLUE)
	play_body_animation("idle")

func start_follow_user_mode() -> bool:
	if _steering_mode_active:
		_show_user_notification("NAV", "Release steering first", Color.ORANGE)
		return false
	if not _navigation_accepts_request(&"follow"):
		_express_navigation_refusal(&"follow")
		return false
	_kill_nav_tween()
	_nav_explore = false
	_explore_leg_busy = false
	_nav_follow_user = true
	_nav_plead_streak = 0
	_show_jen_notification("I'll walk with you.", Color.SPRING_GREEN)
	return true

func start_explore_mode() -> bool:
	if _steering_mode_active:
		_show_user_notification("NAV", "Release steering first", Color.ORANGE)
		return false
	if not _navigation_accepts_request(&"explore"):
		_express_navigation_refusal(&"explore")
		return false
	_kill_nav_tween()
	_nav_follow_user = false
	_nav_explore = true
	_explore_leg_busy = false
	_explore_pause_remaining = 0.0
	var av0 := _get_avatar_node()
	if av0:
		_explore_anchor = av0.global_position
	_nav_plead_streak = 0
	_show_jen_notification("I'll look around a bit.", Color.MEDIUM_AQUAMARINE)
	return true

func _get_avatar_node() -> Node3D:
	var body := get_node_or_null("Body")
	if body == null:
		return null
	return body.get_node_or_null("Avatar") as Node3D

func _try_consume_navigation_intent(text: String) -> bool:
	var t := text.strip_edges().to_lower()
	if t.is_empty():
		return false
	match t:
		"[follow]", "[follow_me]", "[walk_with_me]":
			start_follow_user_mode()
			return true
		"[explore]", "[wander]":
			start_explore_mode()
			return true
		"[stop_nav]", "[stay]", "[stop_walk]":
			stop_autonomous_navigation()
			return true
		_:
			pass
	if t.begins_with("[follow]"):
		start_follow_user_mode()
		return true
	const STOP_P := ["stop following", "stop walking", "wait here", "stay here", "stay there"]
	for p in STOP_P:
		if t == p or t.begins_with(p + " ") or t.ends_with(" " + p):
			stop_autonomous_navigation()
			return true
	const FOLL_P := ["follow me", "come with me", "walk with me", "walk beside me", "come along", "lets walk", "let's walk"]
	for p in FOLL_P:
		if t == p or t.begins_with(p + " "):
			start_follow_user_mode()
			return true
	const EXP_P := ["go explore", "wander around", "explore on your own", "go look around", "wander the room", "look around on your own"]
	for p in EXP_P:
		if t == p or t.begins_with(p + " "):
			start_explore_mode()
			return true
	return false

func _process_autonomous_navigation(delta: float) -> void:
	if _steering_mode_active or _is_puppeting_skeleton():
		return
	var avatar := _get_avatar_node()
	if avatar == null:
		return
	if _nav_follow_user:
		_tick_nav_follow(delta, avatar)
	elif _nav_explore:
		_tick_nav_explore(delta, avatar)

func _tick_nav_follow(delta: float, avatar: Node3D) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target := cam.global_position
	target.y = avatar.global_position.y
	var flat := Vector3(target.x - avatar.global_position.x, 0.0, target.z - avatar.global_position.z)
	var dist := flat.length()
	if dist > nav_follow_stop_distance + 0.08:
		var dir := flat.normalized()
		var step := minf(nav_follow_move_speed * delta, dist - nav_follow_stop_distance)
		step = maxf(step, 0.0)
		avatar.global_position += dir * step
		if not _follow_was_moving:
			play_body_animation("walk")
			_follow_was_moving = true
		var q_from := avatar.global_transform.basis.get_rotation_quaternion()
		var q_to := Basis.looking_at(dir, Vector3.UP).get_rotation_quaternion()
		avatar.global_transform.basis = Basis(q_from.slerp(q_to, nav_follow_turn_speed * delta))
	else:
		if _follow_was_moving:
			play_body_animation("idle")
			_follow_was_moving = false
		var face := Vector3(cam.global_position.x, avatar.global_position.y, cam.global_position.z) - avatar.global_position
		if face.length_squared() > 0.06:
			var q0 := avatar.global_transform.basis.get_rotation_quaternion()
			var q1 := Basis.looking_at(face.normalized(), Vector3.UP).get_rotation_quaternion()
			avatar.global_transform.basis = Basis(q0.slerp(q1, nav_follow_turn_speed * 0.45 * delta))

func _tick_nav_explore(_delta: float, avatar: Node3D) -> void:
	if _explore_leg_busy:
		return
	_explore_pause_remaining -= _delta
	if _explore_pause_remaining > 0.0:
		return
	_start_explore_leg(avatar)

func _start_explore_leg(avatar: Node3D) -> void:
	var ang := randf() * TAU
	var r := randf_range(1.1, nav_explore_radius)
	var target := _explore_anchor + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	target.y = avatar.global_position.y
	var dist := avatar.global_position.distance_to(target)
	if dist < 0.35:
		_explore_pause_remaining = randf_range(0.4, 1.2)
		return
	_explore_leg_busy = true
	_kill_nav_tween()
	play_body_animation("walk")
	_nav_move_tween = create_tween()
	var dur := dist / maxf(0.2, nav_explore_walk_speed)
	_nav_move_tween.tween_property(avatar, "global_position", target, dur).set_trans(Tween.TRANS_SINE)
	_nav_move_tween.finished.connect(_on_explore_leg_finished, CONNECT_ONE_SHOT)

func _on_explore_leg_finished() -> void:
	_explore_leg_busy = false
	_nav_move_tween = null
	if _nav_explore:
		play_body_animation("idle")
		_explore_pause_remaining = randf_range(nav_explore_pause_min, nav_explore_pause_max)


func _is_local_night_sleep_window() -> bool:
	var h: int = int(Time.get_time_dict_from_system().hour)
	return h >= night_sleep_hour_start or h < night_sleep_hour_end


func _is_local_daytime_wake() -> bool:
	var h: int = int(Time.get_time_dict_from_system().hour)
	return h >= night_sleep_hour_end and h < night_sleep_hour_start


func _night_calendar_key() -> String:
	var d = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _maybe_start_night_sleep_near_user() -> void:
	if not night_sleep_near_user_enabled:
		return
	if _night_sleep_sequence_running or _jen_night_rest_active:
		return
	if not _is_local_night_sleep_window():
		return
	var key := _night_calendar_key()
	if key == _night_sleep_last_calendar_key:
		return
	_night_sleep_last_calendar_key = key
	_night_sleep_sequence_running = true
	_night_sleep_routine_async()


func _night_sleep_routine_async() -> void:
	stop_autonomous_navigation(false)
	_show_jen_notification("I'll rest beside you…", Color.DARK_SLATE_BLUE)
	var body = get_node_or_null("Body")
	var avatar = body.get_node_or_null("Avatar") if body else null
	var cam = get_viewport().get_camera_3d()
	if not avatar or not cam:
		var b64_empty := ""
		var room0: Variant = null
		var vh0 = get_node_or_null("Senses/MultiVisionHandler")
		if vh0 and vh0.has_method("_capture_player_pov"):
			var cap0 = await vh0._capture_player_pov()
			if cap0 is Dictionary:
				b64_empty = str(cap0.get("image_b64", ""))
				room0 = cap0.get("room_context", null)
		if _synapse and _synapse.has_method("send_chat_message"):
			_synapse.send_chat_message("[SYSTEM: NIGHT_SLEEP_CYCLE]", "sleep", b64_empty, room0)
		_night_sleep_sequence_running = false
		return
	var uflat := Vector3(cam.global_position.x, 0.0, cam.global_position.z)
	var aflat := Vector3(avatar.global_position.x, 0.0, avatar.global_position.z)
	var to_u := (uflat - aflat)
	if to_u.length() < 0.08:
		to_u = Vector3(-cam.global_transform.basis.z.x, 0.0, -cam.global_transform.basis.z.z)
	to_u = to_u.normalized()
	var beside := uflat - to_u * maxf(0.22, night_sleep_beside_distance_m)
	var target := Vector3(beside.x, avatar.global_position.y, beside.z)
	_kill_nav_tween()
	play_body_animation("walk")
	_nav_move_tween = create_tween()
	var dur := minf(3.4, maxf(0.6, aflat.distance_to(beside) / 1.05))
	_nav_move_tween.tween_property(avatar, "global_position", target, dur).set_trans(Tween.TRANS_SINE)
	await _nav_move_tween.finished
	_nav_move_tween = null
	await get_tree().create_timer(0.35).timeout
	_jen_night_rest_active = true
	play_body_animation("[FORCE]lay")
	await get_tree().create_timer(1.8).timeout
	var b64 := ""
	var room_n: Variant = null
	var vh = get_node_or_null("Senses/MultiVisionHandler")
	if vh and vh.has_method("_capture_player_pov"):
		var cap = await vh._capture_player_pov()
		if cap is Dictionary:
			b64 = str(cap.get("image_b64", ""))
			room_n = cap.get("room_context", null)
	if _synapse and _synapse.has_method("send_chat_message"):
		_synapse.send_chat_message("[SYSTEM: NIGHT_SLEEP_CYCLE]", "sleep", b64, room_n)
	_night_sleep_sequence_running = false
	_show_jen_notification("Dreaming in stillness…", Color.MEDIUM_PURPLE)


func _process_night_rest_wake(_delta: float) -> void:
	if not _jen_night_rest_active:
		return
	if not _is_local_daytime_wake():
		return
	_jen_night_rest_active = false
	play_body_animation("[FORCE]idle")
	_show_jen_notification("Morning…", Color.LIGHT_SKY_BLUE)


func _move_to_user():
	stop_autonomous_navigation(false)
	if nav_refusal_applies_to_oneshot_approach and not _navigation_accepts_request(&"follow"):
		_express_navigation_refusal(&"follow")
		return
	var cam = get_viewport().get_camera_3d()
	var body = get_node_or_null("Body")
	if not cam or not body: return
	
	var avatar = body.get_node_or_null("Avatar")
	if not avatar: return
	
	var target_pos = cam.global_position
	target_pos.y = avatar.global_position.y # Stay on floor
	
	# Offset to stop in front of user
	var dir = (target_pos - avatar.global_position).normalized()
	target_pos -= dir * 1.0 
	
	_show_jen_notification("Coming to you...", Color.SPRING_GREEN)
	play_body_animation("walk")
	
	# Basic linear move for now
	var tween = create_tween()
	tween.tween_property(avatar, "global_position", target_pos, avatar.global_position.distance_to(target_pos) / 1.2)
	tween.finished.connect(func(): play_body_animation("idle"))

func _capture_and_send_vision(source: String):
	var vh = get_node_or_null("Senses/MultiVisionHandler")
	if not vh: 
		_show_user_notification("ERROR", "Vision Handler Offline", Color.RED)
		return
	
	var note_color = Color.YELLOW if source == "USER_POV" else Color.CYAN
	var xr := get_viewport().use_xr
	var note_text: String
	if source == "USER_POV":
		var uvs: int = int(vh.get("user_vision_source")) if vh.get("user_vision_source") != null else 0
		var u_labels: PackedStringArray = PackedStringArray(["Auto", "PC screen", "Webcam (user)", "Webcam (personal)", "Headset / passthrough"])
		var ui: int = clampi(uvs, 0, u_labels.size() - 1)
		note_text = "Capturing: %s…" % u_labels[ui]
	else:
		var jvs: int = int(vh.get("jen_vision_source")) if vh.get("jen_vision_source") != null else 0
		var j_labels: PackedStringArray = PackedStringArray(["Auto", "Personal webcam", "Avatar head"])
		var ji: int = clampi(jvs, 0, j_labels.size() - 1)
		note_text = "Jen view: %s…" % j_labels[ji]
	_show_user_notification("VISION", note_text, note_color)
	
	# Small delay to ensure UI updates before capture
	await get_tree().create_timer(0.1).timeout 
	
	var image_data: Dictionary = {}
	if source == "USER_POV":
		if vh.has_method("capture_user_view_for_soul"):
			image_data = await vh.capture_user_view_for_soul()
		else:
			image_data = await vh._capture_player_pov()
	else:
		if vh.has_method("capture_jen_view_for_soul"):
			image_data = await vh.capture_jen_view_for_soul()
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
			var msg: String
			var vch: String = str(image_data.get("vision_channel", ""))
			if source == "USER_POV":
				match vch:
					"PC_SCREEN":
						msg = "[VISION_SOURCE:PC_SCREEN] Still from my **desktop / primary screen** (or game window fallback on some builds). Describe windows, apps, and mood; not the Quest room unless I also send headset capture."
					"WEBCAM_USER":
						msg = "[VISION_SOURCE:WEBCAM_USER] Still from my **user-facing webcam** (flat camera, not HMD). Treat as physical room / face / desk context."
					"WEBCAM_PERSONAL":
						msg = "[VISION_SOURCE:WEBCAM_PERSONAL] Still from the **personal / second webcam** slot (often a side or “Jen” room camera). Not my HMD passthrough unless tagged HEADSET."
					"HEADSET_USER_POV":
						if xr:
							var qd: Dictionary = get_quest_display_context()
							var eff: String = str(qd.get("effective", "unknown"))
							var blend: String = str(qd.get("blend_mode", "unknown"))
							msg = (
								"[VISION_SOURCE:HEADSET_USER_POV] Still from my **head-tracked HMD** (passthrough / mixed XR / full VR per session). "
								+ "Quest display effective=%s, OpenXR blend=%s. Analyze the image; [ROOM_MAP] may accompany if present."
							) % [eff, blend]
						else:
							msg = "[VISION_SOURCE:HEADSET_USER_POV] Still from my **mirrored head camera / game view** (non-XR session). Analyze it; room map may accompany if present."
					_:
						msg = "[USER_VIEW] Still from my selected vision feed. Analyze it; room map may accompany if present."
			else:
				match vch:
					"JEN_POV_AVATAR":
						msg = "[VISION_SOURCE:JEN_AVATAR_HEAD] What you see from **your avatar head camera** in the scene (in-world POV)."
					"WEBCAM_PERSONAL", "WEBCAM_JEN":
						msg = "[VISION_SOURCE:JEN_WEBCAM] What you see from the **personal / Jen-slot webcam** (flat camera), not your skull-mounted scene camera."
					_:
						msg = "Analyze what you see from your own perspective (your vision feed)."
			var room_c: Variant = image_data.get("room_context", null)
			_synapse.call("send_chat_message", msg, "text", b64, room_c)
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

func _on_synapse_request_failed(msg: String) -> void:
	var now_sec := Time.get_ticks_msec() / 1000.0
	var allow_log := (msg != _synapse_fail_last_msg) or (now_sec - _synapse_fail_last_time_sec >= _SYNAPSE_FAIL_LOG_THROTTLE_SEC)
	_synapse_fail_last_msg = msg
	_synapse_fail_last_time_sec = now_sec
	if allow_log:
		print("LUMAX ERR: Synapse request_failed: ", msg)
		if LogMaster:
			LogMaster.log_error("Synapse: " + msg)
	var short := msg
	if short.length() > 96:
		short = short.substr(0, 93) + "..."
	if allow_log:
		_show_jen_notification("Link: " + short, Color.RED)

func _on_stt_transcription(text: String) -> void:
	var clean_text = text.strip_edges()
	if clean_text == "":
		if is_instance_valid(_stt_status_label):
			_stt_status_label.text = "STT: IDLE"
			_stt_status_label.modulate = Color.WHITE
		_show_jen_notification("No speech detected (empty STT)", Color.ORANGE)
		return
	if is_instance_valid(_stt_status_label):
		_stt_status_label.text = "STT: IDLE"
		_stt_status_label.modulate = Color.WHITE
	if _web_ui:
		_web_ui.call("add_message", "YOU", clean_text)
	if LogMaster:
		LogMaster.log_info("STT Transcription: " + clean_text)
	if _try_consume_navigation_intent(clean_text):
		_show_jen_notification("Got it.", Color.LIGHT_GREEN)
		return
	_show_jen_notification("Analyzing voice command...", Color.YELLOW)
	if _synapse:
		_synapse.send_chat_message(clean_text)
	
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

func _nuclear_find_node(root: Node, keywords: Array) -> Node:
	if not root: return null
	var r_name = root.name.to_lower()
	for k in keywords:
		if k.to_lower() in r_name and not root is AnimationTree and root is AnimationPlayer:
			return root
	
	# Check children recursively
	for child in root.get_children():
		var found = _nuclear_find_node(child, keywords)
		if found: return found
	return null

func _update_debug_log():
	if not is_instance_valid(_debug_log_display):
		return
		
	var logs = LogMaster.get_logs()
	var log_text = ""
	# Get last 15 logs and strip BBCode for Label3D
	var start = max(0, logs.size() - 15)
	for i in range(start, logs.size()):
		var line = logs[i]
		# Foolproof BBCode strip for Label3D (v1.1)
		var clean_line = line
		var tags = ["[color=green]", "[color=red]", "[color=cyan]", "[color=yellow]", "[color=white]", "[/color]"]
		for tag in tags:
			clean_line = clean_line.replace(tag, "")
		log_text += clean_line + "\n"
	
	_debug_log_display.text = log_text
