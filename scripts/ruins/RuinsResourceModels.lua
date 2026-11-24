-- Hand-cut silhouettes. One static mesh per surface finish and harvest state.
-- All dimensions are metres. Colours are also the palette for inventory icons.
local M = {}
local C = {
    bark=0x694531, cut=0xE4AF73, grain=0xA66A40, moss=0x46745B,
    leaf=0x508864, mint=0x8EBB80, ribbon=0xF2803C,
    amber=0xEFA343, honey=0xFFD782, copper=0xAB6944,
    slate=0x435569, stone=0x798C96, chalk=0xBDCCD0,
    blue=0x409FC6, ice=0xA6EDFF, jade=0x35BDAC, light=0xA0F7DD,
    violet=0x8366B9, lilac=0xDFC7FF, indigo=0x413958,
    -- Rust sandstone: deliberately warm and saturated so it cannot pass for the
    -- grey-beige masonry and blue-grey cliffs of the ruins.
    rust=0xA6512A, rustDark=0x4E261A, rustLight=0xCE7239, rustCut=0xF2BA72,
    iron=0x8CA0AD, slateDark=0x2F3B48,
}
local function color(rgb, k)
    k=k or 1
    return Color(((rgb>>16)&255)*k/255, ((rgb>>8)&255)*k/255, (rgb&255)*k/255, 1)
end

function M.Materials()
    local mats={}
    for _,finish in ipairs({'matte','stone','gem','beam','glass'}) do
        local mat=Material:new()
        local path=finish=='beam' and 'Techniques/NoTextureUnlit.xml'
            or finish=='glass' and 'Techniques/PBR/PBRNoTextureAlpha.xml' or 'Techniques/PBR/PBRNoTexture.xml'
        mat:SetTechnique(0,cache:GetResource('Technique',path))
        mat.vertexShaderDefines='VERTEXCOLOR'
        mat.pixelShaderDefines='VERTEXCOLOR'
        mat:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,finish=='glass' and .34 or 1)))
        if finish=='glass' then
            -- Translucent shell: both faces drawn so the inner facets and the
            -- bright core read through it, with a faint self-glow like cut gem.
            mat:SetCullMode(CULL_NONE)
            mat:SetShaderParameter('MatEmissiveColor',Variant(Color(.10,.20,.23)))
        end
        if finish~='beam' then
            mat:SetShaderParameter('Roughness',Variant(finish=='glass' and .10 or finish=='gem' and .17 or finish=='stone' and .96 or .88))
            mat:SetShaderParameter('Metallic',Variant(finish=='glass' and 0 or finish=='gem' and .21 or 0))
        end
        mats[finish]=mat
    end
    return mats
end

local function mesh(node,name,material,shadow)
    local g=node:CreateChild(name):CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST)
    g:SetMaterial(material)
    g.castShadows=shadow
    return g
end

local function triangle(g,a,b,c,tint)
    local normal=(b-a):CrossProduct(c-a):Normalized()
    g:DefineVertex(a); g:DefineNormal(normal); g:DefineColor(tint)
    g:DefineVertex(b); g:DefineNormal(normal); g:DefineColor(tint)
    g:DefineVertex(c); g:DefineNormal(normal); g:DefineColor(tint)
end

-- Each row is {height, xRadius, zRadius, xOffset?, zOffset?}. Offsetting
-- successive rings gives each crystal its own growth axis and cleavage planes.
local function solid(g,sides,x,z,angle,rows,body,cap)
    local lower
    for j,row in ipairs(rows) do
        local ring={}
        for i=1,sides do
            local a=angle+2*math.pi*i/sides
            ring[i]=Vector3(x+(row[4] or 0)+row[2]*math.cos(a),row[1],z+(row[5] or 0)+row[3]*math.sin(a))
        end
        if lower then
            for i=1,sides do
                local n=i%sides+1
                local tint=color(body,.80+.05*((i*3)%5))
                triangle(g,lower[i],ring[i],ring[n],tint)
                triangle(g,lower[i],ring[n],lower[n],tint)
            end
        end
        if j==1 or j==#rows then
            local tint=color(cap or body)
            for i=2,sides-1 do
                if j==1 then triangle(g,ring[1],ring[i],ring[i+1],tint)
                else triangle(g,ring[1],ring[i+1],ring[i],tint) end
            end
        end
        lower=ring
    end
end

local function crystal(g,x,y,z,h,r,dx,dz,tone)
    solid(g,6,x,z,.24,{{y,r*.78,r*.7},{y+h*.19,r,r*.84,dx*.14,dz*.14},
        {y+h*.72,r*.91,r*.79,dx*.70,dz*.70},{y+h,r*.08,r*.06,dx+r*.15,dz}},tone)
end
local function boulder(g,x,y,z,w,h,d,angle,tone)
    solid(g,6,x,z,angle,{{y,w*.82,d*.78},{y+h*.50,w,d,.03,0},
        {y+h,w*.65,d*.63,-w*.09,d*.11}},tone)
end

-- A straight six-sided log lying on the ground. Faces are flipped to face away
-- from the log's axis, so winding never has to be reasoned about per call.
local function log(g,x,y,z,len,r,yaw,tone,cap)
    local dx,dz=math.cos(yaw),math.sin(yaw)
    local sx,sz=-dz,dx
    local rings={}
    for k=1,2 do
        local t=(k-1.5)*len
        local ring={}
        for i=1,6 do
            local a=2*math.pi*i/6+.3
            local u,v=r*math.cos(a),r*math.sin(a)
            ring[i]=Vector3(x+dx*t+sx*u,y+r+v,z+dz*t+sz*u)
        end
        rings[k]=ring
    end
    local function face(a,b,c,tint,center)
        local n=(b-a):CrossProduct(c-a)
        local out=n.x*(a.x-center.x)+n.y*(a.y-center.y)+n.z*(a.z-center.z)
        if out<0 then b,c=c,b end
        triangle(g,a,b,c,tint)
    end
    for i=1,6 do
        local n=i%6+1
        local tint=color(tone,.82+.05*((i*3)%5))
        local mid=Vector3(x,y+r,z)
        face(rings[1][i],rings[2][i],rings[2][n],tint,mid)
        face(rings[1][i],rings[2][n],rings[1][n],tint,mid)
    end
    for k=1,2 do
        local c=Vector3(x+dx*(k-1.5)*len,y+r,z+dz*(k-1.5)*len)
        for i=1,6 do
            local n=i%6+1
            face(c,rings[k][i],rings[k][n],color(cap or tone),Vector3(x,y+r,z))
        end
    end
end

-- Each tree in the ruins gets a neat firewood bundle beside its trunk (no tall
-- sky beam, so 28 trees stay natural). Claiming leaves scattered woodchips.
local function tree(base,stock)
    local g=stock
    if not g then return end
    log(g,-.06,-.02,0,.52,.115,.22,C.bark,C.cut)
    log(g,.06,-.02,.25,.48,.105,.52,C.grain,C.cut)
    log(g,0,.18,.12,.45,.10,.36,C.bark,C.cut)
    -- Small twine band around the top log so it reads as bundled timber.
    log(g,0,.18,.12,.10,.108,.36,C.ribbon,C.ribbon)
end

local function mine(base,stock,core)
    if base then
        boulder(base,-.05,-.08,-.05,.88,.48,.64,.21,C.slate)
        boulder(base,.55,.02,.12,.40,.35,.34,.63,C.stone)
        boulder(base,-.54,0,-.15,.36,.30,.33,.87,C.stone)
        -- Dull broken sockets stay attached to the exposed host rock.
        for _,s in ipairs({{0,.34,0,.23},{-.40,.28,.14,.16},{.37,.27,-.17,.15}}) do
            solid(base,6,s[1],s[3],.24,{{s[2],s[4],s[4]*.8},{s[2]+.15,s[4]*.82,s[4]*.69}},C.moss,C.chalk)
        end
    end
    if not stock then return end
    -- Translucent shells, then a smaller opaque core of the same growth axes so
    -- depth shows through the glass instead of a flat see-through blob.
    crystal(stock,0,.40,-.08,1.32,.28,.10,.04,C.ice)
    crystal(stock,-.40,.34,.12,.90,.20,-.28,.10,C.light)
    crystal(stock,.36,.32,-.14,.98,.21,.28,-.08,C.ice)
    crystal(stock,.16,.31,.24,.58,.145,.12,.22,C.light)
    crystal(core,0,.44,-.08,1.02,.12,.08,.03,C.jade)
    crystal(core,-.40,.37,.12,.64,.085,-.20,.07,C.jade)
    crystal(core,.36,.35,-.14,.74,.09,.20,-.06,C.blue)
    crystal(core,.12,.39,.24,.48,.065,.10,.18,C.light)
end

-- Dedicated quarry stone node: dark slate/basalt bedrock cradle with iron wedges
-- and faceted, angled rust-sandstone slabs crossed by pale mineral seams.
local function slab(g,x,y,z,w,h,d,dx,dz,angle,tone,cap)
    solid(g,6,x,z,angle,{{y,w,d},{y+h*.45,w*.94,d*.92,dx*.45,dz*.45},
        {y+h,w*.56,d*.52,dx,dz}},tone,cap)
end
local function quarry(base,stock)
    if base then
        solid(base,6,0,-.06,.32,{{-.06,.92,.72},{.22,.84,.64},{.36,.58,.44}},C.slateDark,C.slate)
        boulder(base,-.52,0,.16,.34,.22,.28,.62,C.slate)
        boulder(base,.50,.01,.18,.30,.20,.26,.18,C.rustDark)
        -- Left-behind iron quarry wedges / chisel socket on the bed.
        solid(base,4,-.12,.14,.4,{{.28,.07,.07},{.48,.04,.04,.02,0}},C.iron)
        solid(base,4,.22,-.04,.2,{{.26,.06,.06},{.44,.035,.035,-.02,0}},C.iron)
    end
    if not stock then return end
    -- Main tilted layered sandstone-quartz pillar + flanking quarry shelf.
    slab(stock,-.12,.24,-.04,.58,.56,.46,-.06,.04,.24,C.rust,C.rustCut)
    solid(stock,6,-.15,.00,.24,{{.52,.56,.45},{.62,.53,.42}},C.rustCut)
    slab(stock,.06,.66,-.10,.50,.48,.40,.08,-.04,.46,C.rustLight,C.rustCut)
    slab(stock,.44,.18,.20,.32,.46,.28,.08,.06,.14,C.rust,C.rustLight)
    solid(stock,6,.46,.22,.14,{{.38,.31,.27},{.45,.29,.25}},C.rustCut)
end

local sites={timber=tree,crystal_ore=mine,stone=quarry}
local markerY={timber=1.02,crystal_ore=1.96,stone=1.42}
local function buildStock(root,id,mats)
    local canopy=root:CreateChild('Harvestable')
    local stock,core
    if id=='crystal_ore' then
        stock=mesh(canopy,'Yield',mats.glass,false)
        core=mesh(canopy,'Core',mats.gem,false)
    else
        stock=mesh(canopy,'Yield',id=='stone' and mats.stone or mats.matte,true)
    end
    sites[id](nil,stock,core)
    stock:Commit()
    if core then core:Commit() end
    local marker=mesh(canopy,'GatherMark',mats.beam,false)
    local y=markerY[id]
    local r=id=='timber' and .065 or .085
    solid(marker,4,0,0,0,{{y,.012,.012},{y+.12*r/.085,r,r},{y+.24*r/.085,.012,.012}},
        id=='crystal_ore' and C.light or C.honey)
    marker:Commit()
    return canopy
end

function M.Site(root,id,mats,spent)
    if id~='timber' then
        local base=mesh(root,'Remainder',id=='stone' and mats.stone or mats.matte,true)
        sites[id](base,nil,nil)
        base:Commit()
    end
    if not spent then return buildStock(root,id,mats) end
end

function M.Restock(root,id,mats)
    return buildStock(root,id,mats)
end

-- Visible proof that the tree has been worked: scattered woodchips.
function M.Harvested(root,id,mats)
    if id~='timber' then return end
    local holder=root:CreateChild('CutChips')
    local g=holder:CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST); g:SetMaterial(mats.matte); g.castShadows=true
    solid(g,4,-.12,.06,.3,{{-.01,.09,.06},{.05,.07,.04}},C.cut,C.cut)
    solid(g,4,.10,.16,1.1,{{-.01,.08,.05},{.04,.06,.04}},C.bark,C.cut)
    solid(g,4,.02,-.08,2.1,{{-.01,.07,.05},{.04,.05,.03}},C.grain,C.cut)
    g:Commit()
    return holder
end

local drops={}
function drops.wood_resin(g)
    boulder(g,-.07,.035,0,.22,.26,.15,.5,C.bark)
    solid(g,7,.06,-.05,0,{{.055,.13,.12},{.19,.17,.15},{.31,.11,.09,.02,0},
        {.44,.025,.02,.08,0}},C.amber,C.honey)
end
function drops.amber_silk(g)
    for i=0,2 do
        local y=.05+i*.095
        solid(g,8,0,0,i*.28,{{y,.16,.12},{y+.045,.24-i*.012,.18},{y+.115,.16,.11}},
            i==1 and C.honey or C.amber)
    end
    crystal(g,.15,.06,.04,.18,.05,.10,.03,C.honey)
end
function drops.armor_crystal(g)
    boulder(g,0,.02,0,.26,.17,.20,.34,C.slate)
    crystal(g,-.04,.13,0,.37,.13,-.12,-.02,C.blue)
    crystal(g,.09,.12,.05,.25,.09,.09,.05,C.ice)
end
function drops.ruin_conduit(g)
    solid(g,6,0,0,.25,{{.045,.17,.15},{.16,.17,.15},{.18,.12,.11}},C.copper)
    solid(g,6,0,0,.25,{{.14,.12,.11},{.32,.12,.11,.025,0}},C.jade)
    solid(g,6,.025,0,.25,{{.31,.17,.15},{.41,.17,.15}},C.copper)
    solid(g,6,.025,0,.25,{{.410,.11,.09},{.423,.10,.09}},C.light)
end
function drops.time_dust(g)
    solid(g,6,0,0,0,{{.035,.18,.15},{.10,.18,.15}},C.indigo)
    solid(g,6,0,0,0,{{.10,.14,.12},{.23,.052,.045},{.37,.14,.12}},C.violet,C.lilac)
    solid(g,6,0,0,0,{{.37,.18,.15},{.42,.18,.15}},C.indigo)
    for _,side in ipairs({-1,1}) do
        solid(g,4,side*.14,0,0,{{.09,.021,.02},{.37,.021,.02}},C.lilac)
    end
end
local beamTint={wood_resin=C.honey,amber_silk=C.amber,armor_crystal=C.ice,ruin_conduit=C.light,time_dust=C.lilac}
function M.Drop(root,id,mats)
    local body=mesh(root,'Material',mats.gem,true)
    drops[id](body)
    body:Commit()
    local beam=mesh(root,'Locator',mats.beam,false)
    local tint=beamTint[id]
    solid(beam,5,0,0,0,{{.39,.024,.024},{.78,.024,.024},{1.38,.009,.009}},tint)
    solid(beam,4,0,0,0,{{1.40,.008,.008},{1.46,.052,.052},{1.54,.008,.008}},tint)
    beam:Commit()
end
return M
