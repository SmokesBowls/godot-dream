# DREAM WORLD BOUNDARY 1 CONTRACT

Status: CONTRACT ONLY — IMPLEMENTATION NOT AUTHORIZED

Version: 1.0

Repository: `/mnt/data-drive/godot-dream`

Milestone:

```text
Room A
→ alter traveler state and Room A state
→ cross a named exit
→ arrive through a named entrance in Room B
→ return through a named entrance in Room A
→ the same traveler survives
→ Room A remembers
```

## 1. Purpose

This contract defines the first boundary by which Dream stops being one scene containing mechanics and becomes a runtime capable of containing a world.

The proof is deliberately limited to two small rooms and one in-process round trip:

```text
TEST ROOM A → TEST ROOM B → TEST ROOM A
```

The boundary freezes:

- which objects survive room replacement;
- which objects belong to a room;
- who owns transition pause and lifecycle;
- how exits identify destinations and entrances;
- how a destination is staged and validated before destructive change;
- how traveler identity is proven;
- how Room A remembers an apple and a partially looted chest;
- how malformed transitions fail without destroying the current world.

This contract does not authorize implementation.

## 2. Non-goals and forbidden scope

Dream World Boundary 1 must not introduce or absorb:

- save files or save slots;
- persistence across application restart;
- Dream Event Store integration;
- generalized serialization or migration systems;
- Falcon Ridge or another production location;
- quests or quest architecture;
- combat;
- follower repair, follower AI, or companion schedules;
- dialogue trees;
- world streaming;
- procedural room graphs;
- forced transition during an active interaction, loot window, or shop window;
- camera elevation sprite variants or camera presentation refinement;
- final UI or final art;
- copies of `tactical_demo_world.gd` used as Room A and Room B;
- assigning `akashic.tscn` persistent-world ownership without a separately reviewed implementation decision.

Closing Godot and reopening it may forget all traveler and room state for this milestone.

## 3. Closed ownership decisions

### 3.1 Persistent traveler

The same live Player node instance and the same live Inventory node instance must survive every successful Room A → Room B → Room A transition.

```text
Player instance before transition == Player instance after transition
Inventory instance before transition == Inventory instance after transition
```

Traveler inventory must not be reconstructed merely by reproducing expected item counts.

The Inventory remains a child of Player for this milestone so existing interactables may continue resolving:

```text
source/Inventory
```

Room replacement must never free, duplicate, or replace Player or Inventory.

### 3.2 Persistent camera

One TacticalCameraRig survives room replacement with the traveler/world-shell role.

The persistent camera:

- continues following the persistent Player;
- retains its live camera state unless a future, separately authorized room-camera-profile contract says otherwise;
- remains the camera reference used by persistent traveler-facing presentation and input systems;
- is not recreated for each room in this milestone.

Future rooms may eventually propose camera profiles such as bounds, preferred zoom, or allowed pitch/distance ranges. No room-camera-profile format is defined here.

CameraModeController belongs with the persistent camera/traveler side of the boundary, not with the replaceable room.

### 3.3 Room-local interaction

Each active room owns its own InteractionController.

The room-local InteractionController owns:

- its room's GridMap reference;
- wall item IDs and line-of-sight configuration;
- discovery of the room's interactables;
- current target and active interaction session;
- its generated interaction panel;
- its own `&"interaction"` pause request when an interaction is active.

When a room is activated, its InteractionController receives references to:

- the persistent Player;
- the persistent TacticalCameraRig.

InteractionController is not made persistent and no `bind_room()`/`unbind_room()` lifecycle is introduced in this milestone.

### 3.4 Persistent transition coordinator

Exactly one transition coordinator survives room replacement.

Only that persistent coordinator may own the `&"transition"` pause request.

Room-local Exit nodes may create and submit transition requests. They must not:

- own transition pause;
- remove the current room;
- instantiate or install another room;
- place the Player;
- mutate traveler or room-state storage;
- decide that a malformed transition may continue.

### 3.5 Persistent in-memory room-state store

One in-memory room-state store survives room replacement for the duration of the running process.

It owns remembered Room A and Room B consequence records only. It does not own:

- Player or Inventory;
- room geometry;
- node instances;
- disk persistence;
- canon;
- quests;
- event history.

## 4. Persistent runtime role without premature naming

The runtime must contain a persistent composition role equivalent to:

```text
persistent runtime role
├── Player
│   └── Inventory
├── TacticalCameraRig
├── CameraModeController
├── TransitionCoordinator
├── InMemoryRoomStateStore
├── persistent UI/services as already justified
└── RoomContainer
    └── ActiveRoom
```

This contract defines the role, not its final node, scene, script, or class name.

`akashic.tscn` is only a candidate. It currently has no script or established world-shell authority. Giving it this role is a future implementation decision, not a fact established by this contract.

## 5. Room ownership

An active room owns:

- one semantic `room_id`;
- local geometry and visual environment;
- local collision;
- its local GridMap, if used;
- one room-local InteractionController;
- named entrances;
- named exits;
- local interactables;
- local stateful room objects;
- room-local debug/proof elements, if any.

A room must not own:

- Player;
- Inventory;
- TacticalCameraRig;
- CameraModeController;
- TransitionCoordinator;
- in-memory room-state storage;
- transition pause;
- existing autoload services.

Room A and Room B must be tiny purpose-built fixtures. They must not be duplicated copies of the tactical demo compositor.

## 6. Semantic identity

World identities must be explicit authored semantic IDs.

Required first-proof identities include:

```text
room_a
room_b
apple_01
chest_01
east_exit
west_exit
east_entrance
west_entrance
```

Semantic identity must never be derived from:

- NodePath;
- world coordinates;
- child index;
- array position;
- runtime instance ID;
- `.tscn` `unique_id`;
- display name;
- generated traversal order.

Within one room:

- `room_id` must exist exactly once;
- every entrance ID must be non-empty and unique;
- every exit ID must be non-empty and unique;
- every stateful object ID must be non-empty and unique.

A room-state address is the pair:

```text
(room_id, object_id)
```

For display and evidence it may be rendered as:

```text
room_a/apple_01
room_a/chest_01
```

## 7. Transition request

A room-local Exit may submit an immutable request containing exactly the transition identity needed by the coordinator:

```text
TransitionRequest
  source_room_id
  exit_id
  destination_room_id
  destination_entrance_id
```

The request must not contain:

- destination world coordinates;
- a Player reference;
- an Inventory snapshot;
- a camera transform;
- direct room-state mutations;
- an instruction to free the current room;
- a success claim.

The coordinator must reject a stale or mismatched request when:

- `source_room_id` is not the active room ID;
- `exit_id` is not a valid exit of the active room;
- destination identity cannot be resolved;
- the destination entrance is missing or ambiguous.

A destination room owns the Transform3D associated with each of its entrance IDs. Other rooms do not know that transform.

## 8. Modal fail-closed rule

For Dream World Boundary 1, transition is forbidden while any of these is active:

- the current room's InteractionController interaction session;
- LootWindow;
- ShopWindow.

The coordinator must reject the transition before room staging or teardown.

It must not:

- close the modal automatically;
- cancel the interaction automatically;
- invoke a retained room-local callback after teardown;
- hide the refusal;
- treat a paused tree as permission to force travel.

Forced or scripted transition during modal state requires a future close/cancel contract.

## 9. Pause ownership and paused execution

TransitionCoordinator must acquire its own pause claim:

```text
GameStateManager.request_pause(TransitionCoordinator, &"transition")
```

The Exit node must not own that claim.

TransitionCoordinator releases only its own claim:

```text
GameStateManager.release_pause(TransitionCoordinator, &"transition")
```

Other active pause claims must remain effective.

Observed Godot 4.6.1 evidence established that, for a normal node in this project:

- ordinary `_process()` calls stop while paused;
- `await get_tree().process_frame` resumes while paused;
- a default `SceneTreeTimer` timeout resumes while paused.

This evidence must not be generalized to all await sources.

Any transition implementation that awaits a Timer node, Tween, AnimationPlayer, room-owned signal, loading callback, fade, or other source must prove that exact source can complete under the effective pause configuration. No unproven await may sit between transition pause acquisition and release.

## 10. Destination staging and atomicity

The governing transition invariant is:

```text
validate destination completely
→ then permit destructive replacement of the current room
```

Never:

```text
destroy current room
→ hope destination loads and contains a usable entrance
```

A staged destination must not become the active world before commit. During staging it must not:

- accept gameplay input;
- register itself as the active room;
- become the active camera;
- request gameplay pause;
- expose duplicate active interactables;
- collide with the current room;
- mutate traveler state;
- mutate remembered room state merely by being inspected.

The first fixtures must declare their room interface and entrance data so structural validation does not depend on gameplay `_process()` or a pausable room-owned signal.

Before commit, validation must prove:

- destination resource resolves;
- destination can be instantiated;
- destination has exactly one expected `room_id`;
- staged `room_id` equals `destination_room_id`;
- requested entrance exists exactly once;
- entrance supplies a valid finite Transform3D;
- required room-local InteractionController exists exactly once;
- required room bindings can be supplied;
- remembered destination-state records are structurally applicable;
- current room state can be captured successfully.

If any pre-commit validation fails:

- discard the staged destination;
- leave the current room active and untouched;
- leave Player and Inventory untouched;
- leave remembered room state unchanged;
- release only the coordinator's transition pause, if acquired;
- report a visible failure;
- stop the transition.

No failure before commit may strand the Player without a valid current room.

## 11. Normative transition lifecycle

A successful transition follows this order:

```text
1.  Room-local Exit creates TransitionRequest.
2.  Persistent TransitionCoordinator receives it.
3.  Coordinator verifies that no interaction/loot/shop modal forbids travel.
4.  Coordinator verifies source_room_id and exit_id against the active room.
5.  Coordinator acquires its own &"transition" pause claim.
6.  Resolve destination resource without touching the current room.
7.  Instantiate destination in a non-active staging state.
8.  Validate the complete pre-commit destination and state boundary.
9.  If validation fails, execute the fail-closed path and stop.
10. Capture current room state successfully.
11. Commit the room replacement.
12. Apply remembered destination room state.
13. Supply persistent Player and TacticalCameraRig references to the
    destination room's local systems.
14. Place the persistent Player at the requested destination entrance.
15. Verify required post-commit bindings and active-room identity.
16. Release the coordinator's &"transition" pause claim.
17. Gameplay resumes if no other pause requester remains.
```

Post-commit operations must be deterministic consequences of already validated prerequisites. Implementations must not defer discovery of a required binding until after the old room is irreversibly lost.

## 12. Traveler state proof

The first proof must capture the Player and Inventory runtime instance identities before leaving Room A.

After arrival in Room B and again after returning to Room A, it must prove:

```text
same Player instance
same Inventory instance
same inventory mutations
```

Required inventory consequence:

- apple taken from Room A remains in the same Inventory;
- loot taken from Room A chest remains in the same Inventory.

Inventory counts alone do not satisfy the identity proof.

## 13. Room state proof

### 13.1 Apple

The first apple consequence is:

```text
room_a/apple_01
  collected = true
```

When `collected` is true, returning to Room A must not recreate an available apple pickup.

The remembered state is not inferred merely because a node happened to be absent in one scene instance.

### 13.2 Chest

The first chest consequence is:

```text
room_a/chest_01
  remaining_loot = {
    ... exact remaining item_id → amount entries ...
  }
```

A chest is not represented only as `opened = true`.

The proof must distinguish:

- never opened/full;
- opened but partially looted;
- empty.

On return to Room A:

- exact remaining loot must be restored;
- taken entries must not reappear;
- empty visual/prompt state must be derived consistently when no loot remains.

Room-state capture and application must not create or remove traveler inventory items by themselves.

## 14. UI and service boundary

Existing persistent autoloads remain persistent:

- GameStateManager;
- GameFeedback;
- LootWindow;
- ShopWindow.

This contract does not require every visible UI node to persist as the same instance.

Whether InventoryHud and HotbarContainer survive as nodes or are rebound/recreated is an implementation detail only if all of these remain true:

- UI never owns authoritative traveler state;
- InventoryHud observes the same persistent Inventory after every transition;
- stale signal connections are not retained;
- hotbar/input remains functional after both transitions;
- room teardown cannot leave a persistent modal holding an active room-local callback.

## 15. Required positive acceptance proof

The first live proof must demonstrate:

```text
1.  Begin in Room A at its declared starting entrance.
2.  Record Player and Inventory runtime instance identities.
3.  Pick up room_a/apple_01.
4.  Take a strict subset or declared portion of room_a/chest_01 loot so
    remaining_loot is observable.
5.  Confirm both traveler inventory mutations.
6.  Leave through Room A's named exit.
7.  Arrive in Room B through the requested named entrance.
8.  Prove the same Player instance survived.
9.  Prove the same Inventory instance survived.
10. Prove controls, camera, UI, and room-local interaction function in B.
11. Return through Room B's named exit.
12. Arrive in Room A through the requested named entrance.
13. Prove the same Player and Inventory instances again.
14. Prove apple_01 remains collected and unavailable.
15. Prove chest_01 has the exact remembered remaining_loot.
16. Prove controls, camera, UI, collision, and interaction function in A.
17. Prove no transition pause claim remains after successful completion.
```

## 16. Required toxic and refusal proofs

At minimum, the implementation authority must eventually prove these fail closed:

### 16.1 Missing destination resource

```text
unknown destination_room_id
→ current room remains active
→ traveler unchanged
→ no room-state mutation
→ visible failure
```

### 16.2 Missing entrance

```text
valid destination room + unknown entrance ID
→ staged destination discarded
→ current room remains active
→ traveler unchanged
```

### 16.3 Duplicate entrance

```text
destination contains destination_entrance_id more than once
→ reject as ambiguous
→ no commit
```

### 16.4 Room identity mismatch

```text
request says room_b
staged room declares another room_id
→ reject
→ no commit
```

### 16.5 Stale source request

```text
source_room_id or exit_id does not match active room
→ reject
→ no staging side effects
```

### 16.6 Active modal

```text
interaction OR LootWindow OR ShopWindow active
→ transition rejected
→ modal remains active
→ current room untouched
```

### 16.7 Room-local pause requester teardown

Executable evidence must preserve the rule that an Exit-owned pause claim would be released on room teardown and therefore may not be used as transition ownership.

### 16.8 Independent pause claim

If another requester already holds pause, TransitionCoordinator releasing its own claim must not resume gameplay until the other request is released.

### 16.9 State identity collision

Duplicate stateful object IDs within one room must reject room activation or staging before current-room destruction.

## 17. Evidence classes

Future implementation reports must distinguish:

```text
structural validation passed
room transition committed
traveler instance identity preserved
room state captured
room state reapplied
UI rebound or retained
camera retained
live GUI displayed the expected result
```

One class of evidence must not be reported as another.

A headless transition test does not prove GUI presentation. A screenshot does not prove traveler instance identity. Correct item counts do not prove the same Inventory survived.

## 18. Versioning and change control

This is `DREAM_WORLD_BOUNDARY_1_CONTRACT` version 1.0.

Any incompatible change to these closed decisions requires an explicit contract amendment or new version:

- persistent traveler identity;
- persistent camera;
- room-local InteractionController;
- persistent coordinator pause ownership;
- modal transition refusal;
- semantic IDs;
- stage-and-validate-before-destructive-swap;
- in-memory-only room state;
- exact apple/chest consequence shape.

A later save system, forced transition protocol, room camera profile, companion placement system, or quest architecture must build above this boundary rather than silently redefining it.

## 19. Final invariant

```text
Dream World Boundary 1 succeeds only when the same live traveler can
leave a room, enter another through a named boundary, return through a
named boundary, and encounter remembered consequences—while malformed
travel cannot destroy the valid world the traveler already occupies.
```
