# sprite_actor.gd
# Godot version: 4.6
#
# Presentation-only billboarded sprite for a GridActor. Reads
# GridActor.facing_direction (authoritative gameplay state, owned by
# GridActor) and the tactical camera's live orientation to pick which
# row/flip of a directional sprite sheet to show. Never writes back to
# movement, collision, or input -- purely visual.
#
# Sprite-sheet convention (reverse-engineered from Godot's official
# "2.5d" demo project's assets/player/player_sprite.gd +
# player_25d.tscn, used here only as a TEMPORARY PROOF ASSET -- see this
# repo's chat history / commit message for the full frame-mapping report
# derived by measuring the actual PNGs and reading vframes off the
# demo's own .tscn, not guessed):
#
#   - vframes=5 (row = one of 5 drawn poses). Frame pixel size is NOT
#     hardcoded -- it's derived per-texture from the actual assigned
#     Texture2D's dimensions (see _update_pixel_size()), because the
#     original 64x64 donor art has since been replaced with larger,
#     less-padded frames (measured: stand.png 100x104/frame, run.png and
#     jump.png 100x100/frame -- not perfectly consistent with each
#     other, which is exactly why this is computed per-texture instead
#     of cached once).
#   - hframes varies per animation: idle=1, run=6.
#   - Row 0 = TOWARD the viewer, row 4 = AWAY from the viewer. Confirmed
#     by reading the donor's own player_math_25d.gd + player_sprite.gd,
#     not assumed: their "move_forward" input drives world -Z and maps
#     to _direction=4; "move_back" drives world +Z and maps to
#     _direction=0. An EARLIER version of this file had these swapped
#     (asserted the labels in a comment instead of checking the donor's
#     source), which was the exact cause of a real reported bug --
#     pressing the "move away from camera" input showed the toward-
#     camera pose. Fixed; see the row/flip table in
#     _direction_to_row_flip() below and don't re-swap it without
#     re-reading the donor source again.
#   - Rows 1/3 are the diagonals: row 1 = toward-ish (has a +Z-world
#     component in the donor's convention), row 3 = away-ish. Row 2 is
#     the pure side profile, mirrored (flip_h) for its opposite side.
#   - KNOWN LIMITATION of this placeholder asset (confirmed by looking
#     at the actual frames, not assumed): rows 0, 1, 3, 4 are nearly
#     visually IDENTICAL in the idle sheet -- this robot doesn't have a
#     distinct back-view pose, only row 2 (true side profile) reads as
#     clearly directional. Replace the art before shipping; the mapping
#     code below is correct regardless of how distinguishable the art is.
#
# The donor demo keyed its rows off raw WORLD movement because its
# camera never rotates. Ours does (Q/E via TacticalCameraRig), so this
# maps CAMERA-RELATIVE facing instead, read live off the camera's actual
# transform each frame (not re-derived from yaw_deg, so it stays correct
# even if the camera is ever driven some other way later).

extends Node3D
class_name SpriteActor

## Plain reference now -- no signal connection needed. Animation state
## used to be driven by GridActor's move_started/move_finished signals
## (which is also why this used to need a setter to dodge Godot's
## children-ready-before-parent ordering), but that had a real, reported
## bug: GridActorPlayerInput ALSO listens to move_finished, and connects
## to it earlier (in its own _ready(), which runs before this node's
## `actor` ever got assigned by the parent scene). Godot delivers a
## signal to listeners in connection order, so on every move_finished,
## GridActorPlayerInput's handler ran first -- and for a held key, it
## calls request_move() again immediately, which SYNCHRONOUSLY emits a
## nested move_started for the next step before this node's OWN
## move_finished handler had even run yet. That handler then fired
## afterward and stomped the just-set "walking" state back to idle for a
## step that was already in flight -- position kept gliding
## (GridActor.is_moving true), but the sprite froze on a static idle
## frame. Reordering connections would only fix it by accident and stay
## fragile. Polling actor.is_moving directly every _process() frame
## (see below) is immune to signal delivery order entirely -- by the
## time this reads it, any same-frame chain of nested request_move()
## calls has already settled, so there's nothing left to race.
@export var actor: GridActor

@export var camera_rig: TacticalCameraRig

@export var idle_texture: Texture2D
@export var run_texture: Texture2D
@export var idle_hframes := 1
@export var run_hframes := 6
## Rows in the sheet (one per facing pose -- see the file header). Same
## for every animation's texture; if that ever stops being true, each
## texture would need its own vframes too, not just its own hframes.
@export var vframes := 5
@export var run_fps := 12.0

## Target world-space height for the sprite -- "roughly the current
## capsule's height" per spec (capsule = 1.6m). Maps the FULL frame
## height to this, per texture (see _pixel_size_for_current_texture()) --
## the drawn character has some padding inside the frame so its apparent
## height ends up a bit under 1.6m -- close enough for "roughly", called
## out here rather than left to be discovered.
@export var target_height := 1.6

var sprite: Sprite3D

## Mirrors actor.is_moving, polled once per frame -- see the `actor`
## comment above for why this is polled instead of signal-driven.
var _was_moving := false
var _run_progress := 0.0
var _current_row := 0
var _current_flip := false


func _ready() -> void:
	sprite = Sprite3D.new()
	sprite.vframes = vframes
	sprite.hframes = idle_hframes
	sprite.texture = idle_texture
	sprite.frame = 0

	# Y-locked billboard, not full billboard: keeps the character
	# standing vertically upright as the camera orbits/tilts. Full
	# billboard rotates on every axis to face the camera dead-on, which
	# would make a standing sprite lean/tilt with the camera's pitch --
	# wrong for a character that should always read as "standing up."
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y

	# Pixel art: no filtering, no mipmaps. Mipmaps blur even with
	# nearest-neighbor sampling active, because the blur happens when
	# picking WHICH mip level to sample, not in how that level is
	# sampled -- TEXTURE_FILTER_NEAREST (not the _WITH_MIPMAPS variant)
	# is what actually avoids it.
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_update_pixel_size()

	# Sprite3D centers its texture on its own node by default. Shift up
	# by half the resulting world-space frame height so the sprite's
	# BOTTOM edge (the feet) lands at this node's origin -- which sits
	# at VisualRoot's origin, which sits at the CharacterBody3D's own
	# ground-level origin (local y=0, same point the collision shape and
	# capsule mesh are built around). Safe to set once here (not
	# recomputed alongside pixel_size) because _update_pixel_size()
	# guarantees the rendered frame is ALWAYS exactly target_height tall
	# regardless of which texture is active -- this offset only depends
	# on target_height, never on the texture's raw pixel dimensions.
	sprite.position = Vector3(0, target_height * 0.5, 0)

	add_child(sprite)
	# No signal connection here -- see the `actor` setter above for why.


## Recomputes pixel_size from WHATEVER texture is currently assigned, so
## target_height always applies to that texture's REAL per-frame pixel
## height -- not a hand-maintained frame_size export that can silently
## drift out of sync with the actual art. That drift is a real, reported
## bug: an earlier version of this file hardcoded 64x64 frames and was
## never updated when the sprite sheets were upscaled to ~100px frames,
## which rendered every frame ~1.56x too tall. Feet sank through the
## floor, and raising the node to compensate just pushed the
## now-oversized head out of the camera's normal framing instead of
## fixing the actual problem -- the sprite itself was the wrong size, no
## amount of repositioning fixes that. Different textures in this set
## aren't even guaranteed to share an exact per-frame height (measured:
## stand.png is 104px/frame, run.png and jump.png are 100px/frame -- a
## small, likely-unintentional mismatch in the art, not assumed to be
## zero) -- recomputing per texture, on every swap, absorbs that instead
## of silently applying idle's ratio to run's frames.
func _update_pixel_size() -> void:
	if sprite.texture == null:
		return
	var frame_h := sprite.texture.get_height() / float(vframes)
	if frame_h <= 0.0:
		return
	sprite.pixel_size = target_height / frame_h


func _process(delta: float) -> void:
	if actor == null:
		return

	var row_flip := _direction_to_row_flip(actor.facing_direction)
	_current_row = row_flip.x
	_current_flip = row_flip.y == 1
	sprite.flip_h = _current_flip

	var is_moving_now := actor.is_moving

	# Transition edges only, not level checks -- a consecutive step (the
	# common held-key case) sees is_moving true on BOTH the frame before
	# and after the step boundary (GridActor's own move_finished ->
	# request_move() sequence never lets is_moving observably go false
	# in between, see grid_actor_player_input.gd), so this branch simply
	# doesn't fire again for it. That's the actual fix for "run
	# animation restarts/freezes on consecutive steps": _run_progress and
	# the run texture are only touched here, on a genuine idle->moving
	# edge, never on every step.
	if is_moving_now and not _was_moving:
		_run_progress = 0.0
		sprite.texture = run_texture
		sprite.hframes = run_hframes
		_update_pixel_size()  # run_texture's own per-frame height, not idle's
	elif not is_moving_now and _was_moving:
		sprite.texture = idle_texture
		sprite.hframes = idle_hframes
		_update_pixel_size()
	_was_moving = is_moving_now

	if is_moving_now:
		# Animation timing (run_fps) is intentionally independent of
		# GridActor.move_duration -- the step glide and the leg-cycle
		# framerate are different concerns and shouldn't be coupled just
		# because they happen to run concurrently. Progress accumulates
		# continuously across step boundaries (never reset except on the
		# idle->moving edge above), which is what makes one held-run
		# session read as one continuous locomotion cycle instead of a
		# per-step restart.
		_run_progress = fmod(_run_progress + run_fps * delta, float(run_hframes))
		sprite.frame = _current_row * run_hframes + int(_run_progress)
	else:
		sprite.frame = _current_row * idle_hframes  # idle_hframes is always 1 -- column 0


## Buckets the actor's world-space facing direction into 8 compass
## sectors RELATIVE TO THE CAMERA'S CURRENT FORWARD DIRECTION, then maps
## each sector to (row, flip_h). Returns Vector2i(row, flip_h as 0/1).
##
## angle convention: 0 deg = facing directly away from the camera (into
## the screen), 180 deg = facing directly toward the camera. Which
## physical side flip_h=true represents is an arbitrary-but-consistent
## choice (the donor demo's own left/right convention doesn't carry any
## meaning here -- it was built for a fixed camera we don't use) --
## verified by screenshot that it doesn't read as mirrored-backwards,
## not just asserted.
func _direction_to_row_flip(direction: Vector2i) -> Vector2i:
	if direction == Vector2i.ZERO:
		return Vector2i(4, 0)  # arbitrary default -- away pose, matches bucket 0 below

	var world_angle := rad_to_deg(atan2(float(direction.x), -float(direction.y)))

	var camera_forward_angle := 0.0
	if camera_rig and camera_rig.camera:
		var fwd := -camera_rig.camera.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.0001:
			fwd = fwd.normalized()
			camera_forward_angle = rad_to_deg(atan2(fwd.x, -fwd.z))

	var relative := fmod(world_angle - camera_forward_angle + 360.0, 360.0)
	var bucket := int(round(relative / 45.0)) % 8

	# Row numbers here match the donor asset's own semantics (row 0 =
	# toward viewer, row 4 = away, row 1 = toward-diagonal, row 3 =
	# away-diagonal -- see the file header) applied to CAMERA-RELATIVE
	# buckets instead of the donor's raw world-space ones.
	match bucket:
		0: return Vector2i(4, 0)  # facing away from camera
		1: return Vector2i(3, 1)  # away-ish diagonal
		2: return Vector2i(2, 1)  # camera-relative right, side profile
		3: return Vector2i(1, 1)  # toward-ish diagonal
		4: return Vector2i(0, 0)  # facing toward camera
		5: return Vector2i(1, 0)  # toward-ish diagonal
		6: return Vector2i(2, 0)  # camera-relative left, side profile
		7: return Vector2i(3, 0)  # away-ish diagonal
	return Vector2i(4, 0)
