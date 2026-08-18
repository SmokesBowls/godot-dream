# run_boundary_1_red.gd
# Godot version: 4.6.1
#
# Evolving contract runner for DREAM_WORLD_BOUNDARY_1.
# At 2ff8945 every implementation-facing requirement was BLOCKED. The
# authorized MINIMAL_TRANSITION_GREEN slice converts only A -> B lifecycle
# requirements into executable checks. Room-consequence and full GUI proof
# requirements remain explicitly BLOCKED for their later slices.

extends SceneTree

const SHELL_SCENE := "res://core/akashic.tscn"
const REQUEST_SCRIPT := "res://core/systems/world/transition_request.gd"
const ROOM_SCRIPT := "res://core/systems/world/world_room.gd"
const ENTRANCE_SCRIPT := "res://core/systems/world/room_entrance.gd"
const EXIT_SCRIPT := "res://core/systems/world/room_exit.gd"
const COORDINATOR_SCRIPT := "res://core/systems/world/transition_coordinator.gd"
const ROOM_A_SCENE := "res://core/scenes/world/room_a.tscn"
const ROOM_B_SCENE := "res://core/scenes/world/room_b.tscn"
const PROBE_SCRIPT := "res://tests/dream_world_boundary_1/staging_activity_probe.gd"

var _pass := 0
var _fail := 0
var _blocked := 0
var _results: Array[Dictionary] = []

var _request_script: Script
var _room_script: Script
var _entrance_script: Script
var _probe_script: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== DREAM WORLD BOUNDARY 1 -- selective GREEN authority ===")
	print("Contract: res://DREAM_WORLD_BOUNDARY_1_CONTRACT.md (v1.0)")
	print("Authorized slice: DREAM_WORLD_BOUNDARY_1_MINIMAL_TRANSITION_GREEN")
	print("")

	if not _required_production_exists():
		_report_missing_production_red()
		_print_deferred_requirements()
		_print_report()
		quit(1)
		return

	_request_script = load(REQUEST_SCRIPT)
	_room_script = load(ROOM_SCRIPT)
	_entrance_script = load(ENTRANCE_SCRIPT)
	_probe_script = load(PROBE_SCRIPT)

	_run_scope_guards()
	await _run_transition_contract_checks()
	_print_deferred_requirements()
	_print_report()

	# BLOCKED is expected for later slices. This authorized slice is GREEN
	# when every executable check passes and only the enumerated deferred
	# requirements remain.
	quit(1 if _fail > 0 else 0)


func _required_production_exists() -> bool:
	var required := [
		SHELL_SCENE,
		REQUEST_SCRIPT,
		ROOM_SCRIPT,
		ENTRANCE_SCRIPT,
		EXIT_SCRIPT,
		COORDINATOR_SCRIPT,
		ROOM_A_SCENE,
		ROOM_B_SCENE,
	]
	for path in required:
		if not ResourceLoader.exists(path):
			return false
	return true


func _report_missing_production_red() -> void:
	_check("GREEN production seams exist", false,
		"authorized production world-boundary scripts/scenes are still missing")
	_check("SS15.6/15.7 named A -> B transition is executable", false,
		"Room A/B and TransitionCoordinator do not exist")
	_check("SS15.8 same Player instance survives", false,
		"persistent runtime shell does not exist")
	_check("SS15.9 same Inventory instance survives", false,
		"persistent runtime shell does not exist")
	_check("SS10 invalid destination preserves current world", false,
		"transactional staging machinery does not exist")


func _run_scope_guards() -> void:
	_check("SS4 persistent runtime role is implemented by akashic.tscn",
		_scene_has_script(SHELL_SCENE))
	_check("SS3.4 persistent TransitionCoordinator implementation exists",
		ResourceLoader.exists(COORDINATOR_SCRIPT))
	_check("SS3.4 room-local Exit implementation exists",
		ResourceLoader.exists(EXIT_SCRIPT))
	_check("SS2 room-state store remains unimplemented in minimal transition GREEN",
		not _any_file_matches(["room_state_store", "roomstatestore"]))
	_check("SS2 tiny Room A/B fixtures exist without tactical demo compositor script",
		_fixture_is_tiny(ROOM_A_SCENE) and _fixture_is_tiny(ROOM_B_SCENE))
	print("")


func _run_transition_contract_checks() -> void:
	var request: Variant = _request_script.new(&"room_a", &"east_exit", &"room_b", &"west_entrance")
	var request_dict: Dictionary = request.to_dictionary()
	var request_keys := request_dict.keys()
	request_keys.sort()
	_check("SS7 TransitionRequest has exact coordinate-free semantic fields",
		request_keys == ["destination_entrance_id", "destination_room_id", "exit_id", "source_room_id"]
		and not _file_contains_any(REQUEST_SCRIPT, ["Vector3", "Transform3D", "position", "coordinate"]))
	var mutated_copy: Dictionary = request.to_dictionary()
	mutated_copy["source_room_id"] = &"tampered"
	for property_name in request_keys:
		request.set(property_name, &"tampered")
	# GDScript underscores are naming convention, not access control. Probe any
	# individually named semantic backing members directly; an immutable value
	# object must not expose these as writable storage.
	var request_property_names: Array[StringName] = []
	for property_info in request.get_property_list():
		request_property_names.append(property_info["name"])
	for backing_name in [
		&"_source_room_id",
		&"_exit_id",
		&"_destination_room_id",
		&"_destination_entrance_id",
	]:
		if backing_name in request_property_names:
			request.set(backing_name, &"backing_tamper")
	# A consolidated value container may exist, but replacement after
	# construction must be rejected by its setter.
	if &"_values" in request_property_names:
		request.set("_values", {
			"source_room_id": &"container_tamper",
			"exit_id": &"container_tamper",
			"destination_room_id": &"container_tamper",
			"destination_entrance_id": &"container_tamper",
		})
	_check("SS7 TransitionRequest exposes immutable value semantics",
		request.source_room_id == &"room_a"
		and request.exit_id == &"east_exit"
		and request.destination_room_id == &"room_b"
		and request.destination_entrance_id == &"west_entrance"
		and request.to_dictionary()["source_room_id"] == &"room_a")

	var shell_scene := load(SHELL_SCENE) as PackedScene
	var shell := shell_scene.instantiate()
	root.add_child(shell)
	await process_frame

	var player = shell.get_node_or_null("Player")
	var inventory = player.get_node_or_null("Inventory") if player else null
	var camera = shell.get_node_or_null("TacticalCameraRig")
	var camera_mode = shell.get_node_or_null("CameraModeController")
	var coordinator = shell.get_node_or_null("TransitionCoordinator")
	var room_container = shell.get_node_or_null("RoomContainer")
	var room_a = coordinator.active_room if coordinator else null

	_check("SS15.1 runtime begins in semantic room_a", room_a != null and room_a.room_id == &"room_a")
	_check("SS15.2 persistent Player and Inventory identities are recordable",
		player != null and inventory != null and player.get_instance_id() != 0 and inventory.get_instance_id() != 0)
	_check("SS3.1 Inventory remains a child of persistent Player", inventory != null and inventory.get_parent() == player)
	_check("SS3.2 persistent camera targets persistent Player", camera != null and camera.target == player)
	_check("SS3.2 CameraModeController is persistent and bound",
		camera_mode != null and camera_mode.get_parent() == shell
		and camera_mode.camera_rig == camera and camera_mode.player == player)
	_check("SS3.3 active room owns exactly one local InteractionController",
		room_a != null and room_a.interaction_controllers().size() == 1
		and room_a.interaction_controllers()[0].get_parent() == room_a)

	if shell == null or player == null or inventory == null or camera == null or coordinator == null or room_a == null:
		_check("GREEN runtime composition is complete enough to continue", false)
		if is_instance_valid(shell):
			shell.free()
		return

	var player_before = player
	var inventory_before = inventory
	var inventory_before_items: Dictionary = inventory.items.duplicate(true)
	var room_a_before = room_a
	var player_transform_before: Transform3D = player.global_transform

	# Toxic staging checks run before the successful transition. Every one
	# must preserve the exact current room and traveler identities.
	_check_failed_request_untouched(
		"SS16.1 missing destination resource",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"missing_room", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)

	coordinator.register_room(&"room_missing_entrance",
		_make_room_scene(&"room_missing_entrance", [{"id": &"other_entrance", "transform": Transform3D.IDENTITY}], true))
	_check_failed_request_untouched(
		"SS16.2 missing entrance",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"room_missing_entrance", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)

	coordinator.register_room(&"room_duplicate_entrance",
		_make_room_scene(&"room_duplicate_entrance", [
			{"id": &"west_entrance", "transform": Transform3D.IDENTITY},
			{"id": &"west_entrance", "transform": Transform3D(Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1, 0, 0))},
		], true, true))
	_probe_script.ready_count = 0
	_check_failed_request_untouched(
		"SS16.3 duplicate entrance",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"room_duplicate_entrance", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)
	_check("SS10 invalid staged room remains behaviorally inactive", _probe_script.ready_count == 0)

	coordinator.register_room(&"room_registry_name",
		_make_room_scene(&"different_declared_room", [{"id": &"west_entrance", "transform": Transform3D.IDENTITY}], true))
	_check_failed_request_untouched(
		"SS16.4 room identity mismatch",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"room_registry_name", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)

	coordinator.register_room(&"room_nested_identity",
		_make_room_scene(&"room_nested_identity", [{"id": &"west_entrance", "transform": Transform3D.IDENTITY}], true, false, true, true))
	_check_failed_request_untouched(
		"SS10 destination declares exactly one WorldRoom identity",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"room_nested_identity", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)

	var non_finite := Transform3D.IDENTITY
	non_finite.origin.x = NAN
	coordinator.register_room(&"room_non_finite",
		_make_room_scene(&"room_non_finite", [{"id": &"west_entrance", "transform": non_finite}], true))
	_check_failed_request_untouched(
		"SS10 non-finite entrance transform",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"room_non_finite", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)

	var singular_entrance := Transform3D(
		Basis(Vector3.ZERO, Vector3.UP, Vector3.BACK),
		Vector3.ZERO,
	)
	coordinator.register_room(&"room_singular_entrance",
		_make_room_scene(&"room_singular_entrance", [{"id": &"west_entrance", "transform": singular_entrance}], true))
	_check_failed_request_untouched(
		"SS10 finite singular entrance basis refuses before commit",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"room_singular_entrance", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)

	var non_finite_root := Transform3D.IDENTITY
	non_finite_root.origin.z = NAN
	coordinator.register_room(&"room_non_finite_root",
		_make_room_scene(
			&"room_non_finite_root",
			[{"id": &"west_entrance", "transform": Transform3D.IDENTITY}],
			true, false, true, false, non_finite_root,
		))
	_check_failed_request_untouched(
		"SS10 non-finite final composed entrance transform refuses before commit",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"room_non_finite_root", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)

	coordinator.register_room(&"room_missing_controller",
		_make_room_scene(&"room_missing_controller", [{"id": &"west_entrance", "transform": Transform3D.IDENTITY}], false))
	_check_failed_request_untouched(
		"SS10 missing mandatory room-local InteractionController",
		coordinator,
		_request_script.new(&"room_a", &"east_exit", &"room_missing_controller", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)

	_probe_script.ready_count = 0
	coordinator.register_room(&"room_stale_probe",
		_make_room_scene(&"room_stale_probe", [{"id": &"west_entrance", "transform": Transform3D.IDENTITY}], true, true))
	_check_failed_request_untouched(
		"SS16.5 stale source request",
		coordinator,
		_request_script.new(&"not_room_a", &"east_exit", &"room_stale_probe", &"west_entrance"),
		room_a_before, player_before, inventory_before, inventory_before_items, player_transform_before,
	)
	_check("SS16.5 stale source rejects before destination staging", _probe_script.ready_count == 0)

	var room_a_controller = room_a.interaction_controllers()[0]
	var modal_target := Interactable.new()
	modal_target.name = "ModalPreservationProof"
	room_a.add_child(modal_target)
	room_a_controller.begin_interaction(player, modal_target)
	_check("SS16.6 real room interaction session owns its pause before refusal",
		room_a_controller.is_interacting
		and _game_state().is_paused_by(room_a_controller, &"interaction"))
	_check_failed_request_untouched(
		"SS16.6 active room interaction refuses transition",
		coordinator, request, room_a_before, player_before, inventory_before,
		inventory_before_items, player_transform_before,
	)
	_check("SS16.6 refused transition preserves room interaction session",
		room_a_controller.is_interacting
		and is_instance_valid(modal_target)
		and _game_state().is_paused_by(room_a_controller, &"interaction"))
	room_a_controller.cancel_interaction()
	modal_target.queue_free()

	_loot_window().active = true
	_check_failed_request_untouched(
		"SS16.6 active LootWindow refuses transition",
		coordinator, request, room_a_before, player_before, inventory_before,
		inventory_before_items, player_transform_before,
	)
	_check("SS16.6 refused transition leaves LootWindow active", _loot_window().active)
	_loot_window().active = false

	_shop_window().active = true
	_check_failed_request_untouched(
		"SS16.6 active ShopWindow refuses transition",
		coordinator, request, room_a_before, player_before, inventory_before,
		inventory_before_items, player_transform_before,
	)
	_check("SS16.6 refused transition leaves ShopWindow active", _shop_window().active)
	_shop_window().active = false

	coordinator.transition_started.connect(func(_started_request):
		_loot_window().active = true
	, CONNECT_ONE_SHOT)
	_check_failed_request_untouched(
		"SS16.6 modal opened synchronously during transition refuses before commit",
		coordinator, request, room_a_before, player_before, inventory_before,
		inventory_before_items, player_transform_before,
	)
	_check("SS16.6 callback-opened LootWindow remains active after refusal", _loot_window().active)
	_loot_window().active = false

	# A separate pause owner remains effective after coordinator releases
	# only its own claim at the end of a successful transition.
	var other_pause_owner := Node.new()
	other_pause_owner.name = "IndependentPauseOwner"
	root.add_child(other_pause_owner)
	_game_state().request_pause(other_pause_owner, &"independent_test")
	var east_exit = room_a.find_exit(&"east_exit")
	var pause_observation := {"coordinator": false, "exit": false, "request_mutated": false}
	coordinator.transition_started.connect(func(_transition_request):
		pause_observation["coordinator"] = _game_state().is_paused_by(coordinator, &"transition")
		pause_observation["exit"] = _game_state().is_paused_by(east_exit, &"transition")
		_transition_request.set("_values", {
			"source_room_id": &"callback_tamper",
			"exit_id": &"callback_tamper",
			"destination_room_id": &"callback_tamper",
			"destination_entrance_id": &"callback_tamper",
		})
		pause_observation["request_mutated"] = (
			_transition_request.source_room_id != &"room_a"
			or _transition_request.exit_id != &"east_exit"
			or _transition_request.destination_room_id != &"room_b"
			or _transition_request.destination_entrance_id != &"west_entrance")
	, CONNECT_ONE_SHOT)

	_check("SS15.6 Room A exposes semantic east_exit", east_exit != null)
	var transition_succeeded: bool = east_exit.request_transition(player) if east_exit else false
	var room_b = coordinator.active_room

	_check("SS9 coordinator alone owns transition pause during transition",
		pause_observation["coordinator"] and not pause_observation["exit"])
	_check("SS15.6/15.7 named A -> B transition commits", transition_succeeded
		and room_b != null and room_b.room_id == &"room_b")
	_check("SS7 callback cannot mutate or redirect the validated transition request",
		not pause_observation["request_mutated"] and room_b != null and room_b.room_id == &"room_b")
	_check("SS10 Room A is removed only after valid Room B staged", not is_instance_valid(room_a_before))
	_check("SS15.8 same Player instance survives", shell.get_node("Player") == player_before)
	_check("SS15.9 same Inventory instance survives", shell.get_node("Player/Inventory") == inventory_before)
	_check("SS15 traveler inventory contents remain unchanged", inventory.items == inventory_before_items)

	var west_entrance = room_b.find_entrance(&"west_entrance") if room_b else null
	_check("SS15.7 Player preserves Room B west_entrance authored Transform3D", west_entrance != null
		and player.global_transform.is_equal_approx(west_entrance.global_transform))

	var room_b_controllers: Array = room_b.interaction_controllers() if room_b else []
	var room_b_controller = room_b_controllers[0] if room_b_controllers.size() == 1 else null
	_check("SS3.3 destination InteractionController remains room-local",
		room_b_controller != null and room_b_controller.get_parent() == room_b)
	_check("SS3.3 destination local controller receives persistent Player and camera",
		room_b_controller != null and room_b_controller.player == player and room_b_controller.camera_rig == camera)
	_check("SS3.2 persistent camera remains bound after transition",
		camera.get_parent() == shell and camera.target == player and camera.camera != null)
	_check("SS3.2 persistent camera-mode controller remains bound after transition",
		camera_mode.camera_rig == camera and camera_mode.player == player)
	var player_input = player.get_node_or_null("PlayerInput")
	_check("GREEN persistent controls remain bound after transition",
		player_input != null and player_input.actor == player and player_input.camera_rig == camera)
	_check("SS14 persistent/rebound HUD observes same Inventory",
		shell.get_node_or_null("InventoryHud") != null
		and shell.get_node("InventoryHud").inventory == inventory)
	_check("SS14 hotbar remains present after transition", shell.get_node_or_null("UI/HotbarContainer") != null)

	_check("SS16.8 independent pause survives coordinator release",
		_game_state().is_paused_by(other_pause_owner, &"independent_test")
		and not _game_state().is_paused_by(coordinator, &"transition")
		and paused)
	_game_state().release_pause(other_pause_owner, &"independent_test")
	other_pause_owner.queue_free()
	_check("SS15.17 successful transition leaves no transition pause claim",
		not _game_state().is_paused_by(coordinator, &"transition") and not paused)

	# Movement must begin from the entrance placement, not stale Room A
	# GridActor.current_step state.
	player.move_duration = 0.02
	var movement_origin: Vector3 = player.global_position
	var movement_accepted: bool = player.request_move(Vector2i(0, -1))
	await physics_frame
	await physics_frame
	await physics_frame
	_check("GREEN movement remains functional from Room B entrance",
		movement_accepted and not player.global_position.is_equal_approx(movement_origin)
		and player.global_position.distance_to(movement_origin) < 1.0)

	var room_b_interactable = room_b.get_node_or_null("InteractionProof")
	if room_b_controller and room_b_interactable:
		room_b_controller.begin_interaction(player, room_b_interactable)
	_check("GREEN room-local interaction remains functional in Room B",
		room_b_controller != null and room_b_controller.is_interacting
		and _game_state().is_paused_by(room_b_controller, &"interaction"))
	if room_b_controller and room_b_controller.is_interacting:
		room_b_controller.cancel_interaction()
	_check("GREEN Room B interaction releases only its own pause",
		room_b_controller != null and not room_b_controller.is_interacting and not paused)

	# SS16.7 is a direct executable proof of why Exit cannot own transition pause.
	var temporary_room := Node.new()
	var temporary_exit := Node.new()
	root.add_child(temporary_room)
	temporary_room.add_child(temporary_exit)
	var pause_count_before_exit_probe: int = _game_state().active_pause_count()
	_game_state().request_pause(temporary_exit, &"transition")
	temporary_room.queue_free()
	await process_frame
	_check("SS16.7 room-local requester teardown releases its pause claim",
		_game_state().active_pause_count() == pause_count_before_exit_probe and not paused)

	shell.queue_free()
	await process_frame
	await _check_physics_exit_transition()
	print("")


func _check_physics_exit_transition() -> void:
	var shell = (load(SHELL_SCENE) as PackedScene).instantiate()
	root.add_child(shell)
	await process_frame
	await physics_frame

	var player = shell.get_node("Player")
	var inventory = player.get_node("Inventory")
	var camera = shell.get_node("TacticalCameraRig")
	var camera_mode = shell.get_node("CameraModeController")
	var coordinator = shell.get_node("TransitionCoordinator")
	var identities := {
		"player": player.get_instance_id(),
		"inventory": inventory.get_instance_id(),
		"camera": camera.get_instance_id(),
		"camera_mode": camera_mode.get_instance_id(),
	}

	player.place_at_world_transform(Transform3D(Basis.IDENTITY, Vector3(3, 0, 0)))
	player.move_duration = 0.02
	var move_accepted: bool = player.request_move(Vector2i(1, 0))
	for frame in range(12):
		await physics_frame

	var room = coordinator.active_room
	var controllers: Array = room.interaction_controllers() if room else []
	var controller = controllers[0] if controllers.size() == 1 else null
	_check("GREEN physics-triggered east_exit safely transitions outside callback",
		move_accepted
		and room != null and room.room_id == &"room_b"
		and shell.get_node("Player").get_instance_id() == identities["player"]
		and shell.get_node("Player/Inventory").get_instance_id() == identities["inventory"]
		and shell.get_node("TacticalCameraRig").get_instance_id() == identities["camera"]
		and shell.get_node("CameraModeController").get_instance_id() == identities["camera_mode"]
		and camera.target == player
		and controller != null and controller.player == player and controller.camera_rig == camera
		and not paused)

	shell.queue_free()
	await process_frame


func _check_failed_request_untouched(
	name: String,
	coordinator,
	request,
	expected_room,
	expected_player,
	expected_inventory,
	expected_items: Dictionary,
	expected_transform: Transform3D,
) -> void:
	# Author the existing source exit toward this toxic fixture so the
	# request reaches destination staging rather than failing an earlier
	# source-exit mismatch check. Restore it before asserting untouchedness.
	var source_exit = expected_room.find_exit(request.exit_id)
	var original_room_id: StringName
	var original_entrance_id: StringName
	var source_matches: bool = request.source_room_id == expected_room.room_id and source_exit != null
	if source_matches:
		original_room_id = source_exit.destination_room_id
		original_entrance_id = source_exit.destination_entrance_id
		source_exit.destination_room_id = request.destination_room_id
		source_exit.destination_entrance_id = request.destination_entrance_id
	var succeeded: bool = coordinator.request_transition(request)
	if source_matches:
		source_exit.destination_room_id = original_room_id
		source_exit.destination_entrance_id = original_entrance_id
	_check(name,
		not succeeded
		and coordinator.active_room == expected_room
		and is_instance_valid(expected_room)
		and expected_player.get_parent() != null
		and expected_player.get_node("Inventory") == expected_inventory
		and expected_inventory.items == expected_items
		and expected_player.global_transform.is_equal_approx(expected_transform)
		and (not source_matches or (
			source_exit.destination_room_id == original_room_id
			and source_exit.destination_entrance_id == original_entrance_id))
		and not _game_state().is_paused_by(coordinator, &"transition"))


func _make_room_scene(
	room_id: StringName,
	entrance_specs: Array,
	include_controller: bool,
	include_probe := false,
	include_grid_map := true,
	include_nested_room := false,
	room_transform: Transform3D = Transform3D.IDENTITY,
) -> PackedScene:
	var room := Node3D.new()
	room.name = "TestStagedRoom"
	room.set_script(_room_script)
	room.set("room_id", room_id)
	room.transform = room_transform

	for spec in entrance_specs:
		var entrance := Marker3D.new()
		entrance.name = "Entrance_%s" % String(spec["id"])
		entrance.set_script(_entrance_script)
		entrance.set("entrance_id", spec["id"])
		entrance.transform = spec["transform"]
		room.add_child(entrance)
		entrance.owner = room

	if include_controller:
		var controller := Node.new()
		controller.name = "InteractionController"
		controller.set_script(load("res://core/systems/tactical_world/interaction_controller.gd"))
		room.add_child(controller)
		controller.owner = room

	if include_grid_map:
		var grid_map := GridMap.new()
		grid_map.name = "GridMap"
		room.add_child(grid_map)
		grid_map.owner = room

	if include_probe:
		var probe := Node.new()
		probe.name = "StagingActivityProbe"
		probe.set_script(_probe_script)
		room.add_child(probe)
		probe.owner = room

	if include_nested_room:
		var nested_room := Node3D.new()
		nested_room.name = "NestedWorldRoom"
		nested_room.set_script(_room_script)
		nested_room.set("room_id", &"nested_duplicate_identity")
		room.add_child(nested_room)
		nested_room.owner = room

	var packed := PackedScene.new()
	var packed_ok := packed.pack(room) == OK
	room.free()
	if not packed_ok:
		return null
	return packed


func _print_deferred_requirements() -> void:
	var deferred := [
		["SS15.3", "pick up room_a/apple_01 -- deferred to room-state GREEN"],
		["SS15.4", "partially loot room_a/chest_01 -- deferred to room-state GREEN"],
		["SS15.5", "confirm room consequence inventory mutations -- deferred to room-state GREEN"],
		["SS15.10", "full GUI presentation proof in Room B -- deferred to LIVE GODOT PROOF"],
		["SS15.11", "return through Room B named exit -- deferred to room-state GREEN"],
		["SS15.12", "arrive back in Room A -- deferred to room-state GREEN"],
		["SS15.13", "same identities after round trip -- deferred to room-state GREEN"],
		["SS15.14", "apple remains unavailable -- deferred to room-state GREEN"],
		["SS15.15", "exact chest remaining_loot -- deferred to room-state GREEN"],
		["SS15.16", "full GUI/collision/interaction proof after return -- deferred"],
		["SS16.9", "stateful object ID collision -- deferred with room-state seam"],
	]
	for item in deferred:
		_blocked_probe("%s: %s" % [item[0], item[1]], "outside authorized minimal A -> B GREEN slice")
	print("")


func _scene_has_script(scene_path: String) -> bool:
	if not FileAccess.file_exists(scene_path):
		return false
	var text := FileAccess.get_file_as_string(scene_path)
	return text.findn("script = ExtResource") != -1 or text.findn("[sub_resource type=\"GDScript\"") != -1


func _fixture_is_tiny(scene_path: String) -> bool:
	if not FileAccess.file_exists(scene_path):
		return false
	var text := FileAccess.get_file_as_string(scene_path)
	return text.find("tactical_demo_world.gd") == -1 and text.length() < 12000


func _any_file_matches(needles: Array) -> bool:
	return not _scan_dir("res://core", needles).is_empty()


func _scan_dir(path: String, needles: Array) -> Array[String]:
	var hits: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return hits
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full := path.path_join(entry)
		if dir.current_is_dir():
			hits.append_array(_scan_dir(full, needles))
		else:
			var lower := entry.to_lower()
			for needle in needles:
				if lower.find(String(needle).to_lower()) != -1:
					hits.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()
	return hits


func _file_contains_any(path: String, needles: Array) -> bool:
	var text := FileAccess.get_file_as_string(path)
	for needle in needles:
		if text.find(String(needle)) != -1:
			return true
	return false


func _game_state() -> Node:
	return root.get_node("GameStateManager")


func _loot_window() -> Node:
	return root.get_node("LootWindow")


func _shop_window() -> Node:
	return root.get_node("ShopWindow")


func _check(name: String, passed: bool, reason := "") -> void:
	if passed:
		_pass += 1
	else:
		_fail += 1
	_results.append({"name": name, "status": "PASS" if passed else "FAIL", "reason": reason})
	print("[%s] %s%s" % ["PASS" if passed else "FAIL", name, " -- " + reason if not passed and not reason.is_empty() else ""])


func _blocked_probe(name: String, reason: String) -> void:
	_blocked += 1
	_results.append({"name": name, "status": "BLOCKED", "reason": reason})
	print("[BLOCKED] %s\n           -- %s" % [name, reason])


func _print_report() -> void:
	print("=== Summary ===")
	print("PASS:    %d" % _pass)
	print("FAIL:    %d" % _fail)
	print("BLOCKED: %d (intentional later-slice requirements)" % _blocked)
	print("SLICE:   %s" % ("GREEN" if _fail == 0 else "RED"))
	print("MILESTONE: incomplete until deferred room-state/live proofs run")
