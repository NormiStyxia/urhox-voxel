"""Author the construct's six pixel stamps and their eight painted exposures. No resampling."""
from pathlib import Path
from math import atan2, cos, sin, pi, hypot, floor
from PIL import Image, ImageDraw

N=64
INK='#16304b'; LAPIS='#245478'; JADE='#278f95'; TEAL='#4cdec6'
MINT='#b6f6d8'; WHITE='#fff4d2'; BRONZE='#8b5140'; GOLD='#eaa94f'; LEMON='#ffdd88'

def point(angle,radius,tangent=0):
    return (round(31.5+cos(angle)*radius-sin(angle)*tangent),
            round(31.5+sin(angle)*radius+cos(angle)*tangent))

def draw_stamp(row,frame):
    image=Image.new('RGBA',(N,N));d=ImageDraw.Draw(image)
    if row in (0,1):
        # Eight pinned voussoirs around four cut-stone sockets. Each has an
        # engraved, stepped conductor, a bronze lip and a pale rivet head.
        for i in range(8):
            a=i*pi/4;inner=row==1
            def shape(points): return [point(a,r,t) for r,t in points]
            if inner:
                d.polygon(shape([(12,-1),(18,-2),(20,-6),(24,-6),(22,-1),(28,0),(22,2),(19,7),(18,3)]),fill=LAPIS)
                d.line(shape([(12,0),(18,0),(21,-3),(24,-3)]),fill=TEAL,width=2)
                d.line(shape([(20,4),(23,1),(27,0)]),fill=LEMON)
                d.line([point(a+.13,16),point(a+.40,15),point(a+.62,16)],fill=JADE)
            else:
                d.polygon(shape([(20,-7),(25,-9),(28,-7),(29,-3),(31,-2),(31,2),(28,3),(27,7),(23,9),(20,6),(22,3),(22,-3)]),fill=INK)
                d.polygon(shape([(22,-6),(25,-8),(27,-6),(28,-2),(28,3),(26,6),(23,7),(24,3),(24,-3)]),fill=LAPIS)
                d.line(shape([(21,-6),(23,-8),(26,-8),(28,-5)]),fill=GOLD,width=2)
                d.line(shape([(27,-4),(25,-3),(25,1),(27,2),(25,4),(22,5)]),fill=TEAL)
                d.line(shape([(28,0),(30,0)]),fill=LEMON,width=2)
                d.line([point(a+.25,19),point(a+.5,19),point(a+.55,21)],fill=GOLD)
        if row==1:
            d.polygon([(32,19),(39,31),(32,42),(24,32)],outline=GOLD,width=2)
            d.line([(32,24),(35,31),(31,34),(29,31),(32,27)],fill=MINT,width=2)
        # A stepped azimuthal brush uncovers metal relief, followed by a
        # narrow, hot leading edge. Early frames retain isolated dark rivets.
        for y in range(N):
            for x in range(N):
                rgba=image.getpixel((x,y))
                if not rgba[3]: continue
                phase=((atan2(y-31.5,x-31.5)/(2*pi)+.125)%1 +.14*((x//3+y//3)%3)/3)%1
                edge=(frame+1)/8-phase
                if edge<0: image.putpixel((x,y),(22,48,75,150) if (x+y)%7==0 else (0,0,0,0))
                elif edge<.10: d.point((x,y),fill=WHITE if (x+y)%3 else GOLD)
    elif row in (2,3):
        # Broken arrowhead charges in the spine, asynchronous arcing filaments on the sheath.
        for k in range(-2,5):
            x=k*26+frame*4; y=32+(k%2)*3
            if row==2:
                d.polygon([(x-13,y-3),(x-3,y-3),(x,y-9),(x+8,y-2),(x+13,y),(x+4,y+2),(x-1,y+7),(x-3,y+2),(x-10,y+2)],fill=TEAL)
                d.line([(x-9,y),(x-1,y),(x+1,y-3),(x+6,y)],fill=WHITE,width=2)
                d.line([(x-11,y+9),(x-5,y+9),(x-3,y+6)],fill=GOLD)
            else:
                for sign in (-1,1):
                    v=y+sign*(11+((k+frame)%3)*2)
                    d.line([(x-9,v),(x-3,v),(x+1,v-sign*5),(x+7,v-sign*5),(x+9,v-sign*8)],fill=JADE,width=2)
                    d.line([(x+1,v-sign*5),(x+4,v-sign*5)],fill=MINT)
                    d.point((x+12,v+sign*4),fill=GOLD)
    elif row==4:
        # Overload scar: an off-centre fractured seal, radial branching fractures, molten staples.
        for i in range(9):
            a=i*2*pi/9+.08*(i%3); extent=min(30,9+frame*4-(i%4))
            route=[point(a,3),point(a,8,2),point(a,12,-1),point(a,17,-2+i%3),point(a,21,2),point(a,extent,1-i%4)]
            if frame<3: route=route[:3+frame]
            d.line(route,fill=BRONZE,width=3);d.line(route,fill=GOLD)
            if frame>=2:d.line([route[2],point(a,13,5),point(a,16+i%4,6)],fill=TEAL)
            if i%2==frame%2:d.line([point(a,9),point(a+.3,10),point(a+.42,9)],fill=WHITE,width=2)
        d.polygon([(30,25),(37,28),(38,33),(32,38),(26,34),(25,29)],fill=GOLD,outline=LEMON)
        d.line([(28,32),(32,29),(34,32)],fill=WHITE,width=2)
    else:
        # Split brackets and vent flakes; the central aperture stays transparent.
        for i in range(6):
            a=i*pi/3+pi/6; r=14+frame; col=GOLD if frame<3 else TEAL
            d.line([point(a,r,-5),point(a,r+3,-2),point(a,r+3,2),point(a,r,5)],fill=col,width=2)
            d.line([point(a,r+4,-1),point(a,r+4,1)],fill=WHITE)
            if i%2==0:d.polygon([point(a,r+4,2),point(a,r+9),point(a,r+7,-2)],fill=LEMON if frame<3 else JADE)
    return image

if __name__=='__main__':
    atlas=Image.new('RGBA',(N*8,N*6))
    for row in range(6):
        for frame in range(8): atlas.paste(draw_stamp(row,frame),(frame*N,row*N))
    path=Path('assets/Textures/fx/RuinConstructOptics.png');atlas.save(path,optimize=True)
    print(path,atlas.size,len(atlas.getcolors()))
