# toggle_list_window.gd
# Godot version: 4.6
#
# Base class for a modal, keyboard-driven "pick some rows from a short
# list" window -- currently LootWindow (choose what to take from a
# Chest) and ShopWindow (choose what to buy from a Merchant). Owns the
# one thing both actually share: the pause request (same
# GameStateManager multi-requester machinery InteractionController
# already uses -- see game_state_manager.gd's header for why a second,
# independent requester is safe), the procedurally-built panel (same
# "throwaway placeholder" spirit as InteractionController._build_panel()),
# and F/Esc/1-9 input handling. A subclass supplies row text and what
# "confirm" actually DOES with whichever entries are left checked --
# LootWindow hands them to an Inventory for free, ShopWindow charges
# currency for each one first. Centralizing this (rather than two
# separate near-identical windows) follows the same "two places computing
# the same thing is a bug waiting to happen" reasoning the tactical_world
# README's decision log uses repeatedly (e.g. items 22-32, 33's
# snap_to_grid_direction unification).
#
# NOT registered as an autoload itself -- LootWindow/ShopWindow are (see
# project.godot), each `extends ToggleListWindow` with no class_name of
# its own, same convention game_state_manager.gd documents for why an
# autoload can't share its name with a class_name.
#
# MUTUAL EXCLUSION WITH InteractionController: both this and
# InteractionController listen for keyboard input while the tree is
# paused (PROCESS_MODE_ALWAYS), and both can hold their own pause
# request at the same time in principle (Chest._on_open() only opens a
# LootWindow AFTER InteractionController has already released its own
# "interaction" pause request and closed its confirm panel -- see
# interaction_controller.gd's _confirm_interaction()). To keep
# InteractionController from also reacting to F/Esc/number keys (or
# re-scanning for a new interaction target) while one of these windows
# has focus, InteractionController._process()/_unhandled_input() now
# both bail out whenever the tree is paused for a reason that ISN'T its
# own interaction session -- see its own comment on that guard.

extends CanvasLayer
class_name ToggleListWindow

## True while a session is open -- subclasses' own open()/close() flip
## this via _open_session()/_close_session() below; callers outside this
## class should treat it read-only.
var active := false

## Array[Dictionary], each with at least an "id" (String) and "checked"
## (bool) key, plus whatever else the subclass's _row_text()/_on_confirmed()
## need (LootWindow adds "amount"; ShopWindow adds "price"). A loose
## Dictionary rather than a typed Resource -- same "nothing here needs
## that yet" reasoning inventory.gd's own header already gives for its
## items Dictionary.
var _entries: Array[Dictionary] = []
var _title := ""

var _panel: PanelContainer
var _title_label: Label
var _lines_label: Label

const _CHECK_ON := "[x]"
const _CHECK_OFF := "[ ]"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	_build_panel()


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -180
	_panel.offset_right = 180
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_lines_label = Label.new()
	_lines_label.process_mode = Node.PROCESS_MODE_ALWAYS
	vbox.add_child(_lines_label)


## Subclasses' own open() calls this once `_entries`/`_title` are ready.
## No-ops (does not re-open, does not clobber the in-progress session) if
## a session is already active -- only one of these windows can be open
## at a time in this framework (there's nothing that would even trigger
## two at once today, but silently overwriting one mid-session would be
## a worse bug than just refusing the second call).
func _open_session(entries: Array[Dictionary], title: String) -> void:
	if active:
		return
	active = true
	_entries = entries
	_title = title
	GameStateManager.request_pause(self, _pause_reason())
	_refresh()
	_panel.visible = true


## Which GameStateManager reason this window's pause request is filed
## under -- subclasses override so LootWindow and ShopWindow don't
## silently share (and therefore collide on) the same reason string.
func _pause_reason() -> StringName:
	return &"toggle_list_window"


## Row text for entry `i` (already includes the "[i+1] [x]/[ ]" prefix
## via _refresh() below -- this only supplies what comes after it).
## Subclasses override; base implementation is a placeholder, never
## meant to actually be shown.
func _row_text(_entry: Dictionary) -> String:
	return "Item"


## Called once, after the window has already closed and released its
## pause request, with exactly the entries that were still checked when
## the player pressed F. Subclasses override to do whatever "confirm"
## means for them; base implementation does nothing.
func _on_confirmed(_checked_entries: Array[Dictionary]) -> void:
	pass


func _refresh() -> void:
	_title_label.text = _title
	var lines := PackedStringArray()
	for i in range(_entries.size()):
		var entry := _entries[i]
		var mark: String = _CHECK_ON if entry.get("checked", true) else _CHECK_OFF
		lines.append("[%d] %s %s" % [i + 1, mark, _row_text(entry)])
	lines.append("[F] Confirm    [Esc] Cancel")
	_lines_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).keycode

	if key == KEY_F:
		_confirm()
		get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE:
		_close_session()
		get_viewport().set_input_as_handled()
	elif key >= KEY_1 and key <= KEY_9:
		var idx := key - KEY_1
		if idx < _entries.size():
			_entries[idx]["checked"] = not _entries[idx].get("checked", true)
			_refresh()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	var checked: Array[Dictionary] = []
	for entry in _entries:
		if entry.get("checked", true):
			checked.append(entry)
	_close_session()
	_on_confirmed(checked)


func _close_session() -> void:
	active = false
	_panel.visible = false
	GameStateManager.release_pause(self, _pause_reason())
