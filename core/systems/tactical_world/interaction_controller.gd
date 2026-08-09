# interaction_controller.gd
# Godot version: 4.6
#
# Owns the entire interaction presentation and session lifecycle.
# Interactable/Chest/Plant scripts still don't need to know pausing
# exists at all. This controller does NOT decide get_tree().paused
# anymore, though -- it's one REQUESTER among potentially several
# (a cutscene, a menu, ...), not the authority. It asks
# GameStateManager (core/systems/game_state/game_state_manager.gd, an
# autoload) to pause on interaction start and releases its own request
# on interaction end/cancel; GameStateManager is the only thing that
# ever writes get_tree().paused, and only resumes once EVERY active
# request -- from every system, not just this one -- has been released.
#
# Per frame (while NOT interacting), scans every node in the
# "interactable" group and puts each one's label into exactly one of
# three states based on distance and line of sight:
#
#   > viewing_range_steps away, OR no line of sight  -> hidden
#   <= viewing_range_steps away (Euclidean, in navigation
#      STEPS -- player.step_distance units)          -> name only
#   in the CARDINALLY ADJACENT GridMap cell
#      (Manhattan == 1 in CELL units)                -> name + action
#
# Viewing range is measured in steps (finer-grained, matches how far you
# can actually see); interaction range is measured in CELLS, not steps.
# That's not an arbitrary choice: solid Interactables (see
# Interactable.blocks_movement / occupies_full_cell) occupy their whole
# cell as non-passable space by default, so the closest the player can
# ever actually stand next to one is the adjacent cell -- which is 2
# steps away at the current step_distance=0.5/cell_size=1.0 tuning, not
# 1. Checking cell-adjacency directly (rather than hardcoding "2 steps")
# keeps this correct automatically if that ratio ever changes.
#
# Manhattan distance == 1 is diagonal-proof on its own: a diagonal
# neighbor is dx=1,dz=1 (or similar), which sums to 2, never 1 -- so no
# separate cardinal-vs-diagonal check is needed beyond that formula.
#
# This node is process_mode ALWAYS so it keeps running (to read
# confirm/cancel input and drive the interaction panel) even after its
# own pause REQUEST takes effect. Everything else in the scene (player,
# camera, GridMap, NPCs) is left at the Godot default
# (PROCESS_MODE_PAUSABLE / INHERIT), which is what actually stops them
# when GameStateManager sets get_tree().paused true -- no per-script
# pause checks scattered elsewhere.
#
# MULTI-TYPE TARGETS (Interactable.interaction_flags with more than one
# bit set -- a Merchant with both TALK and OPEN, say): the world-space
# label above the object still only ever shows ONE action (its
# primary_interaction_type()), same as a single-type object -- the
# floating nameplate has no room to list several verbs and doesn't try.
# The DIFFERENCE surfaces once an interaction session actually begins:
# begin_interaction() reads every OTHER active type off the target
# (Interactable.active_interaction_types(), minus the primary) into
# _current_secondary_types, and the confirm panel lists one extra line
# per secondary action, numbered 1-9 -- the same numbered-key vocabulary
# the hotbar already uses. F still always confirms the primary action,
# unchanged from a single-type target's behavior; a secondary action
# needs its number pressed explicitly. A target with zero secondary
# types (every existing single-type object) gets exactly the
# `[F] Verb  [Esc] Cancel` panel this always showed.

extends Node
class_name InteractionController

@export var player: GridActor
@export var grid_map: GridMap
## Which GridMap item ids block line of sight. GridActor no longer
## reads the GridMap for movement blocking at all (obstruction is a
## native physics query now -- see grid_actor.gd's file header), so this
## is independent, scene-authored data, not something read off `player`
## anymore; whoever wires this controller up (tactical_demo_world.gd)
## is responsible for keeping it in sync with whatever id its own wall
## cells actually use.
@export var wall_item_ids: PackedInt32Array = [1]
## Where walls live relative to the layer this LOS check samples, in
## GridMap cell units -- e.g. Vector3i(0, 1, 0) if walls are painted on
## a different GridMap y-layer than the floor. Left at zero (the
## default), walls are assumed to occupy the same layer LOS sampling
## already looks at. Formerly read from GridActor.wall_layer_offset
## (removed along with GridActor's whole GridMap-based obstruction
## path); relocated here since LOS sampling is now the only remaining
## GridMap-cell consumer in this framework.
@export var wall_layer_offset: Vector3i = Vector3i.ZERO

@export var viewing_range_steps := 10.0
@export var interact_key: Key = KEY_F
@export var cancel_key: Key = KEY_ESCAPE

## By default the camera pauses along with everything else (it's left
## at the Godot default process mode, same as the player). Set this
## true to explicitly opt the camera BACK into moving during an
## interaction -- "explicitly allowed," not the default.
@export var allow_camera_during_interaction := false
@export var camera_rig: TacticalCameraRig

var is_interacting := false

var _current_target: Interactable
var _current_source: Node
var _nearest_valid_target: Interactable
## Every active InteractionType on _current_target OTHER than the one
## the panel's [F] line already covers -- see the file header's
## "MULTI-TYPE TARGETS" note. Populated in begin_interaction(), cleared
## in end_interaction(); index i here is what key (i+1) confirms.
var _current_secondary_types: Array[Interactable.InteractionType] = []
var _panel: CanvasLayer
var _panel_name_label: Label
var _panel_hint_label: Label
var _camera_process_mode_before: int


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_panel()


func _process(_delta: float) -> void:
	if is_interacting:
		return  # frozen on purpose -- see file header
	if get_tree().paused:
		# Paused for a reason that ISN'T this controller's own interaction
		# session (is_interacting already handled that case above) --
		# another PROCESS_MODE_ALWAYS system (a LootWindow/ShopWindow, see
		# toggle_list_window.gd's file header) has focus right now. Don't
		# keep rescanning for/highlighting a nearest target while that has
		# the player's actual attention.
		return
	if player == null:
		return
	_nearest_valid_target = null
	for node in get_tree().get_nodes_in_group(Interactable.INTERACTABLE_GROUP):
		var interactable := node as Interactable
		if interactable == null:
			continue
		_update_label(interactable)


func _update_label(interactable: Interactable) -> void:
	if interactable.is_hidden:
		interactable.label.set_hidden()
		return

	var delta := interactable.global_position - player.global_position
	var step := maxf(player.step_distance, 0.0001)
	var step_dx := roundi(delta.x / step)
	var step_dz := roundi(delta.z / step)

	var euclidean := sqrt(float(step_dx * step_dx + step_dz * step_dz))
	if euclidean > viewing_range_steps:
		interactable.label.set_hidden()
		return

	if not _has_line_of_sight(player.global_position, interactable.global_position):
		interactable.label.set_hidden()
		return

	# Interaction range is cell-adjacency, not step-adjacency -- see the
	# file header for why. player.cell_size is assumed to match this
	# object's GridMap footprint on X/Z (Y is irrelevant here).
	var cell_x := maxf(player.cell_size.x, 0.0001)
	var cell_z := maxf(player.cell_size.z, 0.0001)
	var cell_dx := roundi(delta.x / cell_x)
	var cell_dz := roundi(delta.z / cell_z)
	var cell_manhattan := absi(cell_dx) + absi(cell_dz)

	if cell_manhattan == 1:
		var primary := interactable.primary_interaction_type()
		interactable.label.show_action(interactable.display_name, interactable.prompt_for(primary), OS.get_keycode_string(interact_key))
		if _nearest_valid_target == null:
			_nearest_valid_target = interactable
	else:
		interactable.label.show_name(interactable.display_name)


func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	if grid_map == null:
		return true
	var total_distance := from.distance_to(to)
	if total_distance < 0.001:
		return true
	# Fine enough to never skip over a full grid cell of wall (cells are
	# at least 1 unit thick in every layout this framework builds so far).
	var sample_count := maxi(4, int(ceil(total_distance / 0.1)))
	for i in range(1, sample_count):
		var t := float(i) / float(sample_count)
		var point := from.lerp(to, t)
		# Y pinned to the player's own ground level, deliberately, BEFORE
		# the cell lookup -- confirmed empirically (not assumed) that
		# leaving it interpolated toward an elevated interactable (chests
		# / plants sit at y=0.3-0.35, not y=0) is a real bug: cell_size.y
		# is razor-thin (0.1, so every ~0.05m of Y drift rounds to a
		# DIFFERENT y-cell), so by the time the sampled point's Z reaches
		# a wall's actual row, its interpolated Y has usually already
		# rounded away from y-index 0 -- the ONLY layer walls are ever
		# placed on -- and the wall is silently missed. Walls live on a
		# single known layer regardless of the target's height; LOS is a
		# floor-plan (X/Z) question, the same "X/Z only, deliberately"
		# reasoning Interactable's own occupies_full_cell collision (see
		# interactable.gd's _build_collision_body()) uses for the
		# identical underlying cause.
		point.y = from.y
		# player.world_to_cell(), NOT grid_map.local_to_map() -- confirmed
		# empirically (raycast against the wall's real collision shape) that
		# local_to_map() does NOT respect this project's
		# cell_center_x/y/z = false setting: it stays floor-based
		# regardless, disagreeing with where a wall ACTUALLY, physically
		# sits by up to half a cell. GridActor no longer uses cell lookups
		# for movement blocking at all (see its file header -- obstruction
		# is a native physics query now), but world_to_cell() is still the
		# one geometry-correct GridMap<->world mapping this project trusts,
		# so LOS keeps using it rather than reintroducing local_to_map()'s
		# disagreement. This GridMap sits at an identity transform (no
		# to_local() conversion), not a new gap introduced here.
		var cell := player.world_to_cell(point)
		var check_cell := cell + wall_layer_offset
		var item := grid_map.get_cell_item(check_cell)
		if item != GridMap.INVALID_CELL_ITEM and wall_item_ids.has(item):
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# Same reasoning as the identical check in _process() above -- not
	# repeated here as a call to a shared helper only because a guard
	# clause reads more plainly than threading a bool through two
	# differently-shaped functions for one condition.
	if not is_interacting and get_tree().paused:
		return
	var key_event := event as InputEventKey

	if key_event.keycode == interact_key:
		if is_interacting:
			_confirm_interaction()
		elif _nearest_valid_target:
			begin_interaction(player, _nearest_valid_target)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == cancel_key and is_interacting:
		cancel_interaction()
		get_viewport().set_input_as_handled()
	elif is_interacting:
		# Secondary actions on a multi-type target -- see the file
		# header's "MULTI-TYPE TARGETS" note. A single-type target's
		# _current_secondary_types is always empty, so this branch is a
		# no-op for every interaction this framework had before
		# interaction_flags existed.
		var index := _secondary_action_index_for_keycode(key_event.keycode)
		if index != -1:
			_confirm_secondary_action(index)
			get_viewport().set_input_as_handled()


## KEY_1..KEY_9 -> index 0..8, matching the numbering _show_panel()
## prints ("[1] Open Satchel" confirms index 0). Anything else, or an
## index beyond however many secondary actions the current target
## actually has, returns -1 -- _confirm_secondary_action() itself also
## bounds-checks, so this is a convenience, not the only guard.
func _secondary_action_index_for_keycode(keycode: Key) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	return -1


## Called by (or on behalf of) the player. Does nothing if an
## interaction is already in progress -- only one session at a time.
func begin_interaction(source: Node, target: Interactable) -> void:
	if is_interacting or target == null:
		return

	is_interacting = true
	_current_target = target
	_current_source = source

	# Every active type on `target` except the one the panel's [F] line
	# already covers -- see the file header's "MULTI-TYPE TARGETS" note.
	# Always empty for a single-type target (active_interaction_types()
	# returns exactly one entry, which IS the primary).
	var primary := target.primary_interaction_type()
	_current_secondary_types.clear()
	for type in target.active_interaction_types():
		if type != primary:
			_current_secondary_types.append(type)

	# Turn to face what's being interacted with, even though no step is
	# being taken to reach it -- real, reported problem: walk up to a
	# wall, stop, interact with something off to the side, and the
	# character kept staring at the wall the whole time since nothing
	# about interacting ever touched facing before. `source` is typed
	# as plain Node (not GridActor) since in principle anything could
	# initiate an interaction; only turn it if it actually has a
	# facing to turn.
	var actor := source as GridActor
	if actor:
		actor.face_direction(actor.snap_to_grid_direction(target.global_position - actor.global_position))

	if camera_rig and not allow_camera_during_interaction:
		_camera_process_mode_before = camera_rig.process_mode
		camera_rig.process_mode = Node.PROCESS_MODE_PAUSABLE

	# NOT get_tree().paused = true anymore -- this controller no longer
	# OWNS pause, it only ever REQUESTS it. See
	# core/systems/game_state/game_state_manager.gd's file header for
	# why a plain boolean breaks once a second system (a cutscene, a
	# menu) can also need the world paused at the same time: whichever
	# one finishes first would unpause the other out from under it.
	# GameStateManager decides get_tree().paused; this is the only
	# thing this controller is allowed to do about it -- ask.
	GameStateManager.request_pause(self, &"interaction")
	_show_panel(target)


## Completes the interaction: runs the target's PRIMARY effect (opens
## the chest, harvests the plant, talks to the merchant, ...), then
## resumes the world. Distinct from cancel_interaction(), which resumes
## WITHOUT running any effect. For a secondary action on a multi-type
## target, see _confirm_secondary_action() instead.
func _confirm_interaction() -> void:
	if not is_interacting:
		return
	var target := _current_target
	var source := _current_source
	end_interaction()
	if target:
		target.interact(source)


## Completes the interaction by running one of the target's SECONDARY
## effects instead of its primary one -- see the file header's
## "MULTI-TYPE TARGETS" note. `index` is into _current_secondary_types
## as it stood when the panel was built; out-of-range (a stale number
## key press after the target's flags somehow changed mid-session, or
## just a number with nothing behind it) is a documented no-op, same as
## Interactable.interact() itself no-op'ing on a type that isn't active.
func _confirm_secondary_action(index: int) -> void:
	if not is_interacting or index < 0 or index >= _current_secondary_types.size():
		return
	var target := _current_target
	var source := _current_source
	var type := _current_secondary_types[index]
	end_interaction()
	if target:
		target.interact(source, type)


## Resumes world simulation without performing the target's action.
func cancel_interaction() -> void:
	if not is_interacting:
		return
	end_interaction()


## Shared resume logic. Safe to call directly if you just need to force
## a resume (e.g. the target was freed mid-interaction) without going
## through confirm/cancel semantics.
func end_interaction() -> void:
	is_interacting = false
	_current_target = null
	_current_source = null
	_current_secondary_types.clear()
	# Releases ONLY this controller's own request -- if some other
	# system also has an active pause request right now, the tree stays
	# paused, correctly, until that other request is released too. This
	# controller has no way to force an unpause and isn't supposed to.
	GameStateManager.release_pause(self, &"interaction")
	_hide_panel()
	if camera_rig and not allow_camera_during_interaction:
		camera_rig.process_mode = _camera_process_mode_before


func _build_panel() -> void:
	_panel = CanvasLayer.new()
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.layer = 10
	add_child(_panel)

	var box := PanelContainer.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -160
	box.offset_right = 160
	# Bottom edge pinned 100px above the screen bottom; top edge left to
	# the container's own minimum size and grows UPWARD from there
	# (GROW_DIRECTION_BEGIN) instead of a hand-picked fixed height. A
	# fixed-height box (the previous approach: offset_top=-170,
	# offset_bottom=-100, always exactly 70px) was fine for the single
	# "[F] Verb  [Esc] Cancel" line every target used to show, but a
	# multi-type target's hint label (see _show_panel() below) can now
	# be several lines tall -- sizing to content is what keeps that from
	# silently overflowing a box that was never resized to fit it.
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_top = -100
	box.offset_bottom = -100
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.add_child(box)

	var vbox := VBoxContainer.new()
	vbox.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_child(vbox)

	_panel_name_label = Label.new()
	_panel_name_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_panel_name_label)

	_panel_hint_label = Label.new()
	_panel_hint_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_panel_hint_label)

	_panel.visible = false


## _current_secondary_types must already be populated (begin_interaction()
## does this before calling here) -- one hint line for the primary
## action, one more per secondary action (numbered 1-9, matching
## _secondary_action_index_for_keycode()), then Cancel last. A
## single-type target (the common case, unchanged from before
## interaction_flags existed) always has zero secondary lines, so this
## produces exactly the old two-part "[F] Verb    [Esc] Cancel" text.
func _show_panel(target: Interactable) -> void:
	_panel_name_label.text = target.display_name

	var lines := PackedStringArray()
	lines.append("[%s] %s" % [OS.get_keycode_string(interact_key), target.prompt_for(target.primary_interaction_type())])
	for i in range(_current_secondary_types.size()):
		lines.append("[%d] %s" % [i + 1, target.prompt_for(_current_secondary_types[i])])
	lines.append("[%s] Cancel" % OS.get_keycode_string(cancel_key))
	_panel_hint_label.text = "\n".join(lines)

	_panel.visible = true


func _hide_panel() -> void:
	_panel.visible = false
