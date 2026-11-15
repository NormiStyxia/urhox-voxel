import math,random,json
from pathlib import Path
from PIL import Image,ImageDraw

def ss(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)
def column(i):
    a=(i+.5)*math.pi/12;x,z=math.cos(a)*23.6,math.sin(a)*23.6
    if abs(x)<5.45 and abs(z)>23.6*.9:x,z=math.copysign(5.45,x),math.copysign(math.sqrt(23.6**2-5.45**2),z)
    return x,z
def foot(x,z,i):
    cx,cz=column(i)
    return 1-ss(.015,.45,math.hypot(max(abs(x-cx)-1.2,0),max(abs(z-cz)-1.2,0)))
def ao(x,y,z,n=(0,1,0),day=1,strength=.28,distance=10,joint=0):
    strength*=ss(.15,.70,day)
    if not strength:return 1
    fade=1-ss(18.9,42,distance);local=0;up=ss(.55,.85,n[1])
    if 5.92<=y<6.4 and abs(math.hypot(x,z)-23.6)<2.2:
        i=math.floor(math.atan2(z,x)/(math.pi/12))
        closest=max(foot(x,z,j) for j in [i,i-1,i+1])
        band=max(up*(1-ss(.025,.12,abs(y-6))),(1-ss(.04,.32,y-6))*(1-up))
        local=closest*band
    zz=abs(z)
    if 20.75<=zz<33.5 and abs(x)<3.58:
        d=zz-20.75;top=min(6,.5*math.floor(d+1));f=d%1
        back=1-ss(.02,.32,1-f) if top<6 else 0
        wall=1-ss(.02,.30,3.5-abs(x)) if zz<32.75 else 0
        tread=max(back,wall*.7)*up*(1-ss(.025,.10,abs(y-top)))
        riser=(1-ss(.01,.06,f))*(1-ss(.02,.22,abs(y-(top-.5))))
        riser*=ss(.65,.9,-n[2]*math.copysign(1,z))*(1-up)
        local=max(local,tread,riser*.7)
    return 1-min(.32,strength)*fade*max(local,min(1,max(0,joint))*.65)

rng=random.Random(11);maxerror=0
for _ in range(20000):
    a=rng.uniform(-math.pi,math.pi);r=rng.uniform(21.4,25.8);x,z=math.cos(a)*r,math.sin(a)*r
    i=math.floor(a/(math.pi/12))
    nearest=max(foot(x,z,j) for j in [i,i-1,i+1])
    full=max(foot(x,z,j) for j in range(24))
    maxerror=max(maxerror,abs(nearest-full))
assert maxerror<1e-10,maxerror
for i in range(24):
    x,z=column(i)
    assert ao(x+1.25,6,z)<.9
    for y in [-14,0,5,7,14,20]: assert ao(x+1.25,y,z)==1,(i,y)
    assert ao(x+1.7,6,z)==1
    assert ao(x+1.25,6,z,day=0)==1
    assert ao(x+1.25,6,z,distance=42)==1
for sign in [-1,1]:
    for step in range(11):
        y=(step+1)*.5
        assert ao(0,y,sign*(20.75+step+.98))<.9
        assert ao(0,y,sign*(20.75+step+.30))==1
        assert ao(0,y+1,sign*(20.75+step+.98))==1
assert ao(0,6,33.2)==1 # top landing has no imaginary next riser
for _ in range(50000):
    x,y,z=rng.uniform(-80,80),rng.uniform(-20,40),rng.uniform(-80,80)
    value=ao(x,y,z)
    assert .72<=value<=1 and ao(x,y,z,strength=0)==1
print('PASS 20,000 closest-three vs all-24 anchors; 50,000 spatial samples; no wrong-height/cap/void projection; 0.3m treads; night/low/distance gates')

# These are analytical AO-factor maps only, not rendered game screenshots.
im=Image.new('RGB',(1020,620),(242,242,242));draw=ImageDraw.Draw(im)
draw.text((20,14),'CPU AO diagnostic / NOT Web / indirect-light factor only',fill=(15,15,15))
cx,cz=column(1)
for p,title in enumerate(['Pillar foot: BEFORE (AO=1)','Pillar foot: AFTER (high)','Stair tread: AFTER (high)']):
    draw.text((20+p*335,46),title,fill=(15,15,15))
    for py in range(480):
        for px in range(310):
            if p<2:
                x,z=cx+(px/309-.5)*5,cz+(py/479-.5)*5;y=6
                solid=abs(x-cx)<1.2 and abs(z-cz)<1.2
                value=1 if p==0 else ao(x,y,z)
                c=(150,154,162) if solid else tuple(int(t*value) for t in (223,224,219))
            else:
                x=-3.6+px/309*7.2;z=25.75+py/479*3;y=min(6,.5*math.floor(z-20.75+1))
                value=ao(x,y,z);c=tuple(int(t*value) for t in (223,224,219))
            im.putpixel((20+p*335+px,72+py),c)
draw.text((20,575),'Pillar actual base half-width 1.2m; contact falloff 0.45m. Camera distance: 10m.',fill=(25,25,25))
draw.text((20,595),'Day high AO >= 0.72. Night / low / >42m: AO=1. Direct light unchanged.',fill=(25,25,25))
im.save('validation/night-visibility/cpu-contact-ao.png')

def linear(x): return x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4
def luma(rgb):return sum(w*linear(c) for w,c in zip((.2126,.7152,.0722),rgb))
rows=[]
for label,old,new in [('zenith',(.05,.08,.20),(.17,.22,.32)),('horizon',(.14,.18,.32),(.24,.29,.39)),('nadir',(.07,.09,.13),(.13,.17,.24))]:
    a,b=luma(old)*.68,luma(new)*1.08
    rows.append({'hemisphere_sample':label,'old_srgb':old,'new_srgb':new,'old_linear_luma_times_diffuse':a,'new_linear_luma_times_diffuse':b,'ratio':b/a})
Path('validation/night-visibility/linear-sky-reference.json').write_text(json.dumps({'warning':'CPU input-radiance reference, not SH integral, exposure output, pixel readability or Web evidence','rows':rows},indent=2))
print('PASS CPU AO map and sRGB input-radiance reference generated (not visual acceptance)')
