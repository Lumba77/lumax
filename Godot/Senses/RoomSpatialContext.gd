extends Node
class_name RoomSpatialContext

## Play-space snapshot for the soul: headset pose relative to XROrigin plus optional **room mesh** anchors.
## **Camera anchors:** add any `Node3D` (or `Camera3D`) to group **`lumax_room_camera`** — optional meta **`lumax_camera_label`** for the soul (e.g. `DESK_WEBCAM`, `CEILING_PT`). Positions are expressed in **play space** (relative to `XROrigin3D` when present), same frame as `headset`, so Jen can relate stills to fixed viewpoints and infer geometry.
## Quest Scene API (walls / global mesh): use the Godot OpenXR Vendors plugin [OpenXRFbSceneManager] with a template
## scene whose root calls `add_to_group("lumax_room_entity")` and sets `set_meta("lumax_semantic", "WALL")` (or uses labels from `setup_scene`).

## Soul guardian: items Daniel marks as normal/harmless for this space (props, pets, messy areas). Sent as `room_context.safety_whitelist`.
@export var guardian_safety_whitelist: PackedStringArray = PackedStringArray()

func _camera_pose_play_space(nd: Node3D, origin: Node3D) -> Dictionary:
	var pos: Vector3 = nd.global_position
	var fwd: Vector3 = (-nd.global_transform.basis.z).normalized()
	if origin:
		pos = origin.global_transform.affine_inverse() * nd.global_position
		var rel_basis: Basis = origin.global_transform.basis.inverse() * nd.global_transform.basis
		fwd = (-rel_basis.z).normalized()
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	var yaw_deg := 0.0
	if flat.length_squared() > 1e-6:
		flat = flat.normalized()
		yaw_deg = rad_to_deg(atan2(flat.x, flat.z))
	return {
		"position_m": [pos.x, pos.y, pos.z],
		"forward_unit": [fwd.x, fwd.y, fwd.z],
		"yaw_deg": yaw_deg,
	}


func collect_room_snapshot() -> Dictionary:
	var out := {
		"version": 2,
		"xr_active": false,
		"headset": {},
		"entities": [],
		"cameras": [],
		"summary": "",
	}
	var vp := get_viewport()
	if vp:
		out["xr_active"] = vp.use_xr

	var origin := get_tree().root.find_child("XROrigin3D", true, false) as Node3D
	var cam := get_viewport().get_camera_3d()
	if origin and cam:
		var rel: Transform3D = origin.global_transform.affine_inverse() * cam.global_transform
		var o: Vector3 = rel.origin
		var fwd: Vector3 = -rel.basis.z
		var flat := Vector3(fwd.x, 0.0, fwd.z)
		var yaw_deg := 0.0
		if flat.length_squared() > 1e-6:
			flat = flat.normalized()
			yaw_deg = rad_to_deg(atan2(flat.x, flat.z))
		out["headset"] = {
			"position_m": [o.x, o.y, o.z],
			"forward_flat": [flat.x, flat.y, flat.z],
			"yaw_deg": yaw_deg,
		}

	for n in get_tree().get_nodes_in_group("lumax_room_entity"):
		if not n is Node3D:
			continue
		var nd := n as Node3D
		var label := str(nd.name)
		if nd.has_meta("lumax_semantic"):
			label = str(nd.get_meta("lumax_semantic"))
		var center: Vector3 = nd.global_position
		var size := Vector3(0.25, 0.25, 0.25)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var abb: AABB = mi.get_aabb()
			size = abb.size
			center = mi.to_global(abb.get_center())
		var dist := 0.0
		if cam:
			dist = cam.global_position.distance_to(center)
		out["entities"].append({
			"label": label,
			"center_m": [center.x, center.y, center.z],
			"size_m": [size.x, size.y, size.z],
			"distance_to_headset_m": snappedf(dist, 0.01),
		})

	var cam_arr: Array = out["cameras"]
	var hpos_play := Vector3.ZERO
	if origin and cam:
		hpos_play = origin.global_transform.affine_inverse() * cam.global_position
	for n in get_tree().get_nodes_in_group("lumax_room_camera"):
		if not n is Node3D:
			continue
		var cnd := n as Node3D
		var clabel := str(cnd.name)
		if cnd.has_meta("lumax_camera_label"):
			clabel = str(cnd.get_meta("lumax_camera_label"))
		var pose: Dictionary = _camera_pose_play_space(cnd, origin)
		var p_arr: Variant = pose.get("position_m", [0, 0, 0])
		var cp := Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
		var dhc := snappedf(hpos_play.distance_to(cp), 0.01) if origin and cam else 0.0
		cam_arr.append({
			"id": str(cnd.name),
			"label": clabel,
			"position_m": pose["position_m"],
			"forward_unit": pose["forward_unit"],
			"yaw_deg": pose["yaw_deg"],
			"distance_to_headset_m": dhc,
		})

	var sk_cam: Node = get_tree().root.find_child("LumaxCore", true, false)
	if sk_cam:
		var body: Node = sk_cam.get_node_or_null("Body")
		if body:
			var jen_eye: Node = body.find_child("VisionCamera", true, false)
			if jen_eye is Camera3D:
				var jcam := jen_eye as Camera3D
				var jpose: Dictionary = _camera_pose_play_space(jcam, origin)
				var jp: Variant = jpose.get("position_m", [0, 0, 0])
				var jv := Vector3(float(jp[0]), float(jp[1]), float(jp[2]))
				var djen := snappedf(hpos_play.distance_to(jv), 0.01) if origin and cam else 0.0
				cam_arr.append({
					"id": "jen_avatar_vision_camera",
					"label": "JEN_NATIVE_POV",
					"position_m": jpose["position_m"],
					"forward_unit": jpose["forward_unit"],
					"yaw_deg": jpose["yaw_deg"],
					"distance_to_headset_m": djen,
				})

	var lumax_core: Node = get_tree().get_first_node_in_group("lumax_core")
	if lumax_core and lumax_core.has_method("get_quest_display_context"):
		out["quest_display"] = lumax_core.get_quest_display_context()

	var vh: Node = get_tree().root.find_child("MultiVisionHandler", true, false)
	if vh:
		var uvs: Variant = vh.get("user_vision_source")
		var jvs: Variant = vh.get("jen_vision_source")
		out["vision_sources"] = {
			"user_feed": int(uvs) if uvs != null else 0,
			"jen_feed": int(jvs) if jvs != null else 0,
		}

	if guardian_safety_whitelist.size() > 0:
		var wl: Array = []
		for s in guardian_safety_whitelist:
			var t := str(s).strip_edges()
			if t.length() > 0:
				wl.append(t)
		if wl.size() > 0:
			out["safety_whitelist"] = wl

	out["summary"] = build_room_summary(out)
	return out


func build_room_summary(d: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if d.get("xr_active", false):
		parts.append("XR session active (Quest / OpenXR play space).")
	var qd: Variant = d.get("quest_display", {})
	if qd is Dictionary:
		var req: String = str(qd.get("requested", ""))
		var eff: String = str(qd.get("effective", ""))
		var bm: String = str(qd.get("blend_mode", ""))
		if eff.length() > 0:
			parts.append(
				"Quest display: user chose %s; effective mode %s (OpenXR environment blend %s)."
				% [req, eff, bm]
			)
	var vs: Variant = d.get("vision_sources", {})
	if vs is Dictionary:
		parts.append(
			"Vision feed menu indices (user/Jen): %s / %s — 0 Auto, user:1 PC screen,2 user cam,3 personal cam,4 headset; Jen:1 personal cam,2 avatar head."
			% [str(vs.get("user_feed", 0)), str(vs.get("jen_feed", 0))]
		)
	var h: Variant = d.get("headset", {})
	if h is Dictionary:
		var p: Variant = h.get("position_m", [])
		if p is Array and p.size() >= 3:
			var y: float = float(h.get("yaw_deg", 0.0))
			parts.append(
				"User headset in play space: position (%.2f, %.2f, %.2f) m, yaw ~%.0f deg (flat forward in XZ)."
				% [float(p[0]), float(p[1]), float(p[2]), y]
			)
	var ent_arr: Variant = d.get("entities", [])
	if ent_arr is Array and ent_arr.size() > 0:
		parts.append("Mapped room geometry / semantics (mesh anchors):")
		for e in ent_arr:
			if e is Dictionary:
				var lab: String = str(e.get("label", "?"))
				var dm: float = float(e.get("distance_to_headset_m", 0.0))
				parts.append("%s ~%.2f m from headset." % [lab, dm])
	elif bool(d.get("xr_active", false)):
		parts.append(
			"No room mesh anchors in tree yet. For automatic Quest room mesh, add OpenXRFbSceneManager (godot_openxr_vendors) "
			+ "or place meshes under group lumax_room_entity."
		)

	var cam_snap: Variant = d.get("cameras", [])
	if cam_snap is Array and cam_snap.size() > 0:
		parts.append(
			"Camera map (play space): fixed/registered cameras + native Jen POV rig — use position, yaw, and distance to headset to relate stills to viewpoints and infer who sees what from where."
		)
		for c in cam_snap:
			if c is Dictionary:
				var cn: String = str(c.get("label", "?"))
				var pm: Variant = c.get("position_m", [])
				var yw: float = float(c.get("yaw_deg", 0.0))
				var dh: float = float(c.get("distance_to_headset_m", 0.0))
				if pm is Array and pm.size() >= 3:
					parts.append(
						"%s @ (%.2f,%.2f,%.2f) m yaw~%.0f° ~%.2f m from user headset."
						% [cn, float(pm[0]), float(pm[1]), float(pm[2]), yw, dh]
					)
	return " ".join(parts)
