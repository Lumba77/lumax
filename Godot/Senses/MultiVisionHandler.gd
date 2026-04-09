extends Node

## MultiVision Handler
# Unifies visual streams: **PC screen**, **webcams** (user + personal/Jen slot), **head-tracked HMD** (passthrough / XR / VR via `UserVisionViewport`), and **Jen avatar head** SubViewport.

signal perspectives_captured(images: Array, context: Dictionary)

## What to send when Daniel hits **SENSE_ENV** / user vision share (CORE → SETTINGS `USER_VISION_FEED`).
enum UserVisionSource {
	AUTO,
	PC_SCREEN,
	WEBCAM_USER,
	WEBCAM_PERSONAL,
	HEADSET_USER_POV,
}
## What to send for **Jen POV** shares (SETTINGS `JEN_VISION_FEED`).
enum JenVisionSource {
	AUTO,
	WEBCAM_PERSONAL,
	AVATAR_HEAD,
}

@export var user_vision_source: UserVisionSource = UserVisionSource.AUTO
@export var jen_vision_source: JenVisionSource = JenVisionSource.AUTO

## Enable CameraServer monitoring and bind a feed when available (Linux, macOS, Android, iOS — not Windows in stock Godot 4.x).
@export var enable_webcam: bool = true
## Index into CameraServer feeds (0 = first camera).
@export var webcam_feed_index: int = 0
## Use webcam for user/Jen previews and vision upload when **not** in XR (typical desktop).
@export var use_webcam_when_not_in_xr: bool = true
## When in XR (e.g. Quest), still sample a webcam if the host exposes feeds (PC VR + camera, rare).
@export var use_webcam_alongside_xr: bool = false
## If >= 0, bind a second feed for Jen’s slot; if -1, Jen shares the user webcam (same room view).
@export var jen_webcam_feed_index: int = -1

var _user_cam_tex: CameraTexture = null
var _jen_cam_tex: CameraTexture = null
var _webcam_monitoring_started: bool = false
var _last_webcam_log: String = ""


func _ready() -> void:
	if not enable_webcam:
		return
	CameraServer.camera_feed_added.connect(_on_camera_feed_signal)
	CameraServer.camera_feed_removed.connect(_on_camera_feed_signal)
	CameraServer.camera_feeds_updated.connect(_on_camera_feed_signal)
	_start_camera_monitoring()


func _exit_tree() -> void:
	if _webcam_monitoring_started:
		CameraServer.monitoring_feeds = false
		_webcam_monitoring_started = false


func _start_camera_monitoring() -> void:
	if _webcam_monitoring_started:
		return
	CameraServer.monitoring_feeds = true
	_webcam_monitoring_started = true
	call_deferred("_try_bind_webcam_feeds")


func _on_camera_feed_signal(_arg = null) -> void:
	_try_bind_webcam_feeds()


## Android (and some platforms) require a valid format before activating; otherwise selected_format stays -1 and activate_feed crashes.
func _ensure_camera_feed_format(feed: CameraFeed) -> bool:
	if feed == null:
		return false
	var fmts: Array = feed.get_formats()
	if fmts.is_empty():
		return false
	var best_i: int = 0
	var best_area: int = -1
	for i in range(fmts.size()):
		var d: Variant = fmts[i]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var dd: Dictionary = d
		var w: int = int(dd.get("width", 0))
		var h: int = int(dd.get("height", 0))
		var area: int = w * h if w > 0 and h > 0 else 0
		# Prefer a sane preview size (Quest / phone): not tiny, not huge
		if w >= 480 and w <= 1920 and h >= 360 and area > best_area:
			best_area = area
			best_i = i
	if best_area <= 0:
		best_i = 0
	var params := {}
	if feed.set_format(best_i, params):
		return true
	if best_i != 0 and feed.set_format(0, {}):
		return true
	return false


func _try_bind_webcam_feeds() -> void:
	if not enable_webcam:
		return
	var n: int = CameraServer.get_feed_count()
	if n <= 0:
		if _last_webcam_log != "none":
			_last_webcam_log = "none"
			print("LUMAX_WEBCAM: No CameraServer feeds yet. (Stock Godot: webcams on Linux, macOS, Android, iOS — Windows often has 0 feeds.)")
		return
	var ui: int = clampi(webcam_feed_index, 0, n - 1)
	var feed_u: CameraFeed = CameraServer.get_feed(ui)
	if feed_u == null:
		return
	if not _ensure_camera_feed_format(feed_u):
		if _last_webcam_log != "format":
			_last_webcam_log = "format"
			push_warning("LUMAX_WEBCAM: No valid CameraFeed format yet for feed [%d]; will retry on camera_feeds_updated." % ui)
		return
	feed_u.feed_is_active = true
	if _user_cam_tex == null:
		_user_cam_tex = CameraTexture.new()
	_user_cam_tex.camera_feed_id = feed_u.get_id()
	_user_cam_tex.camera_is_active = true

	if jen_webcam_feed_index >= 0:
		var ji: int = clampi(jen_webcam_feed_index, 0, n - 1)
		var feed_j: CameraFeed = CameraServer.get_feed(ji)
		if feed_j:
			if not _ensure_camera_feed_format(feed_j):
				push_warning("LUMAX_WEBCAM: Could not set format for Jen feed [%d]; sharing user feed." % ji)
				_jen_cam_tex = _user_cam_tex
			else:
				feed_j.feed_is_active = true
				if _jen_cam_tex == null:
					_jen_cam_tex = CameraTexture.new()
				_jen_cam_tex.camera_feed_id = feed_j.get_id()
				_jen_cam_tex.camera_is_active = true
	else:
		_jen_cam_tex = _user_cam_tex

	var names := "%s" % feed_u.get_name()
	if _last_webcam_log != names:
		_last_webcam_log = names
		print("LUMAX_WEBCAM: Active feed [%d] %s" % [ui, names])


func _xr_active() -> bool:
	var vp := get_viewport()
	return vp != null and vp.use_xr


func _webcam_allowed_for_mode() -> bool:
	if not enable_webcam or _user_cam_tex == null:
		return false
	if _xr_active():
		return use_webcam_alongside_xr
	return use_webcam_when_not_in_xr


## Live UI / SubViewport replacement (SkeletonKey cockpit previews).
func get_webcam_texture_user() -> Texture2D:
	if _webcam_allowed_for_mode():
		return _user_cam_tex
	return null


func get_webcam_texture_jen() -> Texture2D:
	if not _webcam_allowed_for_mode():
		return null
	if _jen_cam_tex != null:
		return _jen_cam_tex
	return _user_cam_tex


func _image_payload_from_texture(tex: Texture2D, source_key: String, preview_file: String, vision_channel: String) -> Dictionary:
	if tex == null:
		return {}
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return {}
	img.save_jpg(preview_file, 0.75)
	var dup := img.duplicate()
	dup.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var buffer: PackedByteArray = dup.save_jpg_to_buffer(0.75)
	var b64: String = Marshalls.raw_to_base64(buffer)
	var d := {"source": source_key, "image_b64": b64, "preview_path": preview_file, "vision_channel": vision_channel}
	return d


func _finalize_image_dict(img: Image, preview_file: String, vision_channel: String, source_key: String) -> Dictionary:
	if img == null or img.is_empty():
		return {}
	var dup := img.duplicate()
	dup.save_jpg(preview_file, 0.75)
	dup.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var buffer: PackedByteArray = dup.save_jpg_to_buffer(0.75)
	var b64: String = Marshalls.raw_to_base64(buffer)
	return {"source": source_key, "image_b64": b64, "preview_path": preview_file, "vision_channel": vision_channel}


# --- PUBLIC API ---

func _room_snapshot() -> Dictionary:
	var room_node = get_node_or_null("../RoomSpatialContext")
	if room_node and room_node.has_method("collect_room_snapshot"):
		return room_node.collect_room_snapshot()
	return {}


func _attach_room_context(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return d
	var snap := _room_snapshot()
	if not snap.is_empty():
		d["room_context"] = snap
	return d


## Respects **SETTINGS → USER_VISION_FEED** (SENSE_ENV / user share to soul).
func capture_user_view_for_soul() -> Dictionary:
	var d: Dictionary = {}
	match user_vision_source:
		UserVisionSource.AUTO:
			d = await _capture_player_pov_auto()
		UserVisionSource.PC_SCREEN:
			d = await _capture_pc_screen()
		UserVisionSource.WEBCAM_USER:
			d = _capture_webcam_user_forced()
		UserVisionSource.WEBCAM_PERSONAL:
			d = _capture_webcam_personal_forced()
		UserVisionSource.HEADSET_USER_POV:
			d = await _capture_headset_user_viewport()
	if d.is_empty() and user_vision_source != UserVisionSource.AUTO:
		d = await _capture_player_pov_auto()
	return _attach_room_context(d)


## Respects **SETTINGS → JEN_VISION_FEED**.
func capture_jen_view_for_soul() -> Dictionary:
	var d: Dictionary = {}
	match jen_vision_source:
		JenVisionSource.AUTO:
			d = await _capture_jen_pov_auto()
		JenVisionSource.WEBCAM_PERSONAL:
			d = _capture_jen_webcam_forced()
		JenVisionSource.AVATAR_HEAD:
			d = await _capture_jen_viewport_only()
	if d.is_empty() and jen_vision_source != JenVisionSource.AUTO:
		d = await _capture_jen_pov_auto()
	return _attach_room_context(d)


func capture_all_perspectives() -> Array:
	var images = []

	var player_pov = await _capture_player_pov_auto()
	if not player_pov.is_empty():
		images.append(player_pov)

	var jen_pov = await _capture_jen_pov_auto()
	if not jen_pov.is_empty():
		images.append(jen_pov)

	for i in range(images.size()):
		if images[i] is Dictionary:
			images[i] = _attach_room_context(images[i])

	var ctx := {"room": _room_snapshot()}
	perspectives_captured.emit(images, ctx)

	print("MultiVisionHandler: Captured %d perspectives." % images.size())
	return images


# --- INTERNAL CAPTURE LOGIC ---

func _capture_from_viewport(vp: Viewport, vision_channel: String, preview_file: String) -> Dictionary:
	if not vp:
		print("MultiVisionHandler: Viewport null.")
		return {}

	var is_sub = vp is SubViewport
	var prev_mode = 0
	if is_sub:
		prev_mode = vp.render_target_update_mode
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var texture = vp.get_texture()
	if not texture:
		print("MultiVisionHandler: Texture null.")
		return {}

	var img = texture.get_image()

	if not is_sub and (not img or img.is_empty()):
		print("MultiVisionHandler: Viewport texture failed, trying DisplayServer screenshot...")
		img = get_viewport().get_texture().get_image()
		if not img or img.is_empty():
			pass

	if is_sub and prev_mode != SubViewport.UPDATE_ONCE:
		vp.render_target_update_mode = prev_mode

	if not img or img.is_empty():
		print("MultiVisionHandler: Image empty.")
		return {}

	return _finalize_image_dict(img, preview_file, vision_channel, vp.name)


func _capture_pc_screen() -> Dictionary:
	var img: Image = null
	if DisplayServer.has_method("screen_get_image"):
		img = DisplayServer.screen_get_image(-1)
	if img == null or img.is_empty():
		var root_vp: Viewport = get_tree().root.get_viewport()
		if root_vp != null and not _xr_active():
			await get_tree().process_frame
			var tex: Texture2D = root_vp.get_texture()
			if tex:
				img = tex.get_image()
	if img == null or img.is_empty():
		print("LUMAX: PC screen capture empty (XR headset, permissions, or no framebuffer).")
		return {}
	return _finalize_image_dict(img.duplicate(), "user://preview_pc_screen.jpg", "PC_SCREEN", "PC_SCREEN")


func _capture_webcam_user_forced() -> Dictionary:
	if not enable_webcam or _user_cam_tex == null:
		print("LUMAX: WEBCAM_USER requested but no CameraServer feed.")
		return {}
	var w := _image_payload_from_texture(_user_cam_tex, "WEBCAM_USER", "user://preview_webcam_user.jpg", "WEBCAM_USER")
	return w


func _capture_webcam_personal_forced() -> Dictionary:
	if not enable_webcam:
		return {}
	var jtex: Texture2D = _jen_cam_tex if _jen_cam_tex != null else _user_cam_tex
	if jtex == null:
		print("LUMAX: WEBCAM_PERSONAL requested but no personal/Jen webcam bound.")
		return {}
	return _image_payload_from_texture(jtex, "WEBCAM_PERSONAL", "user://preview_webcam_personal.jpg", "WEBCAM_PERSONAL")


func _capture_jen_webcam_forced() -> Dictionary:
	return _capture_webcam_personal_forced()


func _capture_headset_user_viewport() -> Dictionary:
	var vp = get_tree().root.find_child("UserVisionViewport", true, false)
	if not vp:
		vp = get_viewport()
	var r := await _capture_from_viewport(vp, "HEADSET_USER_POV", "user://preview_headset_user.jpg")
	if not r.is_empty():
		r["source"] = "PLAYER_POV"
	return r


func _capture_jen_viewport_only() -> Dictionary:
	var sk = get_tree().root.find_child("LumaxCore", true, false)
	var vp = null
	if sk:
		var jen = sk.get_node_or_null("Body")
		if jen:
			# Prefer dedicated Jen viewport; generic VisionViewport can collide with wall/debug viewports.
			vp = jen.find_child("JenVisionViewport", true, false)
			if not vp:
				var anchor = jen.find_child("JenVisionAnchor", true, false)
				if anchor:
					vp = anchor.find_child("VisionViewport", true, false)
	if not vp:
		vp = get_tree().root.find_child("JenVisionViewport", true, false)
	if not vp:
		vp = get_tree().root.find_child("VisionViewport", true, false)
	if not vp:
		print("MultiVisionHandler: VisionViewport NOT FOUND.")
		return {}
	var r := await _capture_from_viewport(vp, "JEN_POV_AVATAR", "user://preview_jen_avatar.jpg")
	if not r.is_empty():
		r["source"] = "JEN_POV"
	return r


func _capture_player_pov_auto() -> Dictionary:
	if _webcam_allowed_for_mode() and _user_cam_tex:
		var w := _image_payload_from_texture(_user_cam_tex, "WEBCAM_USER", "user://preview_webcam_user.jpg", "WEBCAM_USER")
		if not w.is_empty():
			w["source"] = "PLAYER_POV"
			return w

	var vp = get_tree().root.find_child("UserVisionViewport", true, false)
	if not vp:
		vp = get_viewport()

	var result = await _capture_from_viewport(vp, "HEADSET_USER_POV", "user://preview_headset_user.jpg")
	if not result.is_empty():
		result["source"] = "PLAYER_POV"
	return result


func _capture_jen_pov_auto() -> Dictionary:
	if _webcam_allowed_for_mode():
		var jtex: Texture2D = _jen_cam_tex if _jen_cam_tex != null else _user_cam_tex
		if jtex:
			var w := _image_payload_from_texture(jtex, "WEBCAM_JEN", "user://preview_webcam_jen.jpg", "WEBCAM_JEN")
			if not w.is_empty():
				w["source"] = "JEN_POV"
				return w

	return await _capture_jen_viewport_only()


## Back-compat: **auto** player path (night sleep, room context) — ignores USER_VISION_FEED selector.
func _capture_player_pov() -> Dictionary:
	return await _capture_player_pov_auto()


## Back-compat: **auto** Jen path.
func _capture_jen_pov() -> Dictionary:
	return await _capture_jen_pov_auto()
