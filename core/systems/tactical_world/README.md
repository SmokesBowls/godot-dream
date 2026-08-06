# Tactical world framework (Balrum → 3D)

Godot version: 4.6. This is a spatial/systems framework, not a game —
matches what was asked for: camera, movement, interaction, and UI
primitives to build a story-rich, persistent 3D tactical RPG on top of,
inspired by *Balrum*'s 2D readable-world design.

## What's here

| File | What it is |
|---|---|
| `tactical_camera.gd` | `TacticalCameraRig` — pulled-back, downward-tilted, fully rotatable camera. Not third-person-behind, not top-down. Clamped pitch (35°–80° by default) so it can't degrade into either. |
| `grid_actor.gd` | `GridActor` — discrete grid-snapped movement (`CharacterBody3D`), one cell per move, matches a GridMap's `cell_size`. |
| `grid_actor_player_input.gd` | WASD/arrow-key adapter for `GridActor`, with input buffering so a tap during a move isn't dropped. Kept separate from `GridActor` so AI/pathing can drive the same movement primitive without this input layer. |
| `interactable.gd` | `Interactable` — base class for anything actionable (trees, rocks, chests, NPCs, ruined walls). `InteractionType` enum + one virtual `_on_*` handler per type + a generic `interacted` signal. Registers to the `"interactable"` group and owns an `InteractionLabel` child in `_ready()` — subclasses that override `_ready()` must call `super._ready()`. |
| `interaction_label.gd` | `InteractionLabel` — reusable floating world-space nameplate, exactly three states (`set_hidden()` / `show_name()` / `show_action()`). Two stacked `Label3D`s (name + action) since Label3D has no per-line color markup. |
| `interaction_controller.gd` | `InteractionController` — the *only* thing that calls `get_tree().paused`. Scans the `"interactable"` group each frame (step-distance Euclidean for viewing range, Manhattan==1 for interaction range, grid-sampled line-of-sight against the GridMap), drives each object's label, and owns `begin_interaction()`/`end_interaction()`/`cancel_interaction()`. `PROCESS_MODE_ALWAYS` so it (and its confirm/cancel panel) keeps running through the pause it causes; everything else pauses via the Godot default. |
| `examples/harvestable_plant.gd` | Concrete `Interactable` subclass — a garden plant with a regrow timer, showing the intended override pattern (including the required `super._ready()` call). |
| `demo_mesh_library.gd` | Runtime-generated placeholder `MeshLibrary` (floor + wall boxes) so the demo scene renders without needing imported art. Throwaway — replace with real modular tile meshes. Also registers real collision shapes (`set_item_shapes`) — GridMap generates NO physics collision from a visual mesh alone; without this the ground-shadow raycast (below) hits nothing. |
| `sprite_actor.gd` | `SpriteActor` — billboarded `Sprite3D` presentation layer for a `GridActor`. Reads `GridActor.facing_direction` + the live camera transform to pick a row/flip from a directional sprite sheet. Purely visual; never writes back to movement or collision. See its header comment for the full frame-mapping/camera-relative-angle writeup. |
| `ground_shadow.gd` | `GroundShadow` — raycasts straight down each frame to place a blob shadow on whatever's actually below (GridMap collision, see above). Presentation only, never authoritative for landing/collision. |
| `camera_mode_controller.gd` | `CameraModeController` — three camera modes on F1/F2/F3 (not literal 1/2/3 — those are hotbar slots): behind-sprite (auto-follows the player's facing, the one place the camera is *allowed* to auto-rotate), locked (default — matches the rig's own baseline, no auto-rotation), quick top-down (deliberately, temporarily overrides the rig's own anti-top-down pitch clamp, restored exactly on exit). |
| `../assets/proof_sprites/` | Temporary placeholder character art (a sci-fi robot, copied from Godot's official "2.5d" demo project as a technique proof, not final art) plus the exact frame-layout mapping, measured not guessed. |
| `VISUAL_STYLE_GUIDE.md` | Poly budgets, shading approach, and depth/verticality cues for art built to be seen from this camera. |
| `../../ui/hotbar/` | Draggable 10-slot hotbar UI (see below). |
| `../../scenes/tactical_demo_world.tscn` + `.gd` | A runnable scene wiring all of the above together: floor + perimeter wall (with one deliberate gap), player, a chest, a harvestable plant, the camera rig, and the hotbar overlay. Open and run it to see the pieces working together. |

## Design decisions made without being asked — check these

Per this repo's existing convention (see the event-store port's README):
flagged rather than silently guessed.

1. **One `interaction_type` per `Interactable` instance, not a bitmask.**
   An object that both talks and opens (an NPC with a satchel) is
   modeled as two `Interactable` nodes, not one multi-typed one. If the
   real design wants single-object multi-type interactions, the enum
   dispatch in `interact()` needs to become a set instead of a scalar.
2. **Superseded: floor and walls now share ONE thin GridMap layer,
   distinguished by item id, not by a y-offset.** The original y=0
   floor / y=1 wall split (previous version of this note) turned out to
   silently hide nearby ground-level props: a cell_size.y of 2 gave
   every floor cell a 2-unit-tall "occlusion volume," and the chest/
   plant sitting well inside that volume got hidden behind the floor
   even though they visually cleared it. Fixed by shrinking `cell_size`
   to match the floor's actual thin visual footprint and giving the
   wall its height via a `MeshLibrary` item mesh-transform offset
   instead of a second GridMap layer. `GridActor.wall_layer_offset`
   still exists for anyone who genuinely needs cross-layer walls (e.g.
   multi-story interiors), but the demo no longer uses it —
   `obstacle_item_ids` (which item ids count as solid) is what
   distinguishes wall cells from floor cells sharing the same layer now.
3. **Doorway gaps are 3 cells wide, not 1.** A single-cell gap is
   exactly capsule-width once cell_size shrank to 1.0m — no room to
   step sideways in it, verified as a real complaint before fixing. An
   *odd* width was the deliberate choice (`gap_width_cells := 3`): it
   splits evenly around the wall's center cell, giving one full step of
   room on both sides of center. An even width was tried first and
   rejected — it only gives slack to one side.
4. **Interaction key is hardcoded to F / Escape**, exposed as
   `InteractionController.interact_key` / `cancel_key` exports rather
   than routed through an input-action map. This project has no
   input-map/rebinding system yet; wiring one is a real decision to
   make deliberately; these are just the two keys nothing else in the
   framework currently uses (Q/E are camera rotation).
5. **The confirm/cancel interaction panel is built procedurally in
   `InteractionController._build_panel()`**, not a `.tscn` — same
   "throwaway placeholder, not final art" spirit as `demo_mesh_library.gd`.
   It proves the pause architecture end-to-end (shows target name +
   `[F] <verb>  [Esc] Cancel`, stays responsive while the world is
   paused) but isn't meant to be the final interaction UI.
6. **`Interactable.is_hidden` is an unused hook, not a feature.** The
   brief's "hidden objects require a separate search action" has no
   search mechanic built yet — the flag exists so
   `InteractionController` has the branch ready (a hidden object never
   gets a label, full stop) without needing a signature change later,
   but nothing currently sets it or implements discovery.
7. **Camera defaults to perspective, not orthographic.** The brief's
   "hills and towers block your line of sight" only happens with real
   perspective depth; a pure top-down ortho camera (closer to Balrum's
   literal 2D look) would flatten that out. `orthographic` is exposed
   as a toggle if the tabletop read matters more than sight-blocking in
   practice — this is a judgment call, not a settled decision.
8. **Hotbar slots hold a loose `Callable`, not a typed item/ability
   resource**, because no inventory/ability system exists yet in this
   repo to type it against. Revisit once one does.
9. **No persistence wiring.** The brief's "governed world model... every
   scene, object, and state as authoritative data" is a real match for
   what `core/systems/event_system/dream_event_store.gd` already does
   (append-only events + checkpoints instead of ambient mutable state) —
   but that system is for a different, currently-unfinished narrative
   game concept, has unresolved dependencies of its own (see its
   README), and this framework does not assume or wire into it. Treat
   "hook the world model into an authoritative store" as a deliberate
   follow-up decision, not something already done here.
10. **Solid Interactables (`blocks_movement`, default true) occupy real,
    non-passable space now** — GridActor checks `Interactable.BLOCKING_GROUP`
    in addition to its GridMap wall check (see `_is_object_obstructed()`,
    X/Z-only on purpose: an object's own height above the floor rounds
    to a different cell *layer* than the actor's always-y=0 step math,
    which has nothing to do with whether it blocks a same-plane move —
    comparing the full 3D cell coordinate silently never matched and
    never blocked, caught by a real scripted collision test before
    shipping). Consequence: since a solid object occupies its whole
    cell, the closest the player can ever stand next to one is the
    *adjacent* cell, not "1 step away" — which is why interaction range
    (below) had to change too.
11. **Interaction range is CELL-adjacency (Manhattan==1 in `cell_size`
    units), not step-adjacency**, in `InteractionController._update_label()`.
    At the current tuning (step_distance=0.5, cell_size=1.0) that's 2
    steps, but the check is done in cell units directly rather than
    hardcoding "2" so it stays correct if that ratio ever changes.
    Viewing range stays in step units (finer-grained, matches "how far
    you can see" rather than "which cell you're standing in").
    `viewing_range_steps` default doubled to 10 (5m).
12. **Player rendering is now a billboarded `Sprite3D` (`sprite_actor.gd`),
    not the capsule mesh** — capsule stays as the real collision shape
    plus a hidden debug-toggle mesh (`show_player_capsule_debug` on
    `tactical_demo_world.gd`), never removed. Two decisions worth
    knowing about:
    - **Direction is resolved camera-relative, not world-fixed.**
      `GridActor.facing_direction` is authoritative world-space state;
      `SpriteActor` combines it with the LIVE camera transform each
      frame (not a re-derived yaw formula) to pick a sprite row/flip,
      because our camera orbits (Q/E) and the donor demo's didn't.
      Verified by rotating the camera 180° in a script and confirming
      the row flips to match — this is the one piece of math in this
      whole feature actually worth distrusting on sight.
    - **Real bug caught before shipping**: `SpriteActor`'s `actor`
      export used to connect `move_started`/`move_finished` inside
      `_ready()`, which runs BEFORE the parent scene assigns `actor` at
      all (Godot calls children's `_ready()` before their own parent's)
      — so the connection silently never happened, and the sprite never
      left its idle pose no matter how much the player moved. The
      direction math still looked right in every screenshot, because
      it's driven by a live per-frame read, not a signal — only a
      script checking `sprite.texture` mid-move caught it. Fixed by
      moving the connection into `actor`'s property setter, which fires
      whenever the reference actually arrives regardless of ready order.
    - GridMap collision shapes (see `demo_mesh_library.gd` above) were
      added specifically to give the ground-shadow raycast something
      real to hit — confirmed empirically that none existed before this
      (a straight-down raycast hit nothing but the player's own capsule).
13. **Real bug fixed: `GridActorPlayerInput`'s move buffer used to
    survive across unrelated moves.** It buffered the direction on ANY
    failed `request_move()` — including ones rejected because the
    target was obstructed, not just ones rejected because the actor was
    still gliding — and never cleared a stale buffered direction when a
    DIFFERENT direction was accepted afterward. Symptom: walk into a
    wall (silently buffers that direction forever), then successfully
    move the opposite way — the instant that move finished,
    `move_finished` replayed the stale wall-bound direction (now legal
    again from the new position) and snapped the actor back toward the
    wall. `GridActor.request_move()` itself was never the problem — a
    rejected move there already left `current_step`/`_move_from`/
    `_move_to`/`_move_t`/`facing_direction` untouched; the bug was
    entirely in the input adapter's queued-input handling. Fixed by (1)
    clearing the buffer at the START of every new key press, before
    attempting the move, so a rejection can never leave a PREVIOUS
    press's direction sitting there, and (2) only re-buffering when the
    actor was ALREADY moving at the moment of rejection (a genuine
    timing gap) -- not when it was idle and got rejected on the move's
    own terms (obstruction, or a disallowed diagonal). Verified by
    intentionally reverting the fix and confirming the regression test
    fails with the exact reported symptom before restoring it.
14. **Real bug fixed: pressing Up showed the toward-camera sprite pose,
    not away.** Two separate causes, both now fixed:
    - `sprite_actor.gd`'s row-to-pose mapping (row 0 = toward, row 4 =
      away, row 1 = toward-diagonal, row 3 = away-diagonal) was
      previously ASSERTED in a code comment rather than checked against
      the donor asset's own source — and was backwards. Confirmed the
      correct mapping by re-reading `player_math_25d.gd` +
      `player_sprite.gd` directly: their "move_forward" input drives
      world -Z and maps to `_direction=4`; "move_back" drives +Z and
      maps to `_direction=0`. Fixed the bucket table in
      `_direction_to_row_flip()` accordingly.
    - `grid_actor_player_input.gd` had NO camera-relative input
      resolution at all — WASD mapped directly to fixed world axes
      regardless of camera orientation, which (separately from the pose
      bug) would have made "Up" stop meaning "away from camera" the
      moment the camera was rotated with Q/E. Added a real
      `_resolve_world_direction()` step: raw key → SCREEN-space intent
      → (read live off the camera's actual transform, not a re-derived
      yaw formula) → snapped WORLD-space grid direction. The input
      buffer now stores the screen-space intent and re-resolves it
      against the CURRENT camera orientation at fire time, not the
      orientation at the moment it was pressed. These three stages
      (input-relative-to-camera, accepted world direction, displayed
      sprite relative to camera) are deliberately three separate
      calculations in three different places — conflating any two of
      them is what caused this bug in the first place.
    Verified independently (stage 1 alone, stage 3 alone) and
    end-to-end through the real key-press path, including a rotated-
    camera case where the world direction "Up" resolves to is genuinely
    different from the unrotated case but the displayed pose is still
    correctly "away" either way. Re-verified again in a follow-up pass
    against three fully worked examples (camera facing north/east/south
    × all 4 directions = 12 checks) — all passed against the existing
    fix without changes, confirming it was already correct.
15. **`camera_mode_controller.gd`'s BEHIND_SPRITE mode is the one
    deliberate exception to "camera rotation must not occur merely
    because the player moved."** Everywhere else in the framework that
    rule is real and checked (`grid_actor.gd` never touches
    `TacticalCameraRig.yaw_deg`, confirmed by grep, not assumed) — this
    mode exists specifically to opt IN to auto-follow, on request (F1),
    off by default (starts LOCKED). Its TOP_DOWN mode similarly
    overrides `tactical_camera.gd`'s own deliberate anti-top-down pitch
    clamp (see that file's doc comment for why the clamp exists) —
    intentionally, not a loophole in it, and restores the rig's original
    pitch/max_pitch_deg exactly on leaving the mode.
16. **`grid_actor_player_input.gd` replaced one-shot key handling with a
    held-key state model** (`_held_up/_down/_left/_right`), to support
    holding a direction for continuous stepping and 8-way diagonal
    intent (Up+Right etc. fall out of combining the four flags for
    free, no diagonal-specific input code needed). A literal reading of
    the model's own pseudocode sketch (store the intent into the
    pending-tap slot unconditionally whenever `actor.is_moving`) turns
    out to break the single-tap case: the press event that just started
    an immediate move also satisfies "actor is moving" a moment later,
    so it would double-book itself into the pending slot and fire an
    unrequested second step once released. Fixed by `return`ing right
    after an immediate idle-attempt instead of also falling through to
    the pending-store — see the comment on `_on_held_state_changed()`.
    Caught by an actual failing test, not by inspection alone.
17. **A held-state change is evaluated on BOTH press and release, not
    just press.** Needed for one specific case: releasing one key of a
    blocked diagonal (`allow_diagonal = false`, or the diagonal cell is
    obstructed) can leave a still-held, still-legal cardinal direction
    with nothing left to ever attempt it — `move_finished` never fires
    again because no move ever started. Restricting this to press-only
    would strand that held key until the player let go and pressed it
    again for no reason.
18. **Diagonal steps are `Vector3i(+-1, 0, +-1)`, not normalized down,
    and take the same fixed `move_duration` as a cardinal step** — the
    established rule (a move costs one fixed time slice regardless of
    direction) already covered this; diagonal was never a special case
    requiring a new decision. Documented explicitly on
    `grid_actor.gd`'s `allow_diagonal` export since it wasn't written
    down anywhere before: diagonal movement is real-world-speed faster
    than cardinal by sqrt(2) (~41%), a deliberate "king move" tactical
    convention, not a physically-normalized speed.
19. **`allow_diagonal = false` rejects a diagonal direction outright —
    no alternate-axis fallback.** `grid_actor.gd`'s `request_move()`
    already enforced this; the input layer doesn't decompose a rejected
    diagonal into "try X then Z," it just recomputes intent from
    whatever's actually still held on the next held-state change.
20. **`sprite_actor.gd` moved from signal-driven to poll-driven
    animation state** (`actor.is_moving` read every `_process()` frame,
    instead of connecting to `move_started`/`move_finished`). Real,
    reported bug: `grid_actor_player_input.gd` also listens to
    `move_finished` and connects to it earlier (its own `_ready()`,
    which runs before this node's `actor` gets assigned by the parent
    scene) — Godot delivers a signal to listeners in connection order,
    so on every `move_finished` the input handler ran first, and for a
    held key it calls `request_move()` again immediately, which
    SYNCHRONOUSLY emits a nested `move_started` for the next step before
    this node's own `move_finished` handler had even run. That handler
    then fired afterward and stomped the just-set "walking" state back
    to idle for a step already in flight — position kept gliding, sprite
    froze on a static idle frame. Polling is immune to signal delivery
    order entirely; also removed the `actor` property setter's
    connect/disconnect complexity, which existed only to work around the
    old ready-order bug and had nothing left to do once signals were
    dropped. `_run_progress` (the run-cycle frame position) now only
    resets on a genuine idle→moving transition edge, never on every
    consecutive step, which is what makes a held run read as one
    continuous locomotion cycle instead of restarting each step.
21. **`sprite_actor.gd`'s `frame_size` export was removed -- it's now
    derived from whatever texture is actually assigned, every time it
    changes.** Real, reported bug: the hand-maintained
    `frame_size := Vector2i(64, 64)` was never updated when the sprite
    sheets were upscaled to ~100px frames (to reduce the empty padding
    noted elsewhere in this file), so `pixel_size` kept using the stale
    64px divisor -- every frame rendered ~1.56x too tall. Feet sank
    through the floor, and raising the node to compensate just pushed
    the now-oversized head out of the camera's normal framing instead of
    fixing the actual problem. Confirmed by measuring the real PNGs with
    Pillow before touching code, not assumed: `stand.png` measured
    100x520 (104px/frame) at the time, while `run.png` and `jump.png`
    were both 100x100/frame -- a likely-unintentional export mismatch,
    since fixed at the source (`stand.png` re-exported to 100x500,
    100px/frame, matching the other two exactly). `_update_pixel_size()`
    still reads `sprite.texture.get_height() / vframes` fresh on every
    texture swap (idle<->run) rather than trusting the three sheets to
    always match pixel-for-pixel, so this class of drift can't silently
    recur even if the art changes size again.
    Verification gotcha worth remembering: `--headless --script` mode
    does NOT reimport changed assets -- it was still testing against the
    old cached 104px `.ctex` for a while after `stand.png` was fixed on
    disk (mtimes confirmed: the cache predated the new file), giving a
    false-positive pass against stale art. An `--editor --quit` pass
    forces the reimport; re-verify against that, not against a raw
    `--script` run, whenever a source asset changes.

22. **A half-step landing exactly on a GridMap cell boundary used to get
    rejected as if it were already inside the neighboring wall cell.**
    Reported precisely, and correctly root-caused by the user before I
    even opened the file: with `cell_center_x/y/z = false` and
    `step_distance` (0.5) exactly half of `cell_size` (1.0), every OTHER
    step lands EXACTLY on a cell boundary. Empirically confirmed (raycast
    against the wall's real collision shape, not assumed) that
    `world_to_cell()`'s `roundi()` is actually the geometrically CORRECT
    mapping here -- a wall at GridMap index N really is centered at
    world `N*cell_size`, matching `map_to_local(N)` and this file's own
    `cell_to_world()` exactly -- so switching to `floori()` (the user's
    first hypothesis, and my own first instinct) would have desynced it
    from the real mesh/collision position and reintroduced the "half a
    space offset" bug `cell_center_x/y/z = false` was set to fix in the
    first place. The actual bug was narrower: `roundi()` has to break a
    tie exactly AT that boundary, and rounds away from zero -- into the
    wall being approached, not staying on the near/touching side. Fixed
    with `_collision_test_point()`: nudges the LEGALITY-CHECK point (not
    the actual glide destination) an epsilon back toward where the step
    came from, so landing exactly flush against a wall reads as
    touching, not penetrating -- symmetric regardless of which side a
    wall is approached from, verified on both axes.
23. **A second, independent bug was found and fixed alongside #22:
    `GridMap.local_to_map()` does NOT respect `cell_center_x/y/z` at
    all** -- confirmed empirically, it stays floor-based regardless, so
    it disagreed with a wall's real position by up to half a cell.
    `interaction_controller.gd`'s line-of-sight check used to call
    `grid_map.local_to_map()` directly for exactly this (wrong) reason;
    it now calls `player.world_to_cell()` instead, the same
    geometry-correct mapping `grid_actor.gd` uses for movement, so
    "can I walk there" and "can I see it" can't disagree about where a
    wall actually is.
24. **A third, latent bug surfaced while fixing #23: the line-of-sight
    ray's sampled Y was left interpolating from the player's ground
    level toward the target interactable's height** (chests/plants sit
    at y=0.3-0.35, not y=0). With `cell_size.y` razor-thin (0.1), that
    drift rounds the sampled point into a DIFFERENT y-cell layer well
    before the ray's X/Z even reaches a wall's row -- walls only ever
    exist at y-index 0, so they'd be silently missed. This was already
    latent in the ORIGINAL `local_to_map()` code too; floor-rounding
    happened to still catch it for some test geometries by coincidence,
    which is exactly why it wasn't caught until #23's fix (round-based)
    changed the tie-breaking and made it miss more consistently. Fixed
    by pinning the sampled point's Y to the player's own ground level
    before the cell lookup -- LOS is a floor-plan (X/Z) question, the
    same reasoning `_is_object_obstructed()`'s "X/Z only, deliberately"
    comment already documents for the identical underlying cause.
    Two older regression tests (`verify_full_validation.gd`,
    `verify_doorway_edges.gd`) had hardcoded expectations that a
    half-step onto a wall's real touching face would be rejected --
    that was the bug itself encoded as a test assertion. Updated both
    to expect the corrected geometry (reaching the wall's true face
    succeeds; only stepping past it into the wall's interior is
    blocked).

25. **`debug_grid_overlay.gd` is TEMPORARY** -- added to visualize the
    two coordinate lattices at the center of README items 22-24 (blue =
    GridMap cell boundaries, orange = GridActor step positions), plus
    two live highlight quads tracking the player's current cell and
    exact step. Remove the node from `tactical_demo_world.tscn`, the
    `_debug_grid_overlay` wiring in `tactical_demo_world.gd`, and the
    script file itself once it's no longer needed -- it's deliberately
    self-contained (one script, one node, two wiring lines) specifically
    so it's cheap to strip back out. Hit the exact same children-ready-
    before-parent ordering bug already documented on the old
    `sprite_actor.gd` `actor` setter while building it -- `player` was
    still null when this node's own `_ready()` ran, so mesh construction
    is deferred to the first `_process()` call instead (see `_built`).

26. **The debug grid overlay (item 25) surfaced a real, deeper bug in
    `world_to_cell()` itself: cell ownership was ORIGIN-relative, not
    cell-relative.** Reported precisely: "I can walk the 4 corners of
    the lower-left square, but any other step the quad jumps ahead of
    me." Root-caused empirically (swept `world_to_cell()` across a wide
    range, not assumed): `roundi()`'s ties-away-from-zero rule makes
    every cell own whichever of its two boundaries faces the coordinate
    ORIGIN and lose whichever faces away from it -- invisible for every
    cell except the one straddling the origin itself (cell (0,0,0)),
    since BOTH its boundaries face away simultaneously, so it correctly
    reported only for the single exact point (0,0), not the quadrant its
    own drawn quad implied. Fixed by switching `world_to_cell()` to
    `floori(x/cell_size + 0.5)`, which gives every cell (including cell
    0) a uniform, origin-independent `[N-0.5, N+0.5)` span. Confirmed
    this doesn't undo README item 22's wall-collision fix: the two
    formulas only disagree exactly AT a tie point, and
    `_collision_test_point()` already nudges every movement-legality
    check away from ties before it ever reaches this function -- so that
    fix depends on the nudge, not on which tie-breaking convention
    `world_to_cell()` uses underneath.
27. **Fixing item 26 exposed that `verify_doorway_edges.gd`'s test setup
    was itself relying on the bug it was supposedly testing against.**
    It stood the player one full row short of the doorway's actual wall
    row (z=-9.5 instead of z=-10.0) and tested sideways movement from
    there -- under the OLD `roundi()` bug, z=-9.5 incorrectly reported
    the wall row's own cell index, so the test coincidentally "passed"
    by finding a wall that, physically, was never actually adjacent to
    where the player stood (confirmed empirically: `get_cell_item` at
    the row the player was really standing in was plain floor, not the
    jamb). Fixed by walking the player the full distance into the gap
    before testing -- this is now testing the real jamb wall, not an
    accidental one.

## Try it

Open `core/scenes/tactical_demo_world.tscn` in the Godot 4.6 editor and
run it. WASD/arrows move the player one grid cell at a time; Q/E rotate
the camera; mouse wheel zooms. The hotbar at the bottom of the screen
can be dragged anywhere and responds to keys 1–9 and 0.
