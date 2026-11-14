-- 天空空间曲面云片：原创多通道烘焙图、普通深度测试，不读取屏幕深度。
local logOK,DebugLog = pcall(require,"ruins.DebugLog")
if not logOK then DebugLog=nil end
---@class RuinsSkyClouds
local M = {}
M.__index = M

-- 图集在 validation/sky-fx/bake_sky_atlas.py 离线烘焙；游戏不运行体积积分。
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

-- Spherical 2x2-cell patches, authored once. Camera stays at their centre.
-- CustomGeometry is needed for per-patch atlas UV and packed drift/haze attributes.
local function AddPatch(g,yaw,elevation,width,radius,tile,speed,haze)
    local sy,cy,se,ce=math.sin(yaw),math.cos(yaw),math.sin(elevation),math.cos(elevation)
    local cx,cz=sy*ce,cy*ce
    local tangent=math.tan(width*0.5)
    local normal=Vector3(cx,se,cz)
    local color=Color(speed,0,haze,1)
    local function vertex(u,v)
        local x=cx+cy*u*tangent-sy*se*v*tangent
        local y=se+ce*v*tangent
        local z=cz-sy*u*tangent-cy*se*v*tangent
        local length=math.sqrt(x*x+y*y+z*z)
        g:DefineVertex(Vector3(x/length*radius,y/length*radius,z/length*radius))
        g:DefineNormal(normal);g:DefineColor(color)
        -- Half-texel-safe interior; every cell also has >20px transparent gutter.
        g:DefineTexCoord(Vector2(((tile%4)+0.004+(u+1)*0.496)/4,
            (math.floor(tile/4)+0.004+(1-v)*0.496)/2))
    end
    for row=1,2 do
        for col=1,2 do
            local u,v=col-2,row-2
            vertex(u,v);vertex(u+1,v);vertex(u,v+1)
            vertex(u+1,v);vertex(u+1,v+1);vertex(u,v+1)
        end
    end
end

---@param scene Scene
function M:Init(scene,count,upper,lower)
    self.budget=math.floor(Finite(count,0,0,24))
    self.horizonOnly=self.budget>0 and self.budget<=4
    self.upper,self.lower,self.count,self.batchCount=upper,lower,0,0
    self.triangleCount,self.disposed,self.ready,self.baking=0,false,false,false
    self.bakeSlices,self.shapeCount,self.readyCount=0,0,0
    ---@type Scene|nil
    self.scene=scene
    ---@type Node|nil
    self.root=nil
    ---@type Material|nil
    self.material=nil
    ---@type Texture2D|nil 缓存借用，不销毁共享纹理
    self.texture=nil
    ---@type table<number, Node>
    self.layers={}
    ---@type table<number, CustomGeometry>
    self.geometry={}
    ---@type number
    self.elapsed=0
    self.fallback,self.unavailable=false,false
    self.textureReads=1
    if self.budget==0 or not (upper or lower) or (self.horizonOnly and not upper) then return end
    local detailed=self.budget>12
    local path=detailed and "Textures/Sky/cloud_sculpted_atlas.png" or "Textures/Sky/cloud_sculpted_atlas_low.png"
    self.texture=cache:GetResource("Texture2D",path)
    local width,height=detailed and 2048 or 1024,detailed and 1024 or 512
    if not self.texture or self.texture.width~=width or self.texture.height~=height then
        self.texture=nil;self.unavailable=true
        if DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud atlas unavailable; clouds hidden") end
        return
    end
    self.texture.sRGB=false
    local source=cache:GetResource("Material","Materials/RuinsCloud.xml")
    self.material=source and source:Clone() or Material:new()
    if not self.material:SetSurfaceShader("Shaders/BLGL/RuinsCloud.shader")
        or not self.material:SetSurfaceTexture("cloud_atlas",self.texture) then
        self.unavailable=true;self.material:Dispose();self.material=nil;self.texture=nil
        if DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud material unavailable; clouds hidden") end
        return
    end
    self.material:SetShaderParameter("cloud_enabled",Variant(1))
    self.root=scene:CreateChild("SkyClouds")
    local node=self.root:CreateChild("CelestialCloudPatches")
    local g=node:CreateComponent("CustomGeometry")
    g:BeginGeometry(0,TRIANGLE_LIST)
    local lowerCount=self.horizonOnly and 0 or math.floor(self.budget/3)
    local upperCount=self.budget-lowerCount
    local horizonCount=self.horizonOnly and upperCount or math.ceil(upperCount*0.625)
    -- Far -> near paint order is explicit within the one transparent draw.
    if upper then
        ---@type integer[]
        local tiles={1,2,4,5,0,2,1,4,3,5}
        ---@type number[]
        local bottom={0.813,0.274,0.508,0.625,0.278,0.497}
        for i=1,horizonCount do
            local tile=tiles[(i-1)%#tiles+1] or 1
            local angularWidth=self.horizonOnly and 0.72 or ((tile==0 or tile==3) and 0.40 or 0.52)
            -- Align each actual baked silhouette's bottom above the horizon.
            -- Centring a tall atlas cell at y=0 would hang half the cloud below it.
            local elevation=0.035+math.atan(math.tan(angularWidth*0.5)*(bottom[tile+1] or 0.5))+(i%2)*0.015
            AddPatch(g,(i-1)/horizonCount*math.pi*2+0.26,elevation,angularWidth,548,tile,0.25,0.9)
            self.count=self.count+1
        end
        local highCount=upperCount-horizonCount
        for i=1,highCount do
            AddPatch(g,(i-1)/highCount*math.pi*2+0.08,0.40+(i%3)*0.10,
                0.44+(i%2)*0.06,535,(i+1)%6,0.65,0.25)
            self.count=self.count+1
        end
    end
    if lower then
        for i=1,lowerCount do
            AddPatch(g,(i-1)/lowerCount*math.pi*2+0.4,-0.30-(i%3)*0.27,
                0.58+(i%2)*0.08,522,6+i%2,0.45,0.48)
            self.count=self.count+1
        end
    end
    -- Zero-area triangles enlarge CPU bounds only; no fragments. Follow() recentres
    -- those bounds on the player, while vertex() centres the visible dome on camera.
    for _,sign in ipairs({-1,1}) do
        for i=1,3 do
            g:DefineVertex(Vector3(sign*2048,sign*2048,sign*2048))
            g:DefineNormal(Vector3.UP);g:DefineColor(Color(0,0,0,0));g:DefineTexCoord(Vector2(0,0))
        end
    end
    g:Commit();g:SetMaterial(self.material)
    g.castShadows,g.occluder,g.occludee=false,false,false
    self.layers[1],self.geometry[1]=node,g
    self.shapeCount=8
    self.triangleCount,self.batchCount,self.readyCount,self.ready=self.count*8+2,1,self.count,true
end

---@param position Vector3
function M:Follow(position)
    if self.root and not self.disposed then self.root.position=position end
end

-- 保留宿主调用兼容性；静态图集即时就绪，没有运行时烘焙任务。
function M:StepBake() end

function M:Dispose()
    if self.disposed then return end
    self.disposed,self.baking,self.ready=true,false,false
    self.texture=nil
    self.scene=nil
    if self.root then self.root:Dispose() end
    self.layers,self.geometry = {},{}
    if self.material then self.material:Dispose() end
end

-- 宿主5Hz；少量uniform缓慢漂移，不更新顶点/图集，不创建日志字符串。
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
        self.material:SetShaderParameter("sky_bottom",Variant(dn.sky.groundBottomColor))
    end
end

return M
