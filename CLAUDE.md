# CDDA2D — 项目指引

2D 俯视、回合制、CDDA-like 生存原型。**Godot 4.6 + 纯 GDScript。**

> **目标**：先做「CDDA-like 的模拟骨架 + 一局 20~30 分钟的游戏」，不是完整 CDDA。
> 搜打撤后面当 `Scenario` 加；核心不需要知道“搜打撤”这个词。
> **当前状态**：灰盒 + 通用动作 + CDDA 式 energy 回合 + 敌人/战斗/AI + 电台目标 + UltiCa 贴图
> （一局能打通：搜零件 → 修电台 → 守 10 回合）。制作和背包格还没接。

## 六个原语（自由度从这里来）

1. **世界是数据**：每格地形/家具/物品；门、窗、容器、工作台都是数据，不是特判。
2. **动作是通用的**：走/打/用/搜/开/砸/制作/读/睡/等待；玩家和 AI 用同一套动作。
3. **物品是动词**：原型 + 实例；组件/改装/耐久/充能；使用/攻击/拆解/制作走同一套。
4. **时间是调度器**：能量/行动点；需求、制作、状态、AI 都挂在回合上。
5. **感知是数据边界**：FOV/光/噪音；UI 只读玩家认知，不读真实世界。
6. **内容是数据**：JSON/Resources；物品/配方/怪物/地图/场景都能加；加载时校验。

有这 6 个，**搜打撤只是“场景”**：一张图 + 出口 + 倒计时/雾 + 带出规则。

## 架构

```
src/core/        纯 GDScript，不碰 Godot 节点/场景
  world.gd       地图/物品/门/需求/回合/视野/存档；perform(actor, action) 是唯一动作入口
  actor.gd       能行动的东西：pos/hp/moves/speed/需求/背包（玩家和怪物同一个类）
  action.gd      瞬间动作基类：{cost, can(), apply()}
  actions.gd     走/搜/用/等/打；费用和效果都在动作自己身上
  item.gd        物品实例（原型 id + charges/active/damage）
  item_use.gd    物品动词注册表：use_methods 的 type → 处理器（CDDA iuse_actor 的微缩版）
  combat.gd      命中/伤害/护甲（纯函数，可单测）
  monster_brain.gd  plan() 选目标 + step() 一步一动作（照 CDDA monmove）
  content_db.gd  内容校验：缺字段/重复 id/负数/引用不存在
scenes/          适配层：main.tscn / main.gd（_draw 贴图、相机、HUD、输入）
content/         items.json（20 件）+ monsters.json（3 种）；tiles/ 是从 UltiCa 裁的图集（CC BY-SA 3.0）
tests/           test_runner.tscn + test_world/actions/combat/content
tools/           build_all.py（Web/Windows/Linux）+ serve_web.py
                 + extract_tiles.py（裁 tileset）+ shot.gd（截图）
```

**铁律**：

- `core` 不 import Godot；`scenes` 不写规则；`content` 是数据，加载时校验。
- UI 只读玩家认知（`seen`/`visible`/已知敌人），不读真实世界。
- 每子系统独立 `RandomNumberGenerator`，种子从 run seed 派生；不用全局 `randi`。
- `seed + command_log` 可回放；最终状态 hash 是 Frozen Oracle。
- 内容非法（未知 id/缺字段/负数值）**加载时报错**，不静默兜底。

## 当前灰盒做了什么

- 地图：48×32，主街（路面）+ 三栋建筑 + 电台塔；FOV 半径 8，`seen`/`visible` 两套。
- 时间：CDDA 那套，每个 Actor 每回合 `moves += speed`；走 100、搜 50、用 50、等 100。
  玩家动到 `moves < 50` 世界推进一回合；空格是「等」，不是「结束回合」。
- 动作：`World.perform(actor, action)`；走/搜/用/等/打五个动词，玩家和 AI 共用一条路径。
- 物品：**原型 + 实例 + 动词注册表**（照 CDDA 的 itype/item/use_methods）。
  `items.json` 只写数据；`ItemUse.register()` 加新玩法；World/UI/存档都不用改。
  加物品 = 加一条 JSON，`ContentDB` 会校验每个 `use_methods.type` 都注册过。
- 背包：`i` 打开，按字母使用；说明文字从 `use_methods` 推出来，不是写死的。
- 门：数据。关着挡路，撞上去会推开（花一次移动的时间），下一格才能过；怪不会开门。
- 敌人：3 种（蹒跚/奔跑者/壮汉），`MonsterBrain.plan()` 选目标、`step()` 一步一动作；
  速度 150 的怪一回合挪两步。撞上去就是打（bump attack）。
- 战斗：`Combat` 里命中 85%、伤害取身上最好的家伙、护甲做减法；武器伤害读 `items.json`。
- 目标：电台塔。带齐 零件/电池/电线 → 站到 `repair_site` 按 e → 修 5 回合
  （`world.activity`，动一下即打断）→ 通了之后守 10 回合，每 2 回合刷一只蹒跚 → 通关。
- 玩家：HP 100、饥饿/口渴/感染。
- 视觉：UltiCa 贴图；移动有平滑插值（指数平滑），相机跟随，HUD 有血条/需求条/目标提示。
- 内容：`content/monsters.json` + `ContentDB` 校验（缺字段/重复 id/负数/未注册动词都报）。
- 存档：F5/F9，`user://save.json`（version 5：物品存实例，不是 id 字符串）。
- 测试：World / Actions / Combat / Content / Objective / Font 六套，共 109 项检查。
- 构建：`export_presets.cfg` 有 Web/Windows/Linux；`tools/build_all.py`。

**还没做**：制作、背包格/重量、多地图、场景/搜打撤、音效、回放测试。

## 跑

```
# 玩
D:\project\ai-project\Godot_v4.6-stable_win64.exe --path D:\project\ai-project\cdda2d

# 测试（第一次先 --import）
D:\project\ai-project\Godot_v4.6-stable_win64_console.exe --headless --path . --import
D:\project\ai-project\Godot_v4.6-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn

# 构建
python tools/build_all.py
python tools/build_all.py --only Web
python tools/serve_web.py     # http://127.0.0.1:8000/
```

**Web**：GDScript + GL Compatibility 可导出；`user://` 走 IndexedDB；没有原生文件对话框；
音频要一次点击；需要 Godot 4.6 导出模板。
**多端**：一个工程、多个预设；`build_all.py` 顺序导出 Web/Windows/Linux；
macOS/Android/iOS 要各自 SDK/签名（iOS/macOS 还要 Mac），后面再加预设。

## 下一步（按顺序）

1. ~~敌人 + 战斗 + AI~~：已接（3 种怪、plan/step、bump attack、命中/伤害/护甲）。
2. ~~电台目标~~：已接（5 回合修理 + 守 10 回合 + 胜/败）。
3. **制作 + 背包格/重量**：10 个配方；6×4 + 20kg；物品尺寸/重量真正生效。
4. **内容校验 + 回放测试**：未知 id 加载报错；`seed + command_log` 同 hash。
5. **3 局试玩 + J4**：哪一刻想继续/想关掉/哪个决定难做/看不看得懂。

## 不做（第一版）

- 不做开放世界、多地图、载具、NPC 派系、基地建造、1000 件物品、身体部位、
  温度/疼痛/morale、技能树、联机、3D。
- 不做完整 CDDA；做“CDDA-like 骨架 + 一局内容”。完整 CDDA 是多年内容工程。

## 这个底子够不够

**够开始，不够承诺“完整 CDDA”。** 6 个原语 + 20 件物品 + 3 条需求 + 10 个配方
+ 4 种敌人 + 1 张图，足够做一局 20~30 分钟的切片；架构能长大，但内容/模拟是长尾。
第一版必须是一局能玩的游戏，不是一堆框架。
