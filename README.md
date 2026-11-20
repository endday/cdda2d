# CDDA2D

A 2D top-down, turn-based survival prototype in **Godot 4.6 / pure GDScript**.
CDDA-like systems, deliberately small scope: one town block, one survivor,
20 items, 3 needs, energy turns, FOV, loot, enemies, combat, one objective.

**Play in a browser:** <https://endday.github.io/cdda2d/>

This is the **greybox** — it proves the skeleton, not the whole game.

## Run

```
D:\project\ai-project\Godot_v4.6-stable_win64.exe --path D:\project\ai-project\cdda2d
```

Or open the folder in the Godot editor and press F5. Main scene: `scenes/main.tscn`.

## Test

```
D:\project\ai-project\Godot_v4.6-stable_win64_console.exe --headless --path . --import
D:\project\ai-project\Godot_v4.6-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn
```

`--import` is needed once after adding new scripts (the `World` class).

## Build (Web + Windows + Linux)

```
python tools/build_all.py
python tools/build_all.py --only Web
python tools/serve_web.py        # http://127.0.0.1:8000/
```

Requires Godot 4.6 **export templates** (Editor > Manage Export Templates > Download).
The presets are in `export_presets.cfg`: `Web`, `Windows`, `Linux`.

## Controls

| Key | Action |
|---|---|
| WASD / arrows / hjkl | 连续方向移动；行动消耗按实际距离计算 |
| y u b n / 小键盘 1 3 7 9 | 对角方向移动 |
| ' 或 " | 切换跑步模式（移动行动点成本减半，消耗更多体力） |
| i | 背包（左键选物品，右键打开动作，i/Esc 关闭） |
| , | 捡起脚下的东西（CDDA 的 pickup） |
| e | 搜索附近容器，或在撤离点开始撤离 |
| . 或 5 或空格 | 等一回合（CDDA 的 pause） |
| F5 / F9 | save / load `user://save.json` |
| R | restart |

> 键位对齐 CDDA：`i` 背包、`.` 等待、`,` 捡东西、`e` 交互，都来自
> `data/raw/keybindings.json`。移动支持八方向，装备和物品动作从背包二级菜单选择。

鼠标左键点击地面位置会显示路线和本回合预计停点，再沿路线自动移动；点击容器会走过去搜索，点击敌人会攻击；地图右键检查目标。
R 打开整备页，勾选仓库物品后出发。背包中右键打开物品动作菜单，拖动物品到人形装备槽即可装备或换装。

## The run

1. 带着基础装备进入小镇，在住宅、诊所或警用装备箱搜索物资。
2. 物资自动进入背包，检查重量和体积，并在装备面板穿戴找到的装备。
3. 避开或击败敌人，沿地图向西移动到标记的撤离点。
4. 在撤离点按 E，撑过撤离时的世界响应后带着物品回到仓库。
5. 死亡或错过撤离窗口会失去本局携带物资，仓库内容保留。

## Status

Implemented: 48×32 town map, FOV + seen tiles, continuous-position movement with
cell-based collision and A* mouse pathfinding, searchable loot containers, raid timer and extraction, persistent stash,
food/water/meds, stamina and running, functional body/weapon/backpack equipment slots,
weight/volume limits, item action menus, save/load, content validation and tests.

Time model is CDDA's: every actor has `moves`; each turn `moves += speed`; actions cost
moves. Player and monsters go through one entry point, `World.perform(actor, action)`;
walk / loot / use / wait are `Action` objects (`src/core/actions.gd`).
Doors are data now: closed blocks, walking into one opens it. `world.command_log`
records every action for future replay.

Enemies are in: three zombie types (`content/monsters.json`), a `plan()`/`step()` brain
ported from CDDA's `monster::plan()`/`monster::move()`, and melee combat with hit /
damage / armor split into `src/core/combat.gd`. Walk into one to hit it. They cannot
open doors, so a closed door is a real defensive tool.

The radio tower defense objective remains as an optional legacy scenario. The primary
loop is now search, manage risk, and extract before the 180-turn window closes. Profile
stash is stored in user://profile.json.

Not yet: quick slots, selective container loot window, crafting, multiple maps,
deterministic replay.

## Art

Tiles are cut from CDDA's **UltiCa** tileset (CC BY-SA 3.0) by `tools/extract_tiles.py`:
25 terrain/item sprites plus a 2-frame actor sheet. See `content/tiles/CREDITS.md`
for provenance and what the license means — short version: keep the attribution,
and art derived from it stays CC BY-SA.

```
python tools/extract_tiles.py                 # re-cut the atlas (needs the source sheets)
Godot... --path . --script res://tools/shot.gd   # write a screenshot to build/shot.png
Godot... --headless --path . --script res://tools/sim.gd -- runs=12   # balance sim
```

Balance numbers and what is still a guess live in [`docs/balance.md`](docs/balance.md).

## Deploy (GitHub Pages)

The playable build lives on the `gh-pages` branch and is served at
<https://endday.github.io/cdda2d/>.

```
python tools/build_all.py --only Web
# copy build/web/* into a clean branch, then force-push it
```

Notes: GitHub Pages serves `.wasm` as `application/wasm`, and the export is
single-threaded (`variant/thread_support=false`), so no COOP/COEP headers are needed.
After deploying, bump the URL query (`?v=2`) or hard-refresh — the browser caches
`index.pck` / `index.wasm` for a few minutes.

## License

- **Code** (`src/`, `scenes/`, `tests/`, `tools/`): © the author, all rights reserved
  for now — no license has been granted yet.
- **Art**: the tiles in `content/tiles/` are cut from Cataclysm: DDA's **UltiCa**
  tileset, **CC BY-SA 3.0** (see `content/tiles/CREDITS.md` and `CDDA-LICENSE.txt`).
  Attribution: *Tiles by the Cataclysm: Dark Days Ahead community (UltiCa), CC BY-SA 3.0.*
  Anything derived from those tiles must stay CC BY-SA 3.0.

## Web and multi-platform

- **Web: yes.** GDScript + GL Compatibility; `user://` maps to IndexedDB; no native
  file dialogs; audio may need a click. Build with `python tools/build_all.py --only Web`,
  serve with `python tools/serve_web.py` (COOP/COEP headers included).
- **Multi-platform: yes, one project, multiple presets.** `build_all.py` exports
  Web + Windows + Linux sequentially. macOS / Android / iOS need their own SDKs,
  signing and (for iOS/macOS) a Mac; add presets later.
- It is **not** one binary that runs everywhere; each target gets its own build.

## Next

1. Add quick slots and a container loot-selection window.
2. Add crafting and more CDDA-style item interactions.
3. Add deterministic replay commands and state-hash tests.
