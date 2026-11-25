"""参考图与离线渲染并排对照，输出 compare.png。"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
D = Path(__file__).resolve().parent
ref = Image.open(D / 'ref/voxel_ref.png').convert('RGB')
pv = Image.open(D / 'preview.png').convert('RGB')
W, H = 560, 520
crops = [ref.crop((60, 20, 500, 840)), ref.crop((600, 20, 1010, 840)), ref.crop((1050, 20, 1480, 840))]
mine = [pv.crop((i * W + 60, 20, i * W + 500, 600)) for i in range(3)]
fit = lambda im: im.resize((int(im.width * H / im.height), H), Image.LANCZOS)
row1, row2 = [fit(c) for c in crops], [fit(m) for m in mine]
cw = max(i.width for i in row1 + row2)
sheet = Image.new('RGB', (cw * 4 + 50, H * 2 + 80), (236, 237, 241))
d = ImageDraw.Draw(sheet)
f = ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc', 24)
for i, im in enumerate(row1): sheet.paste(im, (10 + i * cw + (cw - im.width) // 2, 40))
for i, im in enumerate(row2): sheet.paste(im, (10 + i * cw + (cw - im.width) // 2, H + 70))
for fn, yy in (('preview_face.png', 40), ('preview_face34.png', H + 70)):
    im = Image.open(D / fn); im = im.resize((cw, int(cw * im.height / im.width))); sheet.paste(im, (10 + 3 * cw + 30, yy + (H - im.height) // 2))
d.text((14, 6), '参考图', fill=(80, 80, 90), font=f)
d.text((14, H + 42), 'Blockbench 模型（离线正交渲染：正 / 左 / 背）', fill=(80, 80, 90), font=f)
d.text((10 + 3 * cw + 34, 6), '脸部：正面 / 3/4', fill=(80, 80, 90), font=f)
sheet.save(D / 'compare.png')
