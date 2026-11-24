-- Local forward axis +Z. The locked cylinder, including its amber preview, ends
-- at exactly the same clipped cross-section used by the attack sweep.
local FX={}
FX.__index=FX
FX.radius=.34
local segments=16
local function material(r,g,b,a)
    local m=Material:new()
    local transparent=a and a<1
    local path=transparent and 'Techniques/PBR/PBRNoTextureAlpha.xml' or 'Techniques/NoTextureUnlit.xml'
    m:SetTechnique(0,cache:GetResource('Technique',path))
    m:SetShaderParameter('MatDiffColor',Variant(Color(r,g,b,a or 1)))
    if transparent then m:SetShaderParameter('MatEmissiveColor',Variant(Color(r*.55,g*.55,b*.55))) end
    m:SetCullMode(CULL_NONE)
    return m
end
local function surface(parent,name,mat,build)
    local n=parent:CreateChild(name)
    local g=n:CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST)
    local function quad(a,b,c,d,normal)
        for _,v in ipairs({a,b,c,a,c,d}) do g:DefineVertex(v);g:DefineNormal(normal) end
    end
    build(quad);g:Commit();g:SetMaterial(mat);g.castShadows=false
    return n
end
local function polar(a,r,z) return Vector3(math.cos(a)*r,math.sin(a)*r,z) end
local function collar(parent,name,mat,teeth)
    return surface(parent,name,mat,function(quad)
        for i=0,segments-1 do
            local a,b=i*2*math.pi/segments,(i+.9)*2*math.pi/segments
            local inner=teeth and i%4==0 and .61 or .86
            local p,q,r,s=polar(a,inner,0),polar(a,1,0),polar(b,1,0),polar(b,inner,0)
            local dz=Vector3(0,0,.06)
            quad(p,q,r,s,Vector3.FORWARD);quad(p+dz,s+dz,r+dz,q+dz,Vector3.FORWARD)
            quad(q,q+dz,r+dz,r,polar((a+b)/2,1,0))
        end
    end)
end
local function tube(parent,name,mat)
    return surface(parent,name,mat,function(quad)
        for i=0,segments-1 do
            local a,b=i*2*math.pi/segments,(i+1)*2*math.pi/segments
            quad(polar(a,1,0),polar(b,1,0),polar(b,1,1),polar(a,1,1),polar((a+b)/2,1,0))
        end
    end)
end
local function box(parent,name,mat)
    local n=parent:CreateChild(name)
    local sm=n:CreateComponent('StaticModel');sm:SetModel(cache:GetResource('Model','Models/Box.mdl'));sm:SetMaterial(mat)
    sm.castShadows=false
    return n
end
local atlasPath='Textures/fx/RuinConstructOptics.png'
local shaderPath='Shaders/BLGL/RuinConstructOptics.shader'

-- Build a face for the etched plates or two crossed longitudinal ribbons for
-- the discharges. The sampler repeats along metres, never across the width.
local function texturedMesh(parent,name,mat,ribbon)
    local node=parent:CreateChild(name)
    local g=node:CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST)
    local function face(a,b,c,d)
        local points={a,b,c,d};local uv={{0,0},{1,0},{1,1},{0,1}}
        for _,i in ipairs({1,2,3,1,3,4}) do
            g:DefineVertex(points[i]);g:DefineNormal(Vector3.FORWARD);g:DefineTexCoord(Vector2(uv[i][1],uv[i][2]))
        end
    end
    if ribbon then
        for i=0,1 do
            local t=.48+i*math.pi*.5;local x,y=math.cos(t),math.sin(t)
            face(Vector3(-x,-y,0),Vector3(-x,-y,1),Vector3(x,y,1),Vector3(x,y,0))
        end
    else face(Vector3(-.5,.5,0),Vector3(.5,.5,0),Vector3(.5,-.5,0),Vector3(-.5,-.5,0)) end
    g:Commit();g:SetMaterial(mat);g.castShadows=false;node.enabled=false
    return {node=node,mat=mat}
end

local function paintedOptics(self,scene)
    local texture=cache:GetResource('Texture2D',atlasPath)
    if not texture or not Vector2 then return end
    local materials={}
    for i=1,6 do
        local mat=Material:new()
        if not mat.SetSurfaceShader or not mat.SetSurfaceTexture or not mat:SetSurfaceShader(shaderPath)
            or not mat:SetSurfaceTexture('optics_tex',texture) then return end
        mat:SetShaderParameter('stamp',Variant(i-1));materials[i]=mat
    end
    local names={'SealShell','SealFiligree','ChargeTrain','CoronaArcs','OverloadImprint','CoreVent'}
    local marks={}
    for i,name in ipairs(names) do
        marks[i]=texturedMesh(i>=5 and scene or self.root,name,materials[i],i==3 or i==4)
    end
    return marks
end

local function expose(mark,frame,coverage,runs)
    mark.node.enabled=coverage>0
    if not mark.node.enabled then return end
    frame=math.min(7,math.max(0,math.floor(frame)))
    coverage=math.ceil(math.min(1,coverage)*16)/16
    if frame~=mark.frame then mark.mat:SetShaderParameter('exposure',Variant(frame));mark.frame=frame end
    if coverage~=mark.coverage then mark.mat:SetShaderParameter('coverage',Variant(coverage));mark.coverage=coverage end
    if runs and runs~=mark.runs then mark.mat:SetShaderParameter('runs',Variant(runs));mark.runs=runs end
end

function FX.New(scene)
    local self=setmetatable({},FX)
    self.root=scene:CreateChild('ConstructOptics')
    local brass=material(1,.57,.17);local aqua=material(.18,.92,.88);local ice=material(.86,1,.95)
    self.rings={collar(self.root,'GiltAperture',brass,true),collar(self.root,'InductionRing',aqua,false),collar(self.root,'FocusRing',ice,true)}
    self.guide=tube(self.root,'AmberBoundary',material(1,.52,.12,.17))
    self.halo=tube(self.root,'IonSheath',material(.1,.76,.88,.24))
    self.axis=box(self.root,'LockedAxis',brass)
    local spineMat=material(.86,1,.95)
    self.spine=box(self.root,'CrystalSpine',spineMat)
    self.spine.rotation=Quaternion(90,Vector3.RIGHT) -- DragonBeam scrolls along local +Y.
    if spineMat.SetSurfaceShader and spineMat:SetSurfaceShader('Shaders/BLGL/DragonBeam.shader') then
        self.flow=spineMat
        spineMat:SetShaderParameter('core_color',Variant(Color(.82,1,.96)))
        spineMat:SetShaderParameter('edge_color',Variant(Color(.12,.89,.93)))
        spineMat:SetShaderParameter('dark_color',Variant(Color(.06,.49,.61)))
        spineMat:SetShaderParameter('intensity',Variant(1.1))
    end
    self.tip=collar(self.root,'TerminalFocus',aqua,true)
    self.sparks={}
    for i=1,8 do self.sparks[i]=box(self.root,'FlowPixel'..i,aqua) end
    self.marks=paintedOptics(self,scene)
    self:Hide()
    return self
end
function FX:Hide()
    self.root.enabled=false
    if self.marks then for _,m in ipairs(self.marks) do m.node.enabled=false end end
end

function FX:Vent(center,dir,opening,time)
    if not self.marks then return end
    local v=self.marks[6]
    expose(v,math.min(7,time*14),opening)
    if v.node.enabled then
        v.node.position=center;v.node:LookAt(center+dir)
        local size=.66+.26*opening;v.node.scale=Vector3(size,size,1)
    end
end
function FX:Draw(origin,dir,length,age,progress,locked,fire,wall,fireProgress)
    self.root.enabled=length>.01
    if not self.root.enabled then self:Hide();return end
    self.root.position=origin;self.root:LookAt(origin+dir)
    for i,n in ipairs(self.rings) do
        local k=math.max(0,math.min(1,progress*3.1-i+1))
        local z=.05+(i-1)*.19
        n.enabled=k>0 and z+.06<length
        if n.enabled then
            local r=(.66-i*.09)*(.65+.35*k)
            n.scale=Vector3(r,r,.7);n.position=Vector3(0,0,z)
            n.rotation=Quaternion((i%2==0 and -1 or 1)*math.floor(age*12)*6,Vector3.FORWARD)
        end
    end
    self.guide.enabled=locked and not fire;self.axis.enabled=self.guide.enabled
    self.halo.enabled=fire;self.spine.enabled=fire;self.tip.enabled=fire
    local hull=fire and self.halo or self.guide
    hull.scale=Vector3(FX.radius,FX.radius,length)
    if self.axis.enabled then self.axis.position=Vector3(0,0,length*.5);self.axis.scale=Vector3(.035,.035,length) end
    if fire then
        self.spine.position=Vector3(0,0,length*.5);self.spine.scale=Vector3(.23,length,.23)
        if self.flow then
            self.flow:SetShaderParameter('beam_len',Variant(length));self.flow:SetShaderParameter('scroll',Variant(age))
        end
        local r=FX.radius*(.68+.32*math.abs(math.sin(age*22)))
        self.tip.position=Vector3(0,0,math.max(0,length-.04));self.tip.scale=Vector3(r,r,math.min(.6,length/.06))
    end
    for i,n in ipairs(self.sparks) do
        n.enabled=fire and length>.24
        if n.enabled then
            local u=(i/8+age*1.7)%1;local angle=i*2.4+age*4
            local r=FX.radius*.72*math.min(1,(1-u)*6)
            n.position=polar(angle,r,.10+u*(length-.20));n.scale=Vector3(.047,.047,.14)
        end
    end
    if not self.marks then return end
    for i=1,2 do
        local mark,ring=self.marks[i],self.rings[i]
        local k=math.min(1,math.max(0,progress*1.8-(i-1)*.65))
        local active=k>0 and (i==1 and .07 or .29)+.025<length
        expose(mark,k*8,active and (fire and math.min(1,(1-fireProgress)*4) or k) or 0)
        if mark.node.enabled then
            mark.node.position=Vector3(0,0,i==1 and .07 or .29)
            local diameter=(i==1 and 1.54 or 1.01)*(.72+.28*k)
            mark.node.scale=Vector3(diameter,diameter,1)
            mark.node.rotation=Quaternion((i==1 and -1 or 1)*math.floor(age*9)*4,Vector3.FORWARD)
        end
        ring.enabled=false
    end
    -- Keep the geometric shell at exactly the damage boundary and a thin pilot
    -- light beneath the discontinuous charge packets, even between bright pixels.
    local runs=math.max(1,math.floor(length/.85+.5))
    for i=3,4 do
        local mark=self.marks[i]
        local radius=i==3 and .25 or FX.radius
        expose(mark,(math.floor(age*(i==3 and 20 or 11))+(i==3 and 0 or 3))%8,fire and 1 or 0,runs)
        if mark.node.enabled then mark.node.scale=Vector3(radius,radius,length) end
    end
    if fire then self.spine.scale=Vector3(.055,length,.055) end
    local stamp=self.marks[5]
    local onWall=fire and wall and wall.position and wall.normal and wall.normal:LengthSquared()>.01
    expose(stamp,fireProgress*8,onWall and math.min(1,(1-fireProgress)*6) or 0)
    if stamp.node.enabled then
        local pos=wall.position+wall.normal*.018
        stamp.node.position=pos;stamp.node:LookAt(pos+wall.normal)
        local size=.42+.78*math.min(1,fireProgress*3);stamp.node.scale=Vector3(size,size,1)
    end
end
function FX:Destroy()
    if self.marks then self.marks[5].node:Remove();self.marks[6].node:Remove() end
    self.root:Remove()
end
return FX
