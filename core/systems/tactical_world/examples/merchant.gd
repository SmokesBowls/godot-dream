# merchant.gd
# Godot version: 4.6
#
# Example Interactable subclass proving the exact case interaction_flags
# was built for: one NPC that both TALKS and has an OPENable satchel, as
# ONE Interactable node instead of two. See interactable.gd's doc
# comment on interaction_flags for the "two nodes sharing one world
# position" problem this replaces.
#
# Talk is the PRIMARY action (a plain F press) since that's the more
# common thing to want from an NPC; opening the satchel is the
# secondary action, reached through InteractionController's numbered
# secondary-action list once an interaction session with this NPC
# begins -- see interaction_controller.gd's file header for how a
# multi-type target's confirm panel differs from a single-type one.
#
# _on_talk() is still just one line via GameFeedback -- no real dialogue
# tree exists yet, and guessing at one now risks building the wrong
# shape. _on_open() DOES now open a real purchase UI (ShopWindow, see
# core/ui/toggle_list_window/shop_window.gd) -- `wares` changed from a
# flavor-only Array[String] to a real item_id -> price Dictionary so
# there's something to actually buy, spending the same "gold_coin"
# currency Chest already grants by default (see ShopWindow.CURRENCY_ITEM_ID's
# own doc comment for why that particular id, not a separate currency
# system). Still no sell-back and no stock depletion -- a real economy
# design (haggling, restocking, per-merchant inventory limits) is a
# future decision, not guessed at here.

extends Interactable
class_name Merchant

## item_id -> price, in gold_coin (see ShopWindow.CURRENCY_ITEM_ID).
@export var wares: Dictionary = {
	"health_potion": 8,
	"rope": 3,
	"torch": 2,
}


func _ready() -> void:
	interaction_flags = (1 << InteractionType.TALK) | (1 << InteractionType.OPEN)
	primary_interaction_type_override = InteractionType.TALK
	interaction_prompts = {
		InteractionType.TALK: "Talk",
		InteractionType.OPEN: "Open Satchel",
	}
	if display_name.is_empty():
		display_name = "Merchant"
	super._ready()  # registers INTERACTABLE_GROUP, builds the label/collision body -- must run after the setup above so it picks up these values, not the class defaults


func _on_talk(_source: Node) -> void:
	var line := "%s: \"Welcome, traveler. Care to see my wares?\"" % display_name
	GameFeedback.show_message(line)
	print(line)


func _on_open(source: Node) -> void:
	var inventory := source.get_node_or_null("Inventory") as Inventory
	if inventory == null:
		GameFeedback.show_message("%s: \"You've nowhere to carry that.\"" % display_name)
		return
	ShopWindow.open(wares, display_name, inventory)
