extends RefCounted
## 具体动作。每个只做一件事，费用写在自己身上（CDDA 也是动作自己带 moves 成本）。
## 用法：`world.perform(actor, Actions.Walk.new(1, 0))`。


## 走一格。撞到关着的门会先开门（不移动），下一格才能过去。
## 斜走按 √2 计价（CDDA 的 `move_cost * M_SQRT2`），而且不能从两个墙角之间穿过去。
class Walk extends Action:
	const MOVE_COST := 100
	const DIAGONAL_COST := 141    # int(100 * sqrt(2))

	var dx: int = 0
	var dy: int = 0

	func _init(step_x: int, step_y: int) -> void:
		id = "walk"
		label = "移动"
		dx = step_x
		dy = step_y
		cost = MOVE_COST if dx == 0 or dy == 0 else DIAGONAL_COST

	func can(actor: Variant, world: Variant) -> String:
		var target: Vector2i = actor.pos + Vector2i(dx, dy)
		if world.is_wall(target):
			return "前面是墙。"
		if world.is_closed_door(target) and not actor.can_open_doors:
			return "门关着。"
		if dx != 0 and dy != 0:
			# 两个正交邻格都堵住时不许斜穿——CDDA 的 diagonal 检查。
			var side_a: Vector2i = actor.pos + Vector2i(dx, 0)
			var side_b: Vector2i = actor.pos + Vector2i(0, dy)
			if world.is_blocked(side_a) and world.is_blocked(side_b):
				return "拐角过不去。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		var target: Vector2i = actor.pos + Vector2i(dx, dy)
		if world.is_closed_door(target):
			world.open_door(target)
			world.log_message("%s推开门。" % _who(actor))
			return true
		actor.pos = target
		return true

	func _who(actor: Variant) -> String:
		return "你" if actor.is_player else ""


## 搜脚下的东西。
class Loot extends Action:
	func _init() -> void:
		id = "loot"
		label = "搜刮"
		cost = 50

	func can(actor: Variant, world: Variant) -> String:
		if world.items_at(actor.pos).is_empty():
			return "这里没有东西。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		var taken: Array[String] = world.take_items_at(actor)
		if taken.is_empty():
			return false
		world.log_message("搜到：%s。" % ", ".join(taken))
		return true


## 用一件背包里的东西。走 ItemUse 注册表——加新物品不用改这里。
class UseItem extends Action:
	var item: Item

	func _init(target: Item) -> void:
		id = "use"
		label = "使用"
		cost = 50
		item = target

	func can(actor: Variant, world: Variant) -> String:
		if item == null or not actor.inventory.has(item):
			return "背包里没有这件东西。"
		return ItemUse.can_use(actor, world, item)

	func apply(actor: Variant, world: Variant) -> bool:
		var result: Dictionary = ItemUse.use(actor, world, item)
		if not bool(result.get("ok", false)):
			world.log_message(String(result.get("message", "用不了。")))
			return false
		var message := String(result.get("message", ""))
		if not message.is_empty():
			world.log_message(message)
		if bool(result.get("consume", false)):
			actor.remove_item(item)
		return true


## 等。CDDA 里空格就是这个动作，不是“结束回合”的开关；花掉一整个回合的 moves。
## 剩的 moves 不够 100 时，有多少花多少，照样把回合让出去。
class Wait extends Action:
	func _init() -> void:
		id = "wait"
		label = "等待"
		cost = 100

	func cost_for(actor: Variant) -> int:
		# 等：有多少花多少，但至少花 1，别让停在 0 上不推进。
		return maxi(1, mini(cost, actor.moves))

	func apply(_actor: Variant, _world: Variant) -> bool:
		return true


## 近战。相邻才能打，结算交给 Combat（命中/伤害/护甲）。
class Attack extends Action:
	var target: Actor

	func _init(who: Actor) -> void:
		id = "attack"
		label = "攻击"
		cost = 100
		target = who

	func can(actor: Variant, _world: Variant) -> String:
		if target == null or not target.alive:
			return "那里没有活物。"
		if _distance(actor.pos, target.pos) > 1:
			return "太远了，得先靠近。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		var result: Dictionary = Combat.resolve(actor, target, world.item_db, world.rng)
		var who := "你" if actor.is_player else String(actor.name)
		var victim := "你" if target.is_player else String(target.name)
		if not bool(result["hit"]):
			world.log_message("%s打空了。" % who)
			return true
		var amount: int = int(result["damage"])
		target.take_damage(amount)
		world.log_message("%s打中%s，%d 点伤害。" % [who, victim, amount])
		if not target.alive:
			world.log_message("%s倒下了。" % victim)
		return true

	func _distance(a: Vector2i, b: Vector2i) -> int:
		return absi(a.x - b.x) + absi(a.y - b.y)
