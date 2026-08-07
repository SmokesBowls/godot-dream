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
## Emitted whenever facing_direction actually changes (via
## face_direction() -- see its doc comment). Exists specifically so
## sprite_actor.gd can refresh its displayed pose the INSTANT facing
## changes, even while the tree is paused for an interaction (signal
## delivery isn't gated by process_mode the way _process() calls are --
## SpriteActor deliberately stays PROCESS_MODE_PAUSABLE, not ALWAYS, to
## avoid a worse problem: making the whole sprite always-process would
## also keep its run-animation frame advancing if a glide happened to
## be mid-flight the instant an interaction began, since GridActor
## itself (correctly) stops processing when paused and never gets to
## set is_moving back to false).
signal facing_changed(direction: Vector2i)

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
## move is ACCEPTED, and ALSO on a REJECTED move caused by an
## OBSTRUCTION (a wall or solid object) -- see face_direction() and the
## calls to it inside request_move() below. Deliberately reversed from
## an earlier version of this comment, which said the opposite ("never
## touched on a blocked move, so bumping into a wall doesn't spin the
## actor to face it"): real, reported problem with that -- walk up to a
## wall, stop, press a direction into it, and the character just kept
## facing wherever it already was, which reads as the game not having
## heard the input at all. Bumping into something now visibly turns the
## character toward it; it still doesn't MOVE there.
##
## Deliberately NOT extended to every rejection reason -- the "already
## moving" rejection (is_moving true) and the "diagonal disallowed"
## rejection are excluded on purpose. Neither of those is "I tried to
## go somewhere and something physically blocked me"; they're "that
## request was never really attempted," so there's nothing to visually
## acknowledge, and turning to face a direction that was silently
## dropped (or worse, spinning on every repeated key spammed while
## still mid-glide) would be noise, not feedback.
##
## This is plain gameplay state, not visual: GridActor stays agnostic to
## how (or whether) anything renders facing. A presentation layer
## (sprite_actor.gd) reads this instead of owning its own copy, and an
## AI-driven actor gets a meaningful facing for free the same way.
var facing_direction := Vector2i(0, -1)


## Turns the actor to face `direction` immediately, WITHOUT moving --
## never touches current_step, is_moving, or emits move_started/
## move_finished. THE single place facing_direction is ever assigned
## (request_move()'s successful-move path routes through this too, not
## just the obstruction/interaction callers) so facing_changed always
## fires uniformly, regardless of why facing changed.
##
## Three callers: request_move() itself, both for a successful move AND
## for an obstructed attempt (see facing_direction's doc comment above
## for why bumping a wall now turns the actor); and
## interaction_controller.gd's begin_interaction(), which turns the
## actor to face whatever it just started interacting with even though
## it never moved a step to reach it.
func face_direction(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO or direction == facing_direction:
		return
	facing_direction = direction
	facing_changed.emit(direction)


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
##
## HOW OBSTRUCTION IS DECIDED (rewritten from a float-rounding approach
## to an exact-integer one -- see the big doc comment on step_to_cell()
## below for the full history and why): current_step and target_step
## are always EXACT integers. Every legality check in this function
## works entirely in that integer step space -- step_to_cell() below
## converts a step index to a GridMap cell index via true integer floor
## division, which has no rounding, no ties, and therefore nothing left
## to nudge or patch. World-space float positions only enter the
## picture afterward, purely to compute _move_to (the visual glide
## target) -- never to decide legality.
func request_move(direction: Vector2i) -> bool:
	if is_moving:
		return false
	if direction == Vector2i.ZERO:
		return false
	if not allow_diagonal and direction.x != 0 and direction.y != 0:
		return false

	var target_step := current_step + Vector3i(direction.x, 0, direction.y)

	if _is_step_obstructed(target_step):
		face_direction(direction)
		move_blocked.emit(target_step)
		return false

	# A half-step landing exactly ON a shared cell boundary (not a
	# cell's own center) is only legal if EVERY cell that boundary
	# touches is itself traversable -- see _is_axis_step_on_boundary()'s
	# doc comment for why a zero-radius point touching a wall's face is
	# geometrically fine but this actor, with a real capsule radius,
	# isn't.
	#
	# Deliberately direction-INDEPENDENT -- an earlier version of this
	# check branched on whether `direction` was actively advancing each
	# axis ("the axis I'm moving needs one more step ahead; the axis
	# I'm not moving was already validated"), which fixed one real bug
	# (doorway -> turn along the wall) but left a second one: when BOTH
	# axes land on a boundary AT ONCE -- a true 2D grid corner, not just
	# a 1D edge -- FOUR cells meet at that point, not two. Checking each
	# axis separately (even checking both neighbors on each) only ever
	# reaches the two cells that share an EDGE with the target's own
	# cell; the fourth cell, which shares only the CORNER (both axes
	# shifted at once), was never examined by either axis check alone.
	# Reported precisely via screenshots of the actor standing at
	# exactly such a corner, next to a chest and next to the plant.
	#
	# The fix: stop trying to reason about which neighbor "must already
	# be validated by the direction of travel" (that reasoning is what
	# produced the first bug) and just check every cell touching the
	# boundary(ies) target_step sits on, unconditionally. One boundary
	# axis -> 2 neighbors (an edge). Two boundary axes at once -> all 4
	# corner combinations (dx, dz each independently +-1). Cheap either
	# way -- at most 4 extra GridMap/group lookups, once per requested
	# move, not per frame.
	var per_cell := _steps_per_cell()
	# NOT `x_offsets: Array[int] = [1, -1] if ... else [0]` -- a real
	# GDScript quirk, caught by actually running it rather than assumed:
	# a ternary whose branches are array literals returns a plain
	# untyped Array, which fails at RUNTIME (not parse time) when
	# assigned to an Array[int]-typed variable. Plain if/else
	# reassignment doesn't have this problem.
	var x_offsets: Array[int] = [0]
	if _is_axis_step_on_boundary(target_step.x, per_cell.x):
		x_offsets = [1, -1]
	var z_offsets: Array[int] = [0]
	if _is_axis_step_on_boundary(target_step.z, per_cell.z):
		z_offsets = [1, -1]
	for dx in x_offsets:
		for dz in z_offsets:
			if dx == 0 and dz == 0:
				continue  # target_step itself -- already checked above
			# corner_safety_probe = true -- see that parameter's doc
			# comment on _is_step_obstructed() for why footprint-mode
			# objects are deliberately excluded from THIS check
			# specifically, unlike the plain target_step check above.
			if _is_step_obstructed(target_step + Vector3i(dx, 0, dz), true):
				face_direction(direction)
				move_blocked.emit(target_step)
				return false

	_move_from = global_position
	_move_to = step_to_world(target_step)
	_move_t = 0.0
	is_moving = true
	face_direction(direction)

	move_started.emit(current_step, target_step)
	current_step = target_step
	return true


## corner_safety_probe: true only when called from request_move()'s
## boundary-corner safety loop (see its own comment for the full corner-
## point rationale). That loop's actual question is "is the OTHER cell
## touching this boundary entirely solid mass" -- true for walls and
## occupies_full_cell objects (any point inside a solid cell correctly
## answers that), but not a question a footprint-mode object (see
## Interactable.occupancy_radius) can answer at all: its footprint is
## small and doesn't necessarily reach the shared boundary, so treating
## "this one lattice point 1 full step further out happens to land on
## it" as "the whole neighboring cell is unsafe" is simply the wrong
## question for it. A footprint object's actual overlap with the
## boundary point ITSELF is already caught correctly by the plain
## (non-probe) call on target_step, made once before that loop even
## starts -- this parameter only suppresses the probe loop's OWN extra
## (dx, dz) neighbor checks from re-triggering on it a second, wrong way.
## Found empirically: an apple sitting on an even step index (a normal
## cell-center placement) made every cardinally-adjacent boundary step
## permanently unapproachable regardless of how small occupancy_radius
## was set, because that boundary step's probe neighbor was always the
## apple's own center step -- trivially "obstructed" no matter the
## radius, defeating the whole point of a small footprint.
func _is_step_obstructed(step: Vector3i, corner_safety_probe: bool = false) -> bool:
	if _is_wall_obstructed_step(step):
		return true
	if check_object_collision and _is_object_obstructed_step(step, corner_safety_probe):
		return true
	return false


func _is_wall_obstructed_step(step: Vector3i) -> bool:
	if obstruction_map == null:
		return false
	# A GridMap item id of -1 (GridMap.INVALID_CELL_ITEM) means "no tile
	# placed there" -- always open.
	var cell := step_to_cell(step)
	var check_cell := cell + wall_layer_offset
	var item := obstruction_map.get_cell_item(check_cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return false
	if obstacle_item_ids.is_empty():
		return true
	return obstacle_item_ids.has(item)


func _is_object_obstructed_step(step: Vector3i, corner_safety_probe: bool = false) -> bool:
	# X/Z only, deliberately -- this actor's own step math never leaves
	# y=0, but an object's world_to_cell().y depends on its own height
	# above the floor (e.g. a chest sitting at y=0.35 rounds to a
	# different cell layer than y=0.0 would), which has nothing to do
	# with whether it blocks a same-plane XZ move. Comparing the full
	# Vector3i here would silently never match on Y and never block.
	#
	# The TARGET side uses the exact integer step_to_cell() below; the
	# OBJECT'S side still has to go through the float-based
	# world_to_cell(), because chests/plants are hand-placed at
	# arbitrary world positions, not derived from any step lattice --
	# there's no integer step index to convert for them. That's fine:
	# the entire class of tie-breaking bugs this file's history is full
	# of only ever came from STEP-LATTICE positions landing exactly on a
	# cell boundary, never from arbitrary hand-placed object positions
	# (no bug has ever been reported here, and object placements in
	# practice sit at plain cell centers, nowhere near a tie).
	var target_cell := step_to_cell(step)
	for node in get_tree().get_nodes_in_group(Interactable.BLOCKING_GROUP):
		# BLOCKING_GROUP's actual contract is "any Node3D that wants to
		# occupy space," not "any Interactable" -- Interactable._ready()
		# is the only thing that populates it in practice, but nothing
		# stops a test (or a future non-Interactable system) from joining
		# a plain Node3D directly, and that must keep working exactly as
		# it did before occupies_full_cell/occupancy_radius existed. Real
		# regression, caught by actually running the existing corner-case
		# suite: casting straight to Interactable here silently dropped
		# such nodes (obj == null, continue) instead of blocking them.
		var obj3d := node as Node3D
		if obj3d == null or obj3d == self:
			continue
		var obj := node as Interactable
		if obj == null or obj.occupies_full_cell:
			# Unchanged from before occupies_full_cell existed: the
			# object blocks its entire GridMap cell. Also the fallback
			# for any non-Interactable BLOCKING_GROUP member (see above)
			# -- no footprint data to read, so full-cell is the only
			# behavior that makes sense for it.
			var obj_cell := world_to_cell(obj3d.global_position)
			if obj_cell.x == target_cell.x and obj_cell.z == target_cell.z:
				return true
		elif not corner_safety_probe and _is_step_within_object_footprint(step, obj):
			# "The Apple Problem" fix -- see occupancy_radius's doc
			# comment on Interactable for why this branch deliberately
			# doesn't cell-cull first. Skipped entirely during a corner-
			# safety probe -- see _is_step_obstructed()'s doc comment on
			# corner_safety_probe for why.
			return true
	return false


## True if `step`'s actual landing point (not its enclosing GridMap
## cell) falls within `obj`'s occupancy_radius. Only ever called for
## occupies_full_cell == false objects -- see _is_object_obstructed_step().
func _is_step_within_object_footprint(step: Vector3i, obj: Interactable) -> bool:
	var landing := step_to_world(step)
	var dx := landing.x - obj.global_position.x
	var dz := landing.z - obj.global_position.z
	var reach := obj.occupancy_radius
	return dx * dx + dz * dz <= reach * reach


## True if a step COMPONENT (one axis only -- request_move() calls this
## once per axis, since each axis needs its own direction-vs-static
## handling, see the comment there) sits exactly on a shared boundary
## between two GridMap cells rather than on a cell's own center. Exact-
## integer version of a check that used to compare floating-point world
## coordinates against 0.5 -- see step_to_cell()'s doc comment for why
## that whole approach was replaced. A cell spans `_steps_per_cell()`
## consecutive step indices; its OWN boundary sits exactly halfway
## through that span (only meaningful when `_steps_per_cell()` is even,
## i.e. step_distance evenly divides cell_size into a whole, even
## number of steps -- the project's actual 0.5/1.0 tuning gives exactly
## 2 steps per cell, so the boundary is step-offset 1 of 2; an odd or
## degenerate ratio just makes this a no-op rather than misfire).
func _is_axis_step_on_boundary(step_component: int, steps_per_cell_axis: int) -> bool:
	if steps_per_cell_axis <= 0 or steps_per_cell_axis % 2 != 0:
		return false
	return _floor_mod(step_component, steps_per_cell_axis) == steps_per_cell_axis / 2


## The GridMap cell the actor's actual current position falls into.
## Computed on demand rather than cached, since it's a different lattice
## than `current_step` and only some callers need it. Uses
## world_to_cell() (float-based) rather than step_to_cell(), because
## global_position is only guaranteed to sit exactly on the step
## lattice while idle -- mid-glide it's a genuinely continuous
## interpolated position (see _physics_process()), and there's no exact
## integer step to convert then. When idle, global_position ==
## step_to_world(current_step) exactly, so this and
## step_to_cell(current_step) always agree anyway.
func current_cell() -> Vector3i:
	return world_to_cell(global_position)


## Whole number of steps spanning one GridMap cell, on each axis.
## Computed FRESH on every call rather than cached in _ready() --
## deliberately: tactical_demo_world.gd (and anything like it) assigns
## cell_size/step_distance from ITS OWN _ready(), which runs AFTER this
## node's _ready() (children ready before parents -- the same ordering
## fact that bit sprite_actor.gd's old `actor` setter and
## debug_grid_overlay.gd's static-mesh build, see their history).
## Caching this in _ready() would silently freeze in the export
## defaults instead of the real configured values. The recompute is
## cheap and this is only ever called from a discrete request_move(),
## never per-frame, so there's no performance reason to cache it either.
func _steps_per_cell() -> Vector3i:
	if step_distance <= 0.0:
		return Vector3i.ONE
	return Vector3i(
		maxi(roundi(cell_size.x / step_distance), 1),
		maxi(roundi(cell_size.y / step_distance), 1),
		maxi(roundi(cell_size.z / step_distance), 1)
	)


## Converts a STEP index (current_step's units) directly to a GridMap
## cell index using exact integer floor division -- no floating-point
## division, no rounding, and therefore no tie to break.
##
## This replaces an entire history of float-based tie-breaking bugs
## (README items 22, 26-29): the previous approach converted a step
## index to a world position (step * step_distance), divided by
## cell_size, and rounded -- and because step_distance is exactly half
## of cell_size in this project's tuning, EVERY OTHER step landed
## exactly on a division tie. Every fix in that history was really
## about which way a specific tie broke (roundi() ties away from zero;
## floori(x+0.5) ties toward the lower cell; an epsilon nudge to dodge
## the tie for movement legality specifically) -- each one correctly
## fixed the case it targeted and then surfaced a DIFFERENT case the
## same way, because floating-point division of an exact ratio still
## produces an exact tie, and any stateless rule for breaking a tie
## favors one side over the other somewhere.
##
## Integer floor division has no such tie: (steps_per_cell) consecutive
## step indices belong to exactly one cell, unambiguously, for every
## sign of step index, with no origin-relative or direction-relative
## asymmetry possible. This is the actual fix for the whole bug class,
## not one more instance of patching it.
func step_to_cell(step: Vector3i) -> Vector3i:
	var per_cell := _steps_per_cell()
	return Vector3i(
		_floor_div(step.x, per_cell.x),
		_floor_div(step.y, per_cell.y),
		_floor_div(step.z, per_cell.z)
	)


## True integer floor division (rounds toward negative infinity),
## unlike GDScript's built-in `/` on ints (rounds toward zero -- e.g.
## -7/2 == -3, not -4). Verified empirically against GDScript's actual
## operator behavior before use, not assumed from another language's
## semantics.
static func _floor_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	var q := a / b
	var r := a - q * b
	if r != 0 and ((r < 0) != (b < 0)):
		q -= 1
	return q


## True integer floor modulo -- always has the same sign as `b` (i.e.
## lands in [0, b) for a positive divisor), unlike GDScript's built-in
## `%` on ints (takes the sign of `a`, e.g. -7 % 2 == -1).
static func _floor_mod(a: int, b: int) -> int:
	return a - _floor_div(a, b) * b


func world_to_step(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		roundi(world_pos.x / step_distance),
		roundi(world_pos.y / step_distance),
		roundi(world_pos.z / step_distance)
	)


func step_to_world(step: Vector3i) -> Vector3:
	return Vector3(step.x * step_distance, step.y * step_distance, step.z * step_distance)


## Snaps a continuous world-space XZ vector to the nearest of the 8 grid
## directions this actor understands (4 cardinal + 4 diagonal -- whether
## a diagonal RESULT is actually accepted as a real MOVE is entirely
## allow_diagonal's call, made inside request_move(); this function just
## reports the nearest grid direction regardless, for any caller that
## needs "which way, roughly, is that point from here" in this actor's
## own direction vocabulary).
##
## Canonical home for this math -- it used to be duplicated privately in
## grid_actor_player_input.gd (which now delegates here instead) and is
## also used by interaction_controller.gd to turn the actor toward
## whatever it's interacting with. One place owns the
## atan2(x, -z) convention (0 deg = world -Z), matching sprite_actor.gd's
## identical convention for displaying it -- the exact kind of
## duplicated-math-that-can-drift this project has been bitten by
## repeatedly (see README items 22-32) is worth avoiding here too, even
## though this particular function is small.
func snap_to_grid_direction(world_delta: Vector3) -> Vector2i:
	if world_delta.length_squared() < 0.0001:
		return Vector2i.ZERO
	var angle_deg := rad_to_deg(atan2(world_delta.x, -world_delta.z))
	var octant := int(round(angle_deg / 45.0))
	octant = ((octant % 8) + 8) % 8
	var dirs: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
	]
	return dirs[octant]


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
## exactly AT a tie (x is a multiple of half a cell). Movement legality
## no longer routes through this function AT ALL for step-lattice
## positions (see step_to_cell() -- exact integer floor division has no
## ties to disagree about in the first place); this float-based version
## remains for genuinely continuous/arbitrary inputs that were never on
## the step lattice to begin with: current_cell() mid-glide, hand-placed
## object positions (chests/plants), the debug overlay's live highlight,
## and interaction_controller.gd's line-of-sight sampling.
##
## ceili(v/cell_size - 0.5), NOT floori(v/cell_size + 0.5) -- an earlier
## version of this function used the floori form, which is correct for
## every NON-tie position but resolves an EXACT tie UPWARD (toward the
## higher cell). step_to_cell() (integer floor division on an exact
## step index) resolves the same tie DOWNWARD -- so the two functions
## silently disagreed about which cell a boundary position belongs to,
## even for the exact same physical point (confirmed: step_to_cell(19)
## == 9, but the old world_to_cell(step_to_world(19)) == world_to_cell(
## 9.5) == 10). Never caused a visible bug on its own (movement
## legality only ever calls step_to_cell(), never this function, for
## deciding what's blocked) -- caught while verifying the doorway-turn
## fix above, where a test read a position back through world_to_cell()
## and got a different cell than the actor's own authoritative
## current_step actually occupied. ceili(v - 0.5) is the exact float
## equivalent of floor_div's tie-breaking (verified: agrees with
## step_to_cell() at every step, not just spot-checked, see
## verify_exhaustive_cell_mapping.gd) -- both now consistently treat a
## boundary as belonging to the LOWER of its two neighboring cells.
func world_to_cell(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		ceili(world_pos.x / cell_size.x - 0.5),
		ceili(world_pos.y / cell_size.y - 0.5),
		ceili(world_pos.z / cell_size.z - 0.5)
	)


func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * cell_size.x, cell.y * cell_size.y, cell.z * cell_size.z)
