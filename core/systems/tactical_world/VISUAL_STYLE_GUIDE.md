# Visual style guide — tactical 3D RPG (Balrum → 3D)

Goal: pulled-back, elevated tactical camera (see `tactical_camera.gd`)
means props are always seen small and at a steep angle. That framing
punishes two opposite mistakes — high-poly/PBR detail that's invisible
at this distance and wasted at render time, and flat primitive shapes
that read as "blocky" because there's nothing to break up the silhouette
from above. The target is legible silhouettes with minimal tris, not
detail.

## Polygon budgets (guidelines, not hard limits)

| Category | Triangle budget | Why |
|---|---|---|
| Small props (rocks, mushrooms, tools, single plants) | 100–400 | Seen at a distance, in clusters — cost adds up fast per-instance |
| Mid props (furniture, chests, garden beds, single trees) | 400–1,200 | Focal points, but still one of many on screen |
| Buildings (modular wall/roof/door pieces) | 800–2,500 per piece | Assembled from repeated pieces via GridMap/MultiMesh, not one high-detail mesh |
| Terrain (GridMap floor/wall tiles) | 20–150 per tile | Flat-shaded, no need for terrain-sculpt density at this camera angle |
| Hero elements (unique landmarks: a ruined tower, a named cottage) | 2,000–6,000 total | The rare exception — spend budget where the eye actually lands |

Rule of thumb: if a prop is one of more than ~5 instances visible in a
single frame (grass, garden rows, rubble, trees in a forest edge),
budget it at the bottom of its category and lean on instancing
(`MultiMeshInstance3D` / GridMap repeated items) rather than unique
geometry.

## Avoiding "blocky" without going high-poly

The "blocky" look isn't caused by low tri counts — it's caused by low
tri counts *combined with* flat, single-color faces and hard 90°
silhouettes with no secondary detail. Fixes that don't cost more
triangles:

- **Chamfer/bevel key edges** (roof lines, chest lids, doorframes) by a
  few degrees. A beveled edge catches light differently on each side of
  the bevel, which reads as more detail than it costs.
- **Vertex color for material variation** instead of a second texture
  or extra geometry — a stone wall with three grey vertex-color bands
  reads as "aged stone", not "grey box", for zero extra tris.
- **Break large flat faces** with one inset or extrusion (a door panel
  recessed slightly, a roof ridge raised) rather than more faces
  overall — silhouette breaks read from the tactical camera angle even
  at small screen size; flat color changes mostly don't.
- **Trim sheets over unique textures.** One shared 512–1024px trim
  texture (wood grain, stone edge, thatch) tiled across many props
  keeps texture memory flat as the prop count grows, and keeps the
  palette consistent across the whole world, which matters more than
  per-prop detail at this zoom level.

## Shading

Standard PBR (metallic/roughness maps, detail normal maps) mostly
doesn't survive the pull-back/high-angle framing — the specular detail
it's built for isn't visible at this distance and viewing angle, and it
pushes toward a "realistic" look that fights a handcrafted, readable
world. Prefer:

- `StandardMaterial3D` with `shading_mode = PER_VERTEX` or a simple
  toon/cel ramp for a flatter, more illustrative look, OR
- keep PBR but flatten it deliberately: low roughness variance, no
  detail normal maps, rely on the base albedo + vertex color for
  variation instead of micro-surface detail that won't render at this
  distance anyway.
- A thin outline pass (inverted-hull or a screen-space outline
  post-process) reinforces object-vs-object separation at a distance,
  which matters more here than it would in a close-up camera game —
  it's what makes "every visible object has meaning" actually readable
  instead of a color-blob.

## Depth and verticality cues (the actual Balrum → 3D delta)

Balrum's flat maps read at a glance because everything is on one plane
and nothing occludes anything else. The 3D version trades that legibility
for real verticality (hills, towers, layered interiors) — so it has to
earn that back with depth cues instead:

- **Fog** (see the demo scene's `Environment.fog_enabled`) at a light
  density does double duty: it's the reason hills and towers can block
  line of sight and still look intentional rather than like a
  draw-distance bug, and it gives distant clusters a soft falloff that
  keeps the "meaningful environment cluster" readable against everything
  farther away.
- **Height-based color/light bias**: slightly warmer/brighter light on
  raised terrain, cooler/darker in valleys and interiors, so the camera
  can read elevation changes without needing exaggerated geometry.
- **Consistent tile height increments.** Keep vertical level changes
  (a raised garden bed, a sunken cellar, a hill terrace) in whole-cell
  multiples of `cell_size.y` wherever they're walkable, so grid-snapped
  movement (`grid_actor.gd`) never has to fake a slope — actual walkable
  verticality should be stepped, not ramped, to stay consistent with the
  discrete-grid movement model.

## Camera-driven constraints

`tactical_camera.gd`'s pitch is clamped to 35°–80° by default — never
flat top-down, never shoulder-height. Two consequences for art:

- Roofs and tops-of-props are visible more often than in a third-person
  game — don't leave roof meshes untextured/unshaded assuming they're
  never seen.
- Aggressive LOD/billboarding for foliage (distant trees as
  camera-facing billboards, near trees as real meshes) is safe here in
  a way it wouldn't be in a close first-person camera, because the
  tactical camera's zoomed-out framing means distant foliage is small
  on screen regardless of LOD quality — spend the saved budget on the
  near/mid clusters that are actually being looked at.
