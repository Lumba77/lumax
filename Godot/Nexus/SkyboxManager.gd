extends Node

enum EnvType { NEUTRAL, DREAM, SOLARIS, GASEOUS, SPACESHIP, CLOUD_RAVE }
var _fog: FogVolume = null
var _engine_hum: AudioStreamPlayer = null
var _wind_synth: AudioStreamPlayer = null
var _ambient_layers: Dictionary = {}

## 🌌 LUMAX SKYBOX MANAGER
## Handles the loading and blending of 360 environments.
## Supports AI-generated panorama integration via [DREAM] tags.

@export var environment_node: WorldEnvironment = null
var _overlay_viewport: SubViewport = null
var _overlay_mesh: MeshInstance3D = null

func _ready():
	if not environment_node:
		environment_node = get_parent().get_node_or_null("WorldEnvironment")
	_setup_fog()
	_setup_xr_overlay()
	_setup_ambient_sounds()

func _setup_ambient_sounds():
	_engine_hum = AudioStreamPlayer.new(); _engine_hum.name = "EngineHum"; add_child(_engine_hum)
	var engine_stream = AudioStreamGenerator.new(); engine_stream.mix_rate = 44100; engine_stream.buffer_length = 1.0
	_engine_hum.stream = engine_stream; _engine_hum.volume_db = -40.0
	
	_wind_synth = AudioStreamPlayer.new(); _wind_synth.name = "WindSynth"; add_child(_wind_synth)
	var wind_stream = AudioStreamGenerator.new(); wind_stream.mix_rate = 44100; wind_stream.buffer_length = 1.0
	_wind_synth.stream = wind_stream; _wind_synth.volume_db = -35.0
	
	_ambient_layers = {
		"SOLARIS": {"hum": -45, "wind": -25, "pitch": 0.8},
		"GASEOUS": {"hum": -35, "wind": -45, "pitch": 0.5},
		"SPACESHIP": {"hum": -20, "wind": -60, "pitch": 1.2},
		"CLOUD_RAVE": {"hum": -15, "wind": -15, "pitch": 1.5}
	}

func _setup_xr_overlay():
	# Replicated Reality Layer (Overlay for XR)
	_overlay_viewport = SubViewport.new()
	_overlay_viewport.size = Vector2i(2048, 1024); _overlay_viewport.transparent_bg = true
	add_child(_overlay_viewport)
	
	_overlay_mesh = MeshInstance3D.new()
	var mesh = SphereMesh.new(); mesh.radius = 10.0; mesh.height = 20.0; mesh.flip_faces = true
	_overlay_mesh.mesh = mesh; add_child(_overlay_mesh)
	
	var mat = StandardMaterial3D.new()
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _overlay_viewport.get_texture()
	_overlay_mesh.set_surface_override_material(0, mat)
	_overlay_mesh.visible = true

func _setup_fog():
	_fog = FogVolume.new(); _fog.size = Vector3(50, 20, 50); add_child(_fog)
	_fog.visible = false

func load_panorama(path: String):
	if not environment_node: return
	
	var tex = load(path)
	if tex is Texture2D:
		var sky = environment_node.environment.sky
		if not sky:
			sky = Sky.new()
			environment_node.environment.sky = sky
		
		var mat = PanoramaSkyMaterial.new()
		mat.panorama = tex
		sky.sky_material = mat
		print("LUMAX: 360 Environment loaded: ", path)

func set_environment_type(type: EnvType):
	match type:
		EnvType.SOLARIS: _apply_solaris_vibe()
		EnvType.GASEOUS: _apply_gaseous_vibe()
		EnvType.SPACESHIP: _apply_spaceship_vibe()
		EnvType.CLOUD_RAVE: _apply_rave_vibe()
	
	_update_ambient_mix(type)

func _update_ambient_mix(type: EnvType):
	var key = EnvType.keys()[type]
	if _ambient_layers.has(key):
		var layers = _ambient_layers[key]
		if _engine_hum: _engine_hum.volume_db = layers["hum"]; _engine_hum.play()
		if _wind_synth: _wind_synth.volume_db = layers["wind"]; _wind_synth.play()
		# Add a procedural 'Pink Noise' loop for wind
		_fill_wind_buffer()

func _fill_wind_buffer():
	if not _wind_synth: return
	var playback = _wind_synth.get_stream_playback()
	var frames = playback.get_frames_available()
	for i in range(frames):
		var val = (randf() * 2.0 - 1.0) * 0.05 # Soft White Noise
		playback.push_frame(Vector2(val, val))

func _apply_rave_vibe():
	# Global Rave Party in the Clouds
	_fog.visible = true
	var mat = FogMaterial.new()
	mat.albedo = Color(1.0, 0.0, 0.5, 0.5) # Neon Pink Pulse
	mat.density = 0.2; _fog.material = mat
	
	if environment_node:
		var sky = environment_node.environment.sky.sky_material as ProceduralSkyMaterial
		if sky:
			sky.sky_top_color = Color(0.1, 0, 0.2)
			sky.sky_horizon_color = Color(0.3, 0.1, 0.5)
	
	# Start Rhythmic Pulse (AI DJ)
	if _engine_hum:
		_engine_hum.volume_db = -20.0
		# In a real impl, we'd start a beat-synced sampler
	
	print("LUMAX: Cloud Rave Manifested. [AI_DJ: GOD_MODE_ACTIVE]")

func _apply_spaceship_vibe():
	# Cozy Sleepy Spaceship Cabin
	_fog.visible = true
	var mat = FogMaterial.new()
	mat.albedo = Color(0.1, 0.1, 0.2, 0.3) # Deep Blue Void
	mat.density = 0.1; _fog.material = mat
	
	if environment_node:
		var sky = environment_node.environment.sky.sky_material as ProceduralSkyMaterial
		if sky:
			sky.sky_top_color = Color(0.02, 0.02, 0.05)
			sky.sky_horizon_color = Color(0.1, 0.05, 0.15)
	
	if _engine_hum: _engine_hum.play()
	print("LUMAX: Spaceship Cabin Atmosphere Active. [CORE_HUM: STABLE]")
func apply_stylized_overlay(b64: String):
	var data = Marshalls.base64_to_raw(b64)
	var img = Image.new()
	img.load_png_from_buffer(data) # Assuming PNG from back-end
	var tex = ImageTexture.create_from_image(img)
	
	if environment_node:
		var sky = environment_node.environment.sky
		if sky:
			var mat = sky.sky_material as PanoramaSkyMaterial
			if mat: mat.panorama = tex
	print("LUMAX: Reality stylization projected.")

func _apply_solaris_vibe():
	# Organic Solaris Foggy Planet
	_fog.visible = true
	var mat = FogMaterial.new()
	mat.albedo = Color(0.2, 0.4, 0.3, 0.6)
	mat.density = 0.8; _fog.material = mat
	print("LUMAX: Solaris Vibe active. Atmospheric density: High.")

func _apply_gaseous_vibe():
	_fog.visible = true
	var mat = FogMaterial.new()
	mat.albedo = Color(0.5, 0.2, 0.5, 0.4)
	mat.density = 0.4; _fog.material = mat

func update_xr_overlay_content(node: Control):
	# Inject a 2D UI into the 360 overlay (e.g. Diary apparitions)
	if _overlay_viewport:
		for c in _overlay_viewport.get_children(): c.queue_free()
		_overlay_viewport.add_child(node)
