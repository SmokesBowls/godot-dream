# transition_request.gd
# Immutable semantic description of travel between two named room boundaries.
extends RefCounted
class_name TransitionRequest

# GDScript has no hard-private members. Consolidate semantic storage into one
# initialization-once property and make the native Dictionary read-only so
# neither direct property assignment nor mutation through a returned reference
# can change request identity after construction.
var _values: Dictionary:
	set(value):
		if not _values.is_empty():
			return
		_values = value.duplicate()
		_values.make_read_only()
	get:
		return _values

var source_room_id: StringName:
	get:
		return _values["source_room_id"]

var exit_id: StringName:
	get:
		return _values["exit_id"]

var destination_room_id: StringName:
	get:
		return _values["destination_room_id"]

var destination_entrance_id: StringName:
	get:
		return _values["destination_entrance_id"]


func _init(
	new_source_room_id: StringName,
	new_exit_id: StringName,
	new_destination_room_id: StringName,
	new_destination_entrance_id: StringName,
) -> void:
	_values = {
		"source_room_id": new_source_room_id,
		"exit_id": new_exit_id,
		"destination_room_id": new_destination_room_id,
		"destination_entrance_id": new_destination_entrance_id,
	}


func to_dictionary() -> Dictionary:
	return _values.duplicate()
