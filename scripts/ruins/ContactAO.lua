-- Material AO for the permanent colonnade and stairs. No render-path changes,
-- GPU resources, events, logs or per-frame geometry. Caller owns all materials.
local Terrain=require('ruins.RuinsTerrain')
local Build=require('ruins.RuinsBuild')
---@class RuinsContactAO
local M={}
M.__index=M

---@param materials table<string,Material>
---@param ground Material|nil
function M.New(materials,ground)
    local self=setmetatable({},M)
    self:Init(materials,ground)
    return self
end

---@param materials table<string,Material>
---@param ground Material|nil
function M:Init(materials,ground)
    -- Weak references do not extend the lifetime of scene-owned materials.
    ---@type table<string,Material>
    self.materials=setmetatable({},{__mode='v'})
    for key,material in pairs(materials or {}) do
        if key~='gateRubble' then self.materials[key]=material end
    end
    self.materials.ground=ground
    self.strength,self.lastStrength,self.day=0,-1,1
    self.disposed=false
    local radius=Build.COLONNADE_R
    local clear=Terrain.STAIR_HALF+0.7+1.25
    self.layoutSupported=radius>clear
    -- Fail closed if the actual permanent layout diverges from the bounded
    -- shader nearest-three formula; do not project an imaginary pillar base.
    for i=0,23 do
        local angle=(i+0.5)/24*math.pi*2
        local x,z=math.cos(angle)*radius,math.sin(angle)*radius
        if math.abs(x)<clear and math.abs(z)>radius*.9 then
            x=(x<0 and -1 or 1)*clear
            z=(z<0 and -1 or 1)*math.sqrt(radius*radius-clear*clear)
        end
        local actual=Build.ColAngle(i)
        if math.abs(x-math.cos(actual)*radius)>.001 or math.abs(z-math.sin(actual)*radius)>.001 then self.layoutSupported=false end
    end
    local columns=Variant(Vector4(radius,Terrain.RING_Y,1.2,clear))
    local stairs=Variant(Vector4(Terrain.COURT_R,Terrain.STAIR_HALF,Terrain.STAIR_END,Terrain.STAIR_JOIN))
    for _,material in pairs(self.materials) do
        material:SetShaderParameter('contact_columns',columns)
        material:SetShaderParameter('contact_stairs',stairs)
    end
end

function M:SetQuality(profile,day)
    if self.disposed then return end
    self.strength=self.layoutSupported and math.max(0,math.min(.32,profile.contactAO or 0)) or 0
    local far=math.max(20,profile.contactAODistance or 42)
    local distance=Variant(Vector2(far*.45,far))
    for _,material in pairs(self.materials) do material:SetShaderParameter('contact_ao_distance',distance) end
    self.lastStrength=-1
    self:Apply(day)
end

function M:Apply(day)
    if self.disposed then return end
    local d=math.max(0,math.min(1,((day or 0)-.15)/.55))
    local strength=self.strength*d*d*(3-2*d)
    -- Steady noon/night/low: no material walk or Variant creation. Quantized
    -- twilight writes stay below 0.2% IBL occlusion, but exact zero is immediate.
    if strength==self.lastStrength or (strength>0 and math.abs(strength-self.lastStrength)<.002) then return end
    self.lastStrength=strength
    local value=Variant(strength)
    for _,material in pairs(self.materials) do material:SetShaderParameter('contact_ao_strength',value) end
end

function M:Dispose()
    if self.disposed then return end
    self.strength=0;self:Apply(0)
    self.disposed=true
    self.materials={}
end
return M
