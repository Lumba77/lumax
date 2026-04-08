extends Node

## [MULTI-USER LUMINANCE NETWORK]
## Handles ENet peer-to-peer connections and avatar synchronization.
## Part of the Lumax Multiverse expansion.

signal player_joined(id: int)
signal player_left(id: int)
signal space_synced(space_data: Dictionary)

var peer = ENetMultiplayerPeer.new()
var _port = 25565
var _player_map = {}
## From res://lumax_network_config.json (connect_quest.ps1 / Docker sentry) — default join host for NAT P2P.
var nat_peer_default: String = ""

func _load_lumax_network_config() -> void:
	const path := "res://lumax_network_config.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(raw) != OK:
		return
	var data = j.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.has("nat_peer_default"):
		nat_peer_default = str(data["nat_peer_default"])
	elif data.has("pc_lan_ip"):
		nat_peer_default = str(data["pc_lan_ip"])

## Same path Synapse uses after LAN auto-discover — no JSON needed on second+ launch.
func _load_user_soul_host_fallback() -> void:
	if nat_peer_default != "":
		return
	const p := "user://lumax_soul_host.txt"
	if not FileAccess.file_exists(p):
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return
	var line := str(f.get_as_text().strip_edges().split("\n")[0]).strip_edges()
	if line.is_valid_ip_address() and line != "127.0.0.1":
		nat_peer_default = line

func set_nat_peer_default(ip: String) -> void:
	if not ip.is_valid_ip_address() or ip == "127.0.0.1":
		return
	nat_peer_default = ip

func _ready():
	add_to_group("lumax_multiverse_network")
	_load_lumax_network_config()
	_load_user_soul_host_fallback()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("LUMAX: Multiverse Network Core READY.")
	if nat_peer_default != "":
		print("LUMAX: NAT peer default: ", nat_peer_default, " (use join_space_default_peer or join_space)")

func host_space():
	peer.create_server(_port, 8)
	multiplayer.multiplayer_peer = peer
	print("LUMAX: Hosting space on port ", _port)
	_on_peer_connected(1) # Host is also a player

func join_space(address: String):
	peer.create_client(address, _port)
	multiplayer.multiplayer_peer = peer
	print("LUMAX: Attempting to synchronize with space at: ", address)

func join_space_default_peer() -> void:
	if nat_peer_default.is_empty():
		push_warning("LUMAX: nat_peer_default empty — run connect_quest.ps1 or set lumax_network_config.json")
		return
	join_space(nat_peer_default)

func _on_peer_connected(id: int):
	print("LUMAX: Peer [", id, "] entered the luminance stream.")
	player_joined.emit(id)
	
	if id != 1 and multiplayer.is_server():
		_spawn_proxy_avatar(id)

func _on_peer_disconnected(id: int):
	print("LUMAX: Peer [", id, "] vanished from the stream.")
	player_left.emit(id)
	if _player_map.has(id):
		_player_map[id].queue_free()
		_player_map.erase(id)

func _spawn_proxy_avatar(id: int):
	# Instantiate a placeholder for the visiting user
	var proxy = Node3D.new()
	proxy.name = "User_" + str(id)
	add_child(proxy)
	_player_map[id] = proxy
	
	# Add a simple mesh for now, until full avatar sync is ready
	var mesh = MeshInstance3D.new()
	mesh.mesh = CapsuleMesh.new()
	mesh.mesh.radius = 0.2; mesh.mesh.height = 1.6
	proxy.add_child(mesh)
	
	# Hovering Social Status Label
	var info = Label3D.new()
	info.name = "SocialStatus"
	info.pixel_size = 0.002
	info.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	info.position = Vector3(0, 1.8, 0) # Above head
	info.text = "Guest / co-play"
	proxy.add_child(info)
	
	print("LUMAX: Proxy avatar materialized with social status for user ", id)

@rpc("any_peer", "reliable")
func sync_social_status(status_text: String, tags: Array):
	var id = multiplayer.get_remote_sender_id()
	if _player_map.has(id):
		var label = _player_map[id].get_node("SocialStatus")
		if label:
			label.text = "[" + status_text + "]\n" + ", ".join(PackedStringArray(tags))

@rpc("any_peer", "unreliable")
func sync_pose(pos: Vector3, rot: Quaternion):
	var id = multiplayer.get_remote_sender_id()
	if _player_map.has(id):
		_player_map[id].global_position = pos
		_player_map[id].quaternion = rot

@rpc("any_peer", "call_local", "reliable")
func sync_environment_mesh(mesh_data: Array):
	# Reconstruct the remote user's room architecture
	var id = multiplayer.get_remote_sender_id()
	print("LUMAX: Materializing remote environment for Peer ", id)
	
	if _player_map.has(id):
		var proxy = _player_map[id]
		var remote_room = proxy.get_node_or_null("RemoteRoom")
		if not remote_room:
			remote_room = MeshInstance3D.new()
			remote_room.name = "RemoteRoom"
			proxy.add_child(remote_room)
		
		# For demonstration, we use a simple procedural generation logic
		# In a production app, mesh_data would contain vertices/indices
		var mesh = ArrayMesh.new()
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(mesh_data)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		remote_room.mesh = mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0, 1, 1, 0.4)
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		remote_room.set_surface_override_material(0, mat)

@rpc("any_peer", "call_local", "reliable")
func request_visit():
	var id = multiplayer.get_remote_sender_id()
	print("LUMAX: Peer ", id, " is requesting a virtual visit to your room.")
	# This would trigger a notification in the UI
	var p := get_parent()
	if p and p.has_method("on_visit_requested"):
		p.call("on_visit_requested", id)

@rpc("any_peer", "call_local", "reliable")
func accept_visit(id: int):
	print("LUMAX: Visit accepted. Streaming environment data...")
	# The host now sends their mesh to the visitor
	# Conceptual: get_parent()._get_current_mesh_data()
	rpc_id(id, "sync_environment_mesh", [Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0)])

@rpc("any_peer", "unreliable")
func sync_user_preference(pref: Dictionary):
	# Broadasts user-specific delights (Color, Style, Focus)
	var id = multiplayer.get_remote_sender_id()
	if _player_map.has(id):
		_player_map[id].set_meta("preferences", pref)

func get_global_vibe_stats() -> Dictionary:
	var stats = {"color": Color(0,0,0), "intensity": 0.0, "styles": {}}
	var count = 0
	for id in _player_map.keys():
		var prefs = _player_map[id].get_meta("preferences") if _player_map[id].has_meta("preferences") else {}
		if prefs.has("color"):
			stats["color"] += prefs["color"]
			count += 1
		if prefs.has("style"):
			var s = prefs["style"]
			stats["styles"][s] = stats["styles"].get(s, 0) + 1
	
	if count > 0:
		stats["color"] /= count
	return stats

@rpc("any_peer", "unreliable")
func sync_camera_texture(_img_data: PackedByteArray):
	# Allows projecting 'Users cameras' onto virtual screens in other spaces
	pass

@rpc("any_peer", "call_local", "reliable")
func sync_rave_pulse(beat_index: int):
	# Synchronizes the 'Cloud Rave' pulse across the community
	var pr := get_parent()
	if pr and pr.has_method("on_rave_pulse"):
		pr.call("on_rave_pulse", beat_index)
