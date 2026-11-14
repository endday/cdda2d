class_name Action
extends RefCounted
## 一个瞬间动作：花多少 moves、能不能做、做了什么。
##
## 玩家和 AI 走同一条 `World.perform(actor, action)`，没有“玩家的走路”和“怪的走路”之分。
## 参数故意用 Variant：core 里 Action ↔ World 互相引用会让 GDScript 的类解析打结。
##
## 长动作（制作/修电台）不走这里——那种要跨回合推进、可被打断，
## 对应 CDDA 的 player_activity + activity_actor（src/activity_actor.h:56-70）。

var id: String = ""
var label: String = ""
var cost: int = 0


## 实际费用。等待这类动作可以“有多少花多少”，所以费用依赖角色状态。
func cost_for(_actor: Variant) -> int:
	return cost


## 返回空字符串表示可以做；否则是给玩家看的原因，不扣 moves。
func can(_actor: Variant, _world: Variant) -> String:
	return ""


## 真正产生效果。返回 false 表示没做成，World 会退还 moves。
func apply(_actor: Variant, _world: Variant) -> bool:
	return false
