# loot_window.gd
# Godot version: 4.6
#
# Autoload singleton (see project.godot). Modal "choose what to take"
# window for a Chest -- see toggle_list_window.gd's header for the shared
# machinery this builds on, and Chest._on_open() (examples/chest.gd) for
# the caller. Everything defaults CHECKED (opt-OUT of taking an item, not
# opt-in) -- looting is free, so "take everything" is the sensible
# default; ShopWindow (buying costs currency) defaults the other way.

extends ToggleListWindow

var _on_taken: Callable


## `loot` is item_id -> amount, e.g. Chest.loot. `on_taken` is called
## once, after the window closes, with a Dictionary of exactly the
## item_id -> amount entries the player left checked (empty if they
## unchecked everything or pressed Esc) -- the caller decides what
## "taken" means for its own state (Chest removes taken entries from its
## own `loot` and grants them to an Inventory; see its _on_loot_taken()).
func open(loot: Dictionary, title: String, on_taken: Callable) -> void:
	if active or loot.is_empty():
		return
	_on_taken = on_taken
	var entries: Array[Dictionary] = []
	for item_id in loot.keys():
		entries.append({"id": item_id, "amount": loot[item_id], "checked": true})
	_open_session(entries, title)


func _pause_reason() -> StringName:
	return &"loot"


func _row_text(entry: Dictionary) -> String:
	return "%s x%d" % [String(entry["id"]).capitalize(), entry["amount"]]


func _on_confirmed(checked_entries: Array[Dictionary]) -> void:
	var taken := {}
	for entry in checked_entries:
		taken[entry["id"]] = entry["amount"]
	if _on_taken.is_valid():
		_on_taken.call(taken)
