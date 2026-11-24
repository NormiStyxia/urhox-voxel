-- World-space clock face. Six static meshes: only material opacity and transforms
-- change after construction. Every outer rim vertex is on the query cylinder.
local Field = {radius=2.8, bottom=-.18, top=1.6, warning=.85, duration=3.6, release=.48}
local TAU = 2 * math.pi
local function point(r,a,y) return Vector3(math.sin(a)*r, y, math.cos(a)*r) end
local function tri(g,a,b,c,n)
    g:DefineVertex(a); g:DefineNormal(n)
    g:DefineVertex(b); g:DefineNormal(n)
    g:DefineVertex(c); g:DefineNormal(n)
end
local function quad(g,a,b,c,d,n)
    tri(g,a,b,c,n); tri(g,a,c,d,n)
end
local function band(g,inner,outer,a,b,low,high)
    local p,q,r,s = point(inner,a,high),point(outer,a,high),point(outer,b,high),point(inner,b,high)
    quad(g,p,q,r,s,Vector3.UP)
    quad(g,q,point(outer,a,low),point(outer,b,low),r,point(1,(a+b)*.5,0))
    quad(g,s,point(inner,b,low),point(inner,a,low),p,point(-1,(a+b)*.5,0))
end
local function slab(g,x,y,z,w,h,d)
    local a,b,c,f=Vector3(x-w,y+h,z-d),Vector3(x-w,y+h,z+d),Vector3(x+w,y+h,z+d),Vector3(x+w,y+h,z-d)
    local aa,bb,cc,ff=Vector3(x-w,y-h,z-d),Vector3(x-w,y-h,z+d),Vector3(x+w,y-h,z+d),Vector3(x+w,y-h,z-d)
    quad(g,a,b,c,f,Vector3.UP); quad(g,aa,ff,cc,bb,Vector3(0,-1,0))
    quad(g,f,c,cc,ff,Vector3.RIGHT); quad(g,b,a,aa,bb,Vector3(-1,0,0))
    quad(g,c,b,bb,cc,Vector3.FORWARD); quad(g,a,f,ff,aa,Vector3(0,0,-1))
end
local function layer(root,name,color,build)
    local node=root:CreateChild(name)
    local g=node:CreateComponent('CustomGeometry'); g.castShadows=false
    g:BeginGeometry(0,TRIANGLE_LIST); build(g); g:Commit()
    local mat=Material:new()
    mat:SetTechnique(0,cache:GetResource('Technique','Techniques/PBR/PBRNoTextureAlpha.xml'))
    mat:SetCullMode(CULL_NONE)
    mat:SetShaderParameter('MatEmissiveColor',Variant(Color(color[1]*.65,color[2]*.65,color[3]*.65)))
    mat:SetShaderParameter('Roughness',Variant(.68)); g:SetMaterial(mat)
    return {node=node,geom=g,mat=mat,color=color}
end
local function opacity(layer,a)
    local step=math.floor(math.min(1,math.max(0,a))*64+.5)
    if layer.step==step then return end
    layer.step=step; layer.node.enabled=step>0
    local c=layer.color
    layer.mat:SetShaderParameter('MatDiffColor',Variant(Color(c[1],c[2],c[3],step/64)))
end
local R=Field.radius
-- Leave the geometric floor bound until both the shader and atlas are ready.
local function tryPrint(floor)
    if not floor.geom.DefineTexCoord then return end
    local tex=cache:GetResource('Texture2D','Textures/fx/TimeWraithDial.png')
    if not tex then return end
    local mat=Material:new()
    if not mat:SetSurfaceShader('Shaders/BLGL/TimeWraithDial.shader') then return end
    if not mat:SetSurfaceTexture('dial_atlas',tex) then return end
    floor.geom:SetMaterial(mat)
    floor.ink=mat
end
local function floorVertex(g,v)
    g:DefineVertex(v); g:DefineNormal(Vector3.UP)
    if g.DefineTexCoord then g:DefineTexCoord(Vector2(.5+v.x/(2*R),.5-v.z/(2*R))) end
end
function Field.New(scene)
    local f={root=scene:CreateChild('TimeWraithField')}
    f.root.enabled=false
    f.floor=layer(f.root,'GlassFace',{.07,.48,.42},function(g)
        local o=Vector3(0,.037,0)
        for i=0,95 do
            floorVertex(g,o); floorVertex(g,point(R,i*TAU/96,.037)); floorVertex(g,point(R,(i+1)*TAU/96,.037))
        end
    end)
    pcall(tryPrint,f.floor)
    f.rim=layer(f.root,'Bezel',{.35,.95,.79},function(g)
        for i=0,95 do
            local a,b=i*TAU/96,(i+1)*TAU/96
            band(g,R-.055,R,a,b,.04,.105)
            band(g,R*.71-.012,R*.71,a,b,.045,.053)
        end
    end)
    f.ticks=layer(f.root,'Indices',{1,.67,.24},function(g)
        for i=0,59 do
            local hour=i%5==0
            local w=hour and .024 or .009
            band(g,R-(hour and .44 or .20),R-.09,i*TAU/60-w,i*TAU/60+w,.05,hour and .14 or .09)
            if hour then
                local p=point(R-.08,i*TAU/60,.32)
                slab(g,p.x,p.y,p.z,.024,.17,.024)
            end
        end
    end)
    f.hand=layer(f.root,'ShadowHand',{.96,.84,.54},function(g)
        slab(g,0,.10,R*.32,.038,.023,R*.36)
        slab(g,0,.10,-.26,.095,.032,.09)
        band(g,.04,.16,0,TAU/4,.10,.15); band(g,.04,.16,TAU/4,TAU/2,.10,.15)
        band(g,.04,.16,TAU/2,.75*TAU,.10,.15); band(g,.04,.16,.75*TAU,TAU,.10,.15)
    end)
    local function sand(g,start)
        for i=start,47,2 do
            local a=i*2.399963
            local radius=R*math.sqrt((i+.5)/48)*.95
            local y=.16+((i*17)%47)/47*(Field.top-.31)
            local p=point(radius,a,y); local w=.021+.008*(i%3)
            slab(g,p.x,p.y,p.z,w,w*(i%4==0 and 2 or 1),w)
            if i%3==0 then
                slab(g,p.x,p.y-.075,p.z,w*.58,w*.72,w*.58)
                slab(g,p.x,p.y-.137,p.z,w*.32,w*.48,w*.32)
            end
        end
        -- Counter-drifting ribbons mark the top of the suspended sand.
        for arm=start,5,2 do
            for j=0,6 do
                local a=TAU*arm/6+j*.046
                local h=Field.top-.026*math.abs(j-3)-.075*start
                local outer=R-.055-.015*math.abs(j-3)
                band(g,outer-.04,outer,a,a+.044,h-.034,h)
            end
        end
    end
    f.dust=layer(f.root,'MintSand',{.58,1,.86},function(g) sand(g,0) end)
    f.gold=layer(f.root,'AmberSand',{1,.81,.44},function(g) sand(g,1) end)
    return f
end
function Field.Draw(f,center,stage,t)
    if not f then return end
    f.root.enabled=stage~=nil
    if not stage then return end
    f.root.position=center
    local fade,speedAngle,spread,height,fill=1,0,1,1,.24
    local phase,progress,handAngle=0,0,0
    if stage=='warn' then
        local u=math.min(1,t/Field.warning)
        phase,progress,handAngle=0,u,90*u
        speedAngle=120*t; height=.14+.86*u; spread=.60+.40*u; fill=.07+.08*u
    elseif stage=='active' then
        phase,progress=1,math.min(1,t/Field.duration)
        handAngle=90+252*progress
        speedAngle=120*Field.warning+9*t
    else
        local u=math.min(1,t/Field.release)
        speedAngle=120*Field.warning+9*Field.duration+105*t
        phase,progress,handAngle=2,u,342+16*u
        fade=1-u; height=1-.42*u; spread=1-.10*u; fill=.24*fade
    end
    handAngle=math.floor(handAngle/2)*2
    if f.floor.ink then
        f.floor.node.enabled=true
        f.floor.ink:SetShaderParameter('ink_phase',Variant(phase+0.0))
        f.floor.ink:SetShaderParameter('phase_progress',Variant(progress+0.0))
        f.floor.ink:SetShaderParameter('hand_turn',Variant(handAngle/360))
    else opacity(f.floor,fill*fade) end
    local edge=phase==2 and math.max(.12*(1-progress),1-2.6*progress) or 1
    opacity(f.rim,.82*edge); opacity(f.ticks,.96*edge)
    opacity(f.hand,.78*fade); opacity(f.dust,.94*fade); opacity(f.gold,.9*fade)
    f.rim.node.scale=Vector3(1,height,1)
    f.hand.node.rotation=Quaternion(handAngle,Vector3.UP)
    f.dust.node.rotation=Quaternion(speedAngle,Vector3.UP); f.gold.node.rotation=Quaternion(-speedAngle*.72,Vector3.UP)
    local size=Vector3(spread,height,spread); f.dust.node.scale=size; f.gold.node.scale=size
end
return Field
