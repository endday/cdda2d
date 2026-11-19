class_name Combat
extends RefCounted
## 战斗的纯规则：命中、伤害、护甲。不碰 World 状态，方便单测。
##
## 对照 CDDA：命中在攻击方算（hit_roll），伤害在防守方结算（deal_damage），
## 护甲直接从每段伤害里扣（absorb_hit）。我们只留一条伤害类型，不搞穿透/身体部位
## ——那个复杂度是 1000 件物品规模才付得起的，见 docs/cdda-notes.md §4。

const HIT_CHANCE := 85      # 近战基础命中率，百分比
const FIST_DAMAGE := 3


## 武器伤害只取手持物品。怪物和空手玩家使用天生攻击力。
static func weapon_damage(actor: Actor, item_db: Dictionary) -> int:
	var weapon := actor.wielded if actor.wielded != null else actor.offhand
	if weapon == null:
		return maxi(FIST_DAMAGE, actor.damage)
	var melee: Dictionary = weapon.prototype(item_db).get("melee", {})
	return int(melee.get("damage", maxi(FIST_DAMAGE, actor.damage)))


## 护甲只计算已穿戴物品。
static func armor_of(actor: Actor, item_db: Dictionary) -> int:
	var best: int = actor.armor
	for item: Item in actor.worn:
		best += int(item.prototype(item_db).get("armor", 0))
	return best


## 结算一次近战。返回 {hit, damage}，调用方负责扣血和写日志。
static func resolve(attacker: Actor, defender: Actor, item_db: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	if rng.randi_range(1, 100) > HIT_CHANCE:
		return {"hit": false, "damage": 0}
	var raw := weapon_damage(attacker, item_db) + rng.randi_range(-1, 1)
	var reduced := raw - armor_of(defender, item_db)
	return {"hit": true, "damage": maxi(1, reduced)}
