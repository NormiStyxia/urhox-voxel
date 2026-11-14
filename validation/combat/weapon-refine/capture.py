"""Offline Lua 5.4 geometry audit. Run at project root: capture.py before|after.
No Runtime: CustomGeometry/Volume calls below use tests/combat/weapon_mock.lua.
"""
import itertools
import json
import statistics
import sys
import time
from pathlib import Path
from lupa.lua54 import LuaRuntime, lua_type

OUT = Path(__file__).resolve().parent

def plain(value):
    if lua_type(value) != 'table':
        return value
    keys = list(value.keys())
    if keys and set(keys) == set(range(1, len(keys) + 1)):
        return [plain(value[i]) for i in range(1, len(keys) + 1)]
    return {str(k): plain(value[k]) for k in keys}

def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path='scripts/?.lua;tests/combat/?.lua;'..package.path; Mock=require('weapon_mock'); P=require('combat.WeaponParts'); B=require('combat.WeaponBuilder'); cache={GetResource=function() return {} end}")
    return lua

def capture(label):
    lua = runtime()
    p, b = lua.globals().P, lua.globals().B
    result = {'label': label, 'parts': plain(p.All), 'combinations': [], 'presets': {}}
    preview = lua.eval("""function(c)
        local job=B.BeginPreview(Mock.Node('preview'),c,nil)
        local steps=0
        repeat steps=steps+1;B.StepPreview(job,2,function() return 0 end) until job.done or steps>2000
        assert(job.mesh,job.error)
        local count=#job.mesh.quads;B.DisposePreview(job.mesh)
        return count,steps
    end""")
    for weapon in ['sword', 'bow']:
        slots = plain(p.Slots[weapon])
        options = [[part['id'] for part in plain(p.GetOptions(weapon, slot))] for slot in slots]
        for ids in itertools.product(*options):
            c = p.DefaultWeapon(weapon)
            c.weapon = weapon
            for slot, ident in zip(slots, ids):
                c.parts[slot] = ident
            bp = b.Compile(c)
            quads, steps = preview(c)
            result['combinations'].append({'ids': ids, 'weapon': weapon, 'voxels': len(bp.geometry.cells),
                'bounds': plain(bp.bounds), 'hit': plain(bp.hit), 'offsets': plain(bp.geometry.offsets),
                'stats': plain(bp.stats), 'quads': quads, 'preview_steps': steps})
        for preset in ['balanced', 'fast', 'armor']:
            c = p.Preset(weapon, preset)
            c.weapon = weapon
            bp = b.Compile(c)
            result['presets'][weapon + '_' + preset] = {
                'config': plain(c), 'cells': plain(bp.geometry.cells), 'bounds': plain(bp.bounds),
                'hit': plain(bp.hit), 'offsets': plain(bp.geometry.offsets)}
            if weapon == 'bow':
                result['presets'][weapon + '_' + preset]['draw'] = [plain(b.BowVisual(bp, i)) for i in range(3)]
                if b.NockedArrow:
                    result['presets'][weapon + '_' + preset]['arrow'] = plain(b.NockedArrow(bp))
    result['rig'] = plain(lua.eval("""function()
        local Rig=require('combat.WeaponRig')
        local root=Mock.Node('audit');local w=Mock.World(root)
        local r=Rig.New(root,w,Mock.Nomi(root))
        local occupied,capacity=0,0
        for _,v in ipairs(w.volumes) do
            capacity=capacity+v.dimensions[1]*v.dimensions[2]*v.dimensions[3]
            for _ in pairs(v.grid.solid) do occupied=occupied+1 end
        end
        local result={volumes=w.created,rebuilds=w.rebuilds,writes=w.writes,occupied=occupied,capacity=capacity}
        r:Dispose();assert(w.created==w.removed);return result
    end""")())
    timings = []
    for _ in range(9):
        # Fresh module caches each trial; only timed Lua work, not loading/mock setup.
        bench = runtime()
        run = bench.eval("""function()
            for _,weapon in ipairs({'sword','bow'}) do
                local c=P.DefaultWeapon(weapon);c.weapon=weapon
                local bp=B.Compile(c);assert(bp)
                local job=B.BeginPreview(Mock.Node('bench'),c,nil)
                repeat B.StepPreview(job,2,function() return 0 end) until job.done
                assert(job.mesh,job.error);B.DisposePreview(job.mesh)
            end
        end""")
        start = time.perf_counter()
        run()
        timings.append((time.perf_counter() - start) * 1000)
    result['offline_compile_plus_mock_preview_ms'] = {'trials': timings, 'median': statistics.median(timings)}
    (OUT / (label + '.json')).write_text(json.dumps(result, ensure_ascii=False, indent=2) + chr(10))
    print(label, '72 combinations', result['rig'], 'offline median ms', statistics.median(timings))

if __name__ == '__main__':
    capture(sys.argv[1])
