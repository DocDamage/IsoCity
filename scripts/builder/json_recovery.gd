extends RefCounted

# Best-effort parsing is only used after native JSON parsing fails. Preserve
# recognizable values around bad tokens; the complete source is archived by
# ProjectRepair, and the resulting document must still pass schema validation.
var source: String
var position: int = 0
var token: String = ""
var value: Variant

func recover(text: String) -> Variant:
	source = text
	position = 0
	advance()
	while token not in ["{","end"]: advance()
	var parsed: Dictionary = parse_value(0)
	return parsed.get("value") if parsed.get("ok",false) else null

func advance() -> void:
	while position < source.length() and source.substr(position,1) in [" ","\t","\r","\n"]: position += 1
	if position >= source.length(): token = "end"; value = null; return
	var c: String = source.substr(position,1)
	position += 1
	if c in ["{","}","[","]",":",","]: token = c; value = null; return
	var start: int = position-1
	if c == '"':
		var escaped: bool = false
		while position < source.length():
			var next: String = source.substr(position,1)
			position += 1
			if escaped: escaped = false
			elif next == "\\": escaped = true
			elif next == '"':
				var parser := JSON.new()
				if parser.parse(source.substr(start,position-start)) == OK:
					token = "string"; value = parser.data; return
				break
		token = "bad"; value = source.substr(start,position-start); return
	while position < source.length() and not source.substr(position,1) in [" ","\t","\r","\n","{","}","[","]",":",","]: position += 1
	var word: String = source.substr(start,position-start)
	if word == "true": token = "scalar"; value = true
	elif word == "false": token = "scalar"; value = false
	elif word == "null": token = "scalar"; value = null
	elif word.is_valid_float() and is_finite(float(word)): token = "scalar"; value = float(word)
	else: token = "bad"; value = word

func parse_value(depth: int) -> Dictionary:
	if depth > 64:
		skip_value()
		return {"ok":false}
	if token in ["string","scalar"]:
		var parsed: Variant = value
		advance()
		return {"ok":true,"value":parsed}
	if token == "{": return parse_object(depth+1)
	if token == "[": return parse_array(depth+1)
	if token not in ["end","}","]"]: advance()
	return {"ok":false}

func parse_object(depth: int) -> Dictionary:
	var result: Dictionary = {}
	advance()
	while token not in ["end","}","]"]:
		if token == ",": advance(); continue
		if token not in ["string","bad"]: skip_value(); continue
		var key: String = str(value)
		advance()
		if token != ":": continue
		advance()
		var parsed: Dictionary = parse_value(depth)
		if parsed.get("ok",false): result[key] = parsed["value"]
		if token == ",": advance()
	if token == "}": advance()
	return {"ok":true,"value":result}

func parse_array(depth: int) -> Dictionary:
	var result: Array = []
	advance()
	while token not in ["end","]","}"]:
		if token == ",": advance(); continue
		var parsed: Dictionary = parse_value(depth)
		if parsed.get("ok",false): result.append(parsed["value"])
		else:
			# Keep the damaged slot so paths and generated IDs remain stable.
			result.append(null)
			while token not in ["end",",","]","}","{","["]: advance()
		if token == ",": advance()
	if token == "]": advance()
	return {"ok":true,"value":result}

func skip_value() -> void:
	if token not in ["{","["]: advance(); return
	var stack: Array[String] = ["}" if token == "{" else "]"]
	advance()
	while not stack.is_empty() and token != "end":
		if token in ["{","["]: stack.append("}" if token == "{" else "]")
		elif token == stack.back(): stack.pop_back()
		advance()
