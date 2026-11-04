"""
诺米体素化 —— 从 Mivo YSM 三视图（ref/ref_ysm_navy.png）雕刻体素角色

思路：正 / 背 / 侧三张正交视图当投影，体素格三个方向都落在轮廓内才保留
（visual hull），表面颜色取自朝向对应的视图，再按位置分到骨骼。

坐标（UrhoX 约定，左手系）：x 向角色右，y 向上，z 向角色正面；脚底 y=0。
  正视图：图像 x → -X（看着角色时，她的右手在画面左边）
  背视图：图像 x → +X
  侧视图：画面朝左 = 正面 +Z，看到的是角色左侧（-X 面）
"""
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
REF = HERE.parent / "nomi_ysm" / "ref" / "ref_ysm_navy.png"

P = 10            # 每个体素对应的参考图像素
GROUND = 831      # 参考图鞋底所在行（三视图一致）
BG = np.array([198, 197, 197])
VIEW_X = {"front": (40, 500), "side": (560, 980), "back": (1000, 1536)}


def load():
    from scipy import ndimage
    im = np.asarray(Image.open(REF).convert("RGB")).astype(np.int32)
    diff = np.abs(im - BG).sum(2)
    mask = diff > 24
    # 地面阴影：脚边一圈低饱和、比背景暗的灰
    sat = im.max(2) - im.min(2)
    lum = im.mean(2)
    shadow = (sat < 12) & (lum < 200)
    shadow[:760] = False
    mask &= ~shadow
    mask[GROUND:] = False
    # 浅色头发 / 白衣服和背景接近，轮廓内会出现空洞：按视图逐个补洞
    out = np.zeros_like(mask)
    for x0, x1 in VIEW_X.values():
        sub = ndimage.binary_closing(mask[:, x0:x1], iterations=2)
        out[:, x0:x1] = ndimage.binary_fill_holes(sub)
    return im, out


def column_center(mask, x0, x1, rows):
    xs = []
    for r in rows:
        cols = np.where(mask[r, x0:x1])[0]
        if len(cols):
            xs.append((cols.min() + cols.max()) / 2 + x0)
    return float(np.mean(xs))


def main():
    im, mask = load()
    H, W = mask.shape
    # 中心线：正 / 背视图取腿部（左右对称）；侧视图取白袜那一段
    fcx = column_center(mask, *VIEW_X["front"], range(770, 800))
    bcx = column_center(mask, *VIEW_X["back"], range(770, 800))
    sx0, sx1 = VIEW_X["side"]
    sock = []
    for r in range(690, 705):
        row = im[r, sx0:sx1]
        white = np.where((row.min(1) > 225))[0]
        if len(white):
            sock.append((white.min() + white.max()) / 2 + sx0)
    scx = float(np.mean(sock))
    print(f"centers front={fcx:.1f} back={bcx:.1f} side={scx:.1f}")
    Image.fromarray((mask * 255).astype(np.uint8)).save(HERE / "mask.png")

    NX, NY, NZ = 26, 84, 22   # 半宽 x / 高 y / 半深 z（体素）
    xs = (np.arange(-NX, NX) + 0.5) * P
    ys = (np.arange(0, NY) + 0.5) * P
    zs = (np.arange(-NZ, NZ) + 0.5) * P

    def cell(view_cx, sign, coord, y):
        """取视图上一个 P×P 格：返回 (覆盖率, 平均色)。sign: 图像 x = cx + sign*coord"""
        px = view_cx + sign * coord
        py = GROUND - y
        x0, x1 = int(round(px - P / 2)), int(round(px + P / 2))
        y0, y1 = int(round(py - P / 2)), int(round(py + P / 2))
        if y0 < 0 or x0 < 0 or x1 > W or y1 > H:
            return 0.0, None
        m = mask[y0:y1, x0:x1]
        cov = m.mean()
        if cov <= 0:
            return 0.0, None
        # 只在中间 60% 取色，避开格边界的混色
        c = im[y0 + 2:y1 - 2, x0 + 2:x1 - 2][m[2:-2, 2:-2]] if m[2:-2, 2:-2].any() else im[y0:y1, x0:x1][m]
        return cov, np.median(c, axis=0)

    def view_grid(cx, sign, coords):
        cov = np.zeros((len(coords), NY))
        col = np.zeros((len(coords), NY, 3))
        for i, a in enumerate(coords):
            for j, y in enumerate(ys):
                cv, c = cell(cx, sign, a, y)
                cov[i, j] = cv
                if c is not None:
                    col[i, j] = c
        return cov, col

    F, Fc = view_grid(fcx, -1, xs)
    B, Bc = view_grid(bcx, +1, xs)
    S, Sc = view_grid(scx, -1, zs)
    f, b, sd = F >= 0.5, B >= 0.5, S >= 0.5
    inter = (f & b).sum(); union = (f | b).sum()
    print(f"front/back silhouette IoU = {inter / union:.3f}  front={f.sum()} back={b.sum()} side={sd.sum()}")
    np.savez(HERE / "views.npz", F=F, B=B, S=S, Fc=Fc, Bc=Bc, Sc=Sc, xs=xs, ys=ys, zs=zs)


if __name__ == "__main__":
    main()
