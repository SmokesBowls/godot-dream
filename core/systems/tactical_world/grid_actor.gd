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
# from `cell_size` (used only to translate a world position into a
# GridMap-shaped cell coordinate for callers that want one, e.g.
# InteractionController's cell-adjacency check -- see below). They
# don't have to match: step_distance smaller than cell_size gives finer
# movement resolution -- e.g. cell_size=1.0m, step_distance=0.5m means
# two key presses cross one tactical grid cell -- without changing the
# grid walls and props are laid out on.
#
# Attach to a CharacterBody3D. Does not read input directly -- call
# request_move(direction) from a player-input script (or an AI/pathing
# script for NPCs), so the same component drives both.
#
# OBSTRUCTION IS DECIDED BY REAL PHYSICS NOW, NOT GRID MATH -- a
# structural rewrite, not one more patch on the previous approach. See
# the long comment on request_move()/_is_step_obstructed() below for
# what changed and why; the short version: the grid still answers
# "where would this step land" (step_to_world()/current_step below),
# but no longer answers "is that landing spot solid" -- a
# PhysicsDirectSpaceState3D.intersect_shape() query, cast with this
# actor's own real collision shape at the exact destination, answers
# that instead. This project's entire prior collision-bug lineage
# (README items 22-32, 36 -- half-step boundary ties, corner-safety
# probes, the "Apple Problem" footprint math) was fundamentally about
# reasoning over integer cell/step LATTICE positions as a stand-in for
# real geometry; a real shape-vs-shape overlap query at a real world
# position has no lattice to tie-break on in the first place.

extends CharacterBody3D
class_name GridActor

## Godot physics layer (1-indexed, matching the Project Settings /
## collision_layer picker) that wall/world-geometry obstruction bodies
## live on. Layer 1 is left alone for "everything default" (the
## player's own body, floor/ground meshes used by ground_shadow.gd's
## raycast, general visuals) -- this is just the first layer number
## this framework claims for its own use, a convention, not something
## Godot requires.
const WALL_COLLISION_LAYER_BIT := 2

## Physics layer solid Interactable objects (chests, plants, small
## props) build their own auto-generated collision on -- see
## Interactable._build_collision_body(). Kept SEPARATE from the wall
## layer specifically so `check_object_collision` (below) can mask
## objects out of an actor's obstruction query without also blinding it
## to real walls; an NPC that's allowed to walk through furniture still
## has to stop at a wall.
const OBJECT_COLLISION_LAYER_BIT := 3

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

## World-space size of a GridMap cell, for callers that want to talk in
## cell units (InteractionController's cell-adjacency range check,
## current_cell()/cell_to_world() below). NOT used for obstruction
## anymore -- see the file header. Must match the actual GridMap's
## `cell_size` (X/Z; Y is irrelevant here since this actor never steps
## vertically) for those callers to agree with the visual layout.
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

## If true (the default), a move's obstruction query includes the
## OBJECT_COLLISION_LAYER_BIT layer, so solid Interactables (chests,
## plants, ...) block this actor same as a wall. Set false to opt an
## individual actor out (e.g. an NPC that's allowed to walk through
## furniture) without touching the objects themselves -- the WALL
## layer is never excluded regardless of this flag.
@export var check_object_collision := true

## Maximum height (meters) request_jump_step() below will step UP or DOWN
## in one press. Bounds this to short ledges deliberately -- see
## request_jump_step()'s own header for the fuller reasoning; this is not
## a general climbing/verticality system, just enough to cross a ledge
## roughly knee-to-thigh height.
@export var max_step_height := 1.0

## Discrete position, measured in `step_distance` units -- NOT GridMap
## cells. With sub-cell stepping this is finer than the tactical grid
## (e.g. two step values per cell_size), so it deliberately isn't named
## current_cell anymore: after an odd number of steps the actor can sit
## exactly on a cell boundary, which has no single "current cell." Use
## `current_cell()` below when you need the GridMap cell under the
## actor's actual position instead.
var current_step: Vector3i
var is_moving := false

## World-space Y this actor is currently standing at. 0.0 (the default)
## everywhere in the world except while standing on a Ledge (see
## ledge.gd) -- the ONLY thing that ever changes this is
## request_jump_step() below; request_move() (plain WASD) reads it but
## never writes it, so ordinary movement is byte-identical to before
## this existed anywhere `current_ground_height` stays at its default.
var current_ground_height := 0.0

## The Ledge this actor is currently standing on, or null if it's on the
## base floor. Tracked explicitly (not re-derived from
## current_ground_height, which is just a float) so request_move() can
## ask "am I still inside THIS SAME ledge's footprint" -- see its own
## comment for why leaving a ledge's footprint requires a deliberate
## jump, not a walk.
var _current_ledge: Ledge = null

## Authoritative world-facing direction, in the same XZ direction units
## request_move() takes (e.g. Vector2i(0,-1) = north). Updated whenever a
## move is ACCEPTED, and ALSO on a REJECTED move caused by an
## OBSTRUCTION (a wall or solid object) -- see face_direction() and the
## calls to it inside request_move() below. Real, reported problem this
## fixed: walk up to a wall, stop, press a direction into it, and the
## character just kept facing wherever it already was, which reads as
## the game not having heard the input at all. Bumping into something
## now visibly turns the character toward it; it still doesn't MOVE
## there.
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
## for an obstructed attempt; and interaction_controller.gd's
## begin_interaction(), which turns the actor to face whatever it just
## started interacting with even though it never moved a step to reach
## it.
func face_direction(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO or direction == facing_direction:
		return
	facing_direction = direction
	facing_changed.emit(direction)


var _move_from: Vector3
var _move_to: Vector3
var _move_t := 0.0

## The Shape3D actually used to probe for obstruction, and its local
## offset from this actor's own origin -- read once, in _ready(), from
## this node's own first CollisionShape3D child (the same shape already
## authoritative for this actor's real physics body). Querying with the
## actor's OWN real shape, rather than a synthetic point or box, is
## what makes the corner-safety-probe machinery the old grid-cell
## version needed (README item 32) unnecessary: a real shape-vs-shape
## overlap test at the destination already answers "does MY actual body
## fit there," including partial corner overlaps, without enumerating
## neighbor cells by hand.
var _probe_shape: Shape3D
var _probe_local_offset := Vector3.ZERO


func _ready() -> void:
	current_step = world_to_step(global_position)
	global_position = step_to_world(current_step)
	_find_probe_shape()


## Deliberately NOT exported as its own field to hand-configure -- this
## actor's obstruction probe should always match whatever shape this
## CharacterBody3D is ACTUALLY built from, or "am I blocked" and "what
## the physics engine already thinks my body occupies" could silently
## disagree, the exact class of two-sources-of-truth bug this project's
## whole collision history (README items 22-36) kept finding in other
## forms.
func _find_probe_shape() -> void:
	for child in get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			var shape_node := child as CollisionShape3D
			_probe_shape = shape_node.shape
			_probe_local_offset = shape_node.position
			return
	push_warning("GridActor (%s): no CollisionShape3D child with a shape assigned -- obstruction queries have nothing to probe with, every move will be accepted unconditionally." % name)


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
## Operates at `current_ground_height` -- unchanged (always 0.0) unless
## request_jump_step() below has put the actor on a Ledge. While ON a
## ledge, this ALSO refuses to step outside that ledge's footprint (same
## rejection shape as an obstruction: face the direction, don't move) --
## leaving a ledge is request_jump_step()'s job specifically, so this
## never silently walks the actor off an edge into open air with no
## floor under it.
func request_move(direction: Vector2i) -> bool:
	if is_moving:
		return false
	if direction == Vector2i.ZERO:
		return false
	if not allow_diagonal and direction.x != 0 and direction.y != 0:
		return false

	var target_step := current_step + Vector3i(direction.x, 0, direction.y)

	if _current_ledge != null:
		var target_world := step_to_world(target_step)
		if not _current_ledge.contains_xz(Vector2(target_world.x, target_world.z)):
			face_direction(direction)
			move_blocked.emit(target_step)
			return false

	if _is_step_obstructed(target_step):
		face_direction(direction)
		move_blocked.emit(target_step)
		return false

	_move_from = global_position
	_move_to = step_to_world(target_step)
	_move_to.y = current_ground_height
	_move_t = 0.0
	is_moving = true
	face_direction(direction)

	move_started.emit(current_step, target_step)
	current_step = target_step
	return true


## JUMP-triggered step (bound to the jump key in
## grid_actor_player_input.gd, alongside sprite_actor.gd's independent,
## purely-visual jump arc -- see that file's header for why both listen
## to the same key separately). This is the ONLY function that ever
## changes current_ground_height/global_position.y -- request_move()
## above only ever READS current_ground_height, never writes it.
##
## Deliberately narrow, not a general climb/verticality system: from the
## base floor, this can step UP onto a Ledge directly ahead if its
## height is within max_step_height and there's room to stand on it; from
## ON a Ledge, it can only step back DOWN to the base floor, and only by
## stepping outside that ledge's own footprint (still within
## max_step_height, which should always hold since the same check gated
## the way up). Ledge-to-ledge hops and multi-story stacks are NOT
## supported -- there's exactly one ledge in this framework right now
## (the demo jump-test platform) and no design yet for stacking more than
## one, so this doesn't guess at that shape.
##
## Returns false, doing nothing, whenever there's nothing to step
## to/from at `direction` -- the caller (grid_actor_player_input.gd)
## treats that as "this jump was purely cosmetic," unchanged from before
## this function existed, since jump still needs to do nothing positional
## on flat open ground.
func request_jump_step(direction: Vector2i) -> bool:
	if is_moving or direction == Vector2i.ZERO:
		return false

	var target_step := current_step + Vector3i(direction.x, 0, direction.y)
	var target_world := step_to_world(target_step)
	var target_xz := Vector2(target_world.x, target_world.z)

	if _current_ledge == null:
		var ledge := _ledge_at_xz(target_xz)
		if ledge == null:
			return false  # nothing to step onto -- fall back to the cosmetic arc
		var height_delta := ledge.height - current_ground_height
		if height_delta <= 0.001 or height_delta > max_step_height + 0.001:
			return false  # not actually higher, or too high to step up
		if _is_step_obstructed_at(target_step, ledge.height):
			return false  # something's in the way up there too
		_begin_elevated_move(target_step, ledge.height, direction)
		_current_ledge = ledge
		return true
	else:
		if _current_ledge.contains_xz(target_xz):
			return false  # still inside the same ledge -- request_move()'s job, not a jump
		if _is_step_obstructed_at(target_step, 0.0):
			return false
		_begin_elevated_move(target_step, 0.0, direction)
		_current_ledge = null
		return true


func _begin_elevated_move(target_step: Vector3i, new_ground_height: float, direction: Vector2i) -> void:
	_move_from = global_position
	_move_to = step_to_world(target_step)
	_move_to.y = new_ground_height
	_move_t = 0.0
	is_moving = true
	current_ground_height = new_ground_height
	face_direction(direction)

	move_started.emit(current_step, target_step)
	current_step = target_step


## Every Ledge in the "ledge" group whose footprint contains `world_xz`.
## Linear scan, not spatially indexed -- there's exactly one Ledge in
## this framework right now; revisit if that ever stops being true.
func _ledge_at_xz(world_xz: Vector2) -> Ledge:
	for node in get_tree().get_nodes_in_group(Ledge.LEDGE_GROUP):
		var ledge := node as Ledge
		if ledge and ledge.contains_xz(world_xz):
			return ledge
	return null


## True if this actor's own probe shape, placed exactly at `target_step`'s
## world position AT `current_ground_height`, overlaps ANYTHING on the
## obstruction layers (walls always; solid Interactables too, unless
## check_object_collision is false) -- one native physics query, no
## grid-cell math at all. Thin wrapper over _is_step_obstructed_at() below
## fixed to the actor's OWN current height, which is what every existing
## caller (request_move()) wants; request_jump_step() calls
## _is_step_obstructed_at() directly since it needs to probe a height the
## actor ISN'T at yet.
##
## `intersect_shape(..., 1)` asks for at most one result, deliberately:
## this only ever needs a yes/no answer, never WHAT was hit or how many
## things overlap -- asking for more would just be discarded work.
func _is_step_obstructed(target_step: Vector3i) -> bool:
	return _is_step_obstructed_at(target_step, current_ground_height)


func _is_step_obstructed_at(target_step: Vector3i, height: float) -> bool:
	if _probe_shape == null:
		return false  # nothing to probe with -- see _find_probe_shape()'s warning
	var space := get_world_3d().direct_space_state
	if space == null:
		return false

	var pos := step_to_world(target_step)
	pos.y = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe_shape
	query.transform = Transform3D(Basis(), pos + _probe_local_offset)
	query.collision_mask = _obstruction_collision_mask()
	query.exclude = [get_rid()]
	return not space.intersect_shape(query, 1).is_empty()


## Recomputed fresh on every call rather than cached -- same reasoning
## this file already used for _steps_per_cell() before it was removed:
## check_object_collision can change at runtime (a designer/AI system
## toggling it on an NPC), and this is only ever called once per
## discrete request_move(), never per-frame, so there's no real cost to
## recomputing it.
func _obstruction_collision_mask() -> int:
	var mask := 1 << (WALL_COLLISION_LAYER_BIT - 1)
	if check_object_collision:
		mask |= 1 << (OBJECT_COLLISION_LAYER_BIT - 1)
	return mask


## The GridMap-shaped cell the actor's actual current position falls
## into. Computed on demand rather than cached, since it's a different
## lattice than `current_step` and only some callers need it (right now:
## InteractionController's cell-adjacency check). Uses world_to_cell()
## (float-based) rather than an exact step-to-cell conversion, since
## global_position is only guaranteed to sit exactly on the step
## lattice while idle -- mid-glide it's a genuinely continuous
## interpolated position (see _physics_process()).
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


## Snaps a continuous world-space XZ vector to the nearest of the 8 grid
## directions this actor understands (4 cardinal + 4 diagonal -- whether
## a diagonal RESULT is actually accepted as a real MOVE is entirely
## allow_diagonal's call, made inside request_move(); this function just
## reports the nearest grid direction regardless, for any caller that
## needs "which way, roughly, is that point from here" in this actor's
## own direction vocabulary).
##
## Canonical home for this math -- used by grid_actor_player_input.gd
## and interaction_controller.gd (to turn the actor toward whatever it's
## interacting with). One place owns the atan2(x, -z) convention (0 deg
## = world -Z), matching sprite_actor.gd's identical convention for
## displaying it.
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
## AWAY FROM ZERO, which for EACH cell means it owns whichever boundary
## happens to face the coordinate ORIGIN and loses whichever boundary
## faces away from it. ceili(v/cell_size - 0.5) gives every cell a
## uniform, origin-independent span instead, and agrees with the exact
## integer step-lattice tie-breaking this project settled on before the
## obstruction system stopped needing an exact-integer path at all (see
## README items 26 and 31 for the full history) -- kept exactly as
## before since callers of THIS function (current_cell(), the debug
## overlay, interaction line-of-sight) still work with continuous,
## non-lattice positions where a consistent tie-break still matters.
func world_to_cell(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		ceili(world_pos.x / cell_size.x - 0.5),
		ceili(world_pos.y / cell_size.y - 0.5),
		ceili(world_pos.z / cell_size.z - 0.5)
	)


func cell_to_world(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * cell_size.x, cell.y * cell_size.y, cell.z * cell_size.z)
