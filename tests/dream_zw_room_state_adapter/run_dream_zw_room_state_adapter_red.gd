# DREAM_ZW_ROOM_STATE_ADAPTER_RED
# Godot version: 4.6.1
#
# Test-only authority for DREAM_ZW_ROOM_STATE_ADAPTER_BOUNDARY_CONTRACT v1.0.
# The existing conformant parser is a fixed dependency. A room-state boundary
# candidate may be injected only through a test environment variable.

extends SceneTree

const CONTRACT_PATH := "res://DREAM_ZW_ROOM_STATE_ADAPTER_BOUNDARY_CONTRACT.md"
const CONTRACT_SHA256 := "04737a95d68bda251aa608e97f46e4fa212e8603c27a68db00d0987cca71793f"
const PARSER_PATH := "res://core/systems/zw/zw_s_v1_parser.gd"
const PARSER_SHA256 := "f9253b6037ab3697c33692f4ad623913a4e0cfb8f32c715e9c68771951bbf798"
const ROOM_STATE_FIXTURE := "res://tests/zw_s_v1_dream_boundary/fixtures/room_state.zw"
const ROOM_STATE_FIXTURE_SHA256 := "e4cfaeaea99cf4da1f9161b8467fca0e10b01ae0019dc98bfc322937d884d7c2"
const BOUNDARY_TEST_SCRIPT_ENV := "DREAM_ZW_ROOM_STATE_BOUNDARY_TEST_SCRIPT"

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

const UNKNOWN_SOURCE := """{room_state
  {room_id room_variant}
  {climate
    {season winter}
    {temperature .5}
  }
  {objects [
    {state
      {id relic_77}
      {type artifact}
      {unknown_scalar ORANGE}
      {%future
        {opaque [ALPHA {child {deep true}}]}
      }
    }
  ]}
}
"""

const DUPLICATE_ID_SOURCE := """{room_state
  {room_id duplicate_room}
  {objects [
    {state {id same_id} {value FIRST}}
    {state {id same_id} {value SECOND}}
  ]}
}
"""

const NONLEXICAL_ORDER_SOURCE := """{room_state
  {room_id order_room}
  {objects [
    {state {id zeta_01} {value FIRST}}
    {state {id alpha_01} {value SECOND}}
  ]}
}
"""

const WRONG_ROOT_SOURCE := "{world_state {room_id room_a} {objects []}}\n"
const EXTRA_ROOT_SOURCE := "{room_state {room_id room_a} {objects []}}\n{other {value 1}}\n"
const SCALAR_ROOT_SOURCE := "{room_state VALUE}\n"
const EMPTY_ROOM_SOURCE := "{room_state {room_id empty_room} {objects []}}\n"
const MISSING_ROOM_ID_SOURCE := "{room_state {objects []}}\n"
const EMPTY_ROOM_ID_SOURCE := "{room_state {room_id \"\"} {objects []}}\n"
const WRONG_ROOM_ID_SOURCE := "{room_state {room_id 7} {objects []}}\n"
const ARRAY_ROOM_ID_SOURCE := "{room_state {room_id [room_a]} {objects []}}\n"
const MISSING_OBJECTS_SOURCE := "{room_state {room_id room_a}}\n"
const MISSING_OBJECT_ID_SOURCE := "{room_state {room_id room_a} {objects [{state {type pickup}}]}}\n"
const EMPTY_OBJECT_ID_SOURCE := "{room_state {room_id room_a} {objects [{state {id \"\"}}]}}\n"
const WRONG_OBJECT_ID_SOURCE := "{room_state {room_id room_a} {objects [{state {id 7}}]}}\n"
const ARRAY_OBJECT_ID_SOURCE := "{room_state {room_id room_a} {objects [{state {id [object_01]}}]}}\n"
const WRONG_OBJECTS_SOURCE := "{room_state {room_id room_a} {objects VALUE}}\n"
const DICTIONARY_OBJECTS_SOURCE := "{room_state {room_id room_a} {objects {state {id object_01}}}}\n"
const SCALAR_OBJECT_ITEM_SOURCE := "{room_state {room_id room_a} {objects [7]}}\n"
const SCALAR_STATE_SOURCE := "{room_state {room_id room_a} {objects [{state VALUE}]}}\n"
const WRONG_WRAPPER_SOURCE := "{room_state {room_id room_a} {objects [{object {id object_01}}]}}\n"
const MALFORMED_SOURCE := "{room_state {room_id room_a} {objects []}\n"
const MALFORMED_LIST_SOURCE := "{room_state {room_id room_a} {objects [}\n"

const EXPECTED_ROOM_STATE_OUTCOME := {
	"ok": true,
	"room_state": {
		"room_id": "room_a",
		"objects": {
			"apple_01": {
				"id": "apple_01",
				"type": "pickup",
				"collected": true,
			},
			"chest_01": {
				"id": "chest_01",
				"type": "chest",
				"remaining_loot": {
					"health_potion": 1,
					"rope": 1,
				},
			},
		},
	},
	"error": null,
}

const EXPECTED_UNKNOWN_OUTCOME := {
	"ok": true,
	"room_state": {
		"room_id": "room_variant",
		"climate": {
			"season": "winter",
			"temperature": 0.5,
		},
		"objects": {
			"relic_77": {
				"id": "relic_77",
				"type": "artifact",
				"unknown_scalar": "ORANGE",
				"%future": {
					"opaque": ["ALPHA", {"child": {"deep": true}}],
				},
			},
		},
	},
	"error": null,
}

const EXPECTED_NONLEXICAL_ORDER_OUTCOME := {
	"ok": true,
	"room_state": {
		"room_id": "order_room",
		"objects": {
			"zeta_01": {"id": "zeta_01", "value": "FIRST"},
			"alpha_01": {"id": "alpha_01", "value": "SECOND"},
		},
	},
	"error": null,
}

const PARSER_SCRIPT := preload(PARSER_PATH)

var _parser: Object
var _subject_script: Script
var _subject_status := "not selected"
var _pass := 0
var _fail := 0

var _room_parse: Dictionary = {}
var _unknown_parse: Dictionary = {}
var _duplicate_parse: Dictionary = {}
var _nonlexical_order_parse: Dictionary = {}
var _wrong_root_parse: Dictionary = {}
var _extra_root_parse: Dictionary = {}
var _scalar_root_parse: Dictionary = {}
var _empty_room_parse: Dictionary = {}
var _missing_room_id_parse: Dictionary = {}
var _empty_room_id_parse: Dictionary = {}
var _wrong_room_id_parse: Dictionary = {}
var _array_room_id_parse: Dictionary = {}
var _missing_objects_parse: Dictionary = {}
var _missing_object_id_parse: Dictionary = {}
var _empty_object_id_parse: Dictionary = {}
var _wrong_object_id_parse: Dictionary = {}
var _array_object_id_parse: Dictionary = {}
var _wrong_objects_parse: Dictionary = {}
var _dictionary_objects_parse: Dictionary = {}
var _scalar_object_item_parse: Dictionary = {}
var _scalar_state_parse: Dictionary = {}
var _wrong_wrapper_parse: Dictionary = {}
var _malformed_parse: Dictionary = {}
var _malformed_list_parse: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== DREAM ZW ROOM-STATE ADAPTER -- intentional RED ===")
	print("Contract: %s" % CONTRACT_PATH)
	print("Authorized slice: contract/test only")
	print("")

	if not _run_controls():
		_print_report()
		quit(2)
		return

	_load_injected_subject()
	print("Room-state boundary subject: %s" % _subject_status)
	print("")

	_run_acceptance_matrix()
	_print_report()
	quit(1 if _fail > 0 else 0)


func _run_controls() -> bool:
	_check("CONTROL contract bytes match frozen SHA-256",
		_sha256_file(CONTRACT_PATH) == CONTRACT_SHA256,
		"room-state boundary contract bytes drifted")
	_check("CONTROL accepted parser bytes match frozen SHA-256",
		_sha256_file(PARSER_PATH) == PARSER_SHA256,
		"accepted parser bytes drifted")
	_check("CONTROL exact Dream fixture bytes match frozen SHA-256 and source",
		_sha256_file(ROOM_STATE_FIXTURE) == ROOM_STATE_FIXTURE_SHA256
		and FileAccess.get_file_as_string(ROOM_STATE_FIXTURE) == ROOM_STATE_SOURCE,
		"exact Dream witness fixture drifted")

	_parser = PARSER_SCRIPT.new()
	if _parser == null or not _parser.has_method("parse"):
		_check("CONTROL accepted parser exposes parse(source_text)", false,
			"accepted parser dependency could not be instantiated")
		return false

	_room_parse = _parse(ROOM_STATE_SOURCE)
	_unknown_parse = _parse(UNKNOWN_SOURCE)
	_duplicate_parse = _parse(DUPLICATE_ID_SOURCE)
	_nonlexical_order_parse = _parse(NONLEXICAL_ORDER_SOURCE)
	_wrong_root_parse = _parse(WRONG_ROOT_SOURCE)
	_extra_root_parse = _parse(EXTRA_ROOT_SOURCE)
	_scalar_root_parse = _parse(SCALAR_ROOT_SOURCE)
	_empty_room_parse = _parse(EMPTY_ROOM_SOURCE)
	_missing_room_id_parse = _parse(MISSING_ROOM_ID_SOURCE)
	_empty_room_id_parse = _parse(EMPTY_ROOM_ID_SOURCE)
	_wrong_room_id_parse = _parse(WRONG_ROOM_ID_SOURCE)
	_array_room_id_parse = _parse(ARRAY_ROOM_ID_SOURCE)
	_missing_objects_parse = _parse(MISSING_OBJECTS_SOURCE)
	_missing_object_id_parse = _parse(MISSING_OBJECT_ID_SOURCE)
	_empty_object_id_parse = _parse(EMPTY_OBJECT_ID_SOURCE)
	_wrong_object_id_parse = _parse(WRONG_OBJECT_ID_SOURCE)
	_array_object_id_parse = _parse(ARRAY_OBJECT_ID_SOURCE)
	_wrong_objects_parse = _parse(WRONG_OBJECTS_SOURCE)
	_dictionary_objects_parse = _parse(DICTIONARY_OBJECTS_SOURCE)
	_scalar_object_item_parse = _parse(SCALAR_OBJECT_ITEM_SOURCE)
	_scalar_state_parse = _parse(SCALAR_STATE_SOURCE)
	_wrong_wrapper_parse = _parse(WRONG_WRAPPER_SOURCE)
	_malformed_parse = _parse(MALFORMED_SOURCE)
	_malformed_list_parse = _parse(MALFORMED_LIST_SOURCE)

	_check("CONTROL every room-state fixture has its exact intended parser projection",
		_parser_fixture_projections_hold(),
		"a room-state fixture parsed to unintended semantic structure or scalar types")
	_check("CONTROL distinct malformed ZW sources fail closed with distinct parser diagnostics",
		_is_parser_failure(_malformed_parse)
		and _is_parser_failure(_malformed_list_parse)
		and _malformed_parse.get("error") != _malformed_list_parse.get("error"),
		"malformed sources did not produce distinct complete parser failures")
	return _fail == 0


func _parser_fixture_projections_hold() -> bool:
	var cases := [
		[_room_parse, {
			"room_state": {
				"room_id": "room_a",
				"objects": [
					{"state": {"id": "apple_01", "type": "pickup", "collected": true}},
					{"state": {"id": "chest_01", "type": "chest", "remaining_loot": {"health_potion": 1, "rope": 1}}},
				],
			},
		}],
		[_unknown_parse, {
			"room_state": {
				"room_id": "room_variant",
				"climate": {"season": "winter", "temperature": 0.5},
				"objects": [{"state": {
					"id": "relic_77",
					"type": "artifact",
					"unknown_scalar": "ORANGE",
					"%future": {"opaque": ["ALPHA", {"child": {"deep": true}}]},
				}}],
			},
		}],
		[_duplicate_parse, {"room_state": {
			"room_id": "duplicate_room",
			"objects": [
				{"state": {"id": "same_id", "value": "FIRST"}},
				{"state": {"id": "same_id", "value": "SECOND"}},
			],
		}}],
		[_nonlexical_order_parse, {"room_state": {
			"room_id": "order_room",
			"objects": [
				{"state": {"id": "zeta_01", "value": "FIRST"}},
				{"state": {"id": "alpha_01", "value": "SECOND"}},
			],
		}}],
		[_wrong_root_parse, {"world_state": {"room_id": "room_a", "objects": []}}],
		[_extra_root_parse, {
			"room_state": {"room_id": "room_a", "objects": []},
			"other": {"value": 1},
		}],
		[_scalar_root_parse, {"room_state": "VALUE"}],
		[_empty_room_parse, {"room_state": {"room_id": "empty_room", "objects": []}}],
		[_missing_room_id_parse, {"room_state": {"objects": []}}],
		[_empty_room_id_parse, {"room_state": {"room_id": "", "objects": []}}],
		[_wrong_room_id_parse, {"room_state": {"room_id": 7, "objects": []}}],
		[_array_room_id_parse, {"room_state": {"room_id": ["room_a"], "objects": []}}],
		[_missing_objects_parse, {"room_state": {"room_id": "room_a"}}],
		[_missing_object_id_parse, {"room_state": {
			"room_id": "room_a",
			"objects": [{"state": {"type": "pickup"}}],
		}}],
		[_empty_object_id_parse, {"room_state": {
			"room_id": "room_a",
			"objects": [{"state": {"id": ""}}],
		}}],
		[_wrong_object_id_parse, {"room_state": {
			"room_id": "room_a",
			"objects": [{"state": {"id": 7}}],
		}}],
		[_array_object_id_parse, {"room_state": {
			"room_id": "room_a",
			"objects": [{"state": {"id": ["object_01"]}}],
		}}],
		[_wrong_objects_parse, {"room_state": {"room_id": "room_a", "objects": "VALUE"}}],
		[_dictionary_objects_parse, {"room_state": {
			"room_id": "room_a",
			"objects": {"state": {"id": "object_01"}},
		}}],
		[_scalar_object_item_parse, {"room_state": {"room_id": "room_a", "objects": [7]}}],
		[_scalar_state_parse, {"room_state": {
			"room_id": "room_a",
			"objects": [{"state": "VALUE"}],
		}}],
		[_wrong_wrapper_parse, {"room_state": {
			"room_id": "room_a",
			"objects": [{"object": {"id": "object_01"}}],
		}}],
	]
	for fixture_case in cases:
		var outcome: Variant = fixture_case[0]
		var expected: Variant = fixture_case[1]
		if not outcome is Dictionary or not _is_parser_success(outcome):
			return false
		if not _exact_variant_equal(outcome.get("projection"), expected):
			return false
	return true


func _load_injected_subject() -> void:
	var script_path := OS.get_environment(BOUNDARY_TEST_SCRIPT_ENV)
	if script_path.is_empty():
		_subject_status = "UNAVAILABLE (%s is unset)" % BOUNDARY_TEST_SCRIPT_ENV
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
	var probe: Object = candidate.new()
	if probe == null or not probe.has_method("project_room_state"):
		_subject_status = "INVALID (%s does not expose project_room_state(parse_outcome))" % script_path
		return
	_subject_script = candidate
	_subject_status = "injected as a fresh per-call function carrier from %s" % script_path


func _run_acceptance_matrix() -> void:
	var exact := _project(_room_parse)
	_check("A1 exact Dream witness projection",
		_subject_script != null
		and _is_boundary_success(exact)
		and _exact_variant_equal(exact, EXPECTED_ROOM_STATE_OUTCOME),
		"exact parser-derived room-state projection is unavailable or changed")

	_check("A2 semantic room_id resolves as room_a",
		_subject_script != null and _room_value(exact, "room_id") == "room_a",
		"room_id was missing, inferred, or changed")

	var apple: Variant = _object_value(exact, "apple_01")
	_check("A3 apple_01 resolves by semantic id with collected=true",
		_subject_script != null and apple is Dictionary
		and apple.get("id") == "apple_01"
		and apple.get("collected") is bool
		and apple.get("collected") == true,
		"apple_01 did not resolve from its authored semantic id")

	var chest: Variant = _object_value(exact, "chest_01")
	_check("A4 chest_01 resolves by semantic id",
		_subject_script != null and chest is Dictionary and chest.get("id") == "chest_01",
		"chest_01 did not resolve from its authored semantic id")

	_check("A5 remaining_loot preserves health_potion and rope as exact siblings",
		_subject_script != null and _has_exact_remaining_loot(chest),
		"remaining_loot was dropped, promoted, nested incorrectly, or coerced")

	var malformed_boundary := _project(_malformed_parse)
	var malformed_list_boundary := _project(_malformed_list_parse)
	_check("A6 distinct parser failures remain fail-closed and visibly unchanged",
		_subject_script != null
		and _is_boundary_failure(malformed_boundary)
		and _is_boundary_failure(malformed_list_boundary)
		and malformed_boundary.get("error") == _malformed_parse.get("error")
		and malformed_list_boundary.get("error") == _malformed_list_parse.get("error")
		and malformed_boundary.get("error") != malformed_list_boundary.get("error"),
		"upstream parser rejections were hidden, hard-coded, rewritten, or partially projected")

	_check("A7 only exact valid parser outcome shapes are accepted",
		_subject_script != null and _invalid_parser_outcomes_reject(),
		"a fabricated, partial, contradictory, or extra-key parser outcome was accepted")

	_check("A8 room_state is the required and only semantic root",
		_subject_script != null and _all_boundary_fail([
			_wrong_root_parse,
			_extra_root_parse,
			_scalar_root_parse,
		]),
		"wrong, extra, or non-Dictionary semantic roots were accepted")

	_check("A9 exactly one non-empty String room_id is required",
		_subject_script != null and _all_boundary_fail([
			_missing_room_id_parse,
			_empty_room_id_parse,
			_wrong_room_id_parse,
			_array_room_id_parse,
		]),
		"missing, empty, or wrong-typed room_id material was accepted")

	_check("A10 every state object requires a semantic String id",
		_subject_script != null and _all_boundary_fail([
			_missing_objects_parse,
			_missing_object_id_parse,
			_empty_object_id_parse,
			_wrong_object_id_parse,
			_array_object_id_parse,
			_wrong_objects_parse,
			_dictionary_objects_parse,
			_scalar_object_item_parse,
			_scalar_state_parse,
			_wrong_wrapper_parse,
			{
				"ok": true,
				"projection": {"room_state": {
					"room_id": "room_a",
					"objects": [{
						"state": {"id": "object_01"},
						"extra": {"unknown": true},
					}],
				}},
				"error": null,
			},
		]),
		"a missing/invalid objects container, wrapper, state, or semantic id was accepted")

	var duplicate_result := _project(_duplicate_parse)
	_check("A11 duplicate semantic object ids reject without partial room projection",
		_subject_script != null
		and _is_boundary_failure(duplicate_result)
		and duplicate_result.get("room_state") == null,
		"duplicate ids were overwritten, merged, suffixed, or partially published")

	var unknown := _project(_unknown_parse)
	var empty_room := _project(_empty_room_parse)
	_check("A12 unknown room, state, nested, and percent fields are preserved",
		_subject_script != null
		and _is_boundary_success(unknown)
		and _exact_variant_equal(unknown, EXPECTED_UNKNOWN_OUTCOME),
		"unknown parser-preserved meaning was dropped, normalized, or reinterpreted")

	_check("A13 projection derives different semantic values rather than hard-coding witness ids",
		_subject_script != null
		and _is_boundary_success(unknown)
		and _room_value(unknown, "room_id") == "room_variant"
		and _object_value(unknown, "relic_77") is Dictionary
		and _object_value(unknown, "apple_01") == null
		and _is_boundary_success(empty_room)
		and _exact_variant_equal(empty_room, {
			"ok": true,
			"room_state": {"room_id": "empty_room", "objects": {}},
			"error": null,
		}),
		"boundary appears tied to room_a/apple_01 instead of supplied parser meaning")

	_check("A14 returned projection cannot mutate its parser outcome or a fresh parse",
		_subject_script != null and _mutation_isolation_holds(),
		"mutating the Dream projection rewrote parser-derived semantic material")

	_check("A15 repeated valid and rejected outcomes are deterministic",
		_subject_script != null and _determinism_holds(),
		"repeated room projections, key order, or validation diagnostics differ")
	print("")


func _invalid_parser_outcomes_reject() -> bool:
	var invalid := [
		{},
		{"projection": {}, "error": null},
		{"ok": true, "error": null},
		{"ok": true, "projection": {}},
		{"ok": false, "error": "failed"},
		{"ok": false, "projection": null},
		{"ok": true, "projection": {}, "error": null, "extra": 1},
		{"ok": "true", "projection": {}, "error": null},
		{"ok": 1, "projection": {}, "error": null},
		{"ok": true, "projection": null, "error": null},
		{"ok": true, "projection": [], "error": null},
		{"ok": true, "projection": {}, "error": "unexpected"},
		{"ok": false, "projection": {}, "error": "failed"},
		{"ok": false, "projection": null, "error": ""},
		{"ok": false, "projection": null, "error": "   "},
		{"ok": false, "projection": null, "error": 7},
		{"ok": false, "projection": null, "error": null},
		{"ok": false, "projection": null, "error": "failed", "extra": 1},
	]
	return _all_boundary_fail(invalid)


func _all_boundary_fail(outcomes: Array) -> bool:
	for outcome in outcomes:
		if not outcome is Dictionary:
			return false
		var result := _project(outcome)
		if not _is_boundary_failure(result):
			return false
	return true


func _mutation_isolation_holds() -> bool:
	return _known_witness_mutation_isolated() and _unknown_nested_mutation_isolated()


func _known_witness_mutation_isolated() -> bool:
	var parser_outcome := _parse(ROOM_STATE_SOURCE)
	var baseline := _parse(ROOM_STATE_SOURCE)
	var projected := _project(parser_outcome)
	if not _is_boundary_success(projected):
		return false
	var room: Variant = projected.get("room_state")
	if not room is Dictionary:
		return false
	var objects: Variant = room.get("objects")
	if not objects is Dictionary:
		return false
	var apple: Variant = objects.get("apple_01")
	var chest: Variant = objects.get("chest_01")
	if not apple is Dictionary or not chest is Dictionary:
		return false
	var loot: Variant = chest.get("remaining_loot")
	if not loot is Dictionary:
		return false
	room["room_id"] = "mutated_room"
	apple["collected"] = false
	loot["rope"] = 99
	return _parser_outcome_unchanged(parser_outcome, baseline, ROOM_STATE_SOURCE)


func _unknown_nested_mutation_isolated() -> bool:
	var parser_outcome := _parse(UNKNOWN_SOURCE)
	var baseline := _parse(UNKNOWN_SOURCE)
	var projected := _project(parser_outcome)
	if not _is_boundary_success(projected):
		return false
	var room: Variant = projected.get("room_state")
	if not room is Dictionary:
		return false
	var climate: Variant = room.get("climate")
	var objects: Variant = room.get("objects")
	if not climate is Dictionary or not objects is Dictionary:
		return false
	var relic: Variant = objects.get("relic_77")
	if not relic is Dictionary:
		return false
	var future: Variant = relic.get("%future")
	if not future is Dictionary:
		return false
	var opaque: Variant = future.get("opaque")
	if not opaque is Array or opaque.size() != 2:
		return false
	var nested: Variant = opaque[1]
	if not nested is Dictionary:
		return false
	var child: Variant = nested.get("child")
	if not child is Dictionary:
		return false
	climate["season"] = "mutated_season"
	opaque[0] = "MUTATED"
	opaque.append("ADDED")
	child["deep"] = false
	future["new_unknown"] = {"nested": [1, 2, 3]}
	return _parser_outcome_unchanged(parser_outcome, baseline, UNKNOWN_SOURCE)


func _parser_outcome_unchanged(outcome: Dictionary, baseline: Dictionary, source: String) -> bool:
	var fresh := _parse(source)
	return outcome == baseline \
		and fresh == baseline \
		and _key_order_signature(outcome) == _key_order_signature(baseline) \
		and _key_order_signature(fresh) == _key_order_signature(baseline)


func _determinism_holds() -> bool:
	var first := _project(_room_parse)
	var second := _project(_room_parse)
	if not _is_boundary_success(first) or not _exact_variant_equal(first, second):
		return false
	if not _object_key_order_is_exact(first):
		return false
	var nonlexical := _project(_nonlexical_order_parse)
	if not _is_boundary_success(nonlexical) \
		or not _exact_variant_equal(nonlexical, EXPECTED_NONLEXICAL_ORDER_OUTCOME):
		return false
	if _key_order_signature(first) != _key_order_signature(second):
		return false
	var first_invalid := _project(_missing_room_id_parse)
	var second_invalid := _project(_missing_room_id_parse)
	if not _is_boundary_failure(first_invalid) or not _exact_variant_equal(first_invalid, second_invalid):
		return false
	var first_upstream := _project(_malformed_parse)
	var second_upstream := _project(_malformed_parse)
	return _is_boundary_failure(first_upstream) \
		and _exact_variant_equal(first_upstream, second_upstream) \
		and first_upstream.get("error") == _malformed_parse.get("error")


func _parse(source_text: String) -> Dictionary:
	if _parser == null:
		return {}
	var outcome: Variant = _parser.call("parse", source_text)
	if not outcome is Dictionary:
		return {}
	return outcome


func _project(parse_outcome: Dictionary) -> Dictionary:
	if _subject_script == null:
		return {}
	var carrier: Object = _subject_script.new()
	if carrier == null or not carrier.has_method("project_room_state"):
		return {}
	var outcome: Variant = carrier.call("project_room_state", parse_outcome)
	if not outcome is Dictionary:
		return {}
	return outcome


func _is_parser_success(outcome: Dictionary) -> bool:
	return _has_exact_keys(outcome, ["error", "ok", "projection"]) \
		and outcome.get("ok") is bool \
		and outcome.get("ok") == true \
		and outcome.get("projection") is Dictionary \
		and outcome.get("error") == null


func _is_parser_failure(outcome: Dictionary) -> bool:
	return _has_exact_keys(outcome, ["error", "ok", "projection"]) \
		and outcome.get("ok") is bool \
		and outcome.get("ok") == false \
		and outcome.get("projection") == null \
		and outcome.get("error") is String \
		and not String(outcome.get("error")).strip_edges().is_empty()


func _is_boundary_success(outcome: Dictionary) -> bool:
	return _has_exact_keys(outcome, ["error", "ok", "room_state"]) \
		and outcome.get("ok") is bool \
		and outcome.get("ok") == true \
		and outcome.get("room_state") is Dictionary \
		and outcome.get("error") == null


func _is_boundary_failure(outcome: Dictionary) -> bool:
	return _has_exact_keys(outcome, ["error", "ok", "room_state"]) \
		and outcome.get("ok") is bool \
		and outcome.get("ok") == false \
		and outcome.get("room_state") == null \
		and outcome.get("error") is String \
		and not String(outcome.get("error")).strip_edges().is_empty()


func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	var actual: Array = value.keys()
	actual.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	return actual == sorted_expected


func _room_value(outcome: Dictionary, key: String) -> Variant:
	if not _is_boundary_success(outcome):
		return null
	var room: Variant = outcome.get("room_state")
	return room.get(key) if room is Dictionary else null


func _object_value(outcome: Dictionary, semantic_id: String) -> Variant:
	var objects: Variant = _room_value(outcome, "objects")
	return objects.get(semantic_id) if objects is Dictionary else null


func _has_exact_remaining_loot(chest: Variant) -> bool:
	if not chest is Dictionary:
		return false
	var loot: Variant = chest.get("remaining_loot")
	return loot is Dictionary \
		and _exact_variant_equal(loot, {"health_potion": 1, "rope": 1}) \
		and typeof(loot.get("health_potion")) == TYPE_INT \
		and typeof(loot.get("rope")) == TYPE_INT \
		and loot.keys() == ["health_potion", "rope"] \
		and not chest.has("health_potion") \
		and not chest.has("rope")


func _object_key_order_is_exact(outcome: Dictionary) -> bool:
	var objects: Variant = _room_value(outcome, "objects")
	return objects is Dictionary and objects.keys() == ["apple_01", "chest_01"]


func _exact_variant_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		var left_keys: Array = left.keys()
		var right_keys: Array = right.keys()
		if left_keys != right_keys:
			return false
		for key in left_keys:
			if not _exact_variant_equal(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _exact_variant_equal(left[index], right[index]):
				return false
		return true
	return left == right


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


func _sha256_file(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(bytes)
	return hash_context.finish().hex_encode()


func _check(label: String, passed: bool, detail := "") -> void:
	if passed:
		_pass += 1
		print("PASS: %s" % label)
	else:
		_fail += 1
		print("FAIL: %s" % label)
		if not detail.is_empty():
			print("      %s" % detail)


func _print_report() -> void:
	print("=== DREAM ZW ROOM-STATE ADAPTER RED REPORT ===")
	print("PASS: %d" % _pass)
	print("FAIL: %d" % _fail)
	if _fail > 0:
		print("SLICE: RED")
		print("EXPECTED STOP: room-state boundary GREEN is not authorized")
	else:
		print("SLICE: GREEN")
