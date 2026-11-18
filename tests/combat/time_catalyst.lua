-- Offline checks for the time catalyst orb (art/weapon_gen/clock_catalyst_*.py) and its motion rules.
-- Shader compilation / pixels still require Web preview.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local m=require('combat.models.ClockCatalyst')
assert(m.name=='clock_catalyst' and m.scale==10000 and m.nscale==1000)
local total=0
for _,name in ipairs({'bands','blades','gems','shards','core'}) do
    local part=m[name]
    assert(part and #part.i==part.triangles*3 and #part.v%8==0,name)
    local nv=#part.v//8
    local inward=0
    for t=0,part.triangles-1 do
        local p,n={}, {0,0,0}
        for k=1,3 do
            local idx=part.i[t*3+k];assert(idx>=1 and idx<=nv)
            local b=(idx-1)*8
            p[k]={part.v[b+1],part.v[b+2],part.v[b+3]}
            for a=1,3 do n[a]=n[a]+part.v[b+3+a] end
            assert(part.v[b+7]>=0 and part.v[b+7]<=6 and part.v[b+8]>=0 and part.v[b+8]<=100)
        end
        local ux,uy,uz=p[2][1]-p[1][1],p[2][2]-p[1][2],p[2][3]-p[1][3]
        local vx,vy,vz=p[3][1]-p[1][1],p[3][2]-p[1][2],p[3][3]-p[1][3]
        if (uy*vz-uz*vy)*n[1]+(uz*vx-ux*vz)*n[2]+(ux*vy-uy*vx)*n[3]<0 then inward=inward+1 end
    end
    assert(inward/part.triangles<.01,name..' winding follows normals')
    total=total+part.triangles
end
assert(total>1500 and total<4500,'triangle budget '..total)
assert(m.radius>.25 and m.radius<.30)

local Visual=require('combat.TimeCatalystVisual')
local Material=_G.Material
local oldCache=_G.cache
rawset(_G,'cache',{GetResource=function(_,kind,path)
    if kind=='Material' then return Material:new() end
    return oldCache:GetResource(kind,path)
end})
local scene=Mock.Node('scene')
local v=assert(Visual.New(scene))
assert(not v.ready and not v.root.enabled)
for _=1,12 do Visual.Step(v) end
assert(v.ready,'upload spread over frames completes')
for _,name in ipairs({'bands','blades','gems','shards','core'}) do
    assert(v.geometry[name].commits==1 and #v.geometry[name].vertices==m[name].triangles*3,name)
end
local function Ctx(t)
    local c={active=true,position=Vector3(0,0,0),yaw=0,hand=Vector3(.3,1.2,.2),aiming=false,charge=0,casting=false}
    for k,val in pairs(t or {}) do c[k]=val end
    return c
end
for _=1,60 do Visual.Update(v,1/60,Ctx()) end
assert(v.root.enabled and v.fade>.95)
local rest=Vector3(v.root.position.x,v.root.position.y,v.root.position.z)
assert(rest.z<-.3 and rest.y>1.2 and rest.x>.3,'rests behind the right shoulder')
local restSpin=v.spinBoost
-- aiming: glides to the palm, spin ramps up
for i=1,12 do Visual.Update(v,1/60,Ctx{aiming=true,charge=.5}) end
local mid=v.root.position
assert(mid.z>rest.z and mid.z<.4+.2,'moving, not teleported')
for _=1,90 do Visual.Update(v,1/60,Ctx{aiming=true,charge=1}) end
local atHand=v.root.position
assert(math.abs(atHand.x-.3)<.1 and math.abs(atHand.y-1.23)<.12 and atHand.z>.3,'settles at the palm')
assert(v.spinBoost>restSpin*3,'spin boost while charging')
assert(v.root.scale.x>Visual.SCALE*1.05,'slightly larger while aiming')
-- cast pop then back to the back slot
Visual.Update(v,1/60,Ctx{aiming=true,charge=1,casting=true})
assert(v.pulse>.9)
for _=1,200 do Visual.Update(v,1/60,Ctx()) end
local back=v.root.position
assert(math.abs(back.z-rest.z)<.06 and v.pulse<.05,'returns to the back after the cast')
-- part angles move; bands and blades counter-rotate
local a0,b0=v.angles.bands,v.angles.blades
Visual.Update(v,.05,Ctx())
local function Delta(a,b) local d=(a-b+540)%360-180 return d end
assert(Delta(v.angles.bands,a0)*Delta(v.angles.blades,b0)<0,'opposite spin')
-- armed combat: dissolves and disables
for _=1,120 do Visual.Update(v,1/60,Ctx{active=false}) end
assert(not v.root.enabled and v.fade==0)
-- Urho Node enable is not recursive: every child that draws must be off too (regression: orb stayed in place)
for _,child in ipairs(v.root.children) do assert(not child.enabled,child.name..' must be disabled with the root') end
-- re-appears at the rest slot (no flight from the last position)
Visual.Update(v,1/60,Ctx())
assert(v.root.enabled and v.root.position.z<-.3)
for _,child in ipairs(v.root.children) do
    if child.name~='catalyst_ring' then assert(child.enabled,child.name..' must be enabled with the root') end
end
-- cast ripple: shown right after the cast, gone when it has expired
for _=1,5 do Visual.Update(v,1/60,Ctx()) end
Visual.Update(v,1/60,Ctx{aiming=true,casting=true})
assert(v.ringNode.enabled and v.ringAge<.05)
for _=1,70 do Visual.Update(v,1/60,Ctx()) end
assert(not v.ringNode.enabled)
Visual.Dispose(v)
rawset(_G,'cache',oldCache)
print('time_catalyst OK tris='..total)
