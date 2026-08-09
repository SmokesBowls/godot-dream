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
## themselves here too. Kept for anything that wants to enumerate solid
## objects without a physics query (minimap, AI awareness, ...) -- it is
## NOT what GridActor itself reads for movement blocking anymore (that's
## a real physics query against each object's own generated collision
## body now; see grid_actor.gd's file header and
## _build_collision_body() below).
const BLOCKING_GROUP := "blocks_movement"

## What kinds of interaction this object supports.
##
## A BITMASK now, not a single scalar enum -- see interaction_flags
## below. Previously this was a single InteractionType, on the
## reasoning that an object needing two behaviors at once (an NPC with
## both dialogue AND a lootable satchel) should just be two Interactable
## nodes instead of one multi-typed one. In practice that forced every
## "one entity, several verbs" case into two nodes sharing one world
## position -- two labels computing the same distance/line-of-sight math
## independently, two entries in every "what's here" query, and two
## separate _ready()/interact() lifecycles for what is conceptually one
## thing. A real dispatch surface should let one node advertise several
## interaction types and be told, per call, which one just fired -- see
## interact()'s `type` parameter and primary_interaction_type() below.
enum InteractionType {
	EXAMINE,       ## Read-only: a sign, a corpse, a journal page.
	TALK,          ## An NPC with dialogue.
	HARVEST,       ## Garden plants, foraging, resource nodes.
	OPEN,          ## Chests, doors, containers.
	CLIMB,         ## Ruined walls, ledges -- traversal, not inventory.
	PASS_THROUGH,  ## Broken gates/walls that let you walk through them.
	TOGGLE,        ## Levers, switches -- anything with an on/off state.
}

## Which of the InteractionType values above are active on this
## instance, as a real Godot bitmask -- @export_flags renders it as
## inspector checkboxes (one per name below, in InteractionType order),
## so a designer ticks "Talk" and "Open" on one Merchant node instead of
## building two nodes. Defaults to EXAMINE alone (bit 0 = value 1),
## matching the old enum default and every existing single-type object
## (Chest, Plant, Apple) unchanged -- a node with exactly one flag set
## behaves identically to before, no migration needed beyond how the
## flag happens to be written (see primary_interaction_type() below for
## why single-flag objects never need to think about multi-type
## dispatch at all).
@export_flags("Examine", "Talk", "Harvest", "Open", "Climb", "Pass Through", "Toggle") var interaction_flags: int = 1

## What InteractionController's label shows on the object's NAME line,
## e.g. "Chest", "Harvest Plant". Falls back to the node's own `name`
## if left blank, so simple objects don't need to set this explicitly.
@export var display_name := ""

## Short verb shown on the label's action line, e.g. "Open", "Harvest",
## "Talk" -- NOT a full sentence ("Open Chest"); the object name is
## already on its own line above it. Not used by this class directly --
## kept as data so the text lives with the object, same as display_name.
##
## This is the verb for a SINGLE-type object (the common case -- Chest,
## Plant, Apple all just set this one string, unchanged from before
## interaction_flags existed). An object with MORE than one active
## interaction_flags bit needs a verb PER type instead -- see
## interaction_prompts below -- so this field is only read when exactly
## one flag is set; see prompt_for().
@export var interaction_prompt := "Interact"

## Per-type verb overrides, only consulted when this object has MORE
## THAN ONE active interaction_flags bit (a single-type object always
## uses interaction_prompt above instead, regardless of what's in here).
## Keys are InteractionType values (int), values are the verb string --
## e.g. {InteractionType.TALK: "Talk", InteractionType.OPEN: "Open Satchel"}
## on a Merchant with both flags set. A type that's active but missing
## from this dictionary falls back to a generic default (see
## _DEFAULT_PROMPTS / prompt_for()) rather than failing -- a designer can
## tick a new flag on in the Inspector and get a reasonable label
## immediately, then refine the wording later.
@export var interaction_prompts: Dictionary = {}

## Only meaningful when more than one interaction_flags bit is active.
## Which type `interact()`/InteractionController treat as "the" action
## for a plain, unqualified press (F) -- see primary_interaction_type()
## below. Ignored entirely for a single-type object (there's only one
## possible answer, so this is never consulted); if left at its default
## (EXAMINE) on a multi-type object that doesn't actually have EXAMINE
## active, primary_interaction_type() falls back to the lowest-value
## active flag rather than an invalid choice.
@export var primary_interaction_type_override: InteractionType = InteractionType.EXAMINE

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

## If true (the default), this object occupies real, non-passable space.
## Defaults on because most world objects (chests, plants, rocks,
## furniture) are physically solid; flip off for things that shouldn't
## block (a sign, a floor switch, a pressure plate).
##
## OBSTRUCTION IS REAL PHYSICS NOW, NOT GRID MATH: when true, _ready()
## builds a real StaticBody3D + CollisionShape3D child (see
## _build_collision_body() below) on GridActor.OBJECT_COLLISION_LAYER_BIT.
## GridActor no longer scans a "blocks_movement" group and compares
## GridMap cell indices by hand -- it just runs a native
## PhysicsDirectSpaceState3D.intersect_shape() query at its destination,
## and this object's real collider is what it can (or can't) find there.
## BLOCKING_GROUP is still added to for anything else that wants to
## enumerate solid objects without a physics query (minimap, AI
## awareness, ...), but it is no longer what GridActor itself reads.
##
## Not reactive (a plain @export, not a setter) on purpose -- like
## interaction_type/display_name, this is read once at _ready() to
## build the collision body, not something toggled live at runtime in
## the current framework. A future "unlock the door" system that wants
## to flip this after the fact would need to also rebuild the collision
## body itself (see _build_collision_body()), the same extra step it
## would have needed with the old group-membership approach too.
@export var blocks_movement := true

## Only read when blocks_movement is true. Fixes "the Apple Problem":
## a small prop with a tiny visual footprint (an apple, a dropped coin)
## used to silently occupy its ENTIRE GridMap cell for movement-blocking
## purposes, vetoing sub-cell steps around it that visually have nothing
## in front of them.
##
## true (the default): the object's collider is a box sized to
## `full_cell_size` (below) -- correct for anything actually as big as a
## cell: chests, furniture, plants, rocks, walls-as-props.
##
## false: the object's collider is a cylinder of radius `occupancy_radius`
## (below) instead -- a real, much smaller physical footprint, so a step
## landing anywhere outside that radius (even within the same GridMap
## cell) is correctly left open. This used to be hand-rolled as a
## squared-distance check inside GridActor's collision loop, with a
## separate "corner safety probe" exemption carved out specifically
## because the grid-cell pre-check that loop did couldn't tell a small
## footprint from a full one; a real shape query needs neither -- the
## collider IS the footprint, so there's nothing left to special-case.
@export var occupies_full_cell := true

## Only read when blocks_movement is true AND occupies_full_cell is
## true. Must match the GridMap/GridActor `cell_size` this object's cell
## actually uses on X/Z -- Y is set huge (see _build_collision_body())
## and is not meaningful here.
@export var full_cell_size := Vector3(1.0, 1.0, 1.0)

## Only read when blocks_movement is true AND occupies_full_cell is
## false. Radius, in meters, of THIS OBJECT's own physical footprint
## around its own global_position.
##
## NOT the full effective blocking distance by itself -- since
## obstruction is a real shape-vs-shape physics query now (see
## grid_actor.gd's file header), the actor doing the moving also
## contributes its OWN real radius (a capsule of radius 0.4 in this
## framework's default player rig). Two shapes overlap when the
## distance between their centers is less than the SUM of both radii,
## the same as any real two-body collision -- so an actor effectively
## can't get closer than roughly (occupancy_radius + the actor's own
## radius) to this object's center, not just occupancy_radius alone.
## This is a genuine, deliberate improvement over the old grid-cell
## version of this check (README item 36's "Apple Problem" fix), which
## compared a step's bare LANDING POINT against occupancy_radius --
## correct for walls (which got a separate capsule-radius patch of
## their own, README item 29) but silently treated the actor as a
## zero-size point specifically for footprint objects, an inconsistency
## this rewrite removes rather than preserves. Tune this DOWN from what
## a point-based radius would suggest to compensate: this framework's
## demo Apple uses 0.08 (not 0.15) specifically so a step landing 0.5m
## from its center -- one full sub-cell step away -- stays open against
## a 0.4-radius capsule (0.08 + 0.4 = 0.48 < 0.5).
@export var occupancy_radius := 0.08

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
		_build_collision_body()
	if display_name.is_empty():
		display_name = name
	label = InteractionLabel.new()
	label.height_offset = label_height_offset
	add_child(label)


## Y-extent given to every generated collision shape below, regardless
## of the object's own height or Y position. Deliberately huge, not
## sized to the object's actual visual footprint -- this reproduces, via
## physics, the exact "X/Z only, deliberately" rule the old grid-cell
## version of this check documented: an object's height above the floor
## (a chest at y=0.35, a plant at y=0.3) has nothing to do with whether
## it blocks a same-plane XZ move, so the collider is made tall enough
## that it always overlaps any physically plausible actor probe
## regardless of either object's exact Y, rather than needing the two to
## be precisely aligned.
const _OBSTRUCTION_COLUMN_HEIGHT := 100.0


## Builds this object's real physics presence on
## GridActor.OBJECT_COLLISION_LAYER_BIT -- a plain StaticBody3D (no
## script, no signals of its own) with one CollisionShape3D sized per
## occupies_full_cell/full_cell_size/occupancy_radius above. Its
## collision_mask is 0 (it never needs to detect anything itself; it
## only needs to BE detectable) so it costs nothing in physics
## processing beyond existing as a queryable shape.
func _build_collision_body() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << (GridActor.OBJECT_COLLISION_LAYER_BIT - 1)
	body.collision_mask = 0
	add_child(body)

	var shape_node := CollisionShape3D.new()
	if occupies_full_cell:
		var box := BoxShape3D.new()
		box.size = Vector3(full_cell_size.x, _OBSTRUCTION_COLUMN_HEIGHT, full_cell_size.z)
		shape_node.shape = box
	else:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = occupancy_radius
		cylinder.height = _OBSTRUCTION_COLUMN_HEIGHT
		shape_node.shape = cylinder
	body.add_child(shape_node)


## Default verb shown for a type that's active but has no entry in
## interaction_prompts -- only ever consulted on a multi-type object
## (see prompt_for()); a single-type object always uses
## interaction_prompt instead, which has its own default ("Interact").
const _DEFAULT_PROMPTS := {
	InteractionType.EXAMINE: "Examine",
	InteractionType.TALK: "Talk",
	InteractionType.HARVEST: "Harvest",
	InteractionType.OPEN: "Open",
	InteractionType.CLIMB: "Climb",
	InteractionType.PASS_THROUGH: "Pass Through",
	InteractionType.TOGGLE: "Toggle",
}


## True if `type`'s bit is set in interaction_flags.
func has_interaction_type(type: InteractionType) -> bool:
	return (interaction_flags & (1 << type)) != 0


## Every InteractionType currently active on this instance, in
## InteractionType declaration order (EXAMINE first, TOGGLE last) -- a
## deterministic, designer-legible order rather than bit-scan order
## (they're the same order here, but stated explicitly since callers,
## e.g. InteractionController's secondary-action list, rely on it being
## stable run to run).
func active_interaction_types() -> Array[InteractionType]:
	var out: Array[InteractionType] = []
	for type in InteractionType.values():
		if has_interaction_type(type):
			out.append(type)
	return out


## Which type an unqualified interact() call (no `type` argument) should
## run. A single-flag object (every existing Chest/Plant/Apple) always
## returns its one active type, unaffected by
## primary_interaction_type_override. A multi-flag object uses that
## override IF it's actually one of the active types, otherwise falls
## back to the lowest-value active type. An object with NO flags set at
## all (interaction_flags == 0, not the default but reachable by
## clearing every checkbox) returns EXAMINE as a last-resort, harmless
## default -- has_interaction_type(EXAMINE) will be false for it too, so
## interact() below still correctly no-ops rather than running EXAMINE
## behavior that was never actually opted into.
func primary_interaction_type() -> InteractionType:
	var active := active_interaction_types()
	if active.is_empty():
		return InteractionType.EXAMINE
	if active.size() == 1:
		return active[0]
	if has_interaction_type(primary_interaction_type_override):
		return primary_interaction_type_override
	return active[0]


## The verb to display for `type`. Single-type objects always use
## interaction_prompt (unchanged from before interaction_flags existed);
## multi-type objects look up interaction_prompts first, falling back to
## a generic per-type default so an object with a freshly-ticked flag
## and no custom wording yet still reads sensibly.
func prompt_for(type: InteractionType) -> String:
	if active_interaction_types().size() <= 1:
		return interaction_prompt
	if interaction_prompts.has(type):
		return interaction_prompts[type]
	return _DEFAULT_PROMPTS.get(type, "Interact")


## Entry point interaction systems should call. Handles the one_shot
## guard, routes to the virtual handler matching `type`, then emits the
## generic signal. Subclasses override the specific `_on_*` handler for
## the type(s) they declared -- a chest (OPEN) overrides `_on_open()`, a
## garden plant (HARVEST) overrides `_on_harvest()` -- not `interact()`
## itself.
##
## `type` defaults to -1, meaning "use primary_interaction_type()" --
## every existing single-type call site (InteractionController's F-key
## confirm) can keep calling `interact(source)` with no second argument
## and get exactly the same behavior as before interaction_flags
## existed. A caller that wants a SPECIFIC one of several active types
## (e.g. InteractionController triggering a Merchant's secondary "Open
## Satchel" action) passes it explicitly. `type` is plain `int`, not
## `InteractionType`, purely so -1 is a valid sentinel value to pass --
## GDScript enum-typed parameters don't reserve an "unset" member for
## this. Passing a type this object doesn't actually have active is a
## documented no-op, not a crash or a silent fallback to the primary --
## a caller that gets this wrong (a stale UI showing an action that's no
## longer available) should find out, not have it quietly redirected
## somewhere else.
func interact(source: Node, type: int = -1) -> void:
	if one_shot and consumed:
		return

	var resolved: InteractionType = primary_interaction_type() if type == -1 else (type as InteractionType)
	if not has_interaction_type(resolved):
		return

	match resolved:
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
