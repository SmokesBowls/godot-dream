# ground_shadow.gd
# Godot version: 4.6
#
# A simple blob shadow beneath an actor, positioned by raycasting
# straight down each frame to the nearest real collision surface --
# same technique as the donor demo's ShadowMath25D (which used
# move_and_collide against an invisible 3D body; this uses a direct
# physics raycast instead since we don't have a spare body to spend on
# it). Presentation only: this never feeds into movement, landing, or
# any other gameplay decision, and nothing else may read its position as
# authoritative.
#
# Ground floor cells didn't have real physics collision before this was
# built -- GridActor's own movement blocking checks GridMap cell items
# directly, never physics, so nothing needed it until now. Confirmed
# empirically (a straight-down raycast hit nothing) and fixed by adding
# collision shapes in demo_mesh_library.gd. Worth knowing if this stops
# finding ground later: check that the mesh_library items still have
# shapes registered, not just visuals.

extends Node3D
class_name GroundShadow

## Whose XZ position to track and whose own collision to exclude from
## the raycast (so the ray doesn't just hit the actor's own capsule).
@export var actor: CharacterBody3D

@export var shadow_size := Vector2(0.7, 0.5)
@export var shadow_color := Color(0.0, 0.0, 0.0, 0.35)
@export var ray_start_height := 3.0
@export var ray_length := 20.0
## Tiny lift above the found surface -- without this the shadow quad and
## the floor mesh are coplanar and z-fight (flicker between which one
## wins the depth test).
@export var surface_offset := 0.02

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = shadow_size
	_material = StandardMaterial3D.new()
	_material.albedo_color = shadow_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = _material

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = quad
	# QuadMesh is authored facing +Z by default; rotate it to lie flat,
	# facing up.
	_mesh_instance.rotation_degrees = Vector3(-90, 0, 0)
	_mesh_instance.visible = false
	add_child(_mesh_instance)


func _process(_delta: float) -> void:
	if actor == null:
		_mesh_instance.visible = false
		return

	var origin := actor.global_position + Vector3(0, ray_start_height, 0)
	var target := origin + Vector3(0, -ray_length, 0)

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [actor.get_rid()]
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		_mesh_instance.visible = false
		return

	_mesh_instance.visible = true
	global_position = (result.position as Vector3) + Vector3(0, surface_offset, 0)
