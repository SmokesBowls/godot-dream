# tactical_camera.gd
# Godot version: 4.6
#
# A tabletop/tactical camera rig for a Balrum-inspired 3D RPG.
#
# Design intent (from the brief): NOT a third-person over-the-shoulder rig
# (that reads as "Skyrim"), and NOT a locked top-down orthographic rig
# either (that would throw away the verticality -- hills and towers need
# to be able to block line of sight, which only happens if the camera has
# real perspective depth). Instead: a pulled-back, downward-tilted rig
# that orbits a pivot anchored to the player, fully rotatable, with a
# pitch range clamped so it can never flatten out to pure top-down or
# swing down to shoulder-height.
#
# Structure this is meant to be used as:
#   TacticalCameraRig (Node3D)  <- this script
#     Camera3D                  <- @onready-fetched child, does the looking
#
# The rig node is what you position at/above the player (or drive via
# `target`); the Camera3D child is offset back and up from the rig and
# always looks at the rig's origin. Rotating the rig yaws the camera
# around the player; adjusting `pitch_deg` tilts it; adjusting `distance`
# zooms it.

extends Node3D
class_name TacticalCameraRig

# ---------------------------------------------------------------------
# Tuning
# ---------------------------------------------------------------------

## Node whose position the rig follows every frame (typically the player
## root). Left unset, the rig just stays wherever it's placed in the scene.
@export var target: Node3D

## How quickly the rig chases the target's position (0 = snap instantly,
## higher = smoother/laggier). Keeps the framing calm during grid-snapped
## movement instead of jerking a cell at a time.
@export var follow_smoothing := 8.0

## Use an orthographic projection instead of perspective. Orthographic
## gives the flattest, most "readable tabletop" look, closest to Balrum's
## 2D framing, but it also removes the natural occlusion-by-hills effect
## perspective gives you as you rotate outward. Default is off for that
## reason -- flip this on if you want the pure tabletop read instead.
@export var orthographic := false

## Perspective field of view in degrees.
##
## ROOT-CAUSE FINDING (do not lower this range without re-verifying):
## in this project's rendering configuration -- GL Compatibility renderer,
## Godot 4.6.1, tested on an NVIDIA proprietary driver -- assigning
## Camera3D.fov to a value below ~50 corrupts GridMap's rendering.
## GridMap's drawn geometry is replaced by a screen-filling, incorrectly
## depth-written surface that occludes everything behind it (regular
## MeshInstance3D nodes -- the player, chest, plant -- are NOT affected;
## only GridMap-rendered cells are). This was isolated with a
## one-variable-at-a-time bisection against a known-good hand-placed
## Camera3D: identical global_transform, cull_mask, near, far,
## keep_aspect, and environment in both cases -- fov was the only
## differing property. Empirically bounded: fov=50 renders correctly,
## fov=45 is partially corrupted (screen center fails, corners survive),
## fov<=40 is fully corrupted. The mechanism inside GridMap/the renderer
## that makes it fov-sensitive was not identified -- that would require
## reading Godot's C++ GridMap/RenderingServer source, which wasn't
## available here -- but the trigger property, the affected node type,
## and the safe/broken value boundary are confirmed, not guessed.
##
## Fix applied: default and allowed range moved to stay clear of the
## broken zone entirely, rather than clamping at the exact measured
## boundary. If you need a narrower FOV for a tighter tactical frame,
## re-run the bisection (or just eyeball the GridMap floor) before
## lowering this floor -- don't assume the 45-50 gap is safe, it wasn't
## tested.
@export_range(50.0, 75.0) var fov_deg := 55.0

## Orthographic size, only used when `orthographic` is true.
@export_range(4.0, 40.0) var ortho_size := 14.0

## Distance the camera sits back from the rig origin, i.e. zoom level.
@export_range(4.0, 40.0) var distance := 14.0
@export_range(4.0, 40.0) var min_distance := 6.0
@export_range(4.0, 40.0) var max_distance := 28.0
@export var zoom_speed := 1.5
@export var zoom_smoothing := 10.0

## Downward tilt, in degrees. Clamped so the camera can neither go
## shoulder-height (small values) nor pure top-down (90).
@export_range(20.0, 85.0) var pitch_deg := 55.0
@export_range(20.0, 85.0) var min_pitch_deg := 35.0
@export_range(20.0, 85.0) var max_pitch_deg := 80.0

## Yaw around the rig, in degrees. Free to rotate a full circle.
@export var yaw_deg := 0.0
@export var rotate_speed_deg := 90.0

var camera: Camera3D

# Internal smoothed state so zoom/rotate don't cause camera pops when the
# exported values are changed at runtime (e.g. from a settings menu).
var _current_distance: float
var _current_pitch_deg: float

# Change-detection cache: _apply_transform() only touches the Camera3D
# when one of these actually differs from last frame, instead of
# reassigning projection/fov/size and recomputing the transform
# unconditionally on every _process() tick. Camera3D property setters
# aren't free (fov in particular rebuilds the projection matrix), and a
# camera that's sitting still with no target and no input has no reason
# to pay that cost 60+ times a second.
var _applied_orthographic: bool
var _applied_fov_deg := -1.0
var _applied_ortho_size := -1.0
var _applied_rig_position := Vector3.INF
var _applied_yaw_deg := INF
var _applied_pitch_deg := INF
var _applied_distance := INF
var _has_applied := false


func _ready() -> void:
	camera = _find_or_create_camera()
	_current_distance = distance
	_current_pitch_deg = pitch_deg
	_apply_transform()


func _find_or_create_camera() -> Camera3D:
	for child in get_children():
		if child is Camera3D:
			return child
	var cam := Camera3D.new()
	add_child(cam)
	return cam


func _process(delta: float) -> void:
	if target:
		global_position = global_position.lerp(target.global_position, clampf(follow_smoothing * delta, 0.0, 1.0))

	# Continuous key-held rotation. Checked here (once per frame, scaled
	# by delta) rather than in _unhandled_input, which only fires on
	# discrete press/release events and would make rotation feel stepped.
	if Input.is_key_pressed(KEY_Q):
		rotate_by(-rotate_speed_deg * delta)
	if Input.is_key_pressed(KEY_E):
		rotate_by(rotate_speed_deg * delta)

	pitch_deg = clampf(pitch_deg, min_pitch_deg, max_pitch_deg)
	distance = clampf(distance, min_distance, max_distance)

	_current_distance = lerpf(_current_distance, distance, clampf(zoom_smoothing * delta, 0.0, 1.0))
	_current_pitch_deg = lerpf(_current_pitch_deg, pitch_deg, clampf(zoom_smoothing * delta, 0.0, 1.0))

	_apply_transform()


func _apply_transform() -> void:
	if camera == null:
		return

	# Change-detection: skip entirely if nothing this function reads has
	# moved since the last call. `global_position` is the rig's own
	# position (it's what `target` follow updates), so it has to be part
	# of the comparison too -- not just yaw/pitch/distance.
	var unchanged := _has_applied \
		and _applied_orthographic == orthographic \
		and is_equal_approx(_applied_fov_deg, fov_deg) \
		and is_equal_approx(_applied_ortho_size, ortho_size) \
		and _applied_rig_position.is_equal_approx(global_position) \
		and is_equal_approx(_applied_yaw_deg, yaw_deg) \
		and is_equal_approx(_applied_pitch_deg, _current_pitch_deg) \
		and is_equal_approx(_applied_distance, _current_distance)
	if unchanged:
		return

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if orthographic else Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = fov_deg
	camera.size = ortho_size

	var yaw_rad := deg_to_rad(yaw_deg)
	var pitch_rad := deg_to_rad(_current_pitch_deg)

	# Spherical offset behind/above the rig origin: rotate a "straight
	# back" vector by yaw around Y, then tilt it up by pitch.
	var horizontal_dist := _current_distance * cos(pitch_rad)
	var vertical_dist := _current_distance * sin(pitch_rad)
	var offset := Vector3(
		sin(yaw_rad) * horizontal_dist,
		vertical_dist,
		cos(yaw_rad) * horizontal_dist
	)

	camera.position = offset
	camera.look_at(global_position, Vector3.UP)

	_applied_orthographic = orthographic
	_applied_fov_deg = fov_deg
	_applied_ortho_size = ortho_size
	_applied_rig_position = global_position
	_applied_yaw_deg = yaw_deg
	_applied_pitch_deg = _current_pitch_deg
	_applied_distance = _current_distance
	_has_applied = true


# ---------------------------------------------------------------------
# Input -- rebind these calls from your own input-map handling; kept as
# plain methods rather than baked-in _unhandled_input so this rig doesn't
# fight a game that wants to route camera input through an input-buffer
# or context-sensitive control scheme.
# ---------------------------------------------------------------------

func rotate_by(delta_deg: float) -> void:
	yaw_deg = fmod(yaw_deg + delta_deg, 360.0)


func zoom_by(amount: float) -> void:
	distance = clampf(distance + amount * zoom_speed, min_distance, max_distance)


func _unhandled_input(event: InputEvent) -> void:
	# Default mouse-wheel zoom so the rig is drivable out of the box.
	# Remove this (or guard it behind a flag) if your game routes camera
	# input through its own input-map layer instead. Q/E rotation is
	# handled continuously in _process above, not here.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(1.0)
