-- Reusable geometry: Roman dial, hand seal and bounded impact pool.
local M = {}
local S = {}; S.__index = S
local ROMAN = {'I','II','III','IV','V','VI','VII','VIII','IX','X','XI','XII'}
---@type table<string, number[][]>
local GLYPH = {
 I={{0,-.5,0,.5},{-.22,.5,.22,.5},{-.22,-.5,.22,-.5}},
 V={{-.3,.5,0,-.5},{0,-.5,.3,.5}}, X={{-.3,.5,.3,-.5},{-.3,-.5,.3,.5}},
}
local function Shape(parent, name, clock)
    local node = parent:CreateChild(name)
    local mat = Material:new()
    assert(mat:SetSurfaceShader('Shaders/BLGL/TimeSigil.shader'), 'TimeSigil shader unavailable')
    local g = node:CreateComponent('CustomGeometry')
    g:BeginGeometry(0, TRIANGLE_LIST)
    local function line(x,y,u,v,w)
        local dx,dy=u-x,v-y; local d=math.sqrt(dx*dx+dy*dy)
        if d<.00001 then return end
        local nx,ny=-dy/d*w/2,dx/d*w/2
        local pts={{x+nx,y+ny},{u+nx,v+ny},{u-nx,v-ny},{x+nx,y+ny},{u-nx,v-ny},{x-nx,y-ny}}
        for _,p in ipairs(pts) do
            g:DefineVertex(Vector3(p[1],p[2],0)); g:DefineNormal(Vector3(0,0,-1))
            g:DefineTexCoord(Vector2(p[1]*.5+.5,p[2]*.5+.5))
        end
    end
    local function ring(r,w)
        for i=0,95 do
            local a,b=i*math.pi/48,(i+1)*math.pi/48
            line(math.sin(a)*r,math.cos(a)*r,math.sin(b)*r,math.cos(b)*r,w)
        end
    end
    ring(1,.012); ring(.95,.005)
    if clock then
        ring(.62,.006)
        for i=1,60 do
            local a=i*math.pi/30; local r=i%5==0 and .86 or .9
            line(math.sin(a)*r,math.cos(a)*r,math.sin(a)*.94,math.cos(a)*.94,i%5==0 and .014 or .006)
        end
        for i,word in ipairs(ROMAN) do
            local a=i*math.pi/6; local x,y=math.sin(a)*.75,math.cos(a)*.75
            for j=1,#word do for _,s in ipairs(GLYPH[word:sub(j,j)]) do
                local off=(j-(#word+1)/2)*.066
                line(x+off+s[1]*.095,y+s[2]*.12,x+off+s[3]*.095,y+s[4]*.12,.009)
            end end
        end
        line(0,0,0,.51,.017); line(0,0,.28,-.17,.023)
        ring(.06,.014)
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
    self.target=Shape(root,'SelectedClock',true)
    self.hand=Shape(root,'CastingClock',true)
    self.range=Shape(root,'ChargeRadius',false)
    for i=1,4 do self.impacts[i]=Shape(root,'Impact'..i,false) end
    return self
end
function S:Pulse(pos,normal,color,radius)
    self.next=self.next%#self.impacts+1
    local p=self.impacts[self.next]
    p.pos=pos+normal*.07; p.rot=Quaternion(Vector3.FORWARD,normal)
    p.color=color; p.radius=radius; p.age=0
end
---@param aim table
---@param camera Node
function S:Update(dt,aim,hand,camera,caster,radius,enabled)
    self.age=self.age+dt
    local face=camera.worldRotation
    local selected=enabled and aim.hit and (aim.object~=nil or aim.breakable==true)
    self.target.node.enabled=selected
    if selected then
        local hitPos = aim.pos --[[@as Vector3]]
        local pos=hitPos+(camera.worldPosition-hitPos):Normalized()*.16
        local distance=(camera.worldPosition-pos):Length()
        Show(self.target,pos,face,math.max(.45,math.min(1.2,distance*.035)),Color(.45,.75,1,1),.95)
    end
    local active=enabled and (caster.charging or caster.castAnim>0)
    self.hand.node.enabled=active
    if active then
        local col=caster.charging and Color(1,.77,.32,1) or Color(.4,.65,1,1)
        Show(self.hand,hand,face*Quaternion(-self.age*35,Vector3.FORWARD),.24+.18*caster.charge,col,.85)
    end
    self.range.node.enabled=enabled and caster.charging and aim.hit
    if self.range.node.enabled then
        Show(self.range,aim.pos+aim.normal*.08,Quaternion(Vector3.FORWARD,aim.normal),radius,Color(1,.77,.32,1),.8,caster.charge)
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
