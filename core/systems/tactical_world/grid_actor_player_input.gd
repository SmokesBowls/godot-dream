# grid_actor_player_input.gd
# Godot version: 4.6
#
# Thin input adapter for GridActor. Kept separate from grid_actor.gd on
# purpose: GridActor is the movement primitive (usable by AI/pathing
# too), this is just the "WASD -> request_move()" wiring for a human
# player. Attach to the same node as GridActor (or set `actor` to it).
#
# Three genuinely separate calculations happen here, in this order --
# conflating any two of them is what caused "pressing Up faces the
# character toward the camera" (fixed in sprite_actor.gd) and "pressing
# Up moves the wrong way after rotating the camera" (fixed here
# previously) if left alone:
#
#   1. INPUT relative to camera: a key press (Up/Down/Left/Right, alone
#      or combined for a diagonal) is a SCREEN-space intent, not a
#      world-space one -- "Up" means "the direction that currently reads
#      as away/up-screen," which is a different world direction
#      depending on where the camera has been rotated to (Q/E). Resolved
#      in _resolve_world_direction() by reading the camera's LIVE
#      transform, not a yaw_deg formula -- self-correcting regardless of
#      how the camera got to wherever it is, same reasoning
#      sprite_actor.gd's camera-relative angle math uses.
#   2. ACCEPTED world-facing direction: GridActor.request_move() takes
#      the resolved world-space direction and is the sole authority on
#      whether it's legal (including whether a diagonal is legal at all
#      -- see allow_diagonal below); GridActor.facing_direction is the
#      result. This file never touches facing_direction directly.
#   3. DISPLAYED sprite direction relative to camera: entirely
#      sprite_actor.gd's concern -- it re-reads facing_direction and the
#      camera independently, every frame. Not this file's problem.
#
# HELD-KEY INPUT MODEL
#
# Movement keys are tracked as continuous held/released state
# (_held_up/_held_down/_held_left/_held_right), not one-shot presses --
# this is what makes holding a direction continue stepping, and what
# lets two keys held together (e.g. Up+Right) resolve to a diagonal
# screen-space intent for free: the held-intent vector is just the sum
# of whichever of the four are currently down, each axis clamped to
# [-1, 1] by construction (opposing keys on the same axis cancel to 0).
#
# Two moments matter:
#   - A held-state CHANGE while the actor is idle attempts a move with
#     the freshly recomputed intent immediately (covers both "a new key
#     was just pressed" and "releasing one key of a blocked diagonal
#     leaves a still-held, still-legal cardinal direction stranded with
#     nothing to wake it back up" -- see the comment on
#     _on_held_state_changed() below for why release also has to check
#     this, not just press).
#   - move_finished (the current step just completed) re-resolves intent
#     from whatever is ACTUALLY held right now, against the LIVE camera,
#     and either continues (held direction), fires the one pending tap
#     (see below), or stops. Never both -- held state takes priority so
#     a tap that arrives mid-glide doesn't cause a duplicate extra step
#     once the key it belongs to is already being held through the next
#     move_finished anyway.
#
# TAP VS. HOLD, AND THE PENDING-TAP SLOT
#
# A tap (pressed and released before the current step finishes) must
# still produce exactly one step once the current glide ends, even
# though the key is no longer held by then. _pending_screen_intent is
# that one-slot memory -- NOT a queue. It's written only when the actor
# is already moving and the recomputed intent is NON-ZERO (a release
# that cancels intent back to zero must NOT overwrite/erase a
# still-pending tap that was set by the press moments earlier -- if
# zero-intent updates were allowed to overwrite it, every tap's own
# release event would immediately erase the tap it just registered).
# Consumed and cleared the instant it's used, so rapid taps collapse to
# "the most recent one survives," never stacking future moves.
#
# A move rejected because the actor was already moving is exactly what
# buffering is FOR (a timing gap, not a real rejection) and is handled
# implicitly by re-resolving at move_finished. A move rejected while the
# actor was already idle (a wall/object, or a disallowed diagonal) was
# refused on its own terms and must never be silently retried later --
# this file never writes _pending_screen_intent in response to a FAILED
# request_move() call, only in response to still-held/newly-changed key
# state. If a held direction is blocked, nothing re-attempts it until
# the held state itself changes again (turn away, or the obstruction
# check would need to pass on its own if re-tried, which this file
# doesn't do automatically).

extends Node
class_name GridActorPlayerInput

@export var actor: GridActor
@export var camera_rig: TacticalCameraRig

## Same default as sprite_actor.gd's OWN jump_key export -- kept as a
## separate export here rather than reading sprite_actor.gd's, since this
## file already doesn't reach into that one for anything else (see the
## header's three-separate-calculations rule) and a per-component key
## export is this project's existing convention (InteractionController.
## interact_key/cancel_key are the same shape). Both listeners fire off
## the SAME physical key press independently -- see _unhandled_input()
## below.
@export var jump_key: Key = KEY_SPACE

var _held_up := false
var _held_down := false
var _held_left := false
var _held_right := false

## One-slot memory for a tap that released before its step finished --
## see the file header. Never a queue; always overwritten wholesale, not
## appended to.
var _pending_screen_intent := Vector2i.ZERO


func _ready() -> void:
	if actor == null:
		actor = get_parent() as GridActor
	if actor:
		actor.move_finished.connect(_on_move_finished)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	var key_event := event as InputEventKey

	# GAMEPLAY half of jump -- see request_jump_step()'s own header on
	# GridActor for what this can and can't do. Deliberately does NOT call
	# get_viewport().set_input_as_handled(): sprite_actor.gd listens for
	# this exact same key, independently, for the purely-visual hop arc
	# (unchanged since before this existed), and both need to see every
	# press -- neither ever marks it handled today.
	if key_event.pressed and key_event.keycode == jump_key:
		_try_jump_step()

	if not _update_held_state(key_event):
		return  # not a tracked movement key -- nothing more to do
	_on_held_state_changed(event.pressed)


func _try_jump_step() -> void:
	if actor == null or actor.is_moving:
		return
	# Jumps toward wherever the actor is currently FACING, not toward
	# whatever movement keys happen to be held -- Space has no directional
	# component of its own, and facing_direction is already the
	# established "which way is this actor oriented" answer everything
	# else in this framework reads (sprite_actor.gd's pose,
	# interaction_controller.gd's turn-to-face). A no-op (nothing to step
	# to/from that way) is silent and expected -- see request_jump_step()'s
	# own doc comment.
	actor.request_jump_step(actor.facing_direction)


## Updates the held/released flag for one of the four tracked movement
## keys. Returns false for any other key so the caller can bail out
## without doing further work.
func _update_held_state(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_W, KEY_UP:
			_held_up = event.pressed
		KEY_S, KEY_DOWN:
			_held_down = event.pressed
		KEY_A, KEY_LEFT:
			_held_left = event.pressed
		KEY_D, KEY_RIGHT:
			_held_right = event.pressed
		_:
			return false
	return true


## Combines the four held flags into a single SCREEN-space intent
## vector, each axis independently clamped to [-1, 1] by construction
## (both keys on an axis held together cancel that axis to 0; this is
## how e.g. Up+Right naturally becomes a diagonal intent without any
## separate diagonal-specific code path here -- the diagonal-vs-cardinal
## decision is made once, later, by GridActor.request_move() itself via
## allow_diagonal).
func _held_screen_intent() -> Vector2i:
	var x := (1 if _held_right else 0) - (1 if _held_left else 0)
	var y := (1 if _held_down else 0) - (1 if _held_up else 0)
	return Vector2i(x, y)


func _on_held_state_changed(was_press: bool) -> void:
	if actor == null:
		return
	var intent := _held_screen_intent()

	# Fires on BOTH press and release, not just press: a press obviously
	# needs this (a brand-new direction while idle should move right
	# away), but so does a release in one specific case -- releasing one
	# key of a blocked diagonal (allow_diagonal=false, or the diagonal
	# cell itself is obstructed) can leave a still-held, still-legal
	# cardinal direction on the table with nothing left to ever attempt
	# it, since the only other trigger (move_finished) never fires
	# because no move ever started. Restricting this to press-only would
	# strand that held key until the player releases and re-presses it
	# for no reason. `was_press` is accepted but currently unused beyond
	# documenting that both cases are deliberately handled the same way.
	if not actor.is_moving and intent != Vector2i.ZERO:
		actor.request_move(_resolve_world_direction(intent))
		# Deliberately RETURNS here instead of also falling through to
		# the pending-store below (a real deviation from this file's
		# earlier pseudocode sketch, which ran both checks
		# unconditionally). A plain tap's own press event both starts
		# the move above AND would satisfy "actor.is_moving" immediately
		# afterward -- storing THIS SAME event's intent into the pending
		# slot too double-books it: the key gets released before the
		# glide ends (that's what makes it a tap), held-intent recomputes
		# to zero at move_finished, and the stale pending then fires an
		# unrequested second step, breaking "a tap produces exactly one
		# step." The pending slot only needs to catch an intent that
		# arrives while a DIFFERENT, already-in-flight move owns
		# is_moving -- which is exactly the branch below, reached only
		# when this event's own intent wasn't the thing that just started
		# a move.
		return

	if actor.is_moving and intent != Vector2i.ZERO:
		_pending_screen_intent = intent


## Stage 1, part B: SCREEN-space intent -> WORLD-space grid direction,
## using the camera's actual current orientation. Works identically for
## a single-axis (cardinal) or two-axis (diagonal) screen intent --
## diagonal support falls out of this being generic vector math, nothing
## diagonal-specific needed here. Falls back to returning screen_dir
## unchanged (old world-fixed behavior) if there's no camera to resolve
## against, rather than failing input entirely.
func _resolve_world_direction(screen_dir: Vector2i) -> Vector2i:
	if camera_rig == null or camera_rig.camera == null:
		return screen_dir

	var cam_forward := -camera_rig.camera.global_transform.basis.z
	cam_forward.y = 0.0
	var cam_right := camera_rig.camera.global_transform.basis.x
	cam_right.y = 0.0
	if cam_forward.length_squared() < 0.0001 or cam_right.length_squared() < 0.0001:
		return screen_dir  # camera looking straight down/up -- no meaningful flat direction
	cam_forward = cam_forward.normalized()
	cam_right = cam_right.normalized()

	# screen_dir.y is negative for "away/up-screen" -- see
	# _held_screen_intent -- so "away" contributes +cam_forward.
	var world := cam_right * float(screen_dir.x) - cam_forward * float(screen_dir.y)
	return _snap_to_grid_direction(world)


## Delegates to GridActor.snap_to_grid_direction() -- this used to
## duplicate that math locally. Centralized there instead (see its doc
## comment) so this file's camera-relative input resolution and
## interaction_controller.gd's "turn to face what you're interacting
## with" can't quietly drift apart from each other. Safe to call
## unconditionally: every call site of this function already guards
## `actor == null` before reaching it (_on_held_state_changed,
## _on_move_finished).
func _snap_to_grid_direction(world: Vector3) -> Vector2i:
	return actor.snap_to_grid_direction(world)


func _on_move_finished(_step: Vector3i) -> void:
	if actor == null:
		return

	# Currently-held state wins over a stale pending tap: if the key is
	# still down, this is a hold-continuation, not a leftover tap.
	var held := _held_screen_intent()
	if held != Vector2i.ZERO:
		_pending_screen_intent = Vector2i.ZERO
		# Re-resolved against the LIVE camera right now, not whatever it
		# was when the key was first pressed -- if the camera rotated
		# (Q/E) during the glide, this step follows the new orientation.
		actor.request_move(_resolve_world_direction(held))
		return

	if _pending_screen_intent != Vector2i.ZERO:
		var tap := _pending_screen_intent
		_pending_screen_intent = Vector2i.ZERO
		actor.request_move(_resolve_world_direction(tap))
		return

	# Neither held nor pending -- locomotion genuinely stops here.
