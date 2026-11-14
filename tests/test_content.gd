extends RefCounted
## 内容校验的测试：出货的 JSON 必须干净，坏数据必须被抓出来。

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
	_expect(items.size() == 20, "应该有 20 件物品，实际 %d" % items.size())
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
		{"id": "ghost", "name": "幽灵", "kind": "magic"},
		{"name": "没 id"},
		{"id": "ghost", "name": "重名", "kind": "food", "nutrition": -5},
		{"id": "sized", "name": "尺寸错", "kind": "tool", "size": [1]},
	]
	var problems := ContentDB.validate_items(bad)
	_expect(not problems.is_empty(), "坏物品应该被报出来")
	_expect(_has(problems, "kind 不认识"), "应该抓出不认识的 kind：%s" % ", ".join(problems))
	_expect(_has(problems, "缺 id"), "应该抓出缺 id")
	_expect(_has(problems, "id 重复"), "应该抓出重复 id")
	_expect(_has(problems, "负数"), "应该抓出负数")
	_expect(_has(problems, "size"), "应该抓出 size 格式不对")


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


func _has(problems: Array[String], needle: String) -> bool:
	for problem: String in problems:
		if problem.contains(needle):
			return true
	return false
