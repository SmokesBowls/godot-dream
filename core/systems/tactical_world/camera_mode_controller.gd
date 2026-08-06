# camera_mode_controller.gd
# Godot version: 4.6
#
# Three camera modes. Keys are F1/F2/F3, NOT literal "1"/"2"/"3" -- those
# digits are already the hotbar slots (core/ui/hotbar/), so binding
# camera toggles there would fire both at once. Substituted deliberately,
# flagged here rather than guessed silently -- rebind via the exports
# below if F1-F3 collide with something else later.
#
#   F1 BEHIND_SPRITE -- camera actively re-aligns to sit behind wherever
#     the player is CURRENTLY FACING, smoothly following as they turn.
#     This is the one place in the whole framework allowed to
#     auto-rotate the camera from player movement. Everywhere else --
#     grid_actor_player_input.gd's camera-relative input resolution in
#     particular -- must NOT do this, and doesn't (verified: GridActor
#     never touches TacticalCameraRig.yaw_deg anywhere).
#   F2 LOCKED (default) -- camera yaw only changes from explicit Q/E
#     input. This is the rig's own baseline behavior; this mode does
#     nothing extra, it just means "don't run the other two." Starting
#     mode on purpose, so out of the box nothing auto-rotates the camera.
#   F3 TOP_DOWN -- quick near-top-down glance. TacticalCameraRig's pitch
#     is deliberately clamped elsewhere in this project (35-80 deg)
#     specifically to keep it from flattening to pure top-down (see its
#     own doc comment on why -- hill/tower sight-blocking needs real
#     perspective depth). This mode is a deliberate, explicit override of
#     that constraint for a quick tactical glance, not a loophole in it:
#     it temporarily widens max_pitch_deg just enough to reach
#     top_down_pitch_deg while active, and restores the rig's original
#     values exactly on leaving the mode.

extends Node
class_name CameraModeController

enum Mode { LOCKED, BEHIND_SPRITE, TOP_DOWN }

@export var camera_rig: TacticalCameraRig
@export var player: GridActor

@export var behind_turn_speed_deg := 240.0
## Not literally 90 -- see the file header on why pure top-down is
## avoided even here (a camera looking exactly straight down also makes
## TacticalCameraRig's look_at degenerate, same reason its pitch clamp
## stops short of 90 by default).
@export_range(70.0, 89.0) var top_down_pitch_deg := 85.0

@export var toggle_behind_key: Key = KEY_F1
@export var toggle_locked_key: Key = KEY_F2
@export var toggle_top_down_key: Key = KEY_F3

var mode: Mode = Mode.LOCKED

var _saved_pitch_deg := 0.0
var _saved_max_pitch_deg := 0.0
var _top_down_active := false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == toggle_behind_key:
		_set_mode(Mode.BEHIND_SPRITE)
		get_viewport().set_input_as_handled()
	elif event.keycode == toggle_locked_key:
		_set_mode(Mode.LOCKED)
		get_viewport().set_input_as_handled()
	elif event.keycode == toggle_top_down_key:
		_set_mode(Mode.TOP_DOWN)
		get_viewport().set_input_as_handled()


func _set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	if mode == Mode.TOP_DOWN:
		_exit_top_down()
	mode = new_mode
	if mode == Mode.TOP_DOWN:
		_enter_top_down()


func _enter_top_down() -> void:
	if camera_rig == null:
		return
	_saved_pitch_deg = camera_rig.pitch_deg
	_saved_max_pitch_deg = camera_rig.max_pitch_deg
	camera_rig.max_pitch_deg = maxf(camera_rig.max_pitch_deg, top_down_pitch_deg)
	camera_rig.pitch_deg = top_down_pitch_deg
	_top_down_active = true


func _exit_top_down() -> void:
	if camera_rig == null or not _top_down_active:
		return
	camera_rig.pitch_deg = _saved_pitch_deg
	camera_rig.max_pitch_deg = _saved_max_pitch_deg
	_top_down_active = false


func _process(delta: float) -> void:
	if mode != Mode.BEHIND_SPRITE or camera_rig == null or player == null:
		return
	if player.facing_direction == Vector2i.ZERO:
		return
	# Camera forward should match the player's facing direction (not the
	# opposite) -- the camera then sits on the far side of its own
	# forward vector, i.e. behind the player relative to where they're
	# facing. Same atan2(x,-z)=0-at-north convention as
	# grid_actor_player_input.gd's _snap_to_grid_direction and
	# sprite_actor.gd's world_angle, negated because we're solving for
	# where the CAMERA must sit, not which way an input vector points.
	var target_yaw := rad_to_deg(atan2(-float(player.facing_direction.x), -float(player.facing_direction.y)))
	camera_rig.yaw_deg = _step_angle_deg(camera_rig.yaw_deg, target_yaw, behind_turn_speed_deg * delta)


## Moves `current` toward `target` by at most `max_delta` degrees, always
## taking the SHORTER angular path (never spinning the long way around
## through the 0/360 seam).
func _step_angle_deg(current: float, target: float, max_delta: float) -> float:
	var diff := fmod(target - current + 540.0, 360.0) - 180.0  # shortest signed difference, (-180, 180]
	if absf(diff) <= max_delta:
		return fmod(target + 360.0, 360.0)
	return fmod(current + sign(diff) * max_delta + 360.0, 360.0)
