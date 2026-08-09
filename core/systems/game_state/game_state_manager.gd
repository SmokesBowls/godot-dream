# game_state_manager.gd
# Godot version: 4.6
#
# THE ONLY system in this project allowed to write get_tree().paused.
# Registered as an autoload singleton (see project.godot's [autoload]
# section) so it exists before any scene and outlives scene changes.
#
# Why this exists: before this file, InteractionController owned
# get_tree().paused directly -- true on interaction start, false on
# interaction end/cancel. That's correct only as long as interaction is
# the SOLE reason the world can ever be paused. The moment a second
# system needs pause too (a cutscene, a menu, a scripted event), a
# plain boolean breaks in an easy-to-miss way:
#
#   interaction begins  -> paused = true
#   cutscene begins      -> (already paused, no-op)
#   interaction ends     -> paused = FALSE  <- wrong! cutscene still needs it
#
# Interaction ending would silently unpause a cutscene that has nothing
# to do with it, just because both happened to want the same boolean at
# the same time. This file replaces "the last system to touch a
# boolean wins" with reference-counted requests: every system that
# needs the world paused ADDS a request; every system releases only its
# OWN request; the tree is paused exactly when at least one request is
# still outstanding, decided here and nowhere else. No caller decides
# whether the tree resumes -- only whether ITS OWN request still exists.
#
# LIFECYCLE CLEANUP -- SIGNAL-DRIVEN, NOT POLLED: a request is cleaned
# up automatically if its requester leaves the tree without ever calling
# release_pause() (a bug elsewhere, a scene teardown, an exception
# mid-cutscene). This USED to be done with a WeakRef + a per-frame
# _process() sweep checking every request for a dead ref, every frame,
# forever, purely as a failsafe for the rare case a requester vanishes
# uncleanly -- a continuous polling cost paid every frame to guard
# against an event that here happens at most a handful of times a
# session. Replaced with the actual Godot-native signal for it:
# request_pause() connects to the requester's own `tree_exited` (built
# in to every Node), and that connection itself removes every request
# from that requester the moment it fires. No standing loop, no
# per-frame scan -- cleanup only runs AT ALL when a requester actually
# exits the tree, which is exactly the one moment it needs to run.
#
# Requesters are typed `Node` (not `Object`, the prior signature) BECAUSE
# `tree_exited` is a Node signal -- this system was already only ever
# called with Node requesters in practice (InteractionController, and
# every future requester this ticket anticipates: a cutscene player, a
# menu -- all real scene-tree nodes), so this isn't a narrowing that
# costs anything real, just makes explicit a constraint the WeakRef
# version left implicit.
#
# Known, accepted scope limit of `tree_exited`: it fires on ANY removal
# from the tree, not only on final deletion -- a node that's deliberately
# REPARENTED (removed then immediately re-added elsewhere) would also
# trigger this cleanup, releasing its request even though the node is
# still alive and might still want the world paused. Nothing in this
# project ever reparents a pause requester (InteractionController is a
# permanent scene node), so this is a real but currently theoretical
# edge; a future requester that DOES need to survive reparenting would
# need to re-request pause after being re-added, same as it would need
# to redo any other per-tree setup.
#
# WHY NOT A PLAIN STRING KEY: two different requesters can legitimately
# want the same reason at the same time (two separate NPC dialogues
# both requesting &"interaction", for instance) -- keying purely by
# reason would make the second request overwrite or collide with the
# first. Every request is identified by the PAIR (requester, reason),
# never by reason alone.

extends Node
# NOT `class_name GameStateManager` -- confirmed by actually running it
# (not assumed): Godot rejects a script that declares a class_name
# identical to the name it's ALSO registered under as an autoload
# singleton ("Class hides an autoload singleton"), and refuses to even
# compile. The autoload registration in project.godot's [autoload]
# section is what creates the global `GameStateManager` identifier
# every caller in this ticket uses (GameStateManager.request_pause(...)
# etc.) -- that identifier refers to the singleton INSTANCE, not a
# type, so class_name was never actually needed for the usage this
# ticket specifies.

## One requester's claim on "the world must stay paused," identified by
## (requester, reason). requester is a hard Node reference -- safe
## because every request is removed (see _on_requester_tree_exited())
## before the requester can ever actually be freed; see the file header
## for why that ordering is guaranteed.
class PauseRequest:
	var requester: Node
	var reason: StringName

	func _init(req: Node, r: StringName) -> void:
		requester = req
		reason = r


## Fires whenever the EFFECTIVE tree-paused state actually flips (0
## active requests -> 1+, or 1+ -> 0) -- never on every request add/
## remove, and never once per frame. Going from 1 request to 2 does NOT
## emit a second `true`; going from 2 down to 1 does NOT emit `false`.
## See _recompute_pause_state()'s doc comment for exactly how that's
## enforced.
signal pause_state_changed(is_paused: bool)

## Fired once per successful request_pause() call (not on an idempotent
## repeat -- see request_pause()'s doc comment). `requester` is
## guaranteed alive here; the call itself only succeeds because the
## caller is the live object making it.
signal pause_request_added(reason: StringName, requester: Object)

## Fired once per request actually removed -- via release_pause(),
## release_all_from(), OR the automatic tree_exited-triggered cleanup.
## `requester` is always the real requester object in every case,
## including the cleanup one: `tree_exited` fires while the node is
## still a valid, addressable Object (Godot removes a node from its
## tree BEFORE it's actually freed), so unlike the old WeakRef version
## there's no case where the requester is already gone by the time this
## fires.
signal pause_request_removed(reason: StringName, requester: Object)

var _requests: Array[PauseRequest] = []

## Tracks the last EFFECTIVE (has-any-request) state actually broadcast,
## so repeated recomputes that don't change anything never re-emit --
## see _recompute_pause_state().
var _last_effective_paused := false

## Which requesters currently have a `tree_exited` connection to this
## autoload. Connected lazily, once per requester, the first time it
## makes a request -- not once per (requester, reason) pair, so a
## requester holding several simultaneous reasons still only has one
## connection. Disconnected again the moment that requester has zero
## active requests left (see _sync_requester_connection()), so a
## requester that releases everything manually and sticks around in the
## tree for a long time afterward isn't left with a stale connection.
var _connected_requesters: Dictionary = {}  # Node -> true


## Adds a pause request from `requester` for `reason`. Idempotent: the
## SAME requester requesting the SAME reason twice is a no-op the
## second time -- it does not create a second entry, and does not
## require two release_pause() calls to fully clear. A DIFFERENT reason
## from the same requester, or the same reason from a DIFFERENT
## requester, is always a genuinely separate request.
func request_pause(requester: Node, reason: StringName) -> void:
	if requester == null:
		push_warning("GameStateManager.request_pause() called with a null requester -- ignored.")
		return
	if _find_index(requester, reason) != -1:
		return  # already requested -- idempotent, no duplicate entry
	_requests.append(PauseRequest.new(requester, reason))
	_sync_requester_connection(requester)
	pause_request_added.emit(reason, requester)
	_recompute_pause_state()


## Removes the (requester, reason) request if it exists. Calling this
## for a request that doesn't exist (already released, never made, or
## a typo'd reason) is a documented no-op -- no crash, and critically,
## it must never remove a DIFFERENT request by accident (see
## FAIL-SAFE behavior in the source ticket).
func release_pause(requester: Object, reason: StringName) -> void:
	var idx := _find_index(requester, reason)
	if idx == -1:
		return
	_requests.remove_at(idx)
	pause_request_removed.emit(reason, requester)
	if requester is Node:
		_sync_requester_connection(requester)
	_recompute_pause_state()


## Removes EVERY request belonging to `requester`, regardless of
## reason -- for a node that's about to be freed and wants to clean up
## all of its own claims in one call, rather than remembering every
## individual reason it ever requested. Also what the automatic
## tree_exited cleanup calls internally (see
## _on_requester_tree_exited()).
func release_all_from(requester: Object) -> void:
	var removed_any := false
	for i in range(_requests.size() - 1, -1, -1):
		var record := _requests[i]
		if record.requester == requester:
			var reason := record.reason
			_requests.remove_at(i)
			pause_request_removed.emit(reason, requester)
			removed_any = true
	if requester is Node:
		_sync_requester_connection(requester)
	if removed_any:
		_recompute_pause_state()


## True if `requester` currently has an active request for `reason`
## specifically (not just "is the tree paused at all," which could be
## true because of some OTHER requester entirely).
func is_paused_by(requester: Object, reason: StringName) -> bool:
	return _find_index(requester, reason) != -1


## True if ANY request from ANY requester is currently active.
func has_pause_requests() -> bool:
	return not _requests.is_empty()


## Total number of currently active requests, across all requesters and
## reasons (a requester holding 2 different reasons counts as 2).
func active_pause_count() -> int:
	return _requests.size()


## Answers "who is keeping the game paused?" without needing to poke
## internal arrays by hand -- returns one Dictionary per active request:
## {"requester": <display name>, "reason": <reason as a plain String>}.
## Every requester here is guaranteed alive (see the file header) --
## unlike the old WeakRef version, there's no "<freed>" case to guard
## against anymore.
func debug_active_requests() -> Array:
	var out: Array = []
	for record in _requests:
		var display_name: String = record.requester.name if (record.requester is Node) else str(record.requester)
		out.append({"requester": display_name, "reason": String(record.reason)})
	return out


func _find_index(requester: Object, reason: StringName) -> int:
	for i in range(_requests.size()):
		var record := _requests[i]
		if record.requester == requester and record.reason == reason:
			return i
	return -1


## Connects (or disconnects) this requester's `tree_exited` cleanup hook
## to match whether it currently holds any active request at all --
## called after every add/remove so the connection set never drifts out
## of sync with `_requests`. Idempotent either direction: connecting an
## already-connected requester, or disconnecting an already-disconnected
## one, is a no-op.
func _sync_requester_connection(requester: Node) -> void:
	var still_has_requests := false
	for record in _requests:
		if record.requester == requester:
			still_has_requests = true
			break

	var callback := Callable(self, "_on_requester_tree_exited").bind(requester)
	if still_has_requests:
		if not _connected_requesters.has(requester):
			_connected_requesters[requester] = true
			requester.tree_exited.connect(callback)
	else:
		if _connected_requesters.has(requester):
			_connected_requesters.erase(requester)
			if requester.tree_exited.is_connected(callback):
				requester.tree_exited.disconnect(callback)


## The automatic failsafe: fires when a requester leaves the tree for
## ANY reason (see the file header's note on reparenting) without ever
## calling release_pause()/release_all_from() itself. Releases every
## request it still held, same as if it had called release_all_from()
## on its own way out.
func _on_requester_tree_exited(requester: Node) -> void:
	_connected_requesters.erase(requester)
	release_all_from(requester)


## The single place get_tree().paused is ever assigned in this
## project -- see the file header. Writes AND signal emission are both
## gated on the EFFECTIVE state (has_requests, not the raw count)
## actually changing since the last time this ran: going from 1 request
## to 2 (or 2 down to 1) does neither -- the tree was already paused and
## stays paused, so there's nothing to change or announce.
func _recompute_pause_state() -> void:
	var should_be_paused := not _requests.is_empty()
	if should_be_paused == _last_effective_paused:
		return
	_last_effective_paused = should_be_paused
	get_tree().paused = should_be_paused
	pause_state_changed.emit(should_be_paused)
