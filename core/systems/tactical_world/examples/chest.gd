# chest.gd
# Godot version: 4.6
#
# Concrete Interactable subclass for a lootable container (currently
# just the demo Chest in tactical_demo_world.tscn). Opening it shows a
# real per-item LootWindow (core/ui/toggle_list_window/loot_window.gd) --
# not an automatic grant-everything -- so the player can choose to take
# some items and leave others; anything left unchecked stays in `loot`
# for a later visit rather than being drained in one shot.
#
# This REPLACES an earlier version of this file (see the tactical_world
# README's decision log) that granted one hardcoded item/amount pair
# automatically and used `one_shot` to block re-opening -- a real,
# reported limitation once a chest needed to hold more than one kind of
# item at once. `one_shot` is no longer set at all here; whether this
# chest can still be opened is now determined by whether `loot` is empty,
# checked directly.

extends Interactable
class_name Chest

## item_id -> amount. Player picks per-item what to take; unchecked items
## remain here untouched. A plain Dictionary, same "nothing needs a typed
## Item resource yet" reasoning as inventory.gd's own `items`.
@export var loot: Dictionary = {"gold_coin": 5}

@onready var _mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")


func _ready() -> void:
	interaction_flags = 1 << InteractionType.OPEN
	interaction_prompt = "Open"
	if display_name.is_empty():
		display_name = "Chest"
	super._ready()  # registers INTERACTABLE_GROUP, builds the label/collision body -- must run after the setup above so it picks up these values, not the class defaults


func _on_open(source: Node) -> void:
	if loot.is_empty():
		GameFeedback.show_message("The %s is empty." % display_name)
		return
	LootWindow.open(loot, display_name, _on_loot_taken.bind(source))


## Called once the LootWindow session closes, with exactly the item_id ->
## amount entries the player left checked (possibly empty, if they
## unchecked everything or pressed Esc -- see loot_window.gd's own doc
## comment). `source` arrives via Callable.bind() on the call in
## _on_open() above, appended after `taken` (bind()'s documented
## argument order).
func _on_loot_taken(taken: Dictionary, source: Node) -> void:
	var inventory := source.get_node_or_null("Inventory") as Inventory
	for item_id in taken.keys():
		if inventory:
			inventory.add_item(item_id, taken[item_id])
		loot.erase(item_id)

	if taken.is_empty():
		GameFeedback.show_message("You leave the %s untouched." % display_name)
	else:
		var parts: Array[String] = []
		for item_id in taken.keys():
			parts.append("%d x %s" % [taken[item_id], String(item_id).capitalize()])
		GameFeedback.show_message("Took " + ", ".join(parts))

	if loot.is_empty():
		interaction_prompt = "Empty"
		if _mesh and _mesh.mesh:
			var opened_mat := StandardMaterial3D.new()
			opened_mat.albedo_color = Color(0.25, 0.18, 0.1)
			_mesh.material_override = opened_mat
