# demo_mesh_library.gd
# Godot version: 4.6
#
# Builds a placeholder MeshLibrary at runtime (a flat floor tile and a
# wall block) so the demo scene has something visible in its GridMap
# without needing any imported art assets. This is scaffolding, not
# style guidance -- replace with a real, hand-authored MeshLibrary
# (Scene > Convert To... > MeshLibrary, from a set of modular tile
# meshes) once real props exist. See VISUAL_STYLE_GUIDE.md for what
# those real tiles should look like.
#
# ROOT-CAUSE NOTE (see tactical_camera.gd's fov_deg doc comment for the
# related camera-side finding): this GridMap's `cell_size` used to be a
# uniform (2,2,2) with floor and wall tiles stacked on separate Y-index
# layers. That made every floor cell "own" a full 2-unit-tall volume
# centered on the floor (world y -1..+1) even though the visible floor
# mesh was only 0.2 units thick -- and anything placed inside that
# owned volume (a chest at y=0.35, a plant at y=0.3) got silently
# hidden behind the floor, regardless of camera near/far or shadows.
# Confirmed empirically: a probe at y=0.35 was hidden, one at y=1.0+
# rendered fine, tracking almost exactly with cell_size.y's half-extent.
#
# Fix: floor and walls now share a single, THIN grid layer
# (cell_size.y matches the floor's actual visual thickness), so every
# cell's owned volume is thin too. Walls are still visually 2 units
# tall -- that's done with a per-item mesh_transform offset (see
# `set_item_mesh_transform` below), not by stacking a second grid
# layer. Ground-level props no longer need artificial height clearance
# to render correctly.

class_name DemoMeshLibrary


## Item 0: floor tile, exactly fills its (thin) cell.
## Item 1: wall block, `wall_height` tall, offset so it stands on top of
## the floor layer instead of being centered on it.
static func build(cell_size: Vector3, wall_height: float = 2.0) -> MeshLibrary:
	var lib := MeshLibrary.new()

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = cell_size
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.35, 0.42, 0.3)
	floor_mesh.material = floor_material

	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(cell_size.x, wall_height, cell_size.z)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.5, 0.47, 0.42)
	wall_mesh.material = wall_material

	lib.create_item(0)
	lib.set_item_mesh(0, floor_mesh)
	lib.set_item_name(0, "floor")

	lib.create_item(1)
	lib.set_item_mesh(1, wall_mesh)
	lib.set_item_name(1, "wall")
	# GridMap centers every item's mesh on the cell's own center. The
	# wall shares the floor's thin cell index (see tactical_demo_world.gd
	# -- walls and floor are placed on the SAME y=0 layer now, never
	# both in the same cell), so without this offset a `wall_height`-tall
	# mesh centered on a near-zero-thickness cell would be buried half
	# below the floor. Shift it up by half its height so its bottom face
	# sits on the floor's top surface instead.
	lib.set_item_mesh_transform(1, Transform3D(Basis(), Vector3(0, wall_height * 0.5, 0)))

	# GridMap does NOT generate collision from an item's visual mesh --
	# only from shapes explicitly registered here. Without this, nothing
	# in the GridMap is physically present in the physics world at all
	# (confirmed empirically: a straight-down raycast from above the
	# player hit nothing until this was added). GridActor's own movement
	# blocking doesn't need this -- it checks GridMap cell items directly,
	# not physics -- but anything that DOES need real collision (the
	# ground-shadow raycast in sprite_actor.gd/ground_shadow.gd) does.
	# Format: set_item_shapes takes a flat [shape, transform, shape,
	# transform, ...] array, one pair per collision shape on the item.
	var floor_shape := BoxShape3D.new()
	floor_shape.size = cell_size
	lib.set_item_shapes(0, [floor_shape, Transform3D.IDENTITY])

	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(cell_size.x, wall_height, cell_size.z)
	lib.set_item_shapes(1, [wall_shape, Transform3D(Basis(), Vector3(0, wall_height * 0.5, 0))])

	return lib
