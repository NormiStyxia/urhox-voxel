-- Actual BlockCharacter accessor + actual Nomi constructor/HandPos/F7 fragments.
-- Only Node/geometry bindings are mocked; palm data/parenting/rotations are real.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local V=getmetatable(Vector3())
function V:CrossProduct(b)return Vector3(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x)end
function V:Normalized()local n=self:Length();return n>0 and self*(1/n) or Vector3()end
local ColorOld=Color
Color=setmetatable({WHITE=ColorOld(1,1,1,1)},{__call=function(_,...)return ColorOld(...)end})
cache={GetResource=function()return {}end}
Clamp=function(v,a,b)return math.max(a,math.min(b,v))end
Lerp=function(a,b,t)return a+(b-a)*t end
local function node(name,parent)
    local n=Mock.Node(name,parent)
    function n:CreateChild(name)
        local c=node(name,self);self.children[#self.children+1]=c;return c
    end
    function n:GetChild(name)
        for _,c in ipairs(self.children)do if c.name==name then return c end end
    end
    function n:WorldToLocal(point)
        local q=self.worldRotation
        local inverse=setmetatable({w=q.w,x=-q.x,y=-q.y,z=-q.z},getmetatable(q))
        local p=inverse*(point-self.worldPosition)
        return Vector3(p.x/self.scale.x,p.y/self.scale.y,p.z/self.scale.z)
    end
    function n:CreateComponent(kind)
        assert(kind=='CustomGeometry');local g=Mock.CustomGeometry(self);self.geometry=g;return g
    end
    return n
end
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local function near(a,b)assert((a-b):Length()<1e-8,tostring(a)..' ~= '..tostring(b))end
local B=require('game.BlockCharacter')
local source=read('scripts/ruins/NomiController.lua')
local init=assert(source:match('(    self.nomi = BlockCharacter.CreateVoxel.-)\n    local cc ='))
assert(not init:find('CreateChild',1,true) and not init:find('socket.position',1,true),'caller must not own/move palm')
local N={}
local hand=assert(source:match('(function N:HandPos%(%).-\nend)'))
assert(load(hand,'actual Nomi HandPos','t',setmetatable({N=N},{__index=_G})))()
local oldData=require('game.NomiVoxelData')
local previous
for _,data in ipairs({oldData,(require('game.NomiVoxelDataElbow'))}) do
    local self=setmetatable({node=node('Nomi')},{__index=N})
    assert(load(init,'actual Nomi palm construction','t',setmetatable({self=self,BlockCharacter=B,NomiVoxelData=data},{__index=_G})))()
    local palm=self.nomi:HandSocket('right')
    assert(palm==self.castSocket and palm.name=='SpellPalm')
    near(self:HandPos(),palm.worldPosition)
    local owner=self.nomi.bones.forearm_right or self.nomi.bones.arm_right
    assert(palm.parent==owner)
    local count=#owner.children
    for _=1,3 do assert(self.nomi:HandSocket('right')==palm) end
    assert(#owner.children==count,'no duplicate shared sockets')
    if data==oldData then
        near(palm.position,Vector3(10*B.SLENDER.widen.x,-13,.75*B.SLENDER.widen.z)*data.unit)
        previous=self:HandPos()
    else
        near(self:HandPos(),previous)
        local before=self:HandPos();self.nomi:SetBone('forearm_right',-90,0,0)
        assert((self:HandPos()-before):Length()>.1,'castSocket tracks forearm, not shoulder')
        near(self:HandPos(),self.nomi:HandSocket('right').worldPosition)
    end
    -- F7 uses the actual accessor (left too), not a single-bone reference vector.
    local scene=read('scripts/ruins/RuinsScene.lua')
    local code=assert(scene:match('(local function AppendHandDebug.-)\nlocal function DebugTransfer'))..'\nreturn AppendHandDebug'
    local append=assert(load(code,'actual F7 palm diagnostics','t',_G))()
    local lines={};append(lines,self.nomi,{},false)
    local text=table.concat(lines,'\n')
    assert(text:find('右握点实际',1,true) and text:find('左握点实际',1,true))
    if data==oldData then assert(text:find('单段臂长',1,true) and not text:find('前臂',1,true))
    else assert(text:find('右肘',1,true) and text:find('上臂',1,true) and text:find('前臂',1,true)) end
    local rightPos=palm.position
    append({},self.nomi,{arm_right={target=Vector3(1,2,3)}},true)
    near(palm.position,rightPos)
end
assert(B.USE_ELBOW_DATA==false,'migration must not enable elbow model')
assert(source:find('BlockCharacter.CreateVoxel(self.node, NomiVoxelData, BlockCharacter.SLENDER)',1,true),'this stage preserves explicit current data selection')
print('PASS unified palm: actual constructor/accessor, old calibration/zero-elbow continuity, bent elbow follow, socket reuse/read-only F7, switch unchanged')
