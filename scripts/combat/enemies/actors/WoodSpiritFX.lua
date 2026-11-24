-- Ground contact envelope and short-lived chips for the wood spirit. All positions
-- in the chip pool are world space, so landed splinters stay put as the actor moves.
local FX = {}
local min,max,sqrt = math.min,math.max,math.sqrt

-- Union of the frontal hit sector translated from zero to attack.travel.
-- Base:CanDamage includes .32m for the player's capsule.
function FX.HalfWidth(a, z)
    local radius = a.hitRange + .32
    if z <= 0 or z >= a.travel + radius then return 0 end
    local peak = radius*a.cosine
    local sample = max(z-a.travel, min(z,peak))
    return min(sample*sqrt(1-a.cosine^2)/a.cosine, sqrt(max(0,radius^2-sample^2)))
end

-- The swept sector widens to a straight middle section and ends in a round cap.
FX.SoilTint = {.75,.19,.10,.47}
FX.RimColors = {{.44,.075,.065},{1,.71,.34}}
function FX.SoilSections(a)
    local r = a.hitRange+.32
    local shoulder = r*a.cosine
    local width = FX.HalfWidth(a,shoulder)
    local sections = {{0,0},{shoulder,width},{shoulder+a.travel,width}}
    local angle = math.acos(a.cosine)
    for i=1,12 do
        local phi = angle*(1-i/12)
        sections[#sections+1] = {a.travel+r*math.cos(phi), r*math.sin(phi)}
    end
    return sections
end

FX.Atlas = 'Textures/fx/WoodSpiritBrush.png'
local shader = 'Shaders/BLGL/WoodSpiritBrush.shader'
local function brushMaterial(atlas, impact)
    if not atlas then return nil end
    local material=Material:new()
    if not material.SetSurfaceShader or not material:SetSurfaceShader(shader) then return nil end
    if not material:SetSurfaceTexture('brush_atlas',atlas) then return nil end
    material:SetShaderParameter('impact',Variant(impact))
    material:SetShaderParameter('phase',Variant(0.0))
    return material
end

local function soilSurface(node,a,material,textured)
    local soil = node:CreateChild('soil')
    soil.position = Vector3(0,-.014,0)
    local geom = soil:CreateComponent('CustomGeometry')
    geom.castShadows = false
    geom:BeginGeometry(0,TRIANGLE_LIST)
    local function vertex(x,z)
        geom:DefineVertex(Vector3(x/a.range,0,z/a.range))
        geom:DefineNormal(Vector3.UP)
        if textured then
            geom:DefineTexCoord(Vector2(.5+x/(2*(a.hitRange+.32)),z/a.range))
        end
    end
    local sections = FX.SoilSections(a)
    for i=2,#sections do
        local z0,w0 = table.unpack(sections[i-1])
        local z1,w1 = table.unpack(sections[i])
        if w1>0 then vertex(-w0,z0); vertex(-w1,z1); vertex(w1,z1) end
        if w0>0 then vertex(-w0,z0); vertex(w1,z1); vertex(w0,z0) end
    end
    geom:Commit(); geom:SetMaterial(material)
end

-- Inset both colours from the true sweep contour. In particular the light
-- ticks never advertise extra range past the nose. The uninterrupted inner lip
-- remains visible between the ticks on pale terrain.
function FX.RimQuads(a)
    local sections=FX.SoilSections(a)
    local border={}
    for _,s in ipairs(sections) do border[#border+1]={s[2],s[1]} end
    for i=#sections-1,2,-1 do border[#border+1]={-sections[i][2],sections[i][1]} end
    local middle=a.range*.5
    local bands={{},{}}
    for i,left in ipairs(border) do
        local right=border[i % #border+1]
        local dx,dz=right[1]-left[1],right[2]-left[2]
        local steps=math.ceil(sqrt(dx*dx+dz*dz)/.26)
        local function point(t,inset)
            return {(left[1]+dx*t)*(1-.19*inset), middle+(left[2]+dz*t-middle)*(1-.14*inset)}
        end
        local function strip(layer,start,finish,outer,inner)
            local quads=bands[layer]
            quads[#quads+1]={point(start,outer),point(finish,outer),point(finish,inner),point(start,inner)}
        end
        strip(1,0,1,.42,1)
        for j=1,steps do
            local start,finish=(j-1)/steps,j/steps
            local cut=finish-.22/steps
            strip(2,start,cut,0,.42)
            strip(1,cut,finish,0,.42)
        end
    end
    return bands
end

local function markWarning(visual, a, inks, soil, textured)
    local old = visual.warnings[a.warning]
    old:Remove()
    local node = visual.root:CreateChild('wood_contact_'..a.warning)
    visual.warnings[a.warning] = node
    node.enabled = false
    node.position = Vector3(0,.055,0)
    soilSurface(node,a,soil,textured)
    for layer,quads in ipairs(FX.RimQuads(a)) do
        local edge=node:CreateChild('rim_'..layer)
        local geom=edge:CreateComponent('CustomGeometry')
        geom.castShadows=false
        geom:BeginGeometry(0,TRIANGLE_LIST)
        for _,quad in ipairs(quads) do
            for _,i in ipairs({1,2,3,1,3,4}) do
                geom:DefineVertex(Vector3(quad[i][1]/a.range,0,quad[i][2]/a.range))
                geom:DefineNormal(Vector3.UP)
            end
        end
        geom:Commit(); geom:SetMaterial(inks[layer])
    end
end

-- The ground imprint sits beneath the chips. The contact cut faces outward from
-- the forehead. Both have independent clocks and retain their strike coordinates.
local function createStamp(root,stamp,atlas)
    stamp.material=brushMaterial(atlas,1.0)
    if not stamp.material then return end
    stamp.node=root:CreateChild('wood_'..stamp.event)
    stamp.node.enabled=false
    local g=stamp.node:CreateComponent('CustomGeometry')
    g.castShadows=false
    g:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{0,1},{1,1},{0,0},{1,1},{1,0}}) do
        g:DefineVertex(Vector3(uv[1]-.5,0,uv[2]-.5))
        g:DefineNormal(Vector3.UP)
        g:DefineTexCoord(Vector2(uv[1],uv[2]))
    end
    g:Commit(); g:SetMaterial(stamp.material)
end

local function stampPose(stamp)
    local phase=stamp.age/stamp.life
    stamp.scale=stamp.span*(.63+.37*min(1,phase/.42))
    if stamp.node then
        stamp.node.scale=Vector3(stamp.scale,1,stamp.scale)
        stamp.material:SetShaderParameter('phase',Variant(phase))
    end
end

function FX.New(enemy)
    local pool = {slots={}, next=1, phase=0, stamps={
        contact={event='contact',life=.22,span=1.10,pitch=-64,active=false},
        land={event='land',life=.29,span=1.50,pitch=0,active=false}}}
    local materials = {}
    if enemy.visual then
        pool.root = enemy.scene:CreateChild('WoodSpiritChips_'..enemy.id)
        for _,index in ipairs({1,2,6}) do
            local entry = enemy.visual.data.palette[index]
            local r,g,b = table.unpack(entry.rgb)
            local mat = Material:new()
            mat:SetTechnique(0,cache:GetResource('Technique','Techniques/PBR/PBRNoTexture.xml'))
            mat:SetShaderParameter('MatDiffColor',Variant(Color(r/255,g/255,b/255,1)))
            mat:SetShaderParameter('Roughness',Variant(entry.roughness))
            mat:SetShaderParameter('Metallic',Variant(entry.metallic))
            mat:SetShaderParameter('MatEmissiveColor',Variant(Color(r/255*entry.emission,g/255*entry.emission,b/255*entry.emission)))
            materials[index]=mat
        end
        local inks={}
        for i,c in ipairs(FX.RimColors) do
            local m=Material:new()
            m:SetTechnique(0,cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'))
            m:SetCullMode(CULL_NONE); m:SetShaderParameter('MatDiffColor',Variant(Color(c[1],c[2],c[3],1)))
            inks[i]=m
        end
        local soil=Material:new()
        soil:SetTechnique(0,cache:GetResource('Technique','Techniques/PBR/PBRNoTextureAlpha.xml'))
        soil:SetShaderParameter('MatDiffColor',Variant(Color(table.unpack(FX.SoilTint))))
        soil:SetShaderParameter('Roughness',Variant(.96))
        soil:SetShaderParameter('Metallic',Variant(0))
        soil:SetCullMode(CULL_NONE)
        local atlas=cache:GetResource('Texture2D',FX.Atlas)
        pool.brush=brushMaterial(atlas,0.0)
        for _,a in ipairs(enemy.config.attacks) do markWarning(enemy.visual,a,inks,pool.brush or soil,pool.brush~=nil) end
        for _,stamp in pairs(pool.stamps) do createStamp(pool.root,stamp,atlas) end
    end
    pool.materials = materials
    for i=1,10 do pool.slots[i]={alive=false} end
    return pool
end

local function present(slot)
    if not slot.node then return end
    slot.node.position=Vector3(slot.x,slot.y,slot.z)
    slot.node.rotation=Quaternion(slot.angle,slot.yaw,slot.angle*.4)
    slot.node.scale=Vector3(slot.width,slot.height,slot.depth)
    slot.node.enabled=true
end

-- Four root-tip chips under load, five at landing, three at forehead contact.
function FX.Emit(enemy,event)
    local pool=enemy.woodFX
    local forehead=event=='contact'
    local landing=event=='land'
    local count=forehead and 3 or (landing and 5 or 4)
    local stamp=pool.stamps[event]
    if stamp then
        local forward=forehead and .71 or .28
        stamp.x,stamp.z=enemy.position.x+enemy.fx*forward,enemy.position.z+enemy.fz*forward
        local ground=enemy.terrain.GroundHeight(stamp.x,stamp.z) or enemy.position.y
        stamp.y=forehead and enemy.position.y+.77 or ground+.065
        stamp.age,stamp.active,stamp.yaw=0,true,enemy.yaw
        stampPose(stamp)
        if stamp.node then
            stamp.node.position=Vector3(stamp.x,stamp.y,stamp.z)
            stamp.node.rotation=Quaternion(stamp.pitch,stamp.yaw,0)
            stamp.node.enabled=true
        end
    end
    for i=1,count do
        local slot=pool.slots[pool.next]
        pool.next=pool.next % #pool.slots+1
        local side=i%2==0 and -1 or 1
        local lateral=side*(forehead and .18 or .39)
        local forward=forehead and .65 or ((landing or i<3) and .28 or -.26)
        slot.x=enemy.position.x+enemy.fz*lateral+enemy.fx*forward
        slot.z=enemy.position.z-enemy.fx*lateral+enemy.fz*forward
        slot.y=enemy.position.y+(forehead and .77 or .06)
        local outward=side*(.39+.10*i)
        local push=forehead and .96 or (landing and .55 or -.25)
        slot.vx,slot.vz=enemy.fz*outward+enemy.fx*push,-enemy.fx*outward+enemy.fz*push
        slot.vy=.70+.16*i+(landing and .36 or 0)
        slot.palette=(forehead and i==2 or landing and i==5) and 6 or (i%2+1)
        slot.size=(slot.palette==6 and .055 or .065)+.004*i
        slot.age,slot.life,slot.angle,slot.yaw,slot.alive=0,.26+.024*i,i*22,enemy.yaw+side*25,true
        slot.width,slot.height,slot.depth=slot.size,slot.size*.53,slot.size*(slot.palette==6 and .8 or 1.55)
        if pool.root then
            if not slot.node then
                slot.node=pool.root:CreateChild('WoodChip')
                slot.mesh=slot.node:CreateComponent('StaticModel')
                slot.mesh:SetModel(cache:GetResource('Model','Models/Box.mdl'))
                slot.mesh.castShadows=false
            end
            slot.mesh:SetMaterial(pool.materials[slot.palette])
            present(slot)
        end
    end
end

function FX.Tick(enemy,dt)
    local pool=enemy.woodFX
    local phase=enemy.warning.visible and min(1,(enemy.stateTime+dt)/enemy.attack.telegraph) or 0
    if pool.phase~=phase then
        pool.phase=phase
        if pool.brush then pool.brush:SetShaderParameter('phase',Variant(phase)) end
    end
    for _,stamp in pairs(pool.stamps) do
        if stamp.active then
            stamp.age=stamp.age+dt
            if stamp.age>=stamp.life then
                stamp.active=false
                if stamp.node then stamp.node.enabled=false end
            else stampPose(stamp) end
        end
    end
    for _,s in ipairs(pool.slots) do
        if s.alive then
            s.age=s.age+dt
            if s.age>=s.life then
                s.alive=false
                if s.node then s.node.enabled=false end
            else
                s.x,s.z=s.x+s.vx*dt,s.z+s.vz*dt
                s.vy=s.vy-9.8*dt
                s.y=s.y+s.vy*dt
                local ground=enemy.terrain.GroundHeight(s.x,s.z)
                if ground and s.y<ground+.025 then s.y,s.vy=ground+.025,0 end
                s.angle=s.angle+dt*145
                local scale=s.age>s.life*.72 and .55 or 1
                s.width,s.height,s.depth=s.size*scale,s.size*scale*.53,s.size*scale*(s.palette==6 and .8 or 1.55)
                present(s)
            end
        end
    end
end

function FX.Clear(pool)
    pool.phase=0
    if pool.brush then pool.brush:SetShaderParameter('phase',Variant(0.0)) end
    for _,stamp in pairs(pool.stamps) do
        stamp.active=false
        if stamp.node then stamp.node.enabled=false end
    end
    for _,s in ipairs(pool.slots) do
        s.alive=false
        if s.node then s.node.enabled=false end
    end
end

function FX.Destroy(pool)
    FX.Clear(pool)
    if pool.root then
        pool.root:Remove()
        pool.root=nil
        for _,s in ipairs(pool.slots) do s.node,s.mesh=nil,nil end
        pool.materials={}
        pool.brush=nil
        for _,stamp in pairs(pool.stamps) do stamp.node,stamp.material=nil,nil end
    end
end

return FX
