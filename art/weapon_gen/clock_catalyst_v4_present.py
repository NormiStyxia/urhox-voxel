"""Review sheet and correctly timed loop made from actual Blender renders."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

output = Path('art/weapon_gen/out/clock_catalyst_v4')
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',22)
small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',17)
sheet = Image.new('RGB',(1440,1080),(16,22,34))
draw = ImageDraw.Draw(sheet)
draw.text((32,20),'CLOCK CATALYST / PROJECTED ROMAN CLOCKS',font=font,fill=(218,232,249))
hero = Image.open(output/'hero.png').convert('RGB')
hero.save(output/'hero.jpg',quality=95)
sheet.paste(hero.resize((870,870)),(0,130))
for index,(name,label) in enumerate([('front','FRONT'),('right','RIGHT'),('top','TOP')]):
    position = (940,80+index*325)
    view = Image.open(output/(name+'.png')).convert('RGB').resize((315,315))
    sheet.paste(view,position)
    draw.text((1280,position[1]+145),label,font=small,fill=(183,205,235))
draw.text((32,1020),'Same geometry / same pose / orthographic views',font=small,fill=(183,205,235))
sheet.save(output/'model_sheet.jpg',quality=95)
if '--stills-only' not in sys.argv:
    paths = sorted((output/'frames').glob('*.png'))
    assert len(paths)==60, 'Animation frames missing'
    frames = [Image.open(path).convert('RGB') for path in paths]
    palette_source = Image.new('RGB',(640*4,640))
    for column,index in enumerate([0,15,30,45]):
        palette_source.paste(frames[index],(640*column,0))
    palette = palette_source.quantize(colors=240)
    frames = [frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
    frames[0].save(output/'rotation.gif',save_all=True,append_images=frames[1:],
                   duration=200,loop=0,disposal=2,optimize=False)
    preview = Image.new('RGB',(1280,1280))
    for cell,index in enumerate([0,10,20,30]):
        preview.paste(frames[index].convert('RGB'),((cell%2)*640,(cell//2)*640))
    preview.save(output/'motion-review.jpg',quality=95)
    check = Image.open(output/'rotation.gif')
    elapsed = 0
    for index in range(check.n_frames):
        check.seek(index)
        elapsed += check.info['duration']
    assert elapsed==12000, 'GIF timing does not match Blender animation'
    print('PASS review sheet and GIF: 60 frames / 12 seconds')
