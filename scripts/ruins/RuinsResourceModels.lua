-- Hand-cut silhouettes. One static mesh per surface finish and harvest state.
-- All dimensions are metres. Colours are also the palette for inventory icons.
local M = {}
local C = {
    bark=0x694531, cut=0xE4AF73, grain=0xA66A40, moss=0x46745B,
    leaf=0x508864, mint=0x8EBB80, ribbon=0xE7994D,
    amber=0xEFA343, honey=0xFFD782, copper=0xAB6944,
    slate=0x435569, stone=0x798C96, chalk=0xBDCCD0,
    blue=0x409FC6, ice=0xA6EDFF, jade=0x35BDAC, light=0xA0F7DD,
    violet=0x8366B9, lilac=0xDFC7FF, indigo=0x413958,
}
local function color(rgb, k)
    k=k or 1
    return Color(((rgb>>16)&255)*k/255, ((rgb>>8)&255)*k/255, (rgb&255)*k/255, 1)
end

function M.Materials()
    local mats={}
    for _,finish in ipairs({'matte','gem','beam'}) do
        local mat=Material:new()
        local path=finish=='beam' and 'Techniques/NoTextureUnlit.xml' or 'Techniques/PBR/PBRNoTexture.xml'
        mat:SetTechnique(0,cache:GetResource('Technique',path))
        mat.vertexShaderDefines='VERTEXCOLOR'
        mat.pixelShaderDefines='VERTEXCOLOR'
        mat:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,1)))
        if finish~='beam' then
            mat:SetShaderParameter('Roughness',Variant(finish=='gem' and .17 or .88))
            mat:SetShaderParameter('Metallic',Variant(finish=='gem' and .21 or 0))
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

local function tree(base,stock)
    solid(base,7,0,0,.24,{{-.08,.58,.49},{.16,.43,.38},{.60,.29,.26}},C.bark,C.cut)
    solid(base,7,0,0,.24,{{.60,.22,.18},{.612,.21,.17}},C.grain,C.grain)
    solid(base,7,.012,0,.24,{{.612,.146,.116},{.622,.144,.115}},C.cut)
    if not stock then return end
    solid(stock,7,0,0,.24,{{.58,.295,.269},{1.18,.27,.24,.04,0},{2.46,.13,.12,-.18,0}},C.bark)
    -- Surveyor's double ochre band makes working timber distinct from the old trees.
    for _,y in ipairs({.85,1.04}) do
        solid(stock,7,.024,0,.24,{{y,.312,.28},{y+.09,.31,.277}},C.ribbon)
    end
    solid(stock,6,0,0,0,{{1.38,.19,.17},{1.76,.14,.12,.43,0},{2.08,.08,.07,.72,.03}},C.grain)
    solid(stock,6,0,0,0,{{1.64,.18,.16},{2.02,.13,.11,-.51,.14},{2.23,.07,.06,-.77,.23}},C.bark)
    boulder(stock,.66,1.92,0,.70,.62,.62,.43,C.leaf)
    boulder(stock,-.68,2.08,.16,.68,.67,.60,.87,C.moss)
    boulder(stock,-.23,2.32,0,.87,.70,.74,.34,C.leaf)
    boulder(stock,-.33,2.68,-.05,.59,.46,.53,.23,C.mint)
end

local function mine(base,stock)
    boulder(base,-.05,-.08,0,.90,.49,.66,.21,C.slate)
    boulder(base,.57,.02,.13,.42,.37,.35,.63,C.stone)
    boulder(base,-.57,0,-.18,.38,.32,.35,.87,C.stone)
    -- Dull broken sockets stay attached to the exposed host rock.
    for _,s in ipairs({{0,.34,0,.23},{-.40,.28,.14,.16},{.37,.27,-.17,.15}}) do
        solid(base,6,s[1],s[3],.24,{{s[2],s[4],s[4]*.8},{s[2]+.15,s[4]*.82,s[4]*.69}},C.moss,C.chalk)
    end
    if not stock then return end
    crystal(stock,0,.42,0,1.27,.275,.12,-.04,C.jade)
    crystal(stock,-.4,.35,.14,.87,.20,-.31,.07,C.light)
    crystal(stock,.37,.33,-.17,.97,.215,.29,-.12,C.jade)
    crystal(stock,.19,.32,.25,.54,.14,.13,.20,C.light)
end

local function quarry(base,stock)
    boulder(base,0,-.07,0,.89,.39,.65,.37,C.slate)
    boulder(base,-.50,.01,.17,.31,.24,.25,.62,C.stone)
    if not stock then return end
    -- Offset cleavage shelves and pale quartz seam across the upper slab.
    boulder(stock,-.19,.23,.03,.66,.51,.50,.26,C.stone)
    solid(stock,5,.16,-.07,.44,{{.55,.69,.46},{.67,.65,.45}},C.chalk)
    boulder(stock,.13,.64,-.09,.67,.38,.46,.44,C.stone)
    boulder(stock,.49,.20,.22,.33,.38,.28,.20,C.stone)
end

local sites={timber=tree,crystal_ore=mine,stone=quarry}
function M.Site(root,id,mats,spent)
    local base=mesh(root,'Remainder',mats.matte,true)
    local stock,canopy
    if not spent then
        canopy=root:CreateChild('Harvestable')
        stock=mesh(canopy,'Yield',id=='crystal_ore' and mats.gem or mats.matte,true)
    end
    sites[id](base,stock)
    base:Commit()
    if stock then stock:Commit() end
    return canopy
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
