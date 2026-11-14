-- One world-space quad batch. Terrain is sampled only when a faded-out patch
-- is recycled; flight, breathing and extinction are entirely shader driven.
local Terrain=require("ruins.RuinsTerrain")
---@class RuinsFireflies
local M={}
M.__index=M
local function Smooth(x) x=math.max(0,math.min(1,x));return x*x*(3-2*x) end
local function Hash(x) local v=math.sin(x*127.1+311.7)*43758.5453;return v-math.floor(v) end

-- The complete +/-0.45m XZ flight footprint must lie on a permanent, nearly
-- level island surface. Excludes stairs, cliff lips and the court's 6m step.
function M.SafeHeight(x,z)
    if not Terrain.HasGround(x,z,1.5) then return nil end
    local h=Terrain.GroundHeight(x,z)
    if not h or not Terrain.IsSafeGround(x,h,z) then return nil end
    for ix=-2,2 do for iz=-2,2 do
        local sx,sz=x+ix*0.4,z+iz*0.4
        local y=Terrain.GroundHeight(sx,sz)
        if not y or math.abs(y-h)>0.30 or not Terrain.IsSafeGround(sx,y,sz) then return nil end
    end end
    return h
end

function M.Wrap(value,center) return center+(value-center+20)%40-20 end
function M.NightLevel(night) return Smooth(((night or 0)-0.18)/0.72) end

---@param scene Scene
function M.New(scene,count)
    local self=setmetatable({},M)
    self:Init(scene,count)
    return self
end

---@param scene Scene
function M:Init(scene,count)
    self.count=math.max(0,math.min(60,math.floor(count or 0)))
    self.liveCount,self.batchCount,self.rebuilds=0,0,0
    self.ready,self.disposed,self.built=false,false,false
    self.fade,self.level,self.centerX,self.centerZ=0,0,0,0
    self.recycling=false
    self.anchors={}
    ---@type Node|nil
    self.node=nil
    ---@type CustomGeometry|nil
    self.geometry=nil
    ---@type Material|nil
    self.material=nil
    if self.count==0 then return end
    cache:GetResourceAsync("Material","Materials/RuinsFireflies.xml",function(source)
        ---@cast source Material|nil
        if self.disposed or not source then return end
        self.material=source:Clone()
        self.node=scene:CreateChild("NightGroundFireflies")
        self.node.enabled=false
        self.geometry=self.node:CreateComponent("CustomGeometry")
        self.geometry.castShadows,self.geometry.occluder,self.geometry.occludee=false,false,false
        self.geometry.drawDistance=90
        self.ready=true
    end)
end

-- Whole-batch replacement is rare (8m player travel), never a per-frame
-- particle update. Wrap old anchors first, then reject unsafe destinations.
---@param position Vector3
function M:Rebuild(position)
    local g=self.geometry
    if not g then return end
    self.centerX,self.centerZ=position.x,position.z
    self.liveCount=0
    g:BeginGeometry(0,TRIANGLE_LIST)
    local uv={Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)}
    local order={1,2,3,1,3,4}
    for i=1,self.count do
        local old=self.anchors[i]
        local x=old and M.Wrap(old.x,position.x) or position.x+(Hash(i*3)-0.5)*40
        local z=old and M.Wrap(old.z,position.z) or position.z+(Hash(i*3+1)-0.5)*40
        local h
        for attempt=0,24 do
            if (x-position.x)^2+(z-position.z)^2<26^2 then h=M.SafeHeight(x,z) end
            if h then break end
            x=position.x+(Hash(i*83+attempt*17+self.rebuilds)-0.5)*40
            z=position.z+(Hash(i*97+attempt*31+self.rebuilds)-0.5)*40
        end
        if h then
            local at=Vector3(x,h+1.2+Hash(i+17)*0.4,z)
            self.anchors[i]=at
            self.liveCount=self.liveCount+1
            for _,k in ipairs(order) do
                g:DefineVertex(at);g:DefineNormal(Vector3.UP)
                g:DefineTexCoord(uv[k]);g:DefineColor(Color(Hash(i),Hash(i+9),Hash(i+29),1))
            end
        else self.anchors[i]=nil end
    end
    -- Invisible degenerate triangles extend CPU bounds over shader flight.
    for _,s in ipairs({-1,1}) do for _=1,3 do
        g:DefineVertex(Vector3(position.x+s*30,-2+(s+1)*6,position.z+s*30))
        g:DefineNormal(Vector3.UP);g:DefineTexCoord(Vector2.ZERO);g:DefineColor(Color(0,0,0,0))
    end end
    g:Commit();g:SetMaterial(self.material)
    self.batchCount=self.liveCount>0 and 1 or 0
    self.rebuilds,self.built=self.rebuilds+1,true
end

---@param position Vector3
function M:Update(dt,position,night,clock)
    if self.disposed or not self.ready or self.count==0 then return end
    self.level=M.NightLevel(night)
    if self.level<=0 then
        self.node.enabled=false
        self.fade=0
        return
    end
    local dx,dz=position.x-self.centerX,position.z-self.centerZ
    if self.built and dx*dx+dz*dz>64 then self.recycling=true end
    local step=math.max(0,math.min(0.1,dt))/0.45
    if self.recycling then self.fade=math.max(0,self.fade-step)
    else self.fade=math.min(1,self.fade+step) end
    if not self.built or (self.recycling and self.fade==0) then
        self:Rebuild(position)
        self.fade,self.recycling=0,false
    end
    self.node.enabled=self.liveCount>0 and self.fade>0
    if not self.node.enabled then return end
    self.material:SetShaderParameter("flight_time",Variant(clock))
    self.material:SetShaderParameter("player_center",Variant(position))
    self.material:SetShaderParameter("night_strength",Variant(self.level*Smooth(self.fade)))
end

function M:Dispose()
    if self.disposed then return end
    self.disposed,self.ready=true,false
    if self.node then self.node:Dispose() end
    if self.material then self.material:Dispose() end
    self.node,self.geometry,self.material=nil,nil,nil
    self.anchors={}
    self.liveCount,self.batchCount=0,0
end
return M
