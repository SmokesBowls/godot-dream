# interactable.gd
# Godot version: 4.6
#
# Base class for anything in the world the player can act on: trees,
# rocks, chests, cottage doors, garden plots, ruined walls. This is
# deliberately dumb -- it does not know how to open a chest or grow a
# plant. It gives every interactable object the same signal contract and
# dispatch shape, so a generic "interact" system (player-facing prompt,
# reticle, whatever) can talk to any of them without knowing what they
# are. Concrete behavior belongs in a subclass that overrides
# `_on_interact()` (see examples/harvestable_plant.gd).
#
# This also gives you the seam the world-model brief calls for: because
# every interactable is a real Node in the tree with real @export state
# (not a sprite-swap or a hardcoded switch statement), that state is
# something a persistence/event-store layer can snapshot and restore --
# "authoritative data, not temporary game state" -- without this class
# needing to know persistence exists.

extends Node3D
class_name Interactable

## Every Interactable adds itself here in _ready() so InteractionController
## can find them all with get_tree().get_nodes_in_group() instead of the
## controller needing a hand-maintained registry.
const INTERACTABLE_GROUP := "interactable"

## Solid Interactables (blocks_movement true, the default) add
## themselves here too. GridActor checks this group in ADDITION to its
## GridMap wall check, so a chest/plant/etc. occupies real, non-passable
## space without needing to be baked into the GridMap itself.
const BLOCKING_GROUP := "blocks_movement"

## What kind of interaction this object supports. Kept as a single enum
## rather than flags -- an object that needs to both "open" and "talk"
## (an NPC with a container, say) is two Interactable nodes, not one
## multi-typed one. That keeps _on_interact() a plain match, not a
## bitmask of half-applicable behavior.
enum InteractionType {
	EXAMINE,       ## Read-only: a sign, a corpse, a journal page.
	TALK,          ## An NPC with dialogue.
	HARVEST,       ## Garden plants, foraging, resource nodes.
	OPEN,          ## Chests, doors, containers.
	CLIMB,         ## Ruined walls, ledges -- traversal, not inventory.
	PASS_THROUGH,  ## Broken gates/walls that let you walk through them.
	TOGGLE,        ## Levers, switches -- anything with an on/off state.
}

@export var interaction_type: InteractionType = InteractionType.EXAMINE

## What InteractionController's label shows on the object's NAME line,
## e.g. "Chest", "Harvest Plant". Falls back to the node's own `name`
## if left blank, so simple objects don't need to set this explicitly.
@export var display_name := ""

## Short verb shown on the label's action line, e.g. "Open", "Harvest",
## "Talk" -- NOT a full sentence ("Open Chest"); the object name is
## already on its own line above it. Not used by this class directly --
## kept as data so the text lives with the object, same as display_name.
@export var interaction_prompt := "Interact"

## If true, this object never gets a label at all, at any range or
## distance -- a placeholder for a future "hidden until searched"
## mechanic. Nothing currently sets this or implements the search side;
## it's here so InteractionController has the hook ready rather than
## needing a signature change later.
@export var is_hidden := false

## Local-space height the label floats above this object's origin.
## Tune per-instance for tall/short objects (a chest wants less than a
## standing NPC).
@export var label_height_offset := 1.2

## If true (the default), this object occupies real, non-passable space
## -- GridActor won't let the player step into its cell, same as a wall.
## Defaults on because most world objects (chests, plants, rocks,
## furniture) are physically solid; flip off for things that shouldn't
## block (a sign, a floor switch, a pressure plate).
@export var blocks_movement := true

## Only read when blocks_movement is true. Fixes "the Apple Problem":
## movement steps in 0.5m increments (step_distance) but this flag used
## to make ANY blocking object occupy the entire 1m GridMap cell it sits
## in -- so a small prop with a tiny visual footprint (an apple, a
## dropped coin) silently vetoed all four 0.5m sub-cell steps around it,
## including ones that visually have nothing in front of them.
##
## true (the default): unchanged behavior -- the object blocks its whole
## cell, same as before this export existed. Correct for anything
## actually as big as a cell: chests, furniture, plants, rocks, walls-
## as-props.
##
## false: the object blocks only steps that land within occupancy_radius
## of its actual position (see below), not the whole cell. Two steps in
## the SAME cell can then get different answers depending on which
## quarter of the cell they land in -- this is deliberate; it's what
## proves the check is doing real geometry instead of a coarser
## approximation with a different threshold.
@export var occupies_full_cell := true

## Only read when blocks_movement is true AND occupies_full_cell is
## false. Radius, in meters, of this object's actual physical footprint
## around its own global_position -- a step whose landing point falls
## within this distance is blocked; anything farther (even in the same
## GridMap cell) is not. 0.15 is sized for a small handheld prop (an
## apple, a mushroom); widen it for something chair-sized, but if it
## should really occupy most/all of a cell just leave occupies_full_cell
## true instead -- this radius isn't meant to be pushed out to ~0.5m as
## a substitute for that flag.
##
## Deliberately NOT cell-culled the way the occupies_full_cell branch is
## in grid_actor.gd's _is_object_obstructed_step() -- an object placed
## near a cell boundary can have this radius genuinely spill into the
## neighbor cell, and a cell-index pre-check would silently miss that.
## The distance check itself (squared, no sqrt) is cheap enough per
## object that this isn't a real performance concern at any prop count
## a hand-placed tactical scene actually reaches; if a future scene ever
## needs hundreds of simultaneous small props, revisit with a spatial
## hash then rather than pre-guessing the need now.
@export var occupancy_radius := 0.15

## If true, the object can only be interacted with once (a one-time
## loot chest, a single-harvest bush that doesn't regrow). Enforced here
## so every subclass gets it for free instead of reimplementing a
## "_used" bool each time.
@export var one_shot := false

## Range check helper for callers that want it; this class does not
## enforce range itself -- the calling interaction system decides what
## "in range" means (a raycast, an Area3D, a grid-adjacency check).
@export var interact_range := 2.5

var consumed := false

## Created in _ready(). InteractionController drives this directly
## (label.show_name(...) / label.show_action(...) / label.set_hidden())
## rather than this class owning any range/visibility logic itself --
## see interaction_label.gd and interaction_controller.gd.
var label: InteractionLabel

## Emitted every time `interact()` runs, regardless of type -- generic
## listeners (UI feedback, sound, quest hooks, an event-store adapter)
## connect here instead of to every subclass's type-specific signal.
signal interacted(source: Node)

## Emitted once when `one_shot` interactables are consumed, so listeners
## that only care about that transition don't have to check `consumed`
## themselves after every `interacted` signal.
signal consumed_changed(is_consumed: bool)


## Subclasses that override _ready() (HarvestablePlant does, to set up
## its regrow timer) MUST call super._ready() first, or they won't be
## found by InteractionController and won't get a label.
func _ready() -> void:
	add_to_group(INTERACTABLE_GROUP)
	if blocks_movement:
		add_to_group(BLOCKING_GROUP)
	if display_name.is_empty():
		display_name = name
	label = InteractionLabel.new()
	label.height_offset = label_height_offset
	add_child(label)


## Entry point interaction systems should call. Handles the one_shot
## guard, routes to the virtual handler matching `interaction_type`,
## then emits the generic signal. Subclasses override the specific
## `_on_*` handler for the type they declared -- a chest (OPEN) overrides
## `_on_open()`, a garden plant (HARVEST) overrides `_on_harvest()` --
## not `interact()` itself.
func interact(source: Node) -> void:
	if one_shot and consumed:
		return

	match interaction_type:
		InteractionType.EXAMINE:
			_on_examine(source)
		InteractionType.TALK:
			_on_talk(source)
		InteractionType.HARVEST:
			_on_harvest(source)
		InteractionType.OPEN:
			_on_open(source)
		InteractionType.CLIMB:
			_on_climb(source)
		InteractionType.PASS_THROUGH:
			_on_pass_through(source)
		InteractionType.TOGGLE:
			_on_toggle(source)

	interacted.emit(source)

	if one_shot:
		consumed = true
		consumed_changed.emit(true)


# ---------------------------------------------------------------------
# Override points -- one per InteractionType. Base implementations are
# empty; this class defines the contract, not the behavior. A subclass
# only needs to override the one matching its own `interaction_type`.
# ---------------------------------------------------------------------

func _on_examine(_source: Node) -> void:
	pass

func _on_talk(_source: Node) -> void:
	pass

func _on_harvest(_source: Node) -> void:
	pass

func _on_open(_source: Node) -> void:
	pass

func _on_climb(_source: Node) -> void:
	pass

func _on_pass_through(_source: Node) -> void:
	pass

func _on_toggle(_source: Node) -> void:
	pass
