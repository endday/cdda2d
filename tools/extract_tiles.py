"""从 CDDA 的 UltiCa tileset 里切出本项目要用的精灵，拼成小图集。

源：Cataclysm-DDA 0.H 的 gfx/UltimateCataclysm/{normal,human_body_plus}.png
    + tile_config.json（精灵 id → 全局索引 → 表内槽位）。
许可证：CC BY-SA 3.0（见 content/tiles/CREDITS.md），这个脚本只是裁切，不改画。

用法（先按 docs 里的说明把源文件放到 _ref/art/）：
    python tools/extract_tiles.py
"""

import json
import os
import shutil

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
ART = os.path.join(PROJECT, "..", "_ref", "art")
OUT = os.path.join(PROJECT, "content", "tiles")

# 0.H 里这些图的尺寸（PNG 头里读出来的，槽位数 = (w/sw)*(h/sh)）。
# 顺序必须和 tile_config.json 的 tiles-new 一致，否则全局索引会错。
SHEET_DIMS = {
    "small.png": (320, 1940),
    "normal.png": (512, 12288),
    "tall.png": (512, 2368),
    "human_body.png": (512, 5220),
    "human_body_plus.png": (512, 1680),
    "centered.png": (768, 64),
    "large.png": (512, 1984),
    "large_ridden.png": (192, 64),
    "huge.png": (256, 768),
    "giant.png": (384, 2016),
    "incomplete_small.png": (320, 20),
    "incomplete.png": (512, 1728),
}

# 本项目要的方块（32×32）。顺序就是图集里的顺序。
# 地形各切 4 个变体（CDDA 的 multitile 是连续 4 个槽位），按坐标轮换，避免一眼看出方格。
VARIANTS = {
    "floor": ("t_floor", 4),
    "pavement": ("t_pavement", 4),
    "wall": ("t_brick_wall", 4),
    "rock": ("t_rock", 4),
}

# 单张图：门和物品。
TILES = {
    "door_closed": ["t_door_c"],          # fg + bg 合成
    "door_open": ["t_door_o"],
    "item_crowbar": ["crowbar"],
    "item_knife": ["knife_combat"],
    "item_pistol": ["glock_19"],
    "item_ammo": ["9mm"],
    "item_bandage": ["bandages"],
    "item_medkit": ["1st_aid"],
    "item_antibiotics": ["antibiotics"],
    "item_water": ["water_clean"],
    "item_canned_food": ["can_food"],
    "item_purifier": ["water_purifier"],
    "item_flashlight": ["flashlight"],
    "item_battery": ["battery"],
    "item_lockpick": ["crude_picklock"],
    "item_tape": ["duct_tape"],
    "item_wire": ["wire"],
    "item_radio_part": ["radio"],
    "item_keycard": ["data_card"],
    "item_armor": ["armor_riot"],
    "item_backpack": ["backpack"],
    "item_stimulant": ["caffeine"],
}

# 角色是 32×48（脚在格子底部）。UltiCa 的身体是裸的，衣服是单独一层，所以要叠。
ACTORS = {
    "player": [
        "player_male",
        "overlay_male_worn_jeans",
        "overlay_male_worn_tshirt",
        "overlay_male_worn_sneakers",
    ],
    "shambler": ["mon_zombie"],
    "runner": ["mon_zombie_runner"],
    "brute": ["mon_zombie_brute"],
}

CELL = 32
ACTOR_W, ACTOR_H = 32, 48
COLUMNS = 8


def load_config():
    with open(os.path.join(ART, "tile_config.json"), encoding="utf-8") as fh:
        return json.load(fh)


def build_index(cfg):
    """id -> (sheet, fg, bg)；同时算每张 sheet 的起始槽位。"""
    tile_info = cfg["tile_info"][0]
    default_w, default_h = tile_info["width"], tile_info["height"]
    bases = {}
    offset = 0
    for sheet in cfg["tiles-new"]:
        name = sheet["file"]
        sw = sheet.get("sprite_width") or default_w
        sh = sheet.get("sprite_height") or default_h
        if name in SHEET_DIMS:
            width, height = SHEET_DIMS[name]
            slots = (width // sw) * (height // sh)
        else:
            slots = len(sheet.get("tiles", []))
        bases[name] = (offset, slots, sw, sh)
        offset += slots

    lookup = {}
    for sheet in cfg["tiles-new"]:
        for entry in sheet.get("tiles", []):
            ids = entry.get("id")
            ids = [ids] if isinstance(ids, str) else (ids or [])
            for one in ids:
                lookup.setdefault(one, (sheet["file"], entry.get("fg"), entry.get("bg")))
    return lookup, bases


def sprite_index(fg):
    """fg 可能是 int、list（权重）、或者缺失。取第一个。"""
    if isinstance(fg, int):
        return fg
    if isinstance(fg, list) and fg:
        first = fg[0]
        return first.get("sprite") if isinstance(first, dict) else int(first)
    return None


def cut_index(sheet_cache, lookup, bases, sprite_id, index):
    """按全局索引切一张图；仿照 CDDA 的槽位算法。"""
    if sprite_id not in lookup:
        raise SystemExit("tileset 里找不到精灵：%s" % sprite_id)
    sheet_name = lookup[sprite_id][0]
    start, slots, sw, sh = bases[sheet_name]
    local = index - start
    if local < 0 or local >= slots:
        raise SystemExit("%s 的索引 %d 不在 %s 的槽位范围 [%d,%d) 里"
                         % (sprite_id, index, sheet_name, start, start + slots))
    if sheet_name not in sheet_cache:
        sheet_cache[sheet_name] = Image.open(os.path.join(ART, sheet_name)).convert("RGBA")
    image = sheet_cache[sheet_name]
    width = image.width // sw
    col, row = local % width, local // width
    return image.crop((col * sw, row * sh, col * sw + sw, row * sh + sh))


def cut(sheet_cache, lookup, bases, sprite_id):
    found = lookup.get(sprite_id)
    if found is None:
        raise SystemExit("tileset 里找不到精灵：%s" % sprite_id)
    index = sprite_index(found[1])
    if index is None:
        raise SystemExit("精灵没有 fg：%s" % sprite_id)
    return cut_index(sheet_cache, lookup, bases, sprite_id, index)


def cut_with_bg(sheet_cache, lookup, bases, sprite_id):
    """门这类两层精灵：先 bg 再 fg。"""
    sheet_name, _fg, bg = lookup[sprite_id]
    index = sprite_index(bg)
    canvas = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    if index is not None:
        start, slots, sw, sh = bases[sheet_name]
        local = index - start
        if 0 <= local < slots:
            if sheet_name not in sheet_cache:
                sheet_cache[sheet_name] = Image.open(os.path.join(ART, sheet_name)).convert("RGBA")
            image = sheet_cache[sheet_name]
            width = image.width // sw
            col, row = local % width, local // width
            canvas.alpha_composite(image.crop((col * sw, row * sh, col * sw + sw, row * sh + sh)))
    canvas.alpha_composite(cut(sheet_cache, lookup, bases, sprite_id))
    return canvas


def main():
    cfg = load_config()
    lookup, bases = build_index(cfg)
    cache = {}
    os.makedirs(OUT, exist_ok=True)

    entries = []  # (名字, [图])
    for name, (sprite_id, count) in VARIANTS.items():
        first = sprite_index(lookup[sprite_id][1])
        images = [cut_index(cache, lookup, bases, sprite_id, first + i) for i in range(count)]
        entries.append((name, images))
    for name, ids in TILES.items():
        sprite_id = ids[0]
        if name.startswith("door_"):
            entries.append((name, [cut_with_bg(cache, lookup, bases, sprite_id)]))
        else:
            entries.append((name, [cut(cache, lookup, bases, sprite_id)]))

    total = sum(len(images) for _, images in entries)
    rows = (total + COLUMNS - 1) // COLUMNS
    atlas = Image.new("RGBA", (COLUMNS * CELL, rows * CELL), (0, 0, 0, 0))
    positions = {}
    slot = 0
    for name, images in entries:
        cells = []
        for image in images:
            # 物品在 small.png 里是 20×20，地形是 32×32；统一居中放进格子。
            offset = ((CELL - image.width) // 2, (CELL - image.height) // 2)
            atlas.alpha_composite(image,
                                  ((slot % COLUMNS) * CELL + offset[0],
                                   (slot // COLUMNS) * CELL + offset[1]))
            cells.append([slot % COLUMNS, slot // COLUMNS])
            slot += 1
        positions[name] = cells
    atlas.save(os.path.join(OUT, "tileset.png"))

    actor_atlas = Image.new("RGBA", (len(ACTORS) * ACTOR_W, ACTOR_H), (0, 0, 0, 0))
    actor_positions = {}
    for i, (name, layers) in enumerate(ACTORS.items()):
        frame = Image.new("RGBA", (ACTOR_W, ACTOR_H), (0, 0, 0, 0))
        # 第一层的 bg 是影子，先铺上。
        shadow = lookup[layers[0]][2]
        shadow_index = sprite_index(shadow)
        if shadow_index is not None:
            frame.alpha_composite(cut_index(cache, lookup, bases, layers[0], shadow_index))
        for layer in layers:
            frame.alpha_composite(cut(cache, lookup, bases, layer))
        actor_atlas.alpha_composite(frame, (i * ACTOR_W, 0))
        actor_positions[name] = i
    actor_atlas.save(os.path.join(OUT, "actors.png"))

    meta = {
        "tile_size": CELL,
        "tileset": "tileset.png",
        "columns": COLUMNS,
        "tiles": positions,
        "actors": {"image": "actors.png", "width": ACTOR_W, "height": ACTOR_H, "frames": actor_positions},
    }
    with open(os.path.join(OUT, "tiles.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)

    license_src = os.path.join(ART, "LICENSE.txt")
    if os.path.exists(license_src):
        shutil.copyfile(license_src, os.path.join(OUT, "CDDA-LICENSE.txt"))

    print("图集：%d 张（地形变体 + 门 + 物品）+ %d 个角色 -> %s" % (total, len(ACTORS), OUT))


if __name__ == "__main__":
    main()
