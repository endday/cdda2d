class_name ItemActions
extends RefCounted
## 物品动作菜单的数据层。界面只展示这里返回的可用动作。

static func available(item: Item, actor: Actor, world: Variant) -> Array:
	var out: Array = []
	if item == null or not actor.inventory.has(item):
		return out
	var prototype: Dictionary = item.prototype(world.item_db)
	for entry: Variant in prototype.get("use_methods", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var method: Dictionary = entry
		if ItemUse.can_use_method(actor, world, item, method) == "":
			out.append({"id": "use", "label": _method_label(method), "method": method.duplicate(true)})

	if actor.wielded == item:
		out.append({"id": "unwield", "label": "放回背包", "method": {}})
	elif actor.can_wield_main(item, world.item_db):
		out.append({"id": "wield", "label": "放入主手", "method": {}})

	if actor.offhand == item:
		out.append({"id": "unhold_offhand", "label": "腾出副手", "method": {}})
	elif actor.can_hold_offhand(item, world.item_db):
		out.append({"id": "hold_offhand", "label": "放入副手", "method": {}})

	var flags: Array = prototype.get("flags", [])
	var wearable := prototype.has("armor") or prototype.has("capacity_volume") or ("WEARABLE" in flags)
	if wearable:
		if actor.worn.has(item):
			out.append({"id": "unwear", "label": "脱下", "method": {}})
		elif actor.can_wear(item, world.item_db):
			var slot := actor.equipment_slot(prototype)
			var current := actor.worn_in_slot(slot, world.item_db)
			var label := "更换%s" % _slot_label(slot) if current != null else "穿戴"
			out.append({"id": "wear", "label": label, "method": {}})

	var disassemble: Variant = prototype.get("disassemble", [])
	if typeof(disassemble) == TYPE_ARRAY and not (disassemble as Array).is_empty():
		out.append({"id": "disassemble", "label": "拆解", "method": {}})
	out.append({"id": "drop", "label": "丢弃", "method": {}})
	return out


static func _slot_label(slot: String) -> String:
	match slot:
		"head":
			return "头部装备"
		"body":
			return "身体装备"
		"backpack":
			return "背包"
		"legs":
			return "腿部装备"
		"feet":
			return "脚部装备"
		_:
			return "装备"


static func _method_label(method: Dictionary) -> String:
	var type := String(method.get("type", "使用"))
	match type:
		"consume":
			if int(method.get("quench", 0)) > 0 and int(method.get("calories", 0)) > 0:
				return "吃喝"
			if int(method.get("quench", 0)) > 0:
				return "喝"
			return "吃"
		"heal":
			return "治疗"
		"transform":
			return "切换状态"
		_:
			return String(method.get("label", "使用"))
