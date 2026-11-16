"""把现在的正方形贴图转成等距（2:1 菱形）贴图，供 45° 视角渲染用。

原理：俯视的方形地砖在 2:1 等距投影下就是一个 64×32 的菱形。
所以对每张 32×32 的方块贴图做一次仿射变换，就能得到对应的菱形地板；
墙体的顶面同理，侧面在渲染时用深色多边形补。

输入：content/tiles/{tileset.png,tiles.json}
输出：content/tiles/iso.png + iso.json（每张菱形 64×32，横向排一行）

用法：python tools/build_iso.py
"""

import json
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
TILES_DIR = os.path.join(PROJECT, "content", "tiles")

SRC_SIZE = 32
ISO_W, ISO_H = 64, 32

# 正方形 (x,y) 在菱形里的位置。PIL 的 AFFINE 是「输出像素 → 输入像素」。
# 推导：菱形顶点 (32,0)→源(0,0)，左 (0,16)→(0,32)，右 (64,16)→(32,0)，下 (32,32)→(32,32)
AFFINE = (0.5, 1.0, -16.0, -0.5, 1.0, 16.0)

# 需要转的方块名（对应 tiles.json 里的 key）。
NAMES = ["floor", "pavement", "wall", "rock", "door_closed", "door_open"]


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def cut_square(atlas, cell, inset=2):
    """裁出 32×32 的一格，并往里收几像素再放大回去。

    UltiCa 的地砖自带一圈暗边（做缝用的），正着看不明显，一拉成菱形就是明显的黑缝。
    收掉 2px 边再铺，菱形之间才能接上。
    """
    x, y = int(cell[0]) * SRC_SIZE, int(cell[1]) * SRC_SIZE
    box = (x + inset, y + inset, x + SRC_SIZE - inset, y + SRC_SIZE - inset)
    return atlas.crop(box).resize((SRC_SIZE, SRC_SIZE), Image.BICUBIC)


def harden_alpha(image, threshold=110):
    """把半透明边缘压成 0/255，菱形之间才不会露缝。"""
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            pixels[x, y] = (r, g, b, 255 if a >= threshold else 0)
    return image


def main():
    meta = load_json(os.path.join(TILES_DIR, "tiles.json"))
    atlas = Image.open(os.path.join(TILES_DIR, meta["tileset"])).convert("RGBA")
    cells = meta["tiles"]

    out = Image.new("RGBA", (ISO_W * len(NAMES), ISO_H), (0, 0, 0, 0))
    index = {}
    for i, name in enumerate(NAMES):
        if name not in cells or not cells[name]:
            print("跳过（没有这张图）：%s" % name)
            continue
        square = cut_square(atlas, cells[name][0])
        diamond = square.transform((ISO_W, ISO_H), Image.AFFINE, AFFINE, resample=Image.BICUBIC)
        # 双三次插值会把边缘插成半透明，铺起来就有黑缝；这里把 alpha 拉成硬边。
        diamond = harden_alpha(diamond)
        out.alpha_composite(diamond, (i * ISO_W, 0))
        index[name] = i

    out.save(os.path.join(TILES_DIR, "iso.png"))
    with open(os.path.join(TILES_DIR, "iso.json"), "w", encoding="utf-8") as fh:
        json.dump({
            "image": "iso.png",
            "width": ISO_W,
            "height": ISO_H,
            "tiles": index,
        }, fh, ensure_ascii=False, indent=2)
    print("等距贴图：%d 张 -> %s（%d×%d）"
          % (len(index), os.path.join(TILES_DIR, "iso.png"), out.width, out.height))


if __name__ == "__main__":
    main()
