#!/usr/bin/env python3
"""
小龙娘 YSM 模型与参考三视图自动对齐、轮廓/色域对比与结构审计工具。
不修改 build_longnu.py 或 longnu.bbmodel，仅读取并输出 audit_sheet.png 与控制台报告。
"""
import json
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

D = Path(__file__).resolve().parent


def fg_mask(rgb, bg_tol=8):
    """从图像四周边框 flood-fill 提取真实前景掩码，避免内部白色衣裙被误判为背景。"""
    arr = np.asarray(rgb, dtype=np.int16)
    H, W, _ = arr.shape
    bg = np.median(arr[:15, :15, :], axis=(0, 1))
    is_bg = np.abs(arr - bg).max(axis=2) <= bg_tol
    visited = np.zeros((H, W), dtype=bool)
    q = deque()
    for x in range(W):
        if is_bg[0, x]:
            visited[0, x] = True
            q.append((0, x))
        if is_bg[H - 1, x]:
            visited[H - 1, x] = True
            q.append((H - 1, x))
    for y in range(H):
        if is_bg[y, 0]:
            visited[y, 0] = True
            q.append((y, 0))
        if is_bg[y, W - 1]:
            visited[y, W - 1] = True
            q.append((y, W - 1))
    while q:
        cy, cx = q.popleft()
        for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
            if 0 <= ny < H and 0 <= nx < W and not visited[ny, nx] and is_bg[ny, nx]:
                visited[ny, nx] = True
                q.append((ny, nx))
    return ~visited


def find_crown_and_foot(img, m):
    """提取脚底 y_foot、脚中线 x_mid，以及黑色发冠顶 y_crown（避开粉色龙角）。"""
    arr = np.asarray(img, dtype=np.int16)
    ys, xs = np.where(m)
    if len(ys) == 0:
        return 0, 0, 1, 0
    y_foot = int(ys.max())
    foot_xs = np.where(m[max(0, y_foot - 18):y_foot + 1, :])[1]
    x_mid = int(round((foot_xs.min() + foot_xs.max()) / 2)) if len(foot_xs) else int(round((xs.min() + xs.max()) / 2))
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    hair = m & (r < 95) & (g < 85) & (b < 95)
    hair_ys = np.where(hair)[0]
    y_crown = int(hair_ys.min()) if len(hair_ys) else int(ys.min())
    return y_foot, x_mid, y_crown, int(ys.min())


def normalize_char_tile(img, target_crown_u=36.4, target_size=(420, 860), foot_y_target=805, px_per_unit=17.5):
    """按脚底中点 x_mid 与脚底到发冠顶高度 (target_crown_u) 归一化到同一坐标系画布。"""
    m = fg_mask(img)
    y_foot, x_mid, y_crown, _ = find_crown_and_foot(img, m)
    crown_h_px = max(1, y_foot - y_crown)
    scale = (target_crown_u * px_per_unit) / crown_h_px

    H_im, W_im = m.shape
    r_arr = np.asarray(img).copy()
    r_arr[~m] = (232, 233, 238)
    clean_im = Image.fromarray(r_arr)
    nw = max(1, int(round(W_im * scale)))
    nh = max(1, int(round(H_im * scale)))
    scaled = clean_im.resize((nw, nh), Image.Resampling.NEAREST)

    W, H = target_size
    canvas = Image.new("RGB", (W, H), (232, 233, 238))
    paste_x = W // 2 - int(round(x_mid * scale))
    paste_y = foot_y_target - int(round(y_foot * scale))
    canvas.paste(scaled, (paste_x, paste_y))
    return canvas


def load_ref_views():
    """加载参考三视图。实测参考图下巴=26.65时，发冠顶实际为38.02单位（而非诺米的36.4）。"""
    front_im = Image.open(D / "ref/ref_front.png").convert("RGB")
    sb_im = Image.open(D / "ref/ref_side_back.png").convert("RGB")
    sb_w, sb_h = sb_im.size
    side_raw = sb_im.crop((0, 0, int(sb_w * 0.46), sb_h))
    back_raw = sb_im.crop((int(sb_w * 0.44), 0, sb_w, sb_h))
    return {
        "正面": normalize_char_tile(front_im, target_crown_u=38.02),
        "正侧": normalize_char_tile(side_raw, target_crown_u=38.02),
        "背面": normalize_char_tile(back_raw, target_crown_u=38.02),
    }


def load_model_views():
    """加载 model_sheet.png 四个视图，按模型自身实时实测的发冠高度对齐到统一 px/unit。"""
    sheet = Image.open(D / "model_sheet.png").convert("RGB")
    W = sheet.width // 4
    H = sheet.height
    names = ["正面", "3/4", "正侧", "背面"]
    # 从 bbmodel 读取实际发冠最高点（排除龙角和脚，只取头发组最高 y）
    d = json.loads((D / "longnu.bbmodel").read_text())
    hair_max_y = max(
        (e["to"][1] for e in d["elements"]
         if any(k in e["name"] for k in ("冠", "刘海", "发", "后脑", "鬓"))),
        default=36.4,
    )
    out = {}
    for i, nm in enumerate(names):
        tile = sheet.crop((i * W, 0, (i + 1) * W, H))
        out[nm] = normalize_char_tile(tile, target_crown_u=hair_max_y)
    return out, sheet, hair_max_y


def color_masks(tile):
    a = np.asarray(tile, dtype=np.int16)
    fg = fg_mask(tile)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    hair = fg & (r < 95) & (g < 85) & (b < 95)
    red = fg & (r > 135) & (r - g > 65) & (r - b > 55)
    white = fg & (r > 195) & (g > 195) & (b > 195) & (np.abs(r - b) < 25)
    skin = fg & (r > 205) & (g > 165) & (b > 155) & (r - b > 15) & (r - g < 55)
    return {"fg": fg, "hair": hair, "red": red, "white": white, "skin": skin}


def iou(m1, m2):
    inter = np.logical_and(m1, m2).sum()
    union = np.logical_or(m1, m2).sum()
    return float(inter) / float(union) if union > 0 else 1.0


def audit_bbmodel():
    p = D / "longnu.bbmodel"
    d = json.loads(p.read_text())
    els = d["elements"]
    grps = d["groups"]
    bad_boxes = [e["name"] for e in els if any(b <= a for a, b in zip(e["from"], e["to"]))]
    horns = [e for e in els if "角" in e["name"] and "鬓" not in e["name"]]
    horn_max_y = max((e["to"][1] for e in horns), default=0.0)

    skel_path = D / "ref/nomi_ysm_skeleton.json"
    missing_core_bones = []
    if skel_path.exists():
        nomi_trees = json.loads(skel_path.read_text())
        longnu_g_names = {g["name"] for g in grps}
        coat_only = {"Jacket", "CoatShell", "NomiHood", "RightArmCoat", "LeftArmCoat", "RightForeArmCoat", "LeftForeArmCoat"}

        def check_node(n):
            nm = n["name"]
            if nm in coat_only or nm.startswith("Coat"):
                return
            if nm not in longnu_g_names:
                missing_core_bones.append(nm)
            for ch in n.get("children", []):
                check_node(ch)

        for t in nomi_trees:
            if t:
                check_node(t)

    return {
        "elements": len(els),
        "groups": len(grps),
        "bad_boxes": bad_boxes,
        "horn_cubes": len(horns),
        "horn_max_y": round(horn_max_y, 2),
        "has_pleats": any("Pleat" in g["name"] for g in grps),
        "missing_ysm_bones_count": len(missing_core_bones),
        "missing_ysm_bones_sample": missing_core_bones[:15],
    }


def make_diff_tile(ref_im, mod_im):
    """生成红蓝差异叠图：红=参考图有但模型缺失，蓝=模型多出。"""
    rm = fg_mask(ref_im)
    mm = fg_mask(mod_im)
    r_arr = np.asarray(ref_im, dtype=np.int16)
    m_arr = np.asarray(mod_im, dtype=np.int16)
    vis = np.full((ref_im.height, ref_im.width, 3), (232, 233, 238), dtype=np.uint8)
    both = rm & mm
    vis[both] = ((r_arr[both] + m_arr[both]) // 2).astype(np.uint8)
    vis[rm & (~mm)] = (255, 68, 68)
    vis[mm & (~rm)] = (58, 128, 255)
    return Image.fromarray(vis)


def main():
    refs = load_ref_views()
    mods, _, hair_max_y = load_model_views()
    W, H = 420, 860
    # 3 行 x 4 列：第1行 参考图，第2行 当前模型，第3行 红蓝差异叠图
    canvas = Image.new("RGB", (W * 4, H * 3 + 110), (225, 227, 233))
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 18)
    except Exception:
        font = None

    cols = ["正面", "3/4", "正侧", "背面"]
    scores = {}
    for i, nm in enumerate(cols):
        mod_im = mods[nm]
        canvas.paste(mod_im, (i * W, H + 70))
        draw.text((i * W + 12, H + 44), f"当前模型·{nm} (冠顶={hair_max_y:.2f})", fill=(40, 40, 50), font=font)
        if nm in refs:
            ref_im = refs[nm]
            canvas.paste(ref_im, (i * W, 34))
            rm = color_masks(ref_im)
            mm = color_masks(mod_im)
            fg_iou = iou(rm["fg"], mm["fg"])
            head_iou = iou(rm["fg"][:365, :], mm["fg"][:365, :])
            body_iou = iou(rm["fg"][340:580, :], mm["fg"][340:580, :])
            legs_iou = iou(rm["fg"][560:815, :], mm["fg"][560:815, :])
            hair_iou = iou(rm["hair"], mm["hair"])
            scores[nm] = {
                "fg_iou": round(fg_iou * 100, 1),
                "head_iou": round(head_iou * 100, 1),
                "body_iou": round(body_iou * 100, 1),
                "legs_iou": round(legs_iou * 100, 1),
                "hair_iou": round(hair_iou * 100, 1),
            }
            draw.text(
                (i * W + 12, 8),
                f"参考·{nm} | 总{scores[nm]['fg_iou']}% 头{scores[nm]['head_iou']}%",
                fill=(40, 40, 50),
                font=font,
            )
            diff_im = make_diff_tile(ref_im, mod_im)
            canvas.paste(diff_im, (i * W, H * 2 + 104))
            draw.text((i * W + 12, H * 2 + 78), f"差异叠图·{nm} (红=缺 蓝=多余)", fill=(40, 40, 50), font=font)
        else:
            ov = np.asarray(refs["正面"], dtype=np.float32) * 0.45 + np.asarray(mods["正面"], dtype=np.float32) * 0.55
            canvas.paste(Image.fromarray(ov.astype(np.uint8)), (i * W, 34))
            draw.text((i * W + 12, 8), "正面半透明叠印对照", fill=(40, 40, 50), font=font)

    canvas.save(D / "audit_sheet.png")
    # 同时导出单独的 3 列红蓝差异图，方便一眼审查局部像素对齐
    diff_sheet = Image.new("RGB", (W * 3, H + 40), (225, 227, 233))
    dd = ImageDraw.Draw(diff_sheet)
    for i, nm in enumerate(["正面", "正侧", "背面"]):
        diff_im = make_diff_tile(refs[nm], mods[nm])
        diff_sheet.paste(diff_im, (i * W, 34))
        dd.text((i * W + 12, 8), f"差异叠图·{nm} (红=缺 蓝=多余 | 总{scores[nm]['fg_iou']}%)", fill=(40, 40, 50), font=font)
    diff_sheet.save(D / "audit_diff.png")
    bb_info = audit_bbmodel()
    bb_info["hair_max_y"] = round(hair_max_y, 2)
    print("=== AUDIT SUMMARY ===")
    print("BBMODEL:", json.dumps(bb_info, ensure_ascii=False))
    for k, v in scores.items():
        print(f"VIEW [{k}]:", json.dumps(v, ensure_ascii=False))


if __name__ == "__main__":
    main()
