# inventory_hud.gd
# Godot version: 4.6
#
# Small always-visible top-left readout of an Inventory's contents
# ("Satchel: Apple x1, Gold Coin x5", one line per item_id currently
# held). Built procedurally in _ready() -- same "throwaway placeholder,
# not final art" spirit as InteractionController._build_panel() and
# demo_mesh_library.gd -- rather than a .tscn, since there's nothing
# here yet worth hand-laying-out in the editor.
#
# Purely a presentation layer: reads Inventory.changed and rebuilds its
# label text from Inventory.items; never writes back to Inventory
# itself.

extends CanvasLayer
class_name InventoryHud

## A property SETTER, not a plain @export -- same ready-order fix this
## project has needed repeatedly (sprite_actor.gd's old `actor` setter,
## follower.gd's `leader` setter): whoever assigns this (the scene
## script) may do so before or after this node's own _ready() runs
## depending on tree order, so the connection has to happen at
## assignment time, not just once in _ready().
@export var inventory: Inventory:
	set(value):
		if inventory and inventory.changed.is_connected(_on_changed):
			inventory.changed.disconnect(_on_changed)
		inventory = value
		if inventory:
			inventory.changed.connect(_on_changed)
		_rebuild()

var _label: Label


func _ready() -> void:
	layer = 5

	# Anchored top-RIGHT, not top-left -- debug_grid_overlay.gd's (TEMPORARY,
	# see its own header) coordinate HUD already occupies the top-left
	# corner, and the two would otherwise render stacked on top of each
	# other. grow_horizontal BEGIN so the box grows further left as its
	# content gets wider, staying pinned to the right edge instead of
	# drifting past it.
	var box := PanelContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 0.0
	box.offset_right = -16
	box.offset_top = 16
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(box)

	_label = Label.new()
	box.add_child(_label)

	_rebuild()


func _on_changed(_item_id: String, _new_amount: int) -> void:
	_rebuild()


func _rebuild() -> void:
	if _label == null:
		return  # inventory assigned before _ready() built the label yet -- _ready() calls _rebuild() itself once it has
	if inventory == null or inventory.items.is_empty():
		_label.text = "Satchel: (empty)"
		return
	var lines := PackedStringArray()
	lines.append("Satchel:")
	for item_id in inventory.items.keys():
		lines.append(" %s x%d" % [String(item_id).capitalize(), inventory.items[item_id]])
	_label.text = "\n".join(lines)
