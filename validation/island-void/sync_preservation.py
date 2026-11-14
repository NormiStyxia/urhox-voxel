from pathlib import Path
import json,sys
m=json.loads(Path('validation/island-void/sync-manifest.json').read_text());w=Path(sys.argv[1] if len(sys.argv)>1 else m['worktree']);b=Path(m['backup'])/'remote'
def same(f,start,end=None):
 a=(w/f).read_text();r=(b/f).read_text()
 def part(s):
  i=s.index(start);j=s.index(end,i) if end else len(s)
  return s[i:j]
 assert part(a)==part(r),f+' '+start
 print('UNCHANGED remote section:',f,start)
same('scripts/ruins/RuinsPuzzles.lua','local BRIDGE_D','local function BuildBridge')
same('scripts/ruins/RuinsBuild.lua','local function BuildStairs','-- ---------------------------------------------------------------- 外城墙')
same('scripts/ruins/NomiController.lua','-- 右手掌心位置','-- 鼠标视角')
same('scripts/ruins/NomiController.lua','function N:Animate')
same('scripts/ruins/RuinsScene.lua','function Ruins_HandlePostUpdate','function M.Stop')
s=(w/'scripts/ruins/NomiController.lua').read_text()
assert 'cc.enhancedInternalEdgeRemoval = true' in s and 'aimPitch = self.camPitch' in s
s=(w/'scripts/ruins/RuinsScene.lua').read_text()
for token in ['M.START_HOUR = 12.0','M.surfaceMaterials.gateRubble = Puzzles.gateMaterial','Spells.NewFX(scene_, nomi_:CameraNode())','prepareCast = function(aim) nomi_:PrepareCast(aim) end']:
 assert token in s,token
print('PASS remote palm/precise aim/stair geometry/fine bridge/noon/casting wiring preservation')
