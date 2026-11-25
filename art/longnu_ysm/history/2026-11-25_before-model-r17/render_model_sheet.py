#!/usr/bin/env python3
"""龙娘完整模型四视图（离线正交渲染）：正面 / 3/4 / 正侧 / 背面，浅灰背景，无文字。输出 model_sheet.png"""
from pathlib import Path
from PIL import Image
import build_longnu as B

D = Path(__file__).resolve().parent
root = B.build()
atlas = B.make_atlas(root)
faces = B.collect_faces(root, reference_stance=True)
W, H = 460, 860
views = [0, -35, 90, 180]  # 正面 / 3/4 / 正侧 / 背面
tiles = [Image.fromarray(B.render(faces, atlas, yaw, 0, scale=17.5, size=(W, H), center=(2.25, 21.5, 2.25) if yaw == -35 else (0, 21.5, 0))) for yaw in views]
sheet = Image.new("RGB", (W * 4, H), (232, 233, 238))
for i, t in enumerate(tiles):
    sheet.paste(t, (i * W, 0))
sheet.save(D / "model_sheet.png")
print("ok", sheet.size)

reference = Image.open(D/'ref/voxel_coat_r1.png').convert('RGB')
reference = reference.resize((round(reference.width*H/reference.height),H),Image.Resampling.LANCZOS)
comparison = Image.new('RGB',(reference.width+sheet.width,H))
comparison.paste(reference,(0,0))
comparison.paste(sheet,(reference.width,0))
comparison.save(D/'coat_compare.png')

final_views=D/'final_views'
final_views.mkdir(exist_ok=True)
for name,yaw in zip(('front','three_quarter','side','back'),views):
    center=(2.25,21.0,2.25) if yaw==-35 else (0,21.0,0)
    pixels=B.render(faces,atlas,yaw,0,scale=26,size=(840,1200),center=center)
    Image.fromarray(pixels).save(final_views/(name+'.png'))
comparison.save(final_views/'coat_compare.png')
