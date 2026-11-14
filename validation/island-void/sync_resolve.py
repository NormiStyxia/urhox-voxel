from pathlib import Path
import json,re,subprocess
m=json.loads(Path('validation/island-void/sync-manifest.json').read_text());w=Path(m['worktree']);b=Path(m['backup'])
pattern=r'^<<<<<<< .*?\n(.*?)^=======\n(.*?)^>>>>>>> .*?\n'
def resolve(f,choose):
 p=w/f;s=p.read_text();n=0
 def repl(match):
  nonlocal n
  n+=1;return choose(n,match[1],match[2])
 s=re.sub(pattern,repl,s,flags=re.M|re.S);assert n>0
 p.write_text(s)
resolve('scripts/ruins/NomiController.lua',lambda n,local,remote:local+remote)
resolve('scripts/ruins/RuinsPuzzles.lua',lambda n,local,remote:remote) # remote full fine bridge, no old gold overlay
# Terrain: new domain + latest stairs, not a side-wide choice.
def terrain(n,local,remote):
 if n==1:return local+'-- 石阶/台缘沿用最新单体积方案：隐藏地形退到 -1，视觉 -1.2。\n'
 if n==2:return '-- 未裁剪的顶面延拓；先判新台阶，防止龙庭圆弧覆盖底踏步。\nlocal function SurfaceHeight(x,z)\n    if M.InStair(x,z) then return M.StairY(z) end\n    local r=sqrt(x*x+z*z)\n    if r<M.COURT_R then return 0 end\n'
 if n==3:return local+remote # void guard, then remote hidden stair footprint
 if n==4:return remote.replace('return M.Height(x, z)','return SurfaceHeight(x, z)')
 raise AssertionError(n)
resolve('scripts/ruins/RuinsTerrain.lua',terrain)
# Safety must exclude the complete new stair/foundation footprint, not just its aisle.
p=w/'scripts/ruins/RuinsTerrain.lua';s=p.read_text().replace('or M.InStair(x,z) then return false end','or M.InStairFootprint(x,z) then return false end');p.write_text(s)
with Path('validation/island-void/sync-resolve.log').open('w') as log:
 for f in m['files']:
  data=(w/f).read_text();assert not re.search(r'^(<<<<<<<|=======|>>>>>>>)',data,re.M),f
  r=subprocess.run(['git','diff','--',f],cwd=w,capture_output=True,check=True)
  log.write(r.stdout.decode())
print('sync_resolve.py / PASS / '+str(Path('validation/island-void/sync-resolve.log').resolve()))
