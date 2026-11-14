class_name Actor
extends RefCounted
## 一个能行动的东西。玩家和怪物是同一个类，区别只在数据和脑子。
##
## 对照 CDDA：`Creature` 持有 `moves` / `speed_base` / `speed_bonus`，
## 每回合 `process_turn()` 里 `moves += get_speed()`（src/creature.cpp:488-495）。
## 我们照这个来：速度不是“先攻”，是“一回合里有多少 moves”。

const BASE_SPEED := 100
const MAX_BANKED_MOVES := 200   # 攒不动的时候别无限攒，否则被堵住的怪会存一百步

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
var alive := true
var is_player := false
var faction := "player"      # player / monster
var monster_type := ""       # monsters.json 的 id；玩家为空
var can_open_doors := true
var damage := 2              # 天生攻击力；玩家靠手里的东西，怪物靠这个
var armor := 0               # 天生护甲
var sight := 8               # 视野半径（怪物追击用）
var brain: Dictionary = {}   # 怪物的 AI 记忆：target / dest / wander，不入存档
var inventory: Array[String] = []


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)
	if hp <= 0:
		alive = false


func heal(amount: int) -> void:
	hp = mini(hp_max, hp + amount)


## 世界推进一个回合：每个活着的角色拿到自己速度那么多的 moves。
func gain_turn_moves() -> void:
	moves = mini(moves + speed, MAX_BANKED_MOVES)


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
		"alive": alive,
		"faction": faction,
		"monster_type": monster_type,
		"damage": damage,
		"armor": armor,
		"inventory": inventory.duplicate(),
	}


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
	alive = bool(data.get("alive", true))
	faction = String(data.get("faction", "player"))
	monster_type = String(data.get("monster_type", ""))
	damage = int(data.get("damage", 2))
	armor = int(data.get("armor", 0))
	brain.clear()
	inventory.clear()
	for entry: Variant in data.get("inventory", []):
		inventory.append(String(entry))
