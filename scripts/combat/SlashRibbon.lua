-- Continuous crescent sword trail (半月斩 / 鼠标拖尾 style).
-- A fixed ring of blade samples (root, tip, age) is rebuilt each frame into one
-- strip: the tip edge is a hot white-blue line, the band fades toward the hilt,
-- and the tail thins and dissolves with age. One node, one dynamic geometry.
-- Samples are interpolated along the blade's rotation so fast swings stay round.
---@class SlashRibbon
---@field node Node
---@field geometry CustomGeometry
---@field samples table[]
---@field count integer
---@field head integer
local R={};R.__index=R
R.CAPACITY=48
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
-- Per-style look. width: fraction of the blade covered from the tip inward.
local STYLES={
    light={life=.20,width=.62,core={.85,.95,1},body={.25,.62,1},glow=1.0},
    heavy={life=.32,width=.80,core={1,.97,.86},body={.30,.55,1},glow=1.25},
    moon={life=.42,width=.95,core={1,1,1},body={.18,.42,1},glow=1.45},
}
---@param scene Scene
---@return SlashRibbon
function R.New(scene)
    local self=setmetatable({},R)
    self.node=scene:CreateChild('SlashRibbon');self.node.temporary=true;self.node.enabled=false
    local geometry=self.node:CreateComponent('CustomGeometry')
    geometry:SetNumGeometries(1)
    geometry:SetDynamic(true)
    geometry.castShadows=false
    -- Vertex colour + additive: overlapping passes brighten instead of greying.
    local technique=cache:GetResource('Technique','Techniques/NoTextureVColAddAlpha.xml')
    local material=Material:new()
    if technique then material:SetTechnique(0,technique) end
    material.cullMode=CULL_NONE
    material:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,1)))
    geometry:BeginGeometry(0,TRIANGLE_LIST);geometry:Commit() -- commit before SetMaterial
    geometry:SetMaterial(0,material)
    self.geometry,self.material=geometry,material
    self.samples={}
    for i=1,R.CAPACITY do
        self.samples[i]={rx=0,ry=0,rz=0,tx=0,ty=0,tz=0,age=1,
            ix=0,iy=0,iz=0,mx=0,my=0,mz=0,fade=0}
    end
    self.count,self.head=0,0
    self.style=STYLES.light
    self.emitting=false
    self.lastValid=false
    self.lx,self.ly,self.lz,self.ltx,self.lty,self.ltz=0,0,0,0,0,0
    return self
end
---@param kind string light | heavy | moon
function R:Begin(kind)
    self.style=STYLES[kind] or STYLES.light
    self.emitting=true
    self.lastValid=false
end
function R:End()
    self.emitting=false
    self.lastValid=false
end
function R:Clear()
    self.emitting,self.lastValid=false,false
    self.count,self.head=0,0
    self.node.enabled=false
end
function R:Push(rx,ry,rz,tx,ty,tz)
    self.head=self.head%R.CAPACITY+1
    local s=self.samples[self.head]
    s.rx,s.ry,s.rz,s.tx,s.ty,s.tz,s.age=rx,ry,rz,tx,ty,tz,0
    self.count=math.min(R.CAPACITY,self.count+1)
end
-- Blade root/tip world positions for this frame. Subdivides by blade angle
-- (<=12 degrees per step) so a 30 Hz swing still reads as a smooth arc.
---@param root Vector3
---@param tip Vector3
function R:Sample(root,tip)
    if not self.emitting then return end
    local rx,ry,rz,tx,ty,tz=root.x,root.y,root.z,tip.x,tip.y,tip.z
    if not self.lastValid then
        self:Push(rx,ry,rz,tx,ty,tz)
    else
        local ax,ay,az=self.ltx-self.lx,self.lty-self.ly,self.ltz-self.lz
        local bx,by,bz=tx-rx,ty-ry,tz-rz
        local al=math.sqrt(ax*ax+ay*ay+az*az);local bl=math.sqrt(bx*bx+by*by+bz*bz)
        if al<1e-5 or bl<1e-5 then self.lastValid=false;return end
        local angle=math.acos(clamp((ax*bx+ay*by+az*bz)/(al*bl),-1,1))
        local moved=math.abs(tx-self.ltx)+math.abs(ty-self.lty)+math.abs(tz-self.ltz)
        if angle<math.rad(1.5) and moved<.02 then return end
        local steps=math.min(6,math.max(1,math.ceil(angle/math.rad(12))))
        local sine=math.sin(angle)
        for i=1,steps do
            local u=i/steps
            local a,b=1-u,u
            if sine>1e-3 then a,b=math.sin((1-u)*angle)/sine,math.sin(u*angle)/sine end
            local px,py,pz=self.lx+(rx-self.lx)*u,self.ly+(ry-self.ly)*u,self.lz+(rz-self.lz)*u
            -- Blade length interpolates too; direction follows the arc (slerp).
            local len=(al+(bl-al)*u)
            local dx,dy,dz=(ax*a+bx*b),(ay*a+by*b),(az*a+bz*b)
            local dl=math.sqrt(dx*dx+dy*dy+dz*dz)
            if dl>1e-6 then dx,dy,dz=dx/dl*len,dy/dl*len,dz/dl*len end
            self:Push(px,py,pz,px+dx,py+dy,pz+dz)
        end
    end
    self.lx,self.ly,self.lz,self.ltx,self.lty,self.ltz=rx,ry,rz,tx,ty,tz
    self.lastValid=true
end
local function vertex(g,x,y,z,r,gr,b,a)
    g:DefineVertex(Vector3(x,y,z))
    g:DefineColor(Color(r,gr,b,a))
end
---@param dt number
function R:Update(dt)
    local style=self.style
    local life=style.life
    local live=0
    for i=1,self.count do
        local s=self.samples[i]
        s.age=s.age+dt
        if s.age<life then live=live+1 end
    end
    if live<2 then
        self.node.enabled=false
        if not self.emitting then self.count,self.head=0,0 end
        return
    end
    local g=self.geometry
    g:BeginGeometry(0,TRIANGLE_LIST)
    local core,body,glow=style.core,style.body,style.glow
    local width=style.width
    -- Walk newest -> oldest; quads between consecutive samples. Edge points are
    -- cached on the pooled samples, so the rebuild creates no Lua tables.
    local p=nil
    local index=self.head
    for _=1,self.count do
        local s=self.samples[index]
        if s.age<life then
            local u=s.age/life               -- 0 new .. 1 old
            s.fade=(1-u)*(1-u)*glow          -- tail dissolves quickly
            local w=width*(1-.55*u)          -- crescent thins toward the tail
            -- Inner edge sits partway down the blade: the band hugs the tip.
            s.ix,s.iy,s.iz=s.tx+(s.rx-s.tx)*w,s.ty+(s.ry-s.ty)*w,s.tz+(s.rz-s.tz)*w
            s.mx,s.my,s.mz=(s.tx+s.ix)*.5,(s.ty+s.iy)*.5,(s.tz+s.iz)*.5
            if p then
                local pa,ca=p.fade,s.fade
                local pb,cb=pa*.75,ca*.75
                -- Outer half: hot core line at the tip fading into the blue body.
                vertex(g,p.tx,p.ty,p.tz,core[1]*pa,core[2]*pa,core[3]*pa,pa)
                vertex(g,s.tx,s.ty,s.tz,core[1]*ca,core[2]*ca,core[3]*ca,ca)
                vertex(g,s.mx,s.my,s.mz,body[1]*cb,body[2]*cb,body[3]*cb,cb)
                vertex(g,p.tx,p.ty,p.tz,core[1]*pa,core[2]*pa,core[3]*pa,pa)
                vertex(g,s.mx,s.my,s.mz,body[1]*cb,body[2]*cb,body[3]*cb,cb)
                vertex(g,p.mx,p.my,p.mz,body[1]*pb,body[2]*pb,body[3]*pb,pb)
                -- Inner half: blue body fading to nothing toward the hilt.
                vertex(g,p.mx,p.my,p.mz,body[1]*pb,body[2]*pb,body[3]*pb,pb)
                vertex(g,s.mx,s.my,s.mz,body[1]*cb,body[2]*cb,body[3]*cb,cb)
                vertex(g,s.ix,s.iy,s.iz,0,0,0,0)
                vertex(g,p.mx,p.my,p.mz,body[1]*pb,body[2]*pb,body[3]*pb,pb)
                vertex(g,s.ix,s.iy,s.iz,0,0,0,0)
                vertex(g,p.ix,p.iy,p.iz,0,0,0,0)
            end
            p=s
        end
        index=(index-2)%R.CAPACITY+1
    end
    g:Commit()
    self.node.enabled=true
end
function R:Dispose()
    self.node:Remove()
    self.material:Dispose()
end
return R
