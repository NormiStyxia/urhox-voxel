-- Shared offline helpers for the role acceptance spec. This file ends in
-- _support, so run_offline.py deliberately does not execute it as a suite.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local T=require('combat.enemy_support')

-- Extra Vector3 methods used by the authored effect meshes; kept out of the
-- game support module so existing suites see no new globals.
local vm=getmetatable(Vector3.ZERO)
function vm:CrossProduct(b)
    return Vector3(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x)
end
function vm:LengthSquared() return self.x*self.x+self.y*self.y+self.z*self.z end
function vm:Length() return math.sqrt(self:LengthSquared()) end
function vm:Normalized()
    local l=self:Length(); if l<1e-8 then return Vector3(0,0,0) end
    return Vector3(self.x/l,self.y/l,self.z/l)
end
local H={T=T, failures={}, pendingList={}}

function H.fail(msg) H.failures[#H.failures+1]=msg; print('FAIL '..msg) end
function H.pending(msg) H.pendingList[#H.pendingList+1]=msg; print('PENDING '..msg) end
function H.check(ok,msg) if not ok then H.fail(msg); return false end return true end
function H.near(a,b) return math.abs(a-b)<1e-5 end
function H.has(t,keys)
    if type(t)~='table' then return nil end
    for _,k in ipairs(keys) do if t[k]~=nil then return k,t[k] end end
    return nil
end

-- ---------------------------------------------------------------- mock nodes/materials/world
local nodeMethods={}
local function node(name)
    return setmetatable({name=name,position=Vector3.ZERO,scale=Vector3(1,1,1),
        rotation=Quaternion(),children={},enabled=true}, {__index=nodeMethods})
end
function nodeMethods:CreateChild(name)
    local c=node(name); self.children[#self.children+1]=c; c.parent=self; return c
end
function nodeMethods:SetParent(p) self.parent=p end
function nodeMethods:SetScale(v) self.scale=v end
function nodeMethods:LookAt(p) self.lookAt=p end
function nodeMethods:Remove() self.removed=true end
local noop=function() end
function nodeMethods:CreateComponent(kind)
    if kind=='CustomGeometry' then
        return {BeginGeometry=noop,DefineVertex=noop,DefineNormal=noop,DefineTexCoord=noop,
            SetNumGeometries=noop,Commit=noop,
            SetMaterial=function(self,a,b) if b~=nil then self.materials=self.materials or {}; self.materials[a]=b else self.material=a end end}
    elseif kind=='StaticModel' then
        return {SetModel=noop,SetMaterial=function(self,m) self.material=m end}
    end
    error('unexpected component '..tostring(kind))
end

Vector2=function(x,y) return {x=x,y=y} end
Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a or 1} end
Variant=function(v) return v end
VariantMap=function() return {} end
Quaternion=function(a,b,c) return {angle=a or 0,axis=b,yaw=b,roll=c} end
TRIANGLE_LIST=0; CULL_NONE=0
local surface={GetName=function() return 'Shaders/BLGL/EnemyVoxelHit.shader' end}
local function material()
    return setmetatable({SetTechnique=noop,SetCullMode=noop,
        SetShaderParameter=function(self,k,v) self[k]=v end,
        GetShaderParameter=function() return {IsEmpty=function() return false end,
            GetVector4=function() return {x=1,y=1,z=1,w=1} end} end,
        GetSurfaceShader=function() return surface end,
        SetSurfaceShader=function() return true end,
        GetName=function() return 'mock_material' end,
        SetSurfaceTexture=function() return true end},
        {__index={Clone=function(self) return material() end}})
end
Material={new=material}
local template=material()
cache={GetResource=function(_,kind,path)
    if kind=='Material' and path=='Shaders/BLGL/EnemyVoxelHit.xml' then return template end
    if kind=='Technique' then return {} end
    if kind=='Model' then return {} end
    return {}
end}

function H.newWorld()
    local w={created=0,rebuilt=0,removed=0,rayBlocked=false}
    function w:GetPaletteTexture() return {} end
    function w:GetPaletteBankCount() return 1 end
    function w:GetPaletteBankLimit() return 8 end
    function w:SetPaletteEntry() end
    function w:SetPaletteEntryPBR() end
    function w:FinalizeVolume() error('enemy must not enter physics world') end
    function w:FinalizeVolumeAsDynamic() error('enemy must not enter physics world') end
    function w:CreateVolume()
        self.created=self.created+1
        local n=node('voxel')
        local grid={SetSolid=noop,SetVoxelMaterial=noop,FillBox=noop,PaintBox=noop}
        local v={rebuilds=0,GetGrid=function() return grid end,GetNode=function() return n end,
            SetPaletteBank=noop,SetMaterial=function(self,m) self.material=m end,
            RebuildGeometry=function(self) self.rebuilds=self.rebuilds+1; w.rebuilt=w.rebuilt+1 end,
            GetMaterial=function(self) return self.material or template end,
            GetPaletteDomain=function() return 0 end,GetPaletteBank=function() return 0 end}
        w.volumes=w.volumes or {}; w.volumes[#w.volumes+1]=v; return v
    end
    function w:RemoveVolume(v) v.removed=true; self.removed=self.removed+1 end
    function w:RaycastSingle() return {hit=self.rayBlocked,distance=.3} end
    return w
end
H.scene=node('scene')
function H.scene:SendEvent() end

function H.newLogic(name)
    local ok,mod=pcall(require,'combat.enemies.actors.'..name)
    if not ok then H.fail(name..' require: '..tostring(mod)); return nil end
    local terrain,combat=T.Fixture()
    local ok2,e=pcall(mod.New,nil,nil,terrain,combat,Vector3.ZERO,name)
    if not ok2 then H.fail(name..' New(nil,nil): '..tostring(e)); return nil,mod end
    return e,mod,combat,terrain
end
function H.newVisual(name)
    local ok,mod=pcall(require,'combat.enemies.actors.'..name)
    if not ok then H.fail(name..' require: '..tostring(mod)); return nil end
    local terrain,combat=T.Fixture(); local w=H.newWorld()
    local ok2,e=pcall(mod.New,H.scene,w,terrain,combat,Vector3.ZERO,name)
    if not ok2 then H.fail(name..' New(scene/world): '..tostring(e)); return nil,mod,combat,w end
    return e,mod,combat,w
end
function H.modelFor(mod)
    local name=mod.Config and mod.Config.model
    if type(name)~='string' then H.fail((mod.Config and mod.Config.kind or '?')..' config.model missing'); return nil end
    local ok,m=pcall(require,'combat.enemies.models.'..name)
    if not ok or type(m.Build)~='function' then H.fail(name..' model unloadable'); return nil end
    local ok2,d=pcall(m.Build)
    if not ok2 or not d.parts then H.fail(name..' Build invalid'); return nil end
    return name,d
end
function H.finish(label)
    if #H.failures>0 then error(#H.failures..' role failures:\n'..table.concat(H.failures,'\n'),0) end
    print(string.format('PASS %s; pending=%d: %s',label,#H.pendingList,table.concat(H.pendingList,' | ')))
end
return H
