# dream_event_store.gd
# Godot version: 4.6
# Ported from a Godot 3.x original. See dream_persistence_adapter.gd
# for the rationale: this file contains ONLY decision logic
# (what to record, when to checkpoint, how to replay, how to hash
# integrity). It never calls FileAccess/DirAccess/Time/Thread/OS
# directly -- it calls `persistence` (a DreamPersistenceAdapter)
# instead. If Godot's engine APIs change again, this file should
# not need to change.
#
# CHANGE LOG (for future you):
#   v1.0 (Godot 3.x, lost in OS crash, reconstructed)
#   v2.0 (Godot 4.6) -- this file. Logic 1:1 ported from the
#        original design; only the engine-call surface moved to
#        the adapter. See dream_persistence_adapter.gd CONTRACT_VERSION.

extends Node
class_name DreamEventStore

# ---------------------------------------------------------------------
# Event types
# ---------------------------------------------------------------------

enum EventType {
	DREAM_ENTERED,
	DREAM_EXITED,
	PHYSICS_MODIFIED,
	PHYSICS_REVERTED,
	ENTROPY_CHANGED,
	SNAPSHOT_CREATED,
	CORRUPTION_DETECTED,
	ANCHOR_APPLIED,
	ANCHOR_REMOVED,
	REALITY_SHIFTED,
	UI_STATE_CHANGED,
	NPC_BEHAVIOR_OVERRIDE,
	PLAYER_INVENTORY_ALTERED,
	DIALOGUE_STATE_CHANGED,
	TEMPORAL_PARADOX_RESOLVED,
	SYSTEM_QUARANTINE_ACTIVATED,

	# --- Game Boy dream mode (added for gameboy_dream_integration port) ---
	# Appended at the end so existing enum values keep their integer
	# positions -- old checkpoints/event logs that store these as ints
	# stay valid.
	VISUAL_MODE_CHANGED,
	CAMERA_PERSPECTIVE_SHIFTED,
	PALETTE_APPLIED,
	SPRITE_SET_SWAPPED,
	PHYSICS_MODE_CHANGED,
}

# ---------------------------------------------------------------------
# Dependencies (injected, not autoloaded directly, so this is testable
# without the full EngAIn singleton graph being present)
# ---------------------------------------------------------------------

@export var persistence_path: NodePath
var persistence: DreamPersistenceAdapter

# These remain references to your existing autoloads/singletons.
# Left as-is from the original design; if your lane contracts require
# these to come through GodotSim/EngAInOS gates instead of direct
# autoload access, that's a separate refactor from this port and
# should be done deliberately, not silently here.
@onready var _dream_state_manager = DreamStateManager
@onready var _reality_engine = RealityEngine
@onready var _physics_stack = PhysicsStack
@onready var _global = Global
@onready var _ui = UI
@onready var _event_bus = EventBus

# ---------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------

var event_log: Array = []
var event_checkpoints: Dictionary = {}
var event_pool: Array = []
var max_events_per_checkpoint := 100
var max_pool_size := 500

var checkpoint_directory := "user://dream_checkpoints/"
var persistent_checkpoints: Dictionary = {}

var performance_metrics := {
	"events_recorded": 0,
	"checkpoints_created": 0,
	"replays_executed": 0,
	"integrity_violations": 0,
	"disk_writes": 0,
}

# ---------------------------------------------------------------------
# Background processing
# ---------------------------------------------------------------------

var _checkpoint_thread: Thread
var _pending_checkpoints: Array = []
var _thread_mutex: Mutex
var _thread_running := false

func _ready() -> void:
	persistence = get_node(persistence_path) as DreamPersistenceAdapter
	if persistence == null:
		push_error("DreamEventStore: persistence_path must point to a DreamPersistenceAdapter node")
		return

	persistence.ensure_dir(checkpoint_directory)

	for i in range(max_pool_size):
		event_pool.append(DreamEvent.new())

	load_persistent_checkpoints()
	setup_background_processing()
	connect_to_systems()

func _exit_tree() -> void:
	# Cleanly stop the background thread on shutdown so Godot doesn't
	# warn about a thread still running at exit.
	_thread_running = false
	if _checkpoint_thread != null and _checkpoint_thread.is_started():
		_checkpoint_thread.wait_to_finish()

# ---------------------------------------------------------------------
# Recording
# ---------------------------------------------------------------------

func record_event(type: int, data: Dictionary, system_id: String = "dream") -> void:
	var event := get_pooled_event()
	event.initialize(
		type,
		data,
		system_id,
		_dream_state_manager.dream_depth,
		_reality_engine.timeline_entropy,
		persistence.now_ms()
	)

	event_log.append(event)
	performance_metrics.events_recorded += 1

	if should_create_checkpoint():
		queue_checkpoint_creation()

	_event_bus.emit_signal("dream_event_recorded", event.to_dict())

func get_pooled_event() -> DreamEvent:
	if event_pool.size() > 0:
		return event_pool.pop_back()
	return DreamEvent.new()

func return_event_to_pool(event: DreamEvent) -> void:
	if event_pool.size() < max_pool_size:
		event.reset()
		event_pool.append(event)

# ---------------------------------------------------------------------
# Checkpointing
# ---------------------------------------------------------------------

func should_create_checkpoint() -> bool:
	var events_since_last: bool = event_log.size() % max_events_per_checkpoint == 0
	var entropy_threshold: bool = absf(_reality_engine.timeline_entropy - get_last_checkpoint_entropy()) > 25.0
	var time_threshold: bool = persistence.now_ms() - get_last_checkpoint_time() > 60000
	return events_since_last or entropy_threshold or time_threshold

func get_last_checkpoint_entropy() -> float:
	var last := get_last_checkpoint()
	if last == null:
		return 0.0
	return last.system_snapshot.entropy_levels.timeline

func get_last_checkpoint_time() -> int:
	var last := get_last_checkpoint()
	if last == null:
		return 0
	return last.timestamp

func get_last_checkpoint() -> Dictionary:
	if event_checkpoints.is_empty():
		return {}
	var newest_id := ""
	var newest_ts := -1
	for id in event_checkpoints.keys():
		var ts: int = event_checkpoints[id].timestamp
		if ts > newest_ts:
			newest_ts = ts
			newest_id = id
	return event_checkpoints.get(newest_id, {})

func queue_checkpoint_creation() -> void:
	_thread_mutex.lock()
	_pending_checkpoints.append({
		"id": generate_checkpoint_id(),
		"timestamp": persistence.now_ms(),
		"events_count": event_log.size(),
		"priority": calculate_checkpoint_priority(),
	})
	_thread_mutex.unlock()

func generate_checkpoint_id() -> String:
	return "cp_%d_%d" % [persistence.now_ms(), randi()]

func calculate_checkpoint_priority() -> int:
	var base_priority := 1
	if _reality_engine.timeline_entropy > 75.0:
		base_priority += 3
	if _dream_state_manager.dream_depth > 2:
		base_priority += 2
	if _global.locked_anchor != "":
		base_priority += 1
	return base_priority

func create_checkpoint_background(checkpoint_data: Dictionary) -> void:
	var checkpoint_id: String = checkpoint_data.id
	var checkpoint := {
		"id": checkpoint_id,
		"events_count": checkpoint_data.events_count,
		"system_snapshot": capture_enhanced_system_snapshot(),
		"timestamp": checkpoint_data.timestamp,
		"integrity_hash": calculate_enhanced_integrity_hash(),
		"priority": checkpoint_data.priority,
		"disk_persisted": false,
	}

	event_checkpoints[checkpoint_id] = checkpoint
	performance_metrics.checkpoints_created += 1

	if checkpoint_data.priority >= 3:
		persist_checkpoint_to_disk(checkpoint_id, checkpoint)

func persist_checkpoint_to_disk(checkpoint_id: String, checkpoint: Dictionary) -> void:
	var file_path := checkpoint_directory + checkpoint_id + ".dat"
	var bytes := persistence.serialize(checkpoint)
	if persistence.write_bytes(file_path, bytes):
		checkpoint.disk_persisted = true
		event_checkpoints[checkpoint_id] = checkpoint
		persistent_checkpoints[checkpoint_id] = file_path
		performance_metrics.disk_writes += 1
	else:
		push_error("DreamEventStore: failed to persist checkpoint " + checkpoint_id)

func load_persistent_checkpoints() -> void:
	for file_name in persistence.list_dir(checkpoint_directory):
		if file_name.ends_with(".dat"):
			var checkpoint_id := file_name.get_basename()
			var file_path := checkpoint_directory + file_name
			load_checkpoint_from_disk(checkpoint_id, file_path)

func load_checkpoint_from_disk(checkpoint_id: String, file_path: String) -> void:
	var bytes := persistence.read_bytes(file_path)
	if bytes.is_empty() and not persistence.file_exists(file_path):
		return
	var checkpoint = persistence.deserialize(bytes)
	if typeof(checkpoint) != TYPE_DICTIONARY:
		push_warning("DreamEventStore: corrupted checkpoint file (not a dict): " + file_path)
		persistence.delete_file(file_path)
		return

	if validate_checkpoint_integrity(checkpoint):
		event_checkpoints[checkpoint_id] = checkpoint
		persistent_checkpoints[checkpoint_id] = file_path
	else:
		push_warning("DreamEventStore: corrupted checkpoint file: " + file_path)
		persistence.delete_file(file_path)

func validate_checkpoint_integrity(checkpoint: Dictionary) -> bool:
	var required_fields := ["id", "events_count", "system_snapshot", "timestamp", "integrity_hash"]
	for field in required_fields:
		if not checkpoint.has(field):
			return false
	return validate_snapshot_structure(checkpoint.system_snapshot)

# ---------------------------------------------------------------------
# Snapshot capture
# ---------------------------------------------------------------------

func capture_enhanced_system_snapshot() -> Dictionary:
	return {
		"physics_stack": _physics_stack.physics_mod_stack.duplicate(true),
		"dream_depth": _dream_state_manager.dream_depth,
		"dream_state": _dream_state_manager.current_state,

		"entropy_levels": {
			"timeline": _reality_engine.timeline_entropy,
			"dream": _dream_state_manager.dream_entropy,
			"velocity": _reality_engine.entropy_velocity if _reality_engine.has_method("get_entropy_velocity") else 0.0,
		},

		"anchor_state": {
			"locked_anchor": _global.locked_anchor,
			"anchor_strength": _global.get("anchor_strength") if _global.get("anchor_strength") != null else 0.0,
			"anchor_timestamp": _global.get("anchor_lock_time") if _global.get("anchor_lock_time") != null else 0,
		},

		"player_snapshot": {
			"position": _global.player.global_position if is_instance_valid(_global.player) else Vector2.ZERO,
			"health": _global.player_health,
			"inventory_fingerprint": _global.inventory.calculate_fingerprint() if _global.inventory.has_method("calculate_fingerprint") else "",
			"abilities_unlocked": _global.unlocked_abilities.duplicate(),
		},

		"ui_state": {
			"current_priority": _ui.current_priority,
			"active_dialogs": _ui.get_active_dialogs() if _ui.has_method("get_active_dialogs") else [],
			"hud_visibility": _ui.get_hud_visibility() if _ui.has_method("get_hud_visibility") else true,
		},

		"npc_overrides": capture_npc_behavior_state(),
	}

func capture_npc_behavior_state() -> Dictionary:
	var npc_state := {}
	for npc in get_tree().get_nodes_in_group("dream_npcs"):
		if npc.has_method("get_behavior_snapshot"):
			npc_state[str(npc.get_path())] = npc.get_behavior_snapshot()
	return npc_state

func calculate_enhanced_integrity_hash() -> String:
	var hash_components: Array[String] = []

	hash_components.append(str(_dream_state_manager.dream_depth))
	hash_components.append(str(_reality_engine.timeline_entropy))
	hash_components.append(str(_physics_stack.physics_mod_stack.size()))

	for mod in _physics_stack.physics_mod_stack:
		if mod.has("params"):
			hash_components.append(str(mod.params.hash()))

	if _global.inventory.has_method("calculate_fingerprint"):
		hash_components.append(_global.inventory.calculate_fingerprint())

	hash_components.append(_global.locked_anchor)
	hash_components.append(str(_global.get("anchor_strength") if _global.get("anchor_strength") != null else 0.0))

	return persistence.hash_text("|".join(hash_components))

# ---------------------------------------------------------------------
# Replay
# ---------------------------------------------------------------------

func replay_events_from_checkpoint(checkpoint_id: String) -> bool:
	if not event_checkpoints.has(checkpoint_id):
		push_error("DreamEventStore: checkpoint not found: " + checkpoint_id)
		return false

	var checkpoint: Dictionary = event_checkpoints[checkpoint_id]
	var start_index: int = checkpoint.events_count

	if not restore_enhanced_system_snapshot(checkpoint.system_snapshot):
		return false

	var replay_errors := 0
	for i in range(start_index, event_log.size()):
		var event = event_log[i]
		if not replay_single_event_safe(event):
			replay_errors += 1
			if replay_errors > 5:
				push_error("DreamEventStore: replay failed due to excessive errors")
				return false

	performance_metrics.replays_executed += 1
	return true

func replay_single_event_safe(event) -> bool:
	var success := true
	match event.type:
		EventType.DREAM_ENTERED:
			success = replay_dream_entry(event)
		EventType.PHYSICS_MODIFIED:
			success = replay_physics_modification(event)
		EventType.ENTROPY_CHANGED:
			success = replay_entropy_change(event)
		EventType.UI_STATE_CHANGED:
			success = replay_ui_state_change(event)
		EventType.NPC_BEHAVIOR_OVERRIDE:
			success = replay_npc_behavior_change(event)
		EventType.PLAYER_INVENTORY_ALTERED:
			success = replay_inventory_change(event)
		_:
			push_warning("DreamEventStore: unknown event type in replay: " + str(event.type))
			success = false
	return success

func replay_dream_entry(event) -> bool:
	_dream_state_manager.dream_depth = event.data.get("depth", _dream_state_manager.dream_depth)
	_dream_state_manager.current_state = event.data.get("new_state", _dream_state_manager.current_state)
	return true

func replay_physics_modification(event) -> bool:
	var physics_data: Dictionary = event.data

	_physics_stack.revert_physics_mod(physics_data.name)

	if validate_physics_parameters(physics_data.params):
		_physics_stack.apply_physics_mod(physics_data.name, physics_data.params)
		return true
	else:
		push_error("DreamEventStore: invalid physics parameters in replay")
		return false

func validate_physics_parameters(params: Dictionary) -> bool:
	if not params.has("gravity"):
		return false
	var gravity: float = params.gravity
	if absf(gravity) > 100.0:
		return false
	return true

func replay_entropy_change(event) -> bool:
	if event.data.has("timeline"):
		_reality_engine.timeline_entropy = clampf(event.data.timeline, 0.0, 100.0)
	if event.data.has("dream"):
		_dream_state_manager.dream_entropy = clampf(event.data.dream, 0.0, 100.0)
	return true

func replay_ui_state_change(event) -> bool:
	if event.data.has("new_priority"):
		_ui.current_priority = event.data.new_priority
		return true
	return false

func replay_npc_behavior_change(event) -> bool:
	# Original implementation did not specify a body beyond dispatch;
	# preserved as a hook point. Returns true (no-op success) rather
	# than silently failing replay for an event type that was always
	# routed here without a defined restore action.
	return true

func replay_inventory_change(event) -> bool:
	# Same note as replay_npc_behavior_change -- hook point preserved
	# from the original dispatch table.
	return true

func restore_enhanced_system_snapshot(snapshot: Dictionary) -> bool:
	if not validate_snapshot_structure(snapshot):
		return false

	_physics_stack.physics_mod_stack = snapshot.physics_stack.duplicate(true)
	_physics_stack.apply_current_stack()

	_dream_state_manager.dream_depth = snapshot.dream_depth
	_dream_state_manager.current_state = snapshot.dream_state

	var entropy_data: Dictionary = snapshot.entropy_levels
	_reality_engine.timeline_entropy = clampf(entropy_data.timeline, 0.0, 100.0)
	_dream_state_manager.dream_entropy = clampf(entropy_data.dream, 0.0, 100.0)

	if snapshot.has("anchor_state"):
		var anchor_data: Dictionary = snapshot.anchor_state
		_global.locked_anchor = anchor_data.locked_anchor
		_global.anchor_strength = anchor_data.get("anchor_strength", 0.0)

	if snapshot.has("player_snapshot") and is_instance_valid(_global.player):
		var player_data: Dictionary = snapshot.player_snapshot
		_global.player.global_position = player_data.position
		_global.player_health = player_data.health

	return true

func validate_snapshot_structure(snapshot: Dictionary) -> bool:
	var required_fields := [
		"physics_stack", "dream_depth", "dream_state",
		"entropy_levels", "player_snapshot",
	]
	for field in required_fields:
		if not snapshot.has(field):
			push_error("DreamEventStore: missing snapshot field: " + field)
			return false
	return true

# ---------------------------------------------------------------------
# Background thread
# ---------------------------------------------------------------------

func setup_background_processing() -> void:
	_thread_mutex = persistence.make_mutex()
	_checkpoint_thread = persistence.make_thread()
	_thread_running = true
	persistence.start_thread(_checkpoint_thread, Callable(self, "_background_checkpoint_processor"))

func _background_checkpoint_processor() -> void:
	while _thread_running:
		_thread_mutex.lock()
		var has_pending: bool = _pending_checkpoints.size() > 0
		var checkpoint_data = _pending_checkpoints.pop_front() if has_pending else null
		_thread_mutex.unlock()

		if checkpoint_data:
			create_checkpoint_background(checkpoint_data)
		else:
			persistence.sleep_ms(100)

# ---------------------------------------------------------------------
# Signal wiring (Godot 4 Callable-based connect, no string method names)
# ---------------------------------------------------------------------

func connect_to_systems() -> void:
	if _dream_state_manager:
		_dream_state_manager.dream_state_changed.connect(_on_dream_state_changed)
		_dream_state_manager.dream_corrupted.connect(_on_dream_corrupted)

	if _reality_engine:
		_reality_engine.reality_shift.connect(_on_reality_shift)
		_reality_engine.entropy_threshold_crossed.connect(_on_entropy_threshold_crossed)

	if _ui:
		_ui.priority_changed.connect(_on_ui_priority_changed)

	if _global.inventory and _global.inventory.has_signal("item_changed"):
		_global.inventory.item_changed.connect(_on_inventory_changed)

func _on_dream_state_changed(old_state, new_state) -> void:
	var entering: bool = new_state == _dream_state_manager.DreamState.DREAMING
	record_event(EventType.DREAM_ENTERED if entering else EventType.DREAM_EXITED, {
		"old_state": old_state,
		"new_state": new_state,
		"depth": _dream_state_manager.dream_depth,
	})

func _on_dream_corrupted() -> void:
	record_event(EventType.CORRUPTION_DETECTED, {
		"dream_depth": _dream_state_manager.dream_depth,
	})
	performance_metrics.integrity_violations += 1

func _on_reality_shift(data: Dictionary = {}) -> void:
	record_event(EventType.REALITY_SHIFTED, data)

func _on_entropy_threshold_crossed(threshold: float = 0.0) -> void:
	record_event(EventType.ENTROPY_CHANGED, {
		"threshold": threshold,
		"timeline": _reality_engine.timeline_entropy,
		"dream": _dream_state_manager.dream_entropy,
	})

func _on_ui_priority_changed(old_priority, new_priority) -> void:
	record_event(EventType.UI_STATE_CHANGED, {
		"old_priority": old_priority,
		"new_priority": new_priority,
		"timestamp": persistence.now_ms(),
	}, "ui")

func _on_inventory_changed(item, action) -> void:
	record_event(EventType.PLAYER_INVENTORY_ALTERED, {
		"item_id": item.id if item else "unknown",
		"action": action,
		"dream_origin": _dream_state_manager.current_state == _dream_state_manager.DreamState.DREAMING,
		"inventory_fingerprint": _global.inventory.calculate_fingerprint() if _global.inventory.has_method("calculate_fingerprint") else "",
	}, "inventory")

# ---------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------

func cleanup_old_events() -> void:
	var max_age := 1800000
	var current_time := persistence.now_ms()

	var events_removed := 0
	for i in range(event_log.size() - 1, -1, -1):
		var event = event_log[i]
		if current_time - event.timestamp > max_age:
			return_event_to_pool(event)
			event_log.remove_at(i)
			events_removed += 1

	cleanup_old_checkpoints(max_age)
	print("DreamEventStore: cleaned up %d old events" % events_removed)

func cleanup_old_checkpoints(max_age: int) -> void:
	var current_time := persistence.now_ms()
	var checkpoints_to_remove: Array[String] = []

	for checkpoint_id in event_checkpoints.keys():
		var checkpoint: Dictionary = event_checkpoints[checkpoint_id]
		var age: int = current_time - checkpoint.timestamp
		if age > max_age and checkpoint.get("priority", 1) < 3:
			checkpoints_to_remove.append(checkpoint_id)

	for checkpoint_id in checkpoints_to_remove:
		if persistent_checkpoints.has(checkpoint_id):
			persistence.delete_file(persistent_checkpoints[checkpoint_id])
			persistent_checkpoints.erase(checkpoint_id)
		event_checkpoints.erase(checkpoint_id)

func get_performance_report() -> Dictionary:
	return performance_metrics.duplicate()

# ---------------------------------------------------------------------
# Pooled event object
# ---------------------------------------------------------------------

class DreamEvent:
	var id := ""
	var type := 0
	var data := {}
	var timestamp := 0
	var system_id := ""
	var dream_depth := 0
	var entropy_state := 0.0

	func initialize(event_type: int, event_data: Dictionary, sys_id: String, depth: int, entropy: float, ts: int) -> void:
		id = "%d_%d" % [ts, randi()]
		type = event_type
		data = event_data.duplicate(true)
		timestamp = ts
		system_id = sys_id
		dream_depth = depth
		entropy_state = entropy

	func reset() -> void:
		id = ""
		type = 0
		data.clear()
		timestamp = 0
		system_id = ""
		dream_depth = 0
		entropy_state = 0.0

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"type": type,
			"data": data,
			"timestamp": timestamp,
			"system_id": system_id,
			"dream_depth": dream_depth,
			"entropy_state": entropy_state,
		}
