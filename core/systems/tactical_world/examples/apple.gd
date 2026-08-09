# apple.gd
# Godot version: 4.6
#
# Concrete Interactable subclass for a one-off pickup prop (currently
# just the demo Apple in tactical_demo_world.tscn). It used to be wired
# to the BARE Interactable script directly, with the HARVEST flag set
# from the .tscn -- which meant `interact()` dispatched to the base
# class's empty default `_on_harvest()`, so pressing F closed the
# confirm panel and did, genuinely, nothing else. This gives it a real
# effect: hand one to whoever picked it up (if they have an Inventory --
# see core/systems/inventory/inventory.gd), say so on screen, and remove
# itself from the world.
#
# Reuses the HARVEST interaction type (not a new PICK_UP type) the same
# way the .tscn already did -- "pick up a small prop" and "harvest a
# resource" are different flavors of the same underlying verb (take
# something from the world into the inventory), and interaction_prompt
# already lets this instance show "Pick Up" instead of "Harvest" without
# needing a new InteractionType member.
#
# A pickup, not a regrowing resource like harvestable_plant.gd -- once
# taken it's gone, not "not ripe until a timer elapses."

extends Interactable
class_name ApplePickup

@export var item_id := "apple"
@export var amount := 1


func _ready() -> void:
	interaction_flags = 1 << InteractionType.HARVEST
	interaction_prompt = "Pick Up"
	if display_name.is_empty():
		display_name = "Apple"
	super._ready()  # registers INTERACTABLE_GROUP, builds the label/collision body -- must run after the setup above so it picks up these values, not the class defaults


func _on_harvest(source: Node) -> void:
	var inventory := source.get_node_or_null("Inventory") as Inventory
	if inventory:
		inventory.add_item(item_id, amount)
	GameFeedback.show_message("Picked up %d x %s" % [amount, display_name])
	queue_free()
