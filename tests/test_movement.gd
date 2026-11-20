extends RefCounted
## Movement tests cover distance costs, continuous positions, collisions, A* routing, and saves.

const MainScene := preload("res://scenes/main.gd")

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
	test_free_move_uses_continuous_position()
	test_free_move_stops_at_wall()
	test_pathfinder_routes_around_wall()
	test_free_position_survives_save()
	test_legacy_save_defaults_to_cell_center()
	test_turn_budget_projects_stop_position()

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


func test_free_move_uses_continuous_position() -> void:
	var world := _world()
	world.player.moves = 100
	_expect(world.player_move_direction(Vector2.RIGHT, 0.25), "自由移动应该成功")
	_expect(world.player.free_pos.is_equal_approx(Vector2(24.25, 13)),
		"位置应停在格子之间，实际 %s" % world.player.free_pos)
	_expect(world.player.pos == Vector2i(24, 13), "格子逻辑仍应指向所在地图单元")
	_expect(world.player.moves == 75, "移动费用应按距离结算")


func test_free_move_stops_at_wall() -> void:
	var world := _world()
	world.player.pos = Vector2i(10, 13)
	world.player.moves = 100
	world.map[13][11] = 1
	_expect(not world.player_move_direction(Vector2.RIGHT, 0.75), "自由移动不能穿过墙")
	_expect(world.player.free_pos.is_equal_approx(Vector2(10, 13)), "撞墙后连续坐标不应变化")


func test_pathfinder_routes_around_wall() -> void:
	var world := _world()
	world.map[13][11] = 1
	var path := world.find_path(Vector2i(10, 13), Vector2i(12, 13), world.player)
	_expect(path.size() >= 3, "寻路应绕开墙，而不是直穿")
	for cell: Vector2i in path:
		_expect(not world.is_wall(cell), "路线不能经过墙格 %s" % cell)


func test_free_position_survives_save() -> void:
	var world := _world()
	world.player.free_pos = Vector2(24.25, 13.125)
	var restored := _world()
	_expect(restored.from_dict(world.to_dict()), "自由位置存档应能读回")
	_expect(restored.player.free_pos.is_equal_approx(Vector2(24.25, 13.125)),
		"读档后应保留格子间的位置")


func test_legacy_save_defaults_to_cell_center() -> void:
	var save_data := _world().to_dict()
	save_data["version"] = 7
	for actor_data: Dictionary in save_data["actors"]:
		actor_data.erase("free_pos")
	var restored := _world()
	_expect(restored.from_dict(save_data), "旧版格子存档应能继续读取")
	_expect(restored.player.free_pos == Vector2(24, 13), "旧存档角色应落在格子中心")


func test_turn_budget_projects_stop_position() -> void:
	var world := _world()
	var scene := MainScene.new()
	scene.world = world
	var route := PackedVector2Array([Vector2(24, 13), Vector2(26, 13)])
	var stop_position: Vector2 = scene._position_after_movement(route, 50, 100.0)
	_expect(stop_position.is_equal_approx(Vector2(24.5, 13)), "路线预览应按本回合行动点标出停点")
	var door_route := PackedVector2Array([Vector2(8, 12), Vector2(8, 11), Vector2(8, 10)])
	var door_stop: Vector2 = scene._position_after_movement(door_route, 100, 100.0)
	_expect(door_stop.is_equal_approx(Vector2(8, 11.5)), "路线预览应计入推门消耗")
	_expect(scene._route_cost(door_route, 100.0) == 300.0, "寻路成本应计入打开关闭的门")
	scene.free()
