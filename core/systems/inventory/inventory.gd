# inventory.gd
# Godot version: 4.6
#
# Minimal item-count inventory: a Dictionary of item_id -> amount, plus
# one signal so a HUD (or anything else) can react without polling.
# Deliberately NOT a typed Item resource system (icons, weight, stacking
# rules, equip slots, ...) -- nothing in this project needs any of that
# yet, and guessing at that shape now risks building the wrong one
# before a real design exists (same "flag it, don't invent it" spirit
# as harvestable_plant.gd's yield-handoff comment). This exists purely
# to give the interaction handlers that used to be bare "print() and a
# comment" placeholders (harvestable_plant.gd's _on_harvest, the old
# Chest/Apple no-ops that used the base Interactable script directly) an
# actual place to put what they produce.
#
# Attach as a child of whatever Node should own items (currently only
# the player's GridActor has one -- see tactical_demo_world.tscn's
# "Inventory" child under "Player"). Interaction handlers that receive a
# `source` look for `source.get_node_or_null("Inventory")` and no-op if
# it isn't there, so this is opt-in per-actor, not a hard dependency any
# Interactable subclass needs to assume exists.

extends Node
class_name Inventory

## item_id (String) -> amount (int). Read directly for a snapshot; use
## add_item()/remove_item() to change it so `changed` fires correctly.
var items: Dictionary = {}

## Fires after every successful add/remove, with the single item_id that
## changed and its NEW total (0 if it was just fully removed). A HUD
## listens here and rebuilds its whole display each time rather than
## trying to diff -- cheap enough at this scale, and simpler than
## reasoning about partial UI updates.
signal changed(item_id: String, new_amount: int)


func add_item(item_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	items[item_id] = items.get(item_id, 0) + amount
	changed.emit(item_id, items[item_id])


## Returns true if `amount` was actually available and removed; false
## (a no-op, nothing changed) if there wasn't enough -- callers that need
## to know whether a removal "worked" (a shop purchase, a crafting cost)
## can check the return value instead of comparing counts before/after.
func remove_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return false
	var have: int = items.get(item_id, 0)
	if have < amount:
		return false
	var remaining := have - amount
	if remaining <= 0:
		items.erase(item_id)
		changed.emit(item_id, 0)
	else:
		items[item_id] = remaining
		changed.emit(item_id, remaining)
	return true


func has_item(item_id: String, amount: int = 1) -> bool:
	return items.get(item_id, 0) >= amount


func count(item_id: String) -> int:
	return items.get(item_id, 0)
