-- Offline Lua 5.4 contract test; no UrhoX Runtime.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local V=getmetatable(Vector3())
function V:CrossProduct(b) return Vector3(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x) end
function V:Normalized() local n=self:Length();return n>0 and self*(1/n) or Vector3() end
local C=Color
Color=setmetatable({WHITE=C(1,1,1,1)},{__call=function(_,...)return C(...)end})
cache={GetResource=function()return {}end}
Clamp=function(v,a,b)return math.max(a,math.min(v,b))end
Lerp=function(a,b,t)return a+(b-a)*t end
-- __index is a function in this mock; extend per-instance recursively instead.
local function node(name,parent)
    local n=Mock.Node(name,parent)
    function n:CreateChild(childName)
        local child=node(childName,self);self.children[#self.children+1]=child;return child
    end
    function n:GetChild(childName)
        for _,child in ipairs(self.children) do if child.name==childName then return child end end
    end
    function n:CreateComponent(kind)
        assert(kind=='CustomGeometry')
        local g=Mock.CustomGeometry(self);self.geometry=g;return g
    end
    return n
end
local function near(a,b)assert(math.abs(a-b)<1e-8,tostring(a)..' ~= '..tostring(b))end
local function vec(a,b)near(a.x,b.x);near(a.y,b.y);near(a.z,b.z)end
local function rotation(a,b)near(math.abs(a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z),1)end
local B=require('game.BlockCharacter')
assert(B.USE_ELBOW_DATA==false)
local old=B.LoadVoxelData()
assert(old==require('game.NomiVoxelData'))
B.USE_ELBOW_DATA=true
local new=B.LoadVoxelData()
assert(new==require('game.NomiVoxelDataElbow'))
B.USE_ELBOW_DATA=false
local legacy=B.CreateVoxel(node('scene'),old,B.SLENDER)
local elbow=B.CreateVoxel(node('scene'),new,B.SLENDER)
assert(not legacy.bones.forearm_right)
assert(elbow.bones.forearm_right.parent==elbow.bones.arm_right)
assert(#elbow.bones.forearm_right.geometry.vertices>0)
assert(#elbow.bones.arm_right.geometry.vertices>0)
-- No eager sockets / migration side effects for old call sites.
assert(legacy.bones.arm_right:GetChild('SpellPalm')==nil)
local existing=legacy.bones.arm_right:CreateChild('SpellPalm')
existing.position=Vector3(10*.85,-13,.75*.92)*old.unit
assert(legacy:HandSocket('right')==existing)
for _,side in ipairs({'right','left'}) do
    local a,b=legacy:HandSocket(side),elbow:HandSocket(side)
    assert(a==legacy:HandSocket(side) and b==elbow:HandSocket(side))
    assert(a.parent==legacy.bones['arm_'..side])
    assert(b.parent==elbow.bones['forearm_'..side])
    vec(a.worldPosition,b.worldPosition);rotation(a.worldRotation,b.worldRotation)
    local pivot=b.parent.worldPosition
    local distance=(b.worldPosition-pivot):Length()
    for _,angle in ipairs({0,45,90,120}) do
        elbow:SetBone('forearm_'..side,-angle,0,0)
        near((b.worldPosition-pivot):Length(),distance)
        if angle>0 then assert(b.worldPosition.z>a.worldPosition.z,'backward elbow')end
    end
    elbow:SetBone('forearm_'..side,0,0,0)
end
assert(not pcall(function()legacy:HandSocket('up')end))
elbow:SetBone('forearm_right',-90,0,0)
elbow:Update(.016,{onGround=true,moveSpeed=0})
rotation(elbow.bones.forearm_right.rotation,Quaternion())
-- Reference version is supplied by the runner from read-only git show.
local path=os.getenv('NOMI_BASELINE_LUA')
assert(path,'supply NOMI_BASELINE_LUA for default-behaviour comparison')
local Original=dofile(path)
local reference=Original.CreateVoxel(node('scene'),old,Original.SLENDER)
local current=B.CreateVoxel(node('scene'),old,B.SLENDER)
for name,n in pairs(reference.bones) do
    local actual=current.bones[name]
    vec(n.position,actual.position);vec(n.scale,actual.scale)
    assert(#n.children==#actual.children)
    if n.geometry then
        local av,bv=n.geometry.vertices,actual.geometry.vertices
        assert(#av==#bv)
        for i,v in ipairs(av)do
            vec(v.position,bv[i].position);vec(v.normal,bv[i].normal)
            for _,channel in ipairs({'r','g','b','a'})do near(v.color[channel],bv[i].color[channel])end
        end
    end
end
for _,state in ipairs({{onGround=true,moveSpeed=0},{onGround=true,moveSpeed=5},
    {onGround=false,moveSpeed=7},{onGround=true,crouching=true},{onGround=true,armed=true,aiming=true,aimPitch=25}})do
    for frame=1,30 do
        reference:Update(1/60,state);current:Update(1/60,state)
        for name,n in pairs(reference.bones)do
            vec(n.position,current.bones[name].position)
            rotation(n.rotation,current.bones[name].rotation)
        end
    end
end
print('PASS elbow rig: data switch, parent/geometry, socket continuity, mirrored forward bend, reset, legacy vertices/RGB/poses')
