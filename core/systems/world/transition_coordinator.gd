# transition_coordinator.gd
# Persistent authority for transactional room replacement.
extends Node
class_name TransitionCoordinator

signal transition_started(request: TransitionRequest)
signal transition_committed(request: TransitionRequest, room: WorldRoom)
signal transition_failed(request: TransitionRequest, reason: String)

var player: GridActor
var camera_rig: TacticalCameraRig
var room_container: Node3D
var active_room: WorldRoom
var last_error := ""

var _room_scenes: Dictionary = {}
var _transitioning := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(
	persistent_player: GridActor,
	persistent_camera: TacticalCameraRig,
	mount: Node3D,
) -> void:
	player = persistent_player
	camera_rig = persistent_camera
	room_container = mount


func register_room(semantic_id: StringName, scene: PackedScene) -> void:
	if semantic_id.is_empty() or scene == null:
		return
	_room_scenes[semantic_id] = scene


func install_initial_room(scene: PackedScene, entrance_id: StringName) -> bool:
	if active_room != null or scene == null or not _composition_ready():
		return false
	var staged := scene.instantiate() as WorldRoom
	if staged == null:
		return false
	var validation := _validate_staged(staged, staged.room_id, entrance_id)
	if not validation["ok"]:
		staged.free()
		return false
	_bind_room(staged)
	room_container.add_child(staged)
	active_room = staged
	_bind_exits(staged)
	_place_player(validation["destination_transform"])
	return true


func request_transition(request: TransitionRequest) -> bool:
	last_error = ""
	if _transitioning:
		return _reject_without_pause(request, "A transition is already active.")
	if not _composition_ready() or active_room == null or request == null:
		return _reject_without_pause(request, "World transition composition is incomplete.")
	if _modal_active():
		return _reject_without_pause(request, "Travel is unavailable while a modal interaction is active.")
	# Snapshot the caller-owned request into value types before any signal can
	# invoke arbitrary synchronous listeners. GDScript's underscore fields are
	# not hard-private, so transition authority must never reread the object
	# after callback dispatch.
	var source_room_id := request.source_room_id
	var exit_id := request.exit_id
	var destination_room_id := request.destination_room_id
	var destination_entrance_id := request.destination_entrance_id
	if source_room_id != active_room.room_id:
		return _reject_without_pause(request, "Transition source room is stale.")
	var effective_request := _request_value(source_room_id, exit_id, destination_room_id, destination_entrance_id)
	var source_exits := active_room.find_exits(exit_id)
	if source_exits.size() != 1 or not source_exits[0].matches_request(effective_request):
		return _reject_without_pause(request, "Transition source exit is stale or mismatched.")

	_transitioning = true
	_game_state().request_pause(self, &"transition")
	transition_started.emit(_request_value(source_room_id, exit_id, destination_room_id, destination_entrance_id))
	if _modal_active():
		return _reject_with_pause(
			_request_value(source_room_id, exit_id, destination_room_id, destination_entrance_id),
			"Travel became unavailable because a modal interaction opened.",
		)

	var destination_scene: PackedScene = _room_scenes.get(destination_room_id)
	if destination_scene == null:
		return _reject_with_pause(effective_request, "Destination room is not registered.")

	# Staging remains off-tree. No _ready(), input, physics, groups, or room
	# controller behavior can run before every mandatory precommit check.
	var staged := destination_scene.instantiate() as WorldRoom
	if staged == null:
		return _reject_with_pause(effective_request, "Destination resource is not a WorldRoom.")

	var validation := _validate_staged(staged, destination_room_id, destination_entrance_id)
	if not validation["ok"]:
		staged.free()
		return _reject_with_pause(effective_request, validation["reason"])

	var captured_state: Dictionary = active_room.capture_transition_state()
	if not captured_state.is_empty():
		# Consequence persistence is not part of minimal transition GREEN.
		staged.free()
		return _reject_with_pause(effective_request, "Current room produced unsupported consequence state in this slice.")

	_bind_room(staged)
	var staged_controller := validation["controller"] as InteractionController
	if staged_controller.player != player \
		or staged_controller.camera_rig != camera_rig \
		or staged_controller.grid_map != validation["grid_map"]:
		staged.free()
		return _reject_with_pause(effective_request, "Destination persistent bindings could not be supplied.")
	if _modal_active():
		staged.free()
		return _reject_with_pause(
			_request_value(source_room_id, exit_id, destination_room_id, destination_entrance_id),
			"Travel became unavailable because a modal interaction opened.",
		)
	# Capture hooks and dependency setters ran after initial staging validation.
	# Recompose from current off-tree bytes immediately before destructive commit.
	var commit_relative_transform := staged.relative_entrance_transform(validation["entrance"])
	var commit_destination_transform := _compose_destination_transform(staged, commit_relative_transform)
	if not _transform_is_valid(commit_relative_transform) \
		or not _transform_is_valid(commit_destination_transform):
		staged.free()
		return _reject_with_pause(
			_request_value(source_room_id, exit_id, destination_room_id, destination_entrance_id),
			"Destination entrance transform became invalid before commit.",
		)

	var previous_room := active_room
	room_container.remove_child(previous_room)
	room_container.add_child(staged)
	active_room = staged
	_bind_exits(staged)
	_place_player(commit_destination_transform)
	previous_room.free()

	_transitioning = false
	_game_state().release_pause(self, &"transition")
	transition_committed.emit(
		_request_value(source_room_id, exit_id, destination_room_id, destination_entrance_id),
		staged,
	)
	return true


func _validate_staged(
	staged: WorldRoom,
	expected_room_id: StringName,
	requested_entrance_id: StringName,
) -> Dictionary:
	var declared_rooms := staged.world_rooms()
	if declared_rooms.size() != 1 or declared_rooms[0] != staged:
		return _invalid("Destination must declare exactly one WorldRoom identity.")
	if staged.room_id.is_empty() or staged.room_id != expected_room_id:
		return _invalid("Destination room identity does not match the request.")
	if requested_entrance_id.is_empty():
		return _invalid("Destination entrance identity is empty.")
	if not _semantic_ids_unique(staged.entrances(), "entrance_id"):
		return _invalid("Destination entrance identities are empty or duplicated.")
	if not _semantic_ids_unique(staged.exits(), "exit_id"):
		return _invalid("Destination exit identities are empty or duplicated.")

	var entrance_matches := staged.find_entrances(requested_entrance_id)
	if entrance_matches.size() != 1:
		return _invalid("Destination entrance is missing or ambiguous.")
	var entrance := entrance_matches[0]
	var entrance_transform := staged.relative_entrance_transform(entrance)
	if not _transform_is_valid(entrance_transform):
		return _invalid("Destination entrance transform is not finite and invertible.")
	var destination_transform := _compose_destination_transform(staged, entrance_transform)
	if not _transform_is_valid(destination_transform):
		return _invalid("Final composed destination transform is not finite and invertible.")

	var controllers := staged.interaction_controllers()
	if controllers.size() != 1:
		return _invalid("Destination must own exactly one InteractionController.")
	var grid_maps := staged.grid_maps()
	if grid_maps.size() > 1:
		return _invalid("Destination may own at most one room-local GridMap.")
	if not staged.can_apply_transition_state({}):
		return _invalid("Destination cannot accept the minimal transition-state seam.")

	return {
		"ok": true,
		"reason": "",
		"entrance": entrance,
		"controller": controllers[0],
		"grid_map": grid_maps[0] if grid_maps.size() == 1 else null,
		"destination_transform": destination_transform,
	}


func _semantic_ids_unique(nodes: Array, property_name: StringName) -> bool:
	var seen := {}
	for node in nodes:
		var semantic_id: StringName = node.get(property_name)
		if semantic_id.is_empty() or seen.has(semantic_id):
			return false
		seen[semantic_id] = true
	return true


func _transform_is_valid(value: Transform3D) -> bool:
	return value.origin.is_finite() \
		and value.basis.x.is_finite() \
		and value.basis.y.is_finite() \
		and value.basis.z.is_finite() \
		and absf(value.basis.determinant()) > 0.000001


func _compose_destination_transform(staged: WorldRoom, entrance_transform: Transform3D) -> Transform3D:
	return room_container.global_transform * staged.transform * entrance_transform


func _bind_room(room: WorldRoom) -> void:
	var controller := room.interaction_controllers()[0]
	controller.player = player
	controller.camera_rig = camera_rig
	var local_grid_maps := room.grid_maps()
	controller.grid_map = local_grid_maps[0] if local_grid_maps.size() == 1 else null


func _request_value(
	source_room_id: StringName,
	exit_id: StringName,
	destination_room_id: StringName,
	destination_entrance_id: StringName,
) -> TransitionRequest:
	return TransitionRequest.new(
		source_room_id,
		exit_id,
		destination_room_id,
		destination_entrance_id,
	)


func _bind_exits(room: WorldRoom) -> void:
	for room_exit in room.exits():
		room_exit.bind_transition_coordinator(self)


func _place_player(destination: Transform3D) -> void:
	player.place_at_world_transform(destination)


func _composition_ready() -> bool:
	return player != null and camera_rig != null and room_container != null


func _modal_active() -> bool:
	for controller in active_room.interaction_controllers():
		if controller.is_interacting:
			return true
	var loot_window := get_node_or_null("/root/LootWindow")
	var shop_window := get_node_or_null("/root/ShopWindow")
	return (loot_window != null and bool(loot_window.get("active"))) \
		or (shop_window != null and bool(shop_window.get("active")))


func _reject_without_pause(request: TransitionRequest, reason: String) -> bool:
	last_error = reason
	_feedback(reason)
	transition_failed.emit(request, reason)
	return false


func _reject_with_pause(request: TransitionRequest, reason: String) -> bool:
	_transitioning = false
	_game_state().release_pause(self, &"transition")
	return _reject_without_pause(request, reason)


func _invalid(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"entrance": null,
		"controller": null,
		"grid_map": null,
		"destination_transform": Transform3D.IDENTITY,
	}


func _game_state() -> Node:
	return get_node("/root/GameStateManager")


func _feedback(message: String) -> void:
	var feedback := get_node_or_null("/root/GameFeedback")
	if feedback != null:
		feedback.call("show_message", message)
	push_warning(message)
