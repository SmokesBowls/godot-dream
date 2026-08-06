# tactical_demo_world.gd
# Godot version: 4.6
#
# Wires the demo scene together at runtime rather than hand-baking every
# GridMap cell into the .tscn: paints a small floor with a broken
# perimeter wall (so there's at least one "ruined wall you can pass
# through" gap, per the brief) using the placeholder MeshLibrary from
# demo_mesh_library.gd, and points the camera rig at the player. Replace
# the procedural layout with a real hand-placed level once there's
# actual level content -- this exists to prove the pieces connect, not
# as a leveling tool.
#
# Floor and walls share a single, thin grid layer (y=0) -- see
# demo_mesh_library.gd's doc comment for why: a thick per-axis
# cell_size.y used to make every floor cell "own" a tall volume that
# silently hid nearby ground-level props (the chest, the plant) even
# though they visually cleared the floor. Walls get their visual height
# from the mesh_library item's own transform now, not from stacking a
# second GridMap layer.

extends Node3D

## Scaled up from 5 when cell_size dropped from 2.0m to 1.0m, so the
## playable area stays roughly the same physical size (~20m across)
## instead of shrinking to a quarter of it. The chest/plant world
## positions are absolute meters, unaffected by this or cell_size.
@export var half_extent := 10
## Kept thin on Y so each cell's occlusion footprint matches what's
## actually drawn there (see the root-cause note above) -- do not grow
## this back to a cube without re-checking nearby props still render.
@export var cell_size := Vector3(1.0, 0.1, 1.0)
@export var wall_height := 2.0

## One key press covers this many meters. Deliberately smaller than
## cell_size.x/z (1.0m) -- two presses per tactical grid cell, finer
## movement resolution without changing the grid walls/props align to.
## See grid_actor.gd's header comment for why these two are decoupled.
@export var player_step_distance := 0.5

## Width of each perimeter gap, in whole GridMap cells (not steps). A
## width-1 gap is exactly one cell wide -- with cell_size at 1.0m and a
## ~0.8m-diameter player capsule, that's only enough room to stand dead
## center; stepping half a cell either way rounds into the flanking wall
## cells and gets rejected, so there's no side-to-side room at all.
## Width 3 (an odd number splits evenly around the wall's cell-0
## midpoint -- see _gap_range()) gives one full step of room on BOTH
## sides of center: stand in the middle, or shuffle one step left or
## one step right and back, matching a normal doorway instead of a
## slot exactly your width.
@export var gap_width_cells := 3

## Debug-only: shows the player's collision capsule alongside the sprite
## for scale/collision inspection. The capsule mesh node and its
## CollisionShape3D are never removed by the sprite work -- collision
## stays authoritative regardless of this flag; this only affects the
## capsule MESH's visibility.
@export var show_player_capsule_debug := false

@onready var _grid_map: GridMap = $GridMap
@onready var _camera_rig: TacticalCameraRig = $TacticalCameraRig
@onready var _player: GridActor = $Player
@onready var _interaction_controller: InteractionController = $InteractionController
@onready var _player_capsule_mesh: MeshInstance3D = $Player/MeshInstance3D
@onready var _player_sprite_actor: SpriteActor = $Player/VisualRoot/SpriteActor
@onready var _player_ground_shadow: GroundShadow = $Player/VisualRoot/GroundShadow
@onready var _player_input: GridActorPlayerInput = $Player/PlayerInput
@onready var _camera_mode_controller: CameraModeController = $CameraModeController
## TEMPORARY -- see debug_grid_overlay.gd's file header. Remove this
## node and the export below together when the two-lattice question
## it's answering is settled.
@onready var _debug_grid_overlay: DebugGridOverlay = $DebugGridOverlay


func _ready() -> void:
	_grid_map.cell_size = cell_size
	# GridMap centers cells with a +0.5*cell_size offset on every axis by
	# default (cell_center_x/y/z default true) -- e.g. cell (5,0,-1) sits
	# at world (11.0, 0.1, -1.0), not (10.0, 0.0, -2.0). GridActor's
	# cell_to_world()/world_to_cell(), and every hand-placed world
	# position in this scene (the chest, the plant), assume the plain
	# index*cell_size convention with no offset. Left as defaults, the
	# player's walk grid, the wall's true visual position, and the
	# props' placement are all on DIFFERENT grids, offset by half a cell
	# diagonally from each other -- which is exactly the "half a space
	# offset diagonally" misalignment that showed up as the player
	# looking wrong relative to the wall. Disabling centering makes
	# GridMap match the convention everything else already uses, instead
	# of changing that convention everywhere else to match GridMap.
	_grid_map.cell_center_x = false
	_grid_map.cell_center_y = false
	_grid_map.cell_center_z = false
	_grid_map.mesh_library = DemoMeshLibrary.build(cell_size, wall_height)
	_paint_floor_and_walls()
	_camera_rig.target = _player

	# Walls now live on the SAME grid layer the player walks on (y=0),
	# distinguished from floor only by item id -- no cross-layer offset
	# needed, so this is the trivial same-cell case wall_layer_offset
	# defaults to. Floor (item 0) and walls (item 1) share that layer,
	# so obstacle_item_ids has to name the wall id explicitly -- without
	# it, GridActor's default "any non-empty cell blocks" rule would
	# treat every floor tile as a wall too and reject all movement.
	_player.obstruction_map = _grid_map
	_player.obstacle_item_ids = PackedInt32Array([1])
	# cell_size stays in sync with the GridMap's own for obstruction
	# lookups; step_distance is the separate, finer movement-resolution
	# value -- see grid_actor.gd's header comment.
	_player.cell_size = cell_size
	_player.step_distance = player_step_distance
	# Camera-relative input resolution -- see grid_actor_player_input.gd's
	# header for why "Up" has to mean "away from wherever the camera is
	# CURRENTLY looking," not a fixed world axis, once the camera can
	# orbit (Q/E).
	_player_input.camera_rig = _camera_rig

	# InteractionController does its own line-of-sight checks against the
	# same GridMap/wall-id data GridActor uses for movement blocking, so
	# "can I see it" and "can I walk into it" agree with each other.
	_interaction_controller.player = _player
	_interaction_controller.grid_map = _grid_map
	_interaction_controller.wall_item_ids = _player.obstacle_item_ids
	_interaction_controller.camera_rig = _camera_rig

	# SpriteActor/GroundShadow are presentation only -- they read the
	# player's facing/position and the camera's orientation, but never
	# write back to movement, collision, or input. Collision stays on
	# CollisionShape3D regardless of what's visible.
	_player_sprite_actor.actor = _player
	_player_sprite_actor.camera_rig = _camera_rig
	_player_ground_shadow.actor = _player
	_player_capsule_mesh.visible = show_player_capsule_debug

	# F1/F2/F3 camera modes -- see camera_mode_controller.gd for why not
	# literal "1"/"2"/"3" (those are the hotbar slots).
	_camera_mode_controller.camera_rig = _camera_rig
	_camera_mode_controller.player = _player

	# TEMPORARY debug visualization -- see debug_grid_overlay.gd.
	_debug_grid_overlay.player = _player
	_debug_grid_overlay.half_extent = half_extent


func _paint_floor_and_walls() -> void:
	for x in range(-half_extent, half_extent + 1):
		for z in range(-half_extent, half_extent + 1):
			var on_perimeter := x == -half_extent or x == half_extent or z == -half_extent or z == half_extent
			if on_perimeter and not _is_gap(x, z):
				_grid_map.set_cell_item(Vector3i(x, 0, z), 1)  # wall
			else:
				_grid_map.set_cell_item(Vector3i(x, 0, z), 0)  # floor


func _is_gap(x: int, z: int) -> bool:
	# One deliberate gap per side, centered on the midpoint -- a "ruined
	# wall" you can walk through rather than a sealed box.
	return _in_gap_range(x) or _in_gap_range(z)


func _gap_range() -> Vector2i:
	# gap_width_cells consecutive integer cell indices, centered as
	# evenly as possible on 0. Integer division: width 1 -> [0,0] (the
	# original single-cell gap); width 2 -> [-1,0]; width 3 -> [-1,1].
	var lo := -(gap_width_cells / 2)
	var hi := lo + gap_width_cells - 1
	return Vector2i(lo, hi)


func _in_gap_range(v: int) -> bool:
	var range := _gap_range()
	return v >= range.x and v <= range.y
