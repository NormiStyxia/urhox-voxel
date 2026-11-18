"""v6 review sheet (front large + 3/4 + right + top) and 12 s GIF from the Blender frames."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
out = Path('art/weapon_gen/out/clock_catalyst_v6')
f = ImageFont.truetype('/System/Library/Fonts/Supplemental/Times New Roman.ttf', 30)
sheet = Image.new('RGB', (1800, 1000), (204, 209, 222))
d = ImageDraw.Draw(sheet)
for (name, label, box, pos) in (('front', 'FRONT', 900, (20, 70)), ('hero', '3/4', 430, (940, 70)),
                                ('right', 'RIGHT', 400, (1380, 70)), ('top', 'TOP', 400, (1380, 540))):
    im = Image.open(out / (name + '.png')).convert('RGB').resize((box, box))
    sheet.paste(im, pos)
    d.text((pos[0] + 10, pos[1] - 45), label, font=f, fill=(25, 40, 90))
sheet.save(out / 'model_sheet.jpg', quality=94)
frames = [Image.open(p).convert('RGB') for p in sorted((out / 'frames').glob('*.png'))]
assert len(frames) == 60
pal = frames[0].quantize(colors=240)
q = [fr.quantize(palette=pal, dither=Image.Dither.NONE) for fr in frames]
q[0].save(out / 'rotation.gif', save_all=True, append_images=q[1:], duration=200, loop=0)
grid = Image.new('RGB', (1280, 1280))
for i, k in enumerate((0, 10, 20, 30)):
    grid.paste(frames[k], ((i % 2) * 640, (i // 2) * 640))
grid.save(out / 'motion-review.jpg', quality=94)
print('PASS v6 sheet + gif 60 frames / 12 s')
