# run_boundary_1_red.gd
# Godot version: 4.6.1
#
# HEADLESS RED-PHASE TEST RUNNER for DREAM_WORLD_BOUNDARY_1_CONTRACT.md.
#
# Authorization boundary: DREAM_WORLD_BOUNDARY_1_CONTRACT.md is
# "CONTRACT ONLY -- IMPLEMENTATION NOT AUTHORIZED". This file does not
# implement TransitionCoordinator, Exit, an in-memory room-state store,
# or Room A/B fixtures. It only tests the frozen contract: it proves
# (a) the current repo has not silently jumped ahead of the contract,
# and (b) enumerates every required proof from the contract's positive
# acceptance list (SS15) and toxic/refusal list (SS16) as an explicit
# BLOCKED case, because the production entities each proof depends on
# do not exist yet. Every BLOCKED case names the exact contract section
# it comes from so a future implementation session can walk this file
# top to bottom and know precisely what to turn green -- without this
# file having invented any unauthorized path, node name, or class name
# on the implementation's behalf.
#
# Run:
#   godot --headless -s res://tests/dream_world_boundary_1/run_boundary_1_red.gd
#
# Exit code: 0 only if every check is PASS (no FAIL, no BLOCKED). Today
# that is impossible by design -- the milestone is not implemented --
# so a nonzero exit here is the expected, correct RED result, not a bug
# in this runner.

extends SceneTree

var _pass := 0
var _fail := 0
var _blocked := 0
var _results: Array[Dictionary] = []


func _initialize() -> void:
	print("=== DREAM WORLD BOUNDARY 1 -- RED test slice ===")
	print("Contract: res://DREAM_WORLD_BOUNDARY_1_CONTRACT.md (v1.0)")
	print("")

	_run_non_goal_guards()
	_run_acceptance_proof_checklist()
	_run_refusal_proof_checklist()

	_print_report()
	_print_expressibility_blockers()

	quit(1 if (_fail > 0 or _blocked > 0) else 0)


# ---------------------------------------------------------------------
# Section A -- non-goal guards.
#
# These CAN run and CAN pass today: they assert the repo has not
# accidentally implemented anything SS2 forbids, or anything SS3-SS5
# hasn't yet authorized a name for. A guard going red here means scope
# was silently added outside this contract's authorization, which is a
# real defect this runner exists to catch -- not a blocked probe.
# ---------------------------------------------------------------------
func _run_non_goal_guards() -> void:
	_check(
		"SS2 non-goal / SS4: akashic.tscn has not been given persistent-world " +
		"ownership (no attached script)",
		not _scene_has_script("res://core/akashic.tscn"),
	)
	_check(
		"SS3.4/SS7: no TransitionCoordinator implementation exists yet " +
		"(coordinator ownership is not authorized in this slice)",
		not _any_file_matches(["transition_coordinator", "transitioncoordinator"]),
	)
	_check(
		"SS3.4/SS7: no room-local Exit-node implementation exists yet",
		not _any_file_matches(["room_exit.gd", "transition_exit.gd"]),
	)
	_check(
		"SS3.5: no in-memory room-state store implementation exists yet",
		not _any_file_matches(["room_state_store", "roomstatestore"]),
	)
	_check(
		"SS2 non-goal: no room_a/room_b fixtures exist yet (must not be " +
		"copies of tactical_demo_world.gd when they're authorized)",
		not _any_file_matches(["room_a.tscn", "room_b.tscn", "room_a.gd", "room_b.gd"]),
	)
	print("")


func _scene_has_script(scene_path: String) -> bool:
	if not FileAccess.file_exists(scene_path):
		push_warning("Expected scene not found: %s" % scene_path)
		return false
	var text := FileAccess.get_file_as_string(scene_path)
	return text.findn("script = ExtResource") != -1 or text.findn("[sub_resource type=\"GDScript\"") != -1


func _any_file_matches(needles: Array) -> bool:
	var found := _scan_dir("res://core", needles)
	if found.is_empty():
		found = _scan_dir("res://tests", needles, ["run_boundary_1_red.gd"])
	return not found.is_empty()


func _scan_dir(path: String, needles: Array, skip_basenames: Array = []) -> Array[String]:
	var hits: Array[String] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return hits
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full := path.path_join(entry)
		if dir.current_is_dir():
			hits.append_array(_scan_dir(full, needles, skip_basenames))
		else:
			var lower := entry.to_lower()
			if not skip_basenames.has(entry):
				for needle in needles:
					if lower.find(String(needle).to_lower()) != -1:
						hits.append(full)
						break
		entry = dir.get_next()
	dir.list_dir_end()
	return hits


# ---------------------------------------------------------------------
# Section B -- SS15 required positive acceptance proof, one BLOCKED
# case per numbered step. Each depends on TransitionCoordinator, the
# persistent runtime role (SS4), and Room A/B fixtures -- none of which
# this slice may create.
# ---------------------------------------------------------------------
func _run_acceptance_proof_checklist() -> void:
	var steps := [
		"1. Begin in Room A at its declared starting entrance.",
		"2. Record Player and Inventory runtime instance identities.",
		"3. Pick up room_a/apple_01.",
		"4. Take a strict subset of room_a/chest_01 loot.",
		"5. Confirm both traveler inventory mutations.",
		"6. Leave through Room A's named exit.",
		"7. Arrive in Room B through the requested named entrance.",
		"8. Prove the same Player instance survived.",
		"9. Prove the same Inventory instance survived.",
		"10. Prove controls, camera, UI, and room-local interaction function in B.",
		"11. Return through Room B's named exit.",
		"12. Arrive in Room A through the requested named entrance.",
		"13. Prove the same Player and Inventory instances again.",
		"14. Prove apple_01 remains collected and unavailable.",
		"15. Prove chest_01 has the exact remembered remaining_loot.",
		"16. Prove controls, camera, UI, collision, and interaction function in A.",
		"17. Prove no transition pause claim remains after successful completion.",
	]
	for step in steps:
		_blocked_probe(
			"SS15 acceptance proof: " + step,
			"requires TransitionCoordinator + Room A/B fixtures (SS4/SS5), not authorized in this slice",
		)
	print("")


# ---------------------------------------------------------------------
# Section C -- SS16 required toxic/refusal proofs.
# ---------------------------------------------------------------------
func _run_refusal_proof_checklist() -> void:
	var refusals := [
		["16.1 Missing destination resource", "unknown destination_room_id must leave current room active, traveler unchanged, no room-state mutation, visible failure"],
		["16.2 Missing entrance", "valid destination room + unknown entrance ID must discard staged destination, leave current room active, traveler unchanged"],
		["16.3 Duplicate entrance", "destination containing destination_entrance_id more than once must reject as ambiguous, no commit"],
		["16.4 Room identity mismatch", "staged room_id disagreeing with request's destination_room_id must reject, no commit"],
		["16.5 Stale source request", "source_room_id/exit_id not matching the active room must reject with no staging side effects"],
		["16.6 Active modal", "interaction OR LootWindow OR ShopWindow active must reject transition, modal stays active, current room untouched"],
		["16.7 Room-local pause requester teardown", "an Exit-owned pause claim must be releasable on room teardown and never usable as transition ownership"],
		["16.8 Independent pause claim", "coordinator releasing its own claim must not resume gameplay while another requester's claim remains"],
		["16.9 State identity collision", "duplicate stateful object IDs within one room must reject room activation/staging before current-room destruction"],
	]
	for pair in refusals:
		_blocked_probe(
			"SS%s: %s" % [pair[0], pair[1]],
			"requires TransitionCoordinator + fail-closed staging/pause machinery (SS8-SS10), not authorized in this slice",
		)
	print("")


# ---------------------------------------------------------------------
# Bookkeeping.
# ---------------------------------------------------------------------
func _check(name: String, passed: bool) -> void:
	if passed:
		_pass += 1
	else:
		_fail += 1
	_results.append({"name": name, "status": "PASS" if passed else "FAIL"})
	print("[%s] %s" % ["PASS" if passed else "FAIL", name])


func _blocked_probe(name: String, reason: String) -> void:
	_blocked += 1
	_results.append({"name": name, "status": "BLOCKED", "reason": reason})
	print("[BLOCKED] %s\n           -- %s" % [name, reason])


func _print_report() -> void:
	print("")
	print("=== Summary ===")
	print("PASS:    %d" % _pass)
	print("FAIL:    %d" % _fail)
	print("BLOCKED: %d (expected -- SS1: implementation not authorized)" % _blocked)


func _print_expressibility_blockers() -> void:
	print("")
	print("=== Expressibility blockers ===")
	print("Contract clauses this slice could not even encode as a concrete,")
	print("runnable test without the test itself unilaterally choosing an")
	print("unauthorized implementation detail:")
	print("")
	print("- SS4/SS5: no final node/scene/script/class name is picked yet for")
	print("  the persistent runtime role or TransitionCoordinator. A test that")
	print("  loads a specific script path to instantiate it would be inventing")
	print("  that name on the implementation's behalf, which SS4 explicitly")
	print("  reserves for a future decision -- so no such load can appear here.")
	print("- SS15/SS16 GUI-facing proofs (controls, camera, UI, collision")
	print("  \"function\" in a room) are excluded from SS17's headless evidence")
	print("  class by the contract's own rule: \"A headless transition test")
	print("  does not prove GUI presentation.\" Those steps can only ever be")
	print("  closed by a real, visually-verified run once fixtures exist, not")
	print("  by any headless script including this one.")
	print("- SS13 exact remaining_loot equality has no chest data schema yet")
	print("  (chest.gd's current loot representation is pre-boundary and out")
	print("  of scope to redesign here), so no concrete equality assertion")
	print("  can be written until that schema is part of an authorized slice.")
