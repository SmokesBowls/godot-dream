# harvestable_plant.gd
# Godot version: 4.6
#
# Example Interactable subclass -- a garden plant that can be harvested
# once, then needs `regrow_seconds` before it's harvestable again. Shows
# the intended usage pattern: set `interaction_type = HARVEST` on the
# node (or in the editor Inspector) and override only `_on_harvest()`.
#
# Not meant to be the final word on farming -- it's here to prove the
# Interactable contract is actually usable end-to-end, and to give the
# "cultivated garden with seasonal growth and harvestable plants" part
# of the brief a concrete starting point.

extends Interactable
class_name HarvestablePlant

@export var yield_item_id := "vegetable"
@export var yield_amount := 1
@export_range(1.0, 3600.0) var regrow_seconds := 60.0

var _is_ripe := true

@onready var _regrow_timer := Timer.new()


func _ready() -> void:
	interaction_type = InteractionType.HARVEST
	interaction_prompt = "Harvest"
	if display_name.is_empty():
		display_name = "Harvest Plant"
	super._ready()  # registers the INTERACTABLE_GROUP and builds the label -- must run after the two lines above so it picks up the values set here, not the class defaults
	add_child(_regrow_timer)
	_regrow_timer.one_shot = true
	_regrow_timer.timeout.connect(_on_regrown)


func _on_harvest(source: Node) -> void:
	if not _is_ripe:
		return

	_is_ripe = false
	_regrow_timer.start(regrow_seconds)

	# Placeholder hand-off point: a real inventory system would receive
	# (yield_item_id, yield_amount) here. Left as a print + comment
	# rather than a guessed-at inventory API, same spirit as the rest of
	# this repo's "flag it, don't invent it" convention.
	print("Harvested %d x %s from %s" % [yield_amount, yield_item_id, name])
	# TODO: replace with a real call once an inventory system exists,
	# e.g.: Inventory.add_item(source, yield_item_id, yield_amount)


func _on_regrown() -> void:
	_is_ripe = true
