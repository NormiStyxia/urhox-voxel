"""Actual sparse-cell orthographic projections, never an engine screenshot."""
import json
import statistics
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
BEFORE = json.loads((OUT / 'before.json').read_text())
AFTER = json.loads((OUT / 'after.json').read_text())
FONT = '/System/Library/Fonts/STHeiti Medium.ttc'
COLORS = [(224,178,83),(143,208,232),(157,179,194),(170,102,48),(112,144,82),(153,121,177)]
PAPER, INK = (238,230,210), (48,61,62)

def text(draw, xy, value, size=16):
    draw.text(xy, value, font=ImageFont.truetype(FONT,size), fill=INK)

def project(draw, cells, config, origin, axes=('x','y','z'), scale=6, reverse=False):
    front = {}
    for c in cells:
        key = (c[axes[0]], c[axes[1]])
        if key not in front or ((c[axes[2]] < front[key][axes[2]]) if reverse else (c[axes[2]] > front[key][axes[2]])):
            front[key] = c
    for (u,v), c in front.items():
        channel = c['channel']
        rgb = COLORS[config['colors']['primary' if channel=='dark' else channel]-1]
        if channel == 'dark':
            rgb = tuple(round(n*.38) for n in rgb)
        x,y = origin[0]+u*scale, origin[1]-v*scale
        draw.rectangle((round(x-scale/2),round(y-scale/2),round(x+scale/2)-1,round(y+scale/2)-1),fill=rgb)
    # Origin mark is an audit overlay; it is not part of the weapon.
    x,y=origin
    draw.line((x-4,y,x+4,y),fill=(160,63,49));draw.line((x,y-4,x,y+4),fill=(160,63,49))

def sheet(weapon, names):
    im=Image.new('RGB',(1050,600),PAPER);d=ImageDraw.Draw(im)
    text(d,(20,15),('剑' if weapon=='sword' else '弓')+' · 实际体素正投影 / 非引擎渲染',24)
    text(d,(20,54),'同一比例：1 格 = 3cm；红十字=握点。未套用既有剑视觉缩放。',16)
    for i,(preset,name) in enumerate(names):
        key=weapon+'_'+preset
        old,new=BEFORE['presets'][key],AFTER['presets'][key]
        x=175+i*350
        text(d,(x-145,94),name,22)
        axes=('x','y','z') if weapon=='sword' else ('z','y','x')
        if weapon=='sword':
            for record,cx in [(old,x-85),(new,x+25)]:
                project(d,record['cells'],record['config'],(cx,370),axes,6)
            project(d,new['cells'],new['config'],(x+110,370),('z','y','x'),6)
            text(d,(x-105,442),'原正面');text(d,(x+5,442),'新正面');text(d,(x+85,442),'新侧面')
        else:
            for record,cx in [(old,x-90),(new,x+15)]:
                project(d,record['cells'],record['config'],(cx,280),axes,6)
            project(d,new['cells'],new['config'],(x+110,280),('x','y','z'),6)
            text(d,(x-115,442),'原右侧');text(d,(x-10,442),'新右侧');text(d,(x+85,442),'新正面')
        text(d,(x-145,486),f"体素 {len(old['cells'])} → {len(new['cells'])}")
        text(d,(x-145,512),'尺寸 '+ ' × '.join(f'{n:.2f}' for n in new['bounds']['size'])+' m',15)
    text(d,(20,562),'灰铁刃脊 / 铜金收边 / 深色缠柄；颜色直接来自现有存档色板，无光照美化。',16)
    im.save(OUT/(weapon+'-comparison.png'))

def part_cells(part):
    out=[]
    for iy,layer in enumerate(part['voxels']):
        for iz,row in enumerate(layer):
            for ix,char in enumerate(row):
                if char!='.':
                    out.append(dict(x=part['origin'][0]+ix,y=part['origin'][1]+iy,z=part['origin'][2]+iz,channel=part['palette'][char]))
    return out

def parts_sheet():
    im=Image.new('RGB',(1050,1310),PAPER);d=ImageDraw.Draw(im)
    text(d,(20,15),'19 个部件 · 实际单件几何 / 非引擎渲染',24)
    text(d,(20,52),'每件主/侧视等比例，倍率见下方；原格 3cm；弓臂主视为右侧。',16)
    for i,p in enumerate(AFTER['parts']):
        col,row=i%4,i//4;left,top=col*262,90+row*240
        text(d,(left+12,top),p['name'],19);text(d,(left+12,top+27),p['id'],12)
        cells=part_cells(p)
        lo=min(c['y'] for c in cells);hi=max(c['y'] for c in cells)
        scale=min(12,140//(hi-lo+1))
        y=top+137+(lo+hi)*scale/2
        config=AFTER['presets'][p['weapon']+'_balanced']['config']
        project(d,cells,config,(left+100,y),('z','y','x') if p['slot']=='limbs' else ('x','y','z'),scale)
        project(d,cells,config,(left+190,y),('x','y','z') if p['slot']=='limbs' else ('z','y','x'),scale)
        text(d,(left+12,top+218),str(len(cells))+' 体素 / '+str(scale)+'px每格 / root '+str(p['sockets']['root']),11)
    im.save(OUT/'all-parts.png')

def bows_sheet():
    im=Image.new('RGB',(1050,1150),PAPER);d=ImageDraw.Draw(im)
    text(d,(20,12),'弓三档 + 实际上弦箭 · 右侧视图 / 非引擎渲染',23)
    text(d,(20,50),'左=射手 -Z，右=目标 +Z；箭与箭台同高，尾扣接触弦；红十字=握点。',16)
    for row,(preset,name) in enumerate([('fast','短弓 / 骨簇'),('balanced','反曲弓 / 铁簇'),('armor','长弓 / 晶簇')]):
        p=AFTER['presets']['bow_'+preset]
        for stage in range(3):
            left,top=stage*350,90+row*340
            shape=p['draw'][stage]
            cells=list(shape['cells'])
            nx=round(p['hit']['origin'][0]/.03);ny=round(p['hit']['origin'][1]/.03);nz=round(shape['nockZ']/.03)
            cells += [dict(c,x=c['x']+nx,y=c['y']+ny,z=c['z']+nz) for c in p['arrow']]
            text(d,(left+12,top),f'{name}  档位 {stage}',18)
            text(d,(left+12,top+28),f"弦中点 {shape['stringMidpoint'][2]:.2f}m / 尾扣 {nz*.03:.2f}m",14)
            project(d,cells,p['config'],(left+125,top+181),('z','y','x'),5)
    text(d,(20,1115),'0 档图为上弦后最低拉力（p>0.05）示意；完全松手时箭按既有逻辑隐藏。',16)
    im.save(OUT/'bow-draw-stages.png')

def check_and_report():
    old={p['id']:p for p in BEFORE['parts']};new={p['id']:p for p in AFTER['parts']}
    assert old.keys()==new.keys() and len(new)==19
    for ident,p in new.items():
        for field in ['weapon','slot','stats','sockets','palette']:
            assert p[field]==old[ident][field],(ident,field)
    for a,b in zip(BEFORE['combinations'],AFTER['combinations']):
        assert a['ids']==b['ids'] and a['hit']==b['hit'] and a['stats']==b['stats'] and a['offsets']==b['offsets']
        assert a['bounds']['size'][1]==b['bounds']['size'][1]
    lines=['# 武器造型离线审查','', '实际 Lua 稀疏体素投影，不是引擎渲染。72 组合的 ID、属性、接点、判定长度与发射原点/方向保持一致。', '',
        '## 组合预算','', '| 指标 | 细化前 | 细化后 |','|---|---:|---:|']
    for weapon in ['sword','bow']:
        for key,label in [('voxels','体素数'),('quads','预览合并四边形'),('preview_steps','离线分帧步数')]:
            vals=[[r[key] for r in source['combinations'] if r['weapon']==weapon] for source in [BEFORE,AFTER]]
            lines.append(f'| {weapon} {label}范围 | {min(vals[0])}–{max(vals[0])} | {min(vals[1])}–{max(vals[1])} |')
    for key in ['volumes','rebuilds','writes','occupied','capacity']:
        lines.append(f"| 默认两武器 + 全部预建池 {key} | {BEFORE['rig'][key]} | {AFTER['rig'][key]} |")
    lines += ['', 'capacity 为所有池体积的网格包围盒容量，occupied 为实际已填格；新增箭台横向延伸使部分弓池 AABB 变宽。预览 quads 是实际 Lua 贪心网格结果，三角形=quads×2、顶点=quads×6；世界 VoxelVolume 面数及真实 draw call 需 Web 验证。', '', '## 离线成本（不可当作 Web 性能）','',
        f"冷缓存 Compile + 两把默认武器 mock CustomGeometry 预览，9 次中位数：{BEFORE['offline_compile_plus_mock_preview_ms']['median']:.3f} → {AFTER['offline_compile_plus_mock_preview_ms']['median']:.3f} ms。包含 Lua 算法与 mock 记录，不包含 GPU/原生网格构建；每次采样先重置模块缓存。",'',
        '## 单件尺寸与接点','', '| ID | 体素前→后 | 尺寸 X×Y×Z (m) | root → top (格) | launch (格) |','|---|---:|---|---|---|']
    for ident,p in new.items():
        cells=part_cells(p)
        sizes=[(max(c[k] for c in cells)-min(c[k] for c in cells)+1)*.03 for k in ['x','y','z']]
        lines.append(f"| {ident} | {len(part_cells(old[ident]))} → {len(cells)} | {'×'.join(f'{x:.2f}' for x in sizes)} | {p['sockets']['root']} → {p['sockets']['top']} | {p['sockets'].get('launch','—')} |")
    lines += ['', '## 完整预设','', '| 预设 | 尺寸 X×Y×Z (m) | 握点到实际刃尖 / 发射点 (m) |','|---|---|---|']
    for name,p in AFTER['presets'].items():
        hit=p['hit'];value=f"{hit['length']:.3f}" if 'length' in hit else str(hit['origin'])+' / +Z'
        lines.append(f"| {name} | {'×'.join(f'{x:.2f}' for x in p['bounds']['size'])} | {value} |")
    (OUT/'metrics.md').write_text(chr(10).join(lines)+chr(10))
    print('PASS compatibility: 19 stable IDs, unchanged stats/sockets/palette; all 72 hit/offset/height values equal baseline')
    print('PASS projection export: sword-comparison.png, bow-comparison.png, all-parts.png, bow-draw-stages.png')

def three_views():
    im=Image.new('RGB',(1050,870),PAPER);d=ImageDraw.Draw(im)
    text(d,(20,12),'正 / 右侧 / 背向实际投影 · 非引擎渲染',23)
    text(d,(20,50),'正背保持同一世界 X 轴以对照厚度；背向取最小 Z。红十字=握点。',16)
    for row,weapon in enumerate(['sword','bow']):
        p=AFTER['presets'][weapon+'_balanced']
        for col,(label,axes,back) in enumerate([('正面 +Z',('x','y','z'),False),('右侧 +X',('z','y','x'),False),('背面 -Z',('x','y','z'),True)]):
            x,top=175+col*350,90+row*370
            text(d,(x-100,top),weapon+' / '+label,18)
            project(d,p['cells'],p['config'],(x,top+(260 if weapon=='sword' else 185)),axes,7,back)
    im.save(OUT/'orthographic-views.png')

sheet('sword',[('balanced','直刃 / 十字'),('fast','细剑 / 窄身'),('armor','阔刃 / 翼形')])
sheet('bow',[('fast','短弓'),('balanced','反曲弓'),('armor','长弓')])
parts_sheet();bows_sheet();three_views();check_and_report()
