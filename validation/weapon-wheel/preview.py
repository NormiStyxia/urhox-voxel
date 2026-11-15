"""Record production WeaponWheel.Draw as SVG; not an engine/Web screenshot."""
from pathlib import Path
from math import cos, sin, pi
import copy
from lupa.lua54 import LuaRuntime
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]

class Recorder:
    def __init__(self):
        self.elements, self.path, self.stack = [], [], []
        self.state = dict(transform='', alpha=1, fill=(0,0,0,255), stroke=(255,255,255,255), width=1)
    def save(self, *_): self.stack.append(copy.copy(self.state))
    def restore(self, *_): self.state = self.stack.pop()
    def translate(self, _, x, y): self.state['transform'] += f' translate({x},{y})'
    def scale(self, _, x, y): self.state['transform'] += f' scale({x},{y})'
    def begin(self, *_): self.path=[]
    def move(self, _, x, y): self.path.append(f'M{x},{y}')
    def line(self, _, x, y): self.path.append(f'L{x},{y}')
    def quad(self, _, a,b,c,d): self.path.append(f'Q{a},{b} {c},{d}')
    def bezier(self, _, a,b,c,d,e,f): self.path.append(f'C{a},{b} {c},{d} {e},{f}')
    def close(self, *_): self.path.append('Z')
    def arc(self, _, x,y,r,a,b,direction):
        delta=b-a
        if direction==1:
            while delta<0: delta+=2*pi
        else:
            while delta>0: delta-=2*pi
        sx,sy=x+r*cos(a),y+r*sin(a)
        self.path.append(('L' if self.path else 'M')+f'{sx},{sy}')
        self.path.append(f'A{r},{r} 0 {int(abs(delta)>pi)},{int(direction==1)} {x+r*cos(b)},{y+r*sin(b)}')
    def circle(self, _, x,y,r):
        self.path.append(f'M{x-r},{y} A{r},{r} 0 1,0 {x+r},{y} A{r},{r} 0 1,0 {x-r},{y} Z')
    def color(self, key, value): self.state[key]=value
    def paint(self, fill):
        s=self.state;c=s['fill' if fill else 'stroke'];color=f'rgb({c[0]},{c[1]},{c[2]})'
        attrs=f'fill="{color if fill else "none"}" stroke="{color if not fill else "none"}" stroke-width="{s["width"]}"'
        path=' '.join(self.path)
        self.elements.append(f'<path d="{path}" {attrs} opacity="{s["alpha"]*c[3]/255}" transform="{s["transform"]}"/>')

def render(width,height,filename):
    lua=LuaRuntime(unpack_returned_tuples=True);g=lua.globals();r=Recorder()
    lua.execute("package.path='scripts/?.lua;'..package.path; package.loaded['urhox-libs/UI']={Panel={Extend=function() return {} end}}; package.loaded['ui.PixelDraw']={}; package.loaded['urhox-libs/UI/Core/ImageCache']={}")
    for key,method in [('nvgSave','save'),('nvgRestore','restore'),('nvgTranslate','translate'),('nvgScale','scale'),('nvgBeginPath','begin'),('nvgMoveTo','move'),('nvgLineTo','line'),('nvgQuadTo','quad'),('nvgBezierTo','bezier'),('nvgClosePath','close'),('nvgArc','arc'),('nvgCircle','circle')]: g[key]=getattr(r,method)
    g.nvgShapeAntiAlias=lambda *_:None
    g.nvgRGBA=lambda *c:list(c)
    g.nvgGlobalAlpha=lambda _,a:r.color('alpha',a)
    g.nvgFillColor=lambda _,c:r.color('fill',c)
    g.nvgStrokeColor=lambda _,c:r.color('stroke',c)
    g.nvgStrokeWidth=lambda _,w:r.color('width',w)
    g.nvgFill=lambda _:r.paint(True)
    g.nvgStroke=lambda _:r.paint(False)
    g.NVG_CW,g.NVG_CCW=1,2
    wheel=lua.eval("require('ui.WeaponWheel')")[0]
    layout=wheel.Layout(width,height,.51,.55,True,2,lua.table_from(dict(left=0,right=0,top=0,bottom=0)))
    wheel.Draw('recording',layout,2,None,1)
    side=max(width,height)
    svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{side}" height="{side}" viewBox="0 0 {side} {side}"><rect width="{width}" height="{height}" fill="#4e6475"/>'+''.join(r.elements)+'</svg>'
    target=ROOT/'validation/weapon-wheel'/filename
    target.with_suffix('.svg').write_text(svg)
    subprocess.run(['qlmanage','-t','-s',str(max(width,height)*2),'-o',str(target.parent),str(target.with_suffix('.svg'))],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    target.with_suffix('.svg.png').replace(target)
    # Labels use production Layout positions; raster font is an offline substitute.
    image=Image.open(target).convert('RGB')
    ratio=image.width/side
    image=image.crop((0,0,round(width*ratio),round(height*ratio))).resize((width*2,height*2),Image.Resampling.LANCZOS)
    draw=ImageDraw.Draw(image)
    def text(x,y,value,size,color,anchor='la'):
        font=ImageFont.truetype('/System/Library/Fonts/STHeiti Light.ttc',max(8,round(size*2)))
        draw.text((round(x*2),round(y*2)),value,font=font,fill=color,anchor=anchor)
    k=layout.size
    for i,name in enumerate(('长剑','长弓'),1):
        slot=layout.slots[i];text(slot.x,slot.y+18*k,name,14*k,'#e5b460' if i==2 else '#f0ebdc','ma')
    text(layout.cx-22*k,layout.cy+layout.outer*.53,'02 / RANGED',10*k,'#97a9b7')
    text(layout.cx-22*k,layout.cy+layout.outer*.53+19*k,'点击选择 · 空白处取消',12*k,'#f0ebdc')
    text(12,12,'界面几何预览 · 非引擎截图',11,'#ffffff')
    image.save(target)
    print(target)

if __name__=='__main__':
    import os
    os.chdir(ROOT)
    render(844,390,'arc-landscape.png')
    render(320,430,'arc-portrait.png')
