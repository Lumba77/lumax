extends Node

## Monitors a directory for new screenshots and signals when a new one is found.
## Optimized for Meta Quest (via Virtual Desktop or Godot) pathing.

signal screenshot_detected(image_path: String, image_data: String)

@export var watch_path: String = ""
@export var poll_interval: float = 2.0
@export var file_patterns: Array[String] = ["*.jpg", "*.png", "*.jpeg"]

var _processed_files: Dictionary = {} # filename -> modification_time
var _is_initialized: bool = false

func _ready() -> void:
	# Default to system Pictures directory if none provided
	if watch_path == "":
		watch_path = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	
	watch_path = ProjectSettings.globalize_path(watch_path)
	
	# Check for Quest/Oculus specific subfolders
	var oculus_path = watch_path.path_join("Oculus Screenshots")
	if DirAccess.dir_exists_absolute(oculus_path):
		watch_path = oculus_path
		print("ScreenshotWatcher: Prioritizing Oculus folder -> ", watch_path)
	
	print("ScreenshotWatcher: Monitoring path -> ", watch_path)
	
	if not DirAccess.dir_exists_absolute(watch_path):
		printerr("ScreenshotWatcher: Error - Directory does not exist -> ", watch_path)
		return
	
	# Initial scan to establish baseline (don't process old files)
	_scan_directory(true)
	
	var timer = Timer.new()
	timer.wait_time = poll_interval
	timer.autostart = true
	timer.timeout.connect(_on_timer_timeout)
	add_child(timer)
	
	_is_initialized = true

func _on_timer_timeout() -> void:
	_scan_directory(false)

func _scan_directory(is_baseline: bool) -> void:
	var dir = DirAccess.open(watch_path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir():
			var is_match = false
			for pattern in file_patterns:
				if file_name.match(pattern):
					is_match = true
					break
			
			if is_match:
				var full_path = watch_path + "/" + file_name
				var mod_time = FileAccess.get_modified_time(full_path)
				
				if not _processed_files.has(file_name):
					if not is_baseline:
						print("ScreenshotWatcher: NEW screenshot detected -> ", file_name)
						_process_new_file(full_path)
					_processed_files[file_name] = mod_time
				elif _processed_files[file_name] < mod_time:
					# File was updated (Quest sometimes updates placeholders)
					if not is_baseline:
						print("ScreenshotWatcher: Screenshot UPDATED -> ", file_name)
						_process_new_file(full_path)
					_processed_files[file_name] = mod_time
					
		file_name = dir.get_next()

func _process_new_file(path: String) -> void:
	# Wait a small moment for the OS to finish writing the file
	await get_tree().create_timer(0.5).timeout
	
	var img = Image.load_from_file(path)
	if img:
		# Resize for AI processing efficiency
		img.resize(1024, 768, Image.INTERPOLATE_LANCZOS)
		var buffer = img.save_jpg_to_buffer(0.8)
		var b64 = Marshalls.raw_to_base64(buffer)
		screenshot_detected.emit(path, b64)
	else:
		print("ScreenshotWatcher: Failed to load image at ", path)
