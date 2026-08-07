# debug_grid_overlay.gd
# Godot version: 4.6
#
# TEMPORARY DEBUG TOOL. Not part of the framework proper -- remove this
# node (and this file) once the two lattices below are no longer in
# question. Exists to make "which grid, exactly, are we standing
# relative to" visible on screen instead of read off printed
# coordinates, since this project juggles TWO genuinely different
# coordinate lattices simultaneously (see grid_actor.gd's file header
# and README items 22-24 for the real bugs that came from conflating
# them):
#
#   BLUE  -- the GridMap CELL lattice (GridActor.cell_size, default
#            1.0m). Cells are CENTERED on integer multiples of
#            cell_size (confirmed by raycast against real wall
#            collision -- see grid_actor.gd's step_to_cell()
#            doc comment), so cell BOUNDARIES -- where wall/floor
#            collision actually changes -- fall on the HALF-integer
#            lines drawn here, not the integer ones.
#   ORANGE -- the GridActor STEP lattice (GridActor.step_distance,
#            default 0.5m). Every line here is a position the player
#            can actually come to rest on. With the current 0.5/1.0
#            tuning, every OTHER orange line lands exactly on a blue
#            line (a cell boundary) -- the other half land on a cell's
#            CENTER instead. That coincidence-on-alternating-steps is
#            exactly what produced the "half-step rounds into the next
#            cell" bug (README item 22): the boundary case isn't rare,
#            it's every other step.
#
# Two small filled quads track the player live: a big, dim one showing
# their CURRENT CELL (blue), a small, bright one showing their exact
# CURRENT STEP position (orange) -- so it's visible at a glance which
# cell they're standing in and where within it.

extends Node3D
class_name DebugGridOverlay

@export var enabled := true:
	set(value):
		enabled = value
		visible = value

@export var player: GridActor
## How far the grid extends, in GridMap CELLS from the origin -- match
## tactical_demo_world.gd's own half_extent so the overlay covers the
## whole painted floor, not more or less of it.
@export var half_extent := 10

@export var cell_color := Color(0.15, 0.55, 1.0, 0.85)
@export var step_color := Color(1.0, 0.55, 0.05, 0.9)
## Small Y offsets so the two grids and the two highlight quads never
## z-fight with the floor or with each other. Floor top surface sits at
## roughly cell_size.y * 0.5 (~0.05 at the default 0.1 thickness).
@export var cell_line_y := 0.06
@export var step_line_y := 0.09

## On-screen text readout of the player's exact coordinates -- added
## specifically so a playtester who can describe what they're looking
## at, but not read numbers off this codebase directly, can report a
## bug as "cell (9, 0, -3), facing east" instead of "near that one
## wall." Separate toggle from `enabled` (the 3D grid lines/quads) --
## the HUD is useful even with the floor grid turned off.
@export var show_hud := true
@export var hud_font_size := 20

var _current_cell_highlight: MeshInstance3D
var _current_step_highlight: MeshInstance3D
var _built := false
var _hud_label: Label


func _ready() -> void:
	visible = enabled
	# Deliberately does NOT build the grid meshes here. Godot calls
	# children's _ready() before their PARENT's -- and `player` is only
	# assigned once tactical_demo_world.gd's _ready() gets to it, which
	# is strictly later. Building the cell/step lattice meshes here would
	# silently fall back to defaults instead of the real
	# cell_size/step_distance, the exact ready-order bug already fixed
	# once in this project (see sprite_actor.gd's old `actor` setter
	# comment history). Deferred to the first _process() call instead --
	# see _build_static_grids() below.


func _process(_delta: float) -> void:
	if not _built:
		_build_static_grids()
		_built = true

	if player == null:
		return
	var cell := _sticky_current_cell()
	var cell_world := player.cell_to_world(cell)
	_current_cell_highlight.position = Vector3(cell_world.x, cell_line_y + 0.002, cell_world.z)

	var step_world := player.step_to_world(player.current_step)
	_current_step_highlight.position = Vector3(step_world.x, step_line_y + 0.002, step_world.z)

	_update_hud(cell)


## Facing shown as a compass word, not just the raw Vector2i -- "facing
## east" is what a playtester will actually type back, not "facing
## (1, 0)".
const _FACING_NAMES := {
	Vector2i(0, -1): "north", Vector2i(0, 1): "south",
	Vector2i(1, 0): "east", Vector2i(-1, 0): "west",
	Vector2i(1, -1): "northeast", Vector2i(1, 1): "southeast",
	Vector2i(-1, -1): "northwest", Vector2i(-1, 1): "southwest",
}


func _update_hud(cell: Vector3i) -> void:
	if _hud_label == null:
		return
	_hud_label.visible = show_hud
	if not show_hud:
		return
	var pos := player.global_position
	var facing_name: String = _FACING_NAMES.get(player.facing_direction, "?")
	_hud_label.text = (
		"pos    %6.2f, %6.2f\n" +
		"step   %4d, %4d\n" +
		"cell   %4d, %4d   (facing %s)"
	) % [pos.x, pos.z, player.current_step.x, player.current_step.z, cell.x, cell.z, facing_name]


## A cell is exactly TWO steps wide (step_distance = 0.5 * cell_size in
## this project's tuning), so the boundary between two cells sits
## EXACTLY on the step lattice -- every other step lands exactly on a
## tie, equidistant from both cells' centers. Any STATELESS point->cell
## formula (player.world_to_cell() included) has to break that tie
## SOMEHOW, and whichever direction it picks, that direction always
## "wins" the tie -- which reads as correct from one side (you can
## step fully across into the new cell before it's reported) and wrong
## from the other (the reported cell flips on the FIRST step, one full
## step before you've actually left the old cell, landing you on the
## new cell's far edge instead of its near one). Real, reported bug:
## confirmed this by testing all 4 cardinal directions from a cell's own
## center -- two directions took 2 steps to flip (matching cell_size),
## the other two flipped after 1 step and landed off-center.
##
## Fixed with STICKY tracking instead of a stateless formula: keep
## reporting whichever cell was last reported, and only flip to a
## different cell once the player's position is STRICTLY closer to that
## other cell's center than to the currently-reported one -- an exact
## tie (equidistant, i.e. sitting right on a boundary) stays on the
## current cell rather than resolving it either way. This makes every
## direction behave identically: the first step to a boundary doesn't
## flip anything (still tied), and only the second step -- landing
## exactly on the neighboring cell's own center, unambiguously closer to
## it -- flips the highlight, which is also why "the quad lands centered
## under me" falls out for free rather than needing to be special-cased.
var _tracked_cell: Vector3i
var _tracked_cell_valid := false


func _sticky_current_cell() -> Vector3i:
	var raw_cell := player.world_to_cell(player.global_position)
	if not _tracked_cell_valid:
		_tracked_cell = raw_cell
		_tracked_cell_valid = true
		return _tracked_cell

	if raw_cell == _tracked_cell:
		return _tracked_cell

	var current_center := player.cell_to_world(_tracked_cell)
	var raw_center := player.cell_to_world(raw_cell)
	var dist_to_current := player.global_position.distance_squared_to(current_center)
	var dist_to_raw := player.global_position.distance_squared_to(raw_center)
	# Small epsilon so floating-point noise at a TRUE tie can't
	# accidentally win by a hair in either direction -- both sides of a
	# real boundary must come out exactly equal here (step positions are
	# always exact multiples of 0.5, never inexact), but this guards
	# against relying on that exactness surviving unrelated float error.
	if dist_to_raw < dist_to_current - 0.0001:
		_tracked_cell = raw_cell
	return _tracked_cell


func _build_static_grids() -> void:
	if player == null:
		push_warning("DebugGridOverlay: no player assigned by the time the first frame ran -- grids will use fallback defaults (cell_size=1.0, step_distance=0.5) and the live highlight quads won't move.")

	add_child(_build_line_mesh(_cell_boundary_lines(), cell_color, cell_line_y))
	add_child(_build_line_mesh(_step_lattice_lines(), step_color, step_line_y))

	# Alpha bumped up from an earlier, fainter 0.35 -- at that opacity the
	# blue GRID LINES crossing over the quad's own faint fill blended
	# into a visibly denser patch near cell corners (where 4 lines meet),
	# which could read as a second, separate square even though there's
	# only ever one quad (confirmed by inspecting the actual node tree,
	# not just the screenshot). More opaque fill reads as one solid
	# region regardless of which lines happen to cross it.
	_current_cell_highlight = _build_quad(_cell_size_x(), _cell_size_z(), cell_color * Color(1, 1, 1, 0.55), cell_line_y + 0.002)
	add_child(_current_cell_highlight)

	# A small fraction of a step's own spacing, not the full cell -- this
	# one is meant to read as "a point," the cell quad above already
	# shows the coarser region.
	var marker_size: float = (player.step_distance if player else 0.5) * 0.4
	_current_step_highlight = _build_quad(marker_size, marker_size, step_color, step_line_y + 0.002)
	add_child(_current_step_highlight)

	# _build_hud_label() already parents the label under its own
	# CanvasLayer/PanelContainer internally -- this just keeps the
	# reference for _update_hud() to write to each frame, it does not
	# re-parent it (that would be adding it as a child twice, a real
	# bug caught by actually running this, not just reading it back).
	_hud_label = _build_hud_label()


## 2D CanvasLayer readout, top-left corner -- deliberately NOT drawn in
## 3D world space (unlike the grid/quads above), so it stays flat,
## readable, and camera-independent regardless of mode (LOCKED,
## BEHIND_SPRITE, TOP_DOWN) or zoom.
func _build_hud_label() -> Label:
	var layer := CanvasLayer.new()
	layer.layer = 20  # above the interaction panel (layer 10)
	add_child(layer)

	var panel := PanelContainer.new()
	panel.offset_left = 12
	panel.offset_top = 12
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.55)
	panel_style.content_margin_left = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(panel)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", hud_font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	# Best-effort monospace request so the coordinate columns ("step 4,
	# -6" vs "step 18, -2") line up instead of drifting with each
	# digit's own width. SystemFont queries the OS's installed fonts for
	# the first name it finds and falls back to the default UI font
	# (not a broken/blank state) if none of these happen to be
	# installed -- acceptable for a debug-only readout either way.
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
	label.add_theme_font_override("font", mono)
	panel.add_child(label)
	return label


func _cell_size_x() -> float:
	return player.cell_size.x if player else 1.0


func _cell_size_z() -> float:
	return player.cell_size.z if player else 1.0


## Lines at every cell BOUNDARY (half-integer multiples of cell_size) --
## see the file header for why boundaries, not centers.
func _cell_boundary_lines() -> PackedVector3Array:
	var cs_x := _cell_size_x()
	var cs_z := _cell_size_z()
	var extent_x := (float(half_extent) + 0.5) * cs_x
	var extent_z := (float(half_extent) + 0.5) * cs_z
	var pts := PackedVector3Array()
	for k in range(-half_extent, half_extent + 2):
		var x := (float(k) - 0.5) * cs_x
		pts.append(Vector3(x, 0.0, -extent_z))
		pts.append(Vector3(x, 0.0, extent_z))
	for k in range(-half_extent, half_extent + 2):
		var z := (float(k) - 0.5) * cs_z
		pts.append(Vector3(-extent_x, 0.0, z))
		pts.append(Vector3(extent_x, 0.0, z))
	return pts


## Lines at every STEP position (integer multiples of step_distance) --
## every position the player can actually stand on.
func _step_lattice_lines() -> PackedVector3Array:
	var step := player.step_distance if player else 0.5
	var cs_x := _cell_size_x()
	var cs_z := _cell_size_z()
	var extent_x := float(half_extent) * cs_x
	var extent_z := float(half_extent) * cs_z
	var count_x := int(round(extent_x / step))
	var count_z := int(round(extent_z / step))
	var pts := PackedVector3Array()
	for k in range(-count_x, count_x + 1):
		var x := float(k) * step
		pts.append(Vector3(x, 0.0, -extent_z))
		pts.append(Vector3(x, 0.0, extent_z))
	for k in range(-count_z, count_z + 1):
		var z := float(k) * step
		pts.append(Vector3(-extent_x, 0.0, z))
		pts.append(Vector3(extent_x, 0.0, z))
	return pts


func _build_line_mesh(points: PackedVector3Array, color: Color, y: float) -> MeshInstance3D:
	var shifted := PackedVector3Array()
	for p in points:
		shifted.append(Vector3(p.x, y, p.z))

	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in shifted:
		immediate.surface_add_vertex(p)
	immediate.surface_end()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = immediate
	mesh_instance.material_override = _unshaded_material(color)
	# Debug overlay, not gameplay geometry -- no shadows, no collision,
	# never considered by anything that isn't looking at it.
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance


func _build_quad(size_x: float, size_z: float, color: Color, y: float) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size_x, size_z)
	quad.orientation = PlaneMesh.FACE_Y

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.material_override = _unshaded_material(color)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = Vector3(0, y, 0)
	return mesh_instance


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# no_depth_test would make this draw through walls/floor from any
	# distance -- left OFF on purpose so the grid still looks grounded
	# and gets occluded by walls the way real floor markings would.
	return mat
