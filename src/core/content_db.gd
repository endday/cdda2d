class_name ContentDB
extends RefCounted
## 内容校验：加载后的 JSON 过一遍，坏数据要响，不静默兜底。
##
## 对照 CDDA：它们结构错误直接退出、语义问题只弹窗警告（src/init.cpp:954、
## main_menu.cpp:535）。我们只有一个内容包 + 测试驱动，所以两种都当错误报，
## 由测试和启动日志接住。见 docs/cdda-notes.md §5。
##
## 这里不碰文件——只管已经解析好的 Array/Dictionary，方便单测。

const ITEM_KINDS := ["food", "water", "med", "weapon", "tool", "component", "ammo", "armor"]
const ITEM_NUMERIC := ["weight", "damage", "heal", "cure", "nutrition", "hydration", "armor"]


static func index_by_id(entries: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY and entry.has("id"):
			out[String(entry["id"])] = entry
	return out


static func validate_items(entries: Array) -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	if entries.is_empty():
		problems.append("items：一个都没有")
	for i: int in entries.size():
		var entry: Variant = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("items[%d] 不是对象" % i)
			continue
		var item: Dictionary = entry
		var item_id := String(item.get("id", ""))
		if item_id.is_empty():
			problems.append("items[%d] 缺 id" % i)
			continue
		if seen.has(item_id):
			problems.append("items：id 重复 %s" % item_id)
		seen[item_id] = true
		if String(item.get("name", "")).is_empty():
			problems.append("items[%s] 缺 name" % item_id)
		var kind := String(item.get("kind", ""))
		if kind.is_empty():
			problems.append("items[%s] 缺 kind" % item_id)
		elif not ITEM_KINDS.has(kind):
			problems.append("items[%s] 的 kind 不认识：%s" % [item_id, kind])
		for field: String in ITEM_NUMERIC:
			if item.has(field) and float(item[field]) < 0.0:
				problems.append("items[%s] 的 %s 不能是负数" % [item_id, field])
		if item.has("size"):
			var size: Variant = item["size"]
			if typeof(size) != TYPE_ARRAY or (size as Array).size() != 2:
				problems.append("items[%s] 的 size 应该是 [宽, 高]" % item_id)
			elif int(size[0]) <= 0 or int(size[1]) <= 0:
				problems.append("items[%s] 的 size 必须是正数" % item_id)
	return problems


static func validate_monsters(entries: Array) -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	if entries.is_empty():
		problems.append("monsters：一个都没有")
	for i: int in entries.size():
		var entry: Variant = entries[i]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("monsters[%d] 不是对象" % i)
			continue
		var monster: Dictionary = entry
		var monster_id := String(monster.get("id", ""))
		if monster_id.is_empty():
			problems.append("monsters[%d] 缺 id" % i)
			continue
		if seen.has(monster_id):
			problems.append("monsters：id 重复 %s" % monster_id)
		seen[monster_id] = true
		if String(monster.get("name", "")).is_empty():
			problems.append("monsters[%s] 缺 name" % monster_id)
		if int(monster.get("hp", 0)) <= 0:
			problems.append("monsters[%s] 的 hp 必须 > 0" % monster_id)
		if int(monster.get("speed", 0)) <= 0:
			problems.append("monsters[%s] 的 speed 必须 > 0" % monster_id)
		if int(monster.get("damage", 0)) < 0:
			problems.append("monsters[%s] 的 damage 不能是负数" % monster_id)
		if int(monster.get("sight", 0)) <= 0:
			problems.append("monsters[%s] 的 sight 必须 > 0" % monster_id)
	return problems


## 生成表引用的 id 必须都存在——CDDA 的 check_consistency 里最常抓的就是这种。
static func validate_references(entries: Array, known: Dictionary, where: String) -> Array[String]:
	var problems: Array[String] = []
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item_id := String((entry as Dictionary).get("id", ""))
		if not known.has(item_id):
			problems.append("%s 里引用了不存在的 id：%s" % [where, item_id])
	return problems
