-- Visual-only volumes follow the DragonRig CreateVolume/SetParent pattern.
-- Voxel pieces are pre-split for armor presentation; no runtime grid rebuilds.
---@class EnemyVisual
---@field root Node
---@field body Node
---@field world VoxelPhysicsWorld
---@field pieces table[]
---@field warnings table<string, Node>
---@field bones table<string, Node>
local Visual={}
Visual.__index=Visual
local paletteWorlds=setmetatable({}, {__mode='k'})
local PALETTE={
    [200]={.32,.46,.23},[201]={.53,.63,.35},[202]={.22,.27,.21},
    [203]={.40,.44,.39},[204]={.59,.62,.52},[205]={.76,.50,.20},[206]={.75,.69,.43},
    [208]={.40,.49,.59},[209]={.61,.70,.76},[210]={.23,.30,.39},
    [211]={.27,.68,1,2.4},[212]={.65,.88,1,1.3},
    [216]={.61,.60,.55},[217]={.78,.76,.68},[218]={.34,.35,.33},
    [219]={.61,.37,.19},[220]={.85,.60,.32},[221]={1,.73,.31,2.6},
    [222]={1,.89,.57,1.5},[223]={.24,.23,.22},
    [239]={200/255,80/255,60/255,1.7},
}
Visual.PALETTE=PALETTE
function Visual.SetupPalette(world)
    if paletteWorlds[world] then return end
    for index,c in pairs(PALETTE) do
        world:SetPaletteEntry(index,Color(c[1],c[2],c[3]),100)
        world:SetPaletteEntryPBR(index,.83,index==219 and .35 or 0,.5,
            Color(c[1],c[2],c[3],c[4] or 0))
    end
    paletteWorlds[world]=true
end

-- Pure numeric sculpting also runs in Lua 5.4 tests. Each chunk owns its cells.
function Visual.Sculpt(config)
    local chunks,total={},0
    local s=config.voxelSize
    for _,p in ipairs(config.sculpt) do
        local buckets={}
        local nx,ny,nz=math.ceil(p[5]*2/s),math.ceil(p[6]*2/s),math.ceil(p[7]*2/s)
        for x=0,nx-1 do for y=0,ny-1 do for z=0,nz-1 do
            local px,py,pz=(x+.5)*s-p[5],(y+.5)*s-p[6],(z+.5)*s-p[7]
            if (px/p[5])^2+(py/p[6])^2+(pz/p[7])^2<=1 then
                local split=(p[1]=='body' or p[1]=='back_armor' or p[1]=='shell')
                local key=split and (1+(px>0 and 1 or 0)+(py>0 and 2 or 0)+(pz>0 and 4 or 0)) or 1
                local b=buckets[key]
                if not b then
                    b={name=p[1],cells={},origin={p[2]-p[5],p[3]-p[6],p[4]-p[7]},
                        nx=nx,ny=ny,nz=nz,center={p[2],p[3],p[4]},octant=key}
                    buckets[key]=b; chunks[#chunks+1]=b
                end
                local color=py>p[6]*.35 and p[9] or p[8]
                if (x+z*2)%9==0 then color=p[10] end
                b.cells[#b.cells+1]={x,y,z,color}; total=total+1
            end
        end end end
    end
    assert(total<=3000,'enemy voxel budget exceeded: '..config.kind..' '..total)
    return chunks,total
end

local measures=setmetatable({}, {__mode='k'})
-- Initialization-only occupancy count. Estimates unmerged exposed voxel faces,
-- including surfaces between independently rendered pieces; not actual GPU triangles.
function Visual.Measure(config)
    if measures[config] then return measures[config] end
    local chunks,count=Visual.Sculpt(config)
    local faces=0
    for _,chunk in ipairs(chunks) do
        local occupied={}
        local function key(x,y,z) return x..','..y..','..z end
        for _,c in ipairs(chunk.cells) do occupied[key(c[1],c[2],c[3])]=true end
        for _,c in ipairs(chunk.cells) do
            local x,y,z=c[1],c[2],c[3]
            if not occupied[key(x-1,y,z)] then faces=faces+1 end
            if not occupied[key(x+1,y,z)] then faces=faces+1 end
            if not occupied[key(x,y-1,z)] then faces=faces+1 end
            if not occupied[key(x,y+1,z)] then faces=faces+1 end
            if not occupied[key(x,y,z-1)] then faces=faces+1 end
            if not occupied[key(x,y,z+1)] then faces=faces+1 end
        end
    end
    local metrics={voxelCount=count,surfaceFacesEstimate=faces,drawSubmissionsEstimate=#chunks}
    measures[config]=metrics
    return metrics
end

---@param scene Scene
---@param world VoxelPhysicsWorld
function Visual.New(scene,world,config)
    local self=setmetatable({},Visual)
    self:Init(scene,world,config)
    return self
end
function Visual:Init(scene,world,config)
    local started=os.clock()
    Visual.SetupPalette(world)
    self.world,self.config=world,config
    self.root=scene:CreateChild('Enemy_'..config.kind)
    self.body=self.root:CreateChild('body_pose')
    self.pieces,self.bones,self.warnings={},{},{}
    self.removed=false
    self.flashSupported=false
    local chunks,count=Visual.Sculpt(config)
    self.voxelCount=count
    for index,p in ipairs(chunks) do
        local bone=self.bones[p.name]
        if not bone then
            bone=self.body:CreateChild(p.name)
            bone.position=Vector3(p.center[1],p.center[2],p.center[3])
            self.bones[p.name]=bone
        end
        local vol=world:CreateVolume(p.nx,p.ny,p.nz,config.voxelSize,Vector3.ZERO,Quaternion())
        local grid=vol:GetGrid()
        for _,v in ipairs(p.cells) do grid:SetSolid(v[1],v[2],v[3],true); grid:SetVoxelMaterial(v[1],v[2],v[3],v[4]) end
        vol.destructible,vol.evictable=false,false
        vol.collisionLayer,vol.collisionMask=0,0 -- also exclude visual voxels from grid ray queries
        vol:RebuildGeometry()
        local node=vol:GetNode()
        node:SetParent(bone)
        node.rotation=Quaternion()
        local rest=Vector3(p.origin[1]-p.center[1],p.origin[2]-p.center[2],p.origin[3]-p.center[3])
        node.position=rest
        local a=index*2.399963
        -- Only clone an existing color-aware material. Unsupported voxel shaders
        -- retain original palette/material and use the local pose fallback.
        local material,baseColor,brightColor
        if vol.GetMaterial then
            local original=vol:GetMaterial()
            if original and original.GetShaderParameter then
                local color=original:GetShaderParameter('MatDiffColor')
                if color and not color:IsEmpty() then
                    material=original:Clone('enemy_hit_'..config.kind..'_'..index)
                    baseColor=color
                    local c=color:GetVector4()
                    brightColor=Variant(Color(c.x*1.6,c.y*1.6,c.z*1.6,c.w))
                    vol:SetMaterial(material); self.flashSupported=true
                end
            end
        end
        self.pieces[#self.pieces+1]={volume=vol,node=node,rest=rest,name=p.name,
            material=material,baseColor=baseColor,brightColor=brightColor,lit=false,
            vx=math.cos(a)*(1.1+index%3*.25),vy=.6+(index%5)*.2,vz=math.sin(a)*(1.1+index%3*.25)}
    end
    for _,a in ipairs(config.attacks) do
        if not self.warnings[a.warning] then self.warnings[a.warning]=self:MakeWarning(a.warning) end
    end
    if config.boss then self.phaseRing=self:MakeWarning('ring',true) end
    self.rebuildCpuMs=(os.clock()-started)*1000
end

function Visual:MakeWarning(kind,decorative)
    local node=self.root:CreateChild('warning_'..kind)
    local geom=node:CreateComponent('CustomGeometry')
    geom:BeginGeometry(0,TRIANGLE_LIST)
    local function pixel(x,z,size)
        x,z=math.floor(x/size+.5)*size,math.floor(z/size+.5)*size
        local h=size*.48
        local vertices={Vector3(x-h,0,z-h),Vector3(x-h,0,z+h),Vector3(x+h,0,z+h),
            Vector3(x-h,0,z-h),Vector3(x+h,0,z+h),Vector3(x+h,0,z-h)}
        for _,v in ipairs(vertices) do geom:DefineVertex(v); geom:DefineNormal(Vector3.UP) end
    end
    if kind=='line' then
        for i=0,28 do pixel(-.075,i/28,.045); pixel(.075,i/28,.045) end
    else
        local span=kind=='fan' and math.pi*2/3 or math.pi*2
        for i=0,47 do
            local a=-span/2+span*i/47
            pixel(math.sin(a),math.cos(a),.065)
        end
        if kind=='fan' then
            for i=1,14 do
                pixel(math.sin(span/2)*i/14,math.cos(span/2)*i/14,.065)
                pixel(-math.sin(span/2)*i/14,math.cos(span/2)*i/14,.065)
            end
        end
    end
    geom:Commit()
    local mat=Material:new()
    mat:SetTechnique(0,cache:GetResource('Technique','Techniques/NoTextureUnlit.xml'))
    mat:SetShaderParameter('MatDiffColor',Variant(decorative and Color(.38,.35,.25,1) or Color(200/255,80/255,60/255,1)))
    mat:SetCullMode(CULL_NONE)
    geom:SetMaterial(mat)
    node.position=Vector3(0,.06,0); node.enabled=false
    return node
end

---@param enemy EnemyBase
function Visual:Update(enemy)
    if self.removed then return end
    self.root.position=enemy.position
    self.root.rotation=Quaternion(enemy.yaw,Vector3.UP)
    local roll=math.rad(enemy.poseRoll or 0)
    local pivot=enemy.posePivot
    self.body.position=Vector3(pivot*math.sin(roll),(enemy.config.hover or 0)+enemy.poseY+pivot*(1-math.cos(roll)),0)
    self.body.rotation=(enemy.poseRoll or 0)~=0 and Quaternion(enemy.poseRoll,Vector3.FORWARD)
        or Quaternion(enemy.posePitch or 0,Vector3.RIGHT)
    self.body.scale=Vector3(1,1,1) -- down is a rigid side-roll, never a squash
    local step=enemy.warning.step
    for kind,node in pairs(self.warnings) do
        node.enabled=enemy.warning.visible and kind==enemy.warning.kind
        if node.enabled then
            local radius=enemy.warning.radius*(.25+.75*step/6)
            node.scale=Vector3(radius,1,radius)
        end
    end
    if self.bones.core and enemy.parts.back_armor then self.bones.core.enabled=enemy.parts.back_armor.broken end
    local pulse=enemy.phasePulse or 0
    if self.phaseRing then
        local t=enemy.rageTime or 0
        self.phaseRing.enabled=enemy.rageActive and not enemy.down and t>=.45 and t<.70 and not enemy.dead
        self.phaseRing:SetScale(.5+3.5*math.floor(math.max(0,t-.45)/.25*6)/6)
    end
    if self.bones.back_armor then self.bones.back_armor.enabled=not enemy.parts.back_armor.broken end
    local reaction=enemy.reaction
    local recoil=math.max(0,1-reaction.age/.12)
    for name,bone in pairs(self.bones) do
        if not enemy.dead then
            local angle=0
            if name:find('leg') or name:find('rear') then
                angle=(enemy.state=='CHASE' or enemy.state=='PATROL') and math.sin(enemy.age*9)*14 or 0
                if enemy.state=='TELEGRAPH' and enemy.attack.name=='sweep' then angle=angle-35 end
                if enemy.down then angle=angle+math.sin(enemy.stateTime*8)*8 end
                if enemy.rageActive and not enemy.down and name:find('foreleg') then
                    local t=enemy.rageTime or 0
                    local brace=t<.2 and t/.2 or (t<.7 and 1 or math.max(0,1-(t-.7)/.3))
                    angle=-12*brace
                end
            elseif name=='head' then
                angle=enemy.state=='TELEGRAPH' and 22 or (enemy.state=='ALERT' and -15 or 0)
                if enemy.rageActive and not enemy.down then
                    local t=enemy.rageTime or 0
                    if t<.2 then angle=8*t/.2
                    elseif t<.45 then angle=8-38*(t-.2)/.25
                    elseif t<.7 then angle=-30
                    else angle=-30*math.max(0,1-(t-.7)/.3) end
                end
            end
            if name==reaction.part then angle=angle-(reaction.angle or 0)*recoil end
            bone.rotation=Quaternion(angle,Vector3.RIGHT)
        end
    end
    for _,p in ipairs(self.pieces) do
        local localHit=p.name==reaction.part
        local micro=localHit and reaction.shift*recoil or 0
        if not enemy.dead then
            p.node.position=p.rest+Vector3(reaction.dx*micro,reaction.dy*micro,reaction.dz*micro)
        elseif not p.deathRest then p.deathRest=p.node.position end
        p.node:SetScale(1)
        if not enemy.dead and pulse>0 and p.name=='back_armor' and not enemy.parts.back_armor.broken then
            p.node.position=p.node.position+Vector3(0,math.sin((enemy.rageTime or 0)*24)*.025,0)
        end
        local bright=(localHit and reaction.age<reaction.flash)
            or (enemy.rageActive and (enemy.rageTime or 0)>=.2 and (enemy.rageTime or 0)<.7 and p.name=='back_armor')
        if p.material and bright~=p.lit then
            p.material:SetShaderParameter('MatDiffColor',bright and p.brightColor or p.baseColor)
            p.lit=bright
        end
        if enemy.dead and enemy.deathTime>=.12 and enemy.deathTime<.25 then
            local loosen=(enemy.deathTime-.12)/.13
            p.node.position=p.deathRest+Vector3(p.vx*.07*loosen,-.06*loosen,p.vz*.07*loosen)
        end
    end
    if enemy.dead then
        local t=enemy.deathTime
        if t+1e-8>=1.1 then self.root.enabled=false; self:Destroy(); return end
        self.body.enabled=t<.25 -- .12s hold, .13s loosen, then pooled fragments
    end
end
function Visual:Destroy()
    if self.removed then return end
    self.removed=true
    for _,p in ipairs(self.pieces) do self.world:RemoveVolume(p.volume) end
    self.root:Remove()
end
return Visual
