class_name ContentDB
extends RefCounted
## 内容校验：加载后的 JSON 过一遍，坏数据要响，不静默兜底。
##
## 对照 CDDA：它们结构错误直接退出、语义问题只弹窗警告（src/init.cpp:954、
## main_menu.cpp:535）。我们只有一个内容包 + 测试驱动，所以两种都当错误报，
## 由测试和启动日志接住。见 docs/cdda-notes.md §5。
##
## 这里不碰文件——只管已经解析好的 Array/Dictionary，方便单测。

const ITEM_NUMERIC := ["weight", "volume", "armor", "capacity_volume"]
const WEAR_SLOTS := ["head", "body", "backpack", "arms", "hands", "legs", "feet"]


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
		for field: String in ITEM_NUMERIC:
			if item.has(field) and float(item[field]) < 0.0:
				problems.append("items[%s] 的 %s 不能是负数" % [item_id, field])
		if item.has("flags") and typeof(item["flags"]) != TYPE_ARRAY:
			problems.append("items[%s] 的 flags 应该是数组" % item_id)
		if item.has("wear_slot") and not (String(item["wear_slot"]) in WEAR_SLOTS):
			problems.append("items[%s] 的 wear_slot 不认识：%s" % [item_id, item["wear_slot"]])
		if item.has("disassemble"):
			problems.append_array(_validate_disassemble(item_id, item["disassemble"]))
		if item.has("melee"):
			if typeof(item["melee"]) != TYPE_DICTIONARY:
				problems.append("items[%s] 的 melee 应该是对象" % item_id)
			elif float((item["melee"] as Dictionary).get("damage", 0)) < 0.0:
				problems.append("items[%s] 的 melee.damage 不能是负数" % item_id)
		if item.has("ranged"):
			if typeof(item["ranged"]) != TYPE_DICTIONARY:
				problems.append("items[%s] 的 ranged 应该是对象" % item_id)
			else:
				var ranged: Dictionary = item["ranged"]
				if float(ranged.get("range", 0)) <= 0.0:
					problems.append("items[%s] 的 ranged.range 必须 > 0" % item_id)
				if float(ranged.get("damage", 0)) <= 0.0:
					problems.append("items[%s] 的 ranged.damage 必须 > 0" % item_id)
				if int(ranged.get("accuracy", 0)) < 1 or int(ranged.get("accuracy", 0)) > 100:
					problems.append("items[%s] 的 ranged.accuracy 必须在 1 到 100 之间" % item_id)
				if String(ranged.get("ammo", "")).is_empty():
					problems.append("items[%s] 的 ranged.ammo 不能为空" % item_id)
		problems.append_array(_validate_use_methods(item_id, item.get("use_methods", [])))
	return problems


static func _validate_disassemble(item_id: String, recipe: Variant) -> Array[String]:
	var problems: Array[String] = []
	if typeof(recipe) != TYPE_ARRAY:
		return ["items[%s] 的 disassemble 应该是数组" % item_id]
	for j: int in (recipe as Array).size():
		var entry: Variant = recipe[j]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("items[%s].disassemble[%d] 不是对象" % [item_id, j])
			continue
		var result: Dictionary = entry
		if String(result.get("id", "")).is_empty():
			problems.append("items[%s].disassemble[%d] 缺 id" % [item_id, j])
		if int(result.get("count", 1)) <= 0:
			problems.append("items[%s].disassemble[%d] 的 count 必须 > 0" % [item_id, j])
	return problems


## use_methods 里的 type 必须有人注册，否则这件物品在游戏里就是死的。
static func _validate_use_methods(item_id: String, methods: Variant) -> Array[String]:
	var problems: Array[String] = []
	if methods == null:
		return problems
	if typeof(methods) != TYPE_ARRAY:
		return ["items[%s] 的 use_methods 应该是数组" % item_id]
	for j: int in (methods as Array).size():
		var method: Variant = methods[j]
		if typeof(method) != TYPE_DICTIONARY:
			problems.append("items[%s].use_methods[%d] 不是对象" % [item_id, j])
			continue
		var type := String((method as Dictionary).get("type", ""))
		if type.is_empty():
			problems.append("items[%s].use_methods[%d] 缺 type" % [item_id, j])
		elif not ItemUse.has(type):
			problems.append("items[%s] 用了未注册的动词 %s（已注册：%s）"
				% [item_id, type, ", ".join(ItemUse.known_types())])
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


static func validate_disassemble_references(entries: Array, known: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = entry
		for result: Variant in item.get("disassemble", []):
			if typeof(result) != TYPE_DICTIONARY:
				continue
			var result_id := String((result as Dictionary).get("id", ""))
			if not result_id.is_empty() and not known.has(result_id):
				problems.append("物品 %s 的拆解产物不存在：%s" % [String(item.get("id", "")), result_id])
	return problems


static func validate_ranged_references(entries: Array, known: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = entry
		var ranged: Variant = item.get("ranged", {})
		if typeof(ranged) != TYPE_DICTIONARY:
			continue
		var ammo_id := String((ranged as Dictionary).get("ammo", ""))
		if not ammo_id.is_empty() and not known.has(ammo_id):
			problems.append("物品 %s 的枪械弹药不存在：%s" % [String(item.get("id", "")), ammo_id])
	return problems
