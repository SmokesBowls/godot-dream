# hotbar_container.gd
# Godot version: 4.6
#
# A row of 10 HotbarSlot children (keys 1-9 then 0, matching a real
# keyboard's top row) inside a draggable panel. Not anchored to a
# screen corner -- the player can grab it and move it, and its position
# persists for the session (see `_drag_position` / reset_position()).
#
# Meant to be used with hotbar_container.tscn, which lays out a
# PanelContainer > drag handle + HBoxContainer of 10 HotbarSlot nodes.
# This script only needs *a* PanelContainer-or-Control root with 10
# HotbarSlot descendants; it finds them by class at _ready() rather than
# by hardcoded node paths, so the scene layout can change without this
# script needing to change too.

extends PanelContainer
class_name HotbarContainer

const SLOT_COUNT := 10

## Physical keys, in on-screen left-to-right slot order: 1,2,3,4,5,6,7,8,9,0.
const SLOT_KEYCODES: Array[Key] = [
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
]

## If assigned in the editor, dragging is restricted to this child
## (e.g. a thin title bar) instead of the whole panel. Left unset, the
## whole panel is draggable, which is the simplest "just grab it" feel.
@export var drag_handle: Control

signal slot_activated(slot_index: int)

var slots: Array[HotbarSlot] = []

var _dragging := false
var _drag_grab_offset := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_collect_slots()
	var handle := drag_handle if drag_handle else self
	handle.gui_input.connect(_on_drag_input)


func _collect_slots() -> void:
	slots.clear()
	_find_slots_recursive(self)
	slots.sort_custom(func(a, b): return a.slot_index < b.slot_index)
	if slots.size() != SLOT_COUNT:
		push_warning("HotbarContainer expected %d HotbarSlot children, found %d." % [SLOT_COUNT, slots.size()])


func _find_slots_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is HotbarSlot:
			slots.append(child)
		else:
			_find_slots_recursive(child)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var idx := SLOT_KEYCODES.find(event.keycode)
	if idx == -1:
		return

	activate_slot(idx)


func activate_slot(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	slots[index].trigger()
	slot_activated.emit(index)


func reset_position(anchor_position: Vector2) -> void:
	position = anchor_position


# ---------------------------------------------------------------------
# Dragging. Standard Godot pattern: on left-press, remember the offset
# between the mouse and the panel's top-left corner; on motion while
# dragging, keep that offset constant instead of snapping the panel's
# corner to the cursor.
# ---------------------------------------------------------------------

func _on_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_grab_offset = event.global_position - global_position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		global_position = event.global_position - _drag_grab_offset
		_clamp_to_viewport()


func _clamp_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	global_position.x = clampf(global_position.x, 0.0, maxf(0.0, viewport_size.x - size.x))
	global_position.y = clampf(global_position.y, 0.0, maxf(0.0, viewport_size.y - size.y))
