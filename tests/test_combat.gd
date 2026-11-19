extends RefCounted
## 战斗 + 怪物 AI 的测试：命中/伤害/护甲、撞上去就是打、怪会追人、会打死你。

const MAX_REPORTED_FAILURES := 20
const Actions := preload("res://src/core/actions.gd")

var _failures: Array[String] = []
var _checks: int = 0


func suite_title() -> String:
	return "Combat"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0

	test_weapon_and_armor_values()
	test_resolve_is_deterministic()
	test_player_kills_monster()
	test_bump_attack_does_not_move()
	test_monster_chases_player()
	test_monster_hurts_player()
	test_dead_monster_stops_acting()

	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _items() -> Dictionary:
	return {
		"knife": {"id": "knife", "name": "小刀", "melee": {"damage": 6}},
		"armor": {"id": "armor", "name": "护甲", "armor": 3},
		"water": {"id": "water", "name": "水",
			"use_methods": [{"type": "consume", "quench": 40}]},
	}


func _monsters() -> Dictionary:
	return {
		"shambler": {"id": "shambler", "name": "蹒跚", "hp": 10, "speed": 100,
			"damage": 5, "armor": 0, "sight": 8},
	}


func _world() -> World:
	return World.new(_items(), _monsters(), 12345)


## 从世界里的出生点拿第一只怪，挪到指定位置（测试用）。
func _take_monster(world: World, at: Vector2i) -> Actor:
	for actor: Actor in world.actors:
		if actor != world.player:
			actor.pos = at
			actor.hp = actor.hp_max
			actor.alive = true
			actor.brain.clear()
			actor.moves = 0
			return actor
	return null


func test_weapon_and_armor_values() -> void:
	var world := _world()
	var player := world.player
	_expect(Combat.weapon_damage(player, world.item_db) == Combat.FIST_DAMAGE,
		"空手应该是拳头伤害，实际 %d" % Combat.weapon_damage(player, world.item_db))
	player.take_item(Item.new("knife"))
	_expect(Combat.weapon_damage(player, world.item_db) == Combat.FIST_DAMAGE,
		"只放进背包的小刀不该改变伤害")
	player.wield_item(player.find_item("knife"))
	_expect(Combat.weapon_damage(player, world.item_db) == 6,
		"手持小刀应该是 6，实际 %d" % Combat.weapon_damage(player, world.item_db))
	_expect(Combat.armor_of(player, world.item_db) == 0, "没穿护甲应该是 0")
	player.take_item(Item.new("armor"))
	_expect(Combat.armor_of(player, world.item_db) == 0, "只放进背包的护甲不该生效")
	player.wear_item(player.find_item("armor"), world.item_db)
	_expect(Combat.armor_of(player, world.item_db) == 3,
		"穿上护甲应该是 3，实际 %d" % Combat.armor_of(player, world.item_db))


func test_resolve_is_deterministic() -> void:
	var world := _world()
	var monster := _take_monster(world, Vector2i(10, 10))
	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 99
	var first := Combat.resolve(world.player, monster, world.item_db, first_rng)
	var second_rng := RandomNumberGenerator.new()
	second_rng.seed = 99
	var second := Combat.resolve(world.player, monster, world.item_db, second_rng)
	_expect(first["hit"] == second["hit"] and first["damage"] == second["damage"],
		"同一个种子应该算出同一结果")


func test_player_kills_monster() -> void:
	var world := _world()
	var monster := _take_monster(world, world.player.pos + Vector2i(1, 0))
	world.player.take_item(Item.new("knife"))
	world.player.wield_item(world.player.find_item("knife"))
	for i: int in 40:
		world.player.moves = 100
		world.player_attack(monster)
		if not monster.alive:
			break
	_expect(not monster.alive, "40 次攻击内应该打死一只 10 血的怪")
	_expect(monster.hp == 0, "死的怪 hp 应该是 0，实际 %d" % monster.hp)


func test_bump_attack_does_not_move() -> void:
	var world := _world()
	var monster := _take_monster(world, world.player.pos + Vector2i(1, 0))
	world.player.moves = 100
	var before := world.player.pos
	world.player_step(1, 0)
	_expect(world.player.pos == before, "撞到怪不该走过去")
	_expect(monster.hp < monster.hp_max or not monster.alive, "撞上去应该打中或打空，但一定要出手")


func test_monster_chases_player() -> void:
	var world := _world()
	var monster := _take_monster(world, world.player.pos + Vector2i(-4, 0))
	var before := absi(monster.pos.x - world.player.pos.x)
	for i: int in 3:
		world.advance_turn()
	_expect(monster.pos != Vector2i(-1, -1), "怪应该动过")
	_expect(absi(monster.pos.x - world.player.pos.x) < before,
		"看得见的怪应该朝玩家靠近，之前 %d 格，现在 %d" % [before, absi(monster.pos.x - world.player.pos.x)])


func test_monster_hurts_player() -> void:
	var world := _world()
	_take_monster(world, world.player.pos + Vector2i(1, 0))
	var before := world.player.hp
	world.advance_turn()
	_expect(world.player.hp < before, "adjacent 的怪打一回合应该掉血，之前 %d，现在 %d"
		% [before, world.player.hp])


func test_dead_monster_stops_acting() -> void:
	var world := _world()
	var monster := _take_monster(world, world.player.pos + Vector2i(1, 0))
	monster.take_damage(999)
	var pos_before := monster.pos
	var hp_before := world.player.hp
	world.advance_turn()
	_expect(monster.pos == pos_before, "死怪不该再移动")
	_expect(world.player.hp == hp_before, "死怪不该再打人")
