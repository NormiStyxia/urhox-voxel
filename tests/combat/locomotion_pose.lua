local S=dofile('tests/combat/locomotion_support.lua')
local A,F=S.Anim,S.F
local data=require('game.NomiVoxelData')
local variant=require('game.BlockCharacter').SLENDER
local clip=require('combat.AnimClips').Clips.dodge_slide
local times={0,.02,.06,.12,.22,.26,.30,.32}
local body={4,14,24,24,18,10,6,4}
local head={-1,-10,-18,-18,-13,-7,-3,-1}
local right={0,10,18,16,8,-10,-4,0}
local left={0,-14,-22,-20,-12,10,4,0}
for i,t in ipairs(times) do
 local p=A.DebugSample('dodge_slide',t,{moveZ=1,weaponInHand=0})
 S.near(p.body[1],body[i]);S.near(p.head[1],head[i]);S.near(p.leg_right[1],right[i]);S.near(p.leg_left[1],left[i])
 assert(not p.knee and not p.ankle)
end
for phase=0,3 do
 local p=A.DebugSample('sprint_loop',0,{gaitPhase=phase/4,sprintAccel=1,weaponInHand=0})
 local expected={{14,-34,28,24},{16,0,0,0},{14,28,-34,-24},{16,0,0,0}}
 S.near(p.body[1],expected[phase+1][1]);S.near(p.leg_right[1],expected[phase+1][2]);S.near(p.leg_left[1],expected[phase+1][3]);S.near(p.arm_right[1],expected[phase+1][4])
end
-- Build only the real root/leg transforms, using the shipped pivots, scale and unit.
local char={bones={},basePos={}}
local lift=18*(1.35-1)*data.unit
char.bones.root={position=Vector3(0,lift,0),worldScale=Vector3(1,1,1)}
char.basePos.root=Vector3(0,lift,0)
local function world(node,p)
 local x,y,z=S.Mock.rotate(node.rotation,p.x,p.y*1.35,p.z)
 return Vector3(x+node.position.x,y+node.position.y+char.bones.root.position.y,z+node.position.z)
end
for _,b in ipairs(data.bones) do
 if b.name=='leg_right' or b.name=='leg_left' then
  assert(b.parent=='root')
  char.bones[b.name]={position=Vector3(b.pivot[1]*.85*data.unit,b.pivot[2]*data.unit,b.pivot[3]*.92*data.unit),rotation=Quaternion(0,0,0),LocalToWorld=world}
 end
end
local foot=F.New();foot:Soles(char,data,variant);assert(#foot.soles==8)
local soleVertices={}
for _,bone in ipairs(data.bones) do
 if char.bones[bone.name] and bone.name~='root' then
  local low=math.huge
  for _,q in ipairs(data.quads[bone.name]) do if q[1]==4 then low=math.min(low,q[2]) end end
  for _,q in ipairs(data.quads[bone.name]) do if q[1]==4 and q[2]<=low+1 then
   for x=0,1 do for z=0,1 do
    soleVertices[#soleVertices+1]={bone=bone.name,point=Vector3((q[3]+x*q[5]+data.origin[1]-bone.pivot[1])*.85*data.unit,
      (q[2]+data.origin[2]-bone.pivot[2])*data.unit,(q[4]+z*q[6]+data.origin[3]-bone.pivot[3])*.92*data.unit)}
   end end
  end end
 end
end
S.near(lift,.1386)
local groundY=0
local function ground()return groundY end
for _,dx in ipairs({-1,0,1}) do
 for _,dz in ipairs({-1,0,1}) do
  if dx~=0 or dz~=0 then
   for frame=0,32 do
    local p=A.DebugSample('dodge_slide',frame*.01,{moveX=dx,moveZ=dz,weaponInHand=0})
    char.bones.root.position=Vector3(0,lift-.02,0)
    for _,name in ipairs({'leg_right','leg_left'}) do
     local e=p[name];char.bones[name].rotation=Quaternion(e[1],e[2],e[3])
    end
    foot:Ground(.01,ground,true,true)
    for _,sole in ipairs(foot.soles) do assert(char.bones[sole.bone]:LocalToWorld(sole.point).y>=groundY+.006-1e-8) end
    for _,v in ipairs(soleVertices) do assert(char.bones[v.bone]:LocalToWorld(v.point).y>=groundY-1e-8,'real shoe underside penetrates flat ground') end
    assert(char.bones.root.position.y<.3,'no repeated SLENDER lift')
   end
  end
 end
end
for _,node in pairs(char.bones) do node.rotation=Quaternion(0,0,0) end
for i=1,200 do
 char.bones.root.position=Vector3(0,lift,0);foot:Ground(.01,ground,true,true)
end
S.near(char.bones.root.position.y,lift+.006)
groundY=.1;char.bones.root.position=Vector3(0,lift-.02,0);foot:Ground(.01,ground,true,true)
S.near(char.bones.root.position.y,lift+.106)
-- Crossfade consumes the stopped dodge at the locomotion layer, with no base gait leak.
local c=S.Mock.character();local a=A.New(c,nil,{quantize=false})
local h=a:Play('dodge_slide',{fadeIn=0,params={moveZ=1,sprintPending=1,weaponInHand=0}})
a:Update(.30);a:Poll();a:Apply()
local before=c.bones.body.rotation
a:Stop(h,.04)
local run=a:Play('sprint_loop',{params={sprintWeight=1,gaitPhase=0,sprintAccel=0,weaponInHand=0}})
assert(run)
S.Mock.reset(c);a:Apply();local after=c.bones.body.rotation
S.near(math.abs(before.w*after.w+before.x*after.x+before.y*after.y+before.z*after.z),1)
a:Update(.02);S.Mock.reset(c);a:Apply()
local weight=0;for _,t in ipairs(a.tracks) do if t.live then weight=weight+t.weight end end
S.near(weight,1)
local attack=a:Play('sword_light_1');assert(attack and not a:IsPlaying('sprint_loop'))
assert(#require('combat.AnimClips').Clips.sprint_loop.motion==0)
local file=assert(io.open('scripts/combat/AnimClips.lua'));local src=file:read('*a');file:close()
local _,count=src:gsub('id="dodge_slide"','');assert(count==1)
print('PASS R9 final Euler values, stride phases, real 8 sole corners/8 directions, lift once, ground raise, locomotion crossfade/priority')

S.near(F.PhaseForLegs(18,-18,.2),.5)
S.near(F.PhaseForLegs(-18,18,.9),0)
S.near(F.PhaseForLegs(0,0,.7),.75)
print('PASS first run phase fits actual rigid hips at entry amplitude and preserves nearest cycle branch')
