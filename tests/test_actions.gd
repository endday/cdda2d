extends RefCounted
## Action 层的测试：证明动作不属于玩家——同一个 action 换个 actor 照样能跑。

const MAX_REPORTED_FAILURES := 20
const Actions := preload("res://src/core/actions.gd")

var _failures: Array[String] = []
var _checks: int = 0


func suite_title() -> String:
	return "Actions"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0

	test_dummy_actor_walks()
	test_monster_cannot_open_door()
	test_action_needs_moves()
	test_wait_spends_what_is_left()
	test_command_log_records_action()

	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _dummy(world: World, at: Vector2i) -> Actor:
	var actor := Actor.new()
	actor.id = "dummy"
	actor.name = "假人"
	actor.faction = "monster"
	actor.can_open_doors = false
	actor.pos = at
	actor.moves = Actor.BASE_SPEED
	world.actors.append(actor)
	return actor


func test_dummy_actor_walks() -> void:
	var world := World.new({})
	var dummy := _dummy(world, Vector2i(24, 14))
	var moved := world.perform(dummy, Actions.Walk.new(1, 0))
	_expect(moved, "非玩家 Actor 应该能用同一个 Walk 动作")
	_expect(dummy.pos == Vector2i(25, 14), "假人应走到 (25,14)，实际 %s" % dummy.pos)
	_expect(dummy.moves == 0, "假人应扣 100 moves，实际 %d" % dummy.moves)
	_expect(world.player.pos == Vector2i(24, 13), "玩家不该被带着动")


func test_monster_cannot_open_door() -> void:
	var world := World.new({})
	var dummy := _dummy(world, Vector2i(8, 12))
	var moved := world.perform(dummy, Actions.Walk.new(0, -1))
	_expect(not moved, "不能开门的 Actor 撞门应失败")
	_expect(world.is_closed_door(Vector2i(8, 11)), "门应还是关着")
	_expect(dummy.pos == Vector2i(8, 12), "位置不该变")


func test_action_needs_moves() -> void:
	var world := World.new({})
	var dummy := _dummy(world, Vector2i(24, 14))
	dummy.moves = World.MIN_COST
	_expect(not world.perform(dummy, Actions.Walk.new(1, 0)), "moves 不够走路应失败")
	_expect(dummy.pos == Vector2i(24, 14), "失败不该移动")
	_expect(dummy.moves == World.MIN_COST, "失败不该扣 moves")


func test_wait_spends_what_is_left() -> void:
	var world := World.new({})
	world.player.moves = World.MIN_COST
	_expect(world.player_wait(), "剩一半 moves 也应该能等")
	_expect(world.player.moves == 0, "等待应把剩下的 moves 花光，实际 %d" % world.player.moves)


func test_command_log_records_action() -> void:
	var world := World.new({})
	world.player_move(1, 0)
	_expect(world.command_log.size() == 1, "应记录一条命令，实际 %d" % world.command_log.size())
	if world.command_log.size() == 1:
		_expect(String(world.command_log[0]["action"]) == "walk", "应记录动作 id")
		_expect(String(world.command_log[0]["actor"]) == "player", "应记录是谁做的")
