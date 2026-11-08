extends RefCounted

const LABELS = ["Objects", "Objects and scenery", "All content · sheets and references"]
const KINDS = ["object", "background", "showcase", "atlas", "reference"]

static func kind(asset: Dictionary) -> String:
	var value: Variant = asset.get("data", {}).get("content_kind", "object")
	return value if value is String and value in KINDS else "object"

static func visible(asset: Dictionary, scope: int, favorites_only: bool = false) -> bool:
	# A saved favorite remains directly accessible even when it is a legacy sheet.
	if favorites_only or scope == 2: return true
	return kind(asset) == "object" or scope == 1 and kind(asset) in ["background", "showcase"]
