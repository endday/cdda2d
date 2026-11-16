class_name World
extends RefCounted
## CDDA-like 2D 回合制世界（灰盒）。
##
## 纯逻辑：不 import Godot 节点/场景，只用基础类型、Array、Dictionary。
##
## 时间模型照 CDDA：每个 Actor 有 `moves`，每回合 `moves += speed`，
## 动作花 moves，谁攒得多谁一回合里动得多（src/creature.cpp:488-495）。
## 玩家一直动到 moves 不够一个便宜动作为止，然后世界推进一回合、怪物行动——顺序同
## `game::do_turn()`（src/do_turn.cpp:536-800）。
##
## 地图是手写的 48×32 小镇：主街 + 三栋建筑 + 电台塔。门是数据：关着挡路，开了能过。

const W := 48
const H := 32
const FOV_RADIUS := 8
const MIN_COST := 50          # 最便宜的动作；玩家剩得比这还少就推进世界
const MONSTER_COST := 100     # 怪物一步/一爪的价格
const SAVE_VERSION := 5

## 电台目标：站到塔上、带齐三件东西、修 5 回合、然后守 10 回合。
const REPAIR_TURNS := 5
const DEFENSE_TURNS := 10
const DEFENSE_SPAWN_EVERY := 2
const REPAIR_PARTS := ["radio_part", "battery", "wire"]

var map: Array = []                  # 0=floor 1=wall 2=door
var doors_open: Dictionary = {}      # Vector2i -> true
var seen: Dictionary = {}            # Vector2i -> true
var visible: Dictionary = {}         # Vector2i -> true
var actors: Array[Actor] = []
var player: Actor
var items: Array[Dictionary] = []    # {id, pos}
var item_db: Dictionary = {}         # id -> data
var monster_db: Dictionary = {}      # id -> data
var turn := 1
var log_lines: Array[String] = []
var command_log: Array[Dictionary] = []   # 回放用；见 docs/cdda-notes.md §8
var rng := RandomNumberGenerator.new()    # 战斗/AI 用；种子跟着 run_seed
var run_seed := 0

## 目标状态。activity 是 CDDA 的 player_activity 的最简版：
## 一个跨回合推进、可被打断的「正在做的事」。
var repair_site := Vector2i(37, 24)
var activity: Dictionary = {}       # {id, turns_left, total}
var radio_fixed := false
var defense_left := 0
var won := false
var _defense_just_started := false   # 修好那一回合不扣守塔回合数

var _in_world_turn := false

const Actions := preload("res://src/core/actions.gd")

## 怪物的出生点。写死是为了测试稳定，正式版换成地图数据里的 spawn 表。
const MONSTER_SPAWNS := [
	{"type": "shambler", "pos": Vector2i(12, 13)},
	{"type": "shambler", "pos": Vector2i(33, 14)},
	{"type": "runner", "pos": Vector2i(38, 24)},
	{"type": "brute", "pos": Vector2i(40, 5)},
]

## 玩家死了没有。存档里由 hp 推出来，不单独存。
var dead: bool:
	get:
		return player != null and not player.alive


func _init(db: Dictionary = {}, monsters: Dictionary = {}, seed_value: int = 0) -> void:
	item_db = db
	monster_db = monsters
	rng = RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	run_seed = rng.seed
	_build_map()
	_spawn_items()
	player = Actor.new()
	player.id = "player"
	player.name = "你"
	player.is_player = true
	player.pos = Vector2i(24, 13)
	player.moves = Actor.BASE_SPEED
	actors.append(player)
	_spawn_monsters()
	_update_fov()
	_push_log("你在一座空镇里醒来。目标：修好电台，等救援。")


# ================================================================ 地图

func _build_map() -> void:
	map.clear()
	for y: int in H:
		var row := PackedInt32Array()
		row.resize(W)
		for x: int in W:
			row[x] = 1
		map.append(row)

	# 主街。
	_carve(Rect2i(1, 12, 46, 4))
	# 三栋建筑。
	_carve(Rect2i(2, 1, 14, 10))
	_carve(Rect2i(17, 1, 12, 10))
	_carve(Rect2i(31, 1, 14, 10))
	# 电台塔 + 通道。
	_carve(Rect2i(32, 21, 12, 8))
	_carve(Rect2i(37, 15, 2, 7))
	# 主街铺路面（tile 3），房间留地板（tile 0）。
	for y: int in range(12, 16):
		for x: int in range(1, 47):
			if int(map[y][x]) == 0:
				map[y][x] = 3
	# 门（默认关着）。
	_set_tile(Vector2i(8, 11), 2)
	_set_tile(Vector2i(22, 11), 2)
	_set_tile(Vector2i(37, 11), 2)
	_set_tile(Vector2i(37, 21), 2)
	doors_open.clear()


func _carve(rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			if in_bounds(Vector2i(x, y)):
				map[y][x] = 0


func _set_tile(cell: Vector2i, value: int) -> void:
	if in_bounds(cell):
		map[cell.y][cell.x] = value


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H


func is_wall(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return true
	return int(map[cell.y][cell.x]) == 1


func is_door(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	return int(map[cell.y][cell.x]) == 2


func is_closed_door(cell: Vector2i) -> bool:
	return is_door(cell) and not doors_open.has(cell)


func open_door(cell: Vector2i) -> void:
	if is_door(cell):
		doors_open[cell] = true


## 走不过去的地方：墙、关着的门、越界。
func is_blocked(cell: Vector2i) -> bool:
	return is_wall(cell) or is_closed_door(cell)


## 这一格画什么。纯展示用途，规则不依赖它。
## 贴着可走地面的墙画砖墙，墙心画岩壁——不然整张图会是同一种墙。
func terrain_name(cell: Vector2i) -> String:
	if is_wall(cell):
		return "wall" if _touches_open(cell) else "rock"
	if is_door(cell):
		return "door_open" if doors_open.has(cell) else "door_closed"
	if in_bounds(cell) and int(map[cell.y][cell.x]) == 3:
		return "pavement"
	return "floor"


func _touches_open(cell: Vector2i) -> bool:
	for delta: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if not is_wall(cell + delta):
			return true
	return false


# ================================================================ 实体

## 地面物品的出生表。写死是为了测试稳定，正式版换成地图数据里的 spawn 表。
const SPAWN_ITEMS := [
	{"id": "crowbar", "pos": Vector2i(5, 5)},
	{"id": "water", "pos": Vector2i(6, 6)},
	{"id": "canned_food", "pos": Vector2i(7, 5)},
	{"id": "bandage", "pos": Vector2i(10, 8)},
	{"id": "pistol", "pos": Vector2i(20, 5)},
	{"id": "ammo", "pos": Vector2i(21, 5)},
	{"id": "flashlight", "pos": Vector2i(18, 8)},
	{"id": "tape", "pos": Vector2i(19, 5)},
	{"id": "radio_part", "pos": Vector2i(35, 5)},
	{"id": "wire", "pos": Vector2i(36, 6)},
	{"id": "battery", "pos": Vector2i(38, 5)},
	{"id": "medkit", "pos": Vector2i(40, 8)},
	{"id": "antibiotics", "pos": Vector2i(33, 8)},
	{"id": "keycard", "pos": Vector2i(42, 8)},
	{"id": "lockpick", "pos": Vector2i(39, 5)},
	{"id": "armor", "pos": Vector2i(34, 4)},
	{"id": "backpack", "pos": Vector2i(35, 4)},
	{"id": "stimulant", "pos": Vector2i(36, 4)},
	{"id": "purifier", "pos": Vector2i(37, 4)},
	{"id": "knife", "pos": Vector2i(20, 4)},
]


func _spawn_items() -> void:
	items.clear()
	for entry: Dictionary in SPAWN_ITEMS:
		items.append({"id": String(entry["id"]), "pos": entry["pos"]})


## 按 MONSTER_SPAWNS 放怪。数据来自 content/monsters.json，缺的跳过。
func _spawn_monsters() -> void:
	var index := 0
	for spawn: Dictionary in MONSTER_SPAWNS:
		var monster := _make_monster(String(spawn["type"]), spawn["pos"], index)
		if monster != null:
			index += 1


## 造一只怪。类型不在 monsters.json 里就返回 null（内容校验会先报出来）。
func _make_monster(type_id: String, cell: Vector2i, index: int) -> Actor:
	var monster_data: Dictionary = monster_db.get(type_id, {})
	if monster_data.is_empty():
		return null
	var monster := Actor.new()
	monster.id = "mon_%s_%d" % [type_id, index]
	monster.name = String(monster_data["name"])
	monster.monster_type = type_id
	monster.faction = "monster"
	monster.can_open_doors = false
	monster.hp = int(monster_data["hp"])
	monster.hp_max = monster.hp
	monster.speed = int(monster_data["speed"])
	monster.damage = int(monster_data["damage"])
	monster.armor = int(monster_data.get("armor", 0))
	monster.sight = int(monster_data["sight"])
	monster.pos = cell
	monster.moves = 0
	actors.append(monster)
	return monster


func actor_at(cell: Vector2i) -> Actor:
	for actor: Actor in actors:
		if actor.alive and actor.pos == cell:
			return actor
	return null


func items_at(cell: Vector2i) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		if item["pos"] == cell:
			found.append(item)
	return found


## 把脚下的东西全塞进背包，返回拿到的原型 id（按放置顺序）。
func take_items_at(actor: Actor) -> Array[String]:
	var taken: Array[String] = []
	for i: int in range(items.size() - 1, -1, -1):
		if items[i]["pos"] == actor.pos:
			var item_id := String(items[i]["id"])
			taken.push_front(item_id)
			actor.take_item(Item.new(item_id))
			items.remove_at(i)
	return taken


# ================================================================ 动作

## 唯一的动作入口。玩家、怪物、测试里的假人全走这里。
func perform(actor: Actor, action: Action) -> bool:
	if actor == null or not actor.alive:
		return false
	var reason := action.can(actor, self)
	if reason != "":
		_push_log(reason)
		return false
	var cost := action.cost_for(actor)
	if actor.moves < cost:
		_push_log("动不了（剩 %d moves），等一下。" % actor.moves)
		return false
	actor.moves -= cost
	if not action.apply(actor, self):
		actor.moves += cost
		return false
	command_log.append({"turn": turn, "actor": actor.id, "action": action.id})
	# CDDA 里做事时动一下就会打断手里的事；这里只有「等」不打断。
	if actor == player and not activity.is_empty() and action.id != "wait":
		_cancel_activity("你停下手里的活。")
	if actor == player:
		_update_fov()
	return true


## 玩家动到没 moves 就把回合让出去（CDDA 的 `while (u.get_moves() > 0)` 反过来写）。
## 由 UI 在每次输入后调用；规则在这里，应用层只负责“什么时候问”。
func settle() -> void:
	if not player.alive or _in_world_turn:
		return
	var guard := 0
	while player.moves < MIN_COST and player.alive and guard < 10:
		advance_turn()
		guard += 1


# ---- 玩家便捷方法（UI 用；规则仍在 Action 里）

func player_move(dx: int, dy: int) -> bool:
	return perform(player, Actions.Walk.new(dx, dy))


## 撞过去：那格有活物就打，没东西就走（CDDA 的 bump attack）。
func player_step(dx: int, dy: int) -> bool:
	var target := actor_at(player.pos + Vector2i(dx, dy))
	if target != null and target != player:
		return perform(player, Actions.Attack.new(target))
	return perform(player, Actions.Walk.new(dx, dy))


func player_attack(target: Actor) -> bool:
	return perform(player, Actions.Attack.new(target))


func player_loot() -> bool:
	return perform(player, Actions.Loot.new())


func player_use(item: Item) -> bool:
	return perform(player, Actions.UseItem.new(item))


func player_wait() -> bool:
	return perform(player, Actions.Wait.new())


## 交互（CDDA 的 examine，默认 e 键）：站在塔上就是修电台，旁边有门就推开。
func player_examine() -> bool:
	if player.pos == repair_site:
		return player_repair()
	for delta: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if is_closed_door(player.pos + delta):
			return perform(player, Actions.Walk.new(delta.x, delta.y))
	_push_log("这里没什么可看的。")
	return false


## 在塔上修电台。这是「活动」不是瞬间动作：要连续等 5 回合，动一下就断。
## 对应 CDDA 的 player_activity：跨回合推进、可被打断（docs/cdda-notes.md §2）。
func player_repair() -> bool:
	if won or dead:
		return false
	if player.pos != repair_site:
		_push_log("得到电台塔上才能修。")
		return false
	if radio_fixed:
		_push_log("电台已经修好了，守住就行。")
		return false
	if not activity.is_empty():
		_push_log("已经在修了。")
		return false
	for part: String in REPAIR_PARTS:
		if not player.has_item(part):
			_push_log("还缺%s。" % item_name(part))
			return false
	for part: String in REPAIR_PARTS:
		player.consume_type(part)
	activity = {"id": "repair", "turns_left": REPAIR_TURNS, "total": REPAIR_TURNS}
	_push_log("你把零件接上，开始调频（%d 回合，别乱动）。" % REPAIR_TURNS)
	return true


func _cancel_activity(reason: String) -> void:
	if activity.is_empty():
		return
	activity.clear()
	_push_log(reason)


func _tick_activity() -> void:
	if activity.is_empty():
		return
	activity["turns_left"] = int(activity["turns_left"]) - 1
	if int(activity["turns_left"]) > 0:
		_push_log("修理中……还剩 %d 回合。" % int(activity["turns_left"]))
		return
	activity.clear()
	radio_fixed = true
	defense_left = DEFENSE_TURNS
	_defense_just_started = true
	_push_log("电台咔哒一声通了：「有人在吗？」——守住 %d 回合。" % DEFENSE_TURNS)


func _tick_defense() -> void:
	if not radio_fixed or won or dead:
		return
	if _defense_just_started:
		_defense_just_started = false
		return
	defense_left -= 1
	if defense_left % DEFENSE_SPAWN_EVERY == 0:
		_spawn_wave()
	if defense_left <= 0:
		_win()
		return
	_push_log("还有 %d 回合。" % defense_left)


## 守塔时的刷怪点：塔里的几个角和门口。离修理点 4~8 格，逼玩家腾出手来打。
const DEFENSE_SPAWNS := [
	Vector2i(37, 20), Vector2i(33, 22), Vector2i(42, 22),
	Vector2i(33, 27), Vector2i(42, 27),
]


func _spawn_wave() -> void:
	for cell: Vector2i in DEFENSE_SPAWNS:
		if actor_at(cell) == null and not is_blocked(cell):
			_make_monster("shambler", cell, actors.size())
			_push_log("有什么从暗处围过来了。")
			return


func _win() -> void:
	if won:
		return
	won = true
	_push_log("螺旋桨声盖过了风声。你活下来了。")


# ================================================================ 世界回合

func advance_turn() -> void:
	if _in_world_turn:
		return
	_in_world_turn = true
	turn += 1
	for actor: Actor in actors:
		if actor.alive:
			actor.gain_turn_moves()
	_tick_needs()
	_tick_activity()
	_run_monsters()
	_tick_defense()
	_update_fov()
	_in_world_turn = false


func _tick_needs() -> void:
	if not player.alive:
		return
	player.hunger = maxi(0, player.hunger - 2)
	player.thirst = maxi(0, player.thirst - 3)
	if player.infection > 0:
		player.infection = mini(100, player.infection + 1)
	if player.hunger <= 0:
		player.take_damage(2)
	if player.thirst <= 0:
		player.take_damage(3)
	if player.infection >= 100:
		player.take_damage(2)
	if not player.alive:
		_push_log("你倒下了。")


## 怪物回合：谁攒够一步的 moves 谁就动，动到没钱为止。
## 循环形状照 CDDA：`while (moves > 0) { plan(); move(); }`（src/do_turn.cpp:388），
## 死了的怪留在 actors 里当尸体，UI 不画、也不行动。
func _run_monsters() -> void:
	for actor: Actor in actors:
		if actor == player or not actor.alive:
			continue
		var guard := 0
		while actor.moves >= MONSTER_COST and actor.alive and player.alive and guard < 12:
			guard += 1
			if not MonsterBrain.take_turn(actor, self):
				break


# ================================================================ 视野

func _update_fov() -> void:
	visible.clear()
	if player == null:
		return
	var target := player.pos
	var min_x := maxi(0, target.x - FOV_RADIUS)
	var max_x := mini(W - 1, target.x + FOV_RADIUS)
	var min_y := maxi(0, target.y - FOV_RADIUS)
	var max_y := mini(H - 1, target.y + FOV_RADIUS)
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if abs(cell.x - target.x) + abs(cell.y - target.y) > FOV_RADIUS:
				continue
			if _has_los(target, cell):
				visible[cell] = true
				seen[cell] = true


## 两点之间有没有视线。怪物追击用同一个函数，保证"你看得见它，它才看得见你"。
func has_los(from: Vector2i, to: Vector2i) -> bool:
	return _has_los(from, to)


func _has_los(from: Vector2i, to: Vector2i) -> bool:
	var dx: int = abs(to.x - from.x)
	var dy: int = abs(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err: int = dx - dy
	var current := from
	while current != to:
		if current != from and is_wall(current):
			return false
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			current.x += sx
		if e2 < dx:
			err += dx
			current.y += sy
	return true


# ================================================================ 存档

func to_dict() -> Dictionary:
	var open_doors: Array = []
	for cell: Vector2i in doors_open.keys():
		open_doors.append([cell.x, cell.y])
	var ground: Array = []
	for item: Dictionary in items:
		var pos: Vector2i = item["pos"]
		ground.append({"id": String(item["id"]), "pos": [pos.x, pos.y]})
	var actor_data: Array = []
	for actor: Actor in actors:
		actor_data.append(actor.to_dict())
	return {
		"version": SAVE_VERSION,
		"turn": turn,
		"run_seed": str(run_seed),
		"rng_state": str(rng.state),
		"actors": actor_data,
		"doors_open": open_doors,
		"items": ground,
		"activity": activity.duplicate(),
		"radio_fixed": radio_fixed,
		"defense_left": defense_left,
		"won": won,
		"command_log": command_log.duplicate(true),
	}


## 返回 false 表示存档版本不认识，什么都没改。
func from_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != SAVE_VERSION:
		return false
	turn = int(data.get("turn", 1))
	# RNG 状态存成字符串：JSON 的数字是浮点，64 位 state 直接存会掉精度。
	run_seed = int(String(data.get("run_seed", "0")))
	if run_seed != 0:
		rng.seed = run_seed
		rng.state = int(String(data.get("rng_state", str(run_seed))))
	doors_open.clear()
	for entry: Variant in data.get("doors_open", []):
		var cell: Array = entry
		doors_open[Vector2i(int(cell[0]), int(cell[1]))] = true
	items.clear()
	for entry: Variant in data.get("items", []):
		var pos: Array = entry["pos"]
		items.append({"id": String(entry["id"]), "pos": Vector2i(int(pos[0]), int(pos[1]))})
	actors.clear()
	player = null
	for entry: Variant in data.get("actors", []):
		var actor := Actor.new()
		actor.from_dict(entry)
		actors.append(actor)
		if String(entry.get("id", "")) == "player":
			player = actor
			player.is_player = true
	command_log.clear()
	for entry: Variant in data.get("command_log", []):
		command_log.append(entry)
	activity = (data.get("activity", {}) as Dictionary).duplicate()
	radio_fixed = bool(data.get("radio_fixed", false))
	defense_left = int(data.get("defense_left", 0))
	won = bool(data.get("won", false))
	if player == null:
		return false
	_update_fov()
	return true


# ================================================================ 工具

func log_message(message: String) -> void:
	_push_log(message)


## 视野需要重算时调用（读档、传送、工具用）。
func refresh_view() -> void:
	_update_fov()


func item_name(id: String) -> String:
	var data: Dictionary = item_db.get(id, {})
	return String(data.get("name", id))


func _push_log(message: String) -> void:
	log_lines.append(message)
	if log_lines.size() > 8:
		log_lines.pop_front()
