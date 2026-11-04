"""
诺米体素化 —— 从 Mivo YSM 三视图（../nomi_ysm/ref/ref_ysm_navy.png）雕刻体素角色

只有一张侧视图，所以「三视图轮廓求交」(visual hull) 会把 A 字手臂、腿都撑成
和身体一样厚的板子。做法是先按部件切分，每个部件用自己的侧视深度范围：
  头      y >= 52（下巴以上），以及垂在肩前的发束
  手臂    肩(±9,46) → 手(±19,31) 的斜胶囊，深度 z ∈ [-6, 3]
  腿      y <= 17、两条腿各自的 x 范围，深度取侧视图里含腿中心的那一段
  斗篷碎条 y <= 17 的两侧 / 背后
  裙摆、身体 其余
表面颜色按面朝向取对应视图：+Z 正视、-Z 背视、±X 侧视。最后调色板量化、
同色面合并，按骨骼导出给 UrhoX（scripts/game/NomiVoxelData.lua）。

坐标（UrhoX 约定，左手系）：x 向角色右，y 向上，z 向角色正面；脚底 y=0。
  正视图：图像 x → -X；背视图：图像 x → +X；侧视图（脸朝画面左）：图像 x → -Z
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
REF = HERE.parent / "nomi_ysm" / "ref" / "ref_ysm_navy.png"

P = 10                 # 每个体素对应的参考图像素
GROUND = 831           # 参考图鞋底所在行
BG = np.array([198, 197, 197])
VIEW_X = {"front": (40, 500), "side": (560, 980), "back": (1000, 1536)}
CENTER = {"front": 266.6, "back": 1267.0, "side": 745.7}   # 背视图中心由 IoU 搜索得到
BACK_SCALE = 0.99
NX, NY, NZ = 26, 84, 22  # 网格：x ∈ [-NX, NX)，y ∈ [0, NY)，z ∈ [-NZ, NZ)
UNIT = 0.022           # 1 体素 = 0.022m，头顶约 1.65m
PALETTE_SIZE = 16     # 脸以外的颜色总数（少一点，像素不杂）
FACE_PALETTE = 12     # 脸单独一套，眼睛 / 腮红细节不受影响

BONES = [
    # name, parent, pivot (体素坐标)
    ("root", None, (0, 0, 0)),
    ("leg_right", "root", (4.5, 18, -1)),
    ("leg_left", "root", (-4.5, 18, -1)),
    ("body", "root", (0, 18, -1)),
    ("skirt", "body", (0, 27, -1)),
    ("coat_upper", "body", (0, 48, -1)),        # 外套上半：肩部轴心
    ("coat_lower", "coat_upper", (0, 36, -2)),  # 外套下摆：腰部轴心，摆得更开
    ("cloak_strip_r", "coat_lower", (12, 18, -2)),
    ("cloak_strip_l", "coat_lower", (-12, 18, -2)),
    ("cloak_strip_b", "coat_lower", (0, 18, -10)),
    ("arm_right", "body", (9, 46, -1.5)),
    ("arm_left", "body", (-9, 46, -1.5)),
    ("head", "body", (0, 51, -1)),
    ("hair_locks", "body", (0, 51, -1)),
    ("hair_back", "body", (0, 51, -8)),
    ("hood", "coat_upper", (0, 51, -8)),     # 帽兜：单独一块，挂在外套上半      # 垂在背后的长发：单独一块，盖在帽兜 / 外套外面
]


# ------------------------------------------------------------------ 取样
def load_mask():
    im = np.asarray(Image.open(REF).convert("RGB")).astype(np.int32)
    diff = np.abs(im - BG).sum(2)
    mask = diff > 24
    sat = im.max(2) - im.min(2)
    lum = im.mean(2)
    shadow = (sat < 12) & (lum < 200)   # 脚边地面阴影
    shadow[:760] = False
    mask &= ~shadow
    mask[GROUND:] = False
    out = np.zeros_like(mask)
    for x0, x1 in VIEW_X.values():       # 浅色头发 / 白衣和背景接近，补轮廓内空洞
        sub = ndimage.binary_closing(mask[:, x0:x1], iterations=2)
        out[:, x0:x1] = ndimage.binary_fill_holes(sub)
    return im, out


def sample_view(im, mask, cx, scale, coords):
    """返回 cov[i, j]（覆盖率）与 col[i, j]（中位色），i 沿 coords，j 沿 y。
    图像 x = cx + scale * coord。"""
    H, W = mask.shape
    cov = np.zeros((len(coords), NY))
    col = np.zeros((len(coords), NY, 3))
    for i, a in enumerate(coords):
        px = cx + scale * a
        x0, x1 = int(round(px - P / 2)), int(round(px + P / 2))
        for j in range(NY):
            py = GROUND - (j + 0.5) * P
            y0, y1 = int(round(py - P / 2)), int(round(py + P / 2))
            if y0 < 0 or x0 < 0 or x1 > W or y1 > H:
                continue
            m = mask[y0:y1, x0:x1]
            cov[i, j] = m.mean()
            if cov[i, j] > 0:
                inner = m[2:-2, 2:-2]
                pix = im[y0 + 2:y1 - 2, x0 + 2:x1 - 2][inner] if inner.any() else im[y0:y1, x0:x1][m]
                col[i, j] = np.median(pix, axis=0)
    return cov, col


def classify(c):
    """粗颜色类别，用于部件切分。"""
    r, g, b = c
    mx, mn = max(c), min(c)
    if r > 200 and g > 150 and b < 140 and r - b > 60:
        return "Y"
    if r > 200 and g > 170 and b > 150 and r > b + 15:
        return "s"
    if mn > 205:
        return "w" if (b - r) < 14 else "h"
    if b > r + 35 and mx < 150:
        return "n"
    if mx < 70:
        return "k"
    if b >= r and mx > 150:
        return "h"
    return "?"


# ------------------------------------------------------------------ 雕刻
def carve(F, Fc, B, Bc, S, Sc):
    xs = np.arange(-NX, NX)
    zs = np.arange(-NZ, NZ)
    # 轮廓去噪：逐行 1 格的抖动会在外壳表面留下一圈圈台阶
    fb = ndimage.median_filter((F + B) / 2, size=(1, 3)) >= 0.5   # x-y 轮廓（正背平均）
    sd = ndimage.median_filter(S, size=(1, 3)) >= 0.5             # z-y 轮廓
    fcls = np.array([[classify(Fc[i, j]) if fb[i, j] else "." for j in range(NY)] for i in range(len(xs))])
    # 垂在肩前的发束：按区域做开闭运算，不逐格判断（逐格会碎成薄片）
    ax = np.abs(xs + 0.5)[:, None]
    yy = np.arange(NY)[None, :]
    lock = np.isin(fcls, ("h", "w")) & (yy >= 36) & (yy < 52) & (ax >= 8) & (ax <= 16)
    lock = ndimage.binary_opening(lock, structure=np.ones((2, 3)))
    lock = ndimage.binary_closing(lock, structure=np.ones((3, 3))) & fb
    scls = np.array([[classify(Sc[k, j]) if sd[k, j] else "." for j in range(NY)] for k in range(len(zs))])

    occ = np.zeros((len(xs), NY, len(zs)), dtype=bool)
    part = np.full(occ.shape, "", dtype=object)

    def zrange_segment(j, z_hint):
        """侧视图第 j 行里，包含 z_hint 的那一段连续轮廓。"""
        k = z_hint + NZ
        if not sd[k, j]:
            return None
        a = k
        while a - 1 >= 0 and sd[a - 1, j]:
            a -= 1
        b = k
        while b + 1 < len(zs) and sd[b + 1, j]:
            b += 1
        return a, b

    def arm_dist(x, y, side):
        # 肩 → 手的线段距离（体素）
        ax, ay, bx, by = 9 * side, 46, 19.5 * side, 30.5
        vx, vy = bx - ax, by - ay
        t = np.clip(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy), 0, 1)
        return np.hypot(x - (ax + t * vx), y - (ay + t * vy)), t

    for i, x in enumerate(xs):
        xc = x + 0.5
        for j in range(NY):
            if not fb[i, j]:
                continue
            y = j + 0.5
            fc = fcls[i, j]
            zmask = sd[:, j].copy()
            if j >= 52:
                name = "head"
                if abs(xc) >= 14.5 and j <= 64:
                    # 丸子头和丝带：侧视图里只在头侧中后部
                    zmask &= (zs + 0.5 >= -11) & (zs + 0.5 <= -3)
            elif lock[i, j]:
                name = "hair_locks"   # 垂在肩前的发束：挂身体上，转头时不会扫进肩膀
                # 紧贴在鬓发正下方、外套前面（原来往后 6 格，3/4 视角会像多出来的一缕）
                zmask &= (zs + 0.5 >= 5) & (zs + 0.5 <= 11)
            else:
                side = 1 if xc > 0 else -1
                dist, t = arm_dist(xc, y, side)
                if 28 <= j <= 48 and dist <= 5.0 and abs(xc) >= 9.5:
                    name = "arm_right" if side > 0 else "arm_left"
                    zmask &= (zs + 0.5 >= -6) & (zs + 0.5 <= 3)
                elif 28 <= j <= 48 and abs(xc) >= 12.5:
                    # 宽袖 / 斗篷在手臂外侧的部分：不给它整个身体的厚度
                    name = "body"
                    zmask &= (zs + 0.5 >= -7) & (zs + 0.5 <= 4)
                elif j <= 17:
                    if -9.5 <= xc <= 8.5:
                        name = "leg_right" if xc > -0.5 else "leg_left"
                        seg = zrange_segment(j, -1)
                        zm = np.zeros_like(zmask)
                        if seg:
                            zm[seg[0]:seg[1] + 1] = True
                        # 腿后面的斗篷碎条：背视图在这里是藏青、侧视在 z <= -6
                        back_strip = classify(Bc[i, j]) == "n" and j >= 5 and fc != "n"
                        if back_strip:
                            for k in range(len(zs)):
                                if sd[k, j] and zs[k] + 0.5 <= -6:
                                    occ[i, j, k] = True
                                    part[i, j, k] = "cloak_strip_b"
                        zmask = zm
                    else:
                        name = "cloak_strip_r" if xc > 0 else "cloak_strip_l"
                        # 侧视图里碎条在腿后面；给它全深度会把腿 / 袜子 / 裙摆的侧视颜色印到碎条侧面
                        zmask &= (zs + 0.5 <= -2)
                elif j <= 27 and abs(xc) <= 10.5:
                    name = "skirt"
                else:
                    name = "body"
            for k in np.where(zmask)[0]:
                occ[i, j, k] = True
                part[i, j, k] = name
    return occ, part, fcls


def split_coat(occ, part, fcls, Sc=None):
    """把外套从里面的衣服里分出来：先定一个几何核心（躯干 + 裙子），核心以外的
    身体体素都是外套；外套只留贴外表面的 2~3 层（中间掏空），前襟敞开处正视图
    看到的是衬衫 / 领结 / 裙摆白边，这些留给里面的衣服。"""
    xs = np.arange(-NX, NX) + 0.5
    zs = np.arange(-NZ, NZ) + 0.5
    dist = ndimage.distance_transform_edt(occ)
    for (i, j, k) in zip(*np.where(occ)):
        p = part[i, j, k]
        if p not in ("body", "skirt"):
            continue
        x, y, z = xs[i], j, zs[k]
        if 28 <= y <= 48 and abs(x) >= 12.5:
            part[i, j, k] = "arm_right" if x > 0 else "arm_left"   # 宽袖跟手臂走
            continue
        torso = 27 <= y <= 51 and abs(x) <= 6.5 and -5 <= z <= 6.5
        skirt = 18 <= y < 27 and abs(x) <= 10.5 and -6 <= z <= 8.5
        if torso or skirt:
            continue
        if fcls[i, j] in ("w", "Y", "s") and abs(x) < 7 and z > 3:
            continue
        if Sc is not None and y <= 30 and classify(Sc[k, j]) in ("w", "s", "Y"):
            # 侧视图这里看到的是衬裙白边 / 腿：外套在这一侧是敞开的
            occ[i, j, k] = False
            part[i, j, k] = ""
            continue
        if dist[i, j, k] > 2.5:
            occ[i, j, k] = False
            part[i, j, k] = ""
        else:
            part[i, j, k] = "coat_upper" if y >= 36 else "coat_lower"


def round_head(occ, part):
    """视觉外壳交出来的头是个方盒子：眼睛以上把横截面削成圆角矩形（超椭圆），
    编发以上再逐层收小成穹顶。呆毛、丸子头不动。"""
    xs = np.arange(-NX, NX) + 0.5
    zs = np.arange(-NZ, NZ) + 0.5
    head = (part == "head") & occ
    core = head.copy()
    core[np.abs(xs) >= 14.5, :, :] = False      # 丸子头不参与量尺寸
    ii, jj, kk = np.where(core[:, 56:75, :])
    cx = (xs[ii].min() + xs[ii].max()) / 2
    ax = (xs[ii].max() - xs[ii].min()) / 2 + 0.5
    cz = (zs[kk].min() + zs[kk].max()) / 2
    az = (zs[kk].max() - zs[kk].min()) / 2 + 0.5
    ytop = max(j for j in range(NY) if core[:, j, :].any() and j < 76)
    removed = 0
    for (i, j, k) in zip(*np.where(head)):
        x, z = xs[i], zs[k]
        if j < 58 or j >= 76:
            continue
        if abs(x) >= 14.5 and j <= 64:
            continue
        if j < 66 and z > cz:
            continue   # 脸部高度的前半圈保持平面，不削出斜面
        t = np.clip((j - 66) / max(ytop + 1 - 66, 1), 0, 1)
        sc = np.sqrt(1 - (0.72 * t) ** 2)
        nx = abs(x - cx) / (ax * sc + 0.3)
        nz = abs(z - cz) / (az * sc + 0.3)
        if nx ** 3 + nz ** 3 > 1.0:
            occ[i, j, k] = False
            part[i, j, k] = ""
            removed += 1
    print(f"round_head: center=({cx:.1f},{cz:.1f}) axes=({ax:.1f},{az:.1f}) top={ytop} removed={removed}")


def smooth_coat_back(occ, part):
    """外套背面逐行 1 格的抖动会在斜面上叠出一道道横纹：把每一列的背面轮廓
    沿高度做中值平滑，挖掉凸出的、补上凹进去的。"""
    coat = np.isin(part, ("coat_upper", "coat_lower")) & occ
    X, Y, Z = occ.shape
    changed = 0
    for i in range(X):
        ys = [j for j in range(Y) if coat[i, j].any()]
        if len(ys) < 5:
            continue
        zb = np.array([np.where(coat[i, j])[0].min() if coat[i, j].any() else -1 for j in range(Y)], float)
        valid = zb >= 0
        sm = zb.copy()
        for j in range(Y):
            if not valid[j]:
                continue
            win = [zb[t] for t in range(max(0, j - 2), min(Y, j + 3)) if valid[t]]
            sm[j] = np.median(win)
        for j in range(Y):
            if not valid[j]:
                continue
            cur, tgt = int(zb[j]), int(round(sm[j]))
            name = "coat_upper" if j >= 36 else "coat_lower"
            if tgt > cur:
                for k in range(cur, tgt):
                    if part[i, j, k] in ("coat_upper", "coat_lower"):
                        occ[i, j, k] = False
                        part[i, j, k] = ""
                        changed += 1
            elif tgt < cur:
                for k in range(tgt, cur):
                    if not occ[i, j, k]:
                        occ[i, j, k] = True
                        part[i, j, k] = name
                        changed += 1
    print(f"smooth_coat_back: changed={changed}")


def remove_thin_plates(occ, part):
    """上下都空的一格厚横板（轮廓逐行抖动留下的），从下往上看像一条条百叶。
    只清头发、外套、手臂这些大块部位。"""
    allowed = ("head", "hair_locks", "coat_upper", "coat_lower", "arm_right", "arm_left", "body")
    total = 0
    for _ in range(2):
        up = np.zeros_like(occ); up[:, :-1] = occ[:, 1:]
        down = np.zeros_like(occ); down[:, 1:] = occ[:, :-1]
        kill = occ & ~up & ~down & np.isin(part, allowed)
        kill[:, 74:, :] = False   # 头顶 / 呆毛
        occ[kill] = False
        part[kill] = ""
        total += int(kill.sum())
    print(f"remove_thin_plates: removed={total}")


HAIR_PARTS = ("head", "hair_locks", "hair_back")
COAT_NAVY = np.array([46.0, 62.0, 112.0])


def carve_back_hair(occ, part, B, Bc, S, Sc):
    """背视图、侧视图里下巴以下的头发色区域单独求交，雕成一团挂在背后的长发，
    盖在帽兜 / 外套外面——而不是把头发颜色印在外套表面上。"""
    xs = np.arange(-NX, NX) + 0.5
    zs = np.arange(-NZ, NZ) + 0.5
    yy = np.arange(NY)
    bh = np.array([[B[i, j] >= 0.5 and classify(Bc[i, j]) in ("h", "w") for j in range(NY)]
                   for i in range(len(xs))])
    sh = np.array([[S[k, j] >= 0.5 and classify(Sc[k, j]) in ("h", "w") for j in range(NY)]
                   for k in range(len(zs))])
    band = (yy >= 34) & (yy < 52)
    bh &= band[None, :]
    sh &= band[None, :] & (zs[:, None] <= -3)
    bh = ndimage.binary_closing(ndimage.binary_opening(bh, np.ones((2, 2))), np.ones((3, 3)))
    sh = ndimage.binary_closing(ndimage.binary_opening(sh, np.ones((2, 2))), np.ones((3, 3)))
    # 用视图只量出位置和范围，再按 YSM 的做法一缕一缕「搭」出来：2 格宽、长短错开、
    # 隔一缕前后错 1 格，发梢最后两行收成一格。不清空原有体素，外套不会被挖洞。
    protect = ("head", "hair_locks", "arm_right", "arm_left")
    rng = np.random.default_rng(7)
    hz = np.where(sh.any(1))[0]
    if not len(hz):
        print("carve_back_hair: no side hair")
        return
    zlo, zhi = int(hz.min()), int(hz.max())
    added = strands = 0
    for side in (1, -1):
        cols = [i for i in range(len(xs)) if np.sign(xs[i]) == side and bh[i].any()]
        if not cols:
            continue
        cols.sort(key=lambda i: abs(xs[i]))           # 从里往外
        for n, start in enumerate(range(0, len(cols), 2)):
            group = cols[start:start + 2]
            low = min(int(np.where(bh[i])[0].min()) for i in group)
            low += int(rng.integers(0, 4))
            thick = 3 + (n % 2)                        # 隔一缕厚一格：前后错开出层次
            for gi, i in enumerate(group):
                for j in range(low, 52):
                    if j < low + 2 and gi == len(group) - 1 and len(group) > 1:
                        continue                       # 发梢收尖
                    # 贴着外套 / 身体的背面往外搭（跟着背的弧度），不用侧视图整段深度
                    body_k = [k for k in np.where(occ[i, j])[0] if part[i, j, k] not in ("hair_back",)]
                    back = min(body_k) if body_k else zhi + 1
                    k0, k1 = back - thick, back - 1
                    for k in range(max(k0, 0), k1 + 1):
                        if part[i, j, k] in protect:
                            continue
                        if part[i, j, k] != "hair_back":
                            occ[i, j, k] = True
                            part[i, j, k] = "hair_back"
                            added += 1
            strands += 1
    print(f"carve_back_hair: voxels={added} strands={strands} z=[{zlo},{zhi}]")


AXES = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
VEC_DIR = {(1, 0, 0): "px", (-1, 0, 0): "nx", (0, 1, 0): "py", (0, -1, 0): "ny",
           (0, 0, 1): "pz", (0, 0, -1): "nz"}


def find_wedges(occ, part):
    """一格一格的台阶 → 斜面：台阶的凸角体素切成 45° 楔形（YSM 那种斜面）。
    只有台阶在两边都延续时才切（下一级在斜下方、或上一级在斜上方），
    真正的方盒子棱角（靴子、手）不会被切。脸不动。"""
    X, Y, Z = occ.shape
    xs = np.arange(-NX, NX) + 0.5
    zs = np.arange(-NZ, NZ) + 0.5

    def same(p, q, name):
        a, b, c = p
        return 0 <= a < X and 0 <= b < Y and 0 <= c < Z and occ[a, b, c] and part[a, b, c] == name

    def empty(p):
        a, b, c = p
        return not (0 <= a < X and 0 <= b < Y and 0 <= c < Z) or not occ[a, b, c]

    wedges = {}
    for (i, j, k) in zip(*np.where(occ)):
        name = part[i, j, k]
        if name == "head" and 50 <= j <= 66 and abs(xs[i]) <= 12 and zs[k] >= 0:
            continue   # 脸部和刘海保持原样
        if name == "head" and j >= CAP_Y - 2:
            continue   # 头顶由穹顶面片接管
        if name == "head" and FACE_CHAMFER_Y - 2 <= j < CAP_Y and abs(xs[i]) >= 8.5 and zs[k] >= 0:
            continue   # 脸侧大斜面接管
        V = np.array((i, j, k))
        done = False
        for aa, bb in ((0, 1), (0, 2), (1, 2)):
            for sa in (1, -1):
                for sb in (1, -1):
                    a = np.array(AXES[aa]) * sa
                    b = np.array(AXES[bb]) * sb
                    if (empty(tuple(V + a)) and empty(tuple(V + b))
                            and same(tuple(V - a), None, name) and same(tuple(V - b), None, name)
                            and (same(tuple(V + b - a), None, name) or same(tuple(V + a - b), None, name))):
                        wedges[(i, j, k)] = (tuple(a), tuple(b))
                        done = True
                        break
                if done:
                    break
            if done:
                break
    return wedges


def orient(pts, normal):
    """调整顶点顺序，使 cross(b-a, c-a) 朝外（与 FaceCorners 的正面约定一致）。"""
    a, b, c = (np.array(p, float) for p in pts[:3])
    if np.dot(np.cross(b - a, c - a), normal) < 0:
        return list(reversed(pts))
    return pts


def wedge_geometry(i, j, k, a, b, occ, wedges):
    """返回楔形体素要输出的三角形：[(pts3, normal, face_dir_for_color, owner_voxel)]。"""
    X, Y, Z = occ.shape
    a, b = np.array(a), np.array(b)
    cax = [t for t in range(3) if a[t] == 0 and b[t] == 0][0]
    cvec = np.array(AXES[cax])
    o = np.array((i, j, k), float)

    def P(u, v, w):
        # u 沿 a（0 = 靠里一侧），v 沿 b，w 沿 c
        p = o.copy()
        for vec, t in ((a, u), (b, v)):
            ax_ = int(np.nonzero(vec)[0][0])
            p[ax_] += t if vec[ax_] > 0 else 1 - t
        p[cax] += w
        return tuple(p)

    tris = []
    n_slope = (a + b) / np.sqrt(2)
    quad = orient([P(1, 0, 0), P(0, 1, 0), P(0, 1, 1), P(1, 0, 1)], n_slope)
    tris.append(([quad[0], quad[1], quad[2]], n_slope, "slope", (i, j, k)))
    tris.append(([quad[0], quad[2], quad[3]], n_slope, "slope", (i, j, k)))
    for w, sgn in ((0, -1), (1, 1)):
        nb = (i + sgn * cvec[0], j + sgn * cvec[1], k + sgn * cvec[2])
        inside = 0 <= nb[0] < X and 0 <= nb[1] < Y and 0 <= nb[2] < Z
        n_side = cvec * sgn
        if not inside or not occ[nb]:
            # 侧面露在外面：只剩一半（三角形）
            t = orient([P(0, 0, w), P(1, 0, w), P(0, 1, w)], n_side)
            tris.append((t, n_side, VEC_DIR[tuple(n_side)], (i, j, k)))
        elif wedges.get(nb) != wedges.get((i, j, k)):
            # 旁边是整块：它朝这边的面被切掉的那一角露出来，补一个三角
            t = orient([P(1, 0, w), P(1, 1, w), P(0, 1, w)], -n_side)
            tris.append((t, -n_side, VEC_DIR[tuple(-n_side)], nb))
    return tris


def coat_gap(occ, part):
    """腰以下外套和裙子 / 身体之间留 1 格空隙：下摆、前襟能看到清楚的边和阴影，
    不再糊成一整块藏青。腰以上外套搭在肩上，不留。"""
    inner = np.isin(part, ("body", "skirt")) & occ
    near = ndimage.binary_dilation(inner, structure=ndimage.generate_binary_structure(3, 1))
    coat = np.isin(part, ("coat_upper", "coat_lower")) & occ
    kill = coat & near
    kill[:, 34:, :] = False
    occ[kill] = False
    part[kill] = ""
    print(f"coat_gap: removed={int(kill.sum())}")


def build_hood(occ, part):
    """帽兜单独一块：后颈下面一块下缘收尖的区域，从外套背面再往外凸一层，
    挂在自己的骨骼上（不再和外套背面是同一个平面）。"""
    xs = np.arange(-NX, NX) + 0.5
    zs = np.arange(-NZ, NZ) + 0.5
    X, Y, Z = occ.shape
    hood = 0
    for i, x in enumerate(xs):
        for j in range(37, 52):
            half = 8.5 if j >= 46 else 8.5 - (46 - j) * 0.95   # 下缘收成 V 形
            if abs(x) > half:
                continue
            ks = [k for k in np.where(occ[i, j])[0]
                  if part[i, j, k] in ("coat_upper", "coat_lower", "body") and zs[k] <= -4]
            if not ks:
                continue
            kb = min(ks)
            for k in (kb, kb + 1):
                if k < Z and occ[i, j, k] and part[i, j, k] in ("coat_upper", "coat_lower"):
                    part[i, j, k] = "hood"
                    hood += 1
            if kb - 1 >= 0 and not occ[i, j, kb - 1]:
                occ[i, j, kb - 1] = True
                part[i, j, kb - 1] = "hood"
                hood += 1
    print(f"build_hood: voxels={hood}")


def build_lapels(occ, part, fcls):
    """外套前襟的边缘往前再加一层：前襟有厚度、比里面的衬衫高出来。"""
    xs = np.arange(-NX, NX) + 0.5
    X, Y, Z = occ.shape
    added = 0
    for j in range(20, 50):
        for side in (1, -1):
            # 这一行里从中线往外，第一个外套格子就是前襟边缘
            order = [i for i in range(X) if np.sign(xs[i]) == side]
            order.sort(key=lambda i: abs(xs[i]))
            for i in order:
                coat_k = [k for k in np.where(occ[i, j])[0] if part[i, j, k].startswith("coat")]
                if not coat_k:
                    continue
                for ii in (i, i + side):
                    if not (0 <= ii < X):
                        continue
                    ck = [k for k in np.where(occ[ii, j])[0] if part[ii, j, k].startswith("coat")]
                    if not ck:
                        continue
                    kf = max(ck) + 1
                    if kf < Z and not occ[ii, j, kf]:
                        occ[ii, j, kf] = True
                        part[ii, j, kf] = part[ii, j, max(ck)]
                        added += 1
                break
    print(f"build_lapels: added={added}")


def inset_hands(occ, part, fcls):
    """手比袖口细一圈：手（正视图皮肤色的手臂格子）去掉最前和最后一层，
    袖口就能包住手，而不是和手齐平。"""
    removed = 0
    for i, j in zip(*np.where(fcls == "s")):
        if j > 36:
            continue
        ks = [k for k in np.where(occ[i, j])[0] if part[i, j, k] in ("arm_right", "arm_left")]
        if len(ks) <= 2:
            continue
        for k in (min(ks), max(ks)):
            occ[i, j, k] = False
            part[i, j, k] = ""
            removed += 1
    print(f"inset_hands: removed={removed}")


CAP_Y = 66          # 这一行（含）以上的头顶改成大块斜面穹顶
HAIR_DEFAULT = np.array([226.0, 230.0, 243.0])


def _cross2(a, b):
    return a[0] * b[1] - a[1] * b[0]


def _octagon(xa, xb, za, zb, c, cf=None):
    """矩形切角八边形，逆时针（从上往下看）。c = 后角切角，cf = 前角切角。"""
    cf = c if cf is None else cf
    return [(xa + c, za), (xb - c, za), (xb, za + c), (xb, zb - cf),
            (xb - cf, zb), (xa + cf, zb), (xa, zb - cf), (xa, za + c)]


FACE_CHAMFER = 4.0   # 脸两侧前角的大斜面（水平方向切掉的格数）
FACE_CHAMFER_Y = 52  # 从下巴高度开始切


def _cap_color(p, n, Fc, Bc, Sc, prefer_front=False):
    X, Y = Fc.shape[0], Fc.shape[1]
    i = int(np.clip(np.floor(p[0]), 0, X - 1))
    j = int(np.clip(np.floor(p[1]), 0, CAP_Y + 9))
    k = int(np.clip(np.floor(p[2]), 0, Sc.shape[0] - 1))
    ax = int(np.argmax(np.abs(n)))
    if prefer_front and n[2] > 0.3:
        ax = 2   # 脸侧斜面：用正视图的鬓发色（侧视图这里画的是侧脸）
    if ax == 1:
        c = Fc[i, min(j, 74)]
    elif ax == 2:
        c = Fc[i, j] if n[2] > 0 else Bc[i, j]
    else:
        c = Sc[k, j]
    if c.max() <= 0 or classify(c) not in ("h", "w"):
        return HAIR_DEFAULT.copy()
    return c


def build_head_cap(occ, part, Fc, Bc, Sc):
    """头顶用两段八边形台体做成大块斜面（YSM 那种几块大面拼的头顶），不再是
    一格格台阶。斜面切成约 1 格的小格，按参考图投影上色，保留发丝像素感，
    但每一面是真正的平面，没有细碎折线。呆毛（更高处的体素）保留。"""
    xs = np.arange(-NX, NX) + 0.5
    head = (part == "head") & occ
    layer = head[:, CAP_Y - 1, :].copy()
    layer[np.abs(xs) >= 14.5, :] = False
    ii, kk = np.where(layer)
    xa, xb = ii.min(), ii.max() + 1
    za, zb = kk.min(), kk.max() + 1
    # 去掉旧的头顶体素（呆毛在 76 以上，保留）
    kill = head.copy()
    kill[:, :CAP_Y, :] = False
    kill[:, 76:, :] = False
    occ[kill] = False
    part[kill] = ""
    cx, cz = (xa + xb) / 2, (za + zb) / 2
    # 脸两侧的前角：一整块竖直大斜面（不是一格格台阶），先把伸出斜面的体素切掉
    CF = FACE_CHAMFER
    cut = 0
    for (i, j, k) in zip(*np.where(head)):
        if not (FACE_CHAMFER_Y <= j < CAP_Y):
            continue
        right = (i + 1 - (xb - CF)) + (k + 1 - (zb - CF)) > CF
        left = ((xa + CF) - i) + (k + 1 - (zb - CF)) > CF
        if right or left:
            occ[i, j, k] = False
            part[i, j, k] = ""
            cut += 1
    rings = [
        (CAP_Y, _octagon(xa, xb, za, zb, 2.5, CF)),
        (72.0, _octagon(xa + 1.5, xb - 1.5, za + 1.5, zb - 1.5, 3.5)),
        (76.0, _octagon(xa + 5.0, xb - 5.0, za + 4.5, zb - 4.5, 3.0)),
    ]
    tris = []

    def emit(A, B, C, D, prefer_front=False):
        """四边形 ABCD（A-B 沿环，A-D 向上）切成约 1 格的小格上色。"""
        A, B, C, D = (np.array(v, float) for v in (A, B, C, D))
        nu = max(1, int(round(np.linalg.norm(B - A))))
        nv = max(1, int(round(np.linalg.norm(D - A))))
        fc = (A + B + C + D) / 4
        out_dir = np.array([fc[0] - cx, 0.6, fc[2] - cz])
        out_dir /= np.linalg.norm(out_dir)

        def L(s_, t_):
            return (1 - t_) * ((1 - s_) * A + s_ * B) + t_ * ((1 - s_) * D + s_ * C)
        for a in range(nu):
            for b in range(nv):
                p00, p10 = L(a / nu, b / nv), L((a + 1) / nu, b / nv)
                p11, p01 = L((a + 1) / nu, (b + 1) / nv), L(a / nu, (b + 1) / nv)
                nrm = np.cross(p10 - p00, p01 - p00)
                if np.dot(nrm, out_dir) < 0:
                    nrm = -nrm
                nrm /= np.linalg.norm(nrm) + 1e-9
                col = _cap_color((p00 + p11) / 2, nrm, Fc, Bc, Sc, prefer_front)
                q = orient([tuple(p00), tuple(p10), tuple(p11), tuple(p01)], nrm)
                tris.append(("head", [q[0], q[1], q[2]], col))
                tris.append(("head", [q[0], q[2], q[3]], col))

    y0c, y1c = float(FACE_CHAMFER_Y), float(CAP_Y)
    emit((xb, y0c, zb - CF), (xb - CF, y0c, zb), (xb - CF, y1c, zb), (xb, y1c, zb - CF), True)
    emit((xa + CF, y0c, zb), (xa, y0c, zb - CF), (xa, y1c, zb - CF), (xa + CF, y1c, zb), True)
    for (y0, r0), (y1, r1) in zip(rings[:-1], rings[1:]):
        for n_ in range(8):
            a0, b0 = r0[n_], r0[(n_ + 1) % 8]
            a1, b1 = r1[n_], r1[(n_ + 1) % 8]
            emit((a0[0], y0, a0[1]), (b0[0], y0, b0[1]), (b1[0], y1, b1[1]), (a1[0], y1, a1[1]))
    # 顶面：按 1 格网格切，八边形外的格子不要
    ytop, top = rings[-1]
    poly = np.array(top)
    up = np.array([0.0, 1.0, 0.0])
    for x in np.arange(np.floor(poly[:, 0].min()), np.ceil(poly[:, 0].max())):
        for z in np.arange(np.floor(poly[:, 1].min()), np.ceil(poly[:, 1].max())):
            cxz = (x + 0.5, z + 0.5)
            inside = all(_cross2(np.subtract(top[(m + 1) % 8], top[m]), np.subtract(cxz, top[m])) >= 0
                         for m in range(8))
            if not inside:
                continue
            col = _cap_color((x + 0.5, ytop - 1, z + 0.5), up, Fc, Bc, Sc)
            q = orient([(x, ytop, z), (x + 1, ytop, z), (x + 1, ytop, z + 1), (x, ytop, z + 1)], up)
            tris.append(("head", [q[0], q[1], q[2]], col))
            tris.append(("head", [q[0], q[2], q[3]], col))
    print(f"build_head_cap: rect x[{xa},{xb}] z[{za},{zb}] tris={len(tris)} removed_voxels={int(kill.sum())} chamfer_cut={cut}")
    return tris


def despike(occ, part):
    """去掉只有 0~1 个邻居的孤立体素（细刺、悬空点）。"""
    k = np.zeros((3, 3, 3)); k[1, 1, 0] = k[1, 1, 2] = k[1, 0, 1] = k[1, 2, 1] = k[0, 1, 1] = k[2, 1, 1] = 1
    for _ in range(2):
        nb = ndimage.convolve(occ.astype(int), k, mode="constant")
        kill = occ & (nb <= 1)
        occ[kill] = False
        part[kill] = ""


def relief(occ, part, fcls):
    """脸和刘海分两层：脸（皮肤 + 眼睛 + 眉毛 + 腮红）是一整块平面，固定在
    同一个深度；落在脸范围里的刘海 / 鬓发（头发色的格子）单独一层，比脸往前
    BANG_DEPTH 格，不和脸共用一个平面。"""
    BANG_DEPTH = 2
    xs = np.arange(-NX, NX) + 0.5
    X = len(xs)
    eye = np.isin(fcls, ("k", "n", "?"))
    face = np.zeros((X, NY), dtype=bool)
    box = np.zeros((X, NY), dtype=bool)
    for i, x in enumerate(xs):
        if abs(x) > 8.5:
            continue
        for j in range(52, 65):
            box[i, j] = True
            c = fcls[i, j]
            if c in ("s", "k", "n", "?"):
                face[i, j] = True
            elif c == "w":
                # 白色只有贴着眼睛时才算眼白 / 高光，否则是浅色头发
                nb = eye[max(i - 1, 0):i + 2, max(j - 1, 0):j + 2]
                face[i, j] = bool(nb.any())
    face = ndimage.binary_fill_holes(face) & box   # 只补被脸完全包住的洞，不吞刘海
    hair = box & ~face & (fcls != ".")
    # 头发前沿：脸部高度上脸以外头发格子的最前深度（中位数）
    fronts = [np.where(occ[i, j])[0].max() for i in range(X) for j in range(52, 65)
              if hair[i, j] and occ[i, j].any() and abs(xs[i]) <= 12]
    hair_front = int(np.median(fronts))
    zf = hair_front - BANG_DEPTH

    def set_front(i, j, kf):
        ks = np.where(occ[i, j])[0]
        if not len(ks):
            return
        for k in range(ks.min(), occ.shape[2]):
            if k <= kf:
                if not occ[i, j, k]:
                    occ[i, j, k] = True
                    part[i, j, k] = "head"
            elif occ[i, j, k]:
                occ[i, j, k] = False
                part[i, j, k] = ""

    for i, j in zip(*np.where(face)):
        set_front(i, j, zf)
    for i, j in zip(*np.where(hair)):
        set_front(i, j, hair_front)
    # 脸两侧的鬓发（|x| 8.5~13）也拉到同一前沿，把脸框住：侧面看脸的边缘不会凸出来
    curtain = 0
    for i, x in enumerate(xs):
        if not (8.5 < abs(x) <= 13):
            continue
        for j in range(52, 65):
            if fcls[i, j] in ("h", "w", "?") and occ[i, j].any():
                set_front(i, j, hair_front)
                curtain += 1
    # 脖子往前补，下巴只比脖子突出 2 格（原来 5 格，从下往上看像一块黑板）
    for i, x in enumerate(xs):
        if abs(x) > 2.5:
            continue
        for j in (50, 51):   # 两行高，一行高会被后面的「去薄板」当成横板删掉
            if occ[i, j].any() and np.where(occ[i, j])[0].max() < zf - 2:
                ks = np.where(occ[i, j])[0]
                name = part[i, j, ks.max()]
                for k in range(ks.max() + 1, zf - 1):
                    occ[i, j, k] = True
                    part[i, j, k] = name
    print(f"relief: face={face.sum()} bangs={hair.sum()} curtain={curtain} hair_front_k={hair_front} face_k={zf}")
    return face


# ------------------------------------------------------------------ 上色
DIRS = {
    "px": (1, 0, 0), "nx": (-1, 0, 0),
    "py": (0, 1, 0), "ny": (0, -1, 0),
    "pz": (0, 0, 1), "nz": (0, 0, -1),
}


SKIN = np.array([250.0, 226.0, 212.0])   # 侧脸眼睛位置补的肤色


def _pick(*cands):
    """按顺序取第一个有效颜色（视图里该格没有轮廓时颜色是 0）。"""
    for c in cands:
        if c.max() > 0:
            return c
    return cands[0]


def face_color(d, i, j, k, Fc, Bc, Sc, ext, bone=""):
    """只有在该视图里真正看得到的面才用该视图的颜色；被挡住的面用它在
    其它视图里的颜色。ext = 每条视线上最外侧体素的索引。"""
    f, b, s = Fc[i, j], Bc[i, j], Sc[k, j]
    zmax, zmin, xmax, xmin = ext
    front_vis = k == zmax[i, j]
    back_vis = k == zmin[i, j]
    side_vis = i == xmin[j, k] or i == xmax[j, k]
    if d == "pz":
        return _pick(f, b, s) if front_vis else _pick(s if side_vis else f, f, b)
    if d == "nz":
        return _pick(b, f, s) if back_vis else _pick(s if side_vis else b, b, f)
    if d in ("px", "nx"):
        if bone == "body" and classify(s) == "Y":
            return _pick(f, b) if classify(f) != "Y" else COAT_NAVY.copy()   # 领结只在正面
        if bone in ("arm_right", "arm_left"):
            # A 字手臂在侧视图里是透视缩短的投影，贴到手臂侧面会把手的肤色印错位置
            return _pick(f, b, s)
        if bone == "head" and 50 <= j <= 64 and k - NZ + 0.5 >= 2:
            # 侧视图把眼睛画在脸侧（3/4 视角会出现四只眼）：脸部区域的侧面
            # 改用正视图这一格的皮肤 / 头发色；正视图是丝带等别的颜色时退回侧视头发色
            # 侧视图的皮肤 / 头发照用（保留侧脸轮廓），只把眼睛那几格换成皮肤
            if s.max() > 0 and classify(s) in ("h", "w", "s"):
                return s
            if f.max() > 0 and classify(f) == "s":
                return f
            return SKIN
        vis = (i == xmax[j, k]) if d == "px" else (i == xmin[j, k])
        if vis:
            return _pick(s, f, b)
        # 被外侧挡住的侧面：用正 / 背视图里这一格的颜色（谁更近用谁）
        return _pick(f if front_vis or not back_vis else b, f, b, s)
    if d == "py":
        if front_vis:
            return _pick(f, b, s)
        if back_vis:
            return _pick(b, f, s)
        return _pick(s, f, b) if side_vis else _pick(f, b, s)
    if bone == "head":
        # 头的底面（下巴、发梢底下）：参考图这里是阴影色，直接用会像一块黑板。
        # 取往上两格的颜色（脸是皮肤、其余是头发）
        up = Fc[i, min(j + 2, NY - 1)]
        return _pick(up, f, b) * 0.88
    return _pick(f, b, s) * 0.82   # 底面：稍暗即可，太暗从下往上看会一条条像百叶


def palette_by_class(colors, total):
    """按颜色类别分别聚类再拼成调色板：领结、丝带的黄色这种面积小的关键色
    不会被大面积颜色吞掉（全局 k-means 会让它们漂成土黄）。"""
    cls = np.array([classify(c) for c in colors])
    names = sorted(set(cls))
    alloc = {}
    for nm in names:
        frac = (cls == nm).mean()
        alloc[nm] = max(1, int(round(total * frac)))
    palette, idx = [], np.zeros(len(colors), dtype=int)
    for nm in names:
        sel = np.where(cls == nm)[0]
        k = min(alloc[nm], len(sel))
        cent, lab = kmeans(colors[sel], k)
        idx[sel] = lab + len(palette)
        palette.extend(cent)
    return np.array(palette), idx


def kmeans(colors, k, iters=25, seed=1):
    rng = np.random.default_rng(seed)
    cent = colors[rng.choice(len(colors), k, replace=False)].astype(float)
    for _ in range(iters):
        d = ((colors[:, None, :] - cent[None]) ** 2).sum(2)
        lab = d.argmin(1)
        for c in range(k):
            sel = colors[lab == c]
            if len(sel):
                cent[c] = sel.mean(0)
    d = ((colors[:, None, :] - cent[None]) ** 2).sum(2)
    return cent, d.argmin(1)


def extremes(occ):
    X, Y, Z = occ.shape
    big = 10 ** 6
    ki = np.arange(Z)[None, None, :]
    zmax = np.where(occ, ki, -1).max(2)
    zmin = np.where(occ, ki, big).min(2)
    ii = np.arange(X)[:, None, None]
    xmax = np.where(occ, ii, -1).max(0)       # [y, z]
    xmin = np.where(occ, ii, big).min(0)
    return zmax, zmin, xmax, xmin


def is_inner(occ, i, j, k, d):
    """沿面法线往外走几格还会撞到体素 = 这面朝向角色内部。"""
    dx, dy, dz = DIRS[d]
    X, Y, Z = occ.shape
    for step in range(1, 7):
        a, b, c = i + dx * step, j + dy * step, k + dz * step
        if not (0 <= a < X and 0 <= b < Y and 0 <= c < Z):
            return False
        if occ[a, b, c]:
            return True
    return False


# 每个部位允许出现的颜色类别：参考图里的中间调阴影（灰、土黄）和别的部位的颜色
# 不往这个部位上印，按部位的基础色兜底（不过度拟合三视图）
PART_COLORS = {
    "coat_upper": ("n", "w", "k"), "coat_lower": ("n", "w", "k"),
    "cloak_strip_r": ("n", "w", "k"), "cloak_strip_l": ("n", "w", "k"), "cloak_strip_b": ("n", "w", "k"),
    "skirt": ("n", "w", "k"),
    "body": ("n", "w", "k", "Y", "s"),
    "arm_right": ("n", "w", "k", "s"), "arm_left": ("n", "w", "k", "s"),
    "leg_right": ("n", "w", "k", "s"), "leg_left": ("n", "w", "k", "s"),
    "hair_locks": ("h", "w"), "hair_back": ("h", "w"),
    "hood": ("n", "k"),
}


def surface_color(d, i, j, k, occ, part, Fc, Bc, Sc, ext):
    name = part[i, j, k]
    col = face_color(d, i, j, k, Fc, Bc, Sc, ext, name)
    allowed = PART_COLORS.get(name)
    if allowed is not None and classify(col) not in allowed:
        # 头发色不印在外套 / 衣袖 / 身体上（头发有自己的几何）；其它杂色同理
        col = (HAIR_DEFAULT if name in HAIR_PARTS else COAT_NAVY).copy()
    return col


def build_faces(occ, part, Fc, Bc, Sc, wedges=None):
    shape = occ.shape
    ext = extremes(occ)
    wedges = wedges or {}
    faces = []   # (bone, dir, i, j, k, rgb)
    tris = []    # (bone, pts3, rgb)
    for (i, j, k), (wa, wb) in wedges.items():
        for pts, nrm, d, owner in wedge_geometry(i, j, k, wa, wb, occ, wedges):
            if d == "slope":
                da, db = VEC_DIR[wa], VEC_DIR[wb]
                col = (surface_color(da, i, j, k, occ, part, Fc, Bc, Sc, ext)
                       + surface_color(db, i, j, k, occ, part, Fc, Bc, Sc, ext)) / 2
                bone = part[i, j, k]
            else:
                col = surface_color(d, *owner, occ, part, Fc, Bc, Sc, ext)
                bone = part[owner]
            tris.append((bone, pts, col))
    for (i, j, k) in zip(*np.where(occ)):
        wd = wedges.get((i, j, k))
        cut = set()
        if wd is not None:
            wa, wb = wd
            cvec = [t for t in range(3) if wa[t] == 0 and wb[t] == 0][0]
            cut = {VEC_DIR[wa], VEC_DIR[wb]}
            for sgn in (1, -1):
                v = [0, 0, 0]; v[cvec] = sgn
                nb = (i + v[0], j + v[1], k + v[2])
                if not (0 <= nb[0] < shape[0] and 0 <= nb[1] < shape[1] and 0 <= nb[2] < shape[2]) or not occ[nb]:
                    cut.add(VEC_DIR[tuple(v)])
        for d, (dx, dy, dz) in DIRS.items():
            if d in cut:
                continue
            a, b, c = i + dx, j + dy, k + dz
            inside = 0 <= a < shape[0] and 0 <= b < shape[1] and 0 <= c < shape[2]
            # 不同骨骼之间的接缝也出面，动画转起来不会露空
            if inside and occ[a, b, c] and part[a, b, c] == part[i, j, k]:
                continue
            col = surface_color(d, i, j, k, occ, part, Fc, Bc, Sc, ext)
            if inside and occ[a, b, c]:
                col = col * 0.55          # 两个部件贴在一起的面：平时看不到，动起来露出来是暗面
            elif part[i, j, k].startswith("coat") and is_inner(occ, i, j, k, d):
                col = col * 0.6           # 外套朝里的一面（衬里）
            elif d == "py" and (part[i, j, k].startswith("coat") or part[i, j, k].startswith("cloak")):
                col = col * 0.78          # 斜面台阶的顶面受光最多，压暗，免得一级级亮成横纹
            faces.append((part[i, j, k], d, i, j, k, col))
    return faces, tris


# ------------------------------------------------------------------ 合并
def is_face_zone(bone, d, i, j):
    return bone == "head" and d == "pz" and 50 <= j <= 66 and abs(i - NX + 0.5) <= 12


def denoise(groups):
    """同一平面里的孤立像素（四邻都和它不同色、且邻居多数是同一色）换成邻居色。
    脸不处理。"""
    changed = 0
    for (bone, d, layer), cells in groups.items():
        if bone == "head" and d == "pz":
            continue
        new = dict(cells)
        for (u, v), c in cells.items():
            nb = [cells.get(t) for t in ((u + 1, v), (u - 1, v), (u, v + 1), (u, v - 1))]
            nb = [x for x in nb if x is not None]
            if len(nb) < 3 or c in nb:
                continue
            vals, cnt = np.unique(nb, return_counts=True)
            if cnt.max() >= 2:
                new[(u, v)] = int(vals[cnt.argmax()])
                changed += 1
        groups[(bone, d, layer)] = new
    return changed


def greedy(faces, palette_idx):
    """同骨骼、同朝向、同层、同色的面合并成矩形。返回 quads。"""
    groups = {}
    for (bone, d, i, j, k, _), ci in zip(faces, palette_idx):
        if d in ("px", "nx"):
            key, u, v = (bone, d, i), k, j
        elif d in ("py", "ny"):
            key, u, v = (bone, d, j), i, k
        else:
            key, u, v = (bone, d, k), i, j
        groups.setdefault(key, {})[(u, v)] = int(ci)
    print(f"denoise: changed={denoise(groups)}")
    quads = []
    for (bone, d, layer), cells in groups.items():
        used = set()
        for (u, v) in sorted(cells):
            if (u, v) in used:
                continue
            c = cells[(u, v)]
            w = 1
            while (u + w, v) in cells and (u + w, v) not in used and cells[(u + w, v)] == c:
                w += 1
            h = 1
            while all((u + t, v + h) in cells and (u + t, v + h) not in used and cells[(u + t, v + h)] == c
                      for t in range(w)):
                h += 1
            for t in range(w):
                for s in range(h):
                    used.add((u + t, v + s))
            quads.append((bone, d, layer, u, v, w, h, c))
    # 降噪后的逐格颜色（给预览用，和导出一致）
    final = {}
    for (bone, d, layer), cells in groups.items():
        for (u, v), c in cells.items():
            if d in ("px", "nx"):
                ijk = (layer, v, u)
            elif d in ("py", "ny"):
                ijk = (u, layer, v)
            else:
                ijk = (u, v, layer)
            final[(bone, d) + ijk] = c
    greedy.final = final
    return quads


# ------------------------------------------------------------------ 预览
def render(occ, part, colors_by_face, view, scale=6):
    """正交渲染体素：front 看 +Z 面，back 看 -Z 面，side 从 -X 看。"""
    X, Y, Z = occ.shape
    if view == "front":
        W, d = X, "pz"
    elif view == "back":
        W, d = X, "nz"
    else:
        W, d = Z, "nx"
    img = np.full((Y, W, 3), 60.0)
    depth = np.full((Y, W), -1e9)
    for (bone, dd, i, j, k), rgb in colors_by_face.items():
        if dd != d:
            continue
        if view == "front":
            col, dep = X - 1 - i, k          # 画面左 = +X
        elif view == "back":
            col, dep = i, -k
        else:
            col, dep = Z - 1 - k, -i         # 画面左 = +Z（正面），从 -X 看
        row = Y - 1 - j
        if dep > depth[row, col]:
            depth[row, col] = dep
            img[row, col] = rgb
    shade = {"pz": 1.0, "nz": 0.92, "nx": 0.96}[d]
    img = np.clip(img * shade, 0, 255).astype(np.uint8)
    return Image.fromarray(img).resize((W * scale, Y * scale), Image.NEAREST)


def render_iso(by_face, occ, yaw_deg=35, pitch_deg=20, scale=6, tris=()):
    """3/4 视角，逐像素深度缓冲。yaw>0 从右前方看，yaw 在 90°~270° 之间看背面。"""
    X, Y, Z = occ.shape
    yaw, pitch = np.radians(yaw_deg), np.radians(pitch_deg)
    cy, sy, cp, sp = np.cos(yaw), np.sin(yaw), np.cos(pitch), np.sin(pitch)
    cam = np.array([sy * cp, sp, cy * cp])          # 指向相机
    sun = np.array([0.45, 0.8, 0.55]); sun /= np.linalg.norm(sun)
    Wd, Hd = 64 * scale, 96 * scale
    img = np.full((Hd, Wd, 3), 60.0)
    zbuf = np.full((Hd, Wd), -1e9)

    def proj(p):
        x, y, z = p
        rx = x * cy - z * sy
        rz = x * sy + z * cy
        ry = y * cp - rz * sp
        dz = y * sp + rz * cp
        return np.array([Wd / 2 + rx * scale, Hd - 6 * scale - ry * scale, dz])

    for (bone, d, i, j, k), rgb in by_face.items():
        n = np.array(DIRS[d])
        if n @ cam <= 0:
            continue
        c = np.array([i - X / 2 + 0.5, j + 0.5, k - Z / 2 + 0.5]) + n * 0.5
        ax = [a for a in range(3) if n[a] == 0]
        e1 = np.zeros(3); e1[ax[0]] = 1
        e2 = np.zeros(3); e2[ax[1]] = 1
        o = proj(c - 0.5 * e1 - 0.5 * e2)
        p1 = proj(c + 0.5 * e1 - 0.5 * e2) - o
        p2 = proj(c - 0.5 * e1 + 0.5 * e2) - o
        xs_ = [o[0], o[0] + p1[0], o[0] + p2[0], o[0] + p1[0] + p2[0]]
        ys_ = [o[1], o[1] + p1[1], o[1] + p2[1], o[1] + p1[1] + p2[1]]
        x0, x1 = int(np.floor(min(xs_))), int(np.ceil(max(xs_)))
        y0, y1 = int(np.floor(min(ys_))), int(np.ceil(max(ys_)))
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, Wd - 1), min(y1, Hd - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        det = p1[0] * p2[1] - p1[1] * p2[0]
        if abs(det) < 1e-9:
            continue
        dx, dy = gx - o[0], gy - o[1]
        u = (dx * p2[1] - dy * p2[0]) / det
        v = (p1[0] * dy - p1[1] * dx) / det
        inside = (u >= 0) & (u <= 1) & (v >= 0) & (v <= 1)
        dep = o[2] + u * p1[2] + v * p2[2]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        win = inside & (dep > sub)
        sub[win] = dep[win]
        shade = 0.55 + 0.5 * max(n @ sun, 0) + 0.1
        img[y0:y1 + 1, x0:x1 + 1][win] = np.clip(np.array(rgb) * shade, 0, 255)

    off = np.array([X / 2, 0, Z / 2])
    for pts, rgb in tris:
        P3 = [np.array(p, float) - off for p in pts]
        n = np.cross(P3[1] - P3[0], P3[2] - P3[0])
        n = n / (np.linalg.norm(n) + 1e-9)
        if n @ cam <= 0:
            continue
        q = [proj(p) for p in P3]
        x0 = max(int(np.floor(min(t[0] for t in q))), 0); x1 = min(int(np.ceil(max(t[0] for t in q))), Wd - 1)
        y0 = max(int(np.floor(min(t[1] for t in q))), 0); y1 = min(int(np.ceil(max(t[1] for t in q))), Hd - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax_, ay_, az_), (bx_, by_, bz_), (cx_, cy2, cz_) = q
        det = (by_ - cy2) * (ax_ - cx_) + (cx_ - bx_) * (ay_ - cy2)
        if abs(det) < 1e-9:
            continue
        w1 = ((by_ - cy2) * (gx - cx_) + (cx_ - bx_) * (gy - cy2)) / det
        w2 = ((cy2 - ay_) * (gx - cx_) + (ax_ - cx_) * (gy - cy2)) / det
        w3 = 1 - w1 - w2
        inside = (w1 >= -1e-6) & (w2 >= -1e-6) & (w3 >= -1e-6)
        dep = w1 * az_ + w2 * bz_ + w3 * cz_
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        win = inside & (dep > sub)
        sub[win] = dep[win]
        shade = 0.55 + 0.5 * max(n @ sun, 0) + 0.1
        img[y0:y1 + 1, x0:x1 + 1][win] = np.clip(np.array(rgb) * shade, 0, 255)
    return Image.fromarray(img.astype(np.uint8))


# ------------------------------------------------------------------ 导出
def export_lua(quads, palette, tris_q=()):
    bmap = {b[0]: b for b in BONES}
    lines = [
        "-- 自动生成：art/nomi_voxel/voxelize.py，请勿手改（改脚本后重新运行）",
        "-- 体素坐标：x 向右、y 向上、z 向前，脚底 y=0；quad = {方向, 层, u, v, 宽, 高, 颜色}",
        "-- 方向 1..6 = +X -X +Y -Y +Z -Z；层为该方向上的体素索引坐标",
        "return {",
        f"    unit = {UNIT},",
        f"    origin = {{ {-NX}, 0, {-NZ} }},",
        "    palette = {",
    ]
    for c in palette:
        lines.append("        { %.3f, %.3f, %.3f }," % tuple(np.clip(c, 0, 255) / 255.0))
    lines.append("    },")
    lines.append("    bones = {")
    for name, parent, pv in BONES:
        par = f'"{parent}"' if parent else "nil"
        lines.append(f'        {{ name = "{name}", parent = {par}, pivot = {{ {pv[0]}, {pv[1]}, {pv[2]} }} }},')
    lines.append("    },")
    lines.append("    quads = {")
    dir_index = {"px": 1, "nx": 2, "py": 3, "ny": 4, "pz": 5, "nz": 6}
    by_bone = {}
    for q in quads:
        by_bone.setdefault(q[0], []).append(q)
    for name, _p, _v in BONES:
        qs = by_bone.get(name, [])
        if not qs:
            continue
        lines.append(f"        {name} = {{")
        row = []
        for (_b, d, layer, u, v, w, h, c) in qs:
            row.append(f"{{{dir_index[d]},{layer},{u},{v},{w},{h},{c + 1}}}")
            if len(row) == 12:
                lines.append("            " + ",".join(row) + ",")
                row = []
        if row:
            lines.append("            " + ",".join(row) + ",")
        lines.append("        },")
    lines.append("    },")
    # 斜面三角形：{x1,y1,z1, x2,y2,z2, x3,y3,z3, 颜色}，体素索引坐标，顶点顺序已按正面朝外排好
    lines.append("    tris = {")
    tb = {}
    for bone, pts, c in tris_q:
        tb.setdefault(bone, []).append((pts, c))
    for name, _p, _v in BONES:
        ts = tb.get(name, [])
        if not ts:
            continue
        lines.append(f"        {name} = {{")
        row = []
        for pts, c in ts:
            nums = ",".join("%g" % v for p in pts for v in p)
            row.append("{" + nums + f",{c + 1}}}")
            if len(row) == 8:
                lines.append("            " + ",".join(row) + ",")
                row = []
        if row:
            lines.append("            " + ",".join(row) + ",")
        lines.append("        },")
    lines.append("    },")
    lines.append("}")
    out = ROOT / "scripts" / "game" / "NomiVoxelData.lua"
    out.write_text("\n".join(lines) + "\n")
    return out


def main():
    im, mask = load_mask()
    xs = np.arange(-NX, NX) + 0.5
    zs = np.arange(-NZ, NZ) + 0.5
    F, Fc = sample_view(im, mask, CENTER["front"], -P, xs)
    B, Bc = sample_view(im, mask, CENTER["back"], P * BACK_SCALE, xs)
    S, Sc = sample_view(im, mask, CENTER["side"], -P, zs)

    occ, part, fcls = carve(F, Fc, B, Bc, S, Sc)
    face2d = relief(occ, part, fcls)
    round_head(occ, part)
    split_coat(occ, part, fcls, Sc)
    smooth_coat_back(occ, part)
    carve_back_hair(occ, part, B, Bc, S, Sc)
    coat_gap(occ, part)
    build_lapels(occ, part, fcls)
    build_hood(occ, part)
    inset_hands(occ, part, fcls)
    remove_thin_plates(occ, part)
    despike(occ, part)
    cap_tris = build_head_cap(occ, part, Fc, Bc, Sc)
    wedges = find_wedges(occ, part)
    faces, tris = build_faces(occ, part, Fc, Bc, Sc, wedges)
    tris = tris + cap_tris
    cols = np.array([f[5] for f in faces] + [t[2] for t in tris])
    face_mask = np.array([is_face_zone(f[0], f[1], f[2], f[3]) for f in faces] + [False] * len(tris))
    pal_rest, idx_rest = palette_by_class(cols[~face_mask], PALETTE_SIZE)
    pal_face, idx_face = palette_by_class(cols[face_mask], FACE_PALETTE)
    palette = np.concatenate([pal_rest, pal_face])
    idx = np.zeros(len(cols), dtype=int)
    idx[~face_mask] = idx_rest
    idx[face_mask] = idx_face + len(pal_rest)
    print(f"palette: rest={len(pal_rest)} face={len(pal_face)}")
    fidx, tidx = idx[:len(faces)], idx[len(faces):]
    quads = greedy(faces, fidx)
    tris_q = [(t[0], t[1], int(c)) for t, c in zip(tris, tidx)]
    tris_rgb = [(t[1], palette[c]) for t, c in zip(tris, tidx)]
    print(f"wedges={len(wedges)} tris={len(tris)}")

    by_face = {key: palette[c] for key, c in greedy.final.items()}
    views = [render(occ, part, by_face, v) for v in ("front", "side", "back")]
    # 两排：上排常规 3/4 与背面，下排侧面 / 平视 3/4 / 低角度（实机里最容易露问题的角度）
    angles = ((35, 20), (-40, 20), (150, 20), (215, 20),
              (-90, 4), (-30, 8), (70, -14), (-110, -14))
    isos = [render_iso(by_face, occ, yaw, pitch, tris=tris_rgb) for yaw, pitch in angles]
    w, h = isos[0].size
    sheet = Image.new("RGB", (w * 4, h * 2), (40, 40, 40))
    for n, v in enumerate(isos):
        sheet.paste(v, ((n % 4) * w, (n // 4) * h))
    sheet.save(HERE / "preview_3d.png")

    # 与参考图并排
    ref = Image.open(REF).convert("RGB").crop((40, 0, 1500, GROUND + 5))
    ref = ref.resize((int(ref.width * views[0].height / ref.height), views[0].height))
    cmp_ = Image.new("RGB", (ref.width, ref.height * 2), (40, 40, 40))
    cmp_.paste(ref, (0, 0))
    vw = Image.new("RGB", (ref.width, ref.height), (60, 60, 60))
    # 按参考图三视图的大致横向位置摆放
    pos = {"front": (40, 500), "side": (560, 980), "back": (1000, 1500)}
    for v, name in zip(views, ("front", "side", "back")):
        a, b = pos[name]
        cxp = int(((a + b) / 2 - 40) * ref.width / 1460 - v.width / 2)
        vw.paste(v, (max(cxp, 0), 0))
    cmp_.paste(vw, (0, ref.height))
    cmp_.save(HERE / "compare.png")

    counts = {}
    for p in part[occ]:
        counts[p] = counts.get(p, 0) + 1
    out = export_lua(quads, palette, tris_q)
    print(f"voxels={occ.sum()} faces={len(faces)} quads={len(quads)} parts={counts}")
    print("wrote", out)


if __name__ == "__main__":
    main()
