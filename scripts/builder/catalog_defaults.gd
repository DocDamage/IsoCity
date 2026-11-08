extends RefCounted

# Explicit reviewed defaults. Revision zero (including an absent field) keeps
# these formerly decorative placements decorative until the user opts in.
const PATH = "res://resources/catalog/functional_defaults.json"
const REVISION = 1
const FIELD = "catalog_behavior_revision"
static var assets: Dictionary = {}
static var loaded: bool = false

static func reviewed(asset: String) -> bool:
	if not loaded:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		assets = raw.get("assets", {}) if raw is Dictionary and raw.get("version") == 1 else {}
		loaded = true
	return assets.has(asset)

static func valid_revision(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == roundf(float(value)) and value >= 0 and value <= REVISION

static func enabled(item: Dictionary) -> bool:
	var revision: Variant = item.get(FIELD, 0)
	return valid_revision(revision) and int(revision) == REVISION

static func stamp(item: Dictionary) -> void:
	if reviewed(item.get("asset", "")): item[FIELD] = REVISION
