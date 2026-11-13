-- Reusable geometry: Roman dial, hand seal and bounded impact pool.
local M = {}
local S = {}; S.__index = S
-- 表盘与手印用生图素材（白线黑底，亮度即不透明度）；范围圈与冲击波由 shader 程序化画环。
local TEX = { clock='Textures/Sigils/sigil_clock.png', seal='Textures/Sigils/sigil_seal.png' }
local function Shape(parent, name, kind)
    local node = parent:CreateChild(name)
    local mat = Material:new()
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
    s.mat:SetShaderParameter('fade',Variant(fade))
    s.mat:SetShaderParameter('progress',Variant(progress or 1))
end
function M.New(scene)
    local self=setmetatable({age=0,next=0,impacts={}},S)
    local root=scene:CreateChild('TimeSigils')
    self.target=Shape(root,'SelectedClock','clock')
    self.hand=Shape(root,'CastingClock','seal')
    self.range=Shape(root,'ChargeRadius',nil)
    for i=1,4 do self.impacts[i]=Shape(root,'Impact'..i,nil) end
    return self
end
function S:Pulse(pos,normal,color,radius)
    self.next=self.next%#self.impacts+1
    local p=self.impacts[self.next]
    p.pos=pos+normal*.07; p.rot=Quaternion(Vector3.FORWARD,normal)
    p.color=color; p.radius=radius; p.age=0
end
---@param aim table
---@param hand Vector3
---@param camera Node
---@param caster table
function S:Update(dt,aim,hand,camera,caster,radius,enabled)
    self.age=self.age+dt
    local face=camera.worldRotation
    local selected=enabled and aim.hit and (aim.object~=nil or aim.breakable==true)
    self.target.node.enabled=selected
    if selected then
        local hitPos = aim.pos --[[@as Vector3]]
        local pos=hitPos+(camera.worldPosition-hitPos):Normalized()*.16
        -- 目标钟面颜色跟随可施放的法术：蓄力/只能碎 = 红，可回溯 = 黄
        local obj=aim.object
        local rewindable=obj~=nil and obj.canRewind and (obj.state=='SHATTERED' or obj.state=='FROZEN')
        local col=(caster.charging or not rewindable) and Color(1,.36,.3,1) or Color(1,.8,.36,1)
        -- 表盘按时间缓慢逆转，像在倒拨时间
        Show(self.target,pos,face*Quaternion(self.age*12,Vector3.FORWARD),.65,col,.9)
    end
    local active=enabled and (caster.charging or caster.castAnim>0)
    self.hand.node.enabled=active
    if active then
        local spell=caster.lastCast
        local col=(caster.charging or spell=='shatter') and Color(1,.36,.3,1)
            or (spell=='freeze' and Color(.4,.65,1,1) or Color(1,.8,.36,1))
        -- 手部法阵属于施法空间，不是始终朝镜头的屏幕标记。
        local target = aim.hit and aim.pos or aim.far --[[@as Vector3?]]
        ---@type Vector3
        local delta = target and (target-hand) or aim.dir
        local direction = delta:LengthSquared()>.0001 and delta:Normalized() or Vector3.FORWARD
        local rotation = Quaternion(Vector3.FORWARD,direction)
        Show(self.hand,hand+direction*.12,rotation*Quaternion(-self.age*35,Vector3.FORWARD),.18+.08*caster.charge,col,.85)
    end
    self.range.node.enabled=enabled and caster.charging and aim.hit
    if self.range.node.enabled then
        Show(self.range,aim.pos+aim.normal*.08,Quaternion(Vector3.FORWARD,aim.normal),radius,Color(1,.36,.3,1),.8,caster.charge)
    end
    for _,p in ipairs(self.impacts) do
        if p.age then
            p.age=p.age+dt
            local t=p.age/.6
            if t>=1 then p.age=nil; p.node.enabled=false
            else Show(p,p.pos,p.rot,p.radius*(.3+.7*t),p.color,(1-t)*.9) end
        end
    end
end
return M
