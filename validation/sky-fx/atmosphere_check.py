from pathlib import Path
from lupa.lua54 import LuaRuntime
import runpy, numpy as np, json
ROOT=Path(__file__).resolve().parents[2]
prefix=(ROOT/'validation/sky-fx/check.lua').read_text().split('local settings=require',1)[0]
LuaRuntime(unpack_returned_tuples=True).execute(prefix+(ROOT/'validation/sky-fx/atmosphere_contract.lua').read_text())
r=runpy.run_path(str(ROOT/'validation/sky-fx/skycards_check.py'))
period=10000*np.pi
uv=np.stack(np.meshgrid(np.linspace(.001,.999,160),np.linspace(.001,.999,80)),axis=-1).reshape(-1,2)
for detail in (0,.5,1):
 for t in (0,120,300,1800,period-1e-5,period):
  out=r['warp'](uv,np.full_like(uv,.005),t,detail)
  assert np.isfinite(out).all() and np.array_equal(np.floor(uv*[4,2]),np.floor(out*[4,2]))
  assert np.max(np.abs(out-uv))<=.0015+1e-10
  if detail==0 or t==0:assert np.allclose(out,uv)
 assert np.allclose(r['warp'](uv,np.full_like(uv,.005),period,detail),uv,atol=1e-10)
 assert np.allclose(r['warp'](uv,np.full_like(uv,.03),300,detail),uv)
for speed in (.25,.45,.65):
 assert abs(r['wind'](period,speed))<1e-12
 assert abs(r['wind'](300,speed))>.05
shader=(ROOT/'assets/Shaders/BLGL/RuinsCloud.shader').read_text()
fire=(ROOT/'assets/Shaders/BLGL/RuinsPillarFlame.shader').read_text()
shaft=(ROOT/'assets/Shaders/BLGL/RuinsLightShaft.shader').read_text()
for s in (shader,fire,shaft):
 assert 'hint_depth_texture' not in s and 'SCREEN_UV' not in s and 'POSITION=' not in s
 assert 'depth_draw_never' in s and 'blend_mix' in s
assert shader.count('texture(')==1 and fire.count('texture(')==shaft.count('texture(')==0
print('PASS wrap-continuous world wind; low/far UV stable; all tiles remain inside gutter; 1/0/0 texture reads; no screen/depth coupling')
