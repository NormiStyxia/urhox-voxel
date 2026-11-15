"""Offline gates only; never invokes Maker build or a game Runtime."""
from pathlib import Path
import subprocess,sys,json,hashlib
ROOT=Path(__file__).resolve().parents[2]
cases={
 'contract':'validation/sky-fx/atmosphere_check.py',
 'lua':'validation/sky-fx/check.py',
 'dwp':'validation/sky-fx/missing_dwp_check.py',
 'rotation':'validation/sky-fx/rotation_check.py',
 'detail':'validation/sky-fx/detail_check.py',
 'settings-integration':'validation/settings/sky_integration.py',
 'settings-quality':'validation/settings/quality_check.py',
 'settings':'validation/settings/check.py',
 'lsp':'validation/sky-fx/lsp_check.py',
}
failed=False
for name,script in cases.items():
 p=ROOT/f'validation/sky-fx/atmosphere-{name}.log'
 with p.open('w') as f:result=subprocess.run([sys.executable,script],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 print(script,'—','FAIL' if result.returncode else 'PASS','—',p.relative_to(ROOT))
 failed|=bool(result.returncode)
runtime=['scripts/ruins/SkyClouds.lua','scripts/ruins/SkyAtmosphere.lua','scripts/ruins/NightBraziers.lua','scripts/ruins/GameSettings.lua','scripts/ruins/RuinsScene.lua',
 'assets/Shaders/BLGL/RuinsCloud.shader','assets/Shaders/BLGL/RuinsLightShaft.shader','assets/Shaders/BLGL/RuinsPillarFlame.shader','assets/Materials/RuinsPillarFlame.xml']
unchanged=['assets/Textures/Sky/cloud_sculpted_atlas.png','assets/Textures/Sky/cloud_sculpted_atlas_low.png','assets/Materials/RuinsCloud.xml','assets/Materials/RuinsLightShaft.xml']
hashes={}
for name in runtime+unchanged:
 for p in (ROOT/name,ROOT/(name+'.meta')):
  assert p.exists(),p
  data=p.read_bytes();hashes[str(p.relative_to(ROOT))]=dict(bytes=len(data),md5=hashlib.md5(data).hexdigest(),sha256=hashlib.sha256(data).hexdigest())
(ROOT/'validation/sky-fx/atmosphere-candidate-hashes.json').write_text(json.dumps(hashes,indent=2))
print('Runtime resources + existing meta — PASS — validation/sky-fx/atmosphere-candidate-hashes.json')
raise SystemExit(int(failed))
