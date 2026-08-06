# hotbar_slot.gd
# Godot version: 4.6
#
# A single slot in the hotbar. Displays an index label and (optionally)
# an icon/name for whatever is bound to it, and exposes `trigger()` for
# the container to call when its key (or a click) activates it.
#
# Deliberately holds a loose `bound_action: Callable` rather than a typed
# "Item" resource -- this framework doesn't know yet whether slots will
# hold consumables, spells, or tool-mode toggles, so the slot just knows
# how to display something and fire a callback. Swap `bound_action` for
# a real item/ability resource type once that system exists.

extends Button
class_name HotbarSlot

@export var slot_index := 0:
	set(value):
		slot_index = value
		_refresh_label()

## What this slot does when triggered. Left unset, the slot still
## displays and can be selected, it just has nothing to fire.
var bound_action: Callable
var bound_icon: Texture2D
var bound_name := ""

signal triggered(slot_index: int)


func _ready() -> void:
	custom_minimum_size = Vector2(48, 48)
	toggle_mode = false
	_refresh_label()
	pressed.connect(_on_pressed)


func bind(action: Callable, icon_tex: Texture2D = null, display_name: String = "") -> void:
	bound_action = action
	bound_icon = icon_tex
	bound_name = display_name
	icon = icon_tex
	tooltip_text = display_name
	_refresh_label()


func clear_binding() -> void:
	bound_action = Callable()
	bound_icon = null
	bound_name = ""
	tooltip_text = ""
	_refresh_label()


func trigger() -> void:
	triggered.emit(slot_index)
	if bound_action.is_valid():
		bound_action.call()


func _on_pressed() -> void:
	trigger()


func _refresh_label() -> void:
	# 0-indexed internally, displayed as the row 1..9,0 a keyboard has.
	var key_label := str((slot_index + 1) % 10)
	text = key_label if bound_name.is_empty() else "%s\n%s" % [key_label, bound_name]
