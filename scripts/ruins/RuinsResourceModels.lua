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
local function color(rgb, k, a)
    k=k or 1
    return Color(math.min(1,((rgb>>16)&255)*k/255), math.min(1,((rgb>>8)&255)*k/255), math.min(1,(rgb&255)*k/255), a or 1)
end

local SHADERS = {
    stone = { path = 'Shaders/BLGL/RuinsBark.shader', param = 'rock_mode', value = 1.0 },
    matte = { path = 'Shaders/BLGL/RuinsBark.shader', param = 'rock_mode', value = 2.0 },
    gem   = { path = 'Shaders/BLGL/RuinsCrystal.shader', param = 'ore_mode', value = 1.0 },
    glass = { path = 'model/forge-blades/WingSwordCrystal.shader', xml = 'model/forge-blades/WingSwordCrystal.xml', param = 'ore_mode', value = 1.0 },
}

function M.Materials()
    local mats={}
    for _,finish in ipairs({'matte','stone','gem','beam','glass'}) do
        local mat
        local spec=SHADERS[finish]
        local bound=false
        if spec then
            if spec.xml and cache and cache.GetResource then
                local src=cache:GetResource('Material',spec.xml)
                if src and src.Clone then
                    mat=src:Clone('RuinsResource_'..finish)
                    bound=mat~=nil
                end
            end
            if not mat then mat=Material:new() end
            if not bound and mat.SetSurfaceShader then
                bound=mat:SetSurfaceShader(spec.path)==true
            end
            if bound then
                mat:SetShaderParameter(spec.param,Variant(spec.value))
                if finish=='gem' or finish=='glass' then
                    mat:SetShaderParameter('night_k',Variant(0.0))
                end
            end
        else
            mat=Material:new()
        end
        if not bound then
            local path=finish=='beam' and 'Techniques/NoTextureUnlit.xml'
                or finish=='glass' and 'Techniques/PBR/PBRNoTextureAlpha.xml' or 'Techniques/PBR/PBRNoTexture.xml'
            mat:SetTechnique(0,cache:GetResource('Technique',path))
            mat.vertexShaderDefines='VERTEXCOLOR'
            mat.pixelShaderDefines='VERTEXCOLOR'
            mat:SetShaderParameter('MatDiffColor',Variant(Color(1,1,1,finish=='glass' and .52 or 1)))
            if finish~='beam' then
                mat:SetShaderParameter('Roughness',Variant(finish=='glass' and .05 or finish=='gem' and .08 or finish=='stone' and .92 or .88))
                mat:SetShaderParameter('Metallic',Variant(0))
            end
        end
        mats[finish]=mat
    end
    return mats
end

function M.SetNight(mats, nightK)
    if not mats then return end
    local k=math.max(0,math.min(1,nightK or 0))
    local step=math.floor(k*64+.5)/64
    if mats.nightStep==step then return end
    mats.nightStep=step
    for _,name in ipairs({'gem','glass'}) do
        local m=mats[name]
        if m and m.SetShaderParameter then m:SetShaderParameter('night_k',Variant(step)) end
    end
end

local function mesh(node,name,material,shadow)
    local g=node:CreateChild(name):CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST)
    g:SetMaterial(material)
    g.castShadows=shadow
    return g
end

local faceCounter = 0
local function facetAlpha(normal, salt)
    -- Key-light + per-facet hash matching ClockCatalyst's core facet brightness (COLOR.a).
    local dotKey = -0.45 * normal.x + 0.58 * normal.y - 0.68 * normal.z
    local base = math.max(0, math.min(1, (dotKey + 0.34) / 1.34))
    local h = (((salt or faceCounter) * 43) % 19) / 19
    return math.max(0.02, math.min(0.98, (base ^ 1.25) * 0.78 + h * 0.22))
end

local function triangle(g,a,b,c,rgb,k,center,salt)
    faceCounter = faceCounter + 1
    if center then
        local raw = (b-a):CrossProduct(c-a)
        local out = raw.x*(a.x-center.x)+raw.y*(a.y-center.y)+raw.z*(a.z-center.z)
        if out<0 then b,c=c,b end
    end
    local normal=(b-a):CrossProduct(c-a):Normalized()
    local alpha=type(rgb)=='number' and facetAlpha(normal,salt or faceCounter) or nil
    local tint=type(rgb)=='number' and color(rgb,k or 1,alpha) or rgb
    local hasUV = g.DefineTexCoord ~= nil and Vector2 ~= nil
    g:DefineVertex(a); g:DefineNormal(normal); g:DefineColor(tint)
    if hasUV then g:DefineTexCoord(Vector2(0, 0)) end
    g:DefineVertex(b); g:DefineNormal(normal); g:DefineColor(tint)
    if hasUV then g:DefineTexCoord(Vector2(1, 0)) end
    g:DefineVertex(c); g:DefineNormal(normal); g:DefineColor(tint)
    if hasUV then g:DefineTexCoord(Vector2(0.5, 1)) end
end

-- Each row is {height, xRadius, zRadius, xOffset?, zOffset?}. Offsetting
-- successive rings gives each crystal its own growth axis and cleavage planes.
local function solid(g,sides,x,z,angle,rows,body,cap)
    local lower
    local midY = .5 * (rows[1][1] + rows[#rows][1])
    local center = Vector3(x, midY, z)
    for j,row in ipairs(rows) do
        local ring={}
        for i=1,sides do
            local a=angle+2*math.pi*i/sides
            ring[i]=Vector3(x+(row[4] or 0)+row[2]*math.cos(a),row[1],z+(row[5] or 0)+row[3]*math.sin(a))
        end
        if lower then
            for i=1,sides do
                local n=i%sides+1
                local k=.82+.04*((i*3+j)%5)
                triangle(g,lower[i],ring[i],ring[n],body,k,center,i*7+j*13)
                triangle(g,lower[i],ring[n],lower[n],body,k*.96,center,i*11+j*17)
            end
        end
        if j==1 or j==#rows then
            local cTone=cap or body
            for i=2,sides-1 do
                if j==1 then triangle(g,ring[1],ring[i],ring[i+1],cTone,.86,center,i*5+j)
                else triangle(g,ring[1],ring[i+1],ring[i],cTone,.94,center,i*9+j) end
            end
        end
        lower=ring
    end
end

-- Staggered antiprism / diamond-cut crystal spire: alternating rings twist by half
-- a sector and vary vertex radius/height so every band is a lattice of distinct
-- triangular facets (matching the facet distribution of ClockCatalyst's gem).
local function crystal(g,x,y,z,h,r,dx,dz,tone,seed)
    seed = seed or 1
    local sides = 6
    local step = 2 * math.pi / sides
    local bands = {
        { t = 0.00, rad = 0.76, twist = 0.0, ox = 0.00, oz = 0.00 },
        { t = 0.17, rad = 0.98, twist = 0.5, ox = 0.12, oz = 0.12 },
        { t = 0.41, rad = 1.04, twist = 0.0, ox = 0.34, oz = 0.34 },
        { t = 0.64, rad = 0.94, twist = 0.5, ox = 0.62, oz = 0.62 },
        { t = 0.83, rad = 0.62, twist = 0.0, ox = 0.84, oz = 0.84 },
    }
    local center = Vector3(x + dx * .45, y + h * .48, z + dz * .45)
    local rings = {}
    for bIdx, b in ipairs(bands) do
        local ring = {}
        local cx, cz = x + dx * b.ox, z + dz * b.oz
        for i = 1, sides do
            local a = .22 + seed * .37 + (i - 1 + b.twist) * step
            local alt = (i % 2 == 0) and 1.05 or 0.91
            local rad = r * b.rad * alt
            local hy = y + h * b.t + ((bIdx > 1 and bIdx < #bands) and (((i + bIdx) % 2 == 0 and 1 or -1) * h * .018) or 0)
            ring[i] = Vector3(cx + rad * math.cos(a), hy, cz + rad * math.sin(a) * .88)
        end
        rings[bIdx] = ring
    end
    for bIdx = 1, #bands - 1 do
        local lo, hi = rings[bIdx], rings[bIdx + 1]
        for i = 1, sides do
            local n = i % sides + 1
            if bIdx % 2 == 1 then
                triangle(g, lo[i], hi[i], lo[n], tone, 1, center, seed * 19 + bIdx * 7 + i * 3)
                triangle(g, lo[n], hi[i], hi[n], tone, 1, center, seed * 23 + bIdx * 11 + i * 5)
            else
                triangle(g, lo[i], hi[i], hi[n], tone, 1, center, seed * 29 + bIdx * 13 + i * 3)
                triangle(g, lo[i], hi[n], lo[n], tone, 1, center, seed * 31 + bIdx * 17 + i * 5)
            end
        end
    end
    local topRing = rings[#rings]
    local apex = Vector3(x + dx + r * .08, y + h, z + dz)
    local baseCap = Vector3(x, y, z)
    for i = 1, sides do
        local n = i % sides + 1
        triangle(g, topRing[i], apex, topRing[n], tone, 1.04, center, seed * 37 + i * 7)
        triangle(g, baseCap, rings[1][n], rings[1][i], tone, .82, center, seed * 41 + i * 3)
    end
end

-- Subdivided polyhedral gem heart (same 5-fold staggered latitude rings as ClockCatalyst.core).
local function polyGem(g,x,y,z,rx,ry,rz,yaw,tone,seed)
    seed = seed or 7
    local sides = 6
    local step = 2 * math.pi / sides
    local center = Vector3(x, y, z)
    local levels = {
        { y = -0.72, r = 0.56, twist = 0.0 },
        { y = -0.28, r = 0.94, twist = 0.5 },
        { y =  0.22, r = 1.00, twist = 0.0 },
        { y =  0.66, r = 0.64, twist = 0.5 },
    }
    local rings = {}
    for lIdx, lv in ipairs(levels) do
        local ring = {}
        for i = 1, sides do
            local a = (yaw or 0) + (i - 1 + lv.twist) * step
            local k = ((i + lIdx) % 2 == 0) and 1.04 or 0.92
            ring[i] = Vector3(x + rx * lv.r * k * math.cos(a), y + ry * lv.y, z + rz * lv.r * k * math.sin(a))
        end
        rings[lIdx] = ring
    end
    local bot = Vector3(x, y - ry * .96, z)
    local top = Vector3(x, y + ry * .98, z)
    for i = 1, sides do
        local n = i % sides + 1
        triangle(g, bot, rings[1][n], rings[1][i], tone, .88, center, seed * 11 + i)
        triangle(g, rings[#rings][i], top, rings[#rings][n], tone, 1.04, center, seed * 13 + i)
    end
    for lIdx = 1, #levels - 1 do
        local lo, hi = rings[lIdx], rings[lIdx + 1]
        for i = 1, sides do
            local n = i % sides + 1
            triangle(g, lo[i], hi[i], lo[n], tone, 1, center, seed * 17 + lIdx * 7 + i * 3)
            triangle(g, lo[n], hi[i], hi[n], tone, 1, center, seed * 19 + lIdx * 11 + i * 5)
        end
    end
end

-- Irregular fractured rock crag (replaces smooth hexagonal pucks).
local function crag(g,x,y,z,w,h,d,angle,tone,cap,seed)
    seed = seed or 3
    local sides = 7
    local step = 2 * math.pi / sides
    local center = Vector3(x, y + h * .42, z)
    local bands = {
        { t = 0.00, r = 0.92, twist = 0.0 },
        { t = 0.36, r = 1.04, twist = 0.35 },
        { t = 0.74, r = 0.84, twist = 0.12 },
        { t = 1.00, r = 0.46, twist = 0.48 },
    }
    local rings = {}
    for bIdx, b in ipairs(bands) do
        local ring = {}
        for i = 1, sides do
            local a = angle + (i - 1 + b.twist) * step
            local jag = 0.84 + 0.28 * (((i * 5 + bIdx * 3 + seed) % 7) / 6)
            local lift = (bIdx > 1) and ((((i * 3 + bIdx + seed) % 5) - 2) * h * .045) or 0
            ring[i] = Vector3(x + w * b.r * jag * math.cos(a), y + h * b.t + lift, z + d * b.r * jag * math.sin(a))
        end
        rings[bIdx] = ring
    end
    for bIdx = 1, #bands - 1 do
        local lo, hi = rings[bIdx], rings[bIdx + 1]
        for i = 1, sides do
            local n = i % sides + 1
            triangle(g, lo[i], hi[i], hi[n], tone, 1, center, seed * 13 + bIdx * 7 + i)
            triangle(g, lo[i], hi[n], lo[n], tone, .95, center, seed * 17 + bIdx * 11 + i)
        end
    end
    local topPeak = Vector3(x - w * .06, y + h * 1.04, z + d * .05)
    local botPeak = Vector3(x, y, z)
    local topRing = rings[#rings]
    for i = 1, sides do
        local n = i % sides + 1
        triangle(g, topRing[i], topPeak, topRing[n], cap or tone, 1.02, center, seed * 23 + i)
        triangle(g, botPeak, rings[1][n], rings[1][i], tone, .80, center, seed * 29 + i)
    end
end

local function boulder(g,x,y,z,w,h,d,angle,tone)
    crag(g,x,y,z,w,h,d,angle,tone,tone,math.floor((x*13+z*17+angle*7)*10))
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
    local function face(a,b,c,rgb,k,center)
        triangle(g,a,b,c,rgb,k,center)
    end
    for i=1,6 do
        local n=i%6+1
        local k=.82+.05*((i*3)%5)
        local mid=Vector3(x,y+r,z)
        face(rings[1][i],rings[2][i],rings[2][n],tone,k,mid)
        face(rings[1][i],rings[2][n],rings[1][n],tone,k,mid)
    end
    for k=1,2 do
        local c=Vector3(x+dx*(k-1.5)*len,y+r,z+dz*(k-1.5)*len)
        for i=1,6 do
            local n=i%6+1
            face(c,rings[k][i],rings[k][n],cap or tone,1,Vector3(x,y+r,z))
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
        -- Craggy fractured slate-basalt host rock (no flat hexagonal plugs).
        crag(base,-.04,-.08,-.05,.92,.52,.68,.21,C.slateDark,C.slate,1)
        crag(base,.54,-.02,.12,.44,.38,.36,.63,C.slate,C.stone,2)
        crag(base,-.52,-.02,-.15,.40,.34,.35,.87,C.slate,C.stone,3)
        crag(base,.08,.04,.34,.36,.28,.30,1.24,C.slateDark,C.slate,4)
        -- Jagged dark-mineral collar shards where the crystals break through the rock.
        for idx,s in ipairs({{-.18,.28,.16,.16,.24},{.24,.26,.14,.15,.18},{.02,.30,-.22,.18,.26}}) do
            crag(base,s[1],s[2],s[3],s[4],s[5],s[4]*.88,idx*.7,C.slateDark,C.slate,idx+10)
        end
    end
    if not stock then return end
    -- Central polyhedral gem heart (matching ClockCatalyst's orb facet layout) +
    -- staggered diamond-cut crystal spires with inner cores.
    polyGem(stock,-.02,.52,.10,.26,.30,.24,.35,C.blue,5)
    crystal(stock,0,.38,-.08,1.34,.27,.10,.04,C.blue,1)
    crystal(stock,-.38,.32,.12,.92,.20,-.26,.10,C.ice,2)
    crystal(stock,.36,.30,-.14,.98,.21,.26,-.08,C.blue,3)
    crystal(stock,.18,.29,.25,.62,.15,.14,.20,C.ice,4)
    polyGem(core,-.02,.50,.10,.15,.19,.14,.35,C.jade,6)
    crystal(core,0,.42,-.08,1.04,.13,.08,.03,C.jade,1)
    crystal(core,-.38,.35,.12,.68,.09,-.20,.07,C.blue,2)
    crystal(core,.36,.33,-.14,.74,.095,.20,-.06,C.jade,3)
    crystal(core,.16,.33,.24,.46,.07,.10,.16,C.light,4)
end

-- Dedicated quarry stone node: dark slate/basalt bedrock cradle with iron wedges
-- and faceted, angled rust-sandstone slabs crossed by pale mineral seams.
local function slab(g,x,y,z,w,h,d,dx,dz,angle,tone,cap)
    solid(g,6,x,z,angle,{{y,w,d},{y+h*.45,w*.94,d*.92,dx*.45,dz*.45},
        {y+h,w*.56,d*.52,dx,dz}},tone,cap)
end
local function quarry(base,stock)
    if base then
        crag(base,0,-.07,-.05,.94,.42,.70,.32,C.slateDark,C.slate,5)
        crag(base,-.52,0,.16,.36,.26,.30,.62,C.slate,C.slate,6)
        crag(base,.50,.01,.18,.32,.24,.28,.18,C.rustDark,C.rust,7)
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
        core=mesh(canopy,'Core',mats.gem,true)
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
        id=='crystal_ore' and C.ice or C.honey)
    marker:Commit()
    return canopy
end

function M.Site(root,id,mats,spent)
    if id~='timber' then
        local base=mesh(root,'Remainder',mats.stone,true)
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
