-- Presentation only. Fixed landing/arc slots preserve the combat timing contract.
-- The game path uses layered VoxelFX motes for sword arcs, charge grains and
-- finisher impacts. The immediate-mode slots remain an offline fallback.
---@class CombatFx
---@field land table[] Fixed landing slots (30).
---@field arcs table[] Fixed slash wedges (24).
---@field edges table[] Additive bright tip edges (24).
---@field ghosts table[] Additive blue blade afterimages (12).
local F={};F.__index=F
F.LANDING_COUNT=30;F.ARC_COUNT=24;F.GHOST_COUNT=12
F.GHOSTS=false
F.PIXEL_SLASH_CAPACITY=180
F.PIXEL_IMPACT_CAPACITY=120
F.PIXEL_CHARGE_CAPACITY=72
-- Vector3 is a value type in the engine: callers MUST assign the result back.
local function set(v,x,y,z) v.x,v.y,v.z=x,y,z;return v end
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function vertex(g,x,y,z,a)
    g:DefineVertex(Vector3(x,y,z));g:DefineNormal(Vector3(0,1,0));g:DefineColor(Color(1,1,1,a or 1))
end
local function tri(g,ax,ay,az,bx,by,bz,cx,cy,cz,a,b,c)
    vertex(g,ax,ay,az,a);vertex(g,bx,by,bz,b);vertex(g,cx,cy,cz,c)
    vertex(g,cx,cy,cz,c);vertex(g,bx,by,bz,b);vertex(g,ax,ay,az,a)
end
local function geometry(node,kind,material)
    local g=node:CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST)
    if kind=='ring' then
        for i=0,31 do
            local a,b=i*math.pi/16,(i+1)*math.pi/16
            local ax,az,bx,bz=math.cos(a),math.sin(a),math.cos(b),math.sin(b)
            tri(g,ax,.03,az,bx,.03,bz,ax*.76,0,az*.76,1,1,0)
            tri(g,bx,.03,bz,bx*.76,0,bz*.76,ax*.76,0,az*.76,1,0,0)
        end
    elseif kind=='star' then
        -- Four pointed arms; one surface, no long radial rays.
        for i=0,3 do
            local a=i*math.pi*.5;local b=a+math.pi*.25;local c=a-math.pi*.25
            tri(g,0,0,0,math.cos(c)*.16,0,math.sin(c)*.16,math.cos(a)*.5,0,math.sin(a)*.5)
            tri(g,0,0,0,math.cos(a)*.5,0,math.sin(a)*.5,math.cos(b)*.16,0,math.sin(b)*.16)
        end
    elseif kind=='arc' then
        -- +X follows actual tip motion, -Y extends inward along blade. Tapered ends.
        tri(g,-.5,0,0,.5,0,0,0,-1,0,1,1,0)
        tri(g,-.5,0,0,0,-.10,0,.5,0,0,1,1,1)
    else
        -- Unit cube; crack/spark/star dimensions supplied through node scale.
        for axis=1,3 do for sign=-1,1,2 do
            local p={-.5,-.5,-.5};local q={-.5,-.5,-.5};local r={-.5,-.5,-.5};local s={-.5,-.5,-.5}
            local j,k=axis%3+1,(axis+1)%3+1
            p[axis],q[axis],r[axis],s[axis]=sign*.5,sign*.5,sign*.5,sign*.5
            q[j],r[j],r[k],s[k]=.5,.5,.5,.5
            tri(g,p[1],p[2],p[3],q[1],q[2],q[3],r[1],r[2],r[3])
            tri(g,p[1],p[2],p[3],r[1],r[2],r[3],s[1],s[2],s[3])
        end end
    end
    g:Commit();g:SetMaterial(0,material)
    g.castShadows=false
    return g
end
local function slot(self,kind,i,additive)
    local node=self.scene:CreateChild('CombatFx_'..kind..i..(additive and 'a' or ''));node.temporary=true;node.enabled=false
    local mat=Material:new() -- do not inherit voxel/surface-shader state from terrain
    if self.pixelMode then
        -- Pixel mode keeps the slots as timing/state records for callers, but
        -- submits no broad CustomGeometry. The visible path is VoxelFX motes.
        mat.SetShaderParameter=function() end
    else
        mat:SetTechnique(0,additive and self.additive or self.technique)
        geometry(node,kind,mat)
    end
    return {node=node,mat=mat,pos=Vector3(),scale=Vector3(),rot=Quaternion(),
        x=Vector3(),y=Vector3(),z=Vector3(),age=1,ttl=0,active=false,color=1,peak=1,vx=0,vy=0,vz=0,size=0,ground=0,arc=kind=='arc'}
end
---@param scene Scene
---@param world VoxelPhysicsWorld
---@return CombatFx
function F.New(scene,world)
    local self=setmetatable({scene=scene,land={},arcs={},edges={},ghosts={},
        colors={},head=0,ghostHead=0,ghostStep=0,width=.55,ttl=.16,tip=Vector3(),root=Vector3(),sampleTip=Vector3(),sampleRoot=Vector3(),valid=false},F)
    local ok,pixel=pcall(function()
        local VoxelFX=require('dragon.VoxelFX')
        return {
            slash=VoxelFX.Motes(scene,'SwordArcPixels',F.PIXEL_SLASH_CAPACITY,'square',true),
            impact=VoxelFX.Motes(scene,'SwordImpactPixels',F.PIXEL_IMPACT_CAPACITY,'square',true),
            charge=VoxelFX.Motes(scene,'SwordChargePixels',F.PIXEL_CHARGE_CAPACITY,'square',true),
        }
    end)
    self.pixelMode=ok and pixel~=nil
    if self.pixelMode then
        self.pixel=pixel
        self.pixelColors={
            slash={Color(1,1,1,1),Color(.44,.82,1,.90),Color(.14,.40,1,.52),Color(0,0,0,0)},
            heavy={Color(1,1,.88,1),Color(1,.72,.28,.92),Color(.36,.46,1,.58),Color(0,0,0,0)},
            impact={Color(1,1,1,1),Color(.55,.82,1,.90),Color(.16,.38,.95,.52),Color(0,0,0,0)},
            charge={Color(.86,.96,1,1),Color(.34,.72,1,.86),Color(.10,.32,.90,.44),Color(0,0,0,0)},
        }
    end
    self.technique=cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'):Clone('CombatFxAlpha')
    local pass=self.technique:GetPass('base')
    pass:SetBlendMode(BLEND_ALPHA);pass:SetDepthWrite(false);pass:SetDepthTestMode(CMP_LESSEQUAL)
    -- Light-like layers (edge, ghosts) add onto the scene so overlaps glow.
    self.additive=cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'):Clone('CombatFxAdd')
    pass=self.additive:GetPass('base')
    pass:SetBlendMode(BLEND_ADDALPHA);pass:SetDepthWrite(false);pass:SetDepthTestMode(CMP_LESSEQUAL)
    -- RuinsPalette: marble105, gold109, rune111, stone103, dark147;
    -- 6 crystal blue body, 7 ice-white edge, 8 deep sapphire (combo finisher).
    local palette={{1,.96,.83},{.95,.74,.32},{.35,.55,1},{.66,.67,.68},{.32,.33,.38},
        {.22,.58,1},{.80,.94,1},{.16,.34,1}}
    for i,c in ipairs(palette) do
        self.colors[i]={}
        for j=0,16 do self.colors[i][j+1]=Variant(Color(c[1],c[2],c[3],j/16)) end
    end
    for i=1,F.LANDING_COUNT do self.land[i]=slot(self,i==1 and 'ring' or (i==30 and 'star' or 'cube'),i) end
    for i=1,F.ARC_COUNT do self.arcs[i]=slot(self,'arc',i);self.edges[i]=slot(self,'arc',i,true) end
    for i=1,F.GHOST_COUNT do self.ghosts[i]=slot(self,'arc',i+F.ARC_COUNT,true) end
    return self
end
local function spawnPixel(pool,pos,vel,life,size,colors,drag)
    if pool then pool:Spawn{pos=pos,vel=vel,life=life,size=size,colors=colors,drag=drag or 1.8} end
end
local function pixelSlash(self,pos,dir,heavy)
    if not self.pixelMode then return end
    local colors=heavy and self.pixelColors.heavy or self.pixelColors.slash
    local speed=heavy and .18 or .10
    spawnPixel(self.pixel.slash,pos,dir*speed,heavy and .28 or .20,heavy and .034 or .024,colors,2.1)
    spawnPixel(self.pixel.slash,pos-dir*.045,dir*(speed*.35),heavy and .34 or .24,heavy and .020 or .015,colors,2.4)
end
local function pixelImpact(self,pos,forward)
    if not self.pixelMode then return end
    local colors=self.pixelColors.impact
    for i=1,18 do
        local a=(i-1)*math.pi*2/18+.23
        local speed=1.1+(i%4)*.25
        local dir=Vector3(math.cos(a),.18+(i%3)*.08,math.sin(a))
        spawnPixel(self.pixel.impact,pos+forward*.12+dir*.06,dir*speed,.34+(i%4)*.05,.018+(i%3)*.006,colors,2.0)
    end
    spawnPixel(self.pixel.impact,pos+forward*.18,forward*.35,.24,.040,colors,2.8)
end
local function show(self,s,x,y,z,sx,sy,sz,color,ttl)
    s.pos=set(s.pos,x,y,z);s.scale=set(s.scale,sx,sy,sz)
    s.node.position=s.pos;s.node.scale=s.scale;s.node.enabled=true
    s.color,s.ttl,s.age,s.active=color,ttl,0,true
    s.vx,s.vy,s.vz=0,0,0
    s.mat:SetShaderParameter('MatDiffColor',self.colors[s.arc and 7 or color][math.floor((s.peak or 1)*16)+1])
end
function F:Impact(pos,forward)
    pixelImpact(self,pos,forward)
    local radius=1.5
    local cx,cz=pos.x+forward.x*.65,pos.z+forward.z*.65
    local ring=self.land[1]
    show(self,ring,cx,pos.y+.035,cz,.3,1,.3,3,.28)
    ring.radius=radius
    ring.forwardX,ring.forwardZ=forward.x,forward.z
    ring.centerX,ring.centerZ=cx,cz
    ring.narrow=.55
    ring.rot:FromEulerAngles(0,math.deg(math.atan(forward.x,forward.z)),0);ring.node.rotation=ring.rot
    for i=2,15 do
        local s=self.land[i];local a=(i-2)*math.pi*2/14+.19
        local r=.18+(i%3)*.07;local size=.06+(i%4)*.018
        show(self,s,cx+math.cos(a)*r,pos.y+.08,cz+math.sin(a)*r,size,size,size,i%7==0 and 2 or (i%11==0 and 3 or 4),.5+(i%5)*.05)
        s.ground=pos.y+size*.5;s.vx=math.cos(a)*(1.2+i%3*.4);s.vz=math.sin(a)*(1.2+i%3*.4);s.vy=2+i%4*.25;s.size=size
    end
    -- Six flat stone chips knocked loose (no long fissure bars).
    for i=16,21 do
        local a=(i-16)*math.pi/3+.3;local s=self.land[i]
        show(self,s,cx+math.cos(a)*.5,pos.y+.018,cz+math.sin(a)*.5,.10,.018,.10,5,.6)
        s.rot:FromEulerAngles(0,math.deg(a)+38,0);s.node.rotation=s.rot
    end
    for i=22,29 do
        local s=self.land[i];local a=(i-22)*math.pi/4
        show(self,s,cx,pos.y+.12,cz,.035,.055,.035,i%3==0 and 3 or 2,.12+(i%4)*.03)
        s.ground=pos.y+.02;s.vx,s.vy,s.vz=math.cos(a)*2,1.5+i%3*.4,math.sin(a)*2;s.size=.035
    end
    show(self,self.land[30],cx,pos.y+.08,cz,.55,.055,.55,1,2/60+.15)
    self.land[30].fresh,self.land[30].frames=true,0
end
function F:Contact(pos)
    if not pos then return end
    if self.pixelMode then
        for i=1,12 do
            local a=(i-1)*math.pi*2/12+.17
            local dir=Vector3(math.cos(a),.45+(i%3)*.16,math.sin(a))
            spawnPixel(self.pixel.impact,pos+dir*.04,dir*(1.4+(i%3)*.3),.22+(i%3)*.04,.016+(i%2)*.008,self.pixelColors.impact,2.4)
        end
    end
    -- Eight ice-blue crystal shards burst from the contact point.
    for i=22,29 do
        local s=self.land[i];local a=(i-22)*math.pi*.25+.2
        local size=i%2==0 and .05 or .035
        show(self,s,pos.x,pos.y,pos.z,size,size,size,i%2==0 and 7 or 6,.18+(i%3)*.03)
        local speed=2.2+(i%3)*.6
        s.vx,s.vy,s.vz=math.cos(a)*speed,1.2+(i%4)*.5,math.sin(a)*speed;s.ground=pos.y-.6;s.size=size
    end
end
function F:Begin(combo,heavy)
    self.valid=false
    self.slash=heavy or (combo and combo>=1 and combo<=5)
    self.spin=combo==4 and not heavy -- the cross slash is two straight diagonals
    -- Exaggerated crystal slash: wide translucent blue body, longer linger.
    local base=heavy and .8 or (combo==5 and .85 or (combo==4 and .7 or (combo==3 and .65 or .55)))
    self.width=base*1.05
    self.ttl=(heavy or combo==4 or combo==5) and .24 or .18
    self.color=(heavy or combo==5) and 8 or 6
    self.ghostStep=0
    if self.pixelMode then self.pixel.slash:Clear();self.pixel.charge:Clear() end
end
function F:Segment(root,tip)
    if self.valid then
        local dx,dy,dz=tip.x-self.tip.x,tip.y-self.tip.y,tip.z-self.tip.z
        local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
        if distance>.015 and distance<3 then
            self.head=self.head%F.ARC_COUNT+1;local s=self.arcs[self.head]
            s.x=set(s.x,dx/distance,dy/distance,dz/distance)
            local ax,ay,az=tip.x-root.x,tip.y-root.y,tip.z-root.z
            local dot=ax*s.x.x+ay*s.x.y+az*s.x.z
            ax,ay,az=ax-dot*s.x.x,ay-dot*s.x.y,az-dot*s.x.z
            local length=math.sqrt(ax*ax+ay*ay+az*az)
            if length>1e-5 then
                s.y=set(s.y,ax/length,ay/length,az/length)
                s.z=set(s.z,s.x.y*s.y.z-s.x.z*s.y.y,s.x.z*s.y.x-s.x.x*s.y.z,s.x.x*s.y.y-s.x.y*s.y.x)
                s.rot:FromAxes(s.x,s.y,s.z);s.node.rotation=s.rot
                local cx,cy,cz=(tip.x+self.tip.x)*.5,(tip.y+self.tip.y)*.5,(tip.z+self.tip.z)*.5
                s.peak=.62
                show(self,s,cx,cy,cz,distance*1.2,self.width,1,self.color or 6,self.ttl)
                -- Thin additive edge hugging the tip path: the bright 刀光 line.
                local e=self.edges[self.head]
                e.peak=.9;e.rot:FromAxes(s.x,s.y,s.z);e.node.rotation=e.rot
                show(self,e,cx,cy,cz,distance*1.25,.07+self.width*.08,1,7,self.ttl*.55)
                if self.pixelMode then
                    pixelSlash(self,Vector3(cx,cy,cz),Vector3(s.x.x,s.x.y,s.x.z),self.color==8)
                end
                -- Full-blade ghost streaks read as thin light pillars next to the
                -- continuous crescent ribbon; kept pooled but no longer emitted.
                self.ghostStep=self.ghostStep+1
                if F.GHOSTS and self.ghostStep%3==1 then
                    self.ghostHead=self.ghostHead%F.GHOST_COUNT+1
                    local g=self.ghosts[self.ghostHead]
                    local blade=math.sqrt((tip.x-root.x)^2+(tip.y-root.y)^2+(tip.z-root.z)^2)
                    g.peak=.55;g.rot:FromAxes(s.x,s.y,s.z);g.node.rotation=g.rot
                    show(self,g,tip.x,tip.y,tip.z,.16,blade,1,6,self.ttl*.9)
                end
            end
        end
    end
    self.tip=set(self.tip,tip.x,tip.y,tip.z);self.root=set(self.root,root.x,root.y,root.z);self.valid=true
end
function F:ContactArc(zone)
    if not self.pixelMode or not zone then return end
    local count=10;local half=math.rad(zone.angle*.5);local origin=zone.origin;local forward=zone.forward
    for i=1,count do
        local a=-half+2*half*(i-.5)/count
        local x,z=math.sin(a),math.cos(a)
        local dx,dz=x*forward.z+z*forward.x,z*forward.z-x*forward.x
        local p=origin+Vector3(dx*zone.radius,.9,dz*zone.radius)
        spawnPixel(self.pixel.slash,p,Vector3(dx*.12,.02,dz*.12),.20,.023,self.pixelColors.heavy,2.5)
    end
end
function F:Charge(root,tip,charge)
    if not self.pixelMode or not root or not tip then return end
    self.chargePhase=(self.chargePhase or 0)+1
    if self.chargePhase%2==0 then return end
    local u=.18+.64*math.max(0,math.min(1,charge or 0))
    local p=root+(tip-root)*u
    local delta=tip-root;local len=delta:Length();if len<1e-5 then return end
    local d=delta:Normalized()
    local side=Vector3(-d.z,.18,d.x)
    spawnPixel(self.pixel.charge,p+side*.045,d*.05,.24,.019,self.pixelColors.charge,1.8)
    spawnPixel(self.pixel.charge,p-side*.045,d*-.03,.30,.014,self.pixelColors.charge,2.0)
end
function F:ChargeBurst(pos)
    if not self.pixelMode or not pos then return end
    for i=1,16 do
        local a=(i-1)*math.pi*2/16
        local d=Vector3(math.cos(a),.15+(i%4)*.08,math.sin(a))
        spawnPixel(self.pixel.impact,pos+d*.035,d*(.75+(i%3)*.18),.28+(i%3)*.04,.021,self.pixelColors.heavy,2.2)
    end
end
-- Subdivide the measured blade rotation, not the gameplay strike sector.
-- Bounded work even for low FPS; interpolated roots preserve actor translation.
function F:Blade(root,tip)
    if not self.slash then return end
    if not self.valid then self:Segment(root,tip);return end
    local rx,ry,rz=self.root.x,self.root.y,self.root.z
    local ax,ay,az=self.tip.x-rx,self.tip.y-ry,self.tip.z-rz
    local bx,by,bz=tip.x-root.x,tip.y-root.y,tip.z-root.z
    local al=math.sqrt(ax*ax+ay*ay+az*az);local bl=math.sqrt(bx*bx+by*by+bz*bz)
    if al<1e-5 or bl<1e-5 then self.valid=false;return end
    local angle=math.acos(clamp((ax*bx+ay*by+az*bz)/(al*bl),-1,1))
    -- A fast authored positive XZ revolution can advance >180 degrees at
    -- 30 Hz. Preserve its direction instead of drawing the shortest reverse arc.
    local crossY=az*bx-ax*bz
    if self.spin and angle>math.pi*.5 and crossY>al*bl*.05
        and math.abs(ay/al)<.6 and math.abs(by/bl)<.6 then angle=math.pi*2-angle end
    local count=math.min(8,math.max(1,math.ceil(angle/math.rad(15))))
    local sine=math.sin(angle)
    for i=1,count do
        local u=i/count;local a,b=1-u,u
        if math.abs(sine)>.001 then a=math.sin((1-u)*angle)/sine;b=math.sin(u*angle)/sine end
        local x,y,z=rx+(root.x-rx)*u,ry+(root.y-ry)*u,rz+(root.z-rz)*u
        self.sampleRoot=set(self.sampleRoot,x,y,z)
        self.sampleTip=set(self.sampleTip,x+ax*a+bx*b,y+ay*a+by*b,z+az*a+bz*b)
        self:Segment(self.sampleRoot,self.sampleTip)
    end
end
local function ageSlot(self,s,dt)
    if not s.active then return end
    s.age=s.age+dt
    if s.age>=s.ttl then s.active=false;s.node.enabled=false;return end
    local alpha=clamp(1-s.age/s.ttl,0,1)
    alpha=alpha*alpha*(3-2*alpha)*(s.peak or 1) -- hold the head, then fade fast
    s.mat:SetShaderParameter('MatDiffColor',self.colors[s.arc and s.age<.03 and 7 or s.color][math.floor(alpha*16)+1])
end
function F:Update(dt)
    if self.pixelMode then
        self.pixel.slash:Update(dt);self.pixel.impact:Update(dt);self.pixel.charge:Update(dt)
    end
    for i,s in ipairs(self.land) do
        -- Impact is emitted before Rig.Update. Preserve the first presented
        -- centre flash instead of consuming it entirely on a 30 Hz frame.
        local elapsed=dt
        if i==30 and s.fresh then elapsed=0;s.fresh=false end
        ageSlot(self,s,elapsed)
        if s.active then
            if i==1 then
                local u=1-(1-s.age/s.ttl)^3;local radius=.3+(s.radius-.3)*u
                s.scale=set(s.scale,radius*s.narrow,1,radius);s.node.scale=s.scale
                s.pos=set(s.pos,s.centerX+s.forwardX*u*.65,s.pos.y,s.centerZ+s.forwardZ*u*.65);s.node.position=s.pos
            elseif i>=2 and i<=15 or i>=22 and i<=29 then
                local dy=s.vy*dt-6*dt*dt
                s.pos=set(s.pos,s.pos.x+s.vx*dt,math.max(s.ground,s.pos.y+dy),s.pos.z+s.vz*dt)
                s.vy=s.vy-12*dt
                if s.pos.y<=s.ground then s.vx,s.vy,s.vz=0,0,0 end
                s.node.position=s.pos
            elseif i==30 then
                s.frames=s.frames+1
                s.color=s.frames<=2 and 1 or 2
                s.mat:SetShaderParameter('MatDiffColor',self.colors[s.color][math.floor((1-s.age/s.ttl)*16)+1])
                local u=1-s.age/s.ttl
                s.scale=set(s.scale,.55*u,.055,.55*u);s.node.scale=s.scale
            end
        end
    end
    for _,s in ipairs(self.arcs) do ageSlot(self,s,dt) end
    for _,s in ipairs(self.edges) do ageSlot(self,s,dt) end
    for _,s in ipairs(self.ghosts) do ageSlot(self,s,dt) end
end
local function clearPool(pool)
    for _,s in ipairs(pool) do s.active=false;s.node.enabled=false end
end
function F:ClearSword()
    self.valid,self.slash=false,false
    clearPool(self.arcs);clearPool(self.edges);clearPool(self.ghosts)
    if self.pixelMode then self.pixel.slash:Clear();self.pixel.charge:Clear() end
end
function F:Clear()
    self:ClearSword();clearPool(self.land)
    if self.pixelMode then self.pixel.impact:Clear() end
end
function F:Dispose()
    if self.pixelMode then
        for _,pool in pairs(self.pixel) do pool:Clear();pool.node:Remove() end
    end
    for _,pool in ipairs({self.land,self.arcs,self.edges,self.ghosts}) do
        for _,s in ipairs(pool) do s.node:Remove();s.mat:Dispose() end
    end
end
return F
