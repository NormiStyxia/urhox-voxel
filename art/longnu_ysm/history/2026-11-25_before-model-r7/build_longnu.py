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
    "hair": (54, 46, 52), "hair_soft": (59, 51, 56), "hair_d": (36, 30, 35), "hair_l": (74, 64, 71), "hair_hl": (92, 81, 88),
    "skin": (252, 234, 224), "skin_s": (240, 214, 204), "skin_d": (226, 190, 182),
    "blush": (251, 227, 219), "mouth": (233, 192, 187),
    "white": (250, 250, 251), "white_s": (230, 230, 236), "white_d": (206, 206, 216),
    "pleat": (240, 239, 244), "black": (40, 34, 38), "black_l": (60, 52, 58),
    "red": (230, 44, 49), "red_s": (168, 20, 28), "red_d": (124, 12, 20), "red_l": (232, 70, 66),
    "flower": (177, 23, 33), "flower_s": (120, 10, 22), "flower_c": (84, 6, 14),
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
    side_tones = {"hair_soft": (51, 44, 48), "hair_d": (33, 28, 31), "hair": (48, 41, 46), "hair_l": (66, 57, 63)}
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

def horn(tier=2):
    def p(face, w, h, cube):
        a = np.zeros((h, w, 4), np.uint8)
        base = C["horn_s"] if face in ("east", "west", "south") else C["horn"]
        a[:] = rgba(tuple(channel + (tier-2)*3 for channel in base))
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
            a[-1, :] = rgba((160, 20, 32))
        return a
    return p


def bow_paint(key="red"):
    def paint(face, w, h, cube):
        shade = ({"red": "red_s", "red_s": "red_d"}[key]
                 if face in ("down", "west") else key)
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
    # 内侧眼白单独建模，虹膜的三个色阶完整覆盖正面。
    pixels = np.full((h, w, 4), rgba(C["scl"]), np.uint8)
    if face == "north":
        iris_area = pixels
        iris_area[:] = rgba(C["iris"])
        iris_area[:max(1, round(h * .35))] = rgba(C["iris_d"])
        iris_area[-max(1, round(h * .30)):] = rgba(C["iris_l"])
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
        for child in self.children:
            if isinstance(child, Group) and child.name == name:
                return child
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
def nomi_skeleton():
    """保留诺米 BB 工程的轴系、原始 UUID 和全部定位器，Bedrock 的 X 轴与其相反。"""
    nodes = {}
    for row in json.loads((OUT / "ref/nomi_rig.json").read_text()):
        bone = Group(row["name"], row["origin"], row["rotation"])
        bone.uuid = row["uuid"]
        nodes[bone.name] = bone
        if row["parent"] is not None:
            nodes[row["parent"]].children.append(bone)
    return nodes


def skirt_section(bone, name, lo, hi, yaw, paint):
    # 裙片按静止姿态设计。将它变回摆动骨的局部坐标，保留模板自身的 rest rotation。
    if not any(bone.rot):
        bone.c(name,lo,hi,paint,rot=(0,yaw,0))
        return
    inverse = rot_matrix(bone.rot).T
    center = (np.asarray(lo) + hi) / 2
    pivot = np.asarray(bone.origin)
    offset = inverse @ (center-pivot) + pivot - center
    local = inverse @ rot_matrix((0,yaw,0))
    rx = math.atan2(local[2,1],local[2,2])
    ry = math.asin(-local[2,0])
    rz = math.atan2(local[1,0],local[0,0])
    bone.c(name, np.asarray(lo)+offset, np.asarray(hi)+offset, paint, rot=np.degrees([rx,ry,rz]))


def build():
    """全部坐标按诺米 .bbmodel 实测：腿 0–18.7、躯干 18.8–25.8、颈 25.3–27.5、脸 26.6–33.0（宽 7.4）、肩 25.3。"""
    rig = nomi_skeleton()
    root = rig["Root"]
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
    face.c("轻颊色", (2.12541, 27.43162, -3.506), (2.68541, 27.63784, -3.497), flat("blush"),
           origin=(2.40541, 27.53973, -3.53))
    face.c("短侧颊", (-3.67568, 27.24324, -3.315), (-2.81081, 29.51351, 3.115), flat("skin"),
           origin=(-3.24324, 28.37838, -0.1), rot=(0, 0, -8))
    face.c("轻颊色", (-2.68541, 27.43162, -3.506), (-2.12541, 27.63784, -3.497), flat("blush"),
           origin=(-2.40541, 27.53973, -3.53))
    face.c("下唇一笔", (-0.32432, 27.24324, -3.565), (0.10811, 27.40541, -3.495), flat("mouth"),
           origin=(-0.10811, 27.32432, -3.53))
    face.c("眶下颊面", (-3.67568, 27.34, -3.5), (3.56757, 27.65, -3.17), flat("skin"),
           origin=(-0.05405, 27.4375, -3.335))
    face.c("额面压边", (-3.67568, 30.10, -3.455), (3.56757, 32.974, -3.17), flat("skin"),
           origin=(-0.05405, 31.662, -3.335))
    face.c("鼻梁分眼", (-0.70, 27.65, -3.5), (0.70, 30.35, -3.17), flat("skin"),
           origin=(0, 29.18, -3.335))
    face.c("左眶侧壁", (-3.67568, 27.65, -3.5), (-3.20, 30.35, -3.17), flat("skin"),
           origin=(-3.46784, 29.18, -3.335))
    face.c("右眶侧壁", (3.20, 27.65, -3.5), (3.56757, 30.35, -3.17), flat("skin"),
           origin=(3.41378, 29.18, -3.335))
    face.c("乳白浅眼窝底", (-3.21, 27.65, -3.355), (-.70, 30.10, -3.165), flat("scl"),
           origin=(-2.135, 29.17, -3.26))
    face.c("乳白浅眼窝底", (.70, 27.65, -3.355), (3.21, 30.10, -3.165), flat("scl"),
           origin=(2.135, 29.17, -3.26))

    eyes = face.g("Eyes", (0, 29.4, FZ))
    brow = eyes.g("Eyebrow", (0, 31, FZ))
    lid = eyes.g("Eyelid", (0, 30.1, FZ))
    for side, nm in ((1, "Right"), (-1, "Left")):
        brow.g(nm + "Eyebrow", (side * 2.1, 31, FZ))
        el = lid.g(nm + "Eyelid", (side * 2.1, 30.1, FZ))
        for name, x0, x1, y0, y1 in (
                ("上缘深睫", .70, 2.41, 29.95, 30.16),
                ("上睫·外侧过渡", 2.41, 2.97, 29.95, 30.19),
                ("外睫顿笔", 2.97, 3.23, 29.91, 30.17)):
            el.c(nm + name, *box(side*x0, side*x1, y0, y1, -3.478, -3.446), flat("lash"))
        base = el.g(nm + "EyesBase", (side * 2.1, 29.15, -3.395))
        base.c(nm + "·红眼", *box(side*1.00, side*3.20, 27.65, 29.95, -3.395, -3.351), iris)
        base.c(nm + "·内侧眼白", *box(side*.70, side*1.00, 27.65,29.95,-3.395,-3.351),flat("scl"))
        pupil = base.g(nm + "Pupil", (side*2.1, 29.15, -3.40))
        pupil.c(nm + "·竖瞳", *box(side*1.92, side*2.28, 28.25, 29.56, -3.413, -3.391), flat("pupil"))
    head.g("ViewLocator", (0, 29.4, FZ))

    hairg = head.g("Hair", (0, 30.5, 0.4))
    bh = hairg.g("BaseHair", (0, 30, 1))
    oh = hairg.g("OuterHair", (0, 34, 0))
    fr = hairg.g("front_h1", (0, 33.1, -3.6))
    overlay = fr.g("FringeOverlay", (0, 32, -3.8))
    # 逐层收小宽度与前后深度。每层两侧各切掉两级边角。
    crown = [
        (31.05,33.35,6.34,-4.98,6.10,1.48), (33.26,34.27,6.12,-5.39,5.84,1.36),
        (34.18,35.21,5.64,-5.27,5.66,1.23), (35.12,36.16,5.03,-4.72,5.13,1.09),
        (36.07,37.09,4.42,-4.08,4.52,.96), (37.00,37.66,3.58,-3.30,3.48,.88),
        (37.57,38.00,2.79,-2.52,2.28,.71),
    ]
    for level,(bottom,top_y,radius,front,back,bevel) in enumerate(crown):
        bh.c(f"冠顶{level}·中段", (-radius+bevel,bottom,front),(radius-bevel,top_y,back),hair())
        for side in (-1,1):
            for j,(inner,outer,cut) in enumerate(((radius-bevel,radius-.44,.37),(radius-.44,radius,.99))):
                oh.c(f"冠侧{level}·{side}·{j}", *box(side*inner,side*outer,bottom,top_y,
                     front+bevel*cut,back-bevel*cut),hair())
    bangs = [(-5.90,-4.28,30.54,34.58,-4.93),(-4.29,-2.95,30.75,35.33,-5.13),
             (-2.97,-1.22,30.58,35.78,-5.27),(-1.24,1.25,30.08,36.03,-5.39),
             (1.23,2.94,30.75,35.68,-5.23),(2.92,4.34,30.49,35.17,-5.12),
             (4.32,5.90,30.21,34.43,-4.88)]
    for i,(x0,x1,end,top_y,z) in enumerate(bangs):
        tone = "hair_soft" if i in (1,5) else "hair"
        fr.c(f"刘海{i}·主束",(x0,end+.28,z),(x1,top_y,z+1.48),hair(tone))
        inset = .18 if i==3 else .13
        overlay.c(f"刘海{i}·梢",(x0+inset,end,z+.05),(x1-inset,end+.34,z+1.16),hair(tone))
    for i,(x0,x1,end) in enumerate(((-6.13,-4.12,26.84),(-4.16,-2.54,26.13),
                                     (-2.58,-1.14,25.52),(-1.18,1.18,25.03),
                                     (1.14,2.58,25.52),(2.54,4.16,26.13),(4.12,6.13,26.84))):
        edge = abs(i-3)
        back = 6.30 - .16*edge - .055*edge**2
        outer_end = max(end,29.08) if edge==3 else end
        if edge==3:
            bh.c(f"耳后发根{i}", (max(x0,-5.25),end,1.25),(min(x1,5.25),outer_end+.1,back-.99),hair())
        bh.c(f"短后发{i+1}",(x0,outer_end,1.25),(x1,33.67-edge*.20,back-1.48),hair("hair_d"))
        oh.c(f"后冠覆发{i+1}",(x0+.06,max(outer_end+.56,27.65),back-1.56),
             (x1-.06,34.97-edge*.25,back-.52),hair())
        oh.c(f"后冠转面{i+1}",(x0+.14,29.35+edge*.27,back-.58),
             (x1-.14,32.18-edge*.23,back),hair())

    flh = hairg.g("FLongHair", (0, 27.6, 2.3))
    mlh = flh.g("MLongHair", (0, 27.5, 2.3))
    lh = mlh.g("LongHair", (0, 27.45, 2.3))
    rib = hairg.g("Ribbon", (0, 28.6, -.5))
    for side, nm in ((1, "Right"), (-1, "Left")):
        def paired(group, name, x0, x1, y0, y1, z0, z1, paint, **kw):
            return group.c(nm + name, *box(side*x0, side*x1, y0, y1, z0, z1), paint, **kw)
        paired(bh,"两鬓底发",3.38,5.28,26.55,35.13,-3.60,4.42,hair("hair_d"))
        paired(bh,"耳后覆发",4.44,5.31,26.51,32.28,.14,4.45,hair())
        paired(bh,"耳根",5.31,5.72,28.85,30.06,-.76,-.01,skin_part())
        # 左右独立的三段链。根部轴心取发束关节；模板右鬓角保留原 UUID。
        prefix = "corner_h1" if side > 0 else "corner_h2"
        cg = hairg.g(prefix,(side*3.8,30.8,-2.6))
        cg.origin = [side*3.8,30.8,-2.6]
        cm = cg.g(prefix+"_mid",(side*4.1,26.5,-2.6))
        ct = cm.g(prefix+"_tip",(side*4.3,22.5,-2.6))
        # 每段主体的前后层相错，靠脸侧的收窄与短边阶共同描述轮廓。
        locks = [
            (cg, "颊上主束",3.97,6.15,29.32,33.50,-3.86,-1.47,"hair"),
            (cg, "颊侧暗阶",3.80,4.32,30.06,32.07,-3.80,-2.42,"hair_d"),
            (cg, "颊外转面",5.83,6.60,30.71,32.16,-3.46,-1.43,"hair"),
            (cg, "颊下转束",4.03,5.18,26.33,29.71,-3.94,-1.71,"hair"),
            (cg, "颊内短阶",3.87,4.37,26.88,28.53,-3.75,-2.21,"hair_d"),
            (cm, "锁骨上束",4.13,6.15,24.46,26.77,-3.81,-2.12,"hair"),
            (cm, "锁骨侧阶",5.90,6.60,25.05,26.24,-3.51,-2.18,"hair_l"),
            (cm, "锁骨收束",4.24,6.15,22.31,24.83,-3.62,-2.12,"hair"),
            (cm, "锁骨内阶",4.01,4.50,23.44,24.99,-3.43,-2.26,"hair_d"),
            (ct, "鬓尾转束",4.30,6.03,20.84,22.73,-3.86,-2.18,"hair"),
            (ct, "鬓尾侧阶",5.79,6.60,20.80,21.90,-3.55,-2.32,"hair_l"),
            (ct, "鬓尾主尖根",4.63,6.00,19.40,21.23,-3.74,-2.23,"hair"),
            (ct, "鬓尾主尖",4.71,5.37,18.80,19.64,-3.65,-2.38,"hair"),
            (ct, "鬓尾内尖",4.17,4.79,19.76,21.11,-3.49,-2.37,"hair_d"),
            (ct, "鬓尾外尖",5.52,6.42,20.23,21.34,-3.52,-2.32,"hair_l"),
        ]
        locks.extend([
            (cg,"颊下卷簇",4.99,5.70,27.82,28.88,-3.52,-1.65,"hair"),
            (cm,"锁骨前卷簇",5.78,6.60,22.92,24.04,-3.83,-2.15,"hair_soft"),
            (ct,"鬓梢内卷簇",4.12,4.82,19.18,20.40,-3.74,-2.39,"hair"),
        ])
        for joint,name,*values,tone in locks:
            paired(joint,name,*values,hair(tone))

        base_name = nm+"SideLock"
        pt = lh.g(base_name,(side*4.8,27.5,2.1))
        pm = pt.g(base_name+"1",(side*5.1,23.8,2.3))
        pe = pm.g(base_name+"2",(side*5.4,20.2,2.5))
        pony = [
            (pt,"马尾结下",4.67,5.47,25.83,27.50,0.62,4.36,"hair_d"),
            (pt,"马尾上束",4.63,6.68,23.67,26.25,0.82,4.80,"hair"),
            (pt,"马尾上外簇",5.87,6.70,24.52,26.68,1.32,4.46,"hair"),
            (pt,"马尾上内簇",4.50,5.02,24.06,25.71,3.13,5.06,"hair_l"),
            (pm,"马尾中上",4.88,6.66,21.97,24.01,0.91,4.84,"hair"),
            (pm,"马尾中外簇",6.54,7.18,22.45,23.62,1.17,4.55,"hair_l"),
            (pm,"马尾中内簇",4.65,5.19,21.70,23.18,3.15,5.19,"hair"),
            (pm,"马尾中下",5.03,6.73,20.29,22.30,1.17,5.00,"hair"),
            (pm,"马尾中后阶",5.48,6.48,20.77,21.84,4.67,5.36,"hair_l"),
            (pe,"马尾末束",5.00,6.65,18.89,20.73,1.10,4.96,"hair"),
            (pe,"马尾末外簇",6.42,7.15,19.29,20.65,1.69,4.74,"hair"),
            (pe,"马尾末内簇",4.93,5.61,19.12,20.27,3.35,5.27,"hair_d"),
            (pe,"马尾主尖根",5.28,6.94,17.48,19.47,1.66,5.46,"hair"),
            (pe,"马尾主尖",5.54,6.69,17.00,18.41,2.27,5.75,"hair"),
            (pe,"马尾外副尖",6.49,7.03,17.17,19.35,2.92,5.41,"hair_l"),
            (pe,"马尾内副尖",5.02,5.66,17.61,19.63,3.59,5.21,"hair_d"),
        ]
        for joint,name,x0,x1,y0,y1,z0,z1,tone in pony:
            # 发束中段顺着背部收薄，末端再向后挑出。
            setback = .53 if joint is pm else (.32 if joint is pt else .16)
            paired(joint,name,x0,x1,y0,y1,z0-setback,z1-setback,hair(tone))
        paired(rig["hl_side"],"后颈外翻阶",3.62,4.30,26.04,27.51,3.86,4.78,hair())
        paired(rig["hl_m"],"后颈短发内层",1.18,1.96,25.46,26.44,4.09,4.90,hair("hair_d"))
        flower_center = (side*5.90,27.97,.94)
        fg = rib.g(nm + "HairFlower", flower_center)
        paired(fg,"发花托",5.12,5.64,27.66,28.24,.66,1.21,flat("flower_s"))
        add_flower(fg, nm+"发花", flower_center, side)

        hg = head.g(nm+"Horn", (side*3.6,35.78,.38))
        horn_sections = [(2.43,4.77,35.78,37.48,-.80,1.44),
                         (3.40,5.82,36.86,38.25,-.70,1.56),
                         (4.35,6.77,37.80,39.51,-.52,1.94),
                         (5.22,6.85,39.22,40.52,-.16,2.17),
                         (5.05,6.49,40.30,41.50,.20,2.12)]
        for i,bounds in enumerate(horn_sections):
            paired(hg,f"龙角{i+1}",*bounds,horn(i))
        paired(hg,"支角根",4.55,6.95,36.47,38.07,-.16,1.51,horn())
        paired(hg,"支角外阶",6.06,7.02,37.14,38.25,-.02,1.52,horn())
        eg = head.g(nm+"Ear", (side*5.40,34.12,.68))
        paired(eg,"尖耳根",5.40,6.84,33.50,35.12,-.20,1.6,horn())
        paired(eg,"耳外阶",6.27,7.48,33.28,34.78,-.12,1.40,horn())

    # 肘、腕与握点共用诺米定位器。握持物和皮肤随同一个关节转动。
    for nm in ("Right", "Left"):
        upper_arm = rig[nm+"Arm"]
        forearm = rig[nm+"ForeArm"]
        hand = rig[nm+"Hand"]
        grip = np.asarray(rig[nm+"HandLocator"].origin)
        palm = (np.asarray(hand.origin) + 3*grip)/4
        strand(upper_arm, nm+"上臂", upper_arm.origin,forearm.origin,2.60,2.60,skin_part())
        strand(forearm, nm+"前臂", forearm.origin,hand.origin,2.60,2.60,skin_part())
        hand.c(nm+"手", palm-1.20, palm+1.20, skin_part(True))

    # ---------------- 上衣
    top = upper.g("FittedTop", (0, 22.6, 0))
    top.c("胸身", (-3.4, 21.3, -1.9), (3.4, 25.6, 1.9), flat("white"))
    top.c("收腰", (-3.1, 19.0, -1.75), (3.1, 21.3, 1.75), flat("white"))
    top.c("腰带", (-3.25, 20.0, -1.9), (3.25, 21.3, 1.9), flat("black", edge="black_l"))
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
        f, t = box(side * 0.25, side * 3.15, 9.2, 18.6, -1.55, 1.55)
        lg.c(nm + "Leg裁片", f, t, skin_part())
        ll = lg.g(nm + "LowerLeg", (cx, 9.2, 0))
        f, t = box(side * 0.25, side * 3.15, 3.6, 9.2, -1.5, 1.5)
        ll.c(nm + "LowerLeg裁片", f, t, skin_part())
        f, t = box(side * 0.10, side * 3.30, 2.4, 3.98, -1.7, 1.7)
        ll.c(nm + "脚环", f, t, flat("black", edge="black_l"))
        ft = ll.g(nm + "Foot", (cx, 2.7, 0))
        f, t = box(side * 0.25, side * 3.15, 1.2, 2.4, -1.4, 1.4)
        ft.c(nm + "脚踝", f, t, skin_part())
        f, t = box(side * 0.25, side * 3.15, 0.0, 1.2, -3.15, 1.6)
        ft.c(nm + "脚掌", f, t, skin_part())

    wf = down.g("NomiWaistFollow", (0, 19.3, 0))
    sk = wf.g("Skirt", (0, 19.3, 0))
    TH = 0.5
    tiers = []
    for i in range(10):
        tiers.append((20.0 - 0.483 * (i + 1), 20.0 - 0.483 * i, 3.3 + 0.23 * i, 2.35 + 0.132 * i, flat("white")))
    tiers.append((13.99, 15.17, 5.60, 3.65, flat("black", edge="black_l")))
    for i, (y0, y1, hw, hd, pnt) in enumerate(tiers):
        # 诺米 24 个独立摆片覆盖裙子四周。折角落在分区边界，静态仍是一条连续黑边。
        for k in range(24):
            ends = []
            for j in (k,k+1):
                angle = j*math.tau/24
                x, z = math.sin(angle), -math.cos(angle)
                ends.append(np.array([hw*math.copysign(abs(x)**.85,x), hd*math.copysign(abs(z)**.85,z)]))
            dx,dz = ends[1]-ends[0]
            length = math.hypot(dx,dz)
            yaw = math.degrees(math.atan2(-dz,dx))
            center2 = (ends[0]+ends[1])/2 + np.array([-dz,dx])*(TH/2)/length
            center = np.array([center2[0],(y0+y1)/2,center2[1]])
            half = np.array([length+.12,y1-y0,TH])/2
            bone = rig[f"NomiPleatRoot{k}" if i<3 else f"NomiPleatSwing{k//2}_{k%2}"]
            skirt_section(bone,f"裙围{k}·阶{i}",center-half,center+half,yaw,pnt)
    sk.c("裙内衬", (-3.25, 18.9, -2.25), (3.25, 19.15, 2.25), flat("white_d"))
    kx, ky, kz = -2.28, 20.18, -2.83
    bowg = wf.g("WaistBow", (kx,ky,kz))
    bowg.c("结心",(kx-.46,ky-.52,kz-.81),(kx+.46,ky+.54,kz+.23),flat("red_d"))
    for side in (-1,1):
        # 两翼在深度上打开，让侧面也能看到前后边、暗结与内褶。
        z = kz - side*.21
        bowg.c(f"蝶翼内褶{side}", *box(kx+side*.28,kx+side*.77,ky-.37,ky+.39,z-.45,z+.29),flat("red_s"))
        bowg.c(f"蝶翼展开{side}", *box(kx+side*.57,kx+side*1.42,ky-.76,ky+.76,z-.42,z+.37),flat("red_l",edge="red"))
        bowg.c(f"蝶翼外缘{side}", *box(kx+side*1.27,kx+side*1.88,ky-1.00,ky+1.00,z-.40,z+.47),flat("red_l",edge="red"))
    # 两束从各自翼下并行，外带沿裙的左前角滚下，内带沿正面下垂。
    for x, z, tone in ((-2.85,-2.22,"red"),(-1.18,-3.35,"red")):
        bowg.c(f"蝶翼反折{tone}",(x-.39,18.93,min(z-.25,kz-.04)),(x+.39,19.86,max(z+.28,kz+.12)),bow_paint(tone))
    ribbons = [
        ("RibbonTail", 1.10, 1.06, "red", [(-2.85,19.0,-2.22),(-3.96,16.1,-2.61),
                                            (-5.39,13.1,-2.35),(-6.36,10.62,-2.04)]),
        ("InnerRibbonTail", 1.10, 1.00, "red", [(-1.18,19.0,-3.35),(-2.29,16.1,-3.65),
                                                   (-3.71,13.1,-3.67),(-5.17,8.97,-3.27)]),
    ]
    for prefix,width,depth,tone,points in ribbons:
        parent = bowg
        for j,(start,end) in enumerate(zip(points,points[1:])):
            parent = parent.g(prefix+str(j),start)
            # 两端重叠于关节处。
            strand(parent,prefix+f"·带段{j+1}",start,end,width,depth,bow_paint(tone))

    path = np.array([(3.20,14.12,2.62),(3.79,12.68,3.30),(3.88,10.83,3.94),
                     (4.83,8.36,5.16),(6.58,5.97,6.62),(8.50,4.40,9.05)])
    # 节点保留原轴心，相邻段在关节处共用切线。根部向外探，尾尖稍回平。
    tangents = np.gradient(path, axis=0)
    tangents[0] = (2.4,-.35,1.55)
    tangents[-1] = (2.25,-.30,1.48)

    tg = down.g("Tail", path[0])
    tg.c("尾根衔接",(2.68,13.81,2.10),(3.72,14.84,3.15),tail(0))
    parent = tg
    nseg = len(path) - 1
    for i in range(nseg):
        p, q = np.array(path[i]), np.array(path[i + 1])
        seg = parent.g("Tail%d" % i, tuple(p))
        n = max(2, int(np.ceil(np.linalg.norm(q - p) / 0.45)))
        for k in range(n):
            tt = (i + k / n) / nseg
            sz = 1.10 - 0.20 * tt
            u = (k + 0.5) / n
            blend = u*u*(3-2*u)
            cpos = (1-blend)*p + blend*q + u*(1-u)**2*tangents[i] - u*u*(1-u)*tangents[i+1]
            seg.c("尾%d_%d" % (i, k), cpos - sz / 2, cpos + sz / 2, tail(tt))
        if i == 2:
            mid = path[3] + (.67,0,-.28)
            fg = seg.g("TailFlowerMid", tuple(mid))
            add_flower(fg, "尾花中", tuple(mid), 0, petal_depth=.64)
        parent = seg
    fg = parent.g("TailFlowerTip", path[-1])
    add_flower(fg, "尾花尖", fg.origin, 0)

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


def add_flower(group, name, center, side, petal_depth=1.04):
    """以芯为轴，耳侧的四瓣沿 YZ 对角展开；花冠略朝前，正背面也能看到花瓣分离。"""
    c = np.asarray(center)
    core_half = .50
    group.c(name+"·芯",c-core_half,c+core_half,flower(),role="core")
    for vertical in (-1,1):
        for lateral in (-1,1):
            if side:
                shift = 1.04 if lateral>0 else -.97
                offset = np.array([side*shift, vertical*1.04, lateral*1.03])
                half = np.array([.57,.59,.58])
            else:
                offset = np.array([lateral*1.04,vertical*1.03,lateral*petal_depth])
                half = np.array([.64,.64,.64])
            stem = c+.53*offset
            group.c(f"{name}·内阶{vertical}_{lateral}",stem-.40,stem+.40,flower())
            pos = c+offset
            group.c(f"{name}·瓣{vertical}_{lateral}",pos-half,pos+half,flower())


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
# 正面设定为垂手站姿。模板的绑定姿势用于动画，审查图使用此单帧站姿。
REVIEW_ROTATION = {"RightArm": (23,0,-26.9), "LeftArm": (23,0,26.9),
                  "RightHand": (-18,0,10), "LeftHand": (-18,0,-10)}


def review_stance(groups):
    animators = {}
    for g in groups:
        if g["name"] in REVIEW_ROTATION:
            rx,ry,rz = REVIEW_ROTATION[g["name"]]
            key_id = str(uuidlib.uuid5(uuidlib.NAMESPACE_URL, "longnu/stand/" + g["name"]))
            animators[g["uuid"]] = {"name":g["name"], "type":"bone", "keyframes":[{
                "channel":"rotation", "time":0, "uuid":key_id, "interpolation":"linear",
                "data_points":[{"x":str(rx),"y":str(ry),"z":str(rz)}], "color":-1}]}
    if not animators:
        return []
    return [{"name":"longnu_reference_stance", "loop":"hold", "length":0.0, "snapping":24,
             "override":False, "uuid":str(uuidlib.uuid5(uuidlib.NAMESPACE_URL,"longnu/stand")),
             "animators":animators}]


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
        "animations": review_stance(groups),
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


def collect_faces(root, reference_stance=False):
    out = []

    def walk(g, M, t):
        # 骨骼旋转递归传递给子方块。
        pose = REVIEW_ROTATION.get(g.name,(0,0,0)) if reference_stance else (0,0,0)
        R = rot_matrix(np.add(g.rot,pose))
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
        shade = 0.82 + 0.18 * max(0.0, float(np.dot(n, light)))
        if f == "up":
            shade = min(1.0, shade + 0.06)
        col = tex[..., :3].astype(np.float32) / 255 * shade
        sub[m] = dep[m]
        im = img[y0:y1 + 1, x0:x1 + 1]
        im[m] = col[m]
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def preview(root, atlas):
    faces = collect_faces(root, reference_stance=True)
    views = [("正面", 0, 0), ("左侧", 90, 0), ("背面", 180, 0), ("3/4", -35, 12)]
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
