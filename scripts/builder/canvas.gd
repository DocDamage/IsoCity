extends SubViewportContainer

signal asset_dropped(asset_id: String, at_position: Vector2)

func _ready() -> void:
	accessibility_name = "City canvas"

func _notification(what: int) -> void:
	if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
		# Expose the rendered city as a single image in the workspace's accessibility tree.
		AccessibilityServer.update_set_role(get_accessibility_element(), AccessibilityServer.ROLE_IMAGE)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == "builder_asset"

func _drop_data(at_position: Vector2, data: Variant) -> void:
	asset_dropped.emit(data["asset_id"], at_position)
