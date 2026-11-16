class_name MonsterBrain
extends RefCounted
## 怪物的脑子：plan() 选目标和目的地，step() 走一步或打一下。
##
## 对照 CDDA：`monster::plan()` 用 `rate_target()` 挑目标、`set_dest()` 定方向
## （src/monmove.cpp:558），`monster::move()` 只做一步：相邻就打、否则朝 dest 走一格
## （src/monmove.cpp:976）；外层是 `while (moves > 0) { plan(); move(); }`。
## 我们把循环放在 World._run_monsters() 里，这里只负责一次「想 + 做」。
##
## 参数用 Variant 是为了避开 World ↔ MonsterBrain 的类名循环引用。

const Actions := preload("res://src/core/actions.gd")


## 一次完整的思考+行动。返回 false 表示卡住了，外层别再空转。
static func take_turn(monster: Variant, world: Variant) -> bool:
	_plan(monster, world)
	return _step(monster, world)


static func _plan(monster: Variant, world: Variant) -> void:
	var player: Actor = world.player
	if player == null or not player.alive:
		monster.brain.erase("target")
		monster.brain.erase("dest")
		return
	var distance: int = _manhattan(monster.pos, player.pos)
	if distance <= monster.sight and world.has_los(monster.pos, player.pos):
		monster.brain["target"] = player
		monster.brain["dest"] = player.pos
		return
	# 看不见了：朝最后看见的位置走，走到就忘掉。
	if monster.brain.has("where"):
		var where: Vector2i = monster.brain["where"]
		if monster.pos == where:
			monster.brain.erase("where")
		else:
			monster.brain["dest"] = where


static func _step(monster: Variant, world: Variant) -> bool:
	var target: Actor = monster.brain.get("target")
	if target != null and target.alive and _manhattan(monster.pos, target.pos) == 1:
		monster.brain["where"] = target.pos
		return world.perform(monster, Actions.Attack.new(target))

	if monster.brain.has("dest"):
		var dest: Vector2i = monster.brain["dest"]
		monster.brain["where"] = dest
		if monster.pos == dest:
			monster.brain.erase("dest")
			return true
		for step: Vector2i in _steps_toward(monster.pos, dest):
			if world.perform(monster, Actions.Walk.new(step.x, step.y)):
				return true
		# 两个方向都堵住了：原地想一下，别把 moves 攒成一大坨。
		monster.brain.erase("dest")
		return false

	return _wander(monster, world)


static func _wander(monster: Variant, world: Variant) -> bool:
	var rng: RandomNumberGenerator = world.rng
	var steps: Array[Vector2i] = [
		Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
	]
	# 从随机的方向开始试，免得所有怪都往同一个角走。
	var start: int = rng.randi_range(0, steps.size() - 1)
	for i: int in steps.size():
		var step: Vector2i = steps[(start + i) % steps.size()]
		if world.perform(monster, Actions.Walk.new(step.x, step.y)):
			return true
	return false


## 朝目标走：斜着最近就走斜的；被堵了再试主轴、次轴。
static func _steps_toward(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var dx: int = signi(to.x - from.x)
	var dy: int = signi(to.y - from.y)
	var out: Array[Vector2i] = []
	if dx != 0 and dy != 0:
		out.append(Vector2i(dx, dy))
	if absi(to.x - from.x) >= absi(to.y - from.y):
		if dx != 0:
			out.append(Vector2i(dx, 0))
		if dy != 0:
			out.append(Vector2i(0, dy))
	else:
		if dy != 0:
			out.append(Vector2i(0, dy))
		if dx != 0:
			out.append(Vector2i(dx, 0))
	return out


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
