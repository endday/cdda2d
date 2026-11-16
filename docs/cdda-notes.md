# 读 CDDA 源码：抄什么，不抄什么

> 目的：在写敌人/战斗之前，确认成熟实现怎么组织**时间、动作、AI、数据**，
> 免得自己发明一套模型，三天后和敌人撞车再返工。
>
> 对照版本：[Cataclysm-DDA](https://github.com/CleverRaven/Cataclysm-DDA) `master`，
> 本地浅克隆在 `_ref/Cataclysm-DDA`（218MB，464 个 .cpp / 493 个 .h）。
> 下面每条结论都标了 `文件:行`，可以自己去看。

## 1. 时间是 `moves` + `speed`，不是轮流

- `Creature::moves` 是 int，`get_speed() = speed_base + speed_bonus`（`src/creature.h:732-734, 1244`）。
- 每回合 `Creature::process_turn()` 做两件事：跑状态/持续伤害，然后 `moves += get_speed()`（`src/creature.cpp:488-495`）。
- 基准速度 100：一个"正常速度"的生物每回合拿 100 moves，走一格花 100。
- 主循环 `game::do_turn()`（`src/do_turn.cpp:536`）的顺序是：
  1. `while (u.get_moves() > 0) { handle_action(); ... }` 玩家一直动到没 moves（`src/do_turn.cpp:659-686`）；
  2. `while (u.get_moves() > 0 && u.activity) u.process_activity();` 持续活动顺手推进（`:700`）；
  3. 处理地图（字段/物品/声音），然后 `monmove()` 让所有怪物动。
- 怪物不是"一个回合动一下"，而是 `while (critter.get_moves() > 0) { plan(); move(); }`（`src/do_turn.cpp:388-397`）。
- **没有全局先攻队列。** 速度快 = moves 多 = 一回合里多走几步，不是"先动"。

**对我们的意义**：原来的 `AP 100 / 走 100` 其实就是 CDDA 的 moves，只是挂在 World 上。
改成每个 Actor 自己持有 moves、速度 150 的奔跑者自然一回合走 1.5 步，不需要写任何"先攻"代码。
另外，CDDA 里没有"结束回合"键——空格是 `wait` 动作，花 100 moves。我们照这个做：
空格变成「等」，时间推进由 `World.settle()` 在玩家花光 moves 后触发。

## 2. 动作分两层：瞬间动作 vs 持续活动

- 第一层 `src/action.h`：`action_id` 是**输入**枚举，把按键映射成意图，`game::handle_action()` 分发。
- 第二层 `player_activity` + `activity_actor`：长动作是对象，不是阻塞调用。
  字段 `type / moves_left / moves_total / targets / values`（`src/player_activity.h:36-65`），
  接口 `start / do_turn / finish / canceled / can_resume_with`（`src/activity_actor.h:56-70`）。
- 每回合活动从角色身上扣 moves，分 `based_on::TIME`（按时间，如睡觉）和 `based_on::SPEED`（按速度，如制作）
  （`src/player_activity.cpp:244-259`）。所以制作/修理可以被怪物打断——它是"每回合 tick 的状态机"，不是 `await`。
- 中断是显式的：`Character::cancel_activity()`（`src/character.cpp:5403`）。

**对我们的意义**：短动作（走/搜/开/用）用 `Action{cost, can, apply}` 就够；
长动作（制作、修电台、守塔）必须是 `Activity` 对象，每回合推进、可被打断。
把"修电台"做成一次按键结算，等于扔掉这个游戏最重要的张力。

## 2.5 物品怎么驱动交互（复刻的重点）

CDDA 的物品分成三层，我们照着抄：

| 层 | CDDA | 我们 |
|---|---|---|
| 原型 | `itype`（`src/item.h`），JSON 定义，共享 | `content/items.json` 里的条目 |
| 实例 | `item`，只有 id + 会变的状态（`charges`/`active`） | `src/core/item.gd` |
| 动词 | `use_methods` 里写 `{"type": "..."}`，引擎按 type 找 `iuse_actor` 子类执行（`src/iuse_actor.cpp`） | `src/core/item_use.gd` 的注册表 |

所以物品 JSON 里只有数据，没有分支：

```json
{"id": "water", "name": "瓶装水",
 "use_methods": [{"type": "consume", "quench": 40, "msg": "瓶装水"}]}
```

- **加一件物品**：往 `items.json` 加一条，挑一个已有的 `type`。代码零改动。
- **加一种玩法**：`ItemUse.register("type", can, use)`，再在 JSON 里用。World / UI / 存档都不用动。
- **写错动词**：`ContentDB` 校验会报"未注册的动词"，并列出已注册的；测试直接红。

这就是"后续无痛接入各种物品"的机制：新增的是**数据 + 动词**，不是新的 if 分支。
`tests/test_content.gd` 里有两个测试专门盯这件事（只写数据的新物品、运行时注册的新动词）。

对应的界面也走同一条路：背包面板的说明文字是从 `use_methods` 推出来的
（`喝 +40` / `治 +15` / `开关`），不是给每件物品写死的文案。

## 3. 怪物 AI：`plan()` 想，`move()` 走一步

- `monster::plan()`（`src/monmove.cpp:558`）：看能不能 `sees()` 到目标，
  用 `rate_target()` 给每个候选打分（距离+智能修正），决定 `target`、`fleeing`、`dest`。
  没有威胁时限流思考（`max_turns_to_skip`），省 CPU。
- `monster::move()`（`src/monmove.cpp:976`）：只管**一步**——特殊攻击（带 cooldown）→
  `move_effects` → 相邻就打 / 朝 dest 走一格 / 漫游。
- 感知是独立一层：`sees()` 视野、`hear_sound()` 听觉、scent 嗅觉，都要单独维护。
- 态度/情绪是一整个系统：`anger / morale / friendly / attitude / faction`，为 100+ 怪物类型服务。

**对我们的意义**：抄「plan 一次、走一步、循环」这个骨架，它是 30 行就能写完的东西，
而且天然能吃 moves 累积。**不抄** anger/morale/faction——那是内容规模的产物，我们只有 2 种怪。

## 4. 战斗：命中 / 伤害 / 护甲 三段

- 命中：`Character::hit_roll()`（`src/melee.cpp:385`）对目标的 `deal_melee_attack()`，
  入口 `melee_attack_abstract()`（`src/melee.cpp:603-631`）。
- 伤害是**列表**：`damage_instance` 装若干 `damage_unit{type, amount, res_pen, res_mult, damage_multiplier}`
  （`src/damage.h:113-136`），落到目标身上再按身体部位和护甲 `resistances` 结算。
- 有格挡/闪避/暴击/技巧（`block_hit`、`perform_special_attacks`）。

**对我们的意义**：我们只有一种伤害、一种护甲。`items.json` 里已有的 `damage` 字段直接当武器伤害，
护甲就是 `armor` 数字做减法。**不抄**伤害类型/穿透/身体部位——那是 1000 件物品规模才付得起的复杂度。
但"命中判定和伤害结算分开"值得抄：命中失败要有反馈，否则玩家会以为游戏卡了。

## 5. 数据：每个类型一个 `generic_factory`，校验是独立一遍

- 加载：`mandatory(jo, was_loaded, "id", id)` + `optional(...)`（`src/monstergenerator.cpp:867-886`），
  `string_id<T>` 做 id 驻留。
- 校验不在加载时做，而是全部加载完跑一遍 `DynamicDataLoader::check_consistency()`
  （`src/init.cpp:954-1010`，60 多个类型各自 `check_consistency`），可以用 `SKIP_VERIFICATION` 跳过。
- **出错分两种，不是一刀切**：
  - 结构性错误（未知 `type`、缺 `mandatory` 字段、`id`/`abstract` 都没写）→ `JsonError` →
    `std::runtime_error` → 启动时 `debugmsg` 后 **`std::exit(1)`**（`main_menu.cpp:535`）。真的会退出。
  - 语义问题（引用不存在、掉落表落不了地）→ `check_consistency` 里 `debugmsg` **警告继续**；
    `copy-from` 解不开的走 deferred，重试一轮还不行就 `"circular dependency, this object is discarded"`，
    丢对象、继续跑。未读字段也只是警告（`flexbuffer_json.cpp:249,325`）。
- 存档是 JSON，带 `# version 40` 头，地图按 OMT 分文件、地形用 RLE 字符串 id（`savegame_json.cpp:5106`）；
  版本迁移靠版本分支 + id 重映射（`migrate_id`）。均匀地块干脆不存。
- 随机数是**一个全局引擎** `minstd_rand0`（`src/rng.cpp:207-212`），没有按子系统分流的 RNG，
  也**不保证** seed 回放：`start_game()` 里 `seed = rng_bits()` 只拿去干扰天气生成（`game.cpp:796`）。

**对我们的意义**：JSON + `id/name/kind` 这套没问题，但我们对"坏数据"的态度要比 CDDA 严——
它们是"能跑就先跑，弹窗警告"，我们是单内容包 + 测试驱动，坏掉就该让测试红，而不是弹个窗继续跑。
`abstract / copy-from / extend` 暂时不抄：20 件物品直接写最清楚。
CDDA 自己也不保证回放确定性，所以「seed + command_log」是我们要比它更严，不是从它抄的。

## 6. 对照表

| 主题 | CDDA | 我们 | 理由 |
|---|---|---|---|
| 时间 | `moves`/`speed`，速度=更多 moves | **抄** | 现在 AP 已经是它，只是位置错了 |
| 回合顺序 | 玩家动到没 moves → 世界动 | **抄** | 不用写先攻队列 |
| 结束回合 | 空格 = wait 动作 | **抄** | 少一个特判 |
| 短动作 | `action_id` + 分发 | 抄概念，不抄输入枚举 | Godot 有 InputMap |
| 长动作 | `player_activity` / `activity_actor` | **抄骨架** | 制作/修电台必须可打断 |
| 怪物 AI | plan() + 一步 move() | **抄** | 30 行，天然吃 moves |
| 怪物情绪 | anger/morale/faction | 不抄 | 内容规模产物 |
| 战斗 | 伤害类型/穿透/身体部位 | 不抄 | 一种伤害够用 |
| 命中与伤害分离 | 是 | **抄** | 命中失败要有反馈 |
| 数据校验 | 独立 pass + 丢弃警告 | 抄结构，**改严** | 测试驱动要红 |
| JSON 继承 | abstract/copy-from | 不抄 | 20 件物品不需要 |
| 随机器 | 单一全局 RNG | **不抄** | 我们要回放，按子系统分 |
| FOV | lightmap 缓存 + 阴影投射 | 暂不抄 | 48×32 用 Bresenham 就够 |

## 7. 落到本项目的顺序

1. **Actor**：pos / hp / moves / speed / 需求 / 背包 / alive。玩家和怪物同一个类，区别只在数据和脑子。
2. **Action**：`{cost, can(), apply()}`，走/搜/开/用/等五个动词走同一条 `world.perform(actor, action)`。
3. **能量回合**：每个 Actor 每回合 `moves += speed`；玩家动到 `moves < 50` 世界推进；空格 = Wait。
4. **门**：现在门是装饰（只有 wall 挡路）。变成“关着挡路、开着不挡”，`OpenDoorAction` 成为第二个真动词。
5. 之后才是 `monsters.json` + `MonsterBrain.plan()` + `AttackAction` + `Activity`（修电台）。

## 8. 验收

- 现有 21 项检查的行为不变（测试会跟着 API 改，断言的意图不改）。
- 新增：同一个 `MoveAction` 能被一个非玩家 Actor 执行；门关着走不过去、开了能过。
- `world.command_log` 记录每条动作，后面 `seed + command_log` 回放才有东西可回放。
