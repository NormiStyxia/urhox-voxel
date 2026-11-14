-- 有限三维密度射线积分：静态离线体数据、单次透明合成、运行期只更新少量uniform。
local logOK,DebugLog = pcall(require,"ruins.DebugLog")
if not logOK then DebugLog=nil end
---@class RuinsSkyClouds
local M = {}
M.__index = M

-- 密度在 validation/sky-fx/bake_density.py 离线烘焙；游戏中不生成等值面。
local function Finite(v,default,lo,hi)
    if type(v)~="number" or v~=v or v==math.huge or v==-math.huge then return default end
    return math.max(lo,math.min(hi,v))
end

---@param scene Scene
function M.New(scene,count,upper,lower)
    local self = setmetatable({},M)
    self:Init(scene,count or 24,upper~=false,lower~=false)
    return self
end

---@param scene Scene
function M:Init(scene,count,upper,lower)
    self.budget = math.floor(Finite(count,0,0,24))
    self.horizonOnly=self.budget>0 and self.budget<=4
    self.upper,self.lower,self.count,self.batchCount = upper,lower,0,0
    self.triangleCount,self.disposed,self.ready,self.baking = 0,false,false,false
    self.bakeSlices,self.shapeCount,self.readyCount = 0,0,0
    ---@type Scene|nil
    self.scene=scene
    ---@type Node|nil
    self.root=nil
    ---@type Material|nil
    self.material=nil
    ---@type Texture2D|nil 缓存借用，Dispose只释放引用，不能销毁共享资源
    self.texture=nil
    ---@type Texture2D|nil
    self.occupancy=nil
    ---@type table<number, Node>
    self.layers={}
    ---@type table<number, CustomGeometry>
    self.geometry={}
    self.elapsed=0
    self.fallback,self.unavailable=false,false
    self.viewSteps=self.budget>12 and 64 or (self.horizonOnly and 16 or 24)
    self.traversalSteps=self.budget>12 and 96 or (self.horizonOnly and 16 or 80)
    self.lightSteps=self.horizonOnly and 0 or 1
    if self.budget==0 or not (upper or lower) or (self.horizonOnly and not upper) then return end
    local source=cache:GetResource("Material","Materials/RuinsCloud.xml")
    self.material=source and source:Clone() or Material:new()
    -- 编译/资源错误时不拿默认白材质画全屏。异步GPU编译仍须Web日志验收。
    if not self.material:SetSurfaceShader("Shaders/BLGL/RuinsCloud.shader") then
        self.unavailable=true;self.material:Dispose();self.material=nil
        if DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","volume shader unavailable; cloud pass disabled") end
        return
    end
    if self.horizonOnly then
        self.texture=cache:GetResource("Texture2D","Textures/Sky/cloud_density_low.png")
    else
        self.texture=cache:GetResource("Texture2D","Textures/Sky/cloud_density.png")
    end
    if self.texture then self.texture.sRGB=false end
    local width,height=self.horizonOnly and 2048 or 4096,self.horizonOnly and 256 or 1536
    local bound=self.texture~=nil and self.texture.width==width and self.texture.height==height
        and self.material:SetSurfaceTexture("density_volume",self.texture)
    local occupancyBound=false
    if bound and not self.horizonOnly then
        self.occupancy=cache:GetResource("Texture2D","Textures/Sky/cloud_occupancy.png")
        if self.occupancy then
            self.occupancy.sRGB=false
            occupancyBound=self.occupancy.width==256 and self.occupancy.height==128
                and self.material:SetSurfaceTexture("occupancy_volume",self.occupancy)
        end
    end
    self.material:SetShaderParameter("use_occupancy",Variant(occupancyBound and 1 or 0))
    self.material:SetShaderParameter("volume_dims",Variant(self.horizonOnly and Vector3(128,32,128) or Vector3(256,96,256)))
    self.material:SetShaderParameter("atlas_dims",Variant(Vector2(width,height)))
    self.fallback=not bound
    self.material:SetShaderParameter("use_volume",Variant(bound and 1 or 0))
    self.material:SetShaderParameter("quality_channel",Variant(self.budget>12 and 0 or (self.horizonOnly and 2 or 1)))
    self.material:SetShaderParameter("view_steps",Variant(self.viewSteps))
    self.material:SetShaderParameter("traversal_steps",Variant(self.traversalSteps))
    self.material:SetShaderParameter("light_steps",Variant(self.lightSteps))
    self.material:SetShaderParameter("upper_enabled",Variant(upper and 1 or 0))
    self.material:SetShaderParameter("lower_enabled",Variant(lower and not self.horizonOnly and 1 or 0))
    self.material:SetShaderParameter("horizon_only",Variant(self.horizonOnly and 1 or 0))
    self.material:SetShaderParameter("diagnostic",Variant(0))
    self.root=scene:CreateChild("SkyClouds")
    local node=self.root:CreateChild("CloudDensityPass")
    local g=node:CreateComponent("CustomGeometry")
    -- 一个屏幕三角形只启动积分，不代表云形。CPU包围盒覆盖可见云域；无逐帧顶点上传。
    -- vertex()把UV反投影至近面，Z_CLIP_SCALE=0使用引擎跨后端近裁面语义。
    g:BeginGeometry(0,TRIANGLE_LIST)
    local positions={Vector3(-1024,-1024,-1024),Vector3(1024,-1024,1024),Vector3(-1024,1024,1024)}
    local uvs={Vector2(0,0),Vector2(2,0),Vector2(0,2)}
    for i=1,3 do
        g:DefineVertex(positions[i]);g:DefineNormal(Vector3.UP);g:DefineTexCoord(uvs[i])
    end
    g:Commit();g:SetMaterial(self.material)
    g.castShadows,g.occluder=false,false
    self.layers[1],self.geometry[1]=node,g
    local lowerCount=self.horizonOnly and 0 or math.floor(self.budget/3)
    self.count=(upper and self.budget-lowerCount or 0)+(lower and lowerCount or 0)
    if self.fallback then self.count=(upper and 2 or 0)+(lower and not self.horizonOnly and 2 or 0) end
    self.shapeCount=self.fallback and 1 or 6
    self.triangleCount,self.batchCount,self.readyCount,self.ready=1,1,self.count,true
    if self.fallback and DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","density resource unavailable; bounded analytic 3D medium") end
end

-- 保留旧宿主调用兼容性；静态密度即时就绪，没有分帧烘焙任务。
function M:StepBake() end

function M:Dispose()
    if self.disposed then return end
    self.disposed,self.baking,self.ready=true,false,false
    self.texture=nil
    self.occupancy=nil
    self.scene=nil
    if self.root then self.root:Dispose() end
    self.layers,self.geometry = {},{}
    if self.material then self.material:Dispose() end
end

-- 宿主5Hz；密度坐标缓慢漂移，GPU不重建网格/体纹理，不创建日志字符串。
function M:Update(dt,day,dusk,dn)
    if self.disposed or not self.material then return end
    -- 四个漂移频率的共同周期，重置时相位连续且uniform长期有界。
    self.elapsed = (self.elapsed+Finite(dt,0,0,1))%(10000*math.pi)
    self.material:SetShaderParameter("drift_time",Variant(self.elapsed))
    -- 转头/重新启用时也必须显示当前时段。
    self.material:SetShaderParameter("day",Variant(Finite(day,1,0,1)))
    self.material:SetShaderParameter("dusk",Variant(Finite(dusk,0,0,1)))
    if dn and dn.sky then
        self.material:SetShaderParameter("sky_top",Variant(dn.sky.skyTopColor))
        self.material:SetShaderParameter("sky_horizon",Variant(dn.sky.skyHorizonColor))
    end
    if dn and dn.zone then
        self.material:SetShaderParameter("fog_start",Variant(Finite(dn.zone.depthFogStart,100,0,1000)))
        self.material:SetShaderParameter("fog_end",Variant(Finite(dn.zone.depthFogEnd,300,1,1200)))
    end
end

return M
