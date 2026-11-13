-- 三束光缝合成单批双面交叉网格；仅氛围，不新建灯、不采样屏幕深度。
local logOK,DebugLog = pcall(require,"ruins.DebugLog")
if not logOK then DebugLog=nil end
---@class RuinsLightShafts
local M = {}
M.__index = M

---@param scene Scene
function M.New(scene,count)
    local self = setmetatable({},M)
    self:Init(scene,count or 8)
    return self
end

---@param scene Scene
function M:Init(scene,count)
    self.count = math.max(1,math.min(8,math.floor(count)))
    self.node = scene:CreateChild("CloudLightShafts")
    local source = cache:GetResource("Material","Materials/RuinsLightShaft.xml")
    self.available = source~=nil
    self.material = source and source:Clone() or Material:new()
    if not source and DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","shaft shader unavailable; shafts disabled") end
    self.geometry = self.node:CreateComponent("CustomGeometry")
    local g = self.geometry
    g:BeginGeometry(0,TRIANGLE_LIST)
    local anchors = {{-19,-13,3.8},{18,15,3.0},{-7,28,2.7},{28,-19,2.2},
        {-27,15,2.0},{8,-28,2.3},{-12,-30,1.8},{27,30,1.9}}
    local order = {1,2,3,1,3,4}
    for i=1,self.count do
        local a = anchors[i]
        for plane=1,2 do
            local wx,wz = plane==1 and a[3] or 0,plane==2 and a[3] or 0
            -- 岛面以上淡出；顶端朝南倾斜，根节点 yaw 跟随太阳方位。
            local p = {Vector3(a[1]-wx,7,a[2]-wz),Vector3(a[1]+wx,7,a[2]+wz),
                Vector3(a[1]+wx*0.5,52,a[2]+wz*0.5-24),Vector3(a[1]-wx*0.5,52,a[2]-wz*0.5-24)}
            local uv = {Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)}
            for _,k in ipairs(order) do
                g:DefineVertex(p[k]); g:DefineNormal(Vector3.UP); g:DefineTexCoord(uv[k])
            end
        end
    end
    g:Commit(); g:SetMaterial(self.material)
    g.castShadows,g.occluder = false,false
    g.drawDistance = 150
end

function M:Dispose()
    self.node:Dispose()
    self.material:Dispose()
end

---@param dn DayNight
function M:Update(dn,enabled,realFog)
    self.node.enabled = self.available and enabled and (dn.elev or 0)>0.16
    if not self.node.enabled then return end
    local elevation = math.max(0,math.min(1,((dn.elev or 0)-0.16)/0.25))
    self.material:SetShaderParameter("strength",Variant(elevation*(realFog and 0.35 or 1)))
    self.material:SetShaderParameter("dusk",Variant(dn.dusk or 0))
    if self.geometry.inView then
        -- 低太阳高度淡出，避免近水平的假光柱穿场。
        local direction = dn.sunNode.direction
        self.node.rotation = Quaternion(math.deg(math.atan(direction.x,direction.z)),Vector3.UP)
    end
end

return M
