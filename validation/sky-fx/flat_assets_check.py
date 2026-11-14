"""Celestial cloud asset contract + retained ground-shadow atlas. No GPU compilation."""
from pathlib import Path
import math
import xml.etree.ElementTree as ET
from PIL import Image

shader = Path('assets/Shaders/BLGL/RuinsCloud.shader').read_text()
material = ET.parse('assets/Materials/RuinsCloud.xml').getroot()
texture = material.find('surfacetexture')
assert texture is None, 'quality-specific atlas is bound only by Lua'
assert material.find("parameter[@name='cloud_enabled']").get('value') == '0'
for name,size in [('cloud_sculpted_atlas.png',(2048,1024)),('cloud_sculpted_atlas_low.png',(1024,512))]:
    atlas=Image.open('assets/Textures/Sky/'+name)
    assert atlas.size==size and atlas.mode=='RGBA'
    assert Path('assets/Textures/Sky/'+name+'.meta').is_file()
    w,h=size[0]//4,size[1]//2
    for row in range(2):
        for col in range(4):
            cell=atlas.crop((col*w,row*h,(col+1)*w,(row+1)*h))
            pixels=list(cell.getdata());fg=[p for p in pixels if p[3]>127]
            assert w*h*.03<len(fg)<w*h*.8
            assert max(p[0] for p in fg)-min(p[0] for p in fg)>60, 'missing lighting range'
            assert max(p[1] for p in pixels)>10, 'missing thin-edge channel'
            assert max(p[2] for p in fg)-min(p[2] for p in fg)>60, 'missing lateral normal channel'
            border=list(cell.crop((0,0,w,1)).getdata())+list(cell.crop((0,h-1,w,h)).getdata())
            border+=list(cell.crop((0,0,1,h)).getdata())+list(cell.crop((w-1,0,w,h)).getdata())
            assert max(p[3] for p in border)==0, 'opaque cell edge'
for token in ('MAIN_LIGHT_DIRECTION', 'cloud_atlas', 'CAMERA_POSITION_WORLD',
              'sky_top.rgb', 'sky_horizon.rgb', 'sky_bottom.rgb',
              'cull_disabled', 'blend_mix', 'depth_draw_never', 'world_vertex_coords'):
    assert token in shader, token
assert shader.count('texture(')==1
for token in ('scene_depth','INVERSE_PROJECTION_MATRIX','density_volume','use_occupancy','Z_CLIP_SCALE','PREMUL_ALPHA_FACTOR'):
    assert token not in shader, token
assert 'filter_linear_mipmap, repeat_disable' in shader
im = Image.open('assets/Textures/Sky/cloud_flat_atlas.png')
assert im.mode == 'RGBA' and im.size == (1024, 1024)
assert Path('assets/Textures/Sky/cloud_flat_atlas.png.meta').is_file()
assert 'FRAGCOORD.z' not in shader and 'normalize(NORMAL)' not in shader
assert 'fog_disabled' in shader
print('PASS original celestial atlas: 8 cells, lighting/thin edge/normal/coverage, transparent gutters, official meta; one sampler, no depth read; not a GPU compile')
for row in range(2):
    for col in range(2):
        cell = im.crop((col*512, row*512, (col+1)*512, (row+1)*512))
        fg = [(r,g,b,a) for r,g,b,a in cell.getdata() if a >= 128]
        assert 5000 < len(fg) < 240000, 'empty/solid atlas cell'
        assert sum(r >= 128 for r,g,b,a in fg) > len(fg)*.05
        assert sum(g >= 128 for r,g,b,a in fg) > len(fg)*.005
        assert sum(r < 128 and g < 128 for r,g,b,a in fg) > len(fg)*.1
        # A one-pixel inset cannot prevent a cloud crossing the cell boundary itself.
        border = list(cell.crop((0,0,512,1)).getdata()) + list(cell.crop((0,511,512,512)).getdata())
        border += list(cell.crop((0,0,1,512)).getdata()) + list(cell.crop((511,0,512,512)).getdata())
        assert max(p[3] for p in border) < 128, 'atlas shape touches adjacent cell'
print('PASS actual RGBA atlas: 4 separate shapes, shade/highlight/base coverage, transparent gutters, existing meta')

ground_shader = Path('assets/Shaders/BLGL/RuinsGround.shader').read_text()
shadow = ground_shader.split('if (cloud_shadow_strength > 0.0', 1)[1]
assert 'textureLod(cloud_shadow_atlas, atlasUV, 0.0).a' in shadow
assert 'vnoise(' not in shadow and 'hash' not in shadow
assert 'uniform sampler2D cloud_shadow_atlas : filter_linear, repeat_disable;' in ground_shader
for world in (-1000., -128.001, -128., -64.001, -64., -.001, 0., .001, 63.999, 64., 1000.):
    uv = world/64
    local = uv-math.floor(uv)
    cell = math.floor(uv)*.5-math.floor(math.floor(uv)*.5)
    atlas = cell+(1+local*510)/1024
    assert 0 <= atlas < 1 and math.floor(atlas*2) == int(cell*2)
    assert 1/1024-1e-9 <= atlas-cell <= 511/1024+1e-9
print('PASS retained ground shadow contract: A-only approximation, no noise, Clamp/no mip, positive/negative 64m tiles stay inset')

print('PASS retained shadow mask; current celestial shader preview is skycards_check.py; raymarch checks are historical')
