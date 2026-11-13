-- 单个原生粒子批次：世界空间漂浮，发射器跟随玩家，远离/传送立即回收。
---@class RuinsFloatingMotes
local M = {}
M.__index = M

---@param scene Scene
function M.New(scene,count)
    local self = setmetatable({},M)
    self:Init(scene,count or 80)
    return self
end

---@param scene Scene
function M:Init(scene,count)
    self.node = scene:CreateChild("AmbientFloatingMotes")
    self.node.enabled = false
    self.lastPosition,self.position = Vector3.ZERO,Vector3.ZERO
    self.active,self.count = false,math.max(1,math.min(120,math.floor(count)))
    -- 软圆点程序化纹理，仅初始化生成；沿用官方粒子示例的贴图 technique。
    local img = Image()
    img:SetSize(16,16,4)
    for y=0,15 do for x=0,15 do
        local dx,dy = (x-7.5)/7.5,(y-7.5)/7.5
        local a = math.max(0,1-dx*dx-dy*dy)^2
        img:SetPixel(x,y,Color(1,1,1,a))
    end end
    self.texture = Texture2D:new()
    self.texture:SetData(img,true)
    img:Dispose()
    self.material = Material:new()
    self.material:SetTechnique(0,cache:GetResource("Technique","Techniques/DiffUnlitParticleAdd.xml"))
    self.material:SetTexture(TU_DIFFUSE,self.texture)
    local effect = ParticleEffect:new()
    self.effect = effect
    effect.material,effect.numParticles = self.material,self.count
    effect.emitterType,effect.emitterSize = EMITTER_BOX,Vector3(18,6,18)
    effect.minDirection,effect.maxDirection = Vector3(-0.25,0.3,-0.15),Vector3(0.3,1,0.25)
    effect.minVelocity,effect.maxVelocity = 0.06,0.22
    effect.minTimeToLive,effect.maxTimeToLive = 6,6
    effect.minParticleSize,effect.maxParticleSize = Vector2(0.025,0.025),Vector2(0.065,0.065)
    effect.minEmissionRate,effect.maxEmissionRate = self.count/6,self.count/6
    effect.relative,effect.sorted,effect.updateInvisible = false,false,false
    effect:SetNumColorFrames(0)
    effect:AddColorTime(Color(1,0.93,0.65,0),0)
    effect:AddColorTime(Color(1,0.93,0.65,0.45),1)
    effect:AddColorTime(Color(0.72,0.84,1,0),6)
    self.emitter = self.node:CreateComponent("ParticleEmitter")
    self.emitter.effect = effect
    self.emitter.castShadows,self.emitter.occluder = false,false
    self.emitter.drawDistance = 40
end

function M:Dispose()
    self.emitter:RemoveAllParticles()
    self.node:Dispose()
    self.effect:Dispose()
    self.material:Dispose()
    self.texture:Dispose()
end

---@param position Vector3
function M:Update(position,enabled,day)
    if not enabled then
        if self.active then self.emitter:RemoveAllParticles() end
        self.active,self.node.enabled = false,false
        return
    end
    local previous = self.lastPosition
    local dx,dy,dz = position.x-previous.x,position.y-previous.y,position.z-previous.z
    -- 距上次回收中心 6m 即清旧粒子，骑龙/回安全点不留无限拖尾。
    if not self.active or dx*dx+dy*dy+dz*dz>36 then
        self.emitter:RemoveAllParticles()
        self.lastPosition = position
    end
    local p = self.position
    p.x,p.y,p.z = position.x,position.y+3.2,position.z
    self.node.position = p
    self.node.enabled,self.active = true,true
    self.material:SetShaderParameter("MatDiffColor",Variant(Color(0.35+day*0.65,0.48+day*0.46,0.85,1)))
end

return M
