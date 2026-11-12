-- Lua 5.4，无引擎窗口。世界保留 node/body；Dispose 仅解绑组件，故能捕捉残影删除错误。
package.path = "scripts/?.lua;" .. package.path
local V = {}; V.__index = V
Vector3 = setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x=x,y=y,z=z},V) end})
function V.__add(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) return Vector3(a.x*b,a.y*b,a.z*b) end
function V:LengthSquared() return self.x*self.x+self.y*self.y+self.z*self.z end
function V:Length() return math.sqrt(self:LengthSquared()) end
function V:Normalized() return self*(1/math.max(self:Length(),1e-9)) end
function V:Lerp(b,t) return self+(b-self)*t end
Vector3.UP,Vector3.ZERO=Vector3(0,1,0),Vector3(0,0,0)
local Q={};Q.__index=Q
function Q.__mul(_,v) return v end
function Q:Slerp() return self end
function Q:DotProduct() return 1 end
function Q:Inverse() return self end
Quaternion=function() return setmetatable({},Q) end
Variant=function(x) return x end
Material={new=function()
    return {params={},SetSurfaceShader=function() return true end,SetSurfaceTexture=function() end,
        SetShaderParameter=function(self,k,v) self.params[k]=v end}
end}
local live, created, removed = {},0,0
local world={}
function world:GetPaletteTexture() return {} end
function world:CreateVolume(nx,ny,nz,s,pos,rot)
    local node={worldPosition=pos,worldRotation=rot}
    local v={node=node,solid={},material=nil}
    function v:GetNode() return node end
    function v:GetGrid()
        return {SetSolid=function(_,i,j,k,value) self.solid[i..":"..j..":"..k]=value end,SetVoxelMaterial=function() end}
    end
    function v:RebuildGeometry() end
    function v:Dispose() error("component Dispose leaves world-owned render nodes; use RemoveVolume") end
    live[v]=true;created=created+1
    return v
end
function world:FinalizeVolume(v) assert(live[v]);v.body="static" end
function world:FinalizeVolumeAsDynamic(v)
    assert(live[v]);v.body="dynamic";v.linearVelocity=Vector3.ZERO;v.angularVelocity=Vector3.ZERO
end
function world:RemoveVolume(v)
    assert(live[v],"double removal")
    live[v]=nil;v.node=nil;v.body=nil;removed=removed+1
end
local function count() local n=0;for _ in pairs(live) do n=n+1 end;return n end
local TimeObject=require("ruins.TimeObject")
local vox={}
for i=0,3 do for j=0,2 do for k=0,3 do vox[#vox+1]={i,j,k,105} end end end
local o=TimeObject.New({id="lifecycle",world=world,voxels=vox,size=.25,origin=Vector3.ZERO,dims={4,3,4}})
local restoredEvents=0
o:On(function(_,event) if event=="restored" then restoredEvents=restoredEvents+1 end end)
assert(count()==1)
for round=1,3 do
    assert(o:Shatter({level=2}));assert(o.whole==nil and count()==#o.pieces)
    assert(o.material.params.restored==0)
    if round==1 then
        assert(o:Freeze(3));assert(count()==#o.pieces)
        o:Unfreeze();assert(count()==#o.pieces)
        o:Freeze(3);assert(count()==#o.pieces)
    elseif round==2 then
        -- 真轨迹回溯分支（非开局散落），用物理后的位移模拟一个采样。
        for _,p in ipairs(o.pieces) do p.node.worldPosition=p.node.worldPosition+Vector3(2,1,0) end
        o:RecordAll(1.0)
    else
        o:SettleAsRubble()
    end
    assert(o:Rewind());assert(count()==#o.pieces)
    for _,p in ipairs(o.pieces) do assert(p.vol.body==nil,"rewind must not retain old solver bodies") end
    for i=1,100 do o:Update(.05) end
    assert(o:IsWhole() and count()==1 and #o.pieces==0,"old and new states overlap")
    assert(o.whole.body=="static")
    assert(o.flash==0 and o.material.params.mode==0 and o.material.params.restored==1)
    assert(restoredEvents==round)
    o:Reassemble();assert(count()==1 and restoredEvents==round,"duplicate reassemble")
    assert(not o:Rewind(),"restored object cannot replay stale pieces")
    assert(o:Freeze(.1));o:Update(.01);assert(o.material.params.mode==1)
    o:Update(.2);assert(o.material.params.mode==0)
end
o:RemoveWhole();assert(count()==0 and created==removed)
print(string.format("time lifecycle PASS: %d created / %d fully removed, no residual nodes/bodies",created,removed))
