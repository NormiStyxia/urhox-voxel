-- Reusable geometry: Roman dial, hand seal and bounded impact pool.
local M = {}
local S = {}; S.__index = S
-- 表盘与手印用生图素材（白线黑底，亮度即不透明度）；范围圈与冲击波由 shader 程序化画环。
local TEX = { clock='Textures/Sigils/sigil_clock.png', seal='Textures/Sigils/sigil_seal.png',
    dial='Textures/fx/clock_dial.png' }   -- dial: the AI-painted Roman clock used for every casting circle
local DIAL_SHADER='model/forge-blades/ClockTex.shader'
local function Shape(parent, name, kind)
    local node = parent:CreateChild(name)
    local mat = Material:new()
    if kind == 'dial' then
        -- Casting circles are the Roman clock (ClockTex.shader): no spin in the shader, rotation comes from the node.
        assert(mat:SetSurfaceShader(DIAL_SHADER), 'clock dial shader unavailable')
        local tex = cache:GetResource('Texture2D', TEX.dial)
        if tex ~= nil then mat:SetSurfaceTexture('tex', tex) else print('TimeSigil: missing texture '..TEX.dial) end
        mat:SetShaderParameter('spin', Variant(0.0))
        mat:SetShaderParameter('billboard', Variant(0.0))
    else
        assert(mat:SetSurfaceShader('Shaders/BLGL/TimeSigil.shader'), 'TimeSigil shader unavailable')
        if kind ~= nil then
            local tex = cache:GetResource('Texture2D', TEX[kind])
            if tex ~= nil then
                mat:SetSurfaceTexture('sigil_tex', tex)
                mat:SetShaderParameter('use_tex', Variant(1.0))
            else
                print('TimeSigil: missing texture '..TEX[kind])
            end
        end
    end
    local g = node:CreateComponent('CustomGeometry')
    g:BeginGeometry(0, TRIANGLE_LIST)
    local quad={{-1,-1},{1,1},{1,-1},{-1,-1},{-1,1},{1,1}}
    for _,p in ipairs(quad) do
        g:DefineVertex(Vector3(p[1],p[2],0)); g:DefineNormal(Vector3(0,0,-1))
        -- 图片 v 轴向下：顶点 y=+1 对应图片顶部
        g:DefineTexCoord(Vector2(p[1]*.5+.5,.5-p[2]*.5))
    end
    g:Commit(); g:SetMaterial(mat); g.castShadows=false
    node.enabled=false
    return {node=node,mat=mat}
end
local function Show(s,pos,rot,r,color,fade,progress)
    s.node.enabled=fade>.01
    s.node.worldPosition=pos; s.node.worldRotation=rot; s.node.scale=Vector3(r,r,r)
    s.mat:SetShaderParameter('tint',Variant(color))
    if s.dial then
        s.mat:SetShaderParameter('strength',Variant(fade))
        s.mat:SetShaderParameter('hand_rate',Variant(s.handRate or 0.0))
        s.mat:SetShaderParameter('hand_phase',Variant(s.handPhase or 0.0))
    else
        s.mat:SetShaderParameter('fade',Variant(fade))
        s.mat:SetShaderParameter('progress',Variant(progress or 1))
    end
end
function M.New(scene)
    local self=setmetatable({age=0,next=0,impacts={}},S)
    local root=scene:CreateChild('TimeSigils')
    self.target=Shape(root,'SelectedClock','clock')
    -- Casting circle (hand) and the ground charge ring both use the Roman clock, not the old red seal/ring.
    self.hand=Shape(root,'CastingClock','dial'); self.hand.dial=true
    self.range=Shape(root,'ChargeRadius','dial'); self.range.dial=true
    for i=1,4 do self.impacts[i]=Shape(root,'Impact'..i,'dial');self.impacts[i].dial=true end
    return self
end
function S:Pulse(pos,normal,color,radius)
    self.next=self.next%#self.impacts+1
    local p=self.impacts[self.next]
    p.pos=pos+normal*.07; p.rot=Quaternion(Vector3.FORWARD,normal)
    p.color=color; p.radius=radius; p.age=0
    p.handRate=0.0;p.handPhase=0.0
end
---@param aim table
---@param hand Vector3
---@param camera Node
---@param caster table
function S:Update(dt,aim,hand,camera,caster,radius,enabled)
    self.age=self.age+dt
    -- 瞄准阶段不显示目标盘/指针；目标反馈交给准星与 HUD。
    -- 红色命中表盘只由 Pulse() 在释放后创建。
    self.target.node.enabled=false
    local active=enabled and (caster.charging or caster.castAnim>0)
    self.hand.node.enabled=active
    if active then
        local spell=caster.lastCast
        local col=(caster.charging or spell=='shatter') and Color(.74,.91,1,1)
            or (spell=='freeze' and Color(.42,.66,1,1) or Color(1,.8,.36,1))
        -- 蓄力法阵：罗马时钟，属于施法空间，不是始终朝镜头的屏幕标记。
        local target = aim.hit and aim.pos or aim.far --[[@as Vector3?]]
        ---@type Vector3
        local delta = target and (target-hand) or aim.dir
        local direction = delta:LengthSquared()>.0001 and delta:Normalized() or Vector3.FORWARD
        local rotation = Quaternion(Vector3.FORWARD,direction)
        Show(self.hand,hand+direction*.12,rotation*Quaternion(-self.age*35,Vector3.FORWARD),.18+.08*caster.charge,col,.85)
    end
    self.range.node.enabled=enabled and caster.charging and aim.hit
    if self.range.node.enabled then
        Show(self.range,aim.pos+aim.normal*.08,Quaternion(Vector3.FORWARD,aim.normal)*Quaternion(self.age*-18,Vector3.FORWARD),radius,Color(.74,.91,1,1),.8,caster.charge)
    end
    for _,p in ipairs(self.impacts) do
        if p.age then
            p.age=p.age+dt
            local t=p.age/.85
            if t>=1 then p.age=nil; p.node.enabled=false
            else
                local fade=(1-t)*(1-t)
                p.handRate=math.pi*8.0
                Show(p,p.pos,p.rot,p.radius*(.85+.15*t),p.color,fade)
            end
        end
    end
end
return M
