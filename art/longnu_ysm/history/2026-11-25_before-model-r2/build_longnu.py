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
    "hair": (57, 49, 54), "hair_d": (44, 37, 42), "hair_l": (65, 57, 62), "hair_hl": (74, 66, 71),
    "skin": (252, 234, 224), "skin_s": (240, 214, 204), "skin_d": (226, 190, 182),
    "blush": (248, 214, 207), "mouth": (233, 192, 187),
    "white": (250, 250, 251), "white_s": (230, 230, 236), "white_d": (206, 206, 216),
    "pleat": (240, 239, 244), "black": (40, 34, 38), "black_l": (60, 52, 58),
    "red": (208, 32, 38), "red_s": (168, 20, 28), "red_d": (124, 12, 20), "red_l": (232, 70, 66),
    "flower": (158, 18, 30), "flower_s": (120, 10, 22), "flower_c": (84, 6, 14),
    "tail": (122, 58, 70), "tail_d": (98, 42, 56), "tail_l": (142, 74, 86),
    "horn": (240, 202, 202), "horn_s": (222, 170, 176), "horn_d": (200, 146, 154),
    "gem": (200, 24, 36), "gem_l": (250, 120, 120), "silver": (200, 200, 210),
    # 眼睛
    "lash": (36, 22, 28), "lash_m": (78, 40, 46),
    "scl": (255, 251, 250), "scl_s": (226, 214, 220),
    "iris_d": (112, 10, 22), "iris": (196, 24, 34), "iris_l": (239, 59, 60), "iris_o": (246, 128, 98),
    "pupil": (64, 4, 14), "hl": (255, 255, 255),
}



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


def hair(tone="hair"):
    """让几何转折决定明暗，整块着色。"""
    side_tones = {"hair_d": (41, 35, 39), "hair": (52, 45, 49), "hair_l": (62, 54, 58)}
    def paint(face, w, h, cube):
        color = C[tone]
        if face in ("east", "west"):
            color = side_tones[tone]
        elif face == "up":
            color = C["hair_hl" if tone == "hair_l" else "hair_l"]
        elif face == "down":
            color = C["hair_d"]
        return np.full((h, w, 4), rgba(color), np.uint8)
    return paint

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
            a[-1, :] = rgba((148, 19, 31))
        return a
    return p


def bow_paint(key="red"):
    def paint(face, w, h, cube):
        shade = "red_s" if face in ("down", "west") else key
        return np.full((h, w, 4), rgba(C[shade]), np.uint8)
    return paint

def skin_part(shade_bottom=False):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        a[:] = rgba(C["skin"])
        if shade_bottom and face not in ("up", "down"):
            a[-1:, :] = rgba(C["skin_s"])
        return a
    return p


def iris(face, w, h, cube):
    # 眼白留在虹膜两侧，底边通透；竖瞳单独挂在 Pupil 骨骼。
    pixels = np.full((h, w, 4), rgba(C["scl"]), np.uint8)
    if face == "north":
        iris_area = pixels[:, 1:-1]
        iris_area[:] = rgba(C["iris"])
        iris_area[:max(1, h // 3)] = rgba(C["iris_d"])
        iris_area[-max(1, h // 3):] = rgba(C["iris_l"])
    return pixels

# ------------------------------------------------------------------ model types
class Cube:
    def __init__(self, name, frm, to, paint, origin=None, rot=(0, 0, 0), inflate=0.0, **kw):
        self.name = name
        self.frm = [float(v) for v in frm]
        self.to = [float(v) for v in to]
        if not all(math.isfinite(a) and math.isfinite(b) and a < b for a, b in zip(self.frm, self.to)):
            raise ValueError(f"无效方块 {name}: {frm} -> {to}")
        self.paint = paint
        self.origin = list(origin) if origin is not None else [(a + b) / 2 for a, b in zip(self.frm, self.to)]
        self.rot = list(rot)
        self.inflate = inflate
        self.role = kw.pop("role", "")
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
    # 诺米 Face 原方块的界限、轴心与旋转（单位同原工程）。
    face.c("面部·颊中", (-3.67568, 27.34, -3.16), (3.56757, 32.97297, 3.22), flat("skin"),
           origin=(-0.05405, 29.91892, -0.14))
    face.c("颌底·平段", (-1.8, 26.65, -3.498), (1.8, 27.44, 3.05), flat("skin"),
           origin=(0, 26.65, -3.498))
    face.c("颌缘·右2", (3.03, 26.98, -3.492), (3.65, 27.61, 3.044), flat("skin"),
           origin=(3.34, 26.98, -3.492), rot=(0, 0, 18.2))
    face.c("颌缘·右1", (2.34, 26.79, -3.494), (3.04, 27.52, 3.046), flat("skin"),
           origin=(2.69, 26.79, -3.494), rot=(0, 0, 12.5))
    face.c("颌缘·右0", (1.797, 26.68, -3.496), (2.35, 27.46, 3.048), flat("skin"),
           origin=(2.0735, 26.68, -3.496), rot=(0, 0, 6.8))
    face.c("颌缘·左2", (-3.65, 26.98, -3.492), (-3.03, 27.61, 3.044), flat("skin"),
           origin=(-3.34, 26.98, -3.492), rot=(0, 0, -18.2))
    face.c("颌缘·左1", (-3.04, 26.79, -3.494), (-2.34, 27.52, 3.046), flat("skin"),
           origin=(-2.69, 26.79, -3.494), rot=(0, 0, -12.5))
    face.c("颌缘·左0", (-2.35, 26.68, -3.496), (-1.797, 27.46, 3.048), flat("skin"),
           origin=(-2.0735, 26.68, -3.496), rot=(0, 0, -6.8))
    face.c("短侧颊", (2.81081, 27.24324, -3.315), (3.67568, 29.51351, 3.115), flat("skin"),
           origin=(3.24324, 28.37838, -0.1), rot=(0, 0, 8))
    face.c("轻颊色", (2.12541, 27.62162, -3.506), (2.68541, 27.83784, -3.497), flat("blush"),
           origin=(2.40541, 27.72973, -3.53))
    face.c("短侧颊", (-3.67568, 27.24324, -3.315), (-2.81081, 29.51351, 3.115), flat("skin"),
           origin=(-3.24324, 28.37838, -0.1), rot=(0, 0, -8))
    face.c("轻颊色", (-2.68541, 27.62162, -3.506), (-2.12541, 27.83784, -3.497), flat("blush"),
           origin=(-2.40541, 27.72973, -3.53))
    face.c("下唇一笔", (-0.32432, 27.24324, -3.565), (0.10811, 27.40541, -3.495), flat("mouth"),
           origin=(-0.10811, 27.32432, -3.53))
    face.c("眶下颊面", (-3.67568, 27.34, -3.5), (3.56757, 28.01, -3.17), flat("skin"),
           origin=(-0.05405, 27.4375, -3.335))
    face.c("额面压边", (-3.67568, 30.35, -3.5), (3.56757, 32.974, -3.17), flat("skin"),
           origin=(-0.05405, 31.662, -3.335))
    face.c("鼻梁分眼", (-0.99, 28.01, -3.5), (0.99, 30.35, -3.17), flat("skin"),
           origin=(0, 29.18, -3.335))
    face.c("左眶侧壁", (-3.67568, 28.01, -3.5), (-3.26, 30.35, -3.17), flat("skin"),
           origin=(-3.46784, 29.18, -3.335))
    face.c("右眶侧壁", (3.26, 28.01, -3.5), (3.56757, 30.35, -3.17), flat("skin"),
           origin=(3.41378, 29.18, -3.335))
    face.c("乳白浅眼窝底", (-3.27, 28, -3.355), (-1, 30.34, -3.165), flat("scl"),
           origin=(-2.135, 29.17, -3.26))
    face.c("乳白浅眼窝底", (1, 28, -3.355), (3.27, 30.34, -3.165), flat("scl"),
           origin=(2.135, 29.17, -3.26))

    eyes = face.g("Eyes", (0, 29.4, FZ))
    brow = eyes.g("Eyebrow", (0, 31, FZ))
    lid = eyes.g("Eyelid", (0, 30.1, FZ))
    for side, nm in ((1, "Right"), (-1, "Left")):
        brow.g(nm + "Eyebrow", (side * 2.1, 31, FZ))
        el = lid.g(nm + "Eyelid", (side * 2.1, 30.1, FZ))
        for name, x0, x1, y0, y1 in (
                ("上缘深睫", 1.04, 2.41, 29.84, 30.30),
                ("上睫·外侧过渡", 2.41, 2.97, 29.84, 30.17),
                ("外睫顿笔", 2.97, 3.21, 29.64, 30.03)):
            el.c(nm + name, *box(side*x0, side*x1, y0, y1, -3.478, -3.446), flat("lash"))
        base = el.g(nm + "EyesBase", (side * 2.1, 29.15, -3.395))
        base.c(nm + "·红眼", *box(side*1.10, side*3.10, 28.08, 30.13, -3.395, -3.351), iris)
        pupil = base.g(nm + "Pupil", (side*2.1, 29.15, -3.40))
        pupil.c(nm + "·竖瞳", *box(side*1.92, side*2.28, 28.91, 29.80, -3.413, -3.391), flat("pupil"))
    head.g("ViewLocator", (0, 29.4, FZ))

    hairg = head.g("Hair", (0, 30.5, 0.4))
    bh = hairg.g("BaseHair", (0, 30, 1))
    bh.c("内发颅", (-4.70, 32.12, -3.45), (4.70, 35.12, 3.92), hair())
    bh.c("冠顶收阶", (-3.65, 34.55, -3.30), (3.65, 35.95, 3.62), hair())
    bh.c("冠顶分水", (-2.35, 35.52, -2.76), (2.35, 36.44, 3.05), hair("hair_l"))
    bh.c("后颅承托", (-4.17, 26.78, 0.95), (4.17, 34.42, 4.03), hair("hair_d"))
    oh = hairg.g("OuterHair", (0, 34, 0))
    fr = hairg.g("front_h1", (0, 33.1, -3.6))
    overlay = fr.g("FringeOverlay", (0, 32, -3.8))
    # 下端的收阶让眉峰露出两道窄缝，上端各束相连。
    bangs = [(-1.23, 1.18, 30.48, 35.82, -4.23),
             (1.17, 1.85, 30.80, 35.57, -4.05), (-1.89, -1.22, 30.82, 35.53, -4.06),
             (2.05, 3.28, 30.94, 35.16, -3.99), (-3.32, -2.09, 30.96, 35.13, -4.0),
             (3.24, 4.52, 30.47, 34.60, -3.87), (-4.50, -3.30, 30.45, 34.63, -3.88)]
    for i, (x0, x1, y0, y1, z) in enumerate(bangs):
        fr.c(f"主刘海{i}", (x0, y0, z), (x1, y1, z+1.02), hair("hair_l" if i in (0,3,4) else "hair"), rot=(2, 0, 0))
        fr.c(f"发梢收阶{i}", (x0+.10, y0-.26, z+.04), (x1-.10, y0+.35, z+.84), hair())
    fr.c("额前内发", (-3.45,31.54,-3.73),(3.45,34.99,-3.36),hair("hair_d"))
    overlay.c("冠前收阶", (-2.11,34.95,-4.02),(2.11,35.68,-3.28),hair("hair_l"))
    overlay.c("冠前分水", (-1.52,35.63,-3.64),(1.52,36.22,-2.60),hair())
    overlay.c("中央发尖", (-.80, 30.07, -4.15), (.80, 30.45, -3.50), hair())
    for i, (x0, x1, end, top_y, depth) in enumerate((
            (-4.47,-3.35,27.55,33.92,4.23),(-3.50,-1.95,27.02,34.75,4.65),
            (-2.10,-.87,26.68,35.41,4.84),(-1.02,1.00,26.27,35.84,4.99),
            (.85,2.08,26.68,35.43,4.83),(1.94,3.53,27.02,34.77,4.64),
            (3.35,4.47,27.57,33.90,4.24))):
        bh.c(f"短后发{i+1}", (x0, end+.38, 2.96), (x1, top_y, depth), hair("hair_l" if i in (2,4) else "hair"))
        bh.c(f"后发收阶{i+1}", (x0+.08, end, 2.95), (x1-.08, end+.65, depth-.14), hair("hair_d"))
        # 第二层弧线反向错位，暗阶在发尾露出。
        oh.c(f"后冠覆发{i+1}", (x0+.02, 29.75+abs(i-3)*.42, depth-.56),
             (x1-.02, top_y-.42, depth+.16), hair("hair_l" if i in (0,3,6) else "hair"))

    flh = hairg.g("FLongHair", (0, 27.6, 2.3))
    mlh = flh.g("MLongHair", (0, 27.5, 2.3))
    lh = mlh.g("LongHair", (0, 27.45, 2.3))
    rib = hairg.g("Ribbon", (0, 28.6, -.5))
    for side, nm in ((1, "Right"), (-1, "Left")):
        def paired(group, name, x0, x1, y0, y1, z0, z1, paint, **kw):
            return group.c(nm + name, *box(side*x0, side*x1, y0, y1, z0, z1), paint, **kw)
        paired(bh,"两鬓底发",3.36,4.78,26.55,34.15,-3.60,3.35,hair("hair_d"))
        for i in range(4):
            z = -3.25 + 1.49*i
            paired(oh, f"冠侧转折{i}", 3.90, 5.10-.11*(i%2), 31.24-.30*(i%2),
                   34.72-.14*i, z, z+1.62, hair("hair" if i%2 else "hair_l"), rot=(0,0,-side*9))
        paired(oh,"冠肩斜面",3.12,4.69,33.78,35.57,-3.11,3.05,hair(),rot=(0,0,-side*23))
        paired(bh,"耳后覆发",4.24,5.04,26.51,31.48,.14,3.58,hair())
        paired(bh,"耳根",4.73,4.87,29.43,29.94,-.83,-.12,skin_part())
        cg = hairg.g("corner_h1" if side>0 else "corner_h2", (side*3.77,32.5,-2.8))
        # 前束沿肩前缘贴下，在腰际向内收尖。
        locks = [(3.24,4.77,29.47,33.52,-3.85,-1.26), (3.28,4.81,27.12,30.48,-3.91,-1.22),
                 (3.35,4.91,25.10,28.25,-3.83,-1.31), (3.52,5.04,23.35,25.80,-3.60,-1.43),
                 (3.87,5.28,21.60,24.08,-3.46,-1.55), (4.05,5.12,20.12,22.26,-3.31,-1.66),
                 (4.11,4.77,19.56,20.59,-3.14,-1.78)]
        for i, bounds in enumerate(locks):
            paired(cg, f"鬓角{i+1}", *bounds, hair("hair" if i not in (2,5) else "hair_l"))
        pony = [(3.88,5.09,25.6,27.64,1.02,3.12),(4.07,5.39,24.07,26.12,1.15,3.36),
                (4.35,5.79,22.38,24.68,1.39,3.53),(4.78,6.47,20.82,22.91,1.70,3.77),
                (5.31,6.79,19.06,21.29,1.94,4.01),(5.70,6.64,18.21,19.65,2.21,3.85)]
        parent = lh
        for i, bounds in enumerate(pony):
            if i % 2 == 0:
                name = nm + "SideLock" + (str(i//2) if i else "")
                parent = parent.g(name,(side*(bounds[0]+bounds[1])/2,bounds[3],(bounds[4]+bounds[5])/2))
            paired(parent, f"低马尾{i+1}", *bounds, hair("hair_l" if i in (1,4) else "hair"))
        flower_center = (side*5.19,28.58,-.52)
        fg = rib.g(nm + "HairFlower", flower_center)
        add_flower(fg, nm+"发花", flower_center, side)

        hg = head.g(nm+"Horn", (side*3.60,34.24,-.76))
        # 基部先展开，中上段回弯，分叉与主角在中下部相接。
        for i, (x, y0, y1, z, width, depth, tilt) in enumerate((
                (3.67,34.18,35.70,-.95,1.74,1.73,-11),(4.03,35.42,37.04,-.86,1.63,1.58,-12),
                (4.36,36.76,38.36,-.70,1.44,1.39,-8),(4.49,38.13,39.50,-.49,1.21,1.17,-1),
                (4.39,39.27,40.57,-.25,.98,.94,8),(4.19,40.38,41.26,-.03,.78,.75,12),
                (3.99,41.07,41.87,.13,.60,.60,14))):
            paired(hg,f"龙角{i+1}",x-width/2,x+width/2,y0,y1,z-depth/2,z+depth/2,horn(),rot=(6,0,side*tilt))
        paired(hg,"支角根",4.50,5.19,35.72,36.61,-1.01,-.24,horn(),rot=(0,0,-side*22))
        paired(hg,"支角尖",5.05,5.51,36.34,37.18,-.93,-.36,horn(),rot=(0,0,-side*18))
        eg = head.g(nm+"Ear", (side*4.85,33.45,-.45))
        paired(eg,"尖耳根",4.73,5.61,33.25,34.10,-1.13,.03,horn())
        paired(eg,"尖耳身",5.49,6.05,33.17,33.88,-1.01,-.06,horn())
        paired(eg,"耳尖",5.96,6.40,33.05,33.53,-.91,-.20,horn())

    arm = upper.g("Arm", (0, 25.8, 0))
    for side, nm in ((1, "Right"), (-1, "Left")):
        x = side*3.86
        ua = arm.g(nm+"Arm", (x,25.45,0), rot=(0,0,side*12))
        ua.c(nm+"上臂", (x-1.03,21.59,-1.07),(x+1.03,25.45,1.07),skin_part())
        fa = ua.g(nm+"ForeArm", (x,21.59,0))
        fa.c(nm+"前臂", (x-.98,18.10,-1.01),(x+.98,21.59,1.01),skin_part())
        hd = fa.g(nm+"Hand", (x,18.10,0))
        hd.c(nm+"手", (x-.95,15.62,-.97),(x+.95,18.10,.97),skin_part(True))
        hd.g(nm+"HandLocator", (x,15.7,0))

    # ---------------- 上衣
    top = upper.g("FittedTop", (0, 22.6, 0))
    top.c("胸身", (-3.4, 21.3, -1.9), (3.4, 25.6, 1.9), flat("white"))
    top.c("收腰", (-3.1, 19.0, -1.75), (3.1, 21.3, 1.75), flat("white"))
    top.c("腰带", (-3.25, 19.5, -1.9), (3.25, 20.8, 1.9), flat("black", edge="black_l"))
    upper.c("颈部", (-1.0, 25.3, -1.0), (1.0, 27.5, 1.0), skin_part())
    col = upper.g("Collar", (0, 25.8, 0))
    col.c("后领", (-1.80,25.35,-.40),(1.80,25.96,1.30),flat("white_s"))
    for side in (-1, 1):
        col.c(f"翻领{side}", *box(side*.49,side*1.79,24.59,25.86,-2.13,-1.82), flat("white_s"), rot=(0,0,-side*12))
        col.c(f"领尖{side}", *box(side*.67,side*1.27,24.21,24.88,-2.18,-1.91), flat("white"), rot=(0,0,-side*18))
    br = upper.g("Breast", (0,24.9,-1.8))
    for side in (-1,1):
        strand(br,f"银链{side}", (side*.69,24.87,-2.02),(0,23.75,-2.07),.10,.12,flat("silver"))
    br.c("吊坠·尖", (-.13,23.43,-2.27),(.13,23.80,-2.03),flat("red_s"))
    br.c("吊坠·水滴", (-.29,22.96,-2.34),(.29,23.49,-2.03),flat("gem"))
    br.c("吊坠·收底", (-.20,22.86,-2.26),(.20,23.00,-2.03),flat("red_s"))

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
        ft.c(nm + "脚掌", f, t, skin_part())

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
        tiers.append((19.2 - 0.5 * (i + 1), 19.2 - 0.5 * i, 3.3 + 0.19 * i, 2.35 + 0.115 * i, flat("white")))
    tiers.append((13.2, 14.2, 5.35, 3.55, flat("black", edge="black_l")))
    for i, (y0, y1, hw, hd, pnt) in enumerate(tiers):
        panels["FrontSkirt"].c("裙前%d" % i, (-hw, y0, -hd), (hw, y1, -hd + TH), pnt)
        panels["BackSkirt"].c("裙后%d" % i, (-hw, y0, hd - TH), (hw, y1, hd), pnt)
        panels["LeftSkirt"].c("裙左%d" % i, (-hw, y0, -hd + TH), (-hw + TH, y1, hd - TH), pnt)
        panels["RightSkirt"].c("裙右%d" % i, (hw - TH, y0, -hd + TH), (hw, y1, hd - TH), pnt)
    sk.c("裙内衬", (-3.25, 18.9, -2.25), (3.25, 19.15, 2.25), flat("white_d"))
    # 连续斜褶略高于裙面，侧面与正面有真实深度差。
    for panel, depth in (("FrontSkirt",-1),("BackSkirt",1)):
        for sign in (-1,1):
            strand(panels[panel],f"{panel}褶{sign}",(sign*2.18,19.20,depth*2.37),
                   (sign*3.90,14.18,depth*3.49),1.24,.16,flat("pleat"))
    kx, ky, kz = -1.60, 20.0, -2.22
    bowg = wf.g("WaistBow", (kx,ky,kz))
    bowg.c("结心",(kx-.37,ky-.50,kz-.54),(kx+.37,ky+.50,kz+.10),bow_paint("red_s"))
    for side in (-1,1):
        bowg.c(f"蝶翼·内{side}", *box(kx+side*.24,kx+side*.91,ky-.47,ky+.47,kz-.38,kz+.08),bow_paint(),rot=(0,0,side*9))
        bowg.c(f"蝶翼·外{side}", *box(kx+side*.77,kx+side*1.50,ky-.90,ky+.90,kz-.33,kz+.11),bow_paint(),rot=(0,0,side*7))
    # 相邻段共享中心点且略重叠，裙底以下自由下垂。
    for idx, (x0, x1, x2, x3, end, width) in enumerate((
            (-1.97,-2.09,-3.89,-5.05,9.6,.99),(-1.19,-1.13,-2.36,-2.85,10.8,.86))):
        points = [(x0,19.82,-2.39),(x1,19.20,-2.49),(x2,13.29,-3.60),(x3,end,-3.33-idx*.78)]
        parent = bowg
        for j, (a,b) in enumerate(zip(points,points[1:])):
            group_name = f"RibbonTail{j}" if idx==0 else f"InnerRibbonTail{j}"
            parent = parent.g(group_name,a)
            strand(parent, f"飘带{idx+1}·{j+1}",a,b,width,.57,bow_paint("red" if idx==0 else "red_s"))

    path = [(.4,13.5,2.20),(2.34,12.25,2.57),(3.43,10.19,2.97),(4.01,8.78,3.15),
            (4.67,7.11,3.49),(5.04,4.60,3.67),(6.50,3.0,4.20)]

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
        if i == 3:
            mid = q + np.array([.52, .20, -.33])
            fg = seg.g("TailFlowerMid", tuple(mid))
            add_flower(fg, "尾花中", tuple(mid), 0)
        parent = seg
    fg = parent.g("TailFlowerTip", path[-1])
    add_flower(fg, "尾花尖", path[-1], 0)

    root.g("molang", (0, -0.3, 0))
    return root


def strand(group, name, a, b, width, depth, paint):
    """把方块的局部 -Y 指向下一锚点。两端各留接缝余量。"""
    direction = np.subtract(b, a)
    length = np.linalg.norm(direction)
    center = (np.array(a) + b) / 2
    pitch = -math.degrees(math.asin(direction[2] / length))
    roll = math.degrees(math.atan2(direction[0], -direction[1]))
    half = np.array([width, length+.16, depth]) / 2
    group.c(name, center-half, center+half, paint, rot=(pitch,0,roll))


def add_flower(group, name, center, side):
    """以芯为轴，耳侧的四瓣沿 YZ 对角展开；花冠略朝前，正背面也能看到花瓣分离。"""
    c = np.asarray(center)
    core = c + (side*.30, 0, 0)
    group.c(name+"·芯", core-.39, core+.39, flower(), role="core")
    for vertical in (-1,1):
        for lateral in (-1,1):
            if side:
                pos = c + (side*(.37+lateral*.49), vertical*.54, lateral*.54)
                half = np.array([.41,.32,.34])
                rotation = (45,0,-side*vertical*lateral*23)
            else:
                pos = c + (lateral*.61,vertical*.62,-lateral*.55)
                half = np.array([.46,.43,.40])
                rotation = (0,0,vertical*lateral*16)
            group.c(f"{name}·瓣{vertical}_{lateral}", pos-half,pos+half,flower(),rot=rotation)

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
    texture_name = path.with_suffix(".png").name
    path.with_suffix(".png").write_bytes(png)
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
            "name": texture_name, "relative_path": texture_name, "folder": "", "namespace": "", "id": "0",
            "group": "", "scope": 0, "width": W, "height": H, "uv_width": W, "uv_height": H,
            "particle": False, "use_as_default": False, "layers_enabled": False, "sync_to_project": "",
            "file_format": "png", "render_mode": "default", "render_sides": "auto", "wrap_mode": "limited",
            "pbr_channel": "color", "fps": 7, "force_translucent": False, "frame_time": 1,
            "frame_order_type": "loop", "frame_order": "", "frame_interpolate": False, "visible": True,
            "internal": True, "saved": True,
            "uuid": str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, texture_name)),
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
        # 骨骼旋转递归传递给子方块。
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
        shade = 0.91 + 0.09 * max(0.0, float(np.dot(n, light)))
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
    face = render(faces, atlas, 0, 0, scale=46, size=(680, 520), center=(0, 29.5, 0))
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
