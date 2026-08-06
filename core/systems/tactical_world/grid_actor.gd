# grid_actor.gd
# Godot version: 4.6
#
# Grid-snapping movement for a player (or NPC) entity. Movement happens
# in fixed-distance discrete steps -- the readable, one-input-one-move
# stepping Balrum's flat maps use, carried over into 3D. A new move
# isn't accepted until the current one finishes, so it can't be stacked
# into something that feels like free-roam sliding.
#
# `step_distance` (how far one move covers) is intentionally decoupled
# from `cell_size` (the GridMap's tile size, used only to resolve which
# GridMap cell a position falls in for obstruction checks). They don't
# have to match: step_distance smaller than cell_size gives finer
# movement resolution -- e.g. cell_size=1.0m, step_distance=0.5m means
# two key presses cross one tactical grid cell -- without changing the
# grid walls and props are laid out on. If you DO want the classic
# "one press = one cell" feel, just set them equal.
#
# Attach to a CharacterBody3D. Does not read input directly -- call
# request_move(direction) from a player-input script (or an AI/pathing
# script for NPCs), so the same component drives both.

extends CharacterBody3D
class_name GridActor

signal move_started(from_step: Vector3i, to_step: Vector3i)
signal move_finished(step: Vector3i)
signal move_blocked(step: Vector3i)

## World-space size of one GridMap cell. Used ONLY to translate a target
## world position into a GridMap cell coordinate for obstruction checks
## -- it does not have to equal `step_distance`. Must match the actual
## GridMap's `cell_size` (X/Z; Y is irrelevant here since this actor
## never steps vertically) or obstruction checks will look at the wrong
## cell.
@export var cell_size := Vector3(1.0, 1.0, 1.0)

## World distance one discrete move covers, in X/Z. Independent of
## cell_size -- see the file header. Doesn't have to evenly divide
## cell_size, but if it doesn't, "which cell am I standing in" (see
## `current_cell()`) stops lining up with visually-centered tiles at
## every step, only some of them.
@export var step_distance := 0.5

## Seconds to glide from one step to the next. Kept short and linear --
## this is a tactical stepper, not a physics-driven walk cycle. If you
## shrink step_distance for finer movement, consider shrinking this
## proportionally too or overall traversal speed drops along with it
## (half the distance per step at the same duration = half the speed).
@export_range(0.02, 1.0) var move_duration := 0.18

## Diagonal stepping (8-directional) vs. cardinal-only (4-directional).
## Balrum's readable grid favors cardinal; diagonal is here for games
## that want the extra mobility.
##
## Documented rule for allow_diagonal == false: a diagonal direction is
## REJECTED OUTRIGHT (see the check at the top of request_move()) -- it
## does not fall back to attempting either component axis instead. This
## is the one documented rule; there is no silent "try X then Z" or
## "try Z then X" alternate-axis behavior anywhere. A caller that wants
## diagonal-held input to still make progress along a wall while
## allow_diagonal is false needs to submit the reduced cardinal
## direction itself once only one axis is actually held (which is
## exactly what grid_actor_player_input.gd's held-key model already
## does -- it recomputes intent from live key state, it doesn't try to
## decompose a rejected diagonal).
##
## Diagonal distance vs. cardinal distance: a diagonal step moves
## Vector3i(±1, 0, ±1), which is geometrically farther (step_distance *
## sqrt(2)) than a cardinal step's step_distance. That is NOT
## compensated for -- move_duration is a fixed per-STEP time regardless
## of direction (see move_duration below), the same established rule
## already used for every other step this component takes. The
## consequence, stated plainly rather than left to be discovered:
## diagonal movement covers more ground per second than cardinal
## movement, by a factor of sqrt(2) (~41% faster in world-space speed).
## This mirrors the common tactical/roguelike "king move" convention
## (a diagonal step costs the same one action as a cardinal step) rather
## than a physically-normalized speed. Revisit only if that ever reads
## as a problem in play -- there's no other established rule to fall
## back to here.
@export var allow_diagonal := true

## Optional: assign a GridMap to have moves check against solid cells
## (walls) before committing, instead of only relying on physics
## collision. Left unset, this component still works -- it just won't
## know about GridMap-authored obstacles ahead of time.
@export var obstruction_map: GridMap

## Where walls live relative to the layer this actor walks on, in
## GridMap cell units. If walls are painted on a different GridMap
## y-layer than the floor (e.g. floor at y=0, walls stacked at y=1 so
## they render standing on top of the floor instead of clipping into
## it), set this to that offset, e.g. Vector3i(0, 1, 0). Left at zero,
## walls are assumed to occupy the same layer the actor walks on.
@export var wall_layer_offset := Vector3i.ZERO

## Which GridMap item ids count as solid/blocking. Left empty (default),
## ANY non-empty cell on the checked layer is treated as an obstacle --
## correct for a GridMap that only ever places walls on that layer. If
## your GridMap also places walkable content (floor tiles, decoration)
## on the SAME layer as walls, list the wall item id(s) here explicitly
## so floor tiles aren't mistaken for obstacles and every move gets
## rejected.
@export var obstacle_item_ids: PackedInt32Array = []

## In addition to the GridMap wall check above, also treat any node in
## Interactable.BLOCKING_GROUP as solid if its cell matches the target
## cell -- this is how chests, plants, etc. occupy real, non-passable
## space without being baked into the GridMap. Set false to opt an
## individual actor out (e.g. an NPC that's allowed to walk through
## furniture) without touching the objects themselves.
@export var check_object_collision := true

## Discrete position, measured in `step_distance` units -- NOT GridMap
## cells. With sub-cell stepping this is finer than the tactical grid
## (e.g. two step values per cell_size), so it deliberately isn't named
## current_cell anymore: after an odd number of steps the actor can sit
## exactly on a cell boundary, which has no single "current cell." Use
## `current_cell()` below when you need the GridMap cell under the
## actor's actual position instead.
var current_step: Vector3i
var is_moving := false

## Authoritative world-facing direction, in the same XZ direction units
## request_move() takes (e.g. Vector2i(0,-1) = north). Updated whenever a
## move is ACCEPTED, so it always reflects the last direction the actor
## actually committed to -- never touched on a blocked move, so bumping
## into a wall doesn't spin the actor to face it.
##
## This is plain gameplay state, not visual: GridActor stays agnostic to
## how (or whether) anything renders facing. A presentation layer
## (sprite_actor.gd) reads this instead of owning its own copy, and an
## AI-driven actor gets a meaningful facing for free the same way.
var facing_direction := Vector2i(0, -1)

var _move_from: Vector3
var _move_to: Vector3
var _move_t := 0.0


func _ready() -> void:
	current_step = world_to_step(global_position)
	global_position = step_to_world(current_step)


func _physics_process(delta: float) -> void:
	if not is_moving:
		return

	_move_t = clampf(_move_t + delta / move_duration, 0.0, 1.0)
	global_position = _move_from.lerp(_move_to, _move_t)

	if _move_t >= 1.0:
		is_moving = false
		global_position = _move_to
		move_finished.emit(current_step)


## direction should be a cardinal/diagonal unit-ish vector in XZ, e.g.
## Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, 1). Returns true if the
## move was accepted (a move already in progress, or a disallowed
## diagonal, returns false without side effects).
func request_move(direction: Vector2i) -> bool:
	if is_moving:
		return false
	if direction == Vector2i.ZERO:
		return false
	if not allow_diagonal and direction.x != 0 and direction.y != 0:
		return false

	var target_step := current_step + Vector3i(direction.x, 0, direction.y)
	var target_world := step_to_world(target_step)

	# Collision is tested at a point nudged an epsilon back toward where
	# this step came FROM, not at target_world itself -- see
	# _collision_test_point()'s doc comment for the real, raycast-
	# confirmed geometry bug this fixes: whenever step_distance divides
	# cell_size into an exact half (the default 0.5/1.0 tuning), every
	# other step's target lands EXACTLY on a cell boundary, and
	# world_to_cell()'s nearest-cell rounding has to break that tie
	# somehow. _move_to (the actual glide destination) stays
	# target_world, unmodified -- only the LEGALITY CHECK uses the
	# nudged point, so the actor still visually/physically ends up
	# exactly on the intended half-step grid position.
	if _is_obstructed(_collision_test_point(target_world, direction)):
		move_blocked.emit(target_step)
		return false

	_move_from = global_position
	_move_to = target_world
	_move_t = 0.0
	is_moving = true
	facing_direction = direction

	move_started.emit(current_step, target_step)
	current_step = target_step
	return true


## Nudges a target position an epsilon back toward the direction it came
## from, so a target that lands EXACTLY on a cell boundary (the actual
## reported bug: "a half-step at 0.5 is being rounded into the next
## GridMap cell") tests as still touching the near side, not already
## inside the far cell.
##
## Root cause, confirmed empirically before writing this (not assumed):
## with cell_center_x/y/z = false, a wall at GridMap cell index N is
## REALLY, physically centered at world N*cell_size, spanning
## [N-0.5, N+0.5)*cell_size -- confirmed with a direct-space-state
## raycast against the wall's actual collision shape, which hit at
## exactly N-0.5, matching map_to_local(N) == N*cell_size and this
## file's own cell_to_world()/step_to_world() formula exactly. So
## world_to_cell()'s roundi()-based nearest-cell rounding is the
## CORRECT mapping for this project's geometry -- it is NOT the same
## bug class as "round vs. floor disagreeing with GridMap," and
## switching it to floori() would desync it from where the wall mesh
## and its collision shape actually are, reintroducing the exact
## "half a space offset" misalignment bug cell_center_x/y/z=false was
## originally set to fix (see tactical_demo_world.gd's comment on that).
##
## (A related, DIFFERENT bug was found and fixed alongside this one:
## GridMap.local_to_map() does NOT respect cell_center_x/y/z at all --
## confirmed empirically, it stayed floor-based regardless -- so it
## disagreed with the wall's real position by up to half a cell.
## interaction_controller.gd's line-of-sight check used to call
## grid_map.local_to_map() directly for exactly this reason; it now
## calls player.world_to_cell() instead, the same geometry-correct
## mapping this file uses, so "can I walk there" and "can I see it"
## can't disagree with each other about where a wall actually is.)
##
## The actual remaining problem was narrower than "which rounding
## function": roundi() is right almost everywhere, but has to break a
## tie at EXACTLY a cell boundary, and this project's default tuning
## (step_distance=0.5 is exactly half of cell_size=1.0) makes every
## OTHER step land precisely on that seam -- not a rare edge case here,
## the common one. Godot's roundi() breaks ties away from zero, which
## for a step moving further from the origin along that axis happens to
## round INTO the cell being approached (the wall) rather than staying
## on the near side. Nudging the TEST point (never the actual glide
## destination -- see request_move()) by a small epsilon opposite the
## direction of travel resolves the tie toward "still on the near side,
## touching but not penetrating" regardless of which axis or which
## direction the wall is approached from, without touching the
## nearest-cell math itself (which is already correct).
const _COLLISION_TEST_EPSILON := 0.01  # << 0.5 * min(step_distance, cell_size.x/z) for any sane tuning


func _collision_test_point(target_world: Vector3, direction: Vector2i) -> Vector3:
	var dir3 := Vector3(float(direction.x), 0.0, float(direction.y))
	if dir3.length_squared() < 0.0001:
		return target_world
	return target_world - dir3.normalized() * _COLLISION_TEST_EPSILON


func _is_obstructed(target_world: Vector3) -> bool:
	if _is_wall_obstructed(target_world):
		return true
	if check_object_collision and _is_object_obstructed(target_world):
		return true
	return false


func _is_wall_obstructed(target_world: Vector3) -> bool:
	if obstruction_map == null:
		return false
	# A GridMap item id of -1 (GridMap.INVALID_CELL_ITEM) means "no tile
	# placed there" -- always open. The check happens against the
	# GridMap CELL the target world position falls into (via cell_size),
	# not against step coordinates directly -- those are on a different,
	# finer lattice when step_distance < cell_size.
	var cell := world_to_cell(target_world)
	var check_cell := cell + wall_layer_offset
	var item := obstruction_map.get_cell_item(check_cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return false
	if obstacle_item_ids.is_empty():
		return true
	return obstacle_item_ids.has(item)


func _is_object_obstructed(target_world: Vector3) -> bool:
	# X/Z only, deliberately -- this actor's own step math never leaves
	# y=0, but an object's world_to_cell().y depends on its own height
	# above the floor (e.g. a chest sitting at y=0.35 rounds to a
	# different cell layer than y=0.0 would), which has nothing to do
	# with whether it blocks a same-plane XZ move. Comparing the full
	# Vector3i here would silently never match on Y and never block.
	var target_cell := world_to_cell(target_world)
	for node in get_tree().get_nodes_in_group(Interactable.BLOCKING_GROUP):
		var obj := node as Node3D
		if obj == null or obj == self:
			continue
		var obj_cell := world_to_cell(obj.global_position)
		if obj_cell.x == target_cell.x and obj_cell.z == target_cell.z:
			return true
	return false


## The GridMap cell the actor's actual current position falls into.
## Computed on demand rather than cached, since it's a different lattice
## than `current_step` and only some callers need it.
func current_cell() -> Vector3i:
	return world_to_cell(global_position)


func world_to_step(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		roundi(world_pos.x / step_distance),
		roundi(world_pos.y / step_distance),
		roundi(world_pos.z / step_distance)
	)


func step_to_world(step: Vector3i) -> Vector3:
	return Vector3(step.x * step_distance, step.y * step_distance, step.z * step_distance)


## Deliberately NOT roundi(world_pos / cell_size), even though that
## looks like the obvious "nearest cell center" formula and IS correct
## almost everywhere. Real, reported bug: roundi() breaks exact ties
## AWAY FROM ZERO, which for a EACH cell means it owns whichever
## boundary happens to face the coordinate ORIGIN and loses whichever
## boundary faces away from it -- confirmed empirically (not assumed) by
## sweeping world_to_cell() across a wide 1D range: cell 1 owns
## {0.5, 1.0} but not 1.5 (which goes to cell 2); cell -1 owns
## {-1.0, -0.5} but not -1.5 (which goes to cell -2). That's origin-
## relative, not cell-relative, and it's invisible for every cell except
## ONE: cell 0 straddles the origin, so BOTH of its boundaries (-0.5 and
## +0.5) face away from it simultaneously -- neither is owned, so cell 0
## reports correctly for exactly one point (world 0.0) and nothing else,
## even though the same-sized debug quad drawn for it (see
## debug_grid_overlay.gd) is a full, symmetric square. This is exactly
## what surfaced as "the highlight quad only lets me stand in one
## corner, then jumps ahead everywhere else."
##
## floori(x + 0.5) instead gives EVERY cell N a uniform, origin-
## independent span of [N-0.5, N+0.5) -- lower boundary owned, upper
## boundary belongs to the next cell out, always, regardless of sign.
## Agrees with roundi() at every non-boundary point (both pick the
## nearest cell center identically); the two formulas only ever disagree
## exactly AT a tie (x is a multiple of half a cell), which is precisely
## the case _collision_test_point() already nudges away from before any
## movement-legality check reaches this function -- so that fix is
## unaffected by this one. This function is also used for plain
## identification (current_cell(), the debug overlay, object collision
## cell comparisons) where there's no direction of travel to nudge
## against, which is exactly where the old origin-relative asymmetry was
## actually visible.
func world_to_cell(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_pos.x / cell_size.x + 0.5),
		floori(world_pos.y / cell_size.y + 0.5),
		floori(world_pos.z / cell_size.z + 0.5)
	)


func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * cell_size.x, cell.y * cell_size.y, cell.z * cell_size.z)
