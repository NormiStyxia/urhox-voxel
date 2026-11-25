#!/usr/bin/env python3
"""龙娘 YSM 体素模型 —— Blockbench 工程生成器

按诺米（~/Downloads/诺米/诺米.bbmodel）的 YSM 骨骼命名与层级搭建：
Root > MAllBody > AllBody > UpBody > UpperBody > AllHead > MHead > Head > Face > Eyes ...
DownBody > Leg > LeftLeg > LeftLowerLeg > LeftFoot ...
新增部件（龙角、尖耳、尾巴、腰侧蝴蝶结与飘带）挂在对应父骨骼下，不改动原有骨骼名。

坐标约定与诺米一致：单位 1/16 方块，脚底 y=0，角色面朝 -Z（north），角色右侧 = +X。
贴图密度 4 px / 单位；每个方块面单独分配 UV 区域并逐面绘制。

输出：longnu.bbmodel、longnu.png、preview.png（离线正交渲染，含参考图对照）
用法：python3 art/longnu_ysm/build_longnu.py
"""
import base64
import hashlib
import io
import json
import math
import uuid as uuidlib
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent
PPU = 4  # 贴图像素 / 单位

# ------------------------------------------------------------------ palette
C = {
    "hair": (44, 37, 42), "hair_d": (30, 25, 30), "hair_l": (66, 57, 64), "hair_hl": (86, 76, 84),
    "skin": (252, 234, 224), "skin_s": (240, 214, 204), "skin_d": (226, 190, 182),
    "blush": (247, 196, 192), "mouth": (196, 120, 122),
    "white": (250, 250, 251), "white_s": (230, 230, 236), "white_d": (206, 206, 216),
    "black": (40, 34, 38), "black_l": (60, 52, 58),
    "red": (208, 32, 38), "red_s": (168, 20, 28), "red_d": (124, 12, 20), "red_l": (232, 70, 66),
    "flower": (158, 18, 30), "flower_s": (120, 10, 22), "flower_c": (84, 6, 14),
    "tail": (122, 58, 70), "tail_d": (98, 42, 56), "tail_l": (142, 74, 86),
    "horn": (240, 202, 202), "horn_s": (222, 170, 176), "horn_d": (200, 146, 154),
    "gem": (200, 24, 36), "gem_l": (250, 120, 120), "silver": (200, 200, 210),
    # 眼睛
    "lash": (36, 22, 28), "lash_m": (78, 40, 46),
    "scl": (255, 251, 250), "scl_s": (226, 214, 220),
    "iris_d": (112, 10, 22), "iris": (196, 24, 34), "iris_l": (230, 64, 56), "iris_o": (246, 128, 98),
    "pupil": (64, 4, 14), "hl": (255, 255, 255),
}

_rng_seed = 7


def h01(*k):
    """确定性哈希 → [0,1)。"""
    s = hashlib.md5(("%d|" % _rng_seed + "|".join(map(str, k))).encode()).digest()
    return int.from_bytes(s[:4], "little") / 2 ** 32


# ------------------------------------------------------------------ painters
# painter(face, w, h, cube) -> HxWx4 uint8，face 方向看过去的左上为 (0,0)

def rgba(c, a=255):
    return np.array([c[0], c[1], c[2], a], np.uint8)


def flat(key, edge=None):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C[key])
        if edge and face not in ("up", "down") and h >= 3:
            a[-1, :] = rgba(C[edge])
        return a
    return p


def hair(seed=0, tips=False):
    """诺米式块面头发：结构由方块轮廓表达，贴图不画竖向发丝。"""
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        if face in ("north", "south"):
            # 只做方块级整面明暗，不生成连续竖条纹
            q = h01("block-shade", cube.name, seed)
            key = "hair_d" if q < 0.14 else "hair_l" if q > 0.93 else "hair"
        else:
            key = "hair_d" if face in ("east", "west") else "hair_l"
        a[:] = rgba(C[key])
        if tips and h >= 2 and face not in ("up", "down"):
            a[-1, :] = rgba(C["hair_d"])
        return a
    return p


def crown(seed=0):
    """头顶：带一条光环高光（天使环）。"""
    base = hair(seed)

    def p(face, w, h, cube):
        a = base(face, w, h, cube)
        return a
    return p


def horn():
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["horn"])
        if face in ("east", "west", "south"):
            a[:] = rgba(C["horn_s"])
        return a
    return p


def tail(t):
    """t 0→1 从尾根到尾尖：颜色渐深，背脊一列提亮。"""
    base = np.array(C["tail"]) * (1 - t) + np.array(C["tail_d"]) * t

    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(tuple(int(v) for v in base))
        if face == "up":
            a[:] = rgba(tuple(int(min(255, v * 1.12)) for v in base))
        return a
    return p


def flower():
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["flower_c"] if cube.role == "core" else C["flower"])
        if cube.role != "core" and face not in ("up", "down") and h >= 2:
            a[-1, :] = rgba(C["flower_s"])
        return a
    return p


def bow_paint(key="red"):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C[key])
        if cube.role == "loop" and face in ("north", "south") and w >= 4 and h >= 4:
            a[0, :] = rgba(C["red_s"])
            a[-1, :] = rgba(C["red_s"])
            a[h // 2, 1:-1] = rgba(C["red_s"])  # 中间褶
        if cube.role == "streamer" and face in ("north", "south", "east", "west"):
            a[:, 0] = rgba(C["red_s"])
            if face in ("north", "south") and w >= 3 and h >= 3:  # 燕尾 V 口
                mid = (w - 1) / 2
                for x in range(w):
                    depth = int(round(2 * (1 - abs(x - mid) / max(mid, 1))))
                    if depth:
                        a[h - depth:, x, 3] = 0
        return a
    return p


def skin_part(shade_bottom=False):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["skin"])
        if shade_bottom and face not in ("up", "down"):
            a[-1:, :] = rgba(C["skin_s"])
        return a
    return p


def toes():
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["skin"])
        if face == "north":
            for x in range(2, w - 1, 2):
                a[h // 3:, x] = rgba(C["skin_d"])
        if face == "up" and h >= 2:
            a[0, :] = rgba(C["skin_s"])
        return a
    return p


def dress_top():
    """衣身：领口下方阴影、吊坠细链。"""
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["white"])
        if face in ("north", "south", "east", "west") and h >= 2:
            a[0, :] = rgba(C["white_s"])
        if face == "north" and cube.role == "chest":
            # 细链：从两侧领口斜向中心
            cx = (w - 1) / 2
            for y in range(0, 6):
                for x in (int(round(cx - 3 + y * 0.5)), int(round(cx + 3 - y * 0.5))):
                    if 0 <= x < w and y < h:
                        a[y, x] = rgba(C["silver"])
            # 上衣褶线
            for x in (3, w - 4):
                a[h - 4:, x] = rgba(C["white_s"])
        return a
    return p


def collar():
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["white"])
        if face not in ("up", "down"):
            a[-1, :] = rgba(C["white_d"])
        if face == "up":
            a[:] = rgba(C["white"])
        return a
    return p


def lapel(side):
    """翻领前片：三角尖，外轮廓一圈浅灰。side=+1 角色右片（画面左）。"""
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["white"])
        if face == "north":
            # 画面坐标：右片尖角朝画面右下（中心），左片朝画面左下
            for y in range(h):
                for x in range(w):
                    # 斜边：从外侧顶端到中心底端
                    xx = x if side > 0 else (w - 1 - x)  # xx 从外到内
                    lim = (y + 1) * w / h
                    if xx > lim + 0.5:
                        a[y, x, 3] = 0  # 尖角外透明
                    elif xx > lim - 1.0 or y == h - 1:
                        a[y, x] = rgba(C["white_d"])
        elif face == "south":
            a[:] = rgba(C["white_s"])
        return a
    return p


def skirt_paint(tier):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["white"])
        if face in ("north", "south", "east", "west"):
            # 竖向褶：每 4 px 一条浅阴影
            if face in ("north", "south"):
                for x in range(3, w, 8):
                    a[:, x] = rgba(C["white_s"])
        if face == "down":
            a[:] = rgba(C["white_d"])
        return a
    return p


def gem():
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["gem"])
        if face == "north" and w >= 2 and h >= 3:
            a[0, :] = rgba(C["silver"])
            a[1, 0] = rgba(C["gem_l"])
            a[-1, :] = rgba(C["red_d"])
            a[-1, 0, 3] = 0
            a[-1, -1, 3] = 0
        return a
    return p


# ---------------- 面部
FACE_W, FACE_H = None, None


def face_front():
    """脸正面：肤色、腮红、小嘴。眼睛是独立方块（RightEyesBase 等），不画在这里。"""
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["skin"])
        if face != "north":
            if face in ("east", "west"):
                a[:, :] = rgba(C["skin_s"])
            return a
        # 以单位坐标定位（cube.frm/to），face 左上 = (x2, y2)
        x2, y2 = cube.to[0], cube.to[1]

        def px(x_unit, y_unit):  # 角色坐标 → 像素
            return int(round((x2 - x_unit) * PPU)), int(round((y2 - y_unit) * PPU))
        # 腮红：眼下外侧两片，各 4x2 px
        for sx in (+1, -1):
            for xu in (2.05, 2.30, 2.55):
                for yu in (27.75,):
                    x, y = px(sx * xu + (0.125 if sx > 0 else -0.125) * 0 , yu)
                    x = x if sx > 0 else x - 1
                    if 0 <= x < w and 0 <= y < h:
                        a[y, x] = rgba(C["blush"])
        # 小嘴：2px 宽的“ˆ”，中间一点 + 两侧下沉（原画是小小的倒 V）
        mx, my = px(0.0, 27.38)
        for dx, dy in ((-1, 0), (0, 0)):
            if 0 <= mx + dx < w:
                a[my + dy, mx + dx] = rgba(C["mouth"])
        for dx in (-2, 1):
            if 0 <= mx + dx < w:
                a[my + 1, mx + dx] = rgba(C["skin_d"])
        return a
    return p


# 眼睛像素画（10x10，0.25 单位/px），以“画面左侧那只眼（角色右眼）”绘制：列 0 = 外眼角
EYE_ROWS = [
    "LLLLLLLLLL",
    "LLLLLLLLLL",
    "DDDDDDDDDD",
    "DRRRRRRRRD",
    "DRRPPPRRRD",
    "DRRPPPRRRD",
    "DRRPPPRRRD",
    "DRrrrrrrrD",
    "DRrrrrrrrD",
    "DDDDDDDDDD",
]
EYE_KEY = {"L": "lash", "D": "iris_d", "R": "iris", "r": "iris_l", "P": "pupil"}


def eye_grid(mirror):
    """mirror=True → 画面右侧那只眼（角色左眼）：几何左右镜像，但高光仍留在画面左上（同一光源）。"""
    rows = [list(r) for r in EYE_ROWS]
    if mirror:
        rows = [r[::-1] for r in rows]
        # 把高光挪回画面左侧：交换 H 与其左右对称位置的虹膜色
        for r in rows:
            hs = [i for i, ch in enumerate(r) if ch == "H"]
            for i in hs:
                r[i] = "d"
            for i in hs:
                j = 9 - i
                r[j] = "H"
        # 镜像后瞳孔两侧的深浅也随之调换，保持上暗下亮即可
    return ["".join(r) for r in rows]


def eye_layer(mirror, layer):
    """layer: base=眼白+虹膜；pupil=瞳孔+高光（前凸 0.02）；lash=上睫毛。"""
    grid = eye_grid(mirror)
    take = {"base": set("DRr"), "pupil": set("P"), "lash": set("L")}[layer]

    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        if face != "north":
            if layer == "lash" and face in ("up", "east", "west", "down"):
                a[:] = rgba(C["lash"])
            else:
                a[:, :, 3] = 0
            return a
        if layer == "pupil":
            # 简单中央深色瞳孔，不再依赖复杂高光像素
            a[:, :, 3] = 0
            lo = max(0, w // 2 - max(1, w // 10))
            hi = min(w, w // 2 + max(1, w // 10) + 1)
            a[:, lo:hi] = rgba(C["pupil"])
            return a
        gy0 = int(round((cube.eye_top - cube.to[1]) * PPU))  # 本方块在 10 行网格中的起始行
        for y in range(h):
            for x in range(w):
                gy = gy0 + y
                if 0 <= gy < 10 and x < 10:
                    ch = grid[gy][x]
                    if ch in take:
                        a[y, x] = rgba(C[EYE_KEY[ch]])
        return a
    return p


def eyelid():
    """闭眼用肤色眼睑：默认收在刘海后（y 在眼睛上方），眨眼动画下移覆盖眼睛。"""
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["skin"])
        if face == "north":
            a[-1, :] = rgba(C["lash"])
        return a
    return p


# ------------------------------------------------------------------ model types
class Cube:
    def __init__(self, name, frm, to, paint, origin=None, rot=(0, 0, 0), inflate=0.0, **kw):
        self.name = name
        self.frm = [float(v) for v in frm]
        self.to = [float(v) for v in to]
        self.paint = paint
        self.origin = list(origin) if origin is not None else [(a + b) / 2 for a, b in zip(self.frm, self.to)]
        self.rot = list(rot)
        self.inflate = inflate
        self.role = kw.pop("role", "")
        self.stripe = kw.pop("stripe", 0)
        self.eye_top = kw.pop("eye_top", 0)
        self.uuid = str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, "longnu/" + name + str(frm) + str(to)))
        self.faces = {}


class Group:
    def __init__(self, name, origin, rot=(0, 0, 0)):
        self.name = name
        self.origin = [float(v) for v in origin]
        self.rot = list(rot)
        self.children = []
        self.uuid = str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, "longnu-group/" + name))

    def g(self, name, origin, rot=(0, 0, 0)):
        c = Group(name, origin, rot)
        self.children.append(c)
        return c

    def c(self, *a, **kw):
        cube = Cube(*a, **kw)
        self.children.append(cube)
        return cube


def mirror_x(v):
    return [-v[0], v[1], v[2]]


def box(cx0, cx1, y0, y1, z0, z1):
    return [min(cx0, cx1), y0, min(z0, z1)], [max(cx0, cx1), y1, max(z0, z1)]


# ------------------------------------------------------------------ build
def build():
    """全部坐标按诺米 .bbmodel 实测：腿 0–18.7、躯干 18.8–25.8、颈 25.3–27.5、脸 26.6–33.0（宽 7.4）、肩 25.3。"""
    root = Group("Root", (0, 0, 0))
    mall = root.g("MAllBody", (0, 19.3, 0))
    allb = mall.g("AllBody", (0, 19.3, 0))
    upb = allb.g("UpBody", (0, 19.3, 0))
    upper = upb.g("UpperBody", (0, 19.3, 0))
    FZ = -3.5  # 脸正面 z

    # ---------------- 头
    allhead = upper.g("AllHead", (0, 26.75, 0))
    mhead = allhead.g("MHead", (0, 26.75, 0))
    head = mhead.g("Head", (0, 26.0, 0))
    face = head.g("Face", (0, 29.4, FZ))
    face.c("面部·颊中", (-3.75, 26.6, FZ), (3.75, 33.0, 3.2), face_front())
    face.c("颌底·平段", (-2.0, 26.1, FZ + 0.25), (2.0, 26.6, 2.6), skin_part())
    face.c("颌缘·右", (2.0, 26.35, FZ + 0.25), (3.4, 26.6, 2.6), skin_part())
    face.c("颌缘·左", (-3.4, 26.35, FZ + 0.25), (-2.0, 26.6, 2.6), skin_part())

    eyes = face.g("Eyes", (0, 29.4, FZ))
    brow = eyes.g("Eyebrow", (0, 31.0, FZ))
    brow.g("RightEyebrow", (2.0, 31.0, FZ))
    brow.g("LeftEyebrow", (-2.0, 31.0, FZ))
    brow.c("右眉", (1.05, 30.35, FZ - 0.03), (3.05, 30.62, FZ + 0.02), flat("lash"))
    brow.c("左眉", (-3.05, 30.35, FZ - 0.03), (-1.05, 30.62, FZ + 0.02), flat("lash"))
    lid = eyes.g("Eyelid", (0, 30.5, FZ))
    EYE_TOP, EYE_BOT = 30.05, 28.05
    for side, nm in ((+1, "Right"), (-1, "Left")):
        x_out, x_in = side * 3.05, side * 1.05
        mirror = side < 0
        el = lid.g(nm + "Eyelid", (side * 2.2, EYE_TOP, FZ))
        f, t = box(x_out, x_in, EYE_TOP - 0.5, EYE_TOP, FZ - 0.01, FZ + 0.01)
        el.c(nm + "·上睫", f, t, eye_layer(mirror, "lash"), eye_top=EYE_TOP)
        f, t = box(x_out, x_out - side * 0.25, EYE_TOP - 0.75, EYE_TOP - 0.5, FZ - 0.01, FZ + 0.01)
        el.c(nm + "·外睫顿笔", f, t, eye_layer(mirror, "lash"), eye_top=EYE_TOP)
        f, t = box(x_out, x_in, EYE_TOP, EYE_TOP + 2.0, FZ - 0.01, FZ + 0.01)
        el.c(nm + "·肤色眼睑", f, t, eyelid())
        base = el.g(nm + "EyesBase", (side * 2.2, 29.25, FZ))
        f, t = box(x_out, x_in, EYE_BOT, EYE_TOP - 0.5, FZ - 0.01, FZ + 0.01)
        base.c(nm + "·眼白虹膜", f, t, eye_layer(mirror, "base"), eye_top=EYE_TOP)
        pup = base.g(nm + "Pupil", (side * 2.2, 29.25, FZ - 0.04))
        f, t = box(x_out, x_in, EYE_BOT + 0.75, EYE_TOP - 0.5, FZ - 0.04, FZ - 0.02)
        pup.c(nm + "·瞳孔高光", f, t, eye_layer(mirror, "pupil"), eye_top=EYE_TOP)
    head.g("ViewLocator", (0, 29.4, FZ))

    # ---------------- 头发
    hairg = head.g("Hair", (0, 30.5, 0.4))
    fr = hairg.g("front_h1", (0, 33.1, -3.6))
    bottoms = [31.2, 31.0, 30.8, 30.55, 30.45, 30.55, 30.8, 31.2]
    xs = np.linspace(-4.75, 4.75, 9)
    fringe_tops = [33.55, 33.85, 34.15, 34.35, 34.4, 34.25, 33.95, 33.6]
    for i in range(8):
        fr.c("刘海发束%d" % i, (xs[i], bottoms[i], FZ - 0.5), (xs[i + 1], fringe_tops[i], FZ + 0.1), hair(i, tips=True))
    # 单层刘海，中央只保留一束略长的块体，避免重复叠板
    for side, nm in ((+1, "R"), (-1, "L")):
        cg = hairg.g("corner_h1" if side > 0 else "corner_h2", (side * 3.7, 29.4, -2.4))
        f, t = box(side * 3.75, side * 4.85, 29.2, 33.0, FZ - 0.35, -2.0)
        cg.c("鬓角上" + nm, f, t, hair(30 + side))
        f, t = box(side * 4.0, side * 5.15, 25.8, 29.2, FZ - 0.2, -1.6)
        cg.c("鬓角中" + nm, f, t, hair(32 + side))
        f, t = box(side * 4.2, side * 5.0, 23.0, 25.8, FZ + 0.05, -1.3)
        cg.c("鬓角梢" + nm, f, t, hair(34 + side, tips=True))
    # 头发采用分层体积，而不是一块覆盖头部的发壳
    bh = hairg.g("BaseHair", (0, 30.0, 1.0))
    # 发冠底层填补发束之间的缝隙，前层仍由独立发束塑形
    bh.c("发冠底层", (-5.0, 32.6, -3.05), (5.0, 35.0, -2.72), hair(39))
    # 后脑按中央、左右上层、左右下层拆分，形成圆弧而不是一块平板
    bh.c("后脑中央", (-2.7, 27.0, 1.2), (2.7, 33.2, 5.4), hair(40))
    bh.c("后脑左上", (-4.7, 27.0, 1.6), (-2.65, 32.7, 5.25), hair(41))
    bh.c("后脑右上", (2.65, 27.0, 1.6), (4.7, 32.7, 5.25), hair(42))
    bh.c("后脑左下", (-4.25, 24.0, 2.0), (-2.0, 27.2, 5.05), hair(43, tips=True))
    bh.c("后脑右下", (2.0, 24.0, 2.0), (4.25, 27.2, 5.05), hair(44, tips=True))
    bh.c("后发底层", (-3.6, 22.0, 2.4), (3.6, 24.2, 4.8), hair(45, tips=True))
    # 耳坠后方的侧发底片，包住侧脸并连接后脑，不让肉色穿透
    bh.c("耳后侧发·右", (4.0, 27.0, -2.8), (5.8, 33.0, 2.8), hair(46))
    bh.c("耳后侧发·左", (-5.8, 27.0, -2.8), (-4.0, 33.0, 2.8), hair(47))
    # 顶部六块错层，形成圆顶和真实高低差
    oh = hairg.g("OuterHair", (0, 34.0, 0))
    crown_specs = [(-4.8, -4.15, 34.0, 35.0, -3.0, 4.9), (-3.2, -4.25, 34.0, 35.7, -3.2, 4.8),
                   (-1.6, -4.30, 34.0, 36.2, -3.3, 4.6), (0.0, -4.35, 34.0, 36.4, -3.3, 4.6),
                   (1.6, -4.30, 34.0, 36.2, -3.3, 4.6), (3.2, -4.25, 34.0, 35.7, -3.2, 4.8),
                   (4.8, -4.15, 34.0, 35.0, -3.0, 4.9)]
    for i, (x0, z0, y0, y1, zz0, zz1) in enumerate(crown_specs):
        oh.c("顶层发束%d" % i, (x0 - 0.82, y0, zz0), (x0 + 0.82, y1, zz1), hair(50 + i, tips=True))
    # 额侧与耳侧的三层发束，前后错开形成真实厚度
    for side, nm in ((1, "右"), (-1, "左")):
        f,t=box(side*4.1, side*5.25, 30.8, 34.0, -4.05, -2.7)
        oh.c("侧发上·" + nm, f, t, hair(58 + side))
        f,t=box(side*4.55, side*5.7, 27.0, 31.2, -3.8, -2.3)
        oh.c("侧发中·" + nm, f, t, hair(60 + side, tips=True))
        f,t=box(side*4.7, side*5.95, 24.0, 27.3, -3.4, -1.8)
        oh.c("侧发下·" + nm, f, t, hair(62 + side, tips=True))
    flh = hairg.g("FLongHair", (0, 34.8, 3.5))
    mlh = flh.g("MLongHair", (0, 30, 4.3))
    mlh.c("后发·上", (-5.6, 21.5, 2.2), (5.6, 26.0, 5.6), hair(60))
    lh = mlh.g("LongHair", (0, 26.7, 4.8))
    lh.c("后发·梢", (-5.2, 19.5, 2.6), (5.2, 21.5, 5.2), hair(61, tips=True))
    for side, nm in ((+1, "Right"), (-1, "Left")):
        s0 = lh.g(nm + "SideLock", (side * 5.6, 26.0, 2.0))
        f, t = box(side * 4.6, side * 6.9, 20.5, 26.5, -1.4, 2.4)
        s0.c(nm + "垂发上", f, t, hair(70 + side))
        s1 = s0.g(nm + "SideLock1", (side * 5.9, 20.5, 2.0))
        f, t = box(side * 5.0, side * 7.2, 16.5, 20.5, -1.0, 2.4)
        s1.c(nm + "垂发中", f, t, hair(72 + side))
        s2 = s1.g(nm + "SideLock2", (side * 6.1, 16.5, 2.0))
        f, t = box(side * 4.8, side * 7.0, 13.5, 16.5, 1.0, 3.2)
        s2.c(nm + "垂发下", f, t, hair(74 + side))
        f, t = box(side * 5.3, side * 6.6, 12.5, 13.5, 1.2, 2.9)
        s2.c(nm + "垂发梢", f, t, hair(76 + side, tips=True))
    rib = hairg.g("Ribbon", (4.0, 30.6, 3.1))
    for side, nm in ((+1, "Right"), (-1, "Left")):
        fg = rib.g(nm + "HairFlower", (side * 5.9, 28.6, -0.6), rot=(0, 0, side * 45))
        add_flower(fg, nm + "发花", (side * 5.9, 28.6, -0.6), petal=0.82, core=0.72, out=side)

    # 龙角与尖耳
    for side, nm in ((+1, "Right"), (-1, "Left")):
        hg = head.g(nm + "Horn", (side * 4.0, 34.3, -0.6), rot=(0, 0, -side * 4))
        segs = [(2.6, 5.35, 34.0, 36.0), (3.0, 5.6, 36.0, 37.5), (3.5, 5.9, 37.5, 39.0),
                (4.0, 6.2, 39.0, 40.5), (4.6, 6.4, 40.5, 42.0), (5.0, 6.3, 42.0, 43.4)]
        zs = [(-2.2, 0.6), (-2.1, 0.5), (-2.0, 0.4), (-1.8, 0.2), (-1.5, 0.0), (-1.2, -0.2)]
        for i, ((a, b2, y0, y1), (z0, z1)) in enumerate(zip(segs, zs)):
            f, t = box(side * a, side * b2, y0, y1, z0, z1)
            hg.c("%s角%d" % (nm, i), f, t, horn(), stripe=i)
        eg = head.g(nm + "Ear", (side * 5.2, 33.5, -0.3))
        f, t = box(side * 5.2, side * 7.2, 32.6, 34.6, -1.6, 1.0)
        eg.c(nm + "尖耳", f, t, horn(), stripe=0)
        f, t = box(side * 7.2, side * 8.4, 33.6, 35.4, -1.2, 0.6)
        eg.c(nm + "耳尖", f, t, horn(), stripe=1)

    # ---------------- 手臂
    arm = upper.g("Arm", (0, 25.8, 0))
    ang = 16.0
    for side, nm in ((+1, "Right"), (-1, "Left")):
        a = math.radians(ang)
        p0 = (side * 3.7, 25.2)
        ua = arm.g(nm + "Arm", (p0[0], p0[1], 0), rot=(0, 0, side * 13))
        ua.c(nm + "Arm裁片", (p0[0] - 1.15, p0[1] - 3.8, -1.2), (p0[0] + 1.15, p0[1], 1.2),
             skin_part(), origin=(p0[0], p0[1], 0), rot=(0, 0, side * 21))
        p1 = (p0[0] + side * 3.8 * math.sin(math.radians(21)), p0[1] - 3.8 * math.cos(math.radians(21)))
        fa = ua.g(nm + "ForeArm", (p1[0], p1[1], 0))
        fa.c(nm + "ForeArm裁片", (p1[0] - 1.1, p1[1] - 3.4, -1.15), (p1[0] + 1.1, p1[1], 1.15),
             skin_part(), origin=(p1[0], p1[1], 0), rot=(0, 0, side * ang))
        p2 = (p1[0] + side * 3.4 * math.sin(a), p1[1] - 3.4 * math.cos(a))
        hd = fa.g(nm + "Hand", (p2[0], p2[1], 0))
        hd.c(nm + "Hand裁片", (p2[0] - 0.95, p2[1] - 2.5, -0.95), (p2[0] + 0.95, p2[1], 0.95),
             skin_part(True), origin=(p2[0], p2[1], 0), rot=(0, 0, side * (ang + 4)))
        hd.g(nm + "HandLocator", (p2[0] + side * 0.4, p2[1] - 2.4, 0))

    # ---------------- 上衣
    top = upper.g("FittedTop", (0, 22.6, 0))
    top.c("胸身", (-3.4, 21.3, -1.9), (3.4, 25.6, 1.9), dress_top(), role="chest")
    top.c("收腰", (-3.1, 19.0, -1.75), (3.1, 21.3, 1.75), dress_top())
    top.c("腰带", (-3.25, 19.5, -1.9), (3.25, 20.8, 1.9), flat("black", edge="black_l"))
    upper.c("颈部", (-1.0, 25.3, -1.0), (1.0, 27.5, 1.0), skin_part())
    col = upper.g("Collar", (0, 25.8, 0))
    col.c("翻领·肩", (-3.5, 24.9, -2.1), (3.5, 25.9, 2.1), collar())
    col.c("翻领·后", (-3.0, 23.6, 1.9), (3.0, 24.9, 2.15), collar())
    col.c("翻领前片·右", (0.0, 23.2, -2.3), (2.4, 25.4, -2.05), lapel(+1))
    col.c("翻领前片·左", (-2.4, 23.2, -2.3), (0.0, 25.4, -2.05), lapel(-1))
    br = upper.g("Breast", (0, 24.9, -1.8))
    br.c("红宝石吊坠", (-0.4, 21.9, -2.4), (0.4, 23.1, -2.1), gem())
    upper.g("ElytraLocator", (0, 25.8, 2))
    upper.g("BackpackLocator", (0, 25.0, 2))

    # ---------------- 下身
    down = allb.g("DownBody", (0, 19.3, 0))
    leg = down.g("Leg", (0, 18.1, 0))
    for side, nm in ((+1, "Right"), (-1, "Left")):
        cx = side * 1.9
        lg = leg.g(nm + "Leg", (cx, 18.3, 0))
        f, t = box(side * 0.2, side * 3.4, 9.2, 18.6, -1.55, 1.55)
        lg.c(nm + "Leg裁片", f, t, skin_part())
        ll = lg.g(nm + "LowerLeg", (cx, 9.2, 0))
        f, t = box(side * 0.25, side * 3.35, 3.6, 9.2, -1.5, 1.5)
        ll.c(nm + "LowerLeg裁片", f, t, skin_part())
        f, t = box(side * 0.1, side * 3.5, 2.4, 3.9, -1.7, 1.7)
        ll.c(nm + "脚环", f, t, flat("black", edge="black_l"))
        ft = ll.g(nm + "Foot", (cx, 2.7, 0))
        f, t = box(side * 0.25, side * 3.35, 1.2, 2.4, -1.4, 1.4)
        ft.c(nm + "脚踝", f, t, skin_part())
        f, t = box(side * 0.2, side * 3.4, 0.0, 1.2, -2.9, 1.6)
        ft.c(nm + "脚掌", f, t, toes())

    wf = down.g("NomiWaistFollow", (0, 19.3, 0))
    sk = wf.g("Skirt", (0, 19.3, 0))
    panels = {
        "FrontSkirt": sk.g("FrontSkirt", (0, 19.3, -1.8)),
        "BackSkirt": sk.g("BackSkirt", (0, 19.3, 1.8)),
        "LeftSkirt": sk.g("LeftSkirt", (-3.2, 19.3, 0)),
        "RightSkirt": sk.g("RightSkirt", (3.2, 19.3, 0)),
    }
    TH = 0.5
    tiers = []
    for i in range(10):
        tiers.append((19.2 - 0.5 * (i + 1), 19.2 - 0.5 * i, 3.3 + 0.19 * i, 2.35 + 0.115 * i, skirt_paint(i)))
    tiers.append((13.2, 14.2, 5.35, 3.55, flat("black", edge="black_l")))
    for i, (y0, y1, hw, hd, pnt) in enumerate(tiers):
        panels["FrontSkirt"].c("裙前%d" % i, (-hw, y0, -hd), (hw, y1, -hd + TH), pnt)
        panels["BackSkirt"].c("裙后%d" % i, (-hw, y0, hd - TH), (hw, y1, hd), pnt)
        panels["LeftSkirt"].c("裙左%d" % i, (-hw, y0, -hd + TH), (-hw + TH, y1, hd - TH), pnt)
        panels["RightSkirt"].c("裙右%d" % i, (hw - TH, y0, -hd + TH), (hw, y1, hd - TH), pnt)
    sk.c("裙内衬", (-3.25, 18.9, -2.25), (3.25, 19.15, 2.25), flat("white_d"))
    sk.c("衬裙·上", (-4.2, 12.7, -2.4), (4.2, 13.2, 2.4), flat("white"))
    sk.c("衬裙·下", (-4.9, 11.3, -2.5), (4.9, 12.7, 2.5), flat("white"))

    bowg = wf.g("WaistBow", (-1.15, 20.2, -2.75))
    kx, ky, kz = -1.15, 20.2, -2.75
    bowg.c("结心", (kx - 0.5, ky - 0.65, kz - 0.7), (kx + 0.5, ky + 0.65, kz + 0.1), bow_paint("red_s"))
    for s, nm in ((-1, "外"), (+1, "内")):
        xa, xb = sorted((kx + s * 0.5, kx + s * 2.6))
        bowg.c("蝴蝶结耳·" + nm, (xa, ky - 1.25, kz - 0.6), (xb, ky + 1.25, kz + 0.1), bow_paint(),
               role="loop", origin=(kx, ky, kz), rot=(0, 0, s * 12))
    # 三段折线飘带，始终位于裙前方，避免被裙片吞掉
    ribbon_specs = [
        (0, 0.0, 19.7, 17.2, -2.85, -2.92, 1.65),
        (1, -0.45, 17.2, 14.7, -3.35, -3.42, 1.45),
        (2, -0.95, 14.7, 9.7, -3.85, -3.92, 1.35),
    ]
    for i, dx, top_y, bot_y, z0, z1, tw in ribbon_specs:
        rg = bowg.g("RibbonTail%d" % i, (kx + dx * 0.12, top_y, z0))
        rg.c("飘带%d" % i, (kx + dx * 0.12 - tw / 2, bot_y, z1),
              (kx + dx * 0.12 + tw / 2, top_y, z0), bow_paint(), role="streamer",
              origin=(kx + dx * 0.12, top_y, z0), rot=(0, 0, -4 if i == 0 else -7))

    path = [(0.6, 13.0, -1.2), (1.6, 10.5, -1.0), (2.8, 8.0, -0.8), (4.4, 6.2, -0.4),
            (6.0, 4.6, 0.0), (7.2, 3.2, 0.4)]
    tg = down.g("Tail", path[0])
    parent = tg
    nseg = len(path) - 1
    for i in range(nseg):
        p, q = np.array(path[i]), np.array(path[i + 1])
        seg = parent.g("Tail%d" % i, tuple(p))
        n = max(2, int(np.ceil(np.linalg.norm(q - p) / 0.75)))
        for k in range(n):
            tt = (i + k / n) / nseg
            sz = 1.3 - 0.45 * tt
            cpos = p + (q - p) * (k + 0.5) / n
            seg.c("尾%d_%d" % (i, k), cpos - sz / 2, cpos + sz / 2, tail(tt))
        if i == 2:
            fg = seg.g("TailFlowerMid", tuple(q))
            add_flower(fg, "尾花中", tuple(q), petal=0.95, core=0.9, out=0)
        parent = seg
    fg = parent.g("TailFlowerTip", path[-1])
    tip = np.array(path[-1]) + np.array([0.6, -0.6, 0.3])
    add_flower(fg, "尾花尖", tuple(tip), petal=1.0, core=0.9, out=0)

    root.g("molang", (0, -0.3, 0))
    return root


def add_flower(g, name, c, petal, core, out):
    """立体十字花：中心 + 上下左右前后六瓣。out=±1 时贴头侧，省掉朝内那瓣。"""
    cx, cy, cz = c
    h = core / 2
    g.c(name + "·芯", (cx - h, cy - h, cz - h), (cx + h, cy + h, cz + h), flower(), role="core")
    pw = h
    dirs = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    for d in dirs:
        if out and d[0] == -out:
            continue
        lo, hi = [], []
        for k in range(3):
            if d[k] == 0:
                lo.append(c[k] - pw)
                hi.append(c[k] + pw)
            elif d[k] > 0:
                lo.append(c[k] + h)
                hi.append(c[k] + h + petal)
            else:
                lo.append(c[k] - h - petal)
                hi.append(c[k] - h)
        g.c(name + "·瓣", lo, hi, flower(), role="petal")


# ------------------------------------------------------------------ atlas
FACES = ("north", "east", "south", "west", "up", "down")


def face_size(cube, f):
    w = cube.to[0] - cube.frm[0]
    h = cube.to[1] - cube.frm[1]
    d = cube.to[2] - cube.frm[2]
    sz = {"north": (w, h), "south": (w, h), "east": (d, h), "west": (d, h), "up": (w, d), "down": (w, d)}[f]
    return max(1, int(round(sz[0] * PPU))), max(1, int(round(sz[1] * PPU)))


def iter_cubes(g):
    for ch in g.children:
        if isinstance(ch, Cube):
            yield ch
        else:
            yield from iter_cubes(ch)


def make_atlas(root):
    items = []
    for cube in iter_cubes(root):
        for f in FACES:
            w, h = face_size(cube, f)
            img = cube.paint(f, w, h, cube)
            assert img.shape == (h, w, 4), (cube.name, f, img.shape, w, h)
            items.append((cube, f, img))
    # 去重：完全相同的贴图共用一块
    W = 512
    order = sorted(range(len(items)), key=lambda i: -items[i][2].shape[0])
    placed = {}
    x = y = row_h = 0
    rects = {}
    for i in order:
        cube, f, img = items[i]
        key = img.tobytes() + bytes(img.shape[:2])
        if key in placed:
            rects[(cube.uuid, f)] = placed[key]
            continue
        h, w = img.shape[:2]
        if x + w > W:
            x, y, row_h = 0, y + row_h, 0
        rects[(cube.uuid, f)] = (x, y, w, h)
        placed[key] = (x, y, w, h)
        x += w
        row_h = max(row_h, h)
    H = 1 << int(np.ceil(np.log2(max(64, y + row_h))))
    H = max(H, W) if y + row_h > W else W
    atlas = np.zeros((H, W, 4), np.uint8)
    for cube, f, img in items:
        rx, ry, w, h = rects[(cube.uuid, f)]
        atlas[ry:ry + h, rx:rx + w] = img
    for cube in iter_cubes(root):
        for f in FACES:
            rx, ry, w, h = rects[(cube.uuid, f)]
            cube.faces[f] = [rx, ry, rx + w, ry + h]
    return atlas


# ------------------------------------------------------------------ export bbmodel
def export_bbmodel(root, atlas, path):
    buf = io.BytesIO()
    Image.fromarray(atlas).save(buf, "PNG")
    png = buf.getvalue()
    (OUT / "longnu.png").write_bytes(png)
    H, W = atlas.shape[:2]
    elements, groups = [], []

    def outl(g):
        groups.append({
            "name": g.name, "uuid": g.uuid, "export": True, "locked": False, "scope": 0,
            "visibility": True, "origin": g.origin, "rotation": g.rot, "bedrock_binding": "",
            "color": 0, "reset": False, "shade": True, "mirror_uv": False, "autouv": 0,
            "isOpen": False, "children": [],
        })
        ch = []
        for c in g.children:
            if isinstance(c, Cube):
                el = {
                    "name": c.name, "box_uv": False, "render_order": "default", "locked": False,
                    "export": True, "scope": 0, "allow_mirror_modeling": True,
                    "from": c.frm, "to": c.to, "autouv": 0, "color": 0, "origin": c.origin,
                    "faces": {f: {"uv": c.faces[f], "texture": 0} for f in FACES},
                    "type": "cube", "uuid": c.uuid,
                }
                if any(c.rot):
                    el["rotation"] = c.rot
                if c.inflate:
                    el["inflate"] = c.inflate
                elements.append(el)
                ch.append(c.uuid)
            else:
                ch.append(outl(c))
        return {"uuid": g.uuid, "isOpen": g.name in ("Root", "MAllBody", "AllBody"), "children": ch}

    outliner = [outl(root)]
    model = {
        "meta": {"format_version": "5.0", "model_format": "bedrock", "box_uv": False},
        "name": "龙娘", "model_identifier": "longnu", "visible_box": [4, 3.5, 1.25],
        "variable_placeholders": "", "variable_placeholder_buttons": [],
        "bedrock_animation_mode": "entity", "timeline_setups": [], "unhandled_root_fields": {},
        "resolution": {"width": W, "height": H},
        "elements": elements, "groups": groups, "outliner": outliner,
        "textures": [{
            "name": "longnu.png", "relative_path": "longnu.png", "folder": "", "namespace": "", "id": "0",
            "group": "", "scope": 0, "width": W, "height": H, "uv_width": W, "uv_height": H,
            "particle": False, "use_as_default": False, "layers_enabled": False, "sync_to_project": "",
            "file_format": "png", "render_mode": "default", "render_sides": "auto", "wrap_mode": "limited",
            "pbr_channel": "color", "fps": 7, "force_translucent": False, "frame_time": 1,
            "frame_order_type": "loop", "frame_order": "", "frame_interpolate": False, "visible": True,
            "internal": True, "saved": True,
            "uuid": str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, "longnu-tex")),
            "source": "data:image/png;base64," + base64.b64encode(png).decode(),
        }],
        "animations": [],
    }
    path.write_text(json.dumps(model, ensure_ascii=False, indent=1), encoding="utf-8")
    return len(elements), len(groups)


# ------------------------------------------------------------------ preview renderer
def rot_matrix(r):
    x, y, z = (math.radians(v) for v in r)
    Rx = np.array([[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]])
    Ry = np.array([[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]])
    Rz = np.array([[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]])
    return Rz @ Ry @ Rx  # Blockbench / three.js 'ZYX'


def face_quads(cube):
    (x1, y1, z1), (x2, y2, z2) = cube.frm, cube.to
    q = {  # 从外侧看：左上、右上、右下、左下
        "north": [(x2, y2, z1), (x1, y2, z1), (x1, y1, z1), (x2, y1, z1)],
        "south": [(x1, y2, z2), (x2, y2, z2), (x2, y1, z2), (x1, y1, z2)],
        "east": [(x2, y2, z2), (x2, y2, z1), (x2, y1, z1), (x2, y1, z2)],
        "west": [(x1, y2, z1), (x1, y2, z2), (x1, y1, z2), (x1, y1, z1)],
        "up": [(x1, y2, z1), (x2, y2, z1), (x2, y2, z2), (x1, y2, z2)],
        "down": [(x1, y1, z2), (x2, y1, z2), (x2, y1, z1), (x1, y1, z1)],
    }
    R = rot_matrix(cube.rot)
    o = np.array(cube.origin)
    return {f: [R @ (np.array(p) - o) + o for p in pts] for f, pts in q.items()}


def collect_faces(root):
    out = []

    def walk(g, M, t):
        # 组旋转（本模型组均无旋转，保留通用实现）
        R = rot_matrix(g.rot)
        o = np.array(g.origin)
        for ch in g.children:
            if isinstance(ch, Cube):
                for f, pts in face_quads(ch).items():
                    pts = [M @ (R @ (p - o) + o) + t for p in pts]
                    out.append((ch, f, pts))
            else:
                walk(ch, M @ R, M @ (o - R @ o) + t)
    walk(root, np.eye(3), np.zeros(3))
    return out


def render(faces, atlas, yaw, pitch=0.0, scale=12.5, size=(560, 640), center=(0, 21.5, 0)):
    """正交渲染。yaw=0 从正面（-Z）看。"""
    W, H = size
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    # 相机：位于 -Z 方向绕 Y 旋转 yaw；forward 指向模型
    fwd = np.array([sy * cp, -sp, cy * cp])
    up0 = np.array([0, 1, 0])
    right = np.cross(fwd, up0)
    right = right / np.linalg.norm(right)
    up = np.cross(right, fwd)
    up = -up if up[1] < 0 else up
    # 校验：yaw=0 时 right 应为 -X（角色右手在画面左）
    img = np.zeros((H, W, 3), np.float32)
    img[:] = (0.86, 0.87, 0.9)
    zb = np.full((H, W), np.inf)
    light = np.array([-0.35, 0.85, -0.55])
    light /= np.linalg.norm(light)
    c = np.array(center, float)
    for cube, f, pts in faces:
        P = np.array(pts) - c
        n = np.cross(P[3] - P[0], P[1] - P[0])
        nn = np.linalg.norm(n)
        if nn < 1e-9:
            continue
        n /= nn
        if np.dot(n, fwd) >= -1e-6:
            continue  # 背面剔除（n 指向外侧）
        u = P @ right * scale + W / 2
        v = -(P @ up) * scale + H / 2
        d = P @ fwd
        A = np.array([u[0], v[0]])
        eB = np.array([u[1] - u[0], v[1] - v[0]])
        eD = np.array([u[3] - u[0], v[3] - v[0]])
        det = eB[0] * eD[1] - eB[1] * eD[0]
        if abs(det) < 1e-6:
            continue
        x0, x1 = int(max(0, np.floor(u.min()))), int(min(W - 1, np.ceil(u.max())))
        y0, y1 = int(max(0, np.floor(v.min()))), int(min(H - 1, np.ceil(v.max())))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        rx, ry = xs - A[0], ys - A[1]
        s = (rx * eD[1] - ry * eD[0]) / det
        t = (eB[0] * ry - eB[1] * rx) / det
        m = (s >= 0) & (s < 1) & (t >= 0) & (t < 1)
        if not m.any():
            continue
        uv = cube.faces[f]
        tu = np.clip((uv[0] + s * (uv[2] - uv[0])).astype(int), uv[0], uv[2] - 1)
        tv = np.clip((uv[1] + t * (uv[3] - uv[1])).astype(int), uv[1], uv[3] - 1)
        tex = atlas[tv, tu]
        m &= tex[..., 3] > 127
        dep = d[0] + s * (d[1] - d[0]) + t * (d[3] - d[0])
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        m &= dep < sub - 1e-4
        shade = 0.8 + 0.2 * max(0.0, float(np.dot(n, light)))
        if f == "up":
            shade = min(1.0, shade + 0.06)
        col = tex[..., :3].astype(np.float32) / 255 * shade
        sub[m] = dep[m]
        im = img[y0:y1 + 1, x0:x1 + 1]
        im[m] = col[m]
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def preview(root, atlas):
    faces = collect_faces(root)
    views = [("正面", 0, 0), ("左侧", 90, 0), ("背面", 180, 0), ("3/4", 35, 12)]
    tiles = [Image.fromarray(render(faces, atlas, yaw, pitch)) for _, yaw, pitch in views]
    w, h = tiles[0].size
    sheet = Image.new("RGB", (w * len(tiles), h), (220, 222, 228))
    for i, t in enumerate(tiles):
        sheet.paste(t, (i * w, 0))
    sheet.save(OUT / "preview.png")
    # 脸部特写
    face = render(faces, atlas, 0, 0, scale=56, size=(640, 520), center=(0, 29.5, 0))
    Image.fromarray(face).save(OUT / "preview_face.png")
    face34 = render(faces, atlas, 30, 8, scale=48, size=(640, 520), center=(0, 29.5, 0))
    Image.fromarray(face34).save(OUT / "preview_face34.png")
    return faces


def main():
    root = build()
    atlas = make_atlas(root)
    ne, ng = export_bbmodel(root, atlas, OUT / "longnu.bbmodel")
    preview(root, atlas)
    print("cubes", ne, "groups", ng, "atlas", atlas.shape)


if __name__ == "__main__":
    main()
