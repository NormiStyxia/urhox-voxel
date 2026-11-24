"""Engrave the two registered 128px plates at their native pixel resolution."""
from math import sin, cos, atan2, hypot, pi, floor
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
# Shadow, deep enamel, patina, plate, burnished lip, ivory, oxide, bright enamel.
WARM = ['#122e35', '#254548', '#42726a', '#986c45', '#daaa63', '#ffe6a0', '#5c5845', '#7bb8a2']
COLD = ['#102e40', '#174d60', '#307e87', '#448f91', '#8dd6ce', '#ddffdf', '#36646c', '#62b8bd']
ROMAN = ['XII','I','II','III','IV','V','VI','VII','VIII','IX','X','XI']
LETTERS = {'I':['111','010','010','010','111'], 'V':['101','101','101','101','010'], 'X':['101','101','010','101','101']}

def engrave(cold):
    palette = COLD if cold else WARM
    def ink(i): return tuple(bytes.fromhex(palette[i][1:]))+(255,)
    plate=Image.new('RGBA',(128,128)); d=ImageDraw.Draw(plate)
    for y in range(128):
        for x in range(128):
            dx,dy=x-63.5,63.5-y; r=hypot(dx,dy); a=atan2(dx,dy)%(2*pi)
            if r>62: continue
            sector=a*6/pi; seam=abs((sector+.5)%1-.5)*r*pi/6
            corrosion=sin(.12*dx+.04*dy)+.7*sin(.17*dy-.1*dx)+.32*sin(.29*dx+.25*dy)
            color=2 if corrosion>.55 else 3 if corrosion<-.45 else 6
            if 49<r<56: color=2 if corrosion>.8 else 1
            if 33<r<44: color=1 if seam<1.3 else 2 if corrosion>.15 else 3
            if r<31: color=1 if corrosion>.3 else 0
            if seam<.75 and 31<r<58: color=0
            if any(abs(r-n)<.55 for n in [61,57,47,44,32,28]): color=4
            if any(abs(r-n)<.6 for n in [59,45.5,30.5]): color=0
            if 7<r<25 and abs(r-16-7*cos(6*a))<1.1: color=4
            if r<5: color=4 if r>3 else 0
            # Riveted openwork: light actually passes through the teardrop slots.
            if 38<r<43 and abs((sector%1)-.5)<.14*(1-abs(r-40.5)/3): continue
            if 22<r<27 and abs((sector%1)-.5)<.17: continue
            plate.putpixel((x,y),ink(color))
    for hour,label in enumerate(ROMAN):
        a=hour*pi/6; ox,oy=63.5+51.8*sin(a),63.5-51.8*cos(a)
        for k,ch in enumerate(label):
            for row,line in enumerate(LETTERS[ch]):
                for col,val in enumerate(line):
                    if val=='1': d.point((round(ox+k*4+col-(4*len(label)-2)/2),round(oy+row-2)),ink(5))
        # The cartouches carry alternating lozenges and engraved forked hands.
        def pos(r,side):return (round(63.5+r*sin(a)+side*cos(a)), round(63.5-r*cos(a)+side*sin(a)))
        d.polygon([pos(34,0),pos(39,-2),pos(43,0),pos(39,2)],fill=ink(0),outline=ink(4))
        if cold:
            for r in [18,22,26]:
                d.line([pos(r-2,-3),pos(r,0),pos(r-2,3)],fill=ink(7))
            d.line([pos(14,0),pos(27,0)],fill=ink(4))
        elif hour%2==0:
            d.line([pos(12,0),pos(22,0)],fill=ink(3)); d.point(pos(24,0),ink(5))
        x,y=pos(58,0);d.point((x,y),ink(5))
    # Interlocked glass bulbs at the spindle. Their openings and thin stream
    # read upright when the plate is seen on the ground.
    d.polygon([(56,55),(71,55),(69,60),(65,64),(69,68),(71,73),(56,73),(58,68),(62,64),(58,60)],fill=ink(0),outline=ink(4))
    d.line([(57,55),(70,55)],fill=ink(5),width=2); d.line([(57,73),(70,73)],fill=ink(4),width=2)
    d.polygon([(59,58),(68,58),(64,62)],fill=ink(7 if cold else 4)); d.line([(64,62),(64,68)],fill=ink(5));d.polygon([(59,70),(64,67),(68,70)],fill=ink(5))
    return plate

if __name__=='__main__':
    atlas=Image.new('RGBA',(256,128));atlas.paste(engrave(False),(0,0));atlas.paste(engrave(True),(128,0))
    atlas.save(ROOT/'assets/Textures/fx/TimeWraithDial.png')
