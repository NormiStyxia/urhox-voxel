"""Regression check for the colour-only polish (polish.py).

polish_baseline.json is the order-independent unit-cell description of the mesh at
145d608, which passed the earlier checks (approved head geometry, 544 protected face
triangles, restored clothing/limbs, accepted hanging hair, original 16 bones).
Undoing every edit in polish_edits.json must give exactly that baseline, so geometry
and every unlisted colour are proven unchanged.
"""
import hashlib
import json
from collections import Counter
from pathlib import Path
from review_mesh import read_lua
from polish import canonical

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
q, p, t, b = read_lua(ROOT / 'scripts/game/NomiVoxelData.lua')
base = json.loads((HERE / 'polish_baseline.json').read_text())
edits = json.loads((HERE / 'polish_edits.json').read_text())['edits']


def exported(rgb):
    """RGB as it comes back from the Lua file (exporter writes %.3f of rgb/255)."""
    return [round(float('%.3f' % (min(max(x, 0), 255) / 255.0)) * 255, 3) for x in rgb]


cells, ts = canonical(q, t, p)
cells, ts = [list(c) for c in cells], [list(r) for r in ts]
cell_at = {tuple(c[:5]): c for c in cells}
tri_at = {}
counts = Counter()
for row in ts:
    tri_at[(row[0], counts[row[0]])] = row
    counts[row[0]] += 1

for e in reversed(edits):
    k = tuple(e['key'])
    row = cell_at.get(k) if e['kind'] == 'q' else tri_at.get(k)
    assert row is not None, f'edit points at missing geometry: {k}'
    assert row[-1] == exported(e['after']), f'edit result differs from the file: {k}'
    row[-1] = exported(e['before'])

digest = lambda x: hashlib.sha256(json.dumps(x, separators=(',', ':')).encode()).hexdigest()
cells = sorted(cells)
assert len(cells) == base['unit_cells'] and len(ts) == base['tris'], 'geometry count changed'
assert digest(cells) == base['cells_sha256'], 'unit cells differ from the pre-polish baseline after undo'
assert digest(ts) == base['tris_sha256'], 'triangles differ from the pre-polish baseline after undo'
assert json.loads(json.dumps(b)) == base['bones'], 'bone structure changed'

report = {'pre_polish_mesh_restored_by_undo': True, 'unit_cells': len(cells), 'tris': len(ts),
          'polish_edits': dict(Counter(e['rule'] for e in edits)), 'bones': len(b), 'palette_entries': len(p)}
print(json.dumps(report, indent=2))
out = ROOT / '.tmp/nomi-review'
out.mkdir(parents=True, exist_ok=True)
(out / 'checks.json').write_text(json.dumps(report, indent=2))
