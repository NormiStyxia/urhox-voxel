"""Offline source/runtime comparison; no engine, scene window, build or network."""
import bisect
import importlib.util
import json
import math
import sys
from pathlib import Path
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home()/'Downloads/诺米/诺米.bbmodel'
source = json.loads(SOURCE.read_text())
spec = importlib.util.spec_from_file_location('bbimport', ROOT/'art/nomi_ysm/import_bbmodel.py')
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
local support=dofile('tests/combat/core_support.lua')
local baseQuaternion=Quaternion
Quaternion=function(a,b,c,d)
    if type(b)=='table' then
        local h=math.rad(a)*.5
        return baseQuaternion(math.cos(h),b.x*math.sin(h),b.y*math.sin(h),b.z*math.sin(h))
    end
    return baseQuaternion(a,b,c,d)
end
Clamp=function(x,a,b)return math.max(a,math.min(b,x))end
Lerp=function(a,b,t)return a+(b-a)*t end
Vector2=function(x,y)return {x=x,y=y}end
TRIANGLE_LIST=0
cache={GetResource=function()return nil end}
local Node={}
Node.__index=function(self,key)
    if key=='worldRotation' then return self.parent and self.parent.worldRotation*(self.rotation or Quaternion()) or self.rotation or Quaternion() end
    if key=='worldPosition' then return self.parent and self.parent:LocalToWorld(self.position or Vector3.ZERO) or self.position or Vector3.ZERO end
    if key=='worldScale' then return Vector3(1,1,1) end
    return Node[key]
end
function Node:LocalToWorld(point)return self.worldPosition+self.worldRotation*point end
function Node:WorldToLocal(point)
    local q=self.worldRotation
    return Quaternion(q.w,-q.x,-q.y,-q.z)*(point-self.worldPosition)
end
function Node:CreateChild(name)
    return setmetatable({name=name,parent=self,position=Vector3.ZERO,
        rotation=Quaternion(),scale=Vector3(1,1,1)},Node)
end
function Node:CreateComponent()
    return setmetatable({}, {__index=function()return function()end end})
end
function Node:GetChild()return nil end
local B=require('game.BlockCharacter')
local D=require('game.NomiYSMData')
character=B.Create(setmetatable({},Node),D)
BModule=B
function pose(clip,phase)
    character.time=phase*D.animations[clip].length
    character.bbMotion=clip=='idle' and 0 or 1
    character.bbRun=clip=='run' and 1 or 0
    character.bbCycle=phase
    character.air,character.crouch,character.armed=0,0,0
    character:UpdateImportedLocomotion(0,{onGround=true},clip=='run' and 7.2 or 4.2,0)
end
''')
data=lua.eval("require('game.NomiYSMData')")
if isinstance(data,tuple):data=data[0]
char=lua.globals().character
sample=lua.globals().BModule.SampleAnimationChannel

# Check the written artifact, not just in-memory exporter output.
assert (ROOT/'scripts/game/NomiYSMData.lua').read_text()==importer.convert(source)
groups={g['uuid']:g for g in source['groups']}
clips={a['name']:a for a in source['animations'] if a['name'] in ('idle','walk','run')}
checks=0
seams={}
for name,clip in clips.items():
    mismatch=0
    for uuid,animator in clip['animators'].items():
        bone=importer.ALIASES.get(groups[uuid]['name'],groups[uuid]['name']) if uuid in groups else None
        channels={}
        for f in animator.get('keyframes',[]):channels.setdefault(f['channel'],[]).append(f)
        for channel,frames in channels.items():
            frames.sort(key=lambda f:f['time'])
            actual=data.animations[name].tracks[bone][channel]
            assert len(actual)==len(frames)
            # Every key plus every interval midpoint, including the root Molang.
            times=[f['time'] for f in frames]
            probes=times+[(a+b)*.5 for a,b in zip(times,times[1:])]
            for t in probes:
                idx=max(0,bisect.bisect_right(times,t)-1)
                a,b=frames[idx],frames[min(idx+1,len(frames)-1)]
                u=(t-a['time'])/(b['time']-a['time']) if b['time']>a['time'] else 0
                def val(f,axis):
                    v=f['data_points'][0][axis]
                    return 12 if v=='0.4*ysm.head_yaw' else float(v)
                expected=[val(a,axis)*(1-u)+val(b,axis)*u for axis in 'xyz']
                got=sample(actual,t,1 if channel=='scale' else 0,30)
                assert max(abs(x-y) for x,y in zip(expected,got))<1e-9,(name,bone,channel,t)
                checks+=3
            if len(frames)>1:
                mismatch+=int(any(frames[0]['data_points'][0][axis]!=frames[-1]['data_points'][0][axis] for axis in 'xyz'))
    seams[name]=mismatch
print('PASS source key/midpoint components:',checks,'; source seam mismatches:',seams)

# Independent quaternion multiplication and reference BB ZYX transforms.
def multiply(a,b):
    w,x,y,z=a;W,X,Y,Z=b
    return (w*W-x*X-y*Y-z*Z,w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W)
def rotation(v):
    x,y,z=[math.radians(t)*.5 for t in v]
    return multiply(multiply((math.cos(z),0,0,math.sin(z)),(math.cos(y),0,-math.sin(y),0)),(math.cos(x),-math.sin(x),0,0))
def rotate(q,v):
    out=multiply(multiply(q,(0,*v)),(q[0],-q[1],-q[2],-q[3]))
    return out[1:]
def reference_sample(track,t,fallback):
    if not track:return [fallback]*3
    frames=sorted(track,key=lambda f:f['time']);times=[f['time'] for f in frames]
    i=max(0,bisect.bisect_right(times,t)-1);a,b=frames[i],frames[min(i+1,len(frames)-1)]
    u=(t-a['time'])/(b['time']-a['time']) if b['time']>a['time'] else 0
    def val(f,k):return 0 if f['data_points'][0][k]=='0.4*ysm.head_yaw' else float(f['data_points'][0][k])
    return [val(a,k)*(1-u)+val(b,k)*u for k in 'xyz']

world_checks=0
for name,clip in clips.items():
    tracks={groups[uid]['name']:rec for uid,rec in clip['animators'].items() if uid in groups}
    for phase in (0,.125,.25,.333,.5,.625,.75,.875,.999999):
        lua.globals().pose(name,phase)
        world={}
        def visit(entry,parent=None):
            global world_checks
            if isinstance(entry,str):return
            g=groups[entry['uuid']];srcname=g['name'];alias=importer.ALIASES.get(srcname,srcname)
            animator=tracks.get(srcname,{})
            channels={}
            for f in animator.get('keyframes',[]):channels.setdefault(f['channel'],[]).append(f)
            t=phase*clip['length'];r=reference_sample(channels.get('rotation'),t,0)
            q=rotation([a+b for a,b in zip(g.get('rotation',[0,0,0]),r)])
            offset=reference_sample(channels.get('position'),t,0)
            pg=groups[parent] if parent else None;origin=pg['origin'] if pg else [0,0,0]
            p=[(a-b+c)*.05*s for a,b,c,s in zip(g['origin'],origin,offset,[1,1,-1])]
            node=char.bones[alias];gotq=tuple(node.rotation[k] for k in ('w','x','y','z'))
            assert abs(abs(sum(a*b for a,b in zip(q,gotq)))-1)<1e-9,(name,alias,phase,'rotation')
            assert max(abs(p[i]-node.position[k]) for i,k in enumerate(('x','y','z')))<1e-9,(name,alias,phase,'position')
            if parent:
                pq,pp=world[parent];q=multiply(pq,q);delta=rotate(pq,p);p=[a+b for a,b in zip(pp,delta)]
            world[entry['uuid']]=(q,p)
            expected_parent=importer.ALIASES.get(pg['name'],pg['name']) if pg else 'BlockCharacter'
            assert node.parent.name==expected_parent,(alias,'parent')
            actual_world=node.worldPosition
            assert max(abs(p[i]-actual_world[k]) for i,k in enumerate(('x','y','z')))<1e-8,(name,alias,phase,'world')
            actual_q=node.worldRotation
            assert abs(abs(sum(q[i]*actual_q[k] for i,k in enumerate(('w','x','y','z'))))-1)<1e-8
            world_checks+=1
            for child in entry.get('children',[]):visit(child,entry['uuid'])
        for root in source['outliner']:visit(root)
print('PASS all 177 local/world hierarchy transforms:',world_checks)

lua.execute('''
-- Blocked movement freezes phase; transitions and hitstop retain one clock.
pose('walk',.37)
local cycle=character.bbCycle
for i=1,60 do character:Update(1/60,{moveSpeed=0,onGround=true}) end
assert(character.bbCycle==cycle)
assert(character.bbMotion<.0001)
character:Update(0,{moveSpeed=7.2,onGround=true})
assert(character.bbCycle==cycle)
-- Authored cadence after the speed blend has settled.
character.bbMotion,character.bbRun=1,0
for i=1,60 do character:Update(1/60,{moveSpeed=4.2,onGround=true}) end
assert(math.abs((character.bbCycle-cycle+.5)%1-.5)<1e-8)
character.bbRun=1
for i=1,60 do character:Update(1/60,{moveSpeed=7.2,onGround=true}) end
local expected=(cycle+1/.6667)%1
assert(math.abs((character.bbCycle-expected+.5)%1-.5)<1e-8)
-- Imported run core survives legacy sprint; weapon arms and sword strike cover it.
local A=require('combat.CombatAnim')
character.animations=character.animations
local a=A.New(character,nil,{quantize=false,pathIK=false})
a:Play('sprint_loop',{fadeIn=0,params={sprintWeight=1,gaitPhase=.4,weaponInHand=0}})
a:Update(.1);pose('run',.4)
local r,b,h=character.bones.leg_right.rotation,character.bones.body.rotation,character.bones.arm_right.rotation
local y=character.bones.root.position.y
a:Apply()
local function same(q,p) return math.abs(q.w*p.w+q.x*p.x+q.y*p.y+q.z*p.z)>1-1e-8 end
assert(same(r,character.bones.leg_right.rotation) and same(b,character.bones.body.rotation))
assert(same(h,character.bones.arm_right.rotation))
assert(math.abs(y-character.bones.root.position.y)<1e-9)
a:SetParam('weaponInHand',1);a:Update(.1);pose('run',.4);a:Apply()
assert(not same(h,character.bones.arm_right.rotation))
a:Play('sword_light_1',{fadeIn=0});a:Update(.12);pose('run',.4);a:Apply()
assert(not same(h,character.bones.arm_right.rotation))
-- Fresh base clears overlays, including unkeyed idle limbs.
pose('idle',.4)
assert(same(character.baseRotation.arm_right,character.bones.arm_right.rotation))
''')
print('PASS cadence/block/hitstop/reset and sprint/weapon/attack overlay contracts')
