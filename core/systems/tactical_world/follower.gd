# follower.gd
# Godot version: 4.6
#
# Trailing-step companion AI: drives its own GridActor by literally
# replaying the LEADER's own step history, `trail_steps` moves behind --
# not a distance-chase that picks its own route toward the leader's
# CURRENT position. This is deliberate: the leader has already proven
# every cell in its own path is walkable, so the follower never needs
# to reason about obstacles at all -- it only ever retraces a path that
# is known-good, in the same order the leader walked it (back-and-forth
# included). Kept as a separate Node from GridActor for the same reason
# grid_actor_player_input.gd is separate: GridActor is a dumb movement
# primitive that doesn't care whether a human or an AI is driving it.
#
# HOW THE LAG IS MAINTAINED: every time the leader's GridActor starts a
# step, its direction is pushed onto `_direction_queue`. The follower
# only attempts to consume the OLDEST queued direction once the queue is
# MORE than `trail_steps` deep -- so at rest, exactly `trail_steps`
# directions sit unconsumed in the queue, meaning the follower is always
# that many steps behind, not just spawned there once. Consuming one
# entry (successfully) re-triggers a check for another (via
# move_finished), so a follower that fell behind while the leader kept
# moving catches back up over consecutive frames once the leader stops,
# rather than needing a fresh nudge for every remaining step.
#
# A direction that fails (the follower's own request_move() rejected --
# a real, if unlikely, case: something moved into the path between the
# leader passing through and the follower catching up) is deliberately
# left at the FRONT of the queue, not dropped -- the next trigger (the
# leader's next step) retries the exact same direction rather than
# silently skipping it and drifting off the leader's real path.

extends Node
class_name Follower

## The leader whose step history this follower replays. Typically the
## player's GridActor, but nothing here assumes that -- a follower could
## just as easily trail another NPC.
##
## A property SETTER, not a plain @export -- same ready-order fix this
## project has needed before (sprite_actor.gd's old `actor` setter,
## documented in the tactical_world README): Godot calls a CHILD's
## _ready() before its PARENT's, but the scene script that assigns
## `leader` (tactical_demo_world.gd) is that parent -- so a plain
## `if leader: leader.move_started.connect(...)` inside THIS node's own
## _ready() would run while `leader` is still null, silently connect to
## nothing, and never get a second chance. Connecting from the setter
## instead means it fires whenever `leader` actually arrives, regardless
## of which order that happens to be relative to this node's own
## _ready().
@export var leader: GridActor:
	set(value):
		if leader and leader.move_started.is_connected(_on_leader_move_started):
			leader.move_started.disconnect(_on_leader_move_started)
		leader = value
		if leader:
			leader.move_started.connect(_on_leader_move_started)

## This follower's own GridActor. Auto-detected from the parent node if
## left unset, same convention grid_actor_player_input.gd uses -- attach
## this script as a sibling/child of the GridActor it's meant to drive.
@export var actor: GridActor

## How many of the leader's own steps behind to stay. 2 (not 1) so the
## follower reads as a companion keeping a respectful gap, not glued to
## the leader's heels; tune per-scene feel.
@export_range(1, 10) var trail_steps := 2

var _direction_queue: Array[Vector2i] = []


func _ready() -> void:
	if actor == null:
		actor = get_parent() as GridActor
	if actor:
		actor.move_finished.connect(_on_actor_move_finished)


func _on_leader_move_started(from_step: Vector3i, to_step: Vector3i) -> void:
	var delta := to_step - from_step
	# Cardinal or diagonal, always a unit step per axis -- sign() alone
	# (no normalization) reproduces the leader's exact direction vector,
	# matching the Vector2i(x,z) convention request_move() itself takes.
	_direction_queue.append(Vector2i(signi(delta.x), signi(delta.z)))
	_try_advance()


func _on_actor_move_finished(_step: Vector3i) -> void:
	_try_advance()


func _try_advance() -> void:
	if actor == null or actor.is_moving:
		return
	if _direction_queue.size() <= trail_steps:
		return  # already within the intended lag -- nothing to catch up on
	# Peek, don't pop -- see the file header's note on a failed
	# request_move() staying at the front of the queue for a retry.
	if actor.request_move(_direction_queue[0]):
		_direction_queue.pop_front()
