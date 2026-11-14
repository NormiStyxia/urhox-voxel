"""Legacy filename: current 3D cloud shader contract + retained ground-shadow atlas. No GPU compilation."""
from pathlib import Path
import math
import xml.etree.ElementTree as ET
from PIL import Image

shader = Path('assets/Shaders/BLGL/RuinsCloud.shader').read_text()
material = ET.parse('assets/Materials/RuinsCloud.xml').getroot()
texture = material.find('surfacetexture')
assert texture is None and 'cloud_atlas' not in shader, 'low must not preload large density through material XML'
for name,size in [('cloud_density.png',(4096,1536)),('cloud_density_low.png',(2048,256)),('cloud_occupancy.png',(256,128))]:
    assert Image.open('assets/Textures/Sky/'+name).size==size
    assert Path('assets/Textures/Sky/'+name+'.meta').is_file()
assert 'filter_nearest' in shader and 'use_occupancy' in shader and 'cell_exit' in shader
for token in ('density(vec3 world)', 'MAIN_LIGHT_DIRECTION', 'volume_interval', 'trans*=tr',
              'sky_top.rgb', 'sky_horizon.rgb', 'highp sampler2D scene_depth',
              'cull_disabled', 'blend_premul_alpha', 'depth_draw_never', 'finite3', 'PREMUL_ALPHA_FACTOR=1.0'):
    assert token in shader, token
im = Image.open('assets/Textures/Sky/cloud_flat_atlas.png')
assert im.mode == 'RGBA' and im.size == (1024, 1024)
assert Path('assets/Textures/Sky/cloud_flat_atlas.png.meta').is_file()
assert 'FRAGCOORD.z' not in shader and 'normalize(NORMAL)' not in shader
assert 'textureLod(density_volume' in shader and 'fog_disabled' in shader
print('PASS density shader contract: bounded 3D sampling/integration, finite guards, one premultiplied composite; not a GPU compile')
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
print('PASS ground shadow contract: same A-only mask, no noise, Clamp/no mip, positive/negative 64m tiles stay inset')

print('PASS retained shadow mask; current volume integration preview is raymarch_check.py')
