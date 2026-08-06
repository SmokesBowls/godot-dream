# Dream Event Store — Godot 3.x → 4.6 Port

## What changed and why

All Godot-version-sensitive calls were moved into `dream_persistence_adapter.gd`.
`dream_event_store.gd` now only ever calls `persistence.<method>()` for file I/O,
timing, hashing, and threading — it never touches `FileAccess`, `DirAccess`,
`Time`, `OS`, or `Thread` directly.

If Godot 5 changes these APIs again, only the adapter needs to change.
The checkpoint priority logic, replay logic, snapshot capture, and integrity
hashing in `dream_event_store.gd` should not need to move.

## Concrete API swaps made (3.x → 4.6)

| Godot 3.x | Godot 4.6 |
|---|---|
| `File.new()` / `file.open(path, File.WRITE)` | `FileAccess.open(path, FileAccess.WRITE)` |
| `Directory.new()` / `dir.dir_exists()` | `DirAccess.dir_exists_absolute()` |
| `dir.make_dir_recursive()` | `DirAccess.make_dir_recursive_absolute()` |
| `dir.remove(path)` | `DirAccess.remove_absolute(path)` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `OS.delay_msec()` | still `OS.delay_msec()` (unchanged, isolated in adapter anyway) |
| `var2bytes()` / `bytes2var()` | `var_to_bytes()` / `bytes_to_var()` |
| `signal.connect("name", self, "method")` | `signal.connect(Callable(self, "method"))` (or `signal.connect(method)`) |
| `thread.start(self, "method")` | `thread.start(Callable(self, "method"))` |
| `array.remove(i)` | `array.remove_at(i)` |
| `abs()` on float | `absf()` |
| `clamp()` on float | `clampf()` |
| untyped `enum`/dict access patterns | mostly unchanged, added types where cheap |

## Things I flagged rather than guessed at

The original script's `replay_single_event_safe` dispatched to
`replay_npc_behavior_change` and `replay_inventory_change`, but the
pasted source never defined bodies for those two methods. Rather than
invent restore behavior for NPC state and inventory state — which
would be a real design decision (what does "restore an NPC's
behavior" mean exactly? snapshot-overwrite? blend?) — I added them as
explicit no-op hook points with a comment saying so. **These need real
implementations before replay is trustworthy for those two event
types.** Don't treat the "no-op success" as silently correct; it's a
placeholder.

`_on_dream_corrupted`, `_on_reality_shift`, `_on_entropy_threshold_crossed`
were referenced by `connect_to_systems()` in the original but their
handler bodies weren't in the pasted source either. I wrote minimal
plausible bodies based on event types that already existed in the enum
(`CORRUPTION_DETECTED`, `REALITY_SHIFTED`, `ENTROPY_CHANGED`) so the
file actually compiles and the wiring is complete — but check these
against whatever the real `RealityEngine`/`DreamStateManager` signal
signatures are before trusting them.

## Before this runs

1. **Add a `DreamPersistenceAdapter` node** to the same scene/tree as
   `DreamEventStore`, and set `persistence_path` (the `@export NodePath`)
   to point at it in the editor.
2. **Signal names assumed**: `dream_state_changed`, `dream_corrupted`,
   `reality_shift`, `entropy_threshold_crossed`, `priority_changed`,
   `item_changed`. Confirm these match your actual `DreamStateManager`,
   `RealityEngine`, `UI`, and inventory signal declarations — Godot 4's
   typed-signal connect syntax will throw a parse error at scene load
   if a signal name doesn't exist on the object, so this will fail
   loudly rather than silently if wrong.
3. **Autoload references** (`_dream_state_manager`, `_reality_engine`,
   `_physics_stack`, `_global`, `_ui`, `_event_bus`) assume those
   singletons already exist under those exact names in your Autoload
   list, same as the original script assumed. Not changed in this port.
4. **Put this in git**, in the EngAIn repo, today, regardless of
   whether it's wired in yet. The Godot 3→4 port being lost to an OS
   crash is a backup problem, not an engine-churn problem — don't let
   this port become a second instance of that.

## Suggested repo location

Given EngAIn's existing lane structure, this probably belongs under
something like `engainos/godot/dream_system/` or wherever
`GodotSim`-lane runtime systems live in the current clean root —
adjust to match whatever the actual current `engainos/` layout is.
# godot-dream
