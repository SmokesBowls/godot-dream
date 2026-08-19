extends RefCounted

# Minimal ZW-S v1.0 lexical and structural parser.
# Domain validation and downstream runtime integration are intentionally absent.

var _source := ""
var _index := 0
var _length := 0
var _error := ""


func parse(source_text: String) -> Dictionary:
	_source = source_text
	_index = 0
	_length = _source.length()
	_error = ""

	var projection := _parse_file()
	if not _error.is_empty():
		return {
			"ok": false,
			"projection": null,
			"error": _error,
		}
	return {
		"ok": true,
		"projection": projection,
		"error": null,
	}


func _parse_file() -> Dictionary:
	var projection := {}
	_skip_ignored()
	while _index < _length:
		if _peek() != "{":
			_fail("expected a top-level block")
			return {}
		var pair := _parse_block_pair()
		if not _error.is_empty():
			return {}
		var key: String = pair["key"]
		if projection.has(key):
			_fail("duplicate top-level key '%s' has no frozen projection rule" % key)
			return {}
		projection[key] = pair["value"]
		_skip_ignored()
	return projection


func _parse_block_pair() -> Dictionary:
	if not _consume("{"):
		_fail("expected '{'")
		return {}
	_skip_ignored()

	var key := _read_bare_token()
	if not _is_key(key):
		_fail("invalid block key '%s'" % key)
		return {}

	var elements: Array[Dictionary] = []
	while _error.is_empty():
		_skip_ignored()
		if _index >= _length:
			_fail("unclosed block '%s'" % key)
			return {}
		var character := _peek()
		if character == "}":
			_index += 1
			break
		if character == "{":
			var child := _parse_block_pair()
			if not _error.is_empty():
				return {}
			elements.append({"kind": "block", "key": child["key"], "value": child["value"]})
		elif character == "[":
			var list_value := _parse_list()
			if not _error.is_empty():
				return {}
			elements.append({"kind": "value", "value": list_value})
		elif character == "\"":
			var string_value := _parse_string()
			if not _error.is_empty():
				return {}
			elements.append({"kind": "value", "value": string_value})
		elif character == "]":
			_fail("unexpected ']'")
			return {}
		else:
			var scalar: Variant = _parse_bare_scalar()
			if not _error.is_empty():
				return {}
			elements.append({"kind": "value", "value": scalar})

	return _finish_block(key, elements)


func _finish_block(key: String, elements: Array[Dictionary]) -> Dictionary:
	if elements.is_empty():
		return {"key": key, "value": {}}

	var all_fields := true
	for element in elements:
		if element["kind"] != "block":
			all_fields = false
			break

	if all_fields:
		var object_value := {}
		for element in elements:
			var field_key: String = element["key"]
			if object_value.has(field_key):
				_fail("duplicate field key '%s' has no frozen projection rule" % field_key)
				return {}
			object_value[field_key] = element["value"]
		return {"key": key, "value": object_value}

	if elements.size() == 1 and elements[0]["kind"] == "value":
		return {"key": key, "value": elements[0]["value"]}

	_fail("block '%s' mixes fields or contains multiple direct values" % key)
	return {}


func _parse_list() -> Array:
	if not _consume("["):
		_fail("expected '['")
		return []
	var values := []
	while _error.is_empty():
		_skip_ignored()
		if _index >= _length:
			_fail("unclosed list")
			return []
		var character := _peek()
		if character == "]":
			_index += 1
			return values
		if character == "}":
			_fail("unexpected '}' inside list")
			return []
		if character == "{":
			var pair := _parse_block_pair()
			if not _error.is_empty():
				return []
			values.append({pair["key"]: pair["value"]})
		elif character == "[":
			values.append(_parse_list())
		elif character == "\"":
			values.append(_parse_string())
		else:
			values.append(_parse_bare_scalar())
		if not _error.is_empty():
			return []
	return []


func _parse_string() -> String:
	if not _consume("\""):
		_fail("expected string")
		return ""
	var value := ""
	while _index < _length:
		var character := _peek()
		_index += 1
		if character == "\"":
			return value
		if character == "\\":
			if _index >= _length:
				_fail("unterminated string escape")
				return ""
			var escaped := _peek()
			_index += 1
			if escaped != "\"" and escaped != "\\":
				_fail("unsupported string escape '\\%s'" % escaped)
				return ""
			value += escaped
		else:
			value += character
	_fail("unterminated string")
	return ""


func _parse_bare_scalar() -> Variant:
	var token := _read_bare_token()
	if token.is_empty():
		_fail("expected a scalar value")
		return null
	if token == "true":
		return true
	if token == "false":
		return false
	if token.is_valid_int() and not token.contains("."):
		return token.to_int()
	if token.contains(".") and token.is_valid_float():
		return token.to_float()
	if _is_identifier(token):
		return token
	_fail("invalid scalar token '%s'" % token)
	return null


func _read_bare_token() -> String:
	var start := _index
	while _index < _length:
		var character := _peek()
		if _is_whitespace(character) or character in ["{", "}", "[", "]", "\"", ";"]:
			break
		_index += 1
	return _source.substr(start, _index - start)


func _skip_ignored() -> void:
	while _index < _length:
		var character := _peek()
		if _is_whitespace(character):
			_index += 1
			continue
		if character == ";":
			while _index < _length and _peek() != "\n":
				_index += 1
			continue
		return


func _is_key(token: String) -> bool:
	if token.begins_with("%"):
		return token.length() > 1 and _is_identifier(token.substr(1))
	return _is_identifier(token)


func _is_identifier(token: String) -> bool:
	if token.is_empty() or not _is_identifier_start(token[0]):
		return false
	for index in range(1, token.length()):
		if not _is_identifier_continue(token[index]):
			return false
	return true


func _is_identifier_start(character: String) -> bool:
	var code := character.unicode_at(0)
	return character == "_" or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)


func _is_identifier_continue(character: String) -> bool:
	var code := character.unicode_at(0)
	return _is_identifier_start(character) or (code >= 48 and code <= 57) or character == "." or character == "-"


func _is_whitespace(character: String) -> bool:
	return character == " " or character == "\t" or character == "\r" or character == "\n"


func _peek() -> String:
	return _source[_index]


func _consume(expected: String) -> bool:
	if _index >= _length or _source[_index] != expected:
		return false
	_index += 1
	return true


func _fail(message: String) -> void:
	if _error.is_empty():
		_error = "%s at offset %d" % [message, _index]
