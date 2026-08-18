# world_room.gd
# Replaceable room-local world content and its semantic boundary inventory.
extends Node3D
class_name WorldRoom

@export var room_id: StringName


func entrances() -> Array[RoomEntrance]:
	var found: Array[RoomEntrance] = []
	_collect_type(self, RoomEntrance, found)
	return found


func exits() -> Array[RoomExit]:
	var found: Array[RoomExit] = []
	_collect_type(self, RoomExit, found)
	return found


func interaction_controllers() -> Array[InteractionController]:
	var found: Array[InteractionController] = []
	_collect_type(self, InteractionController, found)
	return found


func grid_maps() -> Array[GridMap]:
	var found: Array[GridMap] = []
	_collect_type(self, GridMap, found)
	return found


func world_rooms() -> Array[WorldRoom]:
	var found: Array[WorldRoom] = []
	_collect_world_rooms(self, found)
	return found


func _collect_world_rooms(node: Node, result: Array[WorldRoom]) -> void:
	if node is WorldRoom:
		result.append(node as WorldRoom)
	for child in node.get_children():
		_collect_world_rooms(child, result)


func find_entrances(semantic_id: StringName) -> Array[RoomEntrance]:
	var matches: Array[RoomEntrance] = []
	for entrance in entrances():
		if entrance.entrance_id == semantic_id:
			matches.append(entrance)
	return matches


func find_entrance(semantic_id: StringName) -> RoomEntrance:
	var matches := find_entrances(semantic_id)
	return matches[0] if matches.size() == 1 else null


func find_exits(semantic_id: StringName) -> Array[RoomExit]:
	var matches: Array[RoomExit] = []
	for room_exit in exits():
		if room_exit.exit_id == semantic_id:
			matches.append(room_exit)
	return matches


func find_exit(semantic_id: StringName) -> RoomExit:
	var matches := find_exits(semantic_id)
	return matches[0] if matches.size() == 1 else null


func relative_entrance_transform(entrance: RoomEntrance) -> Transform3D:
	var result := entrance.transform
	var ancestor := entrance.get_parent()
	while ancestor != null and ancestor != self:
		if ancestor is Node3D:
			result = (ancestor as Node3D).transform * result
		ancestor = ancestor.get_parent()
	return result


# Minimal future-facing seam only. Consequence persistence is deliberately
# deferred; this slice captures no room-owned values.
func capture_transition_state() -> Dictionary:
	return {}


# Minimal validation seam only. Applying remembered consequences is deferred.
func can_apply_transition_state(state: Dictionary) -> bool:
	return state.is_empty()


func _collect_type(node: Node, wanted_type: Variant, output: Array) -> void:
	for child in node.get_children():
		if is_instance_of(child, wanted_type):
			output.append(child)
		_collect_type(child, wanted_type, output)
