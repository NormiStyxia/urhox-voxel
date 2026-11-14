"""Source audit + CPU predicate equivalence, NOT SurfaceShader/HLSL compilation."""
from pathlib import Path
import itertools
import math
import random
import re

root = Path(__file__).resolve().parents[2]
paths = sorted((root / 'assets/Shaders/BLGL').glob('Dragon*.shader'))
paths += [root / 'assets/Shaders/BLGL' / x for x in ('VoxelSprite.shader', 'VoxelCube.shader', 'IceCrystal.shader')]
calls = re.compile(r'\b(texture\w*|Sample\w*|dFdx|dFdy|fwidth|ddx|ddy)\s*\(')
sites = []
for p in paths:
    source = re.sub(r'/\*.*?\*/', '', p.read_text(), flags=re.S)
    source = re.sub(r'//[^\n]*', '', source)
    assert source.count('{') == source.count('}'), p
    assert source.count('(') == source.count(')'), p
    found = list(calls.finditer(source))
    for m in found:
        before = source[:m.start()]
        fragment = before[before.rfind('void fragment()'):]
        assert fragment.startswith('void fragment()'), (p, 'call outside fragment')
        assert fragment.count('{') - fragment.count('}') == 1, (p, 'nested sampling/derivative')
        assert not re.search(r'\b(if|for|while|discard|clip)\b|[?]', fragment), (p, 'control flow before sampling')
        line = source.count(chr(10), 0, m.start()) + 1
        sites.append((p.name, line, m.group(1)))
    print(p.name, 'calls:', [(x[1], x[2]) for x in sites if x[0] == p.name],
          'discard lines:', [source.count(chr(10), 0, m.start()) + 1 for m in re.finditer(r'\bdiscard\b', source)])
assert [(s[0], s[2]) for s in sites] == [('DragonRuneSmooth.shader', 'fwidth'), ('VoxelSprite.shader', 'textureLod')]
for name in ('DragonRune.shader', 'VoxelSprite.shader'):
    s = (root / 'assets/Shaders/BLGL' / name).read_text()
    s = re.sub(r'//[^\n]*', '', s)
    assert len(re.findall(r'\bdiscard\b', s)) == 1
    assert s.rindex('discard') > s.rindex('ALBEDO')
print('PASS source inventory: 9 shaders; no explicit implicit-LOD sampling; single unconditional derivative before control flow')

def step(edge, x): return float(x >= edge)
def mix(a, b, t): return a * (1-t) + b*t
def frac(x): return x-math.floor(x)
def h21(x, y):
    x, y = frac(x*123.34), frac(y*456.21)
    d = x*(x+45.32) + y*(y+45.32)
    return frac((x+d)*(y+d))

rng = random.Random(6)
for _ in range(40000):
    r0, r1 = .885, .94
    r, u, ci, seed = rng.random()*1.5, rng.uniform(-.3, 1.3), rng.randrange(-40, 40), rng.randrange(100)
    gx, gy = math.floor(u*5), math.floor((r-r0)/(r1-r0)*5)
    on = step(.52, h21(gx+ci*7.13+seed, gy+ci*7.13+seed))
    old = on
    if gx == 2: old = max(old, step(.25, h21(ci+3.1, gy+3.1)))
    if gy in (0,4): old *= step(.5, h21(ci*1.7,gx))
    if r<r0 or r>r1 or u<0 or u>1: old=0
    new = mix(on,max(on,step(.25,h21(ci+3.1,gy+3.1))),1-step(.5,abs(gx-2)))
    new *= mix(1,step(.5,h21(ci*1.7,gx)),1-step(.5,min(abs(gy),abs(gy-4))))
    new *= step(r0,r)*step(r,r1)*step(0,u)*step(u,1)
    assert old == new
print('PASS 40000 rune-band mask/early-return parity cases')

# All threshold boundaries, outline masks, visibility and alpha values.
for any_, light, hot, flare, head, outline, vis, alpha, r in itertools.product(
        (0,.5,1), (0,.5,1), (0,1), (0,1), (0,1), (0,1), (0,1), (0,.009,.01,.5,1), (.9,1,1.1)):
    color = .1
    a = 0
    if any_ > .5:
        color = .3
        if light > .5: color=.7
        if hot > .5 or flare > .5 or head > .5: color=1.4
        color *= 1.2
        a=1
    elif outline > .5: a=.85
    a *= vis*alpha
    old_keep = r<=1 and a>=.01
    filled = 1-step(any_,.5)
    ink = mix(.3,.7,1-step(light,.5))
    ink = mix(ink,1.4,1-step(max(hot,flare,head),.5))*1.2
    new_color=mix(.1,ink,filled)
    new_a=mix(.85*outline,1,filled)*vis*alpha
    new_keep=step(r,1)*step(.01,new_a)>.5
    assert old_keep==new_keep
    if old_keep: assert abs(color-new_color)<1e-12 and abs(a-new_a)<1e-12
print('PASS rune palette/discard parity including strict .5 and alpha=.01 boundaries')
for tex, cell, alpha in itertools.product((0,.49,.5,1), (0,.1,.5,1), (0,.1,.5,1)):
    assert (not (tex < .5 or cell > alpha*1.02)) == (step(.5,tex)*step(cell,alpha*1.02)>=.5)
print('PASS sprite discard predicate parity; one-mip nearest lookup stays at LOD 0')
print('UNVERIFIED: generated engine shader code, FXC compilation, actual GPU draw/cache hit and frame timing')
