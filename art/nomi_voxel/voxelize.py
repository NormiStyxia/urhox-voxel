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
PALETTE_SIZE = 40

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
                name = "head"   # 垂在肩前的发束：跟头走
                zmask &= (zs + 0.5 >= -4) & (zs + 0.5 <= 6)
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
                    if 0.0 <= xc <= 8.5 or -9.5 <= xc <= -1.0:
                        name = "leg_right" if xc > 0 else "leg_left"
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
                elif j <= 27 and abs(xc) <= 10.5:
                    name = "skirt"
                else:
                    name = "body"
            for k in np.where(zmask)[0]:
                occ[i, j, k] = True
                part[i, j, k] = name
    return occ, part, fcls


def split_coat(occ, part, fcls):
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
        if dist[i, j, k] > 2.5:
            occ[i, j, k] = False
            part[i, j, k] = ""
        else:
            part[i, j, k] = "coat_upper" if y >= 36 else "coat_lower"


def despike(occ, part):
    """去掉只有 0~1 个邻居的孤立体素（细刺、悬空点）。"""
    k = np.zeros((3, 3, 3)); k[1, 1, 0] = k[1, 1, 2] = k[1, 0, 1] = k[1, 2, 1] = k[0, 1, 1] = k[2, 1, 1] = 1
    for _ in range(2):
        nb = ndimage.convolve(occ.astype(int), k, mode="constant")
        kill = occ & (nb <= 1)
        occ[kill] = False
        part[kill] = ""


def relief(occ, part, fcls):
    """视觉外壳没有正面凹凸：把脸往后推 2 格，让刘海、鬓发盖在脸前面。"""
    xs = np.arange(-NX, NX)
    for i, x in enumerate(xs):
        if abs(x + 0.5) > 8.5:
            continue
        for j in range(52, 64):
            if fcls[i, j] in ("s", "k", "n", "?", "w") and fcls[i, j] != "h":
                ks = np.where(occ[i, j])[0]
                if len(ks):
                    front = ks.max()
                    for k in range(front, max(front - 2, -1), -1):
                        occ[i, j, k] = False
                        part[i, j, k] = ""


# ------------------------------------------------------------------ 上色
DIRS = {
    "px": (1, 0, 0), "nx": (-1, 0, 0),
    "py": (0, 1, 0), "ny": (0, -1, 0),
    "pz": (0, 0, 1), "nz": (0, 0, -1),
}


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
        if bone == "head" and 50 <= j <= 64 and k - NZ + 0.5 >= 2:
            # 侧视图把眼睛画在脸侧（3/4 视角会出现四只眼）：脸部区域的侧面
            # 改用正视图这一格的皮肤 / 头发色；正视图是丝带等别的颜色时退回侧视头发色
            if f.max() > 0 and classify(f) in ("s", "h", "w"):
                return f
            if s.max() > 0 and classify(s) in ("h", "w", "s"):
                return s
            return _pick(f, b, s)
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
    return _pick(f, b, s) * 0.7


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


def build_faces(occ, part, Fc, Bc, Sc):
    shape = occ.shape
    ext = extremes(occ)
    faces = []   # (bone, dir, i, j, k, rgb)
    for (i, j, k) in zip(*np.where(occ)):
        for d, (dx, dy, dz) in DIRS.items():
            a, b, c = i + dx, j + dy, k + dz
            inside = 0 <= a < shape[0] and 0 <= b < shape[1] and 0 <= c < shape[2]
            # 不同骨骼之间的接缝也出面，动画转起来不会露空
            if inside and occ[a, b, c] and part[a, b, c] == part[i, j, k]:
                continue
            col = face_color(d, i, j, k, Fc, Bc, Sc, ext, part[i, j, k])
            if inside and occ[a, b, c]:
                col = col * 0.55          # 两个部件贴在一起的面：平时看不到，动起来露出来是暗面
            elif part[i, j, k].startswith("coat") and is_inner(occ, i, j, k, d):
                col = col * 0.6           # 外套朝里的一面（衬里）
            faces.append((part[i, j, k], d, i, j, k, col))
    return faces


# ------------------------------------------------------------------ 合并
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
        groups.setdefault(key, {})[(u, v)] = ci
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


def render_iso(by_face, occ, yaw_deg=35, pitch_deg=20, scale=6):
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
    return Image.fromarray(img.astype(np.uint8))


# ------------------------------------------------------------------ 导出
def export_lua(quads, palette):
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
    relief(occ, part, fcls)
    split_coat(occ, part, fcls)
    despike(occ, part)
    faces = build_faces(occ, part, Fc, Bc, Sc)
    cols = np.array([f[5] for f in faces])
    palette, idx = kmeans(cols, PALETTE_SIZE)
    quads = greedy(faces, idx)

    by_face = {(f[0], f[1], f[2], f[3], f[4]): palette[c] for f, c in zip(faces, idx)}
    views = [render(occ, part, by_face, v) for v in ("front", "side", "back")]
    isos = [render_iso(by_face, occ, yaw) for yaw in (35, -40, 150, 215)]
    W = sum(v.width for v in isos)
    sheet = Image.new("RGB", (W, isos[0].height), (40, 40, 40))
    x = 0
    for v in isos:
        sheet.paste(v, (x, 0))
        x += v.width
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
    out = export_lua(quads, palette)
    print(f"voxels={occ.sum()} faces={len(faces)} quads={len(quads)} parts={counts}")
    print("wrote", out)


if __name__ == "__main__":
    main()
