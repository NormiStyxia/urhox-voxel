#!/usr/bin/env python3
"""诺米 vs 龙娘 比例实测对照（按骨骼组汇总方块包围盒，不含方块自身旋转）。输出 proportions.md"""
import json, sys
from pathlib import Path
D = Path(__file__).resolve().parent
NOMI = Path.home() / 'Downloads/诺米/诺米.bbmodel'
PARTS = {  # 部位: (诺米组名, 龙娘组名)
    '整体(含头饰)': (['Root'], ['Root']),
    '脸': (['Face'], ['Face']),
    '头发全体': (['Hair'], ['Hair']),
    '躯干': (['FittedTop'], ['FittedTop']),
    '颈': (None, None),
    '单臂(含前臂手)': (['LeftArm'], ['LeftArm']),
    '单腿(含脚)': (['LeftLeg'], ['LeftLeg']),
    '裙': (['Skirt', 'NomiUniformBell'], ['Skirt']),
}

def boxes(path, names):
    d = json.load(open(path)); G = {g['uuid']: g for g in d['groups']}; E = {e['uuid']: e for e in d['elements']}
    out = []
    def walk(n, inside):
        if isinstance(n, dict):
            ins = inside or G[n['uuid']]['name'] in names
            for c in n['children']: walk(c, ins)
        elif inside:
            e = E[n]; out.append((e['from'], e['to']))
    for g in d['outliner']: walk(g, False)
    return out

def bb(bx):
    if not bx: return None
    return [(min(a[k] for a, b in bx), max(b[k] for a, b in bx)) for k in range(3)]

def fmt(b):
    if not b: return '—'
    w, h, dp = (b[0][1]-b[0][0]), (b[1][1]-b[1][0]), (b[2][1]-b[2][0])
    return f'宽{w:.1f} 高{h:.1f} 深{dp:.1f} | y {b[1][0]:.1f}–{b[1][1]:.1f}'

lines = ['| 部位 | 诺米 | 龙娘 |', '|---|---|---|']
nomi_p, long_p = NOMI, D / 'longnu.bbmodel'
for k, (nn, ln) in PARTS.items():
    if nn is None:
        lines.append(f'| {k} | 宽2.0 高2.2 深2.0 | 宽2.0 高2.2 深2.0 |'); continue
    lines.append(f'| {k} | {fmt(bb(boxes(nomi_p, set(nn))))} | {fmt(bb(boxes(long_p, set(ln))))} |')
(D / 'proportions.md').write_text('\n'.join(lines), encoding='utf-8')
print('\n'.join(lines))
