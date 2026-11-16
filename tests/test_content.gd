extends RefCounted
## 内容校验 + 物品引擎的测试：出货 JSON 必须干净，坏数据必须被抓出来，
## 新物品/新动词必须能只靠数据/注册接进来。

const MAX_REPORTED_FAILURES := 20

var _failures: Array[String] = []
var _checks: int = 0


func suite_title() -> String:
	return "Content"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0

	test_items_are_valid()
	test_monsters_are_valid()
	test_bad_item_is_reported()
	test_bad_monster_is_reported()
	test_data_only_item_works()
	test_custom_verb_can_be_registered()

	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _load(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func test_items_are_valid() -> void:
	var problems := ContentDB.validate_items(_load("res://content/items.json"))
	_expect(problems.is_empty(), "items.json 应该没有校验问题：%s" % ", ".join(problems))
	var items := ContentDB.index_by_id(_load("res://content/items.json"))
	_expect(items.size() >= 20, "至少应该有 20 件物品，实际 %d" % items.size())
	var spawn_problems := ContentDB.validate_references(World.SPAWN_ITEMS, items, "地面物品")
	_expect(spawn_problems.is_empty(), "地面物品都该在 items.json 里：%s" % ", ".join(spawn_problems))


func test_monsters_are_valid() -> void:
	var problems := ContentDB.validate_monsters(_load("res://content/monsters.json"))
	_expect(problems.is_empty(), "monsters.json 应该没有校验问题：%s" % ", ".join(problems))
	var monsters := ContentDB.index_by_id(_load("res://content/monsters.json"))
	_expect(monsters.size() >= 1, "至少要有一种怪")
	for spawn: Dictionary in World.MONSTER_SPAWNS:
		_expect(monsters.has(String(spawn["type"])),
			"出生点引用了不存在的怪：%s" % spawn["type"])


func test_bad_item_is_reported() -> void:
	var bad := [
		{"id": "ghost", "name": "幽灵", "use_methods": [{"type": "magic"}]},
		{"name": "没 id"},
		{"id": "ghost", "name": "重名"},
		{"id": "heavy", "name": "负重量", "weight": -5},
		{"id": "no_verb", "name": "没 type", "use_methods": [{"heal": 1}]},
	]
	var problems := ContentDB.validate_items(bad)
	_expect(not problems.is_empty(), "坏物品应该被报出来")
	_expect(_has(problems, "未注册的动词"), "应该抓出没注册的 use_methods：%s" % ", ".join(problems))
	_expect(_has(problems, "缺 id"), "应该抓出缺 id")
	_expect(_has(problems, "id 重复"), "应该抓出重复 id")
	_expect(_has(problems, "负数"), "应该抓出负数")
	_expect(_has(problems, "缺 type"), "应该抓出 use_methods 缺 type")


func test_bad_monster_is_reported() -> void:
	var bad := [
		{"id": "weak", "name": "弱鸡", "hp": 0, "speed": 100, "damage": 1, "sight": 8},
		{"id": "slow", "name": "蜗牛", "hp": 10, "speed": 0, "damage": 1, "sight": 8},
		{"id": "blind", "name": "瞎子", "hp": 10, "speed": 100, "damage": 1},
	]
	var problems := ContentDB.validate_monsters(bad)
	_expect(_has(problems, "hp"), "应该抓出 hp <= 0")
	_expect(_has(problems, "speed"), "应该抓出 speed <= 0")
	_expect(_has(problems, "sight"), "应该抓出缺 sight")


## 「无痛接入」的第一半：加一件物品只写数据。
func test_data_only_item_works() -> void:
	var db := {
		"cola": {"id": "cola", "name": "可乐", "weight": 0.4,
			"use_methods": [{"type": "consume", "quench": 20, "msg": "可乐"}]},
	}
	_expect(ContentDB.validate_items([db["cola"]]).is_empty(), "只写了数据的新物品应该通过校验")
	var world := World.new(db, {}, 7)
	world.player.take_item(Item.new("cola"))
	world.player.thirst = 10
	_expect(world.player_use(world.player.find_item("cola")), "数据里加的物品应该能直接用")
	_expect(world.player.thirst == 30, "可乐应该回 20 口渴，实际 %d" % world.player.thirst)
	_expect(not world.player.has_item("cola"), "消耗类物品应该被用掉")


## 「无痛接入」的第二半：加一种新玩法只需要注册一个动词。
func test_custom_verb_can_be_registered() -> void:
	ItemUse.register("shout",
		func(_actor: Actor, _world: Variant, _item: Item, _method: Dictionary) -> String:
			return "",
		func(_actor: Actor, _world: Variant, _item: Item, _method: Dictionary) -> Dictionary:
			return {"ok": true, "message": "你喊了一声。", "consume": false, "replace": ""})
	var megaphone := {"id": "megaphone", "name": "喇叭",
		"use_methods": [{"type": "shout"}]}
	_expect(ContentDB.validate_items([megaphone]).is_empty(), "注册过的动词应该通过校验")
	var world := World.new({"megaphone": megaphone}, {}, 7)
	world.player.take_item(Item.new("megaphone"))
	_expect(world.player_use(world.player.find_item("megaphone")), "自定义动词应该能跑")
	_expect(world.player.has_item("megaphone"), "不消耗的物品用完应该还在")
	# 注册表是全局的，测完清掉，别把 lambda 留到进程退出。
	ItemUse.reset()


func _has(problems: Array[String], needle: String) -> bool:
	for problem: String in problems:
		if problem.contains(needle):
			return true
	return false
