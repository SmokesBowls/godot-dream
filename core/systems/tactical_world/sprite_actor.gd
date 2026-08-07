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

## Plain reference (no setter) -- ANIMATION state specifically stays
## poll-driven, not signal-driven, for a real, previously-reported
## reason: animation state used to be driven by GridActor's
## move_started/move_finished signals, but GridActorPlayerInput ALSO
## listens to move_finished and connects to it earlier (in its own
## _ready(), which runs before this node's `actor` ever got assigned by
## the parent scene) -- Godot delivers a signal to listeners in
## connection order, so on every move_finished, GridActorPlayerInput's
## handler ran first, and for a held key it calls request_move() again
## immediately, which SYNCHRONOUSLY emits a nested move_started for the
## next step before this node's OWN move_finished handler had even run
## yet. That handler then fired afterward and stomped the just-set
## "walking" state back to idle for a step already in flight -- the
## sprite froze on a static idle frame while position kept gliding.
## Polling actor.is_moving directly every _process() frame (see below)
## is immune to signal delivery order entirely.
##
## A DIFFERENT signal (facing_changed) IS connected now, lazily, on the
## first _process() call once `actor` is non-null (see
## _facing_signal_connected below) -- that one doesn't have the ordering
## problem above (nothing else double-fires it), and exists to solve a
## separate, real problem: the game can be PAUSED (an interaction panel
## open) while facing still needs to visibly update, and _process()
## itself doesn't run at all while paused. Signal delivery isn't gated
## by process_mode/pause the way _process() is, so this still reaches
## the sprite even then.
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

## The donor asset's jump.png -- copied into this project early on but
## explicitly left unwired ("Do not add jumping yet"). 200x500 actual
## (measured, not the stale 128x320 the asset README used to claim --
## it got upscaled along with stand.png/run.png and the note was never
## updated): 2 columns x 5 rows at 100x100/frame, same vframes=5 facing
## convention as everything else here. Purely cosmetic -- see
## _start_jump()'s doc comment for why this never touches GridActor.
@export var jump_texture: Texture2D
@export var jump_hframes := 2
@export var jump_key: Key = KEY_SPACE
## Seconds for one full hop, rise + fall.
@export var jump_duration := 0.5
## Peak visual height of the hop, in meters -- purely a Sprite3D offset,
## never GridActor.global_position.y (which stays 0 always; this actor
## never steps vertically). About a quarter of target_height -- visible
## without reading as cartoonish.
@export var jump_height := 0.4

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

## Lazily connected the first time _process() sees a non-null `actor`
## (same ready-order reasoning as the old setter, minus the
## connect/disconnect churn -- actor is only assigned once
## tactical_demo_world.gd's _ready() runs, strictly after this node's
## own _ready(), see the `actor` comment above). Deliberately a SEPARATE
## signal connection from the poll-driven animation state above, not a
## replacement for it -- see facing_changed's doc comment on GridActor
## for why: this is what lets the character visually turn to face an
## interaction target WHILE the game is paused for it, since a signal
## fires synchronously regardless of process_mode/pause, but _process()
## itself does not run at all while paused.
var _facing_signal_connected := false

## Jump state -- see _start_jump()/_process_jump() below. Deliberately
## separate from is_moving/_was_moving above: a jump can happen while
## idle OR while walking, and must not disturb the run-cycle bookkeeping
## either way (see _process_jump()'s doc comment for exactly how that's
## kept safe).
var _is_jumping := false
var _jump_t := 0.0


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
	# No signal connection here -- `actor` isn't assigned yet at this
	# point (see the `actor` comment above); facing_changed gets
	# connected lazily from _process() once it is.


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

	if not _facing_signal_connected:
		actor.facing_changed.connect(_on_facing_changed)
		_facing_signal_connected = true

	_update_facing_pose()

	var is_moving_now := actor.is_moving
	var just_started_moving := is_moving_now and not _was_moving
	var just_stopped_moving := not is_moving_now and _was_moving
	_was_moving = is_moving_now

	# Progress bookkeeping ALWAYS runs, even mid-jump -- this is timer
	# state, not a display write, so it's always safe (see the DISPLAY
	# write guard below for what specifically isn't).
	if just_started_moving:
		_run_progress = 0.0
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

	# The actual DISPLAYED texture/hframes/frame are a different story
	# from the bookkeeping above -- these are skipped ENTIRELY while a
	# jump is playing, not just planned-to-be-overwritten-later. Real
	# bug, caught by actually running it: Sprite3D.frame validates
	# bounds on EACH assignment independently, not just the last one in
	# a frame -- setting `sprite.frame = row*run_hframes+n` here while
	# `sprite.hframes` is still stuck at jump_hframes (2) from the
	# previous frame's jump override is already out of range the moment
	# it's assigned, even though _process_jump() below would have
	# corrected hframes moments later in the same frame. Skipping this
	# block entirely while _is_jumping avoids ever producing that
	# invalid intermediate value; _process_jump()'s landing branch
	# explicitly hands back a correct, matching (hframes, frame) pair
	# in one shot instead of relying on this block to catch up.
	if not _is_jumping:
		if just_started_moving:
			sprite.texture = run_texture
			sprite.hframes = run_hframes
			_update_pixel_size()  # run_texture's own per-frame height, not idle's
		elif just_stopped_moving:
			sprite.texture = idle_texture
			sprite.hframes = idle_hframes
			_update_pixel_size()

		if is_moving_now:
			sprite.frame = _current_row * run_hframes + int(_run_progress)
		else:
			sprite.frame = _current_row * idle_hframes  # idle_hframes is always 1 -- column 0

	_process_jump(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == jump_key:
		_start_jump()


## Purely cosmetic -- never touches GridActor, current_step, is_moving,
## or collision in any way. This actor's actual grid position never
## leaves y=0; the hop is a Sprite3D-local Y offset only, exactly the
## same "presentation never writes back to gameplay" boundary
## sprite_actor.gd has kept everywhere else. Ignored while already
## jumping (no re-triggering/stacking mid-air) and if no jump_texture is
## assigned (so an unconfigured actor just doesn't respond to the key,
## rather than erroring).
func _start_jump() -> void:
	if _is_jumping or jump_texture == null:
		return
	_is_jumping = true
	_jump_t = 0.0
	sprite.texture = jump_texture
	sprite.hframes = jump_hframes
	# hframes and frame are set TOGETHER, deliberately -- changing one
	# without the other, even briefly, is exactly the kind of mismatch
	# that made Sprite3D reject an assignment elsewhere (see
	# _process_jump()'s doc comment). Frame 0 of the jump's own row is
	# always in range for jump_hframes regardless of whatever frame was
	# showing a moment ago under a totally different hframes.
	sprite.frame = _current_row * jump_hframes
	_update_pixel_size()  # jump_texture's own per-frame height, not idle/run's


## Called every frame, unconditionally -- but the MAIN _process() body
## above deliberately skips its own texture/hframes/frame writes
## whenever _is_jumping is true, so this function is the ONLY thing
## touching the sprite's displayed texture/hframes/frame for a jump's
## entire duration (see the guard comment on that block for the exact
## bug that ordering avoids: Sprite3D.frame validates bounds on EACH
## assignment independently, so hframes and frame must always change
## together, never one before the other).
func _process_jump(delta: float) -> void:
	if not _is_jumping:
		sprite.position.y = target_height * 0.5
		return

	_jump_t += delta / jump_duration
	if _jump_t >= 1.0:
		_is_jumping = false
		_jump_t = 0.0
		sprite.position.y = target_height * 0.5
		# Hand back to whatever is CURRENTLY true, explicitly -- not
		# "wait for the main body's next transition edge to catch up,"
		# which might never fire again if is_moving happens to be the
		# same now as it was when the jump started. hframes and frame
		# set together, same reasoning as _start_jump().
		if actor and actor.is_moving:
			sprite.texture = run_texture
			sprite.hframes = run_hframes
			sprite.frame = _current_row * run_hframes + int(_run_progress)
		else:
			sprite.texture = idle_texture
			sprite.hframes = idle_hframes
			sprite.frame = _current_row * idle_hframes
		_update_pixel_size()
		return

	# First half of the hop shows the rising frame, second half the
	# falling one -- lands on frame 1 exactly when the arc (sin(PI*t),
	# peak at t=0.5) is past its peak and descending. jump_hframes=2
	# makes this a plain rise/fall split; a jump_hframes other than 2
	# would just spread more evenly across the same rise/fall duration.
	sprite.texture = jump_texture
	sprite.hframes = jump_hframes
	sprite.frame = _current_row * jump_hframes + clampi(int(_jump_t * jump_hframes), 0, jump_hframes - 1)
	sprite.position.y = target_height * 0.5 + sin(PI * _jump_t) * jump_height


## Recomputes and applies row/flip from actor.facing_direction and the
## camera's CURRENT orientation -- called every _process() frame
## normally (the camera can rotate while facing_direction itself stays
## fixed, e.g. standing still and orbiting with Q/E, so this can't be
## purely event-driven off facing_changed alone), and ALSO called
## directly from _on_facing_changed() so a facing change is reflected
## immediately even on a frame where _process() itself won't run (the
## tree paused for an interaction -- see _facing_signal_connected's
## comment above).
func _update_facing_pose() -> void:
	var row_flip := _direction_to_row_flip(actor.facing_direction)
	_current_row = row_flip.x
	_current_flip = row_flip.y == 1
	sprite.flip_h = _current_flip


func _on_facing_changed(_direction: Vector2i) -> void:
	_update_facing_pose()


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
