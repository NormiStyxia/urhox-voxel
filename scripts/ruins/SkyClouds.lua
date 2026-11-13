-- 两批静态卡片云：高云/岛外低云各一批；GPU 偏航 billboard，不逐帧改顶点。
local logOK,DebugLog = pcall(require,"ruins.DebugLog")
if not logOK then DebugLog=nil end
---@class RuinsSkyClouds
local M = {}
M.__index = M

---@param g CustomGeometry
---@param center Vector3 整朵云的共同旋转中心；XZ 为偶数米，Y 为整数米
---@param slot integer 图集格 1..4，先左后右、先上后下
local function Card(g,center,slot,w,h,tilt,dx,dy,dz,bottom)
    -- CustomGeometry 只有一套 UV。COLOR 是 RGBA8：中心整数编码无量化漂移，A 区分底片。
    -- +0.25 byte 避免 float 到 RGBA8 的截断误差；shader 先 round 字节再解码。
    local data = Color(((center.x+256)/2+0.25)/255,(center.y+128+0.25)/255,((center.z+256)/2+0.25)/255,bottom and 0.5 or 1)
    local u0,v0 = ((slot-1)%2)*0.5,math.floor((slot-1)/2)*0.5
    local rise,depth = math.sin(tilt)*h,math.cos(tilt)*h
    -- 高云由下方看，低云由上方看；倾斜方向朝常用视点展开，避免约 28° 仰角恰好侧成细线。
    if center.y>0 then depth=-depth end
    for _,uv in ipairs({{0,0},{0,1},{1,1},{0,0},{1,1},{1,0}}) do
        local sx,sy = uv[1]*2-1,1-uv[2]*2
        g:DefineVertex(Vector3(center.x+dx+sx*w,center.y+dy+sy*rise,center.z+dz-sy*depth))
        g:DefineNormal(Vector3(0,depth/h,rise/h))
        g:DefineColor(data)
        -- 一像素 inset，禁止图集格之间的线性采样串色。
        g:DefineTexCoord(Vector2(u0+(1+uv[1]*510)/1024,v0+(1+uv[2]*510)/1024))
    end
end

---@param g CustomGeometry
local function Bounds(g,lower)
    -- Shader 位移不会扩展 CPU 包围盒；两条退化三角形覆盖全部偏航角，不产生片元。
    for _,p in ipairs({Vector3(-210,lower and -72 or 48,-210),Vector3(210,lower and -18 or 110,210)}) do
        for _=1,3 do
            g:DefineVertex(p); g:DefineNormal(Vector3.UP)
            g:DefineColor(Color(0,0,0,0)); g:DefineTexCoord(Vector2(0,0))
        end
    end
end

---@param scene Scene
function M.New(scene,count,upper,lower)
    local self = setmetatable({},M)
    self:Init(scene,count or 24,upper~=false,lower~=false)
    return self
end

---@param scene Scene
function M:Init(scene,count,upper,lower)
    self.budget = math.max(0,math.min(24,math.floor(count)))
    self.upper,self.lower,self.count,self.batchCount = upper,lower,0,0
    self.cardCount,self.triangleCount,self.disposed = 0,0,false
    ---@type Node|nil
    self.root = nil
    ---@type Material|nil
    self.material = nil
    ---@type table<number, Node>
    self.layers = {}
    ---@type table<number, CustomGeometry>
    self.geometry = {}
    self.elapsed = 0
    self.position = Vector3.ZERO
    self.fallback,self.unavailable = false,false
    if self.budget==0 or not (upper or lower) then return end
    local source = cache:GetResource("Material","Materials/RuinsCloud.xml")
    self.material = source and source:Clone() or Material:new()
    if not source and not self.material:SetSurfaceShader("Shaders/BLGL/RuinsCloud.shader") then
        -- Shader 本身不可用时安全隐藏；绝不把缺 shader 的卡片绘成白块。
        self.unavailable=true
        self.material:Dispose(); self.material=nil
        if DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud shader unavailable; clouds hidden") end
        return
    end
    local texture = cache:GetResource("Texture2D","Textures/Sky/cloud_flat_atlas.png")
    self.fallback = texture==nil or not self.material:SetSurfaceTexture("cloud_atlas",texture)
    self.material:SetShaderParameter("use_atlas",Variant(self.fallback and 0 or 1))
    if self.fallback and DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud atlas unavailable; analytic round cards") end
    self.root = scene:CreateChild("SkyClouds")
    ---@type table<number, CustomGeometry>
    local geometries = self.geometry
    for layer=1,3 do
        local amount = math.floor(self.budget/3)+(layer<=self.budget%3 and 1 or 0)
        if amount>0 and ((layer==3 and lower) or (layer~=3 and upper)) then
        local batch = layer==3 and 2 or 1
        local g = geometries[batch]
        if not g then
            local node = self.root:CreateChild(batch==1 and "UpperClouds" or "LowerClouds")
            g = node:CreateComponent("CustomGeometry")
            g:BeginGeometry(0,TRIANGLE_LIST)
            self.layers[batch],self.geometry[batch] = node,g
            self.batchCount = self.batchCount+1
        end
        for i=1,amount do
            local a = (i/amount+layer*0.19)*math.pi*2
            -- 低云在岛外，不把裂隙填成白色地板；高云部分越过主岛。
            local radius = layer==3 and (100+i*5) or (i%3==0 and 32 or 86+i*8)
            local x,z = math.cos(a)*radius,math.sin(a)*radius
            local y = layer==3 and (-35-i*2) or (51+layer*13+(i%3)*4)
            local size = layer==3 and 1.4 or 1.0
            local center = Vector3(math.floor(x/2+0.5)*2,math.floor(y+0.5),math.floor(z/2+0.5)*2)
            local slot = (i+layer)%4+1
            -- 后片、近水平底片、主片；三种格、略错位，主片距水平面 28 度。
            Card(g,center,slot,17*size,9*size,0.35,-3*size,1*size,-3*size,false)
            Card(g,center,slot%4+1,19*size,10*size,0.06,0,-2*size,0,true)
            Card(g,center,(slot+1)%4+1,20*size,11*size,0.49,2*size,0,2*size,false)
        end
        self.count = self.count+amount
        end
    end
    for batch,g in pairs(self.geometry) do
        Bounds(g,batch==2)
        g:Commit(); g:SetMaterial(self.material)
        g.castShadows,g.occluder = false,false
        g.drawDistance = 390
    end
    self.cardCount,self.triangleCount = self.count*3,self.count*6+self.batchCount*2
end

function M:Dispose()
    if self.disposed then return end
    self.disposed=true
    if self.root then self.root:Dispose() end
    self.layers,self.geometry = {},{}
    if self.material then self.material:Dispose() end
end

-- 宿主 5Hz 调用；只移动整批节点，不重建网格。不可见批次不写 transform。
function M:Update(dt,day,dusk)
    if self.disposed or self.count==0 or not self.material then return end
    self.elapsed = self.elapsed+dt
    for i,node in pairs(self.layers) do
        local g = self.geometry[i]
        if node.enabled and g and g.inView then
            local p = self.position
            p.x,p.z = math.sin(self.elapsed*0.009+i)*9,math.sin(self.elapsed*0.006+i)*5
            node.position = p
        end
    end
    -- 转头/重新启用时也必须显示当前时段。
    self.material:SetShaderParameter("day",Variant(math.max(0,math.min(1,day))))
    self.material:SetShaderParameter("dusk",Variant(math.max(0,math.min(1,dusk))))
end

return M
