-- Offline: FootPlant on a minimal two-segment leg rig (real quaternion FK, no engine).
package.path="scripts/?.lua;tests/combat/?.lua;"..package.path
require("anim_mock")
local D=require("combat.AnimClips")
local F=require("combat.FootPlant")
local function near(a,b,e,msg) assert(math.abs(a-b)<(e or 1e-6),(msg or "")..": "..tostring(a).." != "..tostring(b)) end

-- Nodes with a parent chain; world transforms are computed on read like the engine.
local NodeMeta={}
NodeMeta.__index=function(n,key)
    if key=="worldRotation" then
        local p=rawget(n,"parent")
        return p and p.worldRotation*n.rotation or n.rotation
    elseif key=="worldPosition" then
        local p=rawget(n,"parent")
        if not p then return n.position end
        local o=p.worldRotation*n.position
        local w=p.worldPosition
        return Vector3(w.x+o.x,w.y+o.y,w.z+o.z)
    end
end
local function node(name,parent,x,y,z)
    return setmetatable({name=name,parent=parent,position=Vector3(x,y,z),rotation=Quaternion(0,0,0)},NodeMeta)
end
local function rig()
    local c={bones={},basePos={}}
    c.root=node("Character",nil,0,0,0)
    local function add(name,parent,x,y,z)
        local n=node(name,parent and c.bones[parent] or c.root,x,y,z)
        c.bones[name]=n;c.basePos[name]=Vector3(x,y,z)
    end
    add("root",nil,0,0,0);add("DownBody","root",0,.966,0);add("Leg","DownBody",0,-.062,0)
    add("leg_right","Leg",.0925,.012,0);add("ysm_RightLowerLeg","leg_right",.001,-.458,0);add("ysm_RightFoot","ysm_RightLowerLeg",0,-.325,0)
    add("leg_left","Leg",-.0925,.012,0);add("ysm_LeftLowerLeg","leg_left",-.001,-.458,0);add("ysm_LeftFoot","ysm_LeftLowerLeg",0,-.325,0)
    return c
end
-- Rewrite the base pose every frame like BlockCharacter does.
local function reset(c)
    for name,n in pairs(c.bones) do n.rotation=Quaternion(0,0,0);n.position=c.basePos[name] end
end
local function anim(clip)
    local a={clip=clip,t=0,w=1,handle=1}
    function a:Footwork() return self.clip,self.t,self.w,self.handle end
    return a
end
local function dist(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end

-- The voxel rig has no knee bone: footwork stays off instead of guessing.
local voxel=rig();voxel.bones.ysm_RightLowerLeg=nil
assert(F.New(voxel,anim(D.Clips.sword_light_1))==nil)

local c=rig()
local clip=D.Clips.sword_light_1
local a=anim(clip)
local fp=assert(F.New(c,a))
local R,L=fp.legs[1],fp.legs[2]
near(R.ankleY,.133,1e-4,"ankle rest height")
local function step(t,dz)
    reset(c);a.t=t
    if dz then local p=c.root.position;c.root.position=Vector3(p.x,p.y,p.z+dz) end
    fp:Apply(1/60)
end
-- From rest: both feet start where the base pose put them, on the ground.
step(0)
near(R.x,.0935,1e-3);near(L.x,-.0935,1e-3);near(R.y,R.ankleY,1e-6)
for _,leg in ipairs(fp.legs) do near(dist(leg.ankle.worldPosition,{x=leg.x,y=leg.y,z=leg.z}),0,2e-3,"ik reaches rest foot") end

-- The lunge carries the body; the left (support) foot stays nailed to the world.
local planted={x=L.x,y=L.y,z=L.z}
local moved,lifted=0,0
for i=1,14 do
    local t=i*.016
    local dz=.55/14
    moved=moved+dz
    step(t,dz)
    lifted=math.max(lifted,R.y-R.ankleY)
    -- The support foot never lifts. It holds its world spot until the lunge has
    -- carried the body past `drag`, then it is pulled along the floor, not stepped.
    near(L.y,L.ankleY,1e-9,"support foot stays on the ground")
    if moved<=.30 then near(L.x,planted.x,1e-9);near(L.z,planted.z,1e-9)
    else near(math.sqrt((L.x+.0935)^2+(L.z-moved)^2),.30,1e-6,"dragged at the limit") end
    planted={x=L.x,y=L.y,z=L.z}
    -- Toe stays put; past the deepest lunge the heel peels up instead of the foot sliding.
    local p=L.ankle.worldPosition
    near(math.sqrt((p.x-planted.x)^2+(p.z-planted.z)^2),0,.02,"support foot holds while the body moves "..i)
    near(p.y,planted.y+L.heel,.02,"heel lift "..i);assert(L.heel<=.1+1e-9)
    -- The knee bends toward the toes, never backwards.
    local h,k=L.hip.worldPosition,L.knee.worldPosition
    local u=(k.y-h.y)/(p.y-h.y)
    assert(k.z>=h.z+(p.z-h.z)*u-1e-3,"knee points forward")
end
assert(R.swing,"the right foot is mid-step during the lunge")
assert(lifted>.06,"the stepping foot lifts off the ground")
-- Landing: the right foot reaches its body-relative target and locks there.
step(.231)
assert(not R.swing)
near(R.x,.134,1e-3);near(R.z,moved+.34,1e-3,"lands ahead of the moved body");near(R.y,R.ankleY,1e-9)
near(dist(R.ankle.worldPosition,{x=R.x,y=R.y,z=R.z}),0,.02,"ik lands the foot")
assert(fp.drop>0,"a split stance lowers the hips")
assert(L.z<moved-.25,"the support foot stays behind: a long lunge stance")
local landed={x=R.x,z=R.z}
step(.30);near(R.x,landed.x,1e-9);near(R.z,landed.z,1e-9)

-- A chained clip keeps the feet exactly where they are.
local before={R.x,R.z,L.x,L.z}
a.clip,a.handle,a.t=D.Clips.sword_light_2,2,.0;reset(c);fp:Apply(1/60)
near(R.x,before[1],1e-9);near(R.z,before[2],1e-9);near(L.x,before[3],1e-9);near(L.z,before[4],1e-9)

-- By the start of the fade-out, both feet are back under the hips.
for _,id in ipairs({"sword_light_1","sword_light_2","sword_light_3","sword_light_4","sword_light_5"}) do
    local k=D.Clips[id]
    local cc=rig();local aa=anim(k);local f=assert(F.New(cc,aa))
    local t=0
    while t<=k.dur-(k.fadeOut or 0)+1e-9 do
        reset(cc);aa.t=t;f:Apply(1/60);t=t+1/60
    end
    reset(cc);aa.t=k.dur-(k.fadeOut or 0);f:Apply(1/60)
    for _,leg in ipairs(f.legs) do
        assert(not leg.swing,id.." no foot in the air at fade-out")
        near(leg.x,leg.def.side*.094,1e-3,id.." rest x");near(leg.z,0,1e-3,id.." rest z")
    end
    -- Every step is ordered, finite and lands inside the clip.
    for _,st in ipairs(k.footwork.steps) do assert(st[2]<st[3] and st[3]<=k.dur-(k.fadeOut or 0)) end
    -- One lead foot steps out and back; the support foot only leaves the ground in a jump.
    local support=k.footwork.support.foot
    local lead={}
    for _,st in ipairs(k.footwork.steps) do
        if st[1]~=support then lead[#lead+1]=st else assert(st[8],id.." support foot only lifts in a jump") end
    end
    assert(#lead==2 and lead[1][1]==lead[2][1],id.." one lead foot: out, then back")
    assert(lead[2][4]==k.footwork.steps[#k.footwork.steps][4] and lead[2][5]==0,id.." the lead foot comes back under the hips")
    -- Ground strikes spend the lunge by contact; the hops travel with the jump.
    local contact={sword_light_1=.25,sword_light_2=.26,sword_light_3=.27}
    if contact[id] then assert(k.motion[1].t1<=contact[id] and k.motion[1].t0<k.phases.active[1],id.." lunge before contact") end
end
-- Airborne steps ride the hop.
local hop=D.Clips.sword_light_4
local hc=rig();local ha=anim(hop);local hf=assert(F.New(hc,ha))
reset(hc);ha.t=0;hf:Apply(1/60)
reset(hc);hc.bones.root.position=Vector3(0,.36,0);ha.t=.30;hf:Apply(1/60)
assert(hf.legs[1].y>hf.legs[1].ankleY+.3 and hf.legs[2].y>hf.legs[2].ankleY+.3,"both feet leave the ground in the hop")
-- Weight 0 leaves the base pose untouched.
reset(c);a.w=0;a.t=.5;local q=c.bones.leg_right.rotation;fp:Apply(1/60)
near(c.bones.leg_right.rotation.w,q.w,1e-9)
print("PASS foot plant: rest entry, world-locked support foot, forward knee, body-relative landing, lunge drop, chained clips keep feet, rest at fade-out, hop ride, zero weight")
