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
| WASD / arrows / hjkl | 走一格（100 moves）；按住连续走 |
| y u b n / 小键盘 7 9 1 3 | 斜走（141 moves，不能切墙角） |
| i | 背包（按字母使用，i/Esc 关闭） |
| , | 捡起脚下的东西（CDDA 的 pickup） |
| e | 交互：站在塔上就是修电台，旁边有门就推开（CDDA 的 examine） |
| . 或 5 或空格 | 等一回合（CDDA 的 pause） |
| F5 / F9 | save / load `user://save.json` |
| R | restart |

> 键位对齐 CDDA：`i` 背包、`.` 等待、`,` 捡东西、`e` 交互，都来自
> `data/raw/keybindings.json`。移动仍是 4 向（CDDA 是 8 向）。

## The run

1. 在街上醒来，往北进建筑搜刮：**零件 / 电池 / 电线** 是电台要的三件东西。
2. 东西在第三栋建筑里，那儿有只壮汉守着。
3. 回街上、沿电台塔的通道下去，站到塔里按 **e** 开始修（5 回合，期间别动）。
4. 修通后守 **10 回合**：每 2 回合从塔内冒一只蹒跚。
5. 死了看撑到第几回合；活着就是通关。

## Status

Implemented: 48×32 town map, FOV + seen tiles, movement, loot, food/water/meds,
hunger/thirst/infection tick, save/load, 20-item data table, tests.

Time model is CDDA's: every actor has `moves`; each turn `moves += speed`; actions cost
moves. Player and monsters go through one entry point, `World.perform(actor, action)`;
walk / loot / use / wait are `Action` objects (`src/core/actions.gd`).
Doors are data now: closed blocks, walking into one opens it. `world.command_log`
records every action for future replay.

Enemies are in: three zombie types (`content/monsters.json`), a `plan()`/`step()` brain
ported from CDDA's `monster::plan()`/`monster::move()`, and melee combat with hit /
damage / armor split into `src/core/combat.gd`. Walk into one to hit it. They cannot
open doors, so a closed door is a real defensive tool.

The objective is in: repair the radio tower (5 turns, any non-wait action interrupts —
CDDA's `player_activity` in miniature), then hold 10 turns while shamblers come down the
corridor. Win/lose both end the run.

Not yet: crafting, inventory grid UI, weight/size enforcement, multiple maps,
scenarios/extraction.

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

1. Enemies + combat + AI (same action system).
2. Crafting (10 recipes) and the radio objective.
3. Inventory grid + weight/size.
4. Content validation + deterministic replay test.
5. Play 3 runs; write the four J4 questions.
