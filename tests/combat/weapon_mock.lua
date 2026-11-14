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
function Q:FromEulerAngles(p,y,r)
    local value=euler(p,y,r) --[[@as any]] -- recorded quaternion, not native userdata
    self.w,self.x,self.y,self.z=value.w,value.x,value.y,value.z
    self.angles=value.angles
end
function Q:FromAxes(x,y,z)
    local trace=x.x+y.y+z.z
    if trace>0 then
        local s=math.sqrt(trace+1)*2
        self.w,self.x,self.y,self.z=s/4,(y.z-z.y)/s,(z.x-x.z)/s,(x.y-y.x)/s
    elseif x.x>y.y and x.x>z.z then
        local s=math.sqrt(1+x.x-y.y-z.z)*2
        self.w,self.x,self.y,self.z=(y.z-z.y)/s,s/4,(y.x+x.y)/s,(z.x+x.z)/s
    elseif y.y>z.z then
        local s=math.sqrt(1+y.y-x.x-z.z)*2
        self.w,self.x,self.y,self.z=(z.x-x.z)/s,(y.x+x.y)/s,s/4,(z.y+y.z)/s
    else
        local s=math.sqrt(1+z.z-x.x-y.y)*2
        self.w,self.x,self.y,self.z=(x.y-y.x)/s,(z.x+x.z)/s,(z.y+y.z)/s,s/4
    end
    self.angles=nil
end
rawset(_G,"Quaternion",euler)
rawset(_G,"Vector3",setmetatable({ZERO=v(),UP=v(0,1,0),FORWARD=v(0,0,1)}, {__call=function(_,...) return v(...) end}))
rawset(_G,"Color",function(r,g,b,a) return {r=r,g=g,b=b,a=a or 1} end)
rawset(_G,"Variant",function(value) return value end)
rawset(_G,"BLEND_ALPHA",3)
rawset(_G,"BLEND_ADDALPHA",4)
rawset(_G,"CMP_LESSEQUAL",4)
rawset(_G,"TRIANGLE_LIST",0)

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
    if key=="worldPosition" then
        if n.parent then
            local rot=worldRotation(n.parent)
            rawset(n,'position',q(rot.w,-rot.x,-rot.y,-rot.z)*(value-worldPosition(n.parent)))
        else rawset(n,'position',v(value.x,value.y,value.z)) end
    elseif key=="worldRotation" then
        if n.parent then
            local rot=worldRotation(n.parent)
            rawset(n,'rotation',q(rot.w,-rot.x,-rot.y,-rot.z)*value)
        else rawset(n,'rotation',q(value.w,value.x,value.y,value.z)) end
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
function N:LocalToWorld(point) return worldPosition(self)+worldRotation(self)*v(point.x*self.scale.x,point.y*self.scale.y,point.z*self.scale.z) end
function N:Remove() assert(not self.removed,"double node removal"); self.removed=true end

-- Record the public immediate-mode API; no GPU/render/job-system simulation.
function M.CustomGeometry(node,options)
    options=options or {}
    local geom={node=node,vertices={},commits=0,queries=0}
    function geom:BeginGeometry(index,kind) assert(index==0 and kind==TRIANGLE_LIST) end
    function geom:DefineVertex(position) self.vertices[#self.vertices+1]={position=position} end
    function geom:DefineNormal(normal) self.vertices[#self.vertices].normal=normal end
    function geom:DefineColor(color) self.vertices[#self.vertices].color=color end
    function geom:SetMaterial(index,material)
        assert(index==0 and material and self.commits>0,'match BlockCharacter: Commit before SetMaterial')
        if options.materialThrow then error('SetMaterial binding failure') end
        if options.materialFalse then return false end
        self.material=material;return true
    end
    function geom:GetMaterial(index) assert(index==0);return self.material end
    function geom:Commit()
        if options.commitThrow then error('Commit binding failure') end
        self.commits=self.commits+1
        local lo,hi=v(math.huge,math.huge,math.huge),v(-math.huge,-math.huge,-math.huge)
        for _,vertex in ipairs(self.vertices) do for _,axis in ipairs({'x','y','z'}) do
            lo[axis]=math.min(lo[axis],vertex.position[axis]);hi[axis]=math.max(hi[axis],vertex.position[axis])
        end end
        self.boundingBox={min=lo,max=hi}
        if options.commitFalse then return false end
        -- Native Commit is void. Do not return a truthy fake success.
    end
    function geom:GetNumVertices(index)
        assert(index==0 and self.commits>0);self.queries=self.queries+1
        if options.countThrow then error('GetNumVertices binding unavailable') end
        return (self.empty or self.queries<=(options.zeroQueries or 0)) and 0 or #self.vertices
    end
    return geom
end
function N:CreateComponent(kind)
    assert(kind=='CustomGeometry','preview must not create '..kind)
    return M.CustomGeometry(self)
end

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
        local volume={node=node,grid=grid,dimensions={dx,dy,dz},vertexCount=0}
        volume.GetNode=function() return node end
        volume.GetGrid=function() return grid end
        -- Only model readiness, not actual greedy-mesh vertex/face counts.
        volume.RebuildGeometry=function() self.rebuilds=self.rebuilds+1;volume.vertexCount=4 end
        volume.GetVertexCount=function() return volume.vertexCount end
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
