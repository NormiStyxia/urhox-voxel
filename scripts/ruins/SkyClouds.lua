-- 三批静态体素云：两批高云、一批岛外低云，共享一个材质，不参与阴影/碰撞。
local logOK,DebugLog = pcall(require,"ruins.DebugLog")
if not logOK then DebugLog=nil end
---@class RuinsSkyClouds
local M = {}
M.__index = M

---@param g CustomGeometry
---@param a Vector3
---@param b Vector3
---@param c Vector3
---@param d Vector3
---@param normal Vector3
local function Face(g,a,b,c,d,normal,shade)
    local color = Color(shade,shade,shade,1)
    for _,p in ipairs({a,b,c,a,c,d}) do
        g:DefineVertex(p); g:DefineNormal(normal); g:DefineColor(color)
    end
end

---@param g CustomGeometry
local function Box(g, x,y,z,w,h,d)
    local a,b = Vector3(x-w,y-h,z-d),Vector3(x+w,y-h,z-d)
    local c,e = Vector3(x+w,y+h,z-d),Vector3(x-w,y+h,z-d)
    local f,h1 = Vector3(x-w,y-h,z+d),Vector3(x+w,y-h,z+d)
    local j,k = Vector3(x+w,y+h,z+d),Vector3(x-w,y+h,z+d)
    Face(g,a,e,c,b,Vector3(0,0,-1),0.83)
    Face(g,f,h1,j,k,Vector3(0,0,1),0.91)
    Face(g,a,f,k,e,Vector3(-1,0,0),0.86)
    Face(g,b,c,j,h1,Vector3(1,0,0),0.94)
    Face(g,e,k,j,c,Vector3.UP,1.00)
    Face(g,a,b,h1,f,Vector3(0,-1,0),0.71)
end

---@param scene Scene
function M.New(scene,count,upper,lower)
    local self = setmetatable({},M)
    self:Init(scene,count or 24,upper~=false,lower~=false)
    return self
end

---@param scene Scene
function M:Init(scene,count,upper,lower)
    self.budget = math.max(1,math.min(24,math.floor(count)))
    self.upper,self.lower,self.count,self.batchCount = upper,lower,0,0
    self.root = scene:CreateChild("SkyClouds")
    local source = cache:GetResource("Material","Materials/RuinsCloud.xml")
    self.fallback = source==nil
    self.material = source and source:Clone() or Material:new()
    if not source then
        if DebugLog and DebugLog.enabled then DebugLog.Log("SkyFx","cloud shader unavailable; using unlit fallback") end
        self.material:SetTechnique(0,cache:GetResource("Technique","Techniques/NoTextureUnlit.xml"))
    end
    ---@type Node[]
    self.layers = {}
    ---@type CustomGeometry[]
    self.geometry = {}
    self.elapsed = 0
    self.position = Vector3.ZERO
    for layer=1,3 do
        local amount = math.floor(self.budget/3)+(layer<=self.budget%3 and 1 or 0)
        if amount>0 and ((layer==3 and lower) or (layer~=3 and upper)) then
        local node = self.root:CreateChild("CloudLayer"..layer)
        local g = node:CreateComponent("CustomGeometry")
        g:BeginGeometry(0,TRIANGLE_LIST)
        for i=1,amount do
            local a = (i/amount+layer*0.19)*math.pi*2
            -- 低云在岛外，不把裂隙填成白色地板；高云部分越过主岛。
            local radius = layer==3 and (100+i*5) or (i%3==0 and 32 or 86+i*8)
            local x,z = math.cos(a)*radius,math.sin(a)*radius
            local y = layer==3 and (-35-i*2) or (51+layer*13+(i%3)*4)
            local size = layer==3 and 1.4 or 1.0
            for lobe=1,5 do
                local lx = (lobe-3)*4.8*size
                local lz = math.sin(lobe*2.1+i)*3.0*size
                local crown = 1.8+(3-math.abs(lobe-3))*0.9
                Box(g,x+lx,y+crown*0.35,z+lz,(4.1+lobe%2)*size,crown*size,(3.3+lobe%3)*size)
            end
        end
        g:Commit(); g:SetMaterial(self.material)
        g.castShadows,g.occluder = false,false
        g.drawDistance = 390
        self.layers[layer],self.geometry[layer] = node,g
        self.count,self.batchCount = self.count+amount,self.batchCount+1
        end
    end
end

function M:Dispose()
    self.root:Dispose()
    self.layers,self.geometry = {},{}
    self.material:Dispose()
end

-- 宿主 5Hz 调用；只移动整批节点，不重建网格。不可见批次不写 transform。
function M:Update(dt,day,dusk)
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
    self.material:SetShaderParameter("day",Variant(day))
    self.material:SetShaderParameter("dusk",Variant(dusk))
    if self.fallback then
        self.material:SetShaderParameter("MatDiffColor",Variant(Color(0.10+day*0.75,0.16+day*0.72,0.28+day*0.65,1)))
    end
end

return M
