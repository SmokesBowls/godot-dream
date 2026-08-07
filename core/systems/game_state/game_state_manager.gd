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
# WHY WEAK REFERENCES: a request is stored as a WeakRef to its
# requester, not a hard reference. If the requesting node is freed
# without ever calling release_pause() (a bug elsewhere, a scene
# teardown, an exception mid-cutscene), a hard reference would leave a
# permanently dangling pause request and freeze the game forever with
# no way to recover short of restarting. A dead WeakRef is detected
# (get_ref() returns null) and pruned automatically -- every public
# method prunes before it does anything else, and _process() (this node
# is PROCESS_MODE_ALWAYS, so it keeps running even while paused) prunes
# every frame too, so a requester freed without warning is caught
# within one frame even if nothing else ever calls into this file
# again.
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
## (requester, reason). requester is a WeakRef, never a hard Object
## reference -- see the file header for why.
class PauseRequest:
	var requester: WeakRef
	var reason: StringName

	func _init(req: Object, r: StringName) -> void:
		requester = weakref(req)
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
## release_all_from(), OR the automatic stale-WeakRef cleanup. In the
## cleanup case the requester has ALREADY been freed by the time this
## fires, so `requester` is passed as null rather than a dangling
## reference -- callers that care which case this was should treat a
## null requester as "that request's owner is already gone," not
## as an error.
signal pause_request_removed(reason: StringName, requester: Object)

var _requests: Array[PauseRequest] = []

## Tracks the last EFFECTIVE (has-any-request) state actually broadcast,
## so repeated recomputes that don't change anything never re-emit --
## see _recompute_pause_state().
var _last_effective_paused := false


func _ready() -> void:
	# Must keep running even while the tree it manages is paused --
	# otherwise nothing could ever detect "the pausing node was freed,
	# time to clean up and resume" once paused, and the game would stay
	# frozen forever the instant that happened.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	# Catches a requester that was freed WITHOUT ever calling
	# release_pause() -- the ticket this file implements is explicit
	# that this must not be relied on exclusively (every public method
	# below also prunes before doing its own work), but a requester can
	# be freed at any arbitrary moment with nothing else calling into
	# this file at all, so a standing per-frame check is the only way
	# to guarantee it's ever caught.
	_prune_dead_requests()


## Adds a pause request from `requester` for `reason`. Idempotent: the
## SAME requester requesting the SAME reason twice is a no-op the
## second time -- it does not create a second entry, and does not
## require two release_pause() calls to fully clear. A DIFFERENT reason
## from the same requester, or the same reason from a DIFFERENT
## requester, is always a genuinely separate request.
func request_pause(requester: Object, reason: StringName) -> void:
	_prune_dead_requests()
	if requester == null:
		push_warning("GameStateManager.request_pause() called with a null requester -- ignored.")
		return
	if _find_index(requester, reason) != -1:
		return  # already requested -- idempotent, no duplicate entry
	_requests.append(PauseRequest.new(requester, reason))
	pause_request_added.emit(reason, requester)
	_recompute_pause_state()


## Removes the (requester, reason) request if it exists. Calling this
## for a request that doesn't exist (already released, never made, or
## a typo'd reason) is a documented no-op -- no crash, and critically,
## it must never remove a DIFFERENT request by accident (see
## FAIL-SAFE behavior in the source ticket).
func release_pause(requester: Object, reason: StringName) -> void:
	_prune_dead_requests()
	var idx := _find_index(requester, reason)
	if idx == -1:
		return
	_requests.remove_at(idx)
	pause_request_removed.emit(reason, requester)
	_recompute_pause_state()


## Removes EVERY request belonging to `requester`, regardless of
## reason -- for a node that's about to be freed and wants to clean up
## all of its own claims in one call, rather than remembering every
## individual reason it ever requested.
func release_all_from(requester: Object) -> void:
	_prune_dead_requests()
	var removed_any := false
	for i in range(_requests.size() - 1, -1, -1):
		var record := _requests[i]
		if record.requester.get_ref() == requester:
			var reason := record.reason
			_requests.remove_at(i)
			pause_request_removed.emit(reason, requester)
			removed_any = true
	if removed_any:
		_recompute_pause_state()


## True if `requester` currently has an active request for `reason`
## specifically (not just "is the tree paused at all," which could be
## true because of some OTHER requester entirely).
func is_paused_by(requester: Object, reason: StringName) -> bool:
	_prune_dead_requests()
	return _find_index(requester, reason) != -1


## True if ANY request from ANY requester is currently active.
func has_pause_requests() -> bool:
	_prune_dead_requests()
	return not _requests.is_empty()


## Total number of currently active requests, across all requesters and
## reasons (a requester holding 2 different reasons counts as 2).
func active_pause_count() -> int:
	_prune_dead_requests()
	return _requests.size()


## Answers "who is keeping the game paused?" without needing to poke
## internal arrays by hand -- returns one Dictionary per active request:
## {"requester": <display name, or "<freed>">, "reason": <reason as a
## plain String>}. Freed-but-not-yet-pruned entries can't normally
## appear here (this prunes first, same as every other public method),
## but the freed-name fallback is kept for defense in depth rather than
## assuming pruning always runs first in every conceivable call order.
func debug_active_requests() -> Array:
	_prune_dead_requests()
	var out: Array = []
	for record in _requests:
		var alive: Object = record.requester.get_ref()
		var display_name := "<freed>"
		if alive != null:
			display_name = alive.name if (alive is Node) else str(alive)
		out.append({"requester": display_name, "reason": String(record.reason)})
	return out


func _find_index(requester: Object, reason: StringName) -> int:
	for i in range(_requests.size()):
		var record := _requests[i]
		if record.requester.get_ref() == requester and record.reason == reason:
			return i
	return -1


## Removes any request whose requester has been freed (get_ref() ==
## null) -- see the file header for why this can't be optional.
## FAIL-SAFE: a malformed/stale entry is simply dropped, never crashes,
## and never causes an unpause on its own -- removing ONE stale entry
## still leaves every other VALID entry counted normally by the
## recompute that follows.
func _prune_dead_requests() -> void:
	var changed := false
	for i in range(_requests.size() - 1, -1, -1):
		var record := _requests[i]
		if record.requester.get_ref() == null:
			var reason := record.reason
			_requests.remove_at(i)
			pause_request_removed.emit(reason, null)  # owner already gone -- nothing alive to pass
			changed = true
	if changed:
		_recompute_pause_state()


## The single place get_tree().paused is ever assigned in this
## project -- see the file header. Writes AND signal emission are both
## gated on the EFFECTIVE state (has_requests, not the raw count)
## actually changing since the last time this ran: going from 1 request
## to 2 (or 2 down to 1) does neither -- the tree was already paused and
## stays paused, so there's nothing to change or announce. This is what
## satisfies "emit pause_state_changed only when effective tree pause
## state changes," not once per request and never once per frame
## despite _process() calling into the prune path every frame.
func _recompute_pause_state() -> void:
	var should_be_paused := not _requests.is_empty()
	if should_be_paused == _last_effective_paused:
		return
	_last_effective_paused = should_be_paused
	get_tree().paused = should_be_paused
	pause_state_changed.emit(should_be_paused)
