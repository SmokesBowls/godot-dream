# shop_window.gd
# Godot version: 4.6
#
# Autoload singleton (see project.godot). Modal "choose what to buy"
# window for a Merchant -- see toggle_list_window.gd's header for the
# shared machinery this builds on, and Merchant._on_open()
# (examples/merchant.gd) for the caller. Everything defaults UNCHECKED
# (opt-IN to buying an item, not opt-out) -- the opposite default from
# LootWindow, deliberately: buying costs currency, so "buy nothing until
# you choose to" is the sensible default here.
#
# CURRENCY_ITEM_ID is a real, disclosed decision, not an invented
# economy: it's the same "gold_coin" item id Chest already grants by
# default (examples/chest.gd), so a chest's loot is actually spendable
# here without a separate currency-conversion step existing anywhere.
# There is still no sell-back, no stock depletion, and no haggling --
# just spend currency, receive item, one unit at a time per checked row.

extends ToggleListWindow

const CURRENCY_ITEM_ID := "gold_coin"

var _inventory: Inventory


## `wares` is item_id -> price (in CURRENCY_ITEM_ID). `inventory` is
## whoever's buying -- deducted from and added to directly by
## _on_confirmed() below, so this window needs a real Inventory
## reference, unlike LootWindow which just hands its result back to the
## caller. No-ops if `inventory` is null (a source with no Inventory
## component -- see inventory.gd's header on why that's possible) rather
## than opening a shop no purchase could ever complete in.
func open(wares: Dictionary, shop_name: String, inventory: Inventory) -> void:
	if active or inventory == null or wares.is_empty():
		return
	_inventory = inventory
	var entries: Array[Dictionary] = []
	for item_id in wares.keys():
		entries.append({"id": item_id, "price": wares[item_id], "checked": false})
	_open_session(entries, shop_name)


func _pause_reason() -> StringName:
	return &"shop"


func _row_text(entry: Dictionary) -> String:
	return "%s -- %d gold" % [String(entry["id"]).capitalize(), entry["price"]]


## Charges each checked row's price independently, in list order, as it
## goes -- NOT a single up-front "can you afford everything checked"
## pass. A row whose price can't be covered at the moment it's reached is
## silently skipped (not bought, gold not touched) rather than the whole
## purchase failing; the feedback message below reports both what was
## actually bought and what got skipped for insufficient funds, so
## nothing is silent to the PLAYER even though a partial purchase is a
## real, possible outcome.
func _on_confirmed(checked_entries: Array[Dictionary]) -> void:
	var inventory := _inventory
	_inventory = null
	if inventory == null:
		return

	var bought := {}
	var skipped: Array[String] = []
	for entry in checked_entries:
		var item_id: String = entry["id"]
		var price: int = entry["price"]
		if inventory.remove_item(CURRENCY_ITEM_ID, price):
			inventory.add_item(item_id, 1)
			bought[item_id] = bought.get(item_id, 0) + 1
		else:
			skipped.append(item_id)

	var parts := PackedStringArray()
	if not bought.is_empty():
		var items: Array[String] = []
		for item_id in bought:
			items.append("%s x%d" % [String(item_id).capitalize(), bought[item_id]])
		parts.append("Bought " + ", ".join(items))
	if not skipped.is_empty():
		var names: Array[String] = []
		for item_id in skipped:
			names.append(String(item_id).capitalize())
		parts.append("Not enough gold for " + ", ".join(names))
	if parts.is_empty():
		parts.append("No purchase made.")
	GameFeedback.show_message(" | ".join(parts))
