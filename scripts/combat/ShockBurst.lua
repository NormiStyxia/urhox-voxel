-- Ground shockwave for plunge landings and the half-moon finisher.
-- Continuous shapes only (no bars/pillars): an expanding soft ring, a low
-- energy wall riding the ring, swirling crescent petals and a white core flash.
-- One node, one dynamic geometry, additive vertex colour, fixed burst pool.
---@class ShockBurst
---@field node Node
---@field geometry CustomGeometry
---@field bursts table[]
local B={};B.__index=B
B.POOL=3
local SEGMENTS=48
local PETALS,PETAL_STEPS=7,8
local TAU=math.pi*2
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
-- size: ring radius (m); wall: wall height (m); life: seconds.
local KINDS={
    plunge={size=3.4,wall=1.25,life=.55,petal=1,flash=1.0},
    finisher={size=2.4,wall=.80,life=.45,petal=.8,flash=.8},
}
---@param scene Scene
---@return ShockBurst
function B.New(scene)
    local self=setmetatable({},B)
    self.node=scene:CreateChild('ShockBurst');self.node.temporary=true;self.node.enabled=false
    local g=self.node:CreateComponent('CustomGeometry')
    g:SetNumGeometries(1);g:SetDynamic(true);g.castShadows=false
    local technique=cache:GetResource('Technique','Techniques/NoTextureVColAddAlpha.xml')
    local material=Material:new()
    if technique then material:SetTechnique(0,technique) end
    material.cullMode=CULL_NONE
    material:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,1)))
    g:BeginGeometry(0,TRIANGLE_LIST);g:Commit() -- commit before SetMaterial
    g:SetMaterial(0,material)
    self.geometry,self.material=g,material
    self.bursts={}
    for i=1,B.POOL do self.bursts[i]={active=false,x=0,y=0,z=0,fx=0,fz=1,age=0,spin=0,kind=KINDS.plunge} end
    self.head=0
    -- Unit circle table built once; the rebuild reads it without allocating.
    self.cos,self.sin={},{}
    for i=0,SEGMENTS do self.cos[i]=math.cos(i/SEGMENTS*TAU);self.sin[i]=math.sin(i/SEGMENTS*TAU) end
    return self
end
---@param pos Vector3 ground point (feet)
---@param forward Vector3
---@param plunge boolean
function B:Emit(pos,forward,plunge)
    self.head=self.head%B.POOL+1
    local b=self.bursts[self.head]
    local kind=plunge and KINDS.plunge or KINDS.finisher
    local fx,fz=forward and forward.x or 0,forward and forward.z or 1
    local l=math.sqrt(fx*fx+fz*fz);if l<1e-4 then fx,fz,l=0,1,1 end
    fx,fz=fx/l,fz/l
    -- Finisher lands in front of the player; plunge is centred on the feet.
    local offset=plunge and 0 or .65
    b.active,b.kind,b.age=true,kind,0
    b.x,b.y,b.z=pos.x+fx*offset,pos.y,pos.z+fz*offset
    b.fx,b.fz=fx,fz
    b.spin=math.atan(fx,fz)
end
local function v(g,x,y,z,r,gr,bl,a)
    g:DefineVertex(Vector3(x,y,z));g:DefineColor(Color(r*a,gr*a,bl*a,a))
end
local function quad(g,ax,ay,az,aa,bx,by,bz,ba,cx,cy,cz,ca,dx,dy,dz,da,r,gr,bl)
    -- a-b along the outer edge, d-c along the inner edge.
    v(g,ax,ay,az,r,gr,bl,aa);v(g,bx,by,bz,r,gr,bl,ba);v(g,cx,cy,cz,r,gr,bl,ca)
    v(g,ax,ay,az,r,gr,bl,aa);v(g,cx,cy,cz,r,gr,bl,ca);v(g,dx,dy,dz,r,gr,bl,da)
end
---@param dt number
function B:Update(dt)
    local any=false
    for _,b in ipairs(self.bursts) do
        if b.active then
            b.age=b.age+dt
            if b.age>=b.kind.life then b.active=false else any=true end
        end
    end
    if not any then self.node.enabled=false;return end
    local g=self.geometry
    g:BeginGeometry(0,TRIANGLE_LIST)
    local cos,sin=self.cos,self.sin
    for _,b in ipairs(self.bursts) do
        if b.active then
            local k=b.kind
            local u=b.age/k.life
            local grow=1-(1-u)^3
            local fade=(1-u)*(1-u)
            local y=b.y+.05
            -- 1) Soft ring band: transparent inner/outer edges, bright middle.
            local r=.25+(k.size-.25)*grow
            local w=.18+.55*(1-u)
            local ri,rm,ro=math.max(0,r-w),r-w*.25,r+w*.25
            local a=1.2*fade
            for i=0,SEGMENTS-1 do
                local c0,s0,c1,s1=cos[i],sin[i],cos[i+1],sin[i+1]
                quad(g,b.x+c0*rm,y,b.z+s0*rm,a,b.x+c1*rm,y,b.z+s1*rm,a,
                    b.x+c1*ri,y,b.z+s1*ri,0,b.x+c0*ri,y,b.z+s0*ri,0,.45,.75,1)
                quad(g,b.x+c0*ro,y,b.z+s0*ro,0,b.x+c1*ro,y,b.z+s1*ro,0,
                    b.x+c1*rm,y,b.z+s1*rm,a,b.x+c0*rm,y,b.z+s0*rm,a,.85,.95,1)
            end
            -- 2) Low energy wall riding just inside the ring, fading upward.
            local h=k.wall*(1-u)^.6
            local wr=r*.92
            local wa=.75*fade
            for i=0,SEGMENTS-1 do
                local c0,s0,c1,s1=cos[i],sin[i],cos[i+1],sin[i+1]
                quad(g,b.x+c0*wr,y+h,b.z+s0*wr,0,b.x+c1*wr,y+h,b.z+s1*wr,0,
                    b.x+c1*wr,y,b.z+s1*wr,wa,b.x+c0*wr,y,b.z+s0*wr,wa,.35,.62,1)
            end
            -- 3) Crescent petals swirling outward on the ground.
            local pa=.95*fade*k.petal
            local twist=b.spin+u*1.1
            for p=0,PETALS-1 do
                local base=twist+p*TAU/PETALS
                local inner,outer=r*.18,r*.95
                local prevX,prevZ,prevW,prevA,prevC,prevS=0.0,0.0,0.0,0.0,0.0,0.0
                for s=0,PETAL_STEPS do
                    local t=s/PETAL_STEPS
                    local ang=base+t*.95
                    local rad=inner+(outer-inner)*t
                    local cx,sz=math.cos(ang),math.sin(ang)
                    local hw=.22*k.size*.3*math.sin(math.pi*t)*(1-u*.5)
                    local alpha=pa*math.sin(math.pi*t)
                    local x,z=b.x+cx*rad,b.z+sz*rad
                    if s>0 then
                        -- Width along the radial direction: a curved blade of light.
                        local px,pz,pcx,psz=prevX,prevZ,prevC,prevS
                        quad(g,x+cx*hw,y+.01,z+sz*hw,0,px+pcx*prevW,y+.01,pz+psz*prevW,0,
                            px,y+.01,pz,prevA,x,y+.01,z,alpha,.7,.9,1)
                        quad(g,x,y+.01,z,alpha,px,y+.01,pz,prevA,
                            px-pcx*prevW,y+.01,pz-psz*prevW,0,x-cx*hw,y+.01,z-sz*hw,0,.7,.9,1)
                    end
                    prevX,prevZ,prevW,prevA,prevC,prevS=x,z,hw,alpha,cx,sz
                end
            end
            -- 4) White core flash, first ~25% of the life.
            local f=clamp(1-u/.25,0,1)
            if f>0 then
                local fr=k.size*.42*(1.2-f*.4)
                local fa=1.6*f*f*k.flash
                for i=0,SEGMENTS-1,2 do
                    local c0,s0,c1,s1=cos[i],sin[i],cos[i+2],sin[i+2]
                    v(g,b.x,y+.02,b.z,1,1,1,fa)
                    v(g,b.x+c0*fr,y+.02,b.z+s0*fr,.6,.85,1,0)
                    v(g,b.x+c1*fr,y+.02,b.z+s1*fr,.6,.85,1,0)
                end
            end
        end
    end
    g:Commit()
    self.node.enabled=true
end
function B:Clear()
    for _,b in ipairs(self.bursts) do b.active=false end
    self.node.enabled=false
end
function B:Dispose()
    self.node:Remove()
    self.material:Dispose()
end
return B
