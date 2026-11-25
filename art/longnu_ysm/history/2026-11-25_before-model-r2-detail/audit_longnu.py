#!/usr/bin/env python3
"""
小龙娘 YSM 模型与参考三视图自动对齐、轮廓/色域对比与结构审计工具。
不修改 build_longnu.py 或 longnu.bbmodel，仅读取并输出 audit_sheet.png 与控制台报告。
"""
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

D = Path(__file__).resolve().parent


def fg_mask(rgb, bg_tol=18):
    """提取非背景前景掩码（背景为左上角采样色）。"""
    arr = np.asarray(rgb, dtype=np.int16)
    bg = np.median(arr[:20, :20, :], axis=(0, 1))
    diff = np.abs(arr - bg).max(axis=2)
    return diff > bg_tol


def normalize_char_tile(img, target_size=(420, 860), foot_y_target=800, px_per_unit=17.5):
    """按脚底中点 x_mid 与脚底到发冠顶高度 (36.4 单位) 归一化到完全一致的坐标系画布。"""
    m = fg_mask(img)
    ys, xs = np.where(m)
    if len(ys) == 0:
        return img.resize(target_size, Image.Resampling.LANCZOS)
    y_foot_bot = int(ys.max())
    # 用最底部 18px（仅双脚）定水平中线 x_mid
    foot_xs = np.where(m[max(0, y_foot_bot - 18):y_foot_bot + 1, :])[1]
    x_mid = int(round((foot_xs.min() + foot_xs.max()) / 2)) if len(foot_xs) else int(round((xs.min() + xs.max()) / 2))
    # 在中线附近 (±6px) 找发冠顶 y_crown_top（避开两侧高出的龙角）
    H_im, W_im = m.shape
    c_slice = m[:, max(0, x_mid - 6):min(W_im, x_mid + 7)]
    c_ys = np.where(c_slice)[0]
    y_crown_top = int(c_ys.min()) if len(c_ys) else int(ys.min())
    crown_h_px = max(1, y_foot_bot - y_crown_top)
    target_crown_h_px = 36.4 * px_per_unit
    scale = target_crown_h_px / crown_h_px

    r_arr = np.asarray(img).copy()
    r_arr[~m] = (232, 233, 238)
    clean_im = Image.fromarray(r_arr)
    nw = max(1, int(round(W_im * scale)))
    nh = max(1, int(round(H_im * scale)))
    scaled = clean_im.resize((nw, nh), Image.Resampling.NEAREST)

    W, H = target_size
    canvas = Image.new("RGB", (W, H), (232, 233, 238))
    new_x_mid = int(round(x_mid * scale))
    new_y_foot = int(round(y_foot_bot * scale))
    paste_x = W // 2 - new_x_mid
    paste_y = foot_y_target - new_y_foot
    canvas.paste(scaled, (paste_x, paste_y))
    return canvas


def load_ref_views():
    """加载参考三视图（正面、正侧面、背面）并归一化到 420x860。"""
    front_im = Image.open(D / "ref/ref_front.png").convert("RGB")
    sb_im = Image.open(D / "ref/ref_side_back.png").convert("RGB")
    sb_w, sb_h = sb_im.size
    side_raw = sb_im.crop((0, 0, int(sb_w * 0.46), sb_h))
    back_raw = sb_im.crop((int(sb_w * 0.44), 0, sb_w, sb_h))
    return {
        "正面": normalize_char_tile(front_im),
        "正侧": normalize_char_tile(side_raw),
        "背面": normalize_char_tile(back_raw),
    }


def load_model_views():
    """加载 model_sheet.png 中的四个视图并同样按前景高度归一化到 420x860。"""
    sheet = Image.open(D / "model_sheet.png").convert("RGB")
    W = sheet.width // 4
    H = sheet.height
    names = ["正面", "3/4", "正侧", "背面"]
    out = {}
    for i, nm in enumerate(names):
        tile = sheet.crop((i * W, 0, (i + 1) * W, H))
        out[nm] = normalize_char_tile(tile)
    return out, sheet


def color_masks(tile):
    """提取关键部位颜色掩码：黑发、红饰(花/飘带/眼)、白衣裙、肤色、紫尾/粉角。"""
    a = np.asarray(tile, dtype=np.int16)
    fg = fg_mask(tile)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    hair = fg & (r < 95) & (g < 85) & (b < 95)
    red = fg & (r > 135) & (r - g > 70) & (r - b > 60)
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

    # 对照 nomi_ysm_skeleton.json 检查标准骨架复用情况
    skel_path = D / "ref/nomi_ysm_skeleton.json"
    missing_core_bones = []
    if skel_path.exists():
        nomi_trees = json.loads(skel_path.read_text())
        longnu_g_names = {g["name"] for g in grps}
        # 统计非诺米风衣专属(Jacket/Coat/NomiHood)的骨骼覆盖率
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


def main():
    refs = load_ref_views()
    mods, raw_sheet = load_model_views()
    W, H = 420, 860
    # 制作 3 行 x 4 列对比图：第 1 行 参考图，第 2 行 当前模型归一化，第 3 行 轮廓与色域差异叠加
    canvas = Image.new("RGB", (W * 4, H * 2 + 80), (225, 227, 233))
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 20)
    except Exception:
        font = None

    cols = ["正面", "3/4", "正侧", "背面"]
    scores = {}
    for i, nm in enumerate(cols):
        mod_im = mods[nm]
        canvas.paste(mod_im, (i * W, H + 70))
        draw.text((i * W + 14, H + 44), f"当前模型·{nm}", fill=(40, 40, 50), font=font)
        if nm in refs:
            ref_im = refs[nm]
            # 制作半透明叠加对比在参考图右侧或直接在顶部展示参考图
            canvas.paste(ref_im, (i * W, 34))
            rm = color_masks(ref_im)
            mm = color_masks(mod_im)
            fg_iou = iou(rm["fg"], mm["fg"])
            hair_iou = iou(rm["hair"], mm["hair"])
            head_fg_iou = iou(rm["fg"][:380, :], mm["fg"][:380, :])
            head_hair_iou = iou(rm["hair"][:380, :], mm["hair"][:380, :])
            scores[nm] = {
                "fg_iou": round(fg_iou * 100, 1),
                "hair_iou": round(hair_iou * 100, 1),
                "head_fg_iou": round(head_fg_iou * 100, 1),
                "head_hair_iou": round(head_hair_iou * 100, 1),
            }
            draw.text(
                (i * W + 14, 8),
                f"参考·{nm} (轮廓IoU {scores[nm]['fg_iou']}% | 头部发IoU {scores[nm]['head_hair_iou']}%)",
                fill=(40, 40, 50),
                font=font,
            )
        else:
            # 3/4 位置放轮廓对比叠加图（正面参考红线 vs 模型蓝线）
            ov = np.asarray(refs["正面"], dtype=np.float32) * 0.45 + np.asarray(mods["正面"], dtype=np.float32) * 0.55
            canvas.paste(Image.fromarray(ov.astype(np.uint8)), (i * W, 34))
            draw.text((i * W + 14, 8), "正面叠印对照 (半透明重合)", fill=(40, 40, 50), font=font)

    canvas.save(D / "audit_sheet.png")
    bb_info = audit_bbmodel()
    print("=== AUDIT SUMMARY ===")
    print("BBMODEL:", json.dumps(bb_info, ensure_ascii=False))
    for k, v in scores.items():
        print(f"VIEW [{k}]:", json.dumps(v, ensure_ascii=False))


if __name__ == "__main__":
    main()
