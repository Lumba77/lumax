extends Node

## MultiVision Handler
# Unifies all visual input streams (VR, Passthrough, Screenshots) into a single
# sensory input for the Director and Soul.

signal perspectives_captured(images: Array, context: Dictionary)

# --- PUBLIC API ---

func capture_all_perspectives() -> Array:
	var images = []
	
	var player_pov = await _capture_player_pov()
	if not player_pov.is_empty():
		images.append(player_pov)
		
	var jen_pov = await _capture_jen_pov()
	if not jen_pov.is_empty():
		images.append(jen_pov)
	
	# Future: Add third-person, passthrough, etc.
	
	print("MultiVisionHandler: Captured %d perspectives." % images.size())
	return images

# --- INTERNAL CAPTURE LOGIC ---

func _capture_from_viewport(vp: Viewport) -> Dictionary:
	if not vp: 
		print("MultiVisionHandler: Viewport null.")
		return {}
		
	# FORCE UPDATE to ensure it's not black (Only for SubViewports)
	var is_sub = vp is SubViewport
	var prev_mode = 0
	if is_sub:
		prev_mode = vp.render_target_update_mode
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# Wait multiple frames for the GPU to actually render and transfer to CPU
	await get_tree().process_frame 
	await get_tree().process_frame
	await get_tree().process_frame
	
	var texture = vp.get_texture()
	if not texture: 
		print("MultiVisionHandler: Texture null.")
		return {}
	
	var img = texture.get_image()
	
	# Fallback for Main Viewport (often black in XR when using get_texture)
	if not is_sub and (not img or img.is_empty()):
		print("MultiVisionHandler: Viewport texture failed, trying DisplayServer screenshot...")
		img = get_viewport().get_texture().get_image() # Try again once
		if not img or img.is_empty():
			# This is the 'nuclear' option for some Android devices
			pass 

	# Revert mode if it was different (Only for SubViewports)
	if is_sub and prev_mode != SubViewport.UPDATE_ONCE:
		vp.render_target_update_mode = prev_mode
		
	if not img or img.is_empty(): 
		print("MultiVisionHandler: Image empty.")
		return {}
	
	# Save a local preview for the Chat UI
	img.save_jpg("user://preview.jpg", 0.75)
	
	# Standardize size for the AI
	img.resize(512, 512, Image.INTERPOLATE_LANCZOS) # 512 is plenty for vision
	var buffer = img.save_jpg_to_buffer(0.75)
	var b64 = Marshalls.raw_to_base64(buffer)
	
	return {"source": vp.name, "image_b64": b64, "preview_path": "user://preview.jpg"}


func _capture_player_pov() -> Dictionary:
	var vp = get_tree().root.find_child("UserVisionViewport", true, false)
	if not vp: vp = get_viewport() # Fallback
	
	var result = await _capture_from_viewport(vp)
	if not result.is_empty():
		result["source"] = "PLAYER_POV"
	return result


func _capture_jen_pov() -> Dictionary:
	# Deep-scan for the correct dynamic VisionViewport
	var sk = get_tree().root.find_child("LumaxCore", true, false)
	var vp = null
	if sk:
		var jen = sk.get_node_or_null("Body")
		if jen: vp = jen.find_child("VisionViewport", true, false)
	
	if not vp:
		# Fallback to general search
		vp = get_tree().root.find_child("VisionViewport", true, false)

	if not vp: 
		print("MultiVisionHandler: VisionViewport NOT FOUND.")
		return {}
		
	var result = await _capture_from_viewport(vp)
	if not result.is_empty():
		result["source"] = "JEN_POV"
	return result
