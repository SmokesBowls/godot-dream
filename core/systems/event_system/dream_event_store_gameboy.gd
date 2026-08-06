# dream_event_store_gameboy.gd
# Godot version: 4.6
# Ported from gameboy_dream_integration.txt (Godot 3.x).
#
# This is a subclass of DreamEventStore, same pattern the 3.x original
# implied with its `.capture_enhanced_system_snapshot()` / 
# `.replay_single_event_safe()` super-calls -- just made explicit and
# 4.6-correct (`super.method()` instead of leading-dot syntax).
#
# Scope note: this file does NOT touch FileAccess/DirAccess/Time/Thread
# directly, so it doesn't need anything new from DreamPersistenceAdapter.
# It only touches scene-tree/visual APIs (shaders, camera, tweens,
# sprites), which the base DreamEventStore already treats as "left as-is"
# engine references (same tier as DreamStateManager/RealityEngine/etc.),
# not persistence-adapter concerns.
#
# CHANGE LOG (for future you):
#   v1.0 (Godot 3.x) -- gameboy_dream_integration.txt, lost original date
#   v2.0 (Godot 4.6) -- this file. Logic 1:1 ported. EventType additions
#        live in dream_event_store.gd's EventType enum (appended at the
#        end, see that file's change log).

extends DreamEventStore
class_name DreamEventStoreGameBoy

# ---------------------------------------------------------------------
# Game Boy specific state tracking
# ---------------------------------------------------------------------

var gameboy_state := {
	"is_gameboy_mode": false,
	"current_palette": "default",
	"camera_perspective": "topdown",  # "topdown" or "sidescroll"
	"physics_mode": "rpg",            # "rpg" or "platformer"
	"sprite_set": "modern",           # "modern" or "gameboy"
}

# ---------------------------------------------------------------------
# Mode transitions
# ---------------------------------------------------------------------

func enter_gameboy_dream_mode() -> void:
	record_event(EventType.VISUAL_MODE_CHANGED, {
		"old_mode": "modern",
		"new_mode": "gameboy",
		"trigger": "dream_entry",
		"entropy_level": _reality_engine.timeline_entropy,
	}, "visual")

	apply_gameboy_shader()
	record_event(EventType.PALETTE_APPLIED, {
		"palette": "gameboy_green",
		"shader_params": {
			"color_count": 4,
			"green_tint": true,
			"scanlines": true,
		},
	}, "visual")

	shift_camera_to_sidescroll()
	record_event(EventType.CAMERA_PERSPECTIVE_SHIFTED, {
		"old_perspective": "topdown",
		"new_perspective": "sidescroll",
		"rotation": PI / 2,
	}, "camera")

	switch_to_platformer_physics()
	record_event(EventType.PHYSICS_MODE_CHANGED, {
		"old_mode": "rpg",
		"new_mode": "platformer",
		"gravity_change": true,
	}, "physics")

	swap_to_gameboy_sprites()
	record_event(EventType.SPRITE_SET_SWAPPED, {
		"old_set": "modern",
		"new_set": "gameboy",
		"affected_entities": get_all_sprite_entities().size(),
	}, "sprites")

	gameboy_state.is_gameboy_mode = true
	gameboy_state.current_palette = "gameboy_green"
	gameboy_state.camera_perspective = "sidescroll"
	gameboy_state.physics_mode = "platformer"
	gameboy_state.sprite_set = "gameboy"

func exit_gameboy_dream_mode() -> void:
	record_event(EventType.VISUAL_MODE_CHANGED, {
		"old_mode": "gameboy",
		"new_mode": "modern",
		"trigger": "dream_exit",
		"entropy_level": _reality_engine.timeline_entropy,
	}, "visual")

	remove_gameboy_shader()
	record_event(EventType.PALETTE_APPLIED, {
		"palette": "full_color",
		"shader_params": {},
	}, "visual")

	shift_camera_to_topdown()
	record_event(EventType.CAMERA_PERSPECTIVE_SHIFTED, {
		"old_perspective": "sidescroll",
		"new_perspective": "topdown",
		"rotation": -PI / 2,
	}, "camera")

	switch_to_rpg_physics()
	record_event(EventType.PHYSICS_MODE_CHANGED, {
		"old_mode": "platformer",
		"new_mode": "rpg",
		"gravity_change": true,
	}, "physics")

	swap_to_modern_sprites()
	record_event(EventType.SPRITE_SET_SWAPPED, {
		"old_set": "gameboy",
		"new_set": "modern",
		"affected_entities": get_all_sprite_entities().size(),
	}, "sprites")

	gameboy_state.is_gameboy_mode = false
	gameboy_state.current_palette = "default"
	gameboy_state.camera_perspective = "topdown"
	gameboy_state.physics_mode = "rpg"
	gameboy_state.sprite_set = "modern"

# ---------------------------------------------------------------------
# Snapshot/replay overrides
# ---------------------------------------------------------------------

func capture_enhanced_system_snapshot() -> Dictionary:
	var base_snapshot := super.capture_enhanced_system_snapshot()

	base_snapshot["gameboy_state"] = gameboy_state.duplicate(true)
	base_snapshot["visual_state"] = {
		"current_shader": get_current_shader_name(),
		"camera_rotation": get_camera_rotation(),
		"sprite_scale": get_sprite_scale_factor(),
	}

	return base_snapshot

func replay_single_event_safe(event) -> bool:
	# Try the base dispatch table first.
	var success: bool = super.replay_single_event_safe(event)
	if success:
		return true

	# Base only warns+fails on event types it doesn't recognize, so an
	# unhandled Game Boy type lands here rather than being a real error.
	match event.type:
		EventType.VISUAL_MODE_CHANGED:
			success = replay_visual_mode_change(event)
		EventType.CAMERA_PERSPECTIVE_SHIFTED:
			success = replay_camera_shift(event)
		EventType.PALETTE_APPLIED:
			success = replay_palette_change(event)
		EventType.SPRITE_SET_SWAPPED:
			success = replay_sprite_swap(event)
		EventType.PHYSICS_MODE_CHANGED:
			success = replay_physics_mode_change(event)
		_:
			success = false

	return success

func replay_visual_mode_change(event) -> bool:
	var mode_data: Dictionary = event.data

	if mode_data.get("new_mode") == "gameboy":
		if not gameboy_state.is_gameboy_mode:
			apply_gameboy_shader()
			gameboy_state.is_gameboy_mode = true
	elif mode_data.get("new_mode") == "modern":
		if gameboy_state.is_gameboy_mode:
			remove_gameboy_shader()
			gameboy_state.is_gameboy_mode = false

	return true

func replay_camera_shift(event) -> bool:
	var camera_data: Dictionary = event.data

	if camera_data.get("new_perspective") == "sidescroll":
		shift_camera_to_sidescroll()
	elif camera_data.get("new_perspective") == "topdown":
		shift_camera_to_topdown()

	gameboy_state.camera_perspective = camera_data.get("new_perspective", gameboy_state.camera_perspective)
	return true

func replay_palette_change(event) -> bool:
	var palette_data: Dictionary = event.data
	gameboy_state.current_palette = palette_data.get("palette", gameboy_state.current_palette)
	return true

func replay_sprite_swap(event) -> bool:
	var sprite_data: Dictionary = event.data

	if sprite_data.get("new_set") == "gameboy":
		swap_to_gameboy_sprites()
	elif sprite_data.get("new_set") == "modern":
		swap_to_modern_sprites()

	gameboy_state.sprite_set = sprite_data.get("new_set", gameboy_state.sprite_set)
	return true

func replay_physics_mode_change(event) -> bool:
	var physics_data: Dictionary = event.data

	if physics_data.get("new_mode") == "platformer":
		switch_to_platformer_physics()
	elif physics_data.get("new_mode") == "rpg":
		switch_to_rpg_physics()

	gameboy_state.physics_mode = physics_data.get("new_mode", gameboy_state.physics_mode)
	return true

# ---------------------------------------------------------------------
# Visual implementation (scene-tree / shader / camera -- not persistence
# adapter concerns; same tier as the base class's DreamStateManager etc.
# references)
# ---------------------------------------------------------------------

func apply_gameboy_shader() -> void:
	var gameboy_shader := preload("res://shaders/gameboy_dream.tres")
	var screen_overlay := get_node_or_null("/root/Main/ScreenOverlay")

	if screen_overlay:
		screen_overlay.material = gameboy_shader
		screen_overlay.material.set_shader_parameter("palette_colors", [
			Color("#0F380F"),  # Dark green
			Color("#306230"),  # Medium dark green
			Color("#8BAC0F"),  # Medium light green
			Color("#9BBB0F"),  # Light green
		])
		screen_overlay.material.set_shader_parameter("scanline_intensity", 0.1)
		screen_overlay.material.set_shader_parameter("pixel_size", 4.0)

func remove_gameboy_shader() -> void:
	var screen_overlay := get_node_or_null("/root/Main/ScreenOverlay")
	if screen_overlay:
		screen_overlay.material = null

func shift_camera_to_sidescroll() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera:
		var tween := create_tween()
		tween.tween_property(camera, "rotation", PI / 2, 0.5)
		tween.tween_callback(update_camera_constraints_sidescroll)

func shift_camera_to_topdown() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera:
		var tween := create_tween()
		tween.tween_property(camera, "rotation", 0.0, 0.5)
		tween.tween_callback(update_camera_constraints_topdown)

func update_camera_constraints_sidescroll() -> void:
	pass  # Hook point -- preserved from original, no body was specified.

func update_camera_constraints_topdown() -> void:
	pass  # Hook point -- preserved from original, no body was specified.

func switch_to_platformer_physics() -> void:
	_physics_stack.apply_physics_mod("gameboy_platformer", {
		"gravity": 980.0,
		"collision_layers": 0b00000011,
		"jump_enabled": true,
	})

func switch_to_rpg_physics() -> void:
	_physics_stack.revert_physics_mod("gameboy_platformer")

func swap_to_gameboy_sprites() -> void:
	for entity in get_all_sprite_entities():
		if entity.has_method("set_sprite_set"):
			entity.set_sprite_set("gameboy")
		if entity.has_method("set_pixel_scale"):
			entity.set_pixel_scale(4)

func swap_to_modern_sprites() -> void:
	for entity in get_all_sprite_entities():
		if entity.has_method("set_sprite_set"):
			entity.set_sprite_set("modern")
		if entity.has_method("set_pixel_scale"):
			entity.set_pixel_scale(1)

func get_all_sprite_entities() -> Array:
	var entities: Array = []
	entities.append_array(get_tree().get_nodes_in_group("player"))
	entities.append_array(get_tree().get_nodes_in_group("npcs"))
	entities.append_array(get_tree().get_nodes_in_group("dream_npcs"))
	entities.append_array(get_tree().get_nodes_in_group("environment_objects"))
	return entities

func get_current_shader_name() -> String:
	var screen_overlay := get_node_or_null("/root/Main/ScreenOverlay")
	if screen_overlay and screen_overlay.material:
		return screen_overlay.material.resource_path
	return ""

func get_camera_rotation() -> float:
	var camera := get_viewport().get_camera_2d()
	return camera.rotation if camera else 0.0

func get_sprite_scale_factor() -> int:
	return 4 if gameboy_state.sprite_set == "gameboy" else 1

# ---------------------------------------------------------------------
# Corruption handling
# ---------------------------------------------------------------------

func handle_gameboy_corruption(corruption_level: float) -> void:
	record_event(EventType.CORRUPTION_DETECTED, {
		"corruption_type": "gameboy_visual",
		"corruption_level": corruption_level,
		"visual_mode": "gameboy",
	}, "corruption")

	if corruption_level > 0.5:
		apply_corrupted_gameboy_palette()
		apply_sprite_corruption(corruption_level)
		increase_scanline_intensity(corruption_level)

func apply_corrupted_gameboy_palette() -> void:
	var screen_overlay := get_node_or_null("/root/Main/ScreenOverlay")
	if screen_overlay and screen_overlay.material:
		screen_overlay.material.set_shader_parameter("palette_colors", [
			Color("#2C1810"),  # Dark brown
			Color("#8B4513"),  # Brown
			Color("#FF6B47"),  # Corrupt red-orange
			Color("#FFE4E1"),  # Light corrupt pink
		])

func apply_sprite_corruption(corruption_level: float) -> void:
	for entity in get_all_sprite_entities():
		if entity.has_method("apply_pixel_corruption"):
			entity.apply_pixel_corruption(corruption_level)

func increase_scanline_intensity(corruption_level: float) -> void:
	var screen_overlay := get_node_or_null("/root/Main/ScreenOverlay")
	if screen_overlay and screen_overlay.material:
		screen_overlay.material.set_shader_parameter("scanline_intensity", 0.1 + corruption_level * 0.4)

# ---------------------------------------------------------------------
# Asset manifest
# ---------------------------------------------------------------------

func get_required_gameboy_assets() -> Dictionary:
	return {
		"shaders": [
			"gameboy_dream.tres",
			"gameboy_corruption.tres",
		],
		"sprites": {
			"player": [
				"player_gameboy_idle.png",
				"player_gameboy_walk.png",
				"player_gameboy_jump.png",
			],
			"npcs": [
				"npc_gameboy_base.png",
				"shadow_npc_gameboy_low_corruption.png",
				"shadow_npc_gameboy_high_corruption.png",
			],
		},
		"ui": [
			"gameboy_ui_frame.png",
			"gameboy_text_box.png",
		],
	}
