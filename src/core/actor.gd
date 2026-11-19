class_name Actor
extends RefCounted
## 一个能行动的东西。玩家和怪物是同一个类，区别只在数据和脑子。
##
## 对照 CDDA：`Creature` 持有 `moves` / `speed_base` / `speed_bonus`，
## 每回合 `process_turn()` 里 `moves += get_speed()`（src/creature.cpp:488-495）。
## 我们照这个来：速度不是“先攻”，是“一回合里有多少 moves”。

const BASE_SPEED := 100
const MAX_BANKED_MOVES := 200   # 攒不动的时候别无限攒，否则被堵住的怪会存一百步
const MAX_STAMINA := 1000
const MIN_RUN_STAMINA := 100
const BASE_MAX_WEIGHT := 20.0
const BASE_CAPACITY_VOLUME := 2000

var id: String = ""
var name: String = ""
var pos := Vector2i.ZERO
var hp := 100
var hp_max := 100
var moves := 0
var speed := BASE_SPEED
var hunger := 100
var thirst := 100
var infection := 0
var stamina := MAX_STAMINA
var max_stamina := MAX_STAMINA
var run_mode := false
var stamina_used_this_turn := false
var max_weight: float = BASE_MAX_WEIGHT
var capacity_volume: int = BASE_CAPACITY_VOLUME
var alive := true
var is_player := false
var faction := "player"      # player / monster
var monster_type := ""       # monsters.json 的 id；玩家为空
var can_open_doors := true
var damage := 2              # 天生攻击力；玩家靠手里的东西，怪物靠这个
var armor := 0               # 天生护甲
var sight := 8               # 视野半径（怪物追击用）
var brain: Dictionary = {}   # 怪物的 AI 记忆：target / dest / wander，不入存档
var inventory: Array[Item] = []
var wielded: Item = null
var worn: Array[Item] = []


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	if hp <= 0:
		alive = false


func heal(amount: int) -> void:
	hp = mini(hp_max, hp + amount)


## 世界推进一个回合：每个活着的角色拿到自己速度那么多的 moves。
func gain_turn_moves(item_db: Dictionary = {}) -> void:
	moves = mini(moves + effective_speed(item_db), MAX_BANKED_MOVES)


func effective_speed(item_db: Dictionary = {}) -> int:
	if item_db.is_empty() or total_weight(item_db) <= max_weight:
		return speed
	return maxi(1, int(floor(float(speed) * 0.75)))


func burn_stamina(amount: int) -> void:
	stamina = maxi(0, stamina - maxi(0, amount))
	stamina_used_this_turn = true


func recover_stamina(amount: int) -> void:
	stamina = mini(max_stamina, stamina + maxi(0, amount))


func max_volume(item_db: Dictionary) -> int:
	var capacity := capacity_volume
	for item: Item in worn:
		capacity += int(item.prototype(item_db).get("capacity_volume", 0))
	return capacity


func total_weight(item_db: Dictionary) -> float:
	var total := 0.0
	for item: Item in inventory:
		total += float(item.prototype(item_db).get("weight", 0.0))
	return total


func total_volume(item_db: Dictionary) -> int:
	var total := 0
	for item: Item in inventory:
		total += int(item.prototype(item_db).get("volume", 0))
	return total


func carry_error(item: Item, item_db: Dictionary) -> String:
	var prototype := item.prototype(item_db)
	var next_weight := total_weight(item_db) + float(prototype.get("weight", 0.0))
	var next_volume := total_volume(item_db) + int(prototype.get("volume", 0))
	if next_weight > max_weight:
		return "%s 太重，还差 %.1f kg" % [String(prototype.get("name", item.type_id)), next_weight - max_weight]
	if next_volume > max_volume(item_db):
		return "%s 装不下，还差 %.1f L" % [String(prototype.get("name", item.type_id)), float(next_volume - max_volume(item_db)) / 1000.0]
	return ""


# ---- 背包是物品实例的列表，不是 id 字符串（CDDA 的 item 数组）

func take_item(item: Item) -> void:
	inventory.append(item)


func wield_item(item: Item) -> bool:
	if item == null or not inventory.has(item):
		return false
	wielded = item
	return true


func unwield_item() -> bool:
	if wielded == null:
		return false
	wielded = null
	return true


func wear_item(item: Item, item_db: Dictionary) -> bool:
	if item == null or not inventory.has(item) or worn.has(item):
		return false
	var prototype := item.prototype(item_db)
	var flags: Array = prototype.get("flags", [])
	if not prototype.has("armor") and not prototype.has("capacity_volume") and not ("WEARABLE" in flags):
		return false
	var slot := equipment_slot(prototype)
	for worn_item: Item in worn:
		if equipment_slot(worn_item.prototype(item_db)) == slot:
			return false
	worn.append(item)
	return true


func equipment_slot(prototype: Dictionary) -> String:
	var declared := String(prototype.get("wear_slot", ""))
	if not declared.is_empty():
		return declared
	if prototype.has("capacity_volume"):
		return "backpack"
	if prototype.has("armor") or "ARMOR" in Array(prototype.get("flags", [])):
		return "body"
	return ""


func worn_in_slot(slot: String, item_db: Dictionary) -> Item:
	for item: Item in worn:
		if equipment_slot(item.prototype(item_db)) == slot:
			return item
	return null


func remove_worn(item: Item) -> bool:
	var index := worn.find(item)
	if index < 0:
		return false
	worn.remove_at(index)
	return true


func find_item(type_id: String) -> Item:
	for item: Item in inventory:
		if item.type_id == type_id:
			return item
	return null


func has_item(type_id: String) -> bool:
	return find_item(type_id) != null


func remove_item(item: Item) -> bool:
	var index := inventory.find(item)
	if index < 0:
		return false
	if wielded == item:
		wielded = null
	remove_worn(item)
	inventory.remove_at(index)
	return true


## 按原型 id 拿掉一件（修电台这种消耗用）。
func consume_type(type_id: String) -> bool:
	var item := find_item(type_id)
	if item == null:
		return false
	return remove_item(item)


func item_count(type_id: String) -> int:
	var count := 0
	for item: Item in inventory:
		if item.type_id == type_id:
			count += 1
	return count


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"pos": [pos.x, pos.y],
		"hp": hp,
		"hp_max": hp_max,
		"moves": moves,
		"speed": speed,
		"hunger": hunger,
		"thirst": thirst,
		"infection": infection,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"run_mode": run_mode,
		"max_weight": max_weight,
		"capacity_volume": capacity_volume,
		"alive": alive,
		"faction": faction,
		"monster_type": monster_type,
		"damage": damage,
		"armor": armor,
		"inventory": _inventory_dict(),
		"wielded_index": inventory.find(wielded),
		"worn_indices": _worn_indices(),
	}


func _inventory_dict() -> Array:
	var out: Array = []
	for item: Item in inventory:
		out.append(item.to_dict())
	return out


func _worn_indices() -> Array[int]:
	var out: Array[int] = []
	for item: Item in worn:
		var index := inventory.find(item)
		if index >= 0:
			out.append(index)
	return out


func from_dict(data: Dictionary) -> void:
	id = String(data.get("id", "actor"))
	name = String(data.get("name", id))
	var p: Array = data.get("pos", [0, 0])
	pos = Vector2i(int(p[0]), int(p[1]))
	hp = int(data.get("hp", 100))
	hp_max = int(data.get("hp_max", 100))
	moves = int(data.get("moves", 0))
	speed = int(data.get("speed", BASE_SPEED))
	hunger = int(data.get("hunger", 100))
	thirst = int(data.get("thirst", 100))
	infection = int(data.get("infection", 0))
	max_stamina = int(data.get("max_stamina", MAX_STAMINA))
	stamina = clampi(int(data.get("stamina", max_stamina)), 0, max_stamina)
	run_mode = bool(data.get("run_mode", false))
	max_weight = float(data.get("max_weight", BASE_MAX_WEIGHT))
	capacity_volume = int(data.get("capacity_volume", BASE_CAPACITY_VOLUME))
	stamina_used_this_turn = false
	alive = bool(data.get("alive", true))
	faction = String(data.get("faction", "player"))
	monster_type = String(data.get("monster_type", ""))
	damage = int(data.get("damage", 2))
	armor = int(data.get("armor", 0))
	brain.clear()
	inventory.clear()
	for entry: Variant in data.get("inventory", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var item := Item.new()
		item.from_dict(entry)
		if not item.type_id.is_empty():
			inventory.append(item)
	wielded = null
	var wielded_index := int(data.get("wielded_index", -1))
	if wielded_index >= 0 and wielded_index < inventory.size():
		wielded = inventory[wielded_index]
	worn.clear()
	for entry: Variant in data.get("worn_indices", []):
		var index := int(entry)
		if index >= 0 and index < inventory.size():
			worn.append(inventory[index])
