class_name ItemDragButton
extends Button
## Button that drags an inventory item onto a compatible equipment slot.

signal item_dropped(item_index: int, target_slot: String)

var inventory_item_index := -1
var equipment_slot_id := ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if inventory_item_index < 0:
		return null
	var preview := Label.new()
	preview.text = text.get_slice("\n", 0).strip_edges()
	preview.add_theme_font_override("font", get_theme_font("font"))
	preview.add_theme_font_size_override("font_size", 12)
	preview.add_theme_color_override("font_color", Color("#e7f4ef"))
	set_drag_preview(preview)
	return {"type": "inventory_item", "index": inventory_item_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		equipment_slot_id != ""
		and equipment_slot_id != "quick"
		and typeof(data) == TYPE_DICTIONARY
		and String(data.get("type", "")) == "inventory_item"
	)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	item_dropped.emit(int(data["index"]), equipment_slot_id)
