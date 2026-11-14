import sys, math, re
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from lupa.lua54 import LuaRuntime

ROOT='/Users/xd/Desktop/体素test'
FONT='/System/Library/Fonts/Hiragino Sans GB.ttc'
S=2
W=int(sys.argv[1]) if len(sys.argv)>1 else 844
H=int(sys.argv[2]) if len(sys.argv)>2 else 390
MODE=sys.argv[3] if len(sys.argv)>3 else 'fallback'
OUT=sys.argv[4] if len(sys.argv)>4 else f'/tmp/forgeprev/out_{MODE}_{W}x{H}.png'
SCRIPT=sys.argv[5] if len(sys.argv)>5 else ''

img=Image.new('RGBA',(W*S,H*S))
# fake game scene behind
arr=np.zeros((H*S,W*S,4),dtype=np.uint8)
ys=np.linspace(0,1,H*S)[:,None]
arr[...,0]=(120-50*ys)
arr[...,1]=(170-50*ys)
arr[...,2]=(225-150*ys)
arr[...,3]=255
img=Image.fromarray(arr,'RGBA')
fonts={}
FACEFILES={}
def font(size,face=None):
    k=(int(round(size*S)),face)
    if k not in fonts:
        path=FACEFILES.get(face)
        try:
            fonts[k]=ImageFont.truetype(f'{ROOT}/{path}' if path else FONT,k[0],index=0)
        except Exception:
            fonts[k]=ImageFont.truetype(FONT,k[0],index=0)
    return fonts[k]
imgcache={}

class St:
    def __init__(s):
        s.m=[1,0,0,1,0,0]; s.fill=(255,255,255,255); s.stroke=(255,255,255,255); s.sw=1.0
        s.alpha=1.0; s.clip=None; s.fs=16; s.align=1; s.fillpaint=None; s.face=None; s.spacing=0
stack=[St()]
cur=lambda: stack[-1]
paths=[]  # list of (points, closed)
sub=None
def tx(x,y):
    a,b,c,d,e,f=cur().m
    return ((a*x+c*y+e)*S,(b*x+d*y+f)*S)
def mmul(m,t):
    a,b,c,d,e,f=m; A,B,C,D,E,F=t
    return [a*A+c*B,b*A+d*B,a*C+c*D,b*C+d*D,a*E+c*F+e,b*E+d*F+f]

def colr(c):
    return tuple(int(v) for v in c)

def composite(mask_img,box,color_arr_or_rgba,alpha):
    # mask_img: 'L' image for bbox; box: (x0,y0) offset
    st=cur()
    x0,y0=box
    w,h=mask_img.size
    cx0,cy0,cx1,cy1=0,0,img.width,img.height
    if st.clip: cx0,cy0,cx1,cy1=[int(v) for v in st.clip]
    ix0,iy0=max(x0,cx0,0),max(y0,cy0,0)
    ix1,iy1=min(x0+w,cx1,img.width),min(y0+h,cy1,img.height)
    if ix1<=ix0 or iy1<=iy0: return
    m=np.asarray(mask_img,dtype=np.float32)[iy0-y0:iy1-y0,ix0-x0:ix1-x0]/255.0
    if isinstance(color_arr_or_rgba,tuple):
        col=np.zeros((iy1-iy0,ix1-ix0,4),dtype=np.float32); col[...]=color_arr_or_rgba
    else:
        col=color_arr_or_rgba[iy0-y0:iy1-y0,ix0-x0:ix1-x0]
    a=(col[...,3]/255.0)*m*alpha
    dst=np.asarray(img.crop((ix0,iy0,ix1,iy1)),dtype=np.float32)
    out=dst.copy()
    for ch in range(3):
        out[...,ch]=dst[...,ch]*(1-a)+col[...,ch]*a
    out[...,3]=255
    img.paste(Image.fromarray(out.astype(np.uint8),'RGBA'),(ix0,iy0))

def polys_bbox(polys,pad=2):
    xs=[p[0] for poly in polys for p in poly]; ys=[p[1] for poly in polys for p in poly]
    return int(min(xs))-pad,int(min(ys))-pad,int(max(xs))+pad+1,int(max(ys))+pad+1

def do_fill():
    st=cur()
    polys=[p for p,c in paths if len(p)>=3]
    if not polys: return
    x0,y0,x1,y1=polys_bbox(polys)
    w,h=x1-x0,y1-y0
    if w<=0 or h<=0 or w>4000 or h>4000: return
    big=Image.new('L',(w,h),0); d=ImageDraw.Draw(big)
    for poly in polys: d.polygon([(px-x0,py-y0) for px,py in poly],fill=255)
    col=colorfor(x0,y0,w,h)
    composite(big,(x0,y0),col,st.alpha)

def colorfor(x0,y0,w,h):
    st=cur()
    p=st.fillpaint
    if p is None: return st.fill
    _,m,gx1,gy1,gx2,gy2,c1,c2=p
    # gradient points were given in local coords at creation time with matrix m
    def T(x,y):
        a,b,c,d,e,f=m
        return ((a*x+c*y+e)*S,(b*x+d*y+f)*S)
    X1,Y1=T(gx1,gy1); X2,Y2=T(gx2,gy2)
    xs=np.arange(x0,x0+w)[None,:]+0.5; ys=np.arange(y0,y0+h)[:,None]+0.5
    dx,dy=X2-X1,Y2-Y1
    den=dx*dx+dy*dy
    t=np.clip(((xs-X1)*dx+(ys-Y1)*dy)/(den if den else 1),0,1)
    c1=np.array(c1,dtype=np.float32); c2=np.array(c2,dtype=np.float32)
    arr=c1[None,None,:]*(1-t[...,None])+c2[None,None,:]*t[...,None]
    return arr

def do_stroke():
    st=cur()
    if not paths: return
    polys=[(p,c) for p,c in paths if len(p)>=2]
    if not polys: return
    x0,y0,x1,y1=polys_bbox([p for p,c in polys],pad=int(st.sw*S)+3)
    w,h=x1-x0,y1-y0
    if w<=0 or h<=0 or w>4000 or h>4000: return
    big=Image.new('L',(w,h),0); d=ImageDraw.Draw(big)
    for p,c in polys:
        pts=[(px-x0,py-y0) for px,py in p]
        if c: pts.append(pts[0])
        d.line(pts,fill=255,width=max(1,int(round(st.sw*S))),joint='curve')
    composite(big,(x0,y0),st.stroke,st.alpha)

def roundrect(x,y,w,h,r):
    r=max(0,min(r,w/2,h/2))
    if r<=0.01:
        return [tx(x,y),tx(x+w,y),tx(x+w,y+h),tx(x,y+h)]
    pts=[]
    for cx,cy,a0 in ((x+w-r,y+r,-90),(x+w-r,y+h-r,0),(x+r,y+h-r,90),(x+r,y+r,180)):
        for i in range(7):
            a=math.radians(a0+90*i/6)
            pts.append(tx(cx+r*math.cos(a),cy+r*math.sin(a)))
    return pts

def R(name,*a):
    global sub,paths
    st=cur()
    if name=='nvgSave': stack.append(clone(st)); return
    if name=='nvgRestore':
        if len(stack)>1: stack.pop()
        return
    if name=='nvgTranslate': st.m=mmul(st.m,[1,0,0,1,a[1],a[2]]); return
    if name=='nvgScale': st.m=mmul(st.m,[a[1],0,0,a[2],0,0]); return
    if name=='nvgRotate':
        c,s=math.cos(a[1]),math.sin(a[1]); st.m=mmul(st.m,[c,s,-s,c,0,0]); return
    if name=='nvgGlobalAlpha': st.alpha=a[1]; return
    if name=='nvgIntersectScissor':
        x,y,w,h=a[1:5]
        p1=tx(x,y);p2=tx(x+w,y+h)
        nc=[min(p1[0],p2[0]),min(p1[1],p2[1]),max(p1[0],p2[0]),max(p1[1],p2[1])]
        if st.clip:
            c=st.clip; nc=[max(c[0],nc[0]),max(c[1],nc[1]),min(c[2],nc[2]),min(c[3],nc[3])]
        st.clip=nc; return
    if name=='nvgRGBA': return ('c',a[0],a[1],a[2],a[3])
    if name=='nvgFillColor': st.fill=colr(a[1][1:]); st.fillpaint=None; return
    if name=='nvgStrokeColor': st.stroke=colr(a[1][1:]); return
    if name=='nvgStrokeWidth': st.sw=a[1]; return
    if name=='nvgLinearGradient':
        return ('grad',list(st.m),a[1],a[2],a[3],a[4],colr(a[5][1:]),colr(a[6][1:]))
    if name=='nvgFillPaint':
        p=a[1]
        st.fillpaint=('grad',)+tuple(p[1:]) if p[0]=='grad' else None; return
    if name=='nvgBeginPath': paths=[]; sub=None; return
    if name=='nvgMoveTo':
        sub=[tx(a[1],a[2])]; paths.append([sub,False]); return
    if name=='nvgLineTo':
        if sub is None: sub=[tx(a[1],a[2])]; paths.append([sub,False])
        else: sub.append(tx(a[1],a[2]))
        return
    if name=='nvgClosePath':
        if paths: paths[-1][1]=True
        return
    if name=='nvgRect':
        x,y,w,h=a[1:5]; paths.append([[tx(x,y),tx(x+w,y),tx(x+w,y+h),tx(x,y+h)],True]); sub=None; return
    if name=='nvgRoundedRect':
        paths.append([roundrect(*a[1:6]),True]); sub=None; return
    if name=='nvgCircle':
        cx,cy,r=a[1:4]; paths.append([[tx(cx+r*math.cos(t*math.pi/12),cy+r*math.sin(t*math.pi/12)) for t in range(24)],True]); sub=None; return
    if name=='nvgArc':
        cx,cy,r,a0,a1=a[1:6]
        n=16; pts=[tx(cx+r*math.cos(a0+(a1-a0)*i/n),cy+r*math.sin(a0+(a1-a0)*i/n)) for i in range(n+1)]
        sub=pts; paths.append([pts,False]); return
    if name=='nvgEllipse':
        cx,cy,rx,ry=a[1:5]
        paths.append([[tx(cx+rx*math.cos(k*math.pi/20),cy+ry*math.sin(k*math.pi/20)) for k in range(40)],True]); sub=None; return
    if name=='nvgFill': do_fill_wrapped(); return
    if name=='nvgStroke': do_stroke(); return
    if name=='nvgCreateFont':
        FACEFILES[len(FACEFILES)+1]=('assets/'+a[2]); return len(FACEFILES)
    if name=='nvgFontFaceId': st.face=a[1]; return
    if name=='nvgTextLetterSpacing': st.spacing=a[1]; return
    if name=='nvgFontSize': st.fs=a[1]; return
    if name=='nvgTextAlign': st.align=int(a[1]); return
    if name=='nvgText':
        x,y,text=a[1],a[2],a[3]
        px,py=tx(x,y)
        h=st.align&7
        anchor={1:'lm',2:'mm',4:'rm'}.get(h,'lm')
        sc=st.m[0]
        fnt=font(st.fs*sc,st.face)
        big=Image.new('L',(img.width,img.height),0)
        d=ImageDraw.Draw(big)
        if st.spacing:
            total=sum(fnt.getlength(c)+st.spacing*S for c in text)
            x0=px-(total if h==4 else (total/2 if h==2 else 0))
            for c in text:
                d.text((x0,py),c,font=fnt,fill=255,anchor='lm'); x0+=fnt.getlength(c)+st.spacing*S
        else:
            d.text((px,py),text,font=fnt,fill=255,anchor=anchor)
        bb=big.getbbox()
        if bb:
            cropped=big.crop(bb)
            composite(cropped,(bb[0],bb[1]),st.fill,st.alpha)
        return
    if name=='image':
        nm,x,y=a
        if nm not in imgcache:
            try: imgcache[nm]=Image.open(f'{ROOT}/assets/ui/touch/{nm}.png').convert('RGBA')
            except Exception: imgcache[nm]=None
        im=imgcache[nm]
        if im is None: return
        sc=st.m[0]*2*S
        im2=im.resize((int(im.width*sc),int(im.height*sc)),Image.NEAREST)
        px,py=tx(x,y)
        alpha=im2.getchannel('A')
        composite(alpha,(int(px),int(py)),(255,255,255,255),st.alpha) if False else paste_img(im2,int(px),int(py))
        return
    return None

def paste_img(im2,x,y):
    st=cur()
    arr=np.asarray(im2,dtype=np.float32)
    mask=Image.fromarray(arr[...,3].astype(np.uint8),'L')
    composite(mask,(x,y),arr,st.alpha)

def clone(st):
    n=St(); n.__dict__.update(st.__dict__); n.m=list(st.m); return n

def do_fill_wrapped():
    do_fill()

lua=LuaRuntime(unpack_returned_tuples=False)
lua.globals().R=R
head=open(f'{ROOT}/tests/combat/weapon_forge.lua').read()
head=head[:head.index("assert(not Forge.Open(),'missing safety")]
names=['nvgSave','nvgRestore','nvgTranslate','nvgScale','nvgRotate','nvgIntersectScissor','nvgBeginPath','nvgRoundedRect','nvgFillColor','nvgFillPaint','nvgStrokeColor','nvgStrokeWidth','nvgStroke','nvgCircle','nvgMoveTo','nvgLineTo','nvgClosePath','nvgFontSize','nvgTextAlign','nvgText','nvgGlobalAlpha','nvgRect','nvgFill','nvgRGBA','nvgLinearGradient','nvgArc','nvgEllipse','nvgCreateFont','nvgFontFaceId','nvgTextLetterSpacing']
override='\n'.join(f"rawset(_G,'{n}',function(...) return R('{n}',...) end)" for n in names)
override+="\nfor _,n in ipairs({'nvgFontBlur','nvgShapeAntiAlias'}) do rawset(_G,n,function() end) end\n"
body=f'''
{override}
width,height,dpr,scale={W},{H},1,1
safe={{left=0,right=0,top=0,bottom=0}}
if {W}==844 then safe={{left=47,right=47,top=0,bottom=21}} end
Draw.Image=function(_,name,x,y) R('image',name,x,y) end
room.enterOK={'true' if MODE=='room' else 'false'}
local s=OpenReady()
{SCRIPT}
Tick(1)
s.layer:Render('vg')
'''
lua.execute(head+body)
img.convert('RGB').save(OUT)
print('saved',OUT)
