# ledge.gd
# Godot version: 4.6
#
# A walkable elevated footprint -- the minimal piece of "real
# verticality" this project has, added specifically to make the jump-test
# platform (tactical_demo_world.gd's _build_jump_test_platform()) actually
# reachable, not a general multi-story navmesh/height-map system (that
# stays a real future decision -- see the tactical_world README's
# verticality vision note). See grid_actor.gd's request_jump_step() /
# `current_ground_height` for how this gets consumed: GridActor stays
# flat-ground (Y=0) authoritative everywhere in the world EXCEPT the
# footprint declared here, entered or left only through a deliberate
# jump-key press -- never by walking off the edge with plain WASD
# movement (request_move() refuses to leave a ledge's footprint at all;
# see its own comment for why).
#
# Declarative, not physics-probed: `height` is stated data, not sensed by
# a raycast against the platform's own mesh/collision -- same "flag it,
# don't invent it" reasoning the rest of this project uses elsewhere.
# Whoever places a Ledge is responsible for matching `height` and
# `footprint_size`/position to the actual solid geometry it sits on top
# of -- tactical_demo_world.gd's jump-test platform builds both the
# collision box and this node from the SAME local variables in the SAME
# function specifically so they can't silently drift apart from each
# other.

extends Node3D
class_name Ledge

## GridActor scans nodes in this group to find nearby ledges -- see
## grid_actor.gd's _ledge_at_xz().
const LEDGE_GROUP := "ledge"

## World-space Y of this ledge's walkable top surface. Must match the
## real collision geometry's top face, or an actor that steps up here
## will end up floating above it or embedded in it.
@export var height := 0.7

## X/Z size of the walkable top, centered on this node's own X/Z
## position. Y is ignored for containment -- see contains_xz().
@export var footprint_size := Vector2(2.0, 2.0)


func _ready() -> void:
	add_to_group(LEDGE_GROUP)


## True if `world_xz` falls within this ledge's footprint, in world
## space (not local space -- this node's own transform is read fresh
## each call rather than cached, matching Interactable/GridActor's
## existing convention of never caching a world position that could
## move).
func contains_xz(world_xz: Vector2) -> bool:
	var half := footprint_size * 0.5
	var local := world_xz - Vector2(global_position.x, global_position.z)
	return absf(local.x) <= half.x and absf(local.y) <= half.y
