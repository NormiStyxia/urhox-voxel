"""
诺米 YSM 风格方块角色 —— Blockbench 起手工程生成器

输出（同目录）:
  nomi.bbmodel    Blockbench 工程（Bedrock 实体格式，贴图已内嵌）
  nomi.geo.json   Bedrock geometry（YSM / Bedrock 通用）
  nomi.png        贴图（UV 128x128，像素密度 2x → 256x256）
  preview.png     正 / 侧 / 背 三视图预览（脚本自绘，用来快速检查）

坐标约定（Blockbench 空间）:
  单位 = 1/16 方块，脚底 y=0，角色面朝 -Z（north），角色右手 = +X（east）。
  导出 geo.json 时按 Bedrock 规则把 X 取反。

参考: Mivo 生成的「藏青碎条斗篷」YSM 三视图（图1）。头顶用阶梯层做圆，不做平顶。
"""
import base64
import io
import json
import math
import uuid
import zlib
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent
UV_W, UV_H = 128, 128
S = 2  # 贴图像素密度：每个 UV 单位 2 像素

# ---------------------------------------------------------------- palette
HAIR, HAIR_S, HAIR_D = (228, 232, 246), (200, 207, 230), (170, 178, 212)
SKIN, SKIN_S = (253, 228, 212), (238, 204, 190)
NAVY, NAVY_S, NAVY_D = (46, 62, 122), (35, 48, 98), (24, 32, 72)
WHITE, WHITE_S = (245, 247, 252), (212, 219, 236)
YEL, YEL_S = (246, 198, 62), (212, 158, 40)
EYE_D, EYE, EYE_L = (32, 38, 82), (70, 122, 214), (150, 190, 240)
BLUSH, MOUTH = (247, 184, 190), (196, 112, 120)


def rgba(c, a=255):
    return np.array([c[0], c[1], c[2], a], dtype=np.uint8)


def fill(w, h, c):
    a = np.zeros((h, w, 4), dtype=np.uint8)
    a[:, :] = rgba(c)
    return a


def shade(a, top=None, bottom=None):
    """顶行提亮、底行压暗，给方块一点体积感。"""
    if a.shape[0] >= 4:
        if top is not None:
            a[0, a[0, :, 3] > 0, :3] = top
        if bottom is not None:
            a[-1, a[-1, :, 3] > 0, :3] = bottom
    return a


def strands(w, h, base, dark, rng, every=3):
    """头发竖向发丝。"""
    a = fill(w, h, base)
    for x in range(w):
        if x % every == rng.integers(0, every):
            a[:, x, :3] = dark
    return a


def jag_bottom(a, rng, depth, minkeep=0):
    """底部锯齿透明，用于破斗篷、发梢。"""
    h, w = a.shape[:2]
    cut = 0
    for x in range(w):
        cut = int(np.clip(cut + rng.integers(-2, 3), 0, depth))
        if rng.random() < 0.15:
            cut = depth
        cut = max(cut, 0)
        if h - cut < minkeep:
            cut = h - minkeep
        if cut > 0:
            a[h - cut:, x, 3] = 0
    return a


def clear(w, h):
    return np.zeros((h, w, 4), dtype=np.uint8)


# ---------------------------------------------------------------- painters
# painter(face, w_px, h_px, rng) -> RGBA，行0=顶，列0=从外面看过去的左边

def p_solid(c, cs=None, cd=None, top_c=None):
    def f(face, w, h, rng):
        if face in ("up", "down"):
            return fill(w, h, top_c or cs or c)
        return shade(fill(w, h, c), bottom=cd)
    return f


# ---- 脸：对照 Mivo YSM 三视图（图1）逐格摆放
# 头 12x11 单位 → 24x22 px。行 r 的中心到下巴的高度 h = (22 - r - 0.5) / 2。
# 北面列 0 = 从正面看的左边 = 角色右侧（+X）。
LASH = (26, 26, 40)
IRIS_D, IRIS_M, IRIS_L, IRIS_P = (52, 66, 142), (88, 120, 198), (152, 178, 228), (36, 44, 104)
BROW = (182, 164, 170)

# 6x5 虹膜（行 13..17）。P=瞳孔竖线，W=下方高光；左眼版本，右眼水平镜像
IRIS = [
    "DDDDDD",
    "MMMMPM",
    "MMMMPM",
    "LMMMPM",
    "WLLLLM",
]


def p_head(face, w, h, rng):
    a = fill(w, h, SKIN)
    if face != "north":
        return a
    cmap = {"D": IRIS_D, "M": IRIS_M, "L": IRIS_L, "P": IRIS_P, "W": WHITE}
    for x0, mirror in ((3, False), (15, True)):
        rows = [r[::-1] if mirror else r for r in IRIS]
        for r, row in enumerate(rows):
            for c, ch in enumerate(row):
                a[13 + r, x0 + c, :3] = cmap[ch]
        # 上睫毛：一整条黑横杠，外眼角多出 1px 并加厚
        outer = x0 - 1 if not mirror else x0 + 6
        a[12, min(x0, outer):max(x0 + 6, outer + 1), :3] = LASH
        a[13, outer, :3] = LASH
    # 眉毛（细，偏内侧，刘海下沿刚好露出）
    a[10, 7:9, :3] = BROW
    a[10, 15:17, :3] = BROW
    # 腮红 + 小嘴
    a[18, 4:7, :3] = BLUSH
    a[18, 17:20, :3] = BLUSH
    a[20, 11:13, :3] = (216, 146, 152)  # 小嘴：浅一点，图1 里几乎只是一道线
    # 刘海投影
    return a


def bang_bottom(ax):
    """刘海下沿到下巴的高度（单位）。ax = |x|，对照图1：两侧鬓发盖到下巴，
    眼睛上方露额头和眉毛，中间几缕尖刘海垂到两眼之间。"""
    if ax > 4.8:
        return 0.0
    if ax > 2.6:
        return 7.3 - (4.8 - ax) * 0.6
    if ax > 1.4:
        return 6.0
    if ax > 1.0:
        return 4.8
    if ax > 0.5:
        return 4.2
    return 3.4


def p_hair_shell(face, w, h, rng):
    if face == "down":
        return clear(w, h)
    a = strands(w, h, HAIR, HAIR_S, rng)
    if face == "up":
        a[:, w // 2, :3] = HAIR_D  # 发旋中缝
        return a
    if face != "north":
        # 侧面和背面盖到脸颊以下，只留发梢 1px 锯齿
        return jag_bottom(a, rng, 1)
    # 外壳 13x12 单位（含 inflate）→ 24x22 px；底边 = 下巴
    out = clear(w, h)
    for x in range(w):
        ax = abs(6.5 - (x + 0.5) * 13 / w)
        lim = bang_bottom(ax)
        last = -1
        for y in range(h):
            hy = (h - y - 0.5) * 12 / h  # 该行到外壳底边（下巴）的高度
            if hy >= lim:
                out[y, x] = a[y, x]
                last = y
        if 0 <= last < h - 1:
            out[last, x, :3] = HAIR_D  # 发梢描边
    # 刘海高光
    out[2:4, 6:9, :3] = np.where(out[2:4, 6:9, 3:4] > 0, np.array(WHITE), out[2:4, 6:9, :3])
    return out


def p_cloak_shoulder(face, w, h, rng):
    a = p_cloak(face, w, h, rng, depth=0)
    if face == "north":
        # 斗篷前襟敞开，中间露出水手领
        a[:, int(w * 0.3):int(w * 0.7), 3] = 0
    return a


def p_front_lock(face, w, h, rng):
    if face == "up":
        return fill(w, h, HAIR)
    if face == "down":
        return clear(w, h)
    a = strands(w, h, HAIR, HAIR_S, rng)
    return jag_bottom(a, rng, 5, minkeep=h // 2)


def p_braid(face, w, h, rng):
    if face == "down":
        return fill(w, h, HAIR_S)
    if face == "north":
        # 正面是光滑的刘海发根，辫子只在两侧和头顶露出来（对照图1）
        a = strands(w, h, HAIR, HAIR_S, rng)
        a[:, :4, :3] = HAIR_S
        a[:, -4:, :3] = HAIR_S
        return a
    a = fill(w, h, HAIR)
    for y in range(h):
        for x in range(w):
            k = (x + y) % 4
            a[y, x, :3] = (HAIR, HAIR, HAIR_S, HAIR_D)[k]
    return a


def p_hair_plain(face, w, h, rng):
    if face == "down":
        return fill(w, h, HAIR_S)
    return strands(w, h, HAIR, HAIR_S, rng)


def p_hair_hang(face, w, h, rng):
    if face == "up":
        return fill(w, h, HAIR)
    if face == "down":
        return clear(w, h)
    return jag_bottom(strands(w, h, HAIR, HAIR_S, rng), rng, 4, minkeep=h // 2)


def p_bun(face, w, h, rng):
    a = fill(w, h, HAIR)
    a[0, :, :3] = HAIR_S
    a[-1, :, :3] = HAIR_D
    a[:, 0, :3] = HAIR_S
    a[:, -1, :3] = HAIR_S
    a[h // 2 - 1:h // 2 + 1, w // 2 - 1:w // 2 + 1, :3] = HAIR_D
    return a


def p_ribbon(face, w, h, rng):
    a = clear(w, h)
    # 两条飘带：左右两列从上往下，下端斜切
    for y in range(h):
        for x in range(w):
            left = x < w // 2 - (y > h // 2)
            right = x >= w // 2 + (y > h // 2)
            if y < 2 or left or right:
                a[y, x] = rgba(YEL if x % (w // 2) else YEL_S)
    a[-1, :, 3] = 0
    a[-1, 0, 3] = 255
    a[-1, -1, 3] = 255
    return a


def p_ahoge(face, w, h, rng):
    a = clear(w, h)
    # 6x8 px 的一撮弯呆毛
    shape = [
        "...###",
        "..##..",
        "..#...",
        "..#...",
        "..#...",
        ".##...",
        ".##...",
        ".##...",
    ]
    for y, row in enumerate(shape):
        for x, ch in enumerate(row):
            if ch == "#":
                a[y, x] = rgba(HAIR if y > 0 else HAIR_S)
    return a


def p_torso(face, w, h, rng):
    if face in ("up", "down"):
        return fill(w, h, WHITE_S)
    a = fill(w, h, WHITE)
    if face == "north":
        cx = (w - 1) / 2
        for y in range(h):
            for x in range(w):
                d = abs(x - cx)
                v = (9 - y) * 0.75  # V 领开口半宽，往下收尖
                if y < 9 and d >= v:
                    a[y, x, :3] = NAVY
                    if abs(d - v - 1.2) < 0.6:
                        a[y, x, :3] = WHITE_S  # 领边白线
        return a
    if face == "south":
        a[:9, :, :3] = NAVY
        a[7, :, :3] = WHITE_S
    return a


def p_tie(face, w, h, rng):
    a = clear(w, h)
    shape = [
        ".####.",
        "######",
        ".####.",
        "..##..",
        ".####.",
        "##..##",
    ]
    for y, row in enumerate(shape):
        for x, ch in enumerate(row):
            if ch == "#":
                a[y, x] = rgba(YEL if (x + y) % 3 else YEL_S)
    return a


def p_skirt(face, w, h, rng):
    if face in ("up", "down"):
        return fill(w, h, NAVY_D)
    a = fill(w, h, NAVY)
    for x in range(0, w, 3):
        a[:, x, :3] = NAVY_S  # 百褶
    a[h - 4:h - 2, :, :3] = WHITE  # 裙摆白线
    a[-1, :, :3] = NAVY_D
    return a


def p_underskirt(face, w, h, rng):
    if face in ("up", "down"):
        return fill(w, h, WHITE_S)
    a = fill(w, h, WHITE)
    for x in range(1, w, 3):
        a[:, x, :3] = WHITE_S
    return a


def p_leg(face, w, h, rng):
    if face in ("up", "down"):
        return fill(w, h, SKIN)
    a = fill(w, h, SKIN)
    # 腿 0..11 单位；y < 8.5 是白袜（行 >= (11-8.5)*S）
    a[int((11 - 8.5) * S):, :, :3] = WHITE
    a[int((11 - 8.5) * S), :, :3] = WHITE_S
    return a


def p_boot(face, w, h, rng):
    if face == "up":
        return fill(w, h, NAVY_S)
    if face == "down":
        return fill(w, h, NAVY_D)
    a = fill(w, h, NAVY)
    a[0, :, :3] = NAVY_S
    a[-2:, :, :3] = NAVY_D  # 鞋底
    if face == "north":
        for y in range(1, h - 3, 2):
            a[y, w // 2 - 1:w // 2 + 1, :3] = WHITE_S  # 鞋带
    return a


def p_arm(face, w, h, rng):
    if face == "up":
        return fill(w, h, NAVY)
    if face == "down":
        return fill(w, h, SKIN)
    a = fill(w, h, NAVY)
    a[h - 3:, :, :3] = SKIN  # 手
    return a


def p_sleeve(face, w, h, rng):
    if face == "up":
        return fill(w, h, NAVY)
    if face == "down":
        return clear(w, h)
    a = fill(w, h, NAVY)
    a[h - 4, :, :3] = WHITE
    a[h - 2, :, :3] = WHITE
    a[-1, :, :3] = NAVY_D
    return a


def p_cloak(face, w, h, rng, depth=5):
    if face == "up":
        return fill(w, h, NAVY_S)
    if face == "down":
        return fill(w, h, NAVY_D)
    base = NAVY_D if face == "north" else NAVY  # 内侧更暗
    a = fill(w, h, base)
    for x in range(w):
        if rng.random() < 0.25:
            a[:, x, :3] = NAVY_S if base == NAVY else NAVY_D
    return jag_bottom(a, rng, depth)


def p_cloak_back(face, w, h, rng):
    a = p_cloak(face, w, h, rng, depth=6)
    if face == "south":
        # 帽兜轮廓（上缘的倒梯形）
        for y in range(10):
            half = 9 - y * 0.6
            for x in range(w):
                if abs(x - (w - 1) / 2) <= half and a[y, x, 3]:
                    a[y, x, :3] = NAVY_S
        a[10, int(w / 2 - 3):int(w / 2 + 3), :3] = NAVY_D
    return a


def p_cloak_strip(face, w, h, rng):
    if face == "up":
        return fill(w, h, NAVY_S)
    if face == "down":
        return clear(w, h)
    a = fill(w, h, NAVY if face != "north" else NAVY_D)
    return jag_bottom(a, rng, h - 2, minkeep=2)


def p_string(face, w, h, rng):
    a = clear(w, h)
    a[:, w // 2 - 1:w // 2 + 1] = rgba(WHITE)
    a[-2:, :] = rgba(WHITE_S)
    return a


def p_hood(face, w, h, rng):
    if face == "down":
        return fill(w, h, NAVY_D)
    a = fill(w, h, NAVY_S)
    a[0, :, :3] = NAVY
    a[-1, :, :3] = NAVY_D
    return a


# ---------------------------------------------------------------- model
# bone: name, parent, pivot
BONES = [
    ("root", None, [0, 0, 0]),
    ("leg_right", "root", [2, 11, 0]),
    ("leg_left", "root", [-2, 11, 0]),
    ("body", "root", [0, 11, 0]),
    ("skirt", "body", [0, 13, 0]),
    ("cloak", "body", [0, 18, 0]),
    ("cloak_strip_1", "cloak", [-5, 6, 4.1]),
    ("cloak_strip_2", "cloak", [-1.5, 6, 4.1]),
    ("cloak_strip_3", "cloak", [2, 6, 4.1]),
    ("cloak_strip_4", "cloak", [5, 6, 4.1]),
    ("cloak_strip_5", "cloak", [6, 6, -1.5]),
    ("cloak_strip_6", "cloak", [-6, 6, -1.5]),
    ("arm_right", "body", [5.5, 17, 0]),
    ("arm_left", "body", [-5.5, 17, 0]),
    ("head", "body", [0, 19, 0]),
    ("hair", "head", [0, 27, 0]),
    ("bun_right", "hair", [8, 23.5, 0]),
    ("bun_left", "hair", [-8, 23.5, 0]),
]

# cube: name, bone, from[x,y,z], size[w,h,d], inflate, painter
CUBES = [
    # 腿 / 靴（腿 11 高，靴 4 高，中间露白袜）
    ("leg_r", "leg_right", [0.5, 0, -1.5], [3, 11, 3], 0, p_leg),
    ("boot_r", "leg_right", [0.5, 0, -2.5], [3, 4, 4], 0.25, p_boot),
    ("leg_l", "leg_left", [-3.5, 0, -1.5], [3, 11, 3], 0, p_leg),
    ("boot_l", "leg_left", [-3.5, 0, -2.5], [3, 4, 4], 0.25, p_boot),
    # 躯干
    ("torso", "body", [-4, 11, -2.5], [8, 7, 5], 0, p_torso),
    ("tie", "body", [-1.5, 14, -2.6], [3, 3, 0], 0, p_tie),
    ("neck", "body", [-2, 17.5, -1.5], [4, 2, 3], 0, p_solid(SKIN_S)),
    ("skirt", "skirt", [-5, 8, -3.5], [10, 6, 7], 0, p_skirt),
    ("underskirt", "skirt", [-5, 7, -3.5], [10, 1, 7], 0.2, p_underskirt),
    # 斗篷
    ("cloak_back", "cloak", [-6.5, 6, 3.6], [13, 12, 1], 0, p_cloak_back),
    ("cloak_side_r", "cloak", [5.5, 6, -3.4], [1, 6, 7], 0, p_cloak),
    ("cloak_side_l", "cloak", [-6.5, 6, -3.4], [1, 6, 7], 0, p_cloak),
    ("cloak_shoulder", "cloak", [-5, 16, -3], [10, 2, 6], 0.3, p_cloak_shoulder),
    ("hood", "cloak", [-4, 13.5, 4.6], [8, 3, 2], 0, p_hood),
    ("string_r", "cloak", [2, 13, -3.4], [1, 4, 0], 0, p_string),
    ("string_l", "cloak", [-3, 13, -3.4], [1, 4, 0], 0, p_string),
    ("strip_1", "cloak_strip_1", [-6, 0.5, 3.6], [2, 6, 1], 0, p_cloak_strip),
    ("strip_2", "cloak_strip_2", [-2.5, 0.5, 3.6], [2, 6, 1], 0, p_cloak_strip),
    ("strip_3", "cloak_strip_3", [1, 0.5, 3.6], [2, 6, 1], 0, p_cloak_strip),
    ("strip_4", "cloak_strip_4", [4, 0.5, 3.6], [2, 6, 1], 0, p_cloak_strip),
    ("strip_5", "cloak_strip_5", [5.5, 0.5, -2.5], [1, 6, 2], 0, p_cloak_strip),
    ("strip_6", "cloak_strip_6", [-6.5, 0.5, -2.5], [1, 6, 2], 0, p_cloak_strip),
    # 手臂
    ("arm_r", "arm_right", [4, 11, -1.5], [3, 7, 3], 0, p_arm),
    ("sleeve_r", "arm_right", [4, 13, -1.5], [3, 5, 3], 0.6, p_sleeve),
    ("arm_l", "arm_left", [-7, 11, -1.5], [3, 7, 3], 0, p_arm),
    ("sleeve_l", "arm_left", [-7, 13, -1.5], [3, 5, 3], 0.6, p_sleeve),
    # 头（头顶用 13→11→9→6 阶梯收圆，不做平顶）
    ("head", "head", [-6, 19, -6], [12, 11, 12], 0, p_head),
    ("hair_shell", "hair", [-6, 19.5, -6], [12, 11, 12], 0.5, p_hair_shell),
    ("braid", "hair", [-6, 28.5, -6], [12, 2, 12], 0.6, p_braid),
    ("hair_top_1", "hair", [-5.5, 31, -5.5], [11, 1, 11], 0, p_hair_plain),
    ("hair_top_2", "hair", [-4.5, 32, -4.5], [9, 1, 9], 0, p_hair_plain),
    ("hair_top_3", "hair", [-3, 33, -3], [6, 1, 6], 0, p_hair_plain),
    ("ahoge", "hair", [-1.5, 33.5, 0], [3, 4, 0], 0, p_ahoge),
    ("hair_back", "hair", [-6, 17, 3.5], [12, 4, 3], 0.3, p_hair_hang),
    ("lock_r", "hair", [6.5, 14, -2], [2, 8, 4], 0, p_hair_hang),
    ("lock_front_r", "hair", [2.5, 13, -4.3], [4, 6, 1], 0, p_front_lock),
    ("lock_l", "hair", [-8.5, 14, -2], [2, 8, 4], 0, p_hair_hang),
    ("lock_front_l", "hair", [-6.5, 13, -4.3], [4, 6, 1], 0, p_front_lock),
    ("bun_r", "bun_right", [6.5, 22, -1.5], [3, 3, 3], 0, p_bun),
    ("bun_l", "bun_left", [-9.5, 22, -1.5], [3, 3, 3], 0, p_bun),
    ("ribbon_r", "bun_right", [7, 18, -2.2], [2, 4, 0], 0, p_ribbon),
    ("ribbon_l", "bun_left", [-9, 18, -2.2], [2, 4, 0], 0, p_ribbon),
]


# ---------------------------------------------------------------- UV
def box_footprint(size):
    w, h, d = size
    return 2 * (w + d), d + h


def pack(cubes):
    """简单行打包，按占地高度从大到小。"""
    order = sorted(range(len(cubes)), key=lambda i: -box_footprint(cubes[i][3])[1])
    uv = {}
    x = y = row_h = 0
    for i in order:
        fw, fh = box_footprint(cubes[i][3])
        fw, fh = math.ceil(fw), math.ceil(fh)
        if x + fw > UV_W:
            x, y, row_h = 0, y + row_h, 0
        uv[i] = (x, y)
        x += fw
        row_h = max(row_h, fh)
    if y + row_h > UV_H:
        raise SystemExit(f"UV 放不下: 需要高度 {y + row_h}")
    return uv


def face_uvs(u, v, size):
    """与 Blockbench box UV 一致的六面 UV 矩形 [x1,y1,x2,y2]。"""
    w, h, d = size
    return {
        "north": [u + d, v + d, u + d + w, v + d + h],
        "east": [u, v + d, u + d, v + d + h],
        "south": [u + 2 * d + w, v + d, u + 2 * d + 2 * w, v + d + h],
        "west": [u + d + w, v + d, u + 2 * d + w, v + d + h],
        "up": [u + d + w, v + d, u + d, v],
        "down": [u + d + 2 * w, v, u + d + w, v + d],
    }


def build_texture(uv):
    tex = np.zeros((UV_H * S, UV_W * S, 4), dtype=np.uint8)
    for i, (name, _bone, _frm, size, _inf, painter) in enumerate(CUBES):
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        for face, (x1, y1, x2, y2) in face_uvs(*uv[i], size).items():
            wpx, hpx = round(abs(x2 - x1) * S), round(abs(y2 - y1) * S)
            if wpx == 0 or hpx == 0:
                continue
            img = painter(face, wpx, hpx, rng)
            if x2 < x1:
                img = img[:, ::-1]
            if y2 < y1:
                img = img[::-1]
            px, py = round(min(x1, x2) * S), round(min(y1, y2) * S)
            tex[py:py + hpx, px:px + wpx] = img
    return tex


# ---------------------------------------------------------------- export
def bone_map():
    return {b[0]: b for b in BONES}


def export_geo(uv):
    bones = []
    for name, parent, pivot in BONES:
        b = {"name": name, "pivot": [-pivot[0], pivot[1], pivot[2]]}
        if parent:
            b["parent"] = parent
        cubes = []
        for i, (_cn, bone, frm, size, inf, _p) in enumerate(CUBES):
            if bone != name:
                continue
            c = {
                "origin": [-(frm[0] + size[0]), frm[1], frm[2]],
                "size": size,
                "uv": list(uv[i]),
            }
            if inf:
                c["inflate"] = inf
            cubes.append(c)
        if cubes:
            b["cubes"] = cubes
        bones.append(b)
    geo = {
        "format_version": "1.12.0",
        "minecraft:geometry": [{
            "description": {
                "identifier": "geometry.nomi",
                "texture_width": UV_W,
                "texture_height": UV_H,
                "visible_bounds_width": 3,
                "visible_bounds_height": 3,
                "visible_bounds_offset": [0, 1.5, 0],
            },
            "bones": bones,
        }],
    }
    (OUT / "nomi.geo.json").write_text(json.dumps(geo, indent=2, ensure_ascii=False))


def export_bbmodel(uv, png_bytes):
    elem_uuid = {}
    elements = []
    bmap = bone_map()
    for i, (name, bone, frm, size, inf, _p) in enumerate(CUBES):
        uid = str(uuid.uuid4())
        elem_uuid[i] = uid
        to = [frm[k] + size[k] for k in range(3)]
        faces = {f: {"uv": r, "texture": 0} for f, r in face_uvs(*uv[i], size).items()}
        elements.append({
            "name": name,
            "box_uv": True,
            "rescale": False,
            "locked": False,
            "render_order": "default",
            "allow_mirror_modeling": True,
            "from": frm,
            "to": to,
            "autouv": 0,
            "color": i % 8,
            "origin": bmap[bone][2],
            "uv_offset": list(uv[i]),
            "inflate": inf,
            "faces": faces,
            "type": "cube",
            "uuid": uid,
        })

    groups = {}
    for name, parent, pivot in BONES:
        groups[name] = {
            "name": name,
            "origin": pivot,
            "color": 0,
            "uuid": str(uuid.uuid4()),
            "export": True,
            "mirror_uv": False,
            "isOpen": name in ("root", "body", "head"),
            "locked": False,
            "visibility": True,
            "autouv": 0,
            "children": [],
        }
    for name, parent, _pv in BONES:
        g = groups[name]
        for i, c in enumerate(CUBES):
            if c[1] == name:
                g["children"].append(elem_uuid[i])
        if parent:
            groups[parent]["children"].append(g)

    model = {
        "meta": {"format_version": "4.10", "model_format": "bedrock", "box_uv": True},
        "name": "nomi",
        "model_identifier": "nomi",
        "visible_box": [3, 3, 1.5],
        "variable_placeholders": "",
        "variable_placeholder_buttons": [],
        "timeline_setups": [],
        "unhandled_root_fields": {},
        "resolution": {"width": UV_W, "height": UV_H},
        "elements": elements,
        "outliner": [groups["root"]],
        "textures": [{
            "path": "",
            "name": "nomi.png",
            "folder": "",
            "namespace": "",
            "id": "0",
            "group": "",
            "width": UV_W * S,
            "height": UV_H * S,
            "uv_width": UV_W,
            "uv_height": UV_H,
            "particle": False,
            "use_as_default": False,
            "layers_enabled": False,
            "sync_to_project": "",
            "render_mode": "default",
            "render_sides": "auto",
            "frame_time": 1,
            "frame_order_type": "loop",
            "frame_order": "",
            "frame_interpolate": False,
            "visible": True,
            "internal": True,
            "saved": False,
            "uuid": str(uuid.uuid4()),
            "relative_path": "nomi.png",
            "source": "data:image/png;base64," + base64.b64encode(png_bytes).decode(),
        }],
    }
    (OUT / "nomi.bbmodel").write_text(json.dumps(model, ensure_ascii=False))


# ---------------------------------------------------------------- preview
def render_view(tex, uv, view, P=14, pad=2):
    """正交三视图。view: front(-Z 方向看) / side(+X 方向看) / back(+Z 方向看)。"""
    face = {"front": "north", "side": "east", "back": "south"}[view]
    quads = []
    for i, (name, _b, frm, size, inf, _p) in enumerate(CUBES):
        lo = [frm[k] - inf for k in range(3)]
        hi = [frm[k] + size[k] + inf for k in range(3)]
        r = face_uvs(*uv[i], size)[face]
        if abs(r[2] - r[0]) == 0:
            continue
        if view == "front":   # 屏幕 x = -X，近处 z 小
            sx0, sx1, depth = -hi[0], -lo[0], -lo[2]
        elif view == "back":  # 屏幕 x = X，近处 z 大
            sx0, sx1, depth = lo[0], hi[0], hi[2]
        else:                 # 屏幕 x = -Z，近处 x 大
            sx0, sx1, depth = -hi[2], -lo[2], hi[0]
        quads.append((depth, sx0, sx1, lo[1], hi[1], r))
    quads.sort(key=lambda q: q[0])

    xmin, xmax, ymax = -12, 12, 39
    W, H = (xmax - xmin) * P, (ymax + pad) * P
    img = np.zeros((H, W, 3), dtype=np.float32)
    img[:] = (196, 198, 204)
    for _d, sx0, sx1, y0, y1, (u1, v1, u2, v2) in quads:
        px0, px1 = int(round((sx0 - xmin) * P)), int(round((sx1 - xmin) * P))
        py0, py1 = int(round((ymax - y1) * P)), int(round((ymax - y0) * P))
        for py in range(max(py0, 0), min(py1, H)):
            t = (py + 0.5 - py0) / max(py1 - py0, 1)
            ty = int((v1 + t * (v2 - v1)) * S)
            for px in range(max(px0, 0), min(px1, W)):
                s = (px + 0.5 - px0) / max(px1 - px0, 1)
                tx = int((u1 + s * (u2 - u1)) * S)
                tx = min(max(tx, 0), tex.shape[1] - 1)
                tyc = min(max(ty, 0), tex.shape[0] - 1)
                c = tex[tyc, tx]
                if c[3] > 127:
                    img[py, px] = c[:3]
    return Image.fromarray(img.astype(np.uint8))


# ---------------------------------------------------------------- UrhoX
GAME_ROOT = OUT.parent.parent  # 项目根目录


def lua_num(v):
    return ("%g" % v) if isinstance(v, float) else str(v)


def lua_vec(v):
    return "{" + ", ".join(lua_num(x) for x in v) + "}"


def export_urhox(uv, png_bytes):
    """给 UrhoX 运行时用：Lua 数据模块 + 贴图。坐标仍是 Blockbench 空间，
    由 scripts/game/BlockCharacter.lua 统一换算（z 取反、单位缩放）。"""
    lines = [
        "-- 自动生成：art/nomi_ysm/build_nomi.py，请勿手改（改脚本后重新运行）",
        "-- 坐标：Blockbench 空间，1 单位 = 1/16 格，脚底 y=0，正面朝 -Z",
        "return {",
        "    texture = \"Textures/Characters/nomi.png\",",
        f"    uvWidth = {UV_W}, uvHeight = {UV_H},",
        "    bones = {",
    ]
    for name, parent, pivot in BONES:
        par = f"\"{parent}\"" if parent else "nil"
        lines.append(f"        {{ name = \"{name}\", parent = {par}, pivot = {lua_vec(pivot)} }},")
    lines.append("    },")
    lines.append("    cubes = {")
    for i, (name, bone, frm, size, inf, _p) in enumerate(CUBES):
        lines.append(
            f"        {{ name = \"{name}\", bone = \"{bone}\", from = {lua_vec(frm)}, "
            f"size = {lua_vec(size)}, inflate = {lua_num(inf)}, uv = {lua_vec(uv[i])} }},")
    lines.append("    },")
    lines.append("}")
    (GAME_ROOT / "scripts" / "game" / "NomiModelData.lua").write_text("\n".join(lines) + "\n")
    tex_dir = GAME_ROOT / "assets" / "Textures" / "Characters"
    tex_dir.mkdir(parents=True, exist_ok=True)
    (tex_dir / "nomi.png").write_bytes(png_bytes)


def main():
    uv = pack(CUBES)
    tex = build_texture(uv)
    buf = io.BytesIO()
    Image.fromarray(tex).save(buf, "PNG")
    png = buf.getvalue()
    (OUT / "nomi.png").write_bytes(png)
    export_geo(uv)
    export_bbmodel(uv, png)
    export_urhox(uv, png)

    views = [render_view(tex, uv, v) for v in ("front", "side", "back")]
    w = sum(v.width for v in views)
    sheet = Image.new("RGB", (w, views[0].height), (196, 198, 204))
    x = 0
    for v in views:
        sheet.paste(v, (x, 0))
        x += v.width
    sheet.save(OUT / "preview.png")
    used = max(uv[i][1] + box_footprint(CUBES[i][3])[1] for i in uv)
    print(f"bones={len(BONES)} cubes={len(CUBES)} uv_used_height={used}/{UV_H}")


if __name__ == "__main__":
    main()
