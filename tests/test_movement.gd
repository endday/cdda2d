extends RefCounted
## 8 向移动的测试：斜走 141、不能切墙角、怪也会斜着追。

const MAX_REPORTED_FAILURES := 20

var _failures: Array[String] = []
var _checks: int = 0


func suite_title() -> String:
	return "Movement"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0

	test_orthogonal_cost()
	test_diagonal_cost()
	test_corner_cutting_blocked()
	test_one_side_open_is_fine()
	test_monster_steps_diagonally()

	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _world() -> World:
	return World.new({}, {}, 99)


func test_orthogonal_cost() -> void:
	var world := _world()
	world.player.pos = Vector2i(24, 13)
	world.player.moves = 300
	_expect(world.player_step(0, -1), "往北走一格应该成功")
	_expect(world.player.moves == 200, "直走应该花 100，实际剩 %d" % world.player.moves)


func test_diagonal_cost() -> void:
	var world := _world()
	world.player.pos = Vector2i(24, 13)
	world.player.moves = 300
	_expect(world.player_step(1, -1), "斜着走应该成功")
	_expect(world.player.pos == Vector2i(25, 12), "应该走到 (25,12)，实际 %s" % world.player.pos)
	_expect(world.player.moves == 300 - 141, "斜走应该花 141，实际剩 %d" % world.player.moves)


func test_corner_cutting_blocked() -> void:
	var world := _world()
	world.player.pos = Vector2i(10, 13)
	world.player.moves = 300
	# 两个正交邻格都堵住，斜着那格虽然是空的，也不能穿。
	world.map[13][11] = 1
	world.map[12][10] = 1
	_expect(not world.player_step(1, -1), "两个墙角都堵住时不能斜穿")
	_expect(world.player.pos == Vector2i(10, 13), "被挡后位置不该变")


func test_one_side_open_is_fine() -> void:
	var world := _world()
	world.player.pos = Vector2i(10, 13)
	world.player.moves = 300
	world.map[13][11] = 1     # 右边堵，上面通
	_expect(world.player_step(1, -1), "只有一边堵住时应该能斜走")
	_expect(world.player.pos == Vector2i(11, 12), "应该走到 (11,12)，实际 %s" % world.player.pos)


func test_monster_steps_diagonally() -> void:
	var world := World.new({}, {"shambler": {"id": "shambler", "name": "蹒跚", "hp": 24,
		"speed": 100, "damage": 4, "armor": 0, "sight": 8}}, 99)
	# 房子里一块空地：怪在 (20,5)，玩家在 (22,7)，直线和斜线都能走。
	world.player.pos = Vector2i(22, 7)
	world.player.moves = 100
	var monster: Actor = null
	for actor: Actor in world.actors:
		if actor != world.player:
			monster = actor
			break
	_expect(monster != null, "应该刷出怪")
	if monster == null:
		return
	monster.pos = Vector2i(20, 5)
	monster.brain.clear()
	world.advance_turn()
	_expect(monster.pos == Vector2i(21, 6),
		"怪应该斜着靠近到 (21,6)，实际 %s" % monster.pos)
