#!/usr/bin/env python3
"""龙娘完整模型四视图（离线正交渲染）：正面 / 3/4 / 正侧 / 背面，浅灰背景，无文字。输出 model_sheet.png"""
from pathlib import Path
from PIL import Image
import build_longnu as B

D = Path(__file__).resolve().parent
root = B.build()
atlas = B.make_atlas(root)
faces = B.collect_faces(root, reference_stance=True)
W, H = 420, 860
views = [0, -35, 90, 180]  # 正面 / 3/4 / 正侧 / 背面
tiles = [Image.fromarray(B.render(faces, atlas, yaw, 0, scale=17.5, size=(W, H), center=(2.25, 21.5, 2.25) if yaw == -35 else (0, 21.5, 0))) for yaw in views]
sheet = Image.new("RGB", (W * 4, H), (232, 233, 238))
for i, t in enumerate(tiles):
    sheet.paste(t, (i * W, 0))
sheet.save(D / "model_sheet.png")
print("ok", sheet.size)
