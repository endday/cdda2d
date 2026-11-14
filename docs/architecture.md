# 架构：CDDA-like 的骨架

> 目标：规则可测、可回放、UI 不撒谎、内容不静默错。
> 当前是灰盒：`World` 一个类装了地图/玩家/物品/需求/回合/视野/存档；
> 下一步按下面的模块拆开，不改变对外行为。

## 1. 六个原语

| # | 原语 | 含义 |
|---|---|---|
| 1 | **世界是数据** | 每格地形/家具/物品；门、窗、容器、工作台都是数据 |
| 2 | **动作是通用的** | 走/打/用/搜/开/砸/制作/读/睡/等待；玩家和 AI 同一套 |
| 3 | **物品是动词** | 原型 + 实例；组件/改装/耐久/充能；使用/攻击/拆解/制作 |
| 4 | **时间是调度器** | 能量/行动点；需求、制作、状态、AI 都挂在回合上 |
| 5 | **感知是数据边界** | FOV/光/噪音；UI 只读玩家认知 |
| 6 | **内容是数据** | JSON/Resources；加载时校验；可加 mod |

## 2. 三层

```
src/core/        纯 GDScript，不 import Godot
src/app/         用例：新游戏/读档/存档/回合推进/场景
scenes/          Godot 适配层：TileMap/相机/UI/输入
content/         JSON/Resources：items/recipes/monsters/maps/tiles
tests/           纯逻辑 + 回放 + 内容校验
```

依赖方向：`scenes → app → core`；`core` 不反向依赖；`content` 由 app 编译成 catalog。

## 3. 目标模块

| 模块 | 职责 |
|---|---|
| `world.gd` | 地图、地形、家具、地面物品、容器 |
| `turn_scheduler.gd` | 能量/行动点；玩家/AI/需求/状态；1 回合≈1 秒 |
| `actor.gd` | HP/速度/需求/背包/装备/状态/AI |
| `item.gd` | 原型+实例；组件/改装/耐久/充能 |
| `action.gd` | 走/打/用/搜/开/砸/制作/读/睡/等待；成本/校验/效果 |
| `crafting.gd` | 配方/工具/工作台/时间 |
| `combat.gd` | 命中/伤害/护甲 |
| `needs.gd` | 饥饿/口渴/感染 |
| `perception.gd` | FOV/光/噪音/记忆 |
| `ai.gd` | 游荡/调查/追击/攻击/逃跑 |
| `save.gd` | JSON；种子+命令日志 |
| `content_db.gd` | 加载/校验 JSON；catalog |

## 4. 回合调度

CDDA 不是严格的玩家/敌人轮流，而是**能量累积**：每个动作花 moves，角色有速度，
每回合 `moves += speed`，谁攒得多谁一回合里动得多（`src/creature.cpp:488-495`）。

- 单位：moves。100 moves ≈ 1 回合 ≈ 1 秒；1 分钟 = 60 回合。
- 玩家输入时游戏暂停；没有实时时钟。
- 灰盒现在已经是这个模型：每个 `Actor` 有 `moves`/`speed`；
  走 100、搜 50、用 50、等 100；`World.perform(actor, action)` 是唯一入口。
- 玩家动到 `moves < 50`（最便宜的动作）时，`World.settle()` 推进世界回合，
  所有活着的 Actor 拿到自己的 `speed`——顺序同 CDDA 的 `game::do_turn()`
  （玩家先动完 → 世界推进 → 怪物动）。
- 下一步：`_run_monsters()` 里接 `while moves > 0: plan(); step();`，
  速度 150 的奔跑者自然一回合走 1.5 步，不需要写先攻队列。

## 5. 数据边界

**铁律：UI 只读玩家认知，不读真实世界。**

- `World` 是真实状态：所有敌人、所有物品、地图全图。
- `PlayerView`（下一步）是玩家认知：`visible`/`seen`、已知敌人、最后已知位置。
- 灰盒现在用 `seen`/`visible` 两套字典；敌人还没有；加敌人时不要在 `_draw` 里直接读 `world.enemies`。

## 6. 确定性

- 每子系统独立 `RandomNumberGenerator`；种子从 run seed 派生。
- 玩家每条命令进 `command_log`；`seed + command_log = 回放`。
- 最终状态 hash = Frozen Oracle；规则改动导致 hash 变化时测试红，人来决定。
- 存档 = profile + run seed + command log（或完整 state）；灰盒先存 state。

## 7. 内容

- `content/items.json` 现在 20 件；下一步 `recipes.json`、`monsters.json`、`maps/*.json`。
- `content_db.gd` 加载 → 校验 → catalog；未知 id/缺字段/负数值**加载时报错**。
- 测试：每个 item/recipe/monster/map 的引用都存在；每个掉落表能落地。

## 8. 场景 / 搜打撤后面怎么加

- 新增 `Scenario`：地图 + 出生点 + 出口 + 倒计时/雾 + 带出规则。
- 新增 `Stash/Profile`：带出的物品进仓库；死亡丢携带。
- 核心的 `world/action/turn/item/needs` 一行不改。
- 雾/倒计时作为 `Scenario` 的 `WorldModifier`；带出作为 `Scenario` 的 `on_extract`。

**核心不需要知道“搜打撤”这个词。**

## 9. 测试

| 套件 | 问什么 |
|---|---|
| `test_world` | 地图尺寸/出生点/撞墙/AP/搜刮/使用/需求/存档往返 |
| 下一步 `test_combat` | 命中/伤害/护甲/致死 |
| 下一步 `test_crafting` | 配方/工具/材料/产出 |
| 下一步 `test_content` | 未知 id/缺字段/负数值加载报错 |
| 下一步 `test_replay` | seed + command_log → 同 hash |

跑法：

```
Godot... --headless --path . --import
Godot... --headless --path . res://tests/test_runner.tscn
```

## 10. 当前灰盒 vs 目标

| 项 | 灰盒现在 | 目标 |
|---|---|---|
| 地图 | 手写 48×32 | 数据驱动，多张图 |
| 回合 | 每个 Actor 有 moves/speed，`_run_monsters()` 里 `while moves >= 100` | 同左 + NPC/载具 |
| 视野 | 半径 8 + Bresenham；怪物用同一个 `has_los` | FOV/光/噪音/记忆 |
| 物品 | 20 件数据 + 地面物品 | 原型+实例、组件/改装/耐久 |
| 需求 | 饥饿/口渴/感染 | 同左 + 状态效果 |
| 战斗 | 近战：命中 85%、伤害取最好的家伙、护甲减法 | 远程/格挡/技能 |
| 敌人 | 3 种 + `plan()`/`step()` 脑 + 门当障碍 | 行为树、群体包抄 |
| 目标 | 修电台 5 回合 → 守 10 回合 → 通关 | 多场景/搜打撤 |
| 制作 | 无 | 10 配方 |
| 存档 | state JSON（含 run_seed + rng state） | seed + command log 回放 |
| 场景 | 无 | Scenario，搜打撤后加 |

## 11. Web / 多端

- **Web**：Godot 4.6 GDScript + GL Compatibility；`user://` 走 IndexedDB；
  没有原生文件对话框；音频要一次点击；需要导出模板。
- **多端**：一个工程、多个预设；`tools/build_all.py` 顺序导出 Web/Windows/Linux；
  macOS/Android/iOS 要各自 SDK/签名（iOS/macOS 还要 Mac）。
- 不是一份二进制跑所有端；每个目标一个构建。
