"""P0 rollback contract. Verifies source equivalence, NOT GPU visibility."""
from pathlib import Path
import hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
path=ROOT/'assets/Shaders/BLGL/RuinsCloud.shader'
now=path.read_text();before=(HERE/'before.shader.txt').read_text();old=(HERE/'reference-1a78a3d.shader.txt').read_text()
fragment=lambda s:s.split('void fragment() {',1)[1]
vertex=lambda s:s.split('void vertex() {',1)[1].split('void fragment()',1)[0]
assert fragment(now)==fragment(old),'fragment must exactly match 1a78a3d'
assert vertex(now)==vertex(before),'world-space drift path must remain byte-identical'
assert now.count('texture(')==1
for token in ('fwidth','billow','motion_detail','scene_depth','SCREEN_UV'):
 assert token not in fragment(now),token
assert 'world_vertex_coords' in now and 'skip_vertex_transform' not in now
assert 'if (cloud_enabled<0.5) { discard; }' in now
assert 'if (data.a<0.003) { discard; }' in now
for name,digest in json.loads((HERE/'protected-hashes.json').read_text()).items():
 assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,name
lua=(ROOT/'scripts/ruins/SkyClouds.lua').read_text()
assert 'GetResourceAsync("Texture2D",path' in lua and 'if self.disposed or not self.loading then return end' in lua
assert 'SetShaderParameter("cloud_enabled",Variant(1))' in lua
(HERE/'after.shader.txt').write_text(now)
hashes={label:dict(md5=hashlib.md5(s.encode()).hexdigest(),sha256=hashlib.sha256(s.encode()).hexdigest()) for label,s in [('before',before),('after',now),('reference-1a78a3d',old)]}
(HERE/'shader-hashes.json').write_text(json.dumps(hashes,indent=2))
print('PASS fragment byte-identical to 1a78a3d; vertex byte-identical to current release; single texture read, no derivative/UV branch')
print('PASS protected Lua/material/atlas/fire/fog hashes unchanged; cold async load, disposed guard and cloud_enabled preserved')
print(json.dumps(hashes,indent=2))
print('UNVERIFIED: new Web shader compilation, clouds visible, GPU root cause; offline equivalence is not a rendering test')
