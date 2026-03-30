extends Node3D

func _ready():
	print("Lumax: Attempting PURE BOOT...")
	var interface = XRServer.find_interface("OpenXR")
	if interface and interface.initialize():
		get_viewport().use_xr = true
		print("Lumax: PURE BOOT SUCCESS - Viewport XR active.")
	else:
		print("Lumax: PURE BOOT FAILED - OpenXR could not start.")
