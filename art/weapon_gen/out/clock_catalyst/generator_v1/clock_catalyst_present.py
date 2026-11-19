"""Compose actual Blender renders into a review sheet and rotation GIF."""
from PIL import Image,ImageDraw,ImageFont
import os,glob
OUT='art/weapon_gen/out/clock_catalyst'
BG=(22,30,48,255)
def flatten(path):
    im=Image.open(path).convert('RGBA');bg=Image.new('RGBA',im.size,BG);bg.alpha_composite(im)
    return bg.convert('RGB')
font_path='/System/Library/Fonts/Supplemental/Arial.ttf'
font=ImageFont.truetype(font_path,24);small=ImageFont.truetype(font_path,17)
for name in ['hero','front','side','top','back']:
    flatten(OUT+'/'+name+'.png').save(OUT+'/'+name+'_view.jpg',quality=95)
sheet=Image.new('RGB',(1440,1120),BG[:3]);draw=ImageDraw.Draw(sheet)
draw.text((32,22),'CLOCK CATALYST / ARTICULATED MODEL 01',font=font,fill=(225,237,255))
draw.text((32,57),'Three meridians / shared vertical axis / independent blue-white dial',font=small,fill=(160,185,213))
sheet.paste(flatten(OUT+'/hero.png').resize((820,820)),(0,150))
draw.text((32,100),'PERSPECTIVE STUDY (orthographic camera)',font=small,fill=(190,209,231))
for i,(name,label) in enumerate([('front','FRONT'),('side','SIDE'),('top','TOP')]):
    x,y=840,95+330*i
    sheet.paste(flatten(OUT+'/'+name+'.png').resize((320,320)),(x+100,y))
    draw.text((x+12,y+140),label,font=small,fill=(190,209,231))
draw.text((32,1032),'Gold: 3 separate ring meshes   |   White / blue: double-sided rotating dial',font=small,fill=(190,209,231))
draw.text((32,1063),'Solid geometry review. Stellar veil reserved for the next effects pass.',font=small,fill=(150,173,202))
sheet.save(OUT+'/model_sheet.jpg',quality=95)
paths=sorted(glob.glob(OUT+'/frames/*.png'))
assert len(paths)==40, 'Missing animation frames'
frames=[flatten(p) for p in paths]
# One shared palette avoids flicker between frames.
palette=frames[0].quantize(colors=160)
frames=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
frames[0].save(OUT+'/rotation.gif',save_all=True,append_images=frames[1:],duration=200,loop=0,optimize=False,disposal=2)
print('PASS presentation: 5 views, model_sheet.jpg, 40-frame 8s rotation.gif')
