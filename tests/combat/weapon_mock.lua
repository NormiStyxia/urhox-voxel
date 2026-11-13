-- Minimal engine contract double, including real quaternion/node transforms.
-- It does NOT emulate rendering, native allocation or the physical world.
local M={}
local V={}
V.__index=V
local function v(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
function V.__add(a,b) return v(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return v(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) return v(a.x*b,a.y*b,a.z*b) end
function V:Length() return math.sqrt(self.x*self.x+self.y*self.y+self.z*self.z) end
local Q={}
local function q(w,x,y,z) return setmetatable({w=w,x=x,y=y,z=z},Q) end
function Q.__index(a,key)
    if key=="eulerAngles" then return rawget(a,"angles") or v() end
    return Q[key]
end
---@param a any
---@param b any
---@return any
function Q.__mul(a,b)
    if getmetatable(b)==V then
        local r=(a*q(0,b.x,b.y,b.z)*q(a.w,-a.x,-a.y,-a.z)) --[[@as any]]
        return v(r.x,r.y,r.z)
    end
    return q(a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z,
        a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
        a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
        a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w)
end
local function euler(p,y,r)
    p,y,r=p or 0,y or 0,r or 0
    local hp,hy,hr=math.rad(p)/2,math.rad(y)/2,math.rad(r)/2
    local result=q(math.cos(hy),0,math.sin(hy),0)*q(math.cos(hp),math.sin(hp),0,0)*q(math.cos(hr),0,0,math.sin(hr))
    result.angles=v(p,y,r)
    return result
end
rawset(_G,"Quaternion",euler)
rawset(_G,"Vector3",setmetatable({ZERO=v(),UP=v(0,1,0),FORWARD=v(0,0,1)}, {__call=function(_,...) return v(...) end}))
rawset(_G,"Color",function(r,g,b,a) return {r=r,g=g,b=b,a=a or 1} end)
rawset(_G,"Variant",function(value) return value end)
rawset(_G,"BLEND_ALPHA",3)
rawset(_G,"BLEND_ADDALPHA",4)
rawset(_G,"CMP_LESSEQUAL",4)

local N={}
local function worldRotation(n)
    if n.fixedRotation then return n.fixedRotation end
    return n.parent and worldRotation(n.parent)*n.rotation or n.rotation
end
local function worldPosition(n)
    if n.fixedPosition then return n.fixedPosition end
    return n.parent and worldPosition(n.parent)+worldRotation(n.parent)*n.position or n.position
end
local NodeMeta={__index=function(n,key)
    if key=="worldPosition" then return worldPosition(n) end
    if key=="worldRotation" then return worldRotation(n) end
    return N[key]
end,__newindex=function(n,key,value)
    if key=="worldPosition" then rawset(n,"fixedPosition",value)
    elseif key=="worldRotation" then rawset(n,"fixedRotation",value)
    else rawset(n,key,value) end
end}
function M.Node(name,parent)
    return setmetatable({name=name,parent=parent,position=v(),rotation=euler(),scale=v(1,1,1),enabled=true,children={}},NodeMeta)
end
function N:CreateChild(name)
    local child=M.Node(name,self)
    self.children[#self.children+1]=child
    return child
end
function N:SetParent(parent) self.parent=parent end
function N:LocalToWorld(point) return worldPosition(self)+worldRotation(self)*point end
function N:Remove() assert(not self.removed,"double node removal"); self.removed=true end

local function Pass()
    return {SetBlendMode=function(self,x) self.blend=x end,SetDepthWrite=function(self,x) self.depthWrite=x end,
        SetDepthTestMode=function(self,x) self.depthTest=x end}
end
local function Technique()
    local result={passes={base=Pass(),litbase=Pass(),light=Pass(),shadow=Pass(),deferred=Pass(),depth=Pass(),velocity=Pass()}}
    result.Clone=function() return Technique() end
    result.RemovePass=function(self,name) self.passes[name]=nil end
    result.GetPass=function(self,name) return self.passes[name] end
    return result
end
local function Material()
    local result={parameters={},technique=Technique()}
    result.Clone=function() return Material() end
    result.GetTechnique=function(self) return self.technique end
    result.SetTechnique=function(self,_,t) self.technique=t end
    result.SetShaderParameter=function(self,k,value) self.parameters[k]=value end
    result.Dispose=function(self) assert(not self.disposed); self.disposed=true end
    return result
end
function M.World(scene)
    local world={created=0,rebuilds=0,writes=0,removed=0,paletteWrites=0,palette={},volumes={},base=Material()}
    world.GetPaletteMaterial=function(self) return self.base end
    world.SetPaletteEntry=function(self,index,color)
        assert(index>=160 and index<=191,"out of reserved palette")
        self.paletteWrites=self.paletteWrites+1
        self.palette[index]=color
    end
    world.SetPaletteEntryPBR=function() end
    world.CreateVolume=function(self,dx,dy,dz,size)
        assert(dx%1==0 and dy%1==0 and dz%1==0 and size==0.03)
        self.created=self.created+1
        local node=M.Node("volume",scene)
        local grid={solid={},materials={}}
        local function key(x,y,z)
            assert(x%1==0 and y%1==0 and z%1==0)
            assert(x>=0 and x<dx and y>=0 and y<dy and z>=0 and z<dz,"grid bounds")
            return x..":"..y..":"..z
        end
        grid.SetSolid=function(_,x,y,z,on) self.writes=self.writes+1; grid.solid[key(x,y,z)]=on end
        grid.SetVoxelMaterial=function(_,x,y,z,index)
            assert(index>=160 and index<=191)
            self.writes=self.writes+1; grid.materials[key(x,y,z)]=index
        end
        local volume={node=node,grid=grid,dimensions={dx,dy,dz}}
        volume.GetNode=function() return node end
        volume.GetGrid=function() return grid end
        volume.RebuildGeometry=function() self.rebuilds=self.rebuilds+1 end
        self.volumes[#self.volumes+1]=volume
        return volume
    end
    world.RemoveVolume=function(self,volume)
        assert(not volume.removed,"double volume removal")
        volume.removed=true;volume.node:Remove();self.removed=self.removed+1
    end
    world.FinalizeVolume=function() error("visual weapon must not enter physics") end
    world.FinalizeVolumeAsDynamic=world.FinalizeVolume
    return world
end
function M.Nomi(scene)
    local node=scene:CreateChild("Nomi")
    local body=node:CreateChild("body")
    body.position=v(0,1,0)
    local right,left=body:CreateChild("arm_right"),body:CreateChild("arm_left")
    right.position,left.position=v(.2,.3,0),v(-.2,.3,0)
    local cast=right:CreateChild("SpellPalm")
    cast.position=v(.187,-.286,.01518)
    return {node=node,nomi={bones={body=body,arm_right=right,arm_left=left}},castSocket=cast}
end
function M.Near(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." != "..tostring(b)) end
function M.VectorNear(a,b) M.Near(a.x,b.x);M.Near(a.y,b.y);M.Near(a.z,b.z) end
return M
