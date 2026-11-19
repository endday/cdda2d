extends RefCounted
## 装备、体力、负重和物品动作菜单的规则测试。

const MAX_REPORTED_FAILURES := 20

var _failures: Array[String] = []
var _checks := 0


func suite_title() -> String:
	return "Items"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0
	test_stamina_and_running()
	test_capacity_rejects_pickup()
	test_equipment_does_not_use_pack_volume()
	test_backpack_expands_capacity()
	test_legacy_capacity_is_upgraded()
	test_item_actions_are_explicit()
	test_equipment_slots_are_distinct()
	test_equipment_replaces_same_slot()
	test_offhand_is_usable_and_persistent()
	test_equipment_save_roundtrip()
	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _db() -> Dictionary:
	return {
		"knife": {"id": "knife", "name": "小刀", "weight": 1.0, "volume": 100,
			"melee": {"damage": 6}, "disassemble": [{"id": "scrap", "count": 1}]},
		"armor": {"id": "armor", "name": "护甲", "weight": 2.0, "volume": 500, "armor": 3,
			"flags": ["ARMOR"], "wear_slot": "body"},
		"helmet": {"id": "helmet", "name": "头盔", "weight": 0.5, "volume": 300,
			"armor": 1, "wear_slot": "head", "flags": ["WEARABLE"]},
		"backpack": {"id": "backpack", "name": "背包", "weight": 1.0, "volume": 3000,
			"capacity_volume": 20000, "wear_slot": "backpack", "flags": ["CONTAINER"]},
		"flashlight": {"id": "flashlight", "name": "手电筒", "weight": 0.3, "volume": 300,
			"flags": ["OFF_HAND"]},
		"vest": {"id": "vest", "name": "背心", "weight": 1.0, "volume": 900, "armor": 2,
			"flags": ["ARMOR"], "wear_slot": "body"},
		"water": {"id": "water", "name": "水", "weight": 0.5, "volume": 500,
			"use_methods": [{"type": "consume", "quench": 40}]},
		"scrap": {"id": "scrap", "name": "碎料", "weight": 0.1, "volume": 50},
		"heavy": {"id": "heavy", "name": "重物", "weight": 25.0, "volume": 100},
	}


func test_stamina_and_running() -> void:
	var world := World.new(_db(), {}, 17)
	world.player.pos = Vector2i(24, 13)
	world.player.moves = 100
	_expect(world.player_move(1, 0), "走路应该成功")
	_expect(world.player.stamina == 999, "走路应该消耗 1 点体力")
	world.player.moves = 100
	_expect(world.player_toggle_run(), "体力充足时应该能切跑步")
	_expect(world.player_move(1, 0), "跑步应该成功")
	_expect(world.player.moves == 50, "跑步每格应该花 50 moves")
	_expect(world.player.stamina == 994, "跑步应该消耗 5 点体力")
	world.player.stamina = Actor.MIN_RUN_STAMINA - 1
	world.player.moves = 100
	_expect(not world.player_move(1, 0), "体力低时不应该继续跑")
	world.player.run_mode = false
	world.advance_turn()
	_expect(world.player.stamina > Actor.MIN_RUN_STAMINA - 1, "回合推进应该恢复体力")


func test_capacity_rejects_pickup() -> void:
	var world := World.new(_db(), {}, 18)
	world.items = [{"id": "heavy", "pos": world.player.pos}]
	var taken := world.take_items_at(world.player)
	_expect(taken.is_empty(), "超重物品不应该被捡起")
	_expect(world.items.size() == 1, "被拒绝的物品应该留在地上")
	_expect(world.log_lines.back().contains("太重"), "超重时应该写明原因")


func test_equipment_does_not_use_pack_volume() -> void:
	var world := World.new(_db(), {}, 23)
	world.player.capacity_volume = 500
	var armor := Item.new("armor")
	world.player.take_item(armor)
	_expect(world.player.wear_item(armor, world.item_db), "护甲应该能穿上")
	_expect(world.player.total_volume(world.item_db) == 0, "穿戴护甲不应该占背包容积")
	_expect(world.player.total_weight(world.item_db) == 2.0, "穿戴护甲仍然应该计入负重")
	var knife := Item.new("knife")
	world.player.take_item(knife)
	_expect(world.player.wield_item(knife), "小刀应该能拿在主手")
	_expect(world.player.total_volume(world.item_db) == 0, "手持物不应该占背包容积")
	_expect(world.player.carry_error(Item.new("water"), world.item_db).is_empty(),
		"腾出穿戴和手持物的容积后应该能装入水")


func test_backpack_expands_capacity() -> void:
	var world := World.new(_db(), {}, 24)
	var bag := Item.new("backpack")
	world.player.take_item(bag)
	_expect(world.player.wear_item(bag, world.item_db), "背包应该能装备")
	_expect(world.player.max_volume(world.item_db) == Actor.BASE_CAPACITY_VOLUME + 20000,
		"装备背包应该增加 20L 容积")
	_expect(world.player.total_volume(world.item_db) == 0, "穿着的背包不应该占用自身容量")


func test_legacy_capacity_is_upgraded() -> void:
	var actor := Actor.new()
	actor.from_dict({"capacity_volume": 2000, "inventory": []})
	_expect(actor.capacity_volume == Actor.BASE_CAPACITY_VOLUME,
		"旧存档的 2L 基础容量应该升级到新的口袋容量")


func test_item_actions_are_explicit() -> void:
	var world := World.new(_db(), {}, 19)
	var knife := Item.new("knife")
	world.player.take_item(knife)
	var options := ItemActions.available(knife, world.player, world)
	var ids: Array[String] = []
	for option: Dictionary in options:
		ids.append(String(option["id"]))
	_expect(ids.has("wield"), "小刀应该有手持动作")
	_expect(ids.has("disassemble"), "小刀应该有拆解动作")
	_expect(ids.has("drop"), "小刀应该有丢弃动作")
	var method := {"type": "consume", "quench": 40}
	var water := Item.new("water")
	world.player.take_item(water)
	world.player.thirst = 10
	_expect(world.player_use_method(water, method), "指定物品方法应该能执行")
	_expect(world.player.thirst == 50, "指定喝水动作应该恢复口渴")


func test_equipment_save_roundtrip() -> void:
	var world := World.new(_db(), {}, 20)
	var knife := Item.new("knife")
	var armor := Item.new("armor")
	world.player.take_item(knife)
	world.player.take_item(armor)
	world.player.wield_item(knife)
	world.player.wear_item(armor, world.item_db)
	world.player.stamina = 321
	world.player.run_mode = true
	var restored := World.new(_db(), {}, 21)
	_expect(restored.from_dict(world.to_dict()), "装备和体力存档应该能读回")
	_expect(restored.player.wielded != null and restored.player.wielded.type_id == "knife", "读档后应该保留手持物")
	_expect(restored.player.worn.size() == 1 and restored.player.worn[0].type_id == "armor", "读档后应该保留穿戴物")
	_expect(restored.player.stamina == 321 and restored.player.run_mode, "读档后应该保留体力和跑步模式")


func test_equipment_slots_are_distinct() -> void:
	var world := World.new(_db(), {}, 22)
	var armor := Item.new("armor")
	var helmet := Item.new("helmet")
	world.player.take_item(armor)
	world.player.take_item(helmet)
	_expect(world.player.wear_item(armor, world.item_db), "身体护甲应该能穿戴")
	_expect(world.player.wear_item(helmet, world.item_db), "头盔应该能穿戴到独立槽位")
	_expect(world.player.worn_in_slot("body", world.item_db) == armor, "身体槽应该显示护甲")
	_expect(world.player.worn_in_slot("head", world.item_db) == helmet, "头部槽应该显示头盔")
	_expect(Combat.armor_of(world.player, world.item_db) == 4, "多个部位的护甲应该累加")


func test_equipment_replaces_same_slot() -> void:
	var world := World.new(_db(), {}, 25)
	var armor := Item.new("armor")
	var vest := Item.new("vest")
	world.player.take_item(armor)
	world.player.take_item(vest)
	_expect(world.player.wear_item(armor, world.item_db), "初始护甲应该能穿戴")
	_expect(world.player.wear_item(vest, world.item_db), "换装时应替换同部位旧装备")
	_expect(world.player.worn.size() == 1 and world.player.worn[0] == vest,
		"同一装备位只应保留新装备")


func test_offhand_is_usable_and_persistent() -> void:
	var world := World.new(_db(), {}, 26)
	var flashlight := Item.new("flashlight")
	world.player.take_item(flashlight)
	_expect(world.player.can_hold_offhand(flashlight, world.item_db), "标记为 OFF_HAND 的工具应该能放入副手")
	var flashlight_options := ItemActions.available(flashlight, world.player, world)
	var flashlight_can_be_held := false
	for option: Dictionary in flashlight_options:
		flashlight_can_be_held = flashlight_can_be_held or String(option["id"]) == "hold_offhand"
	_expect(flashlight_can_be_held, "工具的动作菜单应该包含放入副手")
	var knife := Item.new("knife")
	world.player.take_item(knife)
	_expect(world.player.hold_offhand(knife, world.item_db), "近战武器应该能放入副手")
	_expect(world.player.offhand == knife, "副手槽应该引用所选物品")
	_expect(Combat.weapon_damage(world.player, world.item_db) == 6,
		"主手空置时，副手武器应该能用于攻击")
	var options := ItemActions.available(knife, world.player, world)
	var has_remove_offhand := false
	for option: Dictionary in options:
		has_remove_offhand = has_remove_offhand or String(option["id"]) == "unhold_offhand"
	_expect(has_remove_offhand, "副手物品应该提供腾出副手的动作")
	var restored := World.new(_db(), {}, 27)
	_expect(restored.from_dict(world.to_dict()), "副手装备应该能读档")
	_expect(restored.player.offhand != null and restored.player.offhand.type_id == "knife",
		"读档后应该保留副手物品")
