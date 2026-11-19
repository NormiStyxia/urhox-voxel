#!/usr/bin/env python3
"""Inline wingsword.json (compact) into template.html -> weapon-codex.html (self-contained)."""
import json, sys, pathlib
here = pathlib.Path(__file__).resolve().parent
root = here.parent.parent
d = json.load(open(root / 'art/weapon_gen/out/wingsword.json'))
parts = ['blade', 'wings', 'grip', 'guard_core', 'collar', 'pommel']
r = lambda v: round(v, 4)
rows = []
for t in d['tris']:
    p = t['p']
    rows.append([r(p[0][0]), r(p[0][1]), r(p[0][2]), r(p[1][0]), r(p[1][1]), r(p[1][2]),
                 r(p[2][0]), r(p[2][1]), r(p[2][2]), t['c'][0], t['c'][1], t['c'][2],
                 t['shade'], t['glow'], parts.index(t['part'])])
data = json.dumps({'parts': parts, 'tris': rows}, separators=(',', ':'))
tpl = (here / 'template.html').read_text(encoding='utf-8')

# ---- fonts: download (OFL) once, subset to the characters used in the page, inline as woff2
import subprocess, base64, io, re
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
FD = pathlib.Path('/tmp/fontdl'); FD.mkdir(exist_ok=True)
SRC = {
 'title': ('zcool.ttf', 'https://raw.githubusercontent.com/google/fonts/main/ofl/zcoolqingkehuangyou/ZCOOLQingKeHuangYou-Regular.ttf'),
 'body': ('noto.ttf', 'https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf'),
}
for k, (fn, url) in SRC.items():
    if not (FD / fn).exists():
        subprocess.run(['curl', '-sSL', '-m', '120', '-o', str(FD / fn), url], check=True)
chars = set(c for c in tpl if ord(c) > 127) | set(chr(i) for i in range(32, 127)) | set('·—…“”‘’、。，：；！？（）【】《》◆◇★☆✕')
def make(key, weight=None):
    f = TTFont(str(FD / SRC[key][0]))
    if weight is not None:
        f = instancer.instantiateVariableFont(f, {'wght': weight})
    opt = subset.Options(); opt.flavor = 'woff2'; opt.layout_features = ['kern', 'liga']; opt.name_IDs = [1, 2]; opt.notdef_outline = True
    sb = subset.Subsetter(opt); sb.populate(text=''.join(sorted(chars))); sb.subset(f)
    buf = io.BytesIO(); f.flavor = 'woff2'; f.save(buf)
    return base64.b64encode(buf.getvalue()).decode()
t64 = make('title'); b64 = make('body', 650)
css = ("@font-face{font-family:'CodexTitle';src:url(data:font/woff2;base64,%s) format('woff2');font-weight:100 900;font-display:block}\n"
       "@font-face{font-family:'CodexBody';src:url(data:font/woff2;base64,%s) format('woff2');font-weight:100 900;font-display:block}" % (t64, b64))
print('fonts: title %d KB, body %d KB, %d glyphs' % (len(t64)*3//4//1024, len(b64)*3//4//1024, len(chars)))
tpl = tpl.replace('/*FONTS*/', css)
# ---- textures (Mivo 生成 → art/codex_ui/baked/*.jpg) inline as CSS variables
tex = {'panel': 'panel', 'card': 'card', 'cream': 'cream', 'btn': 'btn', 'mea': 'meander', 'dia': 'diamonds'}
tcss = ':root{' + ''.join("--t-%s:url(data:image/jpeg;base64,%s);" % (k, base64.b64encode((root / 'art/codex_ui/baked' / (v + '.jpg')).read_bytes()).decode()) for k, v in tex.items()) + '}'
tpl = tpl.replace('/*TEX*/', tcss)
out = tpl.replace('/*WINGSWORD_DATA*/null', data)
(here / 'weapon-codex.html').write_text(out, encoding='utf-8')
print('wrote', here / 'weapon-codex.html', len(out) // 1024, 'KB')
