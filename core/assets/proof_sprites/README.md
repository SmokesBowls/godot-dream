# Proof sprites — temporary, not final art

`player/stand.png`, `player/run.png`, `player/jump.png` are copied
verbatim from Godot's official "2.5d" demo project
(`godotengine/godot-demo-projects`, asset by Aaron Franke — see
`/mnt/data-drive/Godot-2.5-Demo-main`). That repo is MIT-licensed on the
engine/code side; this local copy doesn't carry its own `LICENSE` file,
so if any of this art (as opposed to the technique) ends up shipping,
pull the actual upstream `LICENSE` for provenance rather than relying on
this note.

**These exist to prove the billboarded-Sprite3D pipeline works, not as
final character art.** It's a sci-fi robot; this project is a
Balrum-inspired fantasy temple/RPG. Replace before shipping.

Exact frame layout (measured directly from the PNGs + confirmed against
the donor project's `player_25d.tscn`, not guessed):

| File | Size | Layout | Meaning |
|---|---|---|---|
| `stand.png` | 64×320 | 1 col × 5 rows, 64×64/frame | idle pose, one frame per direction |
| `run.png` | 384×320 | 6 cols × 5 rows, 64×64/frame | 6-frame run cycle per direction |
| `jump.png` | 128×320 | 2 cols × 5 rows, 64×64/frame | rising/falling pose per direction — **not wired up yet** |

Row = direction (0–4), mirrored via `flip_h` for the opposite
horizontal side — see `sprite_actor.gd`'s header comment for the full
row/flip mapping and why it's keyed off camera-relative angle here
instead of raw world direction (the donor project's camera never
rotates; ours does).

**Known limitation, confirmed by looking at the actual frames**: in
`stand.png`, rows 0, 1, 3, and 4 are nearly visually identical — this
robot doesn't have a distinct back-view pose, only row 2 (true side
profile) reads as clearly directional. The mapping code is correct
regardless; the art just doesn't show it well. Worth knowing before
concluding the direction logic is broken from a screenshot alone.
