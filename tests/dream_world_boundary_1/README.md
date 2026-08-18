# Dream World Boundary 1 — RED test slice

This directory holds `DREAM_WORLD_BOUNDARY_1_TEST_RED`: the test-only
slice authorized against `DREAM_WORLD_BOUNDARY_1_CONTRACT.md` (v1.0,
frozen at commit `b17937e`). It **tests the frozen contract; it does
not implement it.** No `TransitionCoordinator`, `Exit`, in-memory
room-state store, or Room A/B fixture exists yet, and this slice does
not create any of them — that remains unauthorized.

## Run it

```sh
godot --headless -s res://tests/dream_world_boundary_1/run_boundary_1_red.gd
```

## What it checks

- **Non-goal guards (PASS today):** confirms the repo hasn't jumped
  ahead of the contract — no `TransitionCoordinator`/`Exit`/room-state
  store implementation, no `room_a`/`room_b` fixtures, and
  `akashic.tscn` still carries no script (§2, §3.4, §3.5, §4).
- **§15 acceptance proof checklist (BLOCKED today):** every numbered
  step of the required positive proof, each tied to the exact contract
  clause it comes from.
- **§16 toxic/refusal proof checklist (BLOCKED today):** all nine
  fail-closed cases (§16.1–§16.9), same treatment.
- **Expressibility blockers:** contract clauses this slice could not
  even encode as a runnable test without inventing an unauthorized
  implementation detail on the contract's behalf (see the runner's
  printed report for the current list — currently §4/§5 naming, §17's
  GUI-evidence exclusion, and §13's not-yet-defined chest loot schema).

## Current result (last verified run)

```
PASS:    5
FAIL:    0
BLOCKED: 26 (expected — §1: implementation not authorized)
```

Exit code `1`. This is the correct RED result: every BLOCKED case is
expected to flip to executable once a future, separately authorized
implementation slice creates the entities the contract's ownership
sections (§3–§5) reserve. A green run of this file, today, without
those entities existing, would itself be evidence something was
implemented without authorization.
