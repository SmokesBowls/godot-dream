# Tactical world framework (Balrum → 3D)

Godot version: 4.6. This is a spatial/systems framework, not a game —
matches what was asked for: camera, movement, interaction, and UI
primitives to build a story-rich, persistent 3D tactical RPG on top of,
inspired by *Balrum*'s 2D readable-world design.

## What's here

| File | What it is |
|---|---|
| `tactical_camera.gd` | `TacticalCameraRig` — pulled-back, downward-tilted, fully rotatable camera. Not third-person-behind, not top-down. Clamped pitch (35°–80° by default) so it can't degrade into either. |
| `grid_actor.gd` | `GridActor` — discrete grid-snapped movement (`CharacterBody3D`), one cell per move, matches a GridMap's `cell_size`. The grid decides WHERE a step would land; a native `PhysicsDirectSpaceState3D.intersect_shape()` query using the actor's own real collision shape decides whether that landing spot is solid — see item 38 below. |
| `grid_actor_player_input.gd` | WASD/arrow-key adapter for `GridActor`, with input buffering so a tap during a move isn't dropped. Kept separate from `GridActor` so AI/pathing can drive the same movement primitive without this input layer. |
| `interactable.gd` | `Interactable` — base class for anything actionable (trees, rocks, chests, NPCs, ruined walls). `interaction_flags` (a real `@export_flags` bitmask, not a single enum — see item 37) + one virtual `_on_*` handler per `InteractionType` + a generic `interacted` signal. Registers to the `"interactable"` group, and — if `blocks_movement` is true — builds a real `StaticBody3D` collision body (see item 38) and owns an `InteractionLabel` child, both in `_ready()`. Subclasses that override `_ready()` must call `super._ready()`. |
| `examples/merchant.gd` | Concrete `Interactable` subclass proving the multi-type case `interaction_flags` exists for — one NPC with both TALK and OPEN active at once (see item 37). |
| `interaction_label.gd` | `InteractionLabel` — reusable floating world-space nameplate, exactly three states (`set_hidden()` / `show_name()` / `show_action()`). Two stacked `Label3D`s (name + action) since Label3D has no per-line color markup. |
| `interaction_controller.gd` | `InteractionController` — the *only* thing that calls `get_tree().paused`. Scans the `"interactable"` group each frame (step-distance Euclidean for viewing range, Manhattan==1 for interaction range, grid-sampled line-of-sight against the GridMap), drives each object's label, and owns `begin_interaction()`/`end_interaction()`/`cancel_interaction()`. `PROCESS_MODE_ALWAYS` so it (and its confirm/cancel panel) keeps running through the pause it causes; everything else pauses via the Godot default. |
| `examples/harvestable_plant.gd` | Concrete `Interactable` subclass — a garden plant with a regrow timer, showing the intended override pattern (including the required `super._ready()` call). |
| `demo_mesh_library.gd` | Runtime-generated placeholder `MeshLibrary` (floor + wall boxes) so the demo scene renders without needing imported art. Throwaway — replace with real modular tile meshes. Also registers real collision shapes (`set_item_shapes`) — GridMap generates NO physics collision from a visual mesh alone; without this the ground-shadow raycast (below) hits nothing. |
| `sprite_actor.gd` | `SpriteActor` — billboarded `Sprite3D` presentation layer for a `GridActor`. Reads `GridActor.facing_direction` + the live camera transform to pick a row/flip from a directional sprite sheet. Purely visual; never writes back to movement or collision. See its header comment for the full frame-mapping/camera-relative-angle writeup. |
| `ground_shadow.gd` | `GroundShadow` — raycasts straight down each frame to place a blob shadow on whatever's actually below (GridMap collision, see above). Presentation only, never authoritative for landing/collision. |
| `camera_mode_controller.gd` | `CameraModeController` — three camera modes on F1/F2/F3 (not literal 1/2/3 — those are hotbar slots): behind-sprite (auto-follows the player's facing, the one place the camera is *allowed* to auto-rotate), locked (default — matches the rig's own baseline, no auto-rotation), quick top-down (deliberately, temporarily overrides the rig's own anti-top-down pitch clamp, restored exactly on exit). |
| `../assets/proof_sprites/` | Temporary placeholder character art (a sci-fi robot, copied from Godot's official "2.5d" demo project as a technique proof, not final art) plus the exact frame-layout mapping, measured not guessed. |
| `VISUAL_STYLE_GUIDE.md` | Poly budgets, shading approach, and depth/verticality cues for art built to be seen from this camera. |
| `follower.gd` | `Follower` — trailing-step companion AI. Drives its own `GridActor` by replaying the LEADER's own step history a few moves behind, rather than pathing toward the leader's current position — see item 40. |
| `examples/apple.gd` | `ApplePickup` — a one-off pickup prop: adds itself to the picker's Inventory, then removes itself from the world. See item 41. |
| `examples/chest.gd` | `Chest` — a lootable container: opens a real `LootWindow` so the player chooses which items to take, leaving the rest for later. See items 41-42. |
| `ledge.gd` | `Ledge` — a declarative walkable elevated footprint (height + X/Z size), what `GridActor.request_jump_step()` reads to know where a real step-up is possible. See item 42. |
| `../inventory/inventory.gd` | `Inventory` — minimal item_id->amount component, attached to the Player. See item 41. |
| `../feedback/game_feedback.gd` | `GameFeedback` — autoload; shows one transient on-screen line for interaction effects (talk, loot, harvest) that used to only `print()`. See item 41. |
| `../../ui/inventory_hud/` | `InventoryHud` — always-on top-right readout of the Player's Inventory contents. See item 41. |
| `../../ui/toggle_list_window/` | `ToggleListWindow` base + `LootWindow`/`ShopWindow` autoloads — modal, keyboard-driven "pick some rows" windows backing Chest and Merchant's satchel. See item 42. |
| `../../ui/hotbar/` | Draggable 10-slot hotbar UI (see below). |
| `../../scenes/tactical_demo_world.tscn` + `.gd` | A runnable scene wiring all of the above together: floor + perimeter wall (with one deliberate gap), player, a follower companion, a chest, a harvestable plant, a merchant, an apple, a jump-test platform, the camera rig, inventory HUD, and the hotbar overlay. Open and run it to see the pieces working together. |

## Design decisions made without being asked — check these

Per this repo's existing convention (see the event-store port's README):
flagged rather than silently guessed.

1. **Superseded — see item 37: `interaction_flags` is now a real bitmask,
   not a single enum.** The original decision (below, kept for history)
   was reversed once an actual multi-type case (a merchant NPC with a
   satchel) needed it: *"One `interaction_type` per `Interactable`
   instance, not a bitmask. An object that both talks and opens (an NPC
   with a satchel) is modeled as two `Interactable` nodes, not one
   multi-typed one. If the real design wants single-object multi-type
   interactions, the enum dispatch in `interact()` needs to become a set
   instead of a scalar."*
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

28. **Item 26's `floori(x+0.5)` fix removed the ORIGIN-relative
    asymmetry but replaced it with a DIRECTION-relative one, uniform
    across the whole map.** Reported precisely again: Up/Left took 2
    steps to flip the highlighted cell (correct), but Down/Right flipped
    after just 1 step and landed the player on the new cell's FAR edge
    instead of its near one. Root cause: `floori(x+0.5)` always assigns
    a cell's "lower" boundary to itself and its "upper" boundary to the
    next cell out -- a uniform rule, but still a STATELESS one, and any
    stateless point->cell formula necessarily picks one side of every
    boundary tie, which reads as correct approaching from one direction
    and wrong from the other. This isn't fixable by choosing a
    different rounding formula -- no single stateless rule can make
    both directions "win" the same tie. Fixed with STICKY tracking in
    `debug_grid_overlay.gd` (`_sticky_current_cell()`): keep reporting
    the last cell shown, and only flip once the player is STRICTLY
    (not tied) closer to a different cell's center. Verified all 4
    cardinal directions now behave identically: step 1 to a boundary
    never flips anything, step 2 flips and lands exactly on the new
    cell's center. `player.world_to_cell()` itself was NOT reverted --
    it's still correct and necessary for item 22's wall-collision fix,
    which never depends on tie-breaking (the nudge steers every
    legality check away from ties before this function ever sees them).
    Stickiness is a display-only concern, scoped to the debug overlay,
    not applied to movement/collision logic.

29. **MOVEMENT AT BLOCKED CELL EDGES: standing exactly at a wall's
    touching face was reversed on purpose.** Real playtest report: the
    actor has a real capsule radius (0.4m), and resting exactly at a
    boundary position (e.g. x=9.5 next to a wall spanning [9.5,10.5))
    put roughly half that radius bodily inside the wall -- geometrically
    fine for the zero-radius point items 22-23's fix reasoned about, not
    for an actor with real size. `request_move()` now looks one more
    half-step PAST any boundary-landing target, in the same direction,
    and rejects the boundary step itself if that further position is
    blocked -- so the actor stops at the last open CELL CENTER instead
    (`_is_cell_boundary()` / the new check in `request_move()`).
    Center-landing steps (the other half of every pair) are unaffected;
    open-to-open movement anywhere away from a wall is unaffected.
    Deliberately does NOT touch the sticky debug-highlight logic (item
    28) or `world_to_cell()`'s tie-breaking (item 26) -- this is a
    movement-legality decision made in `request_move()`, upstream of
    anything the debug overlay visualizes, exactly as specified.
    Directly reverses the specific outcome (not the mechanism) of items
    22-23's fix for the blocked-neighbor case -- `_collision_test_point`
    is still correct and necessary (it's what makes touching a wall
    correctly NOT get rejected on ties when the far side IS open); this
    is a deliberate, additional layer on top of it, not a revert.
    Verified symmetric on both wall sides, against a solid object
    (chest) as well as a wall, for diagonal boundary crossings, and that
    repeated attempts at the stop point never creep forward. Three
    existing tests had hardcoded the old touching-face-reachable
    expectation (`verify_boundary_fix.gd`, `verify_full_validation.gd`,
    `verify_doorway_edges.gd`) -- all three updated with the reversal
    documented in place, not silently changed.

30. **Movement legality was rewritten from float-rounding to exact
    integer arithmetic (`step_to_cell()`), replacing the entire lineage
    of tie-breaking patches (items 22, 26, 28-29).** Not a fourth patch
    on the same rounding function -- a structural fix. Every prior bug
    in this series came from the same root cause: `step_distance` is
    exactly half of `cell_size`, so converting a step position to a
    world float and dividing by `cell_size` produces an EXACT tie on
    every other step -- not a rare edge case, the common one -- and any
    stateless rule for breaking that tie (`roundi()`, `floori(x+0.5)`,
    an epsilon nudge) necessarily favors one side over the other
    *somewhere*, which is exactly why each fix in turn surfaced a new
    case the same way. `current_step` is always an exact integer, and
    `cell_size`/`step_distance` have a fixed integer ratio -- so "which
    cell is this" can be answered with true integer floor division
    (`_floor_div`/`_floor_mod`, verified against GDScript's actual `/`
    and `%` behavior on negative operands empirically before use, not
    assumed) instead of dividing floats and rounding. Integer division
    has no ties, so there is nothing left to break asymmetrically.
    `_collision_test_point()` (the epsilon nudge) and the float-based
    `_is_cell_boundary()` were removed outright, not just replaced --
    once the wall/object checks work in exact step space via
    `step_to_cell()`, there's no longer a tie for either of them to
    exist for. `world_to_cell()` (float-based) stays, scoped to what it
    was always actually needed for: arbitrary continuous positions that
    were never on the step lattice to begin with (mid-glide
    `current_cell()`, hand-placed object positions, the debug overlay,
    interaction line-of-sight).
    Verified two ways: (1) every existing regression suite from this
    entire bug lineage re-passes byte-for-byte identically (28/28,
    17/17, 16/16, 12/12, 13/14 with the one pre-existing unrelated
    stale test) -- the refactor changes HOW the answer is computed, not
    WHAT the answer is; (2) a NEW exhaustive sweep
    (`verify_exhaustive_cell_mapping.gd`) that a float-based approach
    could never cheaply support -- 2000+ step positions spanning the
    origin in both directions, confirming every cell owns exactly the
    same count of steps with zero exceptions, boundary detection agrees
    with cell ownership everywhere, and advancing one full cell always
    changes the cell index by exactly 1 in either direction. This is
    the actual end of the bug class, not a fourth instance of finding
    where the previous fix's tie-break still lost.

31. **The blocked-cell-edge fix (item 29) only checked the axis the
    CURRENT move was advancing along -- a real, reported "still walking
    into the wall" bug got through it.** Reproduced exactly from two
    user-supplied screenshots (a live coordinate HUD added specifically
    for this -- see `debug_grid_overlay.gd`'s `show_hud`): stand mid-
    doorway (a boundary position on one axis, legitimately safe there
    because the doorway leaves both neighboring cells open), then turn
    and walk ALONG the wall on the OTHER, perpendicular axis. The old
    check in `request_move()` only looked at the boundary axis matching
    `direction` -- a pure north/south move never re-examined the
    already-boundary X position at all, so the actor could slide right
    up against a real wall on that axis without it ever being checked
    again at the new row. Root cause: "this axis didn't change, so it
    must already be validated" is only true the FIRST time a boundary
    is reached -- moving along the OTHER axis can change which two
    cells that SAME boundary touches (a different row entirely), and
    neither has been checked at the new position before.
    Fixed by checking BOTH axes independently on every move, not just
    the one matching `direction`: the axis being actively advanced
    still only needs to look one step further (the near side is
    already known-good, it's where the move came from); an axis that's
    ALREADY a boundary but isn't the one advancing needs BOTH its
    neighbors checked, since neither has been validated at this new
    position.
    A second, separate inconsistency surfaced while verifying this:
    `world_to_cell()` (float) and `step_to_cell()` (exact integer) --
    two independent paths that are supposed to describe the same
    lattice -- silently disagreed at exact boundary ties (confirmed:
    `step_to_cell(19) == 9`, but the old `world_to_cell(9.5) == 10` for
    the identical physical point). Never caused a visible bug on its
    own (movement legality only ever used `step_to_cell()`), but caught
    while cross-checking the doorway-turn fix, and fixed for the same
    reason items 22-30 all exist: two different answers to "which cell
    is this" is exactly the shape of bug this whole series has been
    about. `world_to_cell()` now uses `ceili(v - 0.5)` instead of
    `floori(v + 0.5)` -- the precise float equivalent of
    `step_to_cell()`'s floor-division tie-breaking, verified to agree
    at all 1001 swept boundary positions, not spot-checked.
    Verified at all 4 doorways symmetrically (13/13), confirmed the fix
    doesn't seal doorways shut (still walkable straight through), full
    existing regression suite re-passes unchanged, and visually
    reproduced the user's exact two screenshots before/after.

32. **Item 31's per-axis boundary fix left one more gap: a true 2D
    corner (both axes on a boundary at once) has FOUR cells meeting at
    it, not two.** Flagged by the user's own systematic screenshot
    testing (standing at corners next to the chest and the plant,
    probing single-axis vs. both-axis boundary cases on purpose).
    Checking each axis independently -- even checking both neighbors on
    each, per item 31 -- only ever reaches the two cells sharing an
    EDGE with the target's own cell. The fourth cell, sharing only the
    CORNER (both axes shifted at once), was never examined by either
    axis check alone. Root-caused, then isolated in a synthetic test
    (a blocker placed at ONLY the diagonal cell, with both edge-adjacent
    cells deliberately left open, so nothing but the missing check
    could catch it) before touching production code.
    Fixed by dropping the direction-dependent branching entirely --
    that reasoning ("this axis is already validated because I'm not
    moving along it") is exactly what produced item 31's bug in the
    first place, so extending it further was the wrong instinct. The
    new check is direction-INDEPENDENT: every cell a boundary position
    could touch gets checked, unconditionally, regardless of which way
    the move happens to be facing. One boundary axis -> 2 neighbor
    checks; both axes at once -> all 4 corner combinations. Simpler
    code, not just more correct -- no more asking "which side does the
    direction-of-travel reasoning say is already safe."
    Caught a real, unrelated GDScript bug while implementing this:
    `var x: Array[int] = [1,-1] if cond else [0]` fails at RUNTIME
    (not parse time) -- a ternary whose branches are array literals
    returns a plain untyped `Array`, which can't assign into a typed
    `Array[int]` variable. Confirmed empirically (a 4-line standalone
    script) before concluding this, not assumed; fixed by using plain
    if/else reassignment instead, which doesn't have the problem.
    Verified: isolated synthetic-blocker test (5/5, plus a negative
    control confirming the same move succeeds once the corner cell is
    unblocked), full existing regression suite unchanged, and visually
    confirmed diagonal approach to the real chest now stops a clean
    full cell short with no overlap.

33. **Fix #3, "staring at a wall": facing was previously ONLY updated on
    a successful move, which read as the game not hearing input at all
    once you'd stopped moving.** Two concrete cases fixed:
    (a) bumping into a wall or solid object -- `request_move()`'s two
    obstruction-rejection points now call the new `face_direction()`
    before returning false, so a blocked attempt still visibly turns
    the character toward it, even though it doesn't move there.
    Deliberately NOT extended to the "already moving" or "diagonal
    disallowed" rejections -- neither of those is "something physically
    blocked me," they're "that request was never really attempted," so
    there's nothing to acknowledge (and for "already moving," doing so
    would spin the character on every held key spammed mid-glide).
    (b) starting an interaction -- `interaction_controller.gd`'s
    `begin_interaction()` now turns the source (if it's a GridActor) to
    face the target, snapped to the nearest of GridActor's 8 grid
    directions, even though no step is taken to reach it.
    `snap_to_grid_direction()` was previously private, duplicated math
    inside `grid_actor_player_input.gd` -- moved to GridActor as the
    canonical version (same reasoning as items 22-32: two places
    computing the same thing is exactly the failure class this project
    keeps finding), with the input script now delegating instead.
    A deeper issue surfaced verifying (b): `facing_direction` updated
    correctly and immediately, but the SPRITE never visibly turned while
    the interaction panel was open -- only after closing it. Root
    cause: `begin_interaction()` pauses the tree, `SpriteActor` is
    (correctly) left `PROCESS_MODE_PAUSABLE`, and `_process()` simply
    doesn't run at all while paused. Making the whole node
    `PROCESS_MODE_ALWAYS` was considered and rejected -- it would also
    keep the run-animation frame advancing if a glide happened to be
    mid-flight at the exact instant an interaction began, since
    GridActor itself correctly stops processing when paused and never
    gets to set `is_moving` back to false. Fixed instead with a new
    `GridActor.facing_changed` signal, emitted from the single place
    `facing_direction` is ever assigned now (`face_direction()`) --
    signal delivery isn't gated by `process_mode` the way `_process()`
    calls are, so `SpriteActor` (connected lazily on first `_process()`,
    same ready-order pattern as `debug_grid_overlay.gd`) can react
    immediately even while paused, without needing to run every frame.
    Caught a real, unrelated GDScript runtime quirk while writing this
    ticket's tests: `Array[int] = [1,-1] if cond else [0]` -- not this
    ticket's bug, but adjacent code, confirmed with a standalone 4-line
    script before moving on.
    Verified: 18/18 covering both fix cases, the two deliberately-
    excluded rejection reasons staying untouched, a diagonal interaction
    target snapping to the correct compass direction, the delegated
    snap function producing identical results to the code it replaced,
    and (directly, not just visually) the sprite's row/flip actually
    changing while the tree is paused, not just after unpausing. Full
    existing regression suite (28/28, 13/13, 5/5, 17/17, 9/9, 12/12,
    16/16, 8/8, 7/7, 6/6, plus the one pre-existing unrelated stale
    test) unchanged.

34. **Pause ownership moved from InteractionController to a new
    autoload, `core/systems/game_state/game_state_manager.gd`.**
    `InteractionController` used to write `get_tree().paused` directly
    -- correct only as long as interaction was the sole reason the
    world could ever pause. A weak-reference-backed pause-request
    collection replaces the boolean: every system that needs the world
    paused ADDS a (requester, reason) request; releases only its OWN;
    the tree is paused exactly when at least one request survives,
    decided in exactly one place. Idempotent per (requester, reason);
    different requesters, or different reasons from the same
    requester, are independently tracked. A requester freed without
    calling release is auto-pruned (checked before every public method,
    and every frame via `_process()`, since the manager is
    `PROCESS_MODE_ALWAYS`) rather than freezing the game forever.
    `InteractionController` still owns everything about the
    interaction session itself (target, UI, confirm/cancel, facing) --
    only the pause READ/WRITE moved.
    Two real, confirmed Godot findings along the way, neither
    assumed: (1) a script can't declare `class_name X` while ALSO being
    registered as an autoload singleton named `X` -- Godot rejects it
    at compile time ("hides an autoload singleton"); the autoload
    registration itself already provides the global `GameStateManager`
    identifier every caller needs, so `class_name` was redundant. (2) a
    COMPILE-TIME type annotation (`var x: InteractionController`) in a
    script forces Godot to compile `interaction_controller.gd` -- and
    therefore resolve its `GameStateManager` reference -- while loading
    THAT SCRIPT ITSELF, before its own `_init()` ever runs; three
    existing test scripts had exactly this pattern and needed the
    annotation loosened, not a timing fix (an `await` inside `_init()`
    can't fix a failure that happens before `_init()` starts).
    Verified with a new 38/38 suite (all 16 pure pause-arbitration
    validations from the ticket against an isolated manager instance,
    plus 5 integration checks against the real autoload +
    InteractionController), full existing regression suite unchanged
    (including every interaction pause-lifecycle test), and a project-
    wide search confirming `get_tree().paused` is written in exactly
    one place.

35. **Jump added -- Space bar, purely cosmetic.** The donor `jump.png`
    sheet was copied in early on but deliberately left unwired ("Stop
    after the player sprite and shadow are working. Do not add jumping
    yet."). This is that: a Sprite3D-local Y arc (`sin(PI*t)`, peak at
    the midpoint) plus a 2-frame rise/fall animation, entirely inside
    `sprite_actor.gd`. Never touches `GridActor` -- no change to
    `global_position.y` (which stays 0 always; this actor never steps
    vertically), `current_step`, `is_moving`, or any collision check.
    Blocked while the game is paused for free, the same way movement
    input already is -- `sprite_actor.gd` is left at the Godot default
    process mode (PAUSABLE), so its new `_unhandled_input()` simply
    doesn't fire while `GameStateManager` holds the tree paused.
    A real bug caught by actually running it, not just written and
    trusted: `Sprite3D.frame` validates bounds on EACH assignment
    independently, not just the last one applied in a frame. The
    original design let jump run as a pure "overlay applied last" on
    top of the idle/run block, on the theory that a later assignment
    would always win -- but the idle/run block computed a frame index
    assuming `run_hframes` (6) while `sprite.hframes` was still stuck
    at `jump_hframes` (2) from the previous frame, which is already out
    of range the INSTANT it's assigned, before jump's own correction
    ever runs. Fixed by having the idle/run block skip its
    texture/hframes/frame writes ENTIRELY while a jump is playing (its
    underlying `_run_progress` timer bookkeeping still runs
    unconditionally, so nothing goes stale) and having jump's own
    landing logic explicitly hand back a matching (hframes, frame) pair
    in one step, rather than one property at a time.
    Verified with a 19/19 suite: purely cosmetic (GridActor position/
    step/is_moving genuinely untouched), the arc actually rises and
    returns to exactly the resting Y, the frame column switches at the
    arc's midpoint, landing while idle restores idle_texture, landing
    while STILL MOVING (via a real held key, not a single tap that
    would finish before the jump even ends) correctly restores
    run_texture instead of idle, a second press mid-air doesn't restart
    the arc, and jump input genuinely doesn't reach `_unhandled_input`
    at all while `GameStateManager` holds the tree paused. Full existing
    regression suite unchanged. `proof_sprites/README.md`'s frame-size
    table was also stale (never updated after the art got upscaled
    alongside `stand.png`/`run.png`) -- corrected.

36. **Fix #2, "the Apple Problem": a small prop no longer blocks the
    whole 1m cell it sits in.** Movement steps in 0.5m increments
    (`step_distance`) but object collision used to check the whole 1m
    GridMap cell (`world_to_cell()` match) -- any `Interactable` with
    `blocks_movement` true silently vetoed all four 0.5m sub-cell steps
    around it, including the three that have visually nothing in front
    of them. Fixed with two new `Interactable` exports, only read when
    `blocks_movement` is true: `occupies_full_cell` (default `true` --
    unchanged behavior, chests/plants/furniture keep blocking their
    whole cell) and `occupancy_radius` (meters, only read when
    `occupies_full_cell` is `false` -- the object then blocks only steps
    landing within that radius of its actual position). A demo `Apple`
    node (small red sphere, `occupies_full_cell = false`,
    `occupancy_radius = 0.15`) was added to `tactical_demo_world.tscn`
    to prove it live.
    Two real bugs found by actually running the existing regression
    suite against this, not just the new one:
    - The boundary-corner safety check in `request_move()` (item 32)
      probes the lattice step one full step beyond a shared cell
      boundary to ask "is the cell on the other side of this boundary
      entirely solid" -- a question that only makes sense for
      `occupies_full_cell` objects and walls. For a footprint object
      placed at a normal cell-center position, that probe's neighbor
      step is always the object's OWN center step, so it read as
      "obstructed" no matter how small `occupancy_radius` was set,
      permanently blocking every cardinal approach regardless of the
      object's real footprint. Fixed with a `corner_safety_probe`
      parameter on `_is_step_obstructed()` / `_is_object_obstructed_step()`
      that skips the footprint branch specifically during that probe --
      the object's actual overlap with the boundary point itself is
      already caught correctly by the plain (non-probe) check on
      `target_step` earlier in the same function.
    - `_is_object_obstructed_step()`'s loop originally cast each
      `BLOCKING_GROUP` member straight to `Interactable` to read the two
      new exports, silently dropping (via `continue`) any group member
      that isn't actually an `Interactable` instance --
      `verify_diagonal_corner.gd`'s synthetic test blocker (a bare
      `Node3D` added to the group directly, not a full `Interactable`)
      went from "blocks its cell" to "invisible" the instant that cast
      landed. `BLOCKING_GROUP`'s real contract was always "any Node3D
      that wants to occupy space," not "any Interactable" -- fixed by
      casting to `Node3D` first (as before) and only additionally
      reading `Interactable`-specific fields when that second cast also
      succeeds, falling back to the original full-cell behavior for
      anything that isn't one.
    - Also caught (and fixed by relocating, not by touching any logic):
      the new `Apple` node's first placement, `(2, 0.12, 0)`, sat
      directly on the +X ray from spawn that an existing held-movement
      regression test already walks along, deterministically breaking
      that test's "run texture never drops to idle mid-hold" assertion
      once the held walk reached the now-blocked step next to it.
      Confirmed deterministic (3/3 repeated runs), not flaky, before
      moving it to `(2, 0.12, -2)`, off every cardinal ray and prior
      long-hold test path from the origin -- the same placement
      convention `Chest` (4, .35, 4) and `Plant` (-4, .3, -4) already
      used for exactly this reason.
    Verified with an 11/11 suite: `Interactable` defaults are unchanged
    (`occupies_full_cell` true out of the box), the existing Chest still
    blocks every step in its cell and nothing beyond it (regression),
    the apple blocks only the step landing exactly on it and not steps
    0.5m away, two steps sharing the SAME GridMap cell get different
    blocked/open answers depending on which quadrant they land in (the
    real-geometry proof the design memo called for), and `request_move()`
    end-to-end both allows stepping into the open quadrant next to the
    apple and still blocks stepping directly onto it. Full existing
    regression suite confirmed clean afterward, including four older
    scratchpad tests (`verify_exact_spec_scenarios.gd`,
    `verify_stage1_input_resolution.gd`, `verify_sprite_direction.gd`,
    `verify_doorway.gd`, `verify_movement_fix.gd`, `verify_substep.gd`)
    that turned out to already be missing the `await process_frame`
    fix from item 34's `GameStateManager` migration -- discovered while
    re-sweeping for this ticket (that migration's own regression sweep
    hadn't covered them), patched the same way as the files item 34
    already fixed. `verify_sprite_direction.gd` still fails 4/6 on an
    unrelated, pre-existing row-mapping mismatch that predates every
    change in this session (confirmed against the untouched git
    baseline) -- flagged, not silently fixed, since guessing at which
    of several already-iterated-on direction conventions is "correct"
    risks being wrong in a way a screenshot alone wouldn't catch.

37. **`Interactable.interaction_flags` replaced the single-scalar
    `interaction_type` enum with a real `@export_flags` bitmask,
    reversing item 1's original decision.** The old rule -- one
    `InteractionType` per node, so a dual-purpose entity (an NPC that
    both talks and has a lootable satchel) had to be two `Interactable`
    nodes sharing one world position -- was a real, reported scalability
    problem in practice, not a hypothetical one: two nodes meant two
    independent `InteractionLabel`s computing the same distance/line-of-
    sight math against the same target position, two entries in every
    "what's here" group query, and two separate `_ready()`/`interact()`
    lifecycles for what is conceptually one entity, with nothing tying
    them together.
    Fixed by making `interaction_flags` a real bitmask
    (`@export_flags("Examine", "Talk", "Harvest", "Open", "Climb",
    "Pass Through", "Toggle")`, inspector-editable as checkboxes) instead
    of a scalar `InteractionType`. `interact(source, type := -1)` now
    takes an explicit `type` (defaulting to `primary_interaction_type()`,
    the type an unqualified F-press should run); a single-flag object
    (every existing Chest/Plant/Apple) has an unambiguous "the" type
    regardless of `primary_interaction_type_override`, so no existing
    scene needed anything beyond a mechanical `interaction_type = X` ->
    `interaction_flags = 1 << X` conversion. `prompt_for(type)` resolves
    the verb text per type -- a single-flag object always uses the
    existing `interaction_prompt` string unchanged; a multi-flag object
    consults the new `interaction_prompts` dictionary, falling back to a
    generic per-type default. `examples/merchant.gd` is a new concrete
    example (TALK primary, OPEN secondary) proving the exact "NPC with a
    satchel" case item 1 originally punted on, added to
    `tactical_demo_world.tscn` the same way `Apple` proved item 36.
    `InteractionController` surfaces the multi-type case without
    touching the common single-type path: the floating world-space label
    still only ever shows the primary action (unchanged), but
    `begin_interaction()` now also collects every OTHER active type into
    `_current_secondary_types`, and the bottom-screen confirm panel lists
    one extra numbered line per secondary action (`[1] Open Satchel`,
    reusing the hotbar's existing 1-9 key vocabulary) -- F still always
    confirms the primary, unchanged from before. A real, disclosed
    side effect: the panel's hint text is now built as one line per
    action rather than one hand-formatted string, so even a single-type
    target's panel changed from one line (`[F] Verb    [Esc] Cancel`) to
    two (`[F] Verb` / `[Esc] Cancel`) -- the panel's `PanelContainer` was
    changed from a fixed 70px box to grow-to-content
    (`grow_vertical = GROW_DIRECTION_BEGIN`) specifically so this and any
    future longer action list never silently overflows a hardcoded size.
    Verified with a 21/21 headless suite (`verify_pause_and_interaction.gd`,
    scratchpad): `has_interaction_type()`/`active_interaction_types()`/
    `primary_interaction_type()`/`prompt_for()` against both the Merchant
    (multi-flag) and a synthetic single-flag object, `interact()` with no
    argument correctly running the primary handler only, an explicit
    secondary `interact(_, OPEN)` running the correct handler, and an
    explicit call with a type the object does NOT have active correctly
    no-op'ing rather than crashing or silently redirecting to the
    primary. Full scene also run headless 120 frames with the Merchant
    present in `InteractionController`'s per-frame label scan with no
    errors.

38. **Movement obstruction was rewritten from GridMap-cell/step-lattice
    math to a native `PhysicsDirectSpaceState3D.intersect_shape()` query
    at the exact destination, replacing the entire lineage items 22-32
    and 36 built up.** Not one more patch on that lineage -- a
    structural change in what kind of question `request_move()` even
    asks. Every bug in that history (half-step boundary ties, the
    corner-safety probe needing its own carve-out for footprint objects,
    the Apple Problem's squared-distance reimplementation of "does this
    overlap") came from reasoning about integer cell/step LATTICE
    positions as a stand-in for real geometry. A real shape-vs-shape
    overlap query, cast with the actor's OWN actual `CollisionShape3D`
    at a real world position, has no lattice to tie-break on in the
    first place -- it answers "does my actual body fit here" directly.
    `GridActor` now only uses the grid to compute WHERE a step would
    land (`step_to_world()`); whether that spot is solid is entirely a
    physics query against two new dedicated collision layers
    (`GridActor.WALL_COLLISION_LAYER_BIT` = 2, `OBJECT_COLLISION_LAYER_BIT`
    = 3), masked by the actor's own `check_object_collision`. `obstruction_map`,
    `obstacle_item_ids`, `wall_layer_offset`, and every GridMap-cell-index
    helper (`step_to_cell()`, `_floor_div`/`_floor_mod`,
    `_is_axis_step_on_boundary()`, the corner-safety-probe loop) are
    gone from `GridActor` entirely -- there's no lattice tie left for any
    of them to exist for.
    Walls get real collision from `tactical_demo_world.gd`'s new
    `_build_wall_collision()` -- one `StaticBody3D`/`BoxShape3D` per wall
    cell, built independently of the GridMap's OWN collision shapes
    (which stay exactly as they were, on the default layer, still only
    used by `ground_shadow.gd`'s raycast). This is deliberate, not
    redundant: GridMap's `collision_layer`/`collision_mask` are ONE
    property of the whole node, shared by every item it places, so there
    is no per-item way to put walls on the obstruction layer without
    ALSO putting the floor's paper-thin collision boxes on it -- and a
    movement probe resting at ground level would then sit right at the
    floor box's own top surface, close enough to the default physics
    contact margin to risk exactly the kind of geometry-precision
    landmine this project's history is full of. Independent, wall-only
    bodies sidestep the question entirely.
    Solid `Interactable`s get their own real collision the same way --
    `_build_collision_body()`, called from `_ready()` when
    `blocks_movement` is true, builds a `StaticBody3D` with a
    `BoxShape3D` (full-cell objects, sized via the new `full_cell_size`
    export) or `CylinderShape3D` (footprint objects, `occupancy_radius`)
    on `OBJECT_COLLISION_LAYER_BIT`. Both shapes are given a deliberately
    huge Y-extent (100m) regardless of the object's own height or
    position, reproducing -- via physics -- the exact "X/Z only,
    deliberately" rule the old grid-cell check documented (an object's
    height above the floor has nothing to do with whether it blocks a
    same-plane move); this avoids reintroducing a NEW Y-alignment bug
    class in physics form.
    One real, disclosed BEHAVIOR CHANGE surfaced while verifying this,
    not merely a re-implementation: `occupancy_radius` previously
    measured a footprint object's block radius against the bare STEP
    LANDING POINT (the old check treated the moving actor as a
    zero-size point for this specific comparison, even though walls
    separately got a real capsule-radius patch of their own in item 29).
    A physics shape query has no such asymmetry -- two shapes overlap
    when the distance between their centers is less than the SUM of
    both radii, so the moving actor's own real capsule radius (0.4 in
    this framework's default rig) now genuinely adds to
    `occupancy_radius` when deciding what's blocked. This is judged a
    correctness IMPROVEMENT (walls and footprint objects now use the
    same real-geometry rule instead of two different approximations),
    but it meant the demo Apple's tuning (`occupancy_radius = 0.15`)
    no longer left an adjacent 0.5m step open against a 0.4-radius
    capsule (0.15 + 0.4 = 0.55 > 0.5) -- caught by a failing regression
    test, not assumed correct. Retuned to `occupancy_radius = 0.08`
    (0.08 + 0.4 = 0.48 < 0.5), which restores the original item 36 proof
    (a step 0.5m from the apple's center stays open; the step exactly on
    it is blocked) under the new, more physically accurate rule --
    documented directly on the `occupancy_radius` export so a future
    object with a different actor's capsule radius in mind tunes it
    correctly the first time.
    Verified with an 8/8 headless suite (`verify_physics_obstruction.gd`,
    scratchpad, run against the real `tactical_demo_world.tscn`, not a
    synthetic stand-in): a solid perimeter wall cell (away from the
    doorway) rejects a step into it; a straight walk through the actual
    doorway gap succeeds end-to-end; the Chest (full-cell) rejects
    stepping onto its cell; the Apple (footprint) leaves a step 0.5m
    away open while still blocking the exact step on top of it, restoring
    item 36's original proof; `check_object_collision = false` lets an
    actor pass through the Chest while a wall still blocks it regardless;
    and a diagonal step into a target cell with a blocker at ONLY the
    far diagonal corner (both edge-adjacent cells left open) is still
    correctly rejected -- the exact item 32 corner case, now handled for
    free by real shape geometry instead of the direction-independent
    4-neighbor probe loop item 32 had to add by hand. The first run of
    this suite caught two real bugs before they were ever chalked up as
    "the physics rewrite doesn't work": a test-harness bug (not
    resetting `is_moving` between manually-repositioned test cases,
    which made every `request_move()` after the first silently
    auto-reject) that produced two false FAILs, and the genuine
    `occupancy_radius` tuning issue above, caught by a THIRD failure that
    survived fixing the harness bug -- not waved off as "probably the
    test's fault" a second time.

39. **`GameStateManager`'s dead-requester cleanup was rewritten from a
    `WeakRef` + per-frame `_process()` sweep to a `tree_exited`-signal
    hook, replacing the standing poll with an event that only fires when
    there's actually something to clean up.** The old design's own
    header was explicit that the per-frame sweep was a FAILSAFE, not the
    primary path (every public method already pruned before doing its
    own work) -- but it still ran, unconditionally, every single frame,
    for the entire life of the game, to guard against an event (a
    requester freed without calling `release_pause()`) that in practice
    happens a handful of times per session at most. A continuous
    per-frame cost paid to guard against a rare event is exactly the
    "contradicts decoupled signal-driven architecture" problem it was
    flagged for.
    Fixed by connecting to the requester's own built-in `tree_exited`
    signal the first time it makes a request (`_sync_requester_connection()`),
    and disconnecting again once it has zero active requests left --
    idempotent either direction, and at most one connection per
    requester regardless of how many different `reason`s it holds
    simultaneously. `_on_requester_tree_exited()` releases every request
    that requester still held, the same as if it had called
    `release_all_from()` on its own way out. `_process()` and the
    `_prune_dead_requests()` sweep it drove are both gone entirely --
    there's no standing loop left to remove requests, so nothing runs
    at all in an idle frame with no pause activity. `PauseRequest.requester`
    is now a hard `Node` reference instead of a `WeakRef`, which is safe
    specifically BECAUSE cleanup is now guaranteed to run before the
    requester is actually freed: Godot removes a node from its tree
    (firing `tree_exited`) as part of the deletion sequence, strictly
    before the node object itself is destroyed, so there's no window
    where a request could be pointing at a truly-dead object. A useful
    side effect: `pause_request_removed`'s `requester` argument is now
    ALWAYS the real object, even in the automatic-cleanup case -- the old
    `WeakRef` version had to pass `null` there since by the time a dead
    ref was pruned the requester was already gone.
    Requesters are now typed `Node` (not the old `Object`) at the
    `request_pause()` call site, since `tree_exited` is a Node-specific
    signal -- every real requester in this project (`InteractionController`,
    and every anticipated future one: a cutscene player, a menu) already
    was one in practice, so this makes an existing implicit constraint
    explicit rather than narrowing anything real.
    One accepted, documented scope limit, flagged rather than silently
    assumed away: `tree_exited` fires on ANY removal from the tree, not
    only final deletion -- a requester that's deliberately REPARENTED
    (removed then immediately re-added elsewhere) would trigger this
    cleanup too, releasing its request even though the node is still
    alive. Nothing in this project currently reparents a pause requester;
    a future one that needs to survive reparenting would need to
    re-request pause after being re-added, the same extra step it would
    need for any other per-tree setup.
    Verified with an 8/8 headless suite (part of
    `verify_pause_and_interaction.gd`, scratchpad, against a real
    instantiated `GameStateManager`, not a mock): a single request
    pauses; an idempotent repeat from the same (requester, reason) does
    not duplicate; a second requester with a different reason adds a
    genuinely separate request; releasing one requester's request
    leaves a different, still-active requester's claim intact (the
    exact bug this whole file exists to prevent -- see the file header);
    and, the case this ticket was actually about, freeing a requester
    node WITHOUT ever calling `release_pause()` correctly and
    automatically clears its request with no polling involved, confirmed
    by checking `has_pause_requests()`/`active_pause_count()` immediately
    after the freed node's `tree_exited` had a chance to fire.

40. **`follower.gd` (`Follower`) added — a trailing-step companion NPC,
    proven live in `tactical_demo_world.tscn` with a second sprite skin
    (`stand2.png`/`run2.png`/`jump2.png`).** Deliberately NOT a
    distance-chase (checking the leader's current position each move and
    stepping toward it) -- that would need the follower to reason about
    obstacles independently, the same "the grid is a bad abstraction for
    volume intersections" problem item 38 just solved for the player,
    reappearing for free on a second actor. Instead, the follower
    literally REPLAYS the leader's own step-direction history,
    `trail_steps` (default 2) moves behind: every leader `move_started`
    pushes a direction onto a queue; the follower only pops and attempts
    the OLDEST queued direction once the queue is MORE than `trail_steps`
    deep, so at rest exactly `trail_steps` directions sit unconsumed.
    Consuming one move re-triggers a check for the next (via the
    follower's own `move_finished`), so it catches back up over several
    frames if it fell behind while the leader kept moving, rather than
    needing a fresh nudge per remaining step. A failed `request_move()`
    (something occupies a cell between the leader passing through and
    the follower catching up -- possible in principle, if unlikely with
    only these two actors in the demo) is left at the FRONT of the queue
    rather than dropped, so the next trigger retries the same direction
    instead of silently skipping a step and drifting off the leader's
    actual path. The guarantee this produces is a TEMPORAL lag (the
    follower mirrors wherever the leader was `trail_steps` of the
    leader's OWN moves ago), not a constant spatial offset from spawn --
    worth knowing before writing a test or a tuning pass against this
    that assumes otherwise (a first draft of this file's own regression
    test made exactly that wrong assumption; see the verification note
    below).
    Reuses `GridActor` unmodified as the follower's own movement
    primitive (same pattern as `grid_actor_player_input.gd`: a separate
    driver `Node`, not a GridActor subclass) -- the follower's
    `CharacterBody3D` sits on Godot's default physics layer (1), outside
    both `GridActor.WALL_COLLISION_LAYER_BIT`/`OBJECT_COLLISION_LAYER_BIT`
    (item 38), so the player and the follower never obstruct each other;
    only real walls/objects do.
    Real bug caught before shipping, the exact ready-order class this
    project has hit repeatedly (`sprite_actor.gd`'s old `actor` setter,
    `debug_grid_overlay.gd`'s deferred build): `Follower._ready()`
    originally connected to `leader.move_started` directly, but Godot
    calls a CHILD's `_ready()` before its PARENT's -- and the parent
    scene script (`tactical_demo_world.gd`) is what assigns `leader`, so
    the connection attempt ran while `leader` was still null and
    silently connected to nothing, permanently (nothing ever retried
    it). The follower never moved at all in the first test run, caught
    immediately rather than assumed to be a queue-logic bug. Fixed by
    making `leader` a property SETTER that connects/reconnects whenever
    it's actually assigned, the same fix shape `sprite_actor.gd` already
    used for the identical problem -- correct regardless of which order
    `_ready()` calls happen to run in.
    Verified with a 7/7 headless suite (`verify_follower.gd`, scratchpad,
    against the real `tactical_demo_world.tscn`): `leader`/`actor` wiring
    resolved correctly (proving the ready-order fix), the follower's
    queue settles back to exactly `trail_steps` entries after the leader
    takes several steps, the follower replays exactly
    `(steps_taken - trail_steps)` of the leader's moves (the real
    temporal-lag guarantee, not the spatial-offset assumption the first
    draft of this test wrongly asserted and had to be corrected), and it
    stays on the leader's exact path (same X for a pure north walk).
    Full scene also run headless 300 frames with the follower present,
    no errors.

41. **Interaction actions were made to actually DO something, and a jump
    test platform was added -- two separate, real gaps flagged in the
    same pass.** Before this: the Chest and Apple were both wired to the
    BARE `interactable.gd` script directly (interaction_flags set from
    the .tscn), which meant pressing F on either dispatched to the base
    class's empty default `_on_open()`/`_on_harvest()` -- the confirm
    panel closed and nothing else happened at all, not even a print.
    Plant and Merchant already had real override methods, but those only
    ever called `print()`, invisible to anyone actually playing the
    scene rather than reading the console.
    Fixed with three small new pieces, each scoped to what currently
    exists rather than guessing ahead at a bigger system (same "flag it,
    don't invent it" convention this file already follows):
    - `core/systems/inventory/inventory.gd` (`Inventory`) -- a plain
      item_id->amount Dictionary with `add_item()`/`remove_item()` and a
      `changed` signal. NOT a typed Item resource system (icons, weight,
      stacking, equip slots) -- nothing needs that yet. Attached as a
      child of the Player only (`Player/Inventory`); handlers look it up
      via `source.get_node_or_null("Inventory")` and no-op if absent, so
      it's opt-in per-actor, not a hard dependency.
    - `core/systems/feedback/game_feedback.gd` (`GameFeedback`) -- a new
      autoload (same shape as `GameStateManager`, including the same
      "no `class_name`, the autoload registration IS the global name"
      reasoning) that shows one transient on-screen line, replacing bare
      `print()` calls for anything a player should actually see happen.
      Deliberately not a dialogue/quest-log system -- one line, replaced
      outright by the next, auto-hides after a fixed duration.
    - `examples/apple.gd` (`ApplePickup`) and `examples/chest.gd`
      (`Chest`) -- new concrete `Interactable` subclasses (following the
      exact pattern `harvestable_plant.gd`/`merchant.gd` already
      established) replacing the bare-script wiring: Apple adds itself
      to the picker's Inventory then `queue_free()`s (a pickup, not a
      regrowing resource); Chest sets `one_shot = true` (previously
      unset -- the bare script never guarded against re-looting either),
      grants loot once, and darkens its mesh + relabels its prompt to
      "Empty" so an already-opened chest reads as looted at a glance.
      `harvestable_plant.gd`'s `_on_harvest()` and `merchant.gd`'s
      `_on_talk()`/`_on_open()` were updated to call into the same two
      new systems instead of only printing. `Merchant.wares` is new
      real `@export` data (not a hardcoded string) specifically so a
      future shop UI has something to read without touching this class
      again -- opening the satchel still doesn't let you buy anything;
      no currency/economy design exists yet, flagged rather than guessed.
    - `core/ui/inventory_hud/inventory_hud.gd` (`InventoryHud`) -- a
      small always-on readout of the Player's Inventory, built
      procedurally (same spirit as `InteractionController._build_panel()`),
      wired in `tactical_demo_world.gd`. Anchored top-RIGHT specifically
      because `debug_grid_overlay.gd`'s (TEMPORARY, see item 25) own
      coordinate HUD already owns the top-left corner -- confirmed by an
      actual rendered screenshot that the two would otherwise stack
      illegibly on top of each other before moving this one.
    Separately, jump (item 35) is unchanged and still purely cosmetic on
    purpose -- this did NOT give the player any real vertical movement or
    a way to land on anything (`GridActor` still has no vertical stepping
    at all; see the file header's verticality note). What was actually
    missing was simpler: nothing in the demo scene had any height
    variation to judge the jump arc against. `tactical_demo_world.gd`'s
    new `_build_jump_test_platform()` adds one solid raised block --
    real collision on the same wall-obstruction layer a perimeter wall
    cell uses (so it also proves solid-object collision against
    something taller than the Chest), positioned off both axes running
    through the origin (same corner-placement convention Chest/Plant
    already use) so it doesn't sit on a cardinal ray any existing
    scripted movement test walks along.
    Verified with a real headless smoke script (not just inspection):
    Chest grants loot exactly once and no-ops on a second open; Apple
    adds to inventory and is actually removed from the scene tree;
    Plant/Merchant both still work through the new path; the jump
    platform exists at its configured position with real collision.
    Also verified with actual rendered screenshots (`--display-driver
    x11 --rendering-driver opengl3`, per this project's own screenshot-
    over-headless-assumption rule): the platform reads clearly as a
    height cue next to the player, the on-screen feedback toast shows
    the pickup message, and the satchel HUD updates live and does not
    overlap the debug coordinate HUD.

42. **Real playtest feedback on item 41 drove three further changes:
    Chest became a real per-item loot picker, Merchant's satchel became
    a real purchase, and jump got a real, bounded step-up onto short
    ledges.** All three were explicit corrections to item 41's first
    pass, not new requests out of nowhere -- flagged here the same way.
    - **Chest, multi-item with player choice.** A chest holding more
      than one kind of item used to grant everything automatically on
      open, with no way to leave something behind. `core/ui/toggle_list_window/`
      is new: `ToggleListWindow` (base class -- owns the pause request,
      procedural panel, and F/Esc/1-9 input handling) with two thin
      subclasses, `LootWindow` and `ShopWindow`, both new autoloads (see
      project.godot). Opening a Chest now shows every item it holds with
      a `[1] [x] Gold Coin x5`-style checkbox row (all CHECKED by
      default -- looting is free, "take everything" is the sane
      default); confirming grants only what's still checked and leaves
      the rest in `Chest.loot` for a later visit. `one_shot` was dropped
      from `chest.gd` entirely -- whether it can still be opened is now
      "is `loot` empty," checked directly, since a partially-looted chest
      must still be re-openable.
    - **Merchant's satchel is a real purchase now, not just a wares
      list.** `Merchant.wares` changed from a flavor-only
      `Array[String]` to a real `item_id -> price` `Dictionary`;
      opening the satchel shows a `ShopWindow` (everything UNCHECKED by
      default -- the opposite default from LootWindow, deliberately,
      since buying costs currency). Spends the same `"gold_coin"` item
      id Chest already grants by default (`ShopWindow.CURRENCY_ITEM_ID`)
      -- a chest's loot is actually spendable here with no separate
      currency-conversion step. Charges each checked row independently
      as it goes, not an all-or-nothing up-front affordability check --
      a row that can't be covered when it's reached is silently skipped
      (not bought), and the feedback message reports both what was
      bought and what was skipped for insufficient funds. Still no
      sell-back, restocking, or haggling -- a real economy design is a
      future decision, not guessed at here.
    - **A real mutual-exclusion gap surfaced building the two windows
      above, caught before shipping, not discovered live:**
      `InteractionController` releases its OWN pause request and closes
      its confirm panel BEFORE calling `target.interact(source)` (see
      `_confirm_interaction()`), so by the time a Chest/Merchant opens a
      LootWindow/ShopWindow, `is_interacting` is already false but the
      tree is now paused for a DIFFERENT reason. Both
      `InteractionController._process()` (rescanning for a nearest
      target) and `_unhandled_input()` (F/Esc/number keys) now bail out
      whenever `not is_interacting and get_tree().paused` -- i.e.
      whenever some OTHER `PROCESS_MODE_ALWAYS` system currently has
      focus -- so pressing F to confirm a loot/purchase can't also,
      simultaneously, start an unrelated new interaction on whatever
      target happened to be nearest before the window opened.
    - **Jump got a real, bounded step-up/step-down** --
      `GridActor.request_jump_step()`, wired to the same jump key
      alongside (not replacing) `sprite_actor.gd`'s existing, unchanged
      purely-cosmetic hop arc. `Ledge` (`ledge.gd`, new) is a declarative
      walkable-footprint marker (height + X/Z size, NOT physics-probed --
      same "flag it, don't invent it" reasoning as the rest of this
      file) -- `tactical_demo_world.gd`'s jump-test platform now carries
      one, built from the SAME local variables as its visual mesh and
      collision box so the three can't drift apart. `GridActor` gained
      `current_ground_height` (world-space Y the actor currently stands
      at; 0.0 everywhere except on a Ledge) and `_current_ledge`
      (which one, if any); `request_move()` (plain WASD) only ever
      READS these -- it operates at whatever height the actor is
      currently at, and while on a ledge, REFUSES to step outside that
      ledge's own footprint (treated exactly like an obstruction: face
      the direction, don't move) -- leaving a ledge requires the
      deliberate jump key, never a walk off the edge into open air with
      no floor under it. `request_jump_step()` is the ONLY thing that
      ever changes `current_ground_height`: from the base floor it can
      step UP onto a Ledge directly ahead if the height difference is
      within `max_step_height` and there's room to stand there (checked
      with the same real physics shape-query `request_move()` already
      used, just at the candidate height); while ON a ledge it can only
      step back DOWN to the base floor, by stepping outside the ledge's
      footprint. Explicitly NOT a general climbing/multi-story
      verticality system -- no ledge-to-ledge hops, no stacking, exactly
      one Ledge exists in this framework right now. `step_to_world()`/
      `current_step` themselves are UNCHANGED (`current_step.y` still
      always 0) -- the new Y state lives entirely alongside them in
      `current_ground_height`, not inside the step lattice, specifically
      so every existing flat-ground behavior/regression stays untouched
      wherever a Ledge isn't involved.
    Verified with a real headless script exercising the actual scene
    (not a synthetic stand-in): a chest with three item types lets a
    specific item be left unchecked and taken later on a second visit;
    a merchant purchase correctly fails with insufficient gold and
    succeeds (deducting exactly the right amount) once funded; plain
    `request_move()` toward the jump platform is rejected while
    `request_jump_step()` in the same direction succeeds and lands
    EXACTLY at the ledge's declared height; walking around ON TOP of the
    platform works within its footprint and is blocked at its edge;
    jumping back off from the edge returns the actor to exactly Y=0.0.
    Also verified with real rendered screenshots
    (`--display-driver x11 --rendering-driver opengl3`): the loot
    window's checkbox rows and Satchel HUD update correctly on screen,
    and a before/after pair visually confirms the player standing on
    the floor next to the platform vs. standing on top of it after one
    jump-key press. Full scene also re-run 300 frames headless with the
    new autoloads present, no errors.

## Try it

Open `core/scenes/tactical_demo_world.tscn` in the Godot 4.6 editor and
run it. WASD/arrows move the player one grid cell at a time; Q/E rotate
the camera; mouse wheel zooms. The hotbar at the bottom of the screen
can be dragged anywhere and responds to keys 1–9 and 0.
