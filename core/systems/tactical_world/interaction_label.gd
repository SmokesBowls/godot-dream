# interaction_label.gd
# Godot version: 4.6
#
# Reusable world-space label for an Interactable: floats above the
# object, always faces the camera (billboard), and supports exactly
# three presentation states -- nothing in between, on purpose, so
# InteractionController never has to reason about partial states:
#
#   hidden        -- set_hidden()
#   name only     -- show_name("Chest")
#   name + action -- show_action("Chest", "Open", "F")
#
# Owns no distance/range/line-of-sight logic itself -- it just renders
# whatever state it's told. InteractionController decides which state
# applies each frame.
#
# Two stacked Label3Ds (name line + action line) rather than one label
# with two lines of text: they need different colors (name white,
# action highlighted), and Label3D has no per-line/inline color
# markup -- modulate is whole-label.

extends Node3D
class_name InteractionLabel

## Local-space height the NAME line floats above the owning object's
## origin. The action line sits slightly below it. Tune per-object if
## needed (a tall object wants a higher label).
@export var height_offset := 1.2

@export var name_color := Color(1.0, 1.0, 1.0)
@export var action_color := Color(1.0, 0.85, 0.4)

var _name_label: Label3D
var _action_label: Label3D


func _ready() -> void:
	_name_label = _make_label(name_color, 32, height_offset)
	_action_label = _make_label(action_color, 28, height_offset - 0.22)
	set_hidden()


func _make_label(color: Color, size: int, y: float) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# fixed_size=true pins Label3D to a constant SCREEN size regardless
	# of camera distance -- tried it first, but at font_size=48 it filled
	# nearly the whole frame even at normal gameplay camera distance
	# (~14 units), and stayed exactly that huge close-up too, confirming
	# it wasn't scaling with distance at all. Left off: plain 3D text
	# that shrinks/grows with perspective like any other object in the
	# scene, sized in *world* units via pixel_size * font_size below.
	label.pixel_size = 0.008
	label.font_size = size
	label.outline_size = 6
	label.modulate = color
	# Nameplates should read clearly even when the player capsule (or
	# another prop) is standing right in front of them at interaction
	# range -- always draw on top rather than being depth-occluded.
	label.no_depth_test = true
	label.position = Vector3(0, y, 0)
	add_child(label)
	return label


func set_hidden() -> void:
	_name_label.visible = false
	_action_label.visible = false


func show_name(object_name: String) -> void:
	_name_label.text = object_name
	_name_label.visible = true
	_action_label.visible = false


func show_action(object_name: String, action_text: String, key_text: String) -> void:
	_name_label.text = object_name
	_name_label.visible = true
	_action_label.text = "[%s] %s" % [key_text, action_text]
	_action_label.visible = true
