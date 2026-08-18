# room_exit.gd
# Room-local request source. Transition authority remains elsewhere.
extends Area3D
class_name RoomExit

@export var exit_id: StringName
@export var destination_room_id: StringName
@export var destination_entrance_id: StringName

var coordinator: TransitionCoordinator


func _ready() -> void:
	# Physics overlap signals may lead to removal of this Area3D's whole
	# room. Defer the callback so teardown cannot occur during physics
	# signal dispatch.
	body_entered.connect(_on_body_entered, CONNECT_DEFERRED)


func bind_transition_coordinator(value: TransitionCoordinator) -> void:
	coordinator = value


func build_request() -> TransitionRequest:
	var room := _owning_room()
	if room == null:
		return null
	return TransitionRequest.new(
		room.room_id,
		exit_id,
		destination_room_id,
		destination_entrance_id,
	)


func matches_request(request: TransitionRequest) -> bool:
	return request != null \
		and request.exit_id == exit_id \
		and request.destination_room_id == destination_room_id \
		and request.destination_entrance_id == destination_entrance_id


func request_transition(source: Node) -> bool:
	if coordinator == null or source != coordinator.player:
		return false
	var request := build_request()
	return request != null and coordinator.request_transition(request)


func _on_body_entered(body: Node3D) -> void:
	if coordinator != null and body == coordinator.player:
		request_transition(body)


func _owning_room() -> WorldRoom:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is WorldRoom:
			return ancestor as WorldRoom
		ancestor = ancestor.get_parent()
	return null
