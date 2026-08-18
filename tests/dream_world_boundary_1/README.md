# Dream World Boundary 1 — contract test authority

This directory began as `DREAM_WORLD_BOUNDARY_1_TEST_RED`, the test-only
slice frozen against `DREAM_WORLD_BOUNDARY_1_CONTRACT.md` v1.0.

Historical boundaries:

```text
b17937e  contract frozen; implementation not begun
2ff8945  test-only RED; 5 PASS, 0 FAIL, 26 BLOCKED
```

`DREAM_WORLD_BOUNDARY_1_MINIMAL_TRANSITION_GREEN` was subsequently
authorized. The same runner now converts only the executable A → B
transition-lifecycle requirements into PASS/FAIL evidence. Requirements
owned by the later room-state and live-GUI slices remain explicitly
BLOCKED rather than being pulled into this implementation.

## Run it

```sh
godot --headless -s res://tests/dream_world_boundary_1/run_boundary_1_red.gd
```

The filename preserves the historical RED authority. It is not a claim
that the complete milestone is green.

## What is executable in minimal transition GREEN

- persistent runtime shell composition;
- immutable semantic `TransitionRequest` value behavior;
- semantic room, exit, and entrance identities;
- same `Player` and `Inventory` object identities across A → B;
- persistent `TacticalCameraRig` and `CameraModeController` bindings;
- room-local `InteractionController` replacement and rebinding;
- optional room-local `GridMap` validation and rebinding when present;
- destination staging before Room A teardown;
- missing resource, missing/duplicate/non-finite/singular entrance, invalid final
  composed transform, mismatched or nested room identity, missing local controller,
  and stale source refusal;
- staged-room inactivity on refusal;
- interaction, loot, and shop modal refusal without forced closure, including
  modal state opened synchronously by a transition callback;
- coordinator-owned transition pause and independent pause preservation;
- exact authored named-entrance Transform3D placement, including a
  non-grid-aligned entrance;
- movement and interaction after arrival in Room B;
- persistent inventory HUD and hotbar bindings.

## Intentionally still BLOCKED

Exactly 11 requirements remain outside this slice:

- §15.3–§15.5: Room A apple/chest consequence setup;
- §15.10: complete GUI presentation proof in Room B;
- §15.11–§15.16: B → A return, identity after round trip, exact apple and
  chest restoration, and post-return live behavior;
- §16.9: stateful-object identity collision validation.

Those blockers belong to the room-state GREEN and later live Godot proof.
They are not failures of minimal A → B GREEN.

## Current selective result

Last verified after the minimal implementation:

```text
PASS:    57
FAIL:    0
BLOCKED: 11 (intentional later-slice requirements)
SLICE:   GREEN
MILESTONE: incomplete until deferred room-state/live proofs run
```

Exit code is `0` when every currently authorized executable check passes.
The runner continues to print the eleven deferred blockers so a selective
GREEN cannot be mistaken for completion of Dream World Boundary 1.
