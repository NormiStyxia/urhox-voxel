from pathlib import Path
import re,math,json,subprocess
p=Path('validation/island-void/visual-r2');old=(p/'RuinsGround.shader').read_text();new=Path('assets/Shaders/BLGL/RuinsGround.shader').read_text()
strip=lambda s:re.sub(r'//[^\n]*','',s)
for name in ['texture','textureLod','surfaceNoise','fbm','vnoise','rockCell','dFdx','dFdy','pow']:
 assert len(re.findall(r'\b'+name+r'\s*\(',strip(old)))==len(re.findall(r'\b'+name+r'\s*\(',strip(new))),name+' added sampling/expensive call'
print('PASS source call budget: texture/noise/Voronoi/derivative/pow counts unchanged')
assert new[new.index('    // 草地被 GrassField'):]==old[old.index('    // 草地被 GrassField'):]
a=old.index('void fragment()');b=old.index('    // ---- 岩壁')
assert new[new.index('void fragment()'):new.index('    // ---- 岩壁')]==old[a:b]
assert new[new.index('        float rockFade'):new.index('        // 复用已有低频场')]==old[old.index('        float rockFade'):old.index('        rock = mix(rock, deep_color')]
print('PASS top/grass/path/soil shader logic, distance fades, derivatives, snow/frost/daynight PBR outputs preserved')
base=(p/'RuinsTerrain.lua').read_text();cur=Path('scripts/ruins/RuinsTerrain.lua').read_text()
a='local function BuildIslandMesh';b='---@param scene Scene\nlocal function BuildVisual'
assert base.split(a)[0]==cur.split(a)[0]
assert base.split(b)[1]==cur.split(b)[1]
print('PASS terrain domain/top/bottom/collision/safety/grass/material interfaces byte-identical; only BuildIslandMesh changed')
for f in ['scripts/ruins/DayNight.lua','scripts/ruins/RuinsScene.lua','scripts/ruins/RuinsPuzzles.lua','scripts/ruins/NomiController.lua','scripts/ruins/RuinsBuild.lua','scripts/ruins/RuinsDragon.lua']:
 prior=subprocess.check_output(['git','show','736120c:'+f]);assert prior==Path(f).read_bytes(),f
print('PASS DayNight, bridge/puzzles, Scene/input, controller/safety, buildings and dragon unchanged')
def frac(x):return x-math.floor(x)
def hash2(x,z):
 a,b,c=frac(x*.1031),frac(z*.1031),frac(x*.1031)
 d=a*(b+33.33)+b*(c+33.33)+c*(a+33.33)
 a+=d;b+=d;c+=d
 return frac((a+b)*c)
def smooth(a,b,x):
 t=max(0,min(1,(x-a)/(b-a)));return t*t*(3-2*t)
def noise(x,z):
 i,j=math.floor(x),math.floor(z);u=smooth(0,1,x-i);v=smooth(0,1,z-j)
 return (hash2(i,j)*(1-u)+hash2(i+1,j)*u)*(1-v)+(hash2(i,j+1)*(1-u)+hash2(i+1,j+1)*u)*v
def fbm(x,z):
 s=0;w=.5
 for _ in range(4):s+=noise(x,z)*w;x=x*2.03+17.1;z=z*2.03+5.3;w*=.5
 return s
values=[];shift=[]
for j in range(720):
 a=j*math.pi/360;x,z=70*math.cos(a),70*math.sin(a);y=-12
 big=fbm(x*.045,z*.045);warp=fbm(x*.05+y*.03,z*.05+y*.03)*6
 offset=(big-.47)*10+(warp-2.8)*.45
 shift.append(offset);values.append((1-smooth(-17,-6,y+offset))*.5)
assert max(values)-min(values)>.15
assert all(0<=v<=.5 for v in values)
print('PASS CPU formula sample (not shader compilation): y=-12 mixing range',min(values),max(values),'height offset',min(shift),max(shift))
print('UNVERIFIED: real SurfaceShader compile, PBR/shadow appearance and Web GPU cost; requires official Web build')
