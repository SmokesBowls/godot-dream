# run_zw_s_v1_parser_red.gd
# Godot version: 4.6.1
#
# Parser-only RED authority for ZW_S_V1_DREAM_BOUNDARY_CONTRACT v1.0.
# No production parser location is selected. A candidate may be injected only
# for acceptance testing through ZW_S_V1_PARSER_TEST_SCRIPT=res://... .

extends SceneTree

const CONTRACT_PATH := "res://ZW_S_V1_DREAM_BOUNDARY_CONTRACT.md"
const CONTRACT_SHA256 := "65b665654baffb8ed85392a3fd4869134e4bcce74c553ec4430a0b23cd942c2b"
const ROOM_STATE_FIXTURE := "res://tests/zw_s_v1_dream_boundary/fixtures/room_state.zw"
const PARSER_TEST_SCRIPT_ENV := "ZW_S_V1_PARSER_TEST_SCRIPT"

const ROOM_STATE_SOURCE := """{room_state
  {room_id room_a}
  {objects [
    {state
      {id apple_01}
      {type pickup}
      {collected true}
    }
    {state
      {id chest_01}
      {type chest}
      {remaining_loot
        {health_potion 1}
        {rope 1}
      }
    }
  ]}
}
"""

const EXPECTED_ROOM_STATE := {
	"room_state": {
		"room_id": "room_a",
		"objects": [
			{
				"state": {
					"id": "apple_01",
					"type": "pickup",
					"collected": true,
				},
			},
			{
				"state": {
					"id": "chest_01",
					"type": "chest",
					"remaining_loot": {
						"health_potion": 1,
						"rope": 1,
					},
				},
			},
		],
	},
}

var _subject: Object
var _subject_status := "not selected"
var _pass := 0
var _fail := 0
var _results: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== ZW-S V1 DREAM BOUNDARY -- parser-only RED ===")
	print("Contract: %s" % CONTRACT_PATH)
	print("Authorized slice: parser RED only")
	print("")

	if not _verify_authority_and_fixture():
		_print_report()
		quit(2)
		return

	_load_injected_subject()
	print("Parser subject: %s" % _subject_status)
	print("")

	_run_success_matrix()
	_run_failure_matrix()
	_print_report()
	quit(1 if _fail > 0 else 0)


func _verify_authority_and_fixture() -> bool:
	var contract_bytes := FileAccess.get_file_as_bytes(CONTRACT_PATH)
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(contract_bytes)
	var contract_hash := hash_context.finish().hex_encode()
	_check("CONTROL contract bytes match frozen SHA-256", contract_hash == CONTRACT_SHA256,
		"expected %s, got %s" % [CONTRACT_SHA256, contract_hash])

	var fixture := FileAccess.get_file_as_string(ROOM_STATE_FIXTURE)
	_check("CONTROL exact Dream witness fixture matches contract source", fixture == ROOM_STATE_SOURCE,
		"fixture bytes drifted from the frozen witness")
	return _fail == 0


func _load_injected_subject() -> void:
	var script_path := OS.get_environment(PARSER_TEST_SCRIPT_ENV)
	if script_path.is_empty():
		_subject_status = "UNAVAILABLE (%s is unset)" % PARSER_TEST_SCRIPT_ENV
		return
	if not script_path.begins_with("res://"):
		_subject_status = "INVALID (test script must use a res:// path)"
		return
	if not ResourceLoader.exists(script_path):
		_subject_status = "UNAVAILABLE (%s does not exist)" % script_path
		return
	var candidate := load(script_path)
	if not candidate is Script:
		_subject_status = "INVALID (%s is not a Script)" % script_path
		return
	_subject = candidate.new()
	if _subject == null or not _subject.has_method("parse"):
		_subject = null
		_subject_status = "INVALID (%s does not expose parse(source_text))" % script_path
		return
	_subject_status = "injected from %s" % script_path


func _run_success_matrix() -> void:
	var room_outcome := _parse(ROOM_STATE_SOURCE)
	var room_projection: Variant = room_outcome.get("projection") if _is_success(room_outcome) else null

	_check("R1 exact Dream room-state projection",
		_subject != null and _is_success(room_outcome) and room_projection == EXPECTED_ROOM_STATE,
		"no conformant parser projection is available")
	_check("R2 remaining_loot preserves health_potion and rope as siblings",
		_subject != null and _has_exact_remaining_loot(room_projection),
		"remaining_loot was absent, promoted, nested incorrectly, or otherwise changed")
	_check("R3 keyed projection recursively contains no _tag reinterpretation",
		_subject != null and _is_success(room_outcome) and not _contains_key_recursive(room_projection, "_tag"),
		"block keys must remain authored keys, never _tag metadata")

	var comments_source := "; leading comment\n{npc {id GUARD}} ; inline comment\n"
	_check_success_projection("R4 semicolon comments are fully removed", comments_source,
		{"npc": {"id": "GUARD"}})

	var multiple_source := "{npc {id GUARD}}\n{container {id CHEST}}\n"
	_check_success_projection("R5 multiple top-level blocks merge", multiple_source,
		{"npc": {"id": "GUARD"}, "container": {"id": "CHEST"}})

	var scalar_source := """{scalars
  {integer 42}
  {negative -7}
  {float 1.25}
  {leading .5}
  {truth true}
  {lie false}
  {word HELLO}
  {quoted "text"}
}
"""
	_check_success_projection("R6 scalar types follow frozen ZW-S v1.0", scalar_source, {
		"scalars": {
			"integer": 42,
			"negative": -7,
			"float": 1.25,
			"leading": 0.5,
			"truth": true,
			"lie": false,
			"word": "HELLO",
			"quoted": "text",
		},
	})

	var list_source := "{mixed [1 TWO {child {deep true}} false]}\n"
	_check_success_projection("R7 lists preserve scalar, block, and mixed values", list_source, {
		"mixed": [1, "TWO", {"child": {"deep": true}}, false],
	})

	var unknown_source := "{%future {arbitrary {opaque [ALPHA {child {deep true}}]}}}\n"
	_check_success_projection("R8 unknown and percent-prefixed structures survive", unknown_source, {
		"%future": {
			"arbitrary": {
				"opaque": ["ALPHA", {"child": {"deep": true}}],
			},
		},
	})

	var deep_case := _make_deep_case(32)
	_check_success_projection("R9 nested keyed blocks parse beyond donor fixture depth",
		deep_case["source"], deep_case["projection"])

	var first := _parse(ROOM_STATE_SOURCE)
	var second := _parse(ROOM_STATE_SOURCE)
	var malformed_source := "{npc {id GUARD}}\n{broken\n"
	var failed_first := _parse(malformed_source)
	var failed_second := _parse(malformed_source)
	_check("R10 identical valid and rejected inputs produce deterministic outcomes",
		_subject != null
		and _is_success(first)
		and first == second
		and _key_order_signature(first.get("projection")) == _key_order_signature(second.get("projection"))
		and _room_key_order_is_exact(first.get("projection"))
		and _is_closed_failure(failed_first)
		and failed_first == failed_second,
		"projection values/key order or rejected diagnostics differ across identical inputs")
	print("")


func _run_failure_matrix() -> void:
	_check_closed_failure("R11 unclosed block fails closed", "{npc {id GUARD}\n")
	_check_closed_failure("R12 unclosed list fails closed", "{npc {flags [A B}\n")
	_check_closed_failure("R13 unterminated string fails closed", "{npc {description \"open}\n")
	_check_closed_failure("R14 invalid block key fails closed", "{9invalid {id VALUE}}\n")
	_check_closed_failure("R15 unexpected closing delimiter fails closed", "}\n")
	_check_closed_failure("R16 valid prefix plus malformed tail fails closed",
		"{npc {id GUARD}}\n{container {id CHEST}\n")
	_check_closed_failure("R17 top-level scalar material fails closed", "HELLO\n")

	var partial := _parse("{npc {id GUARD}}\n{broken\n")
	_check("R18 failed outcome publishes no partial projection",
		_subject != null and _is_closed_failure(partial) and partial.get("projection") == null,
		"a malformed complete document must not publish its valid prefix")
	print("")


func _parse(source_text: String) -> Dictionary:
	if _subject == null:
		return {}
	var outcome: Variant = _subject.call("parse", source_text)
	if not outcome is Dictionary:
		return {}
	return outcome


func _check_success_projection(label: String, source_text: String, expected: Variant) -> void:
	var outcome := _parse(source_text)
	_check(label,
		_subject != null and _is_success(outcome) and outcome.get("projection") == expected,
		"projection differs from frozen keyed ZW-S semantics")


func _check_closed_failure(label: String, source_text: String) -> void:
	var outcome := _parse(source_text)
	_check(label, _subject != null and _is_closed_failure(outcome),
		"malformed complete input was not rejected with an empty projection")


func _has_exact_outcome_keys(outcome: Dictionary) -> bool:
	var keys := outcome.keys()
	keys.sort()
	return keys == ["error", "ok", "projection"]


func _is_success(outcome: Dictionary) -> bool:
	return _has_exact_outcome_keys(outcome) \
		and outcome.get("ok") is bool \
		and outcome.get("ok") == true \
		and outcome.get("projection") is Dictionary \
		and outcome.get("error") == null


func _is_closed_failure(outcome: Dictionary) -> bool:
	return _has_exact_outcome_keys(outcome) \
		and outcome.get("ok") is bool \
		and outcome.get("ok") == false \
		and outcome.get("projection") == null \
		and outcome.get("error") is String \
		and not String(outcome.get("error")).strip_edges().is_empty()


func _has_exact_remaining_loot(projection: Variant) -> bool:
	if not projection is Dictionary:
		return false
	var room: Variant = projection.get("room_state")
	if not room is Dictionary:
		return false
	var objects: Variant = room.get("objects")
	if not objects is Array or objects.size() != 2:
		return false
	var chest_wrapper: Variant = objects[1]
	if not chest_wrapper is Dictionary:
		return false
	var chest: Variant = chest_wrapper.get("state")
	if not chest is Dictionary:
		return false
	var loot: Variant = chest.get("remaining_loot")
	return loot is Dictionary \
		and loot == {"health_potion": 1, "rope": 1} \
		and not chest.has("health_potion") \
		and not chest.has("rope")


func _contains_key_recursive(value: Variant, key: String) -> bool:
	if value is Dictionary:
		if value.has(key):
			return true
		for child in value.values():
			if _contains_key_recursive(child, key):
				return true
	elif value is Array:
		for child in value:
			if _contains_key_recursive(child, key):
				return true
	return false


func _key_order_signature(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		var children := []
		for key in keys:
			children.append(_key_order_signature(value[key]))
		return {"keys": keys, "children": children}
	if value is Array:
		var array_children := []
		for child in value:
			array_children.append(_key_order_signature(child))
		return array_children
	return typeof(value)


func _room_key_order_is_exact(projection: Variant) -> bool:
	if not projection is Dictionary or projection.keys() != ["room_state"]:
		return false
	var room: Variant = projection.get("room_state")
	if not room is Dictionary or room.keys() != ["room_id", "objects"]:
		return false
	var objects: Variant = room.get("objects")
	if not objects is Array or objects.size() != 2:
		return false
	var apple_wrapper: Variant = objects[0]
	var chest_wrapper: Variant = objects[1]
	if not apple_wrapper is Dictionary or apple_wrapper.keys() != ["state"]:
		return false
	if not chest_wrapper is Dictionary or chest_wrapper.keys() != ["state"]:
		return false
	var apple: Variant = apple_wrapper.get("state")
	var chest: Variant = chest_wrapper.get("state")
	if not apple is Dictionary or apple.keys() != ["id", "type", "collected"]:
		return false
	if not chest is Dictionary or chest.keys() != ["id", "type", "remaining_loot"]:
		return false
	var loot: Variant = chest.get("remaining_loot")
	return loot is Dictionary and loot.keys() == ["health_potion", "rope"]


func _make_deep_case(depth: int) -> Dictionary:
	var source := "{leaf true}"
	var projection: Variant = {"leaf": true}
	for index in range(depth - 1, -1, -1):
		var key := "level_%02d" % index
		source = "{%s %s}" % [key, source]
		projection = {key: projection}
	return {"source": source + "\n", "projection": projection}


func _check(label: String, passed: bool, detail := "") -> void:
	if passed:
		_pass += 1
		_results.append({"status": "PASS", "label": label, "detail": ""})
		print("PASS: %s" % label)
	else:
		_fail += 1
		_results.append({"status": "FAIL", "label": label, "detail": detail})
		print("FAIL: %s" % label)
		if not detail.is_empty():
			print("      %s" % detail)


func _print_report() -> void:
	print("=== ZW-S V1 PARSER RED REPORT ===")
	print("PASS: %d" % _pass)
	print("FAIL: %d" % _fail)
	print("SLICE: %s" % ("RED" if _fail > 0 else "GREEN"))
	if _fail > 0:
		print("EXPECTED STOP: parser GREEN is not authorized")
