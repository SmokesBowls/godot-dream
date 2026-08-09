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

## The MeshLibrary item id (see demo_mesh_library.gd) that means "wall."
## The single source every wall-related piece of this file reads --
## _paint_floor_and_walls() (the visual GridMap), _build_wall_collision()
## (the real physics obstruction bodies), and the InteractionController
## wiring below (line-of-sight sampling) all read this constant instead
## of each hand-maintaining their own copy of the number 1.
const WALL_ITEM_ID := 1

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

## Where the jump-test platform (see _build_jump_test_platform()) sits.
## Deliberately off BOTH axes running through the origin -- x=0 and z=0
## are the cardinal rays the player naturally walks testing movement
## (and what several scratchpad regression tests hold-walk along, per
## README item 36's Apple-placement note) -- same corner-placement
## convention Chest (4,4) and Plant (-4,-4) already use, just in the
## other two quadrants so it doesn't crowd either.
@export var jump_test_platform_position := Vector3(6, 0, -6)
## Tall enough to read clearly as a height cue against the flat floor,
## short enough that the sprite's jump arc (see sprite_actor.gd) still
## visibly clears it rather than looking like it should be climbable.
@export var jump_test_platform_height := 0.7

@onready var _grid_map: GridMap = $GridMap
@onready var _camera_rig: TacticalCameraRig = $TacticalCameraRig
@onready var _player: GridActor = $Player
@onready var _interaction_controller: InteractionController = $InteractionController
@onready var _player_capsule_mesh: MeshInstance3D = $Player/MeshInstance3D
@onready var _player_sprite_actor: SpriteActor = $Player/VisualRoot/SpriteActor
@onready var _player_ground_shadow: GroundShadow = $Player/VisualRoot/GroundShadow
@onready var _player_input: GridActorPlayerInput = $Player/PlayerInput
@onready var _player_inventory: Inventory = $Player/Inventory
@onready var _follower: GridActor = $Follower
@onready var _follower_ai: Follower = $Follower/FollowerAI
@onready var _follower_sprite_actor: SpriteActor = $Follower/VisualRoot/SpriteActor
@onready var _follower_ground_shadow: GroundShadow = $Follower/VisualRoot/GroundShadow
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
	_build_wall_collision()
	_camera_rig.target = _player

	# cell_size stays in sync with the GridMap's own for callers that
	# still want cell units (InteractionController's cell-adjacency
	# check, current_cell()); step_distance is the separate, finer
	# movement-resolution value -- see grid_actor.gd's header comment.
	# Obstruction itself no longer reads the GridMap at all -- see
	# _build_wall_collision() below.
	_player.cell_size = cell_size
	_player.step_distance = player_step_distance
	# Camera-relative input resolution -- see grid_actor_player_input.gd's
	# header for why "Up" has to mean "away from wherever the camera is
	# CURRENTLY looking," not a fixed world axis, once the camera can
	# orbit (Q/E).
	_player_input.camera_rig = _camera_rig

	# InteractionController does its own GridMap-cell line-of-sight
	# sampling -- a genuinely different problem than movement obstruction
	# (a ray needs to know "is there a wall roughly along this line," not
	# "does my exact body fit at this exact point"), so it still reads
	# the GridMap's wall item id directly rather than going through a
	# physics query itself. WALL_ITEM_ID is the single source both this
	# wiring and _paint_floor_and_walls()/_build_wall_collision() read,
	# so all three can never silently disagree about which id means wall.
	_interaction_controller.player = _player
	_interaction_controller.grid_map = _grid_map
	_interaction_controller.wall_item_ids = PackedInt32Array([WALL_ITEM_ID])
	# Never set explicitly here: walls and floor share the same GridMap
	# y-layer in this scene, so InteractionController.wall_layer_offset
	# stays at its own default (Vector3i.ZERO) -- see that export's doc
	# comment on InteractionController for the cross-layer case.
	_interaction_controller.camera_rig = _camera_rig

	# SpriteActor/GroundShadow are presentation only -- they read the
	# player's facing/position and the camera's orientation, but never
	# write back to movement, collision, or input. Collision stays on
	# CollisionShape3D regardless of what's visible.
	_player_sprite_actor.actor = _player
	_player_sprite_actor.camera_rig = _camera_rig
	_player_ground_shadow.actor = _player
	_player_capsule_mesh.visible = show_player_capsule_debug

	# Follower -- trailing-step companion (see follower.gd's file header):
	# replays the PLAYER's own step history a few steps behind rather
	# than pathing toward the player's current position, so it never
	# has to reason about obstacles itself. Same cell_size/step_distance
	# as the player -- they're walking the same grid.
	_follower.cell_size = cell_size
	_follower.step_distance = player_step_distance
	_follower_ai.leader = _player
	_follower_sprite_actor.actor = _follower
	_follower_sprite_actor.camera_rig = _camera_rig
	_follower_ground_shadow.actor = _follower

	# F1/F2/F3 camera modes -- see camera_mode_controller.gd for why not
	# literal "1"/"2"/"3" (those are the hotbar slots).
	_camera_mode_controller.camera_rig = _camera_rig
	_camera_mode_controller.player = _player

	# TEMPORARY debug visualization -- see debug_grid_overlay.gd.
	_debug_grid_overlay.player = _player
	_debug_grid_overlay.half_extent = half_extent

	# Inventory HUD -- presentation only, reads Player/Inventory (see
	# inventory.gd) via its own `changed` signal; never writes back to it.
	var inventory_hud := InventoryHud.new()
	add_child(inventory_hud)
	inventory_hud.inventory = _player_inventory

	_build_jump_test_platform()


func _paint_floor_and_walls() -> void:
	for x in range(-half_extent, half_extent + 1):
		for z in range(-half_extent, half_extent + 1):
			var on_perimeter := x == -half_extent or x == half_extent or z == -half_extent or z == half_extent
			if on_perimeter and not _is_gap(x, z):
				_grid_map.set_cell_item(Vector3i(x, 0, z), WALL_ITEM_ID)
			else:
				_grid_map.set_cell_item(Vector3i(x, 0, z), 0)  # floor


## Builds GridActor's real movement-obstruction geometry for every wall
## cell just painted above: one StaticBody3D + BoxShape3D per cell, on
## GridActor.WALL_COLLISION_LAYER_BIT, sized to the cell's real footprint
## and standing from the floor up to wall_height (matching the visual
## wall exactly -- see demo_mesh_library.gd's own wall mesh transform).
##
## WHY THIS EXISTS SEPARATELY FROM THE GRIDMAP'S OWN COLLISION SHAPES
## (demo_mesh_library.gd already registers physics shapes for both the
## floor and wall items, for ground_shadow.gd's downward raycast):
## GridMap's collision_layer/collision_mask are ONE property of the
## whole node, shared by every item it places -- there is no per-item
## way to put walls on the obstruction layer without also putting the
## paper-thin floor cells on it. A movement probe resting exactly at
## ground level would then sit right at the floor collision box's own
## top surface (cell_size.y=0.1, so roughly y=+0.05) -- close enough to
## the default physics contact margin that "am I touching the ground"
## and "is the ground blocking me" could get confused, exactly the kind
## of geometry-precision landmine this project's collision history
## (README items 22-36) is full of. Building independent, wall-only
## bodies sidesteps the whole question: the GridMap's own collision
## shapes stay exactly as they were (floor + wall, default layer, used
## only for the ground-shadow raycast); these new bodies are the ONLY
## thing on the obstruction layer, and they only ever exist where a wall
## visually is.
func _build_wall_collision() -> void:
	var container := Node3D.new()
	container.name = "WallCollision"
	add_child(container)

	var wall_layer := 1 << (GridActor.WALL_COLLISION_LAYER_BIT - 1)
	for x in range(-half_extent, half_extent + 1):
		for z in range(-half_extent, half_extent + 1):
			if _grid_map.get_cell_item(Vector3i(x, 0, z)) != WALL_ITEM_ID:
				continue
			var body := StaticBody3D.new()
			body.collision_layer = wall_layer
			body.collision_mask = 0
			# GridMap places a cell's own origin at index*cell_size (see
			# cell_center_x/y/z = false above) -- the wall mesh itself is
			# then shifted up by wall_height*0.5 (demo_mesh_library.gd's
			# set_item_mesh_transform) so its bottom face sits on the
			# floor. Matched here so the collision volume lines up with
			# the visual mesh exactly, not just the cell's footprint.
			body.position = Vector3(x * cell_size.x, wall_height * 0.5, z * cell_size.z)
			container.add_child(body)

			var shape_node := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(cell_size.x, wall_height, cell_size.z)
			shape_node.shape = box
			body.add_child(shape_node)


## "A platform to test the jump" -- jump (sprite_actor.gd, README item
## 35) still plays a purely cosmetic Sprite3D-local Y arc, unchanged, but
## GridActor now ALSO has a real, bounded step-up move (`request_jump_step()`
## -- see its own doc comment, and README item 42) triggered by the same
## key, so pressing jump while facing and adjacent to this platform
## actually lifts the player onto its top. This is still NOT a general
## verticality system -- the platform gets a `Ledge` (ledge.gd) alongside
## its real collision, declaring its walkable footprint/height as data,
## not something the player can climb ANYWHERE tall enough; only through
## a Ledge. Built from the SAME local variables as the collision box below
## specifically so the two can't drift apart from each other.
func _build_jump_test_platform() -> void:
	var platform := Node3D.new()
	platform.name = "JumpTestPlatform"
	platform.position = jump_test_platform_position
	add_child(platform)

	var box_mesh := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.6)
	box_mesh.material = mat
	box_mesh.size = Vector3(2.0, jump_test_platform_height, 2.0)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = box_mesh
	mesh_instance.position = Vector3(0, jump_test_platform_height * 0.5, 0)
	platform.add_child(mesh_instance)

	# Real obstruction, built the same way _build_wall_collision() builds
	# each wall cell -- an independent StaticBody3D on
	# WALL_COLLISION_LAYER_BIT, not a GridMap cell (this platform isn't
	# painted on the grid at all) and not an Interactable (it's not
	# interactable -- pure scenery + collision).
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (GridActor.WALL_COLLISION_LAYER_BIT - 1)
	body.collision_mask = 0
	body.position = mesh_instance.position
	platform.add_child(body)

	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box_mesh.size
	shape_node.shape = box_shape
	body.add_child(shape_node)

	# The walkable-top declaration GridActor's request_jump_step() reads.
	# height/footprint_size come from the exact same box_mesh.size this
	# function just used for the visual + collision, not hand-copied
	# numbers that could quietly fall out of sync with it.
	var ledge := Ledge.new()
	ledge.name = "Ledge"
	ledge.height = box_mesh.size.y
	ledge.footprint_size = Vector2(box_mesh.size.x, box_mesh.size.z)
	ledge.position = Vector3.ZERO
	platform.add_child(ledge)


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
