# game_feedback.gd
# Godot version: 4.6
#
# Autoload singleton (see project.godot's [autoload] section) providing
# one thing: a transient on-screen text message, for interaction effects
# that used to only print() to the console -- talking to the Merchant,
# opening the Chest, harvesting the Plant/Apple -- which is invisible to
# anyone actually playing the scene. Same "one small owned concern,
# reachable from anywhere without wiring a reference through every
# caller" shape as game_state_manager.gd -- see that file's header for
# the fuller case for an autoload here. Deliberately NOT given a
# class_name for the same reason documented there: a script can't
# declare class_name X while also being registered as an autoload
# singleton named X -- the autoload registration already provides the
# global `GameFeedback` identifier every caller needs.
#
# Deliberately NOT a dialogue/quest-log system -- one line, replaced
# outright by the next call, shown for a fixed duration then hidden.
# Anything richer (a scrolling log, multiple simultaneous messages,
# portraits) is a real design decision for later, not guessed at here.

extends CanvasLayer

@export var display_seconds := 2.5

var _box: PanelContainer
var _label: Label
var _hide_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15

	_box = PanelContainer.new()
	_box.process_mode = Node.PROCESS_MODE_ALWAYS
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.offset_left = -220
	_box.offset_right = 220
	_box.offset_top = 24
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_END
	_box.visible = false
	add_child(_box)

	_label = Label.new()
	_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_label)

	_hide_timer = Timer.new()
	_hide_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_hide_timer.one_shot = true
	_hide_timer.timeout.connect(func(): _box.visible = false)
	add_child(_hide_timer)


## Shows `text` for `display_seconds` (or `duration` if given and > 0),
## replacing whatever message is currently showing. Safe to call before
## _ready() has run (e.g. from another autoload's own _ready()) -- it
## just silently drops the message rather than crashing, since there is
## nothing to display yet; nothing in this project currently calls it
## that early, but this is cheap insurance against the ready-order class
## of bug this project has hit repeatedly elsewhere.
func show_message(text: String, duration: float = -1.0) -> void:
	if _label == null or _box == null:
		return
	_label.text = text
	_box.visible = true
	_hide_timer.start(duration if duration > 0.0 else display_seconds)
