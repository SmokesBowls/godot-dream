# akashic.gd
# Persistent runtime composition for Dream World Boundary 1.
extends Node
class_name DreamWorldRuntime

const ROOM_A := preload("res://core/scenes/world/room_a.tscn")
const ROOM_B := preload("res://core/scenes/world/room_b.tscn")

@onready var player: GridActor = $Player
@onready var inventory: Inventory = $Player/Inventory
@onready var camera_rig: TacticalCameraRig = $TacticalCameraRig
@onready var camera_mode_controller: CameraModeController = $CameraModeController
@onready var transition_coordinator: TransitionCoordinator = $TransitionCoordinator
@onready var room_container: Node3D = $RoomContainer
@onready var inventory_hud: InventoryHud = $InventoryHud


func _ready() -> void:
	camera_rig.target = player
	camera_mode_controller.camera_rig = camera_rig
	camera_mode_controller.player = player

	var player_input := player.get_node("PlayerInput") as GridActorPlayerInput
	player_input.actor = player
	player_input.camera_rig = camera_rig

	var sprite_actor := player.get_node("VisualRoot/SpriteActor") as SpriteActor
	sprite_actor.actor = player
	sprite_actor.camera_rig = camera_rig

	var ground_shadow := player.get_node("VisualRoot/GroundShadow") as GroundShadow
	ground_shadow.actor = player

	inventory_hud.inventory = inventory

	transition_coordinator.configure(player, camera_rig, room_container)
	transition_coordinator.register_room(&"room_a", ROOM_A)
	transition_coordinator.register_room(&"room_b", ROOM_B)
	if not transition_coordinator.install_initial_room(ROOM_A, &"start_entrance"):
		push_error("DreamWorldRuntime failed to install initial room_a.")
