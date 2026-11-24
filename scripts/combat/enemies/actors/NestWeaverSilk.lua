-- Local X/Y are fractions of the existing horizontal danger radius. Local Z
-- runs from -0.5 to +0.5 along the swept trajectory. The open fibres behind
-- the compact leading knot never extend beyond the swept head of the shot.
local Silk={}
local sin,cos,pi=math.sin,math.cos,math.pi
local palette={
    ribbon={.94,.59,.22,.48}, stitch={.93,.74,.50,.78}, flax={.99,.88,.66,1},
    twist={.49,.27,.135,1}, ochre={.81,.49,.22,1}, dust={.91,.72,.43,.74},
}
local batches={}
local function batch(group,tone)
    local b={group=group,color=palette[tone],quads={}}
    batches[#batches+1]=b
    return b
end

-- A flat-ended four-sided strand between two rectangular sections. Sharing
-- faces per material keeps dozens of separate stitches in a single draw.
local function fibre(b,x,y,z,X,Y,Z,w,h,endWidth,endHeight)
    local W,H=(endWidth or w)*.5,(endHeight or h)*.5
    w,h=w*.5,h*.5
    local v={{x-w,y-h,z},{x+w,y-h,z},{x+w,y+h,z},{x-w,y+h,z},
             {X-W,Y-H,Z},{X+W,Y-H,Z},{X+W,Y+H,Z},{X-W,Y+H,Z}}
    for _,f in ipairs({{1,4,3,2},{5,6,7,8},{1,2,6,5},{2,3,7,6},{3,4,8,7},{4,1,5,8}}) do
        b.quads[#b.quads+1]={v[f[1]],v[f[2]],v[f[3]],v[f[4]]}
    end
end

local ribbon,stitches=batch('warn','ribbon'),batch('warn','stitch')
for i=0,11 do
    local z=-.5+i/12
    local side=i%2==0 and 1 or -1
    -- Broken overlapping shuttles, with two detached selvedges delimiting the
    -- dodge lane. Gaps and a slight alternating twist stay readable end-on.
    fibre(ribbon,-.28*side,-.025,z,.28*side,.035,z+.066,.52,.16,.36,.10)
    fibre(ribbon,.31*side,.075,z+.015,-.23*side,.10,z+.068,.29,.11,.14,.08)
    for _,edge in ipairs({-1,1}) do
        local x=edge*(.82+.06*sin(i*2.1)); local y=.12*sin(i*1.6+edge)
        fibre(stitches,x,y,z+.018,x-edge*.06,y+.06,z+.026,.14,.11)
        if i%2==0 then fibre(stitches,x-edge*.17,y-.10,z+.048,x-edge*.15,y-.08,z+.055,.085,.08) end
    end
end
local mouth,mouthLint=batch('gather','ochre'),batch('gather','flax')
for i=0,7 do
    local angle=2*pi*i/8
    local x,y=cos(angle),sin(angle)
    fibre(mouth,.77*x,.77*y,.02,.37*cos(angle+.28),.37*sin(angle+.28),.51,.15,.14,.12,.10)
    fibre(mouthLint,.31*cos(angle+.28),.31*sin(angle+.28),.55,.075*x,.075*y,.83,.09,.08,.065,.05)
    fibre(mouthLint,.83*x,.83*y,.08,.81*x,.81*y,.18,.085,.08)
end
local core,ropes,flax=batch('bolt','flax'),batch('bolt','twist'),batch('bolt','ochre')
fibre(core,0,0,-.46,0,0,.46,.13,.14,.23,.19)
fibre(core,0,0,.41,0,0,.50,.23,.19,.13,.12)
for j=0,2 do
    -- Three thick cords twist around a pale core. Narrow the woven leading
    -- end to the contact diameter; let the trailing end fray into separate plies.
    local function section(i)
        local u=i/9; local angle=u*2.4*pi+j*2*pi/3
        local r=.11+.30*sin(pi*u)^.78+.10*(1-u)
        return cos(angle)*r,sin(angle)*r,-.49+.95*u
    end
    for i=0,8 do
        local x,y,z=section(i); local X,Y,Z=section(i+1)
        local w=i>=7 and .14 or .24
        fibre(j==1 and flax or ropes,x,y,z,X,Y,Z,w,w*.8,w*.86,w*.75)
    end
end
local flecks=batch('shed','dust')
for i=0,6 do
    local a=i*2.40; local r=.68+.15*sin(i*2)
    local z=-.49+.66*i/7
    fibre(flecks,r*cos(a),r*sin(a),z,(r-.05)*cos(a),(r-.05)*sin(a),z+.025+.02*(i%2),.11,.10)
end
-- Broad twisted brush surfaces give the little ink cuts enough projected area
-- to read. The PBR fallback only renders the original solid strand batches.
local brush=batch('gather','flax'); brush.card=true
for i=0,2 do
    local a=i*pi/3+.3;local x,y=.92*cos(a),.92*sin(a)
    brush.quads[#brush.quads+1]={{-x,-y,.04},{x,y,.04},{x*.7,y*.7,.94},{-x*.7,-y*.7,.94}}
end
local ply=batch('bolt','ochre'); ply.card=true
for i=0,1 do
    local a=i*pi/2+.45;local x,y=cos(a),sin(a)
    ply.quads[#ply.quads+1]={{-x*.67,-y*.67,-.48},{x*.67,y*.67,-.48},{x*.13,y*.13,.45},{-x*.13,-y*.13,.45}}
end
local remnant=batch('end','flax')
for i=0,5 do
    local a=i*2.4; local x,y=cos(a),sin(a)
    fibre(remnant,x*.22,y*.22,-.46,x*.69,y*.69,.36,.21,.14,.085,.06)
end
Silk.batches=batches
local cuts={warn=0,gather=1,bolt=2,shed=3,['end']=3}
local speeds={warn=1.2,gather=2.1,bolt=2.7,shed=1.3,['end']=.7}
for _,b in ipairs(batches) do
    b.cut=cuts[b.group]; b.rate=speeds[b.group]*(b.color==palette.twist and .48 or 1)
    b.backing=b.card and 0 or (b.group=='bolt' and .50 or .20)
end
-- U follows the length; V runs between the two banks of each brush.
local uvs={{0,0},{0,1},{1,1},{1,0}}
local indices={1,2,3,1,3,4}
local function mesh(node,b)
    local geo=node:CreateComponent('CustomGeometry')
    geo:BeginGeometry(0,TRIANGLE_LIST)
    for _,q in ipairs(b.quads) do
        local a,bp,c=q[1],q[2],q[3]
        local ux,uy,uz=bp[1]-a[1],bp[2]-a[2],bp[3]-a[3]
        local vx,vy,vz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
        local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
        local length=math.sqrt(nx*nx+ny*ny+nz*nz)
        local n=Vector3(nx/length,ny/length,nz/length)
        for _,k in ipairs(indices) do
            local v=q[k]; geo:DefineVertex(Vector3(v[1],v[2],v[3])); geo:DefineNormal(n)
            if geo.DefineTexCoord and Vector2 then geo:DefineTexCoord(Vector2(uvs[k][1],uvs[k][2])) end
        end
    end
    geo:Commit()
    return geo
end
local function inkMaterial(b,texture)
    local mat=Material:new()
    if not mat:SetSurfaceShader('Shaders/BLGL/NestWeaverSilk.shader') or not mat:SetSurfaceTexture('fibre_ink',texture) then return end
    local c=b.color
    mat:SetShaderParameter('silk_tint',Variant(Color(c[1],c[2],c[3],c[4])))
    mat:SetShaderParameter('cut',Variant(b.cut+0.0))
    mat:SetShaderParameter('rate',Variant(b.rate))
    mat:SetShaderParameter('backing',Variant(b.backing))
    return mat
end
local function fallback(c)
    local mat=Material:new()
    local technique=c[4]<1 and 'Techniques/PBR/PBRNoTextureAlpha.xml' or 'Techniques/PBR/PBRNoTexture.xml'
    mat:SetTechnique(0,cache:GetResource('Technique',technique))
    mat:SetShaderParameter('MatDiffColor',Variant(Color(c[1],c[2],c[3],c[4])))
    mat:SetShaderParameter('Roughness',Variant(.89)); mat:SetShaderParameter('Metallic',Variant(0))
    mat:SetShaderParameter('MatEmissiveColor',Variant(Color(c[1]*.22,c[2]*.22,c[3]*.22)))
    return mat
end
function Silk.New(root,endRoot)
    local fx={groups={},visible=false}
    local texture
    if root then
        local ok,value=pcall(function() return cache:GetResource('Texture2D','Textures/fx/NestWeaverSilk.png') end)
        if ok then texture=value end
    end
    for _,b in ipairs(batches) do
        local owner=root
        if b.group=='end' then owner=endRoot end
        local group=fx.groups[b.group]
        if not group then
            group={enabled=false,radial=1,depth=1,z=0,roll=0,meshes={},inks={}}
            fx.groups[b.group]=group
            if owner then group.node=owner:CreateChild(b.group) end
        end
        if owner then
            local mat
            if texture then
                local ok,ink=pcall(inkMaterial,b,texture)
                if ok and ink then mat=ink; group.inks[#group.inks+1]=ink end
            end
            if mat or not b.card then
                local geo=mesh(group.node:CreateChild('fibres'),b)
                geo:SetMaterial(mat or fallback(b.color)); geo.castShadows=false; geo.enabled=false
                group.meshes[#group.meshes+1]=geo
            end
        end
    end
    return fx
end
local function visible(g,on)
    if g.enabled==on then return end
    g.enabled=on
    for _,geo in ipairs(g.meshes) do geo.enabled=on end
end
local function transform(g,radial,depth,z,roll)
    g.radial,g.depth,g.z,g.roll=radial,depth,z,roll
    if g.node then
        g.node.position=Vector3(0,0,z); g.node.scale=Vector3(radial,radial,depth)
        g.node.rotation=Quaternion(roll,Vector3.FORWARD)
    end
end
local function clock(g,age)
    g.age=age
    for _,mat in ipairs(g.inks) do mat:SetShaderParameter('brush_age',Variant(age)) end
end
function Silk.EndFrame(fx,age)
    local g=fx.groups['end']
    visible(g,age<1)
    if age<1 then
        clock(g,age); transform(g,.45+.55*age,.8-.45*age,0,18*age)
    end
end
function Silk.Update(fx,aim,progress,length)
    local g=fx.groups
    fx.visible=true
    visible(g.warn,aim); visible(g.gather,aim); visible(g.bolt,not aim); visible(g.shed,not aim)
    if aim then
        clock(g.warn,progress); clock(g.gather,progress)
        local pulse=(progress*3)%1
        transform(g.warn,1,1,0,0)
        transform(g.gather,1-.58*pulse,math.min(1,.38/length),-.5,65*progress)
    else
        clock(g.bolt,progress); clock(g.shed,progress*.55)
        transform(g.bolt,1,1,0,95*progress)
        transform(g.shed,.48+.50*math.min(1,progress*3),1,0,-63*progress)
    end
end
function Silk.Hide(fx)
    fx.visible=false
    for _,g in pairs(fx.groups) do visible(g,false) end
end
return Silk
