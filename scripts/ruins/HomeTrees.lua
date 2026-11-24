-- 家园与遗迹共用的实体体素树：方粒叶簇、封闭枝干、根部外扩。
-- 先在统一格点上合并体积，再将外层色块合并为两个模型；没有叶片卡或透明贴图。
local Noise = require("ruins.Noise")
local SurfaceMesh = require("ruins.TreeSurfaceMesh")
local M = {}
-- 每种叶粒尺寸一份材质：着色器按 leaf_cell 画方粒棱边。
---@type table<number, Material>
local leafMaterials_ = {}

---@param cell number
---@return Material
local function leafMaterial(cell)
    local m=leafMaterials_[cell]
    if not m then
        m=cache:GetResource("Material","Materials/HomeTreeLeaves.xml"):Clone()
        m:SetShaderParameter("leaf_cell",Variant(cell))
        leafMaterials_[cell]=m
    end
    return m
end

-- 由入口 PostUpdate 在相机位置确定后调用，不额外订阅全局事件。
---@param eye Vector3
---@param target Vector3
---@param active boolean
function M.UpdateView(eye,target,active)
    for _,m in pairs(leafMaterials_) do
        m:SetShaderParameter("foliage_eye",Variant(Vector4(eye.x,eye.y,eye.z,active and 1 or 0)))
        m:SetShaderParameter("foliage_target",Variant(Vector4(target.x,target.y,target.z,0)))
    end
end

function M.Stop()
    for _,m in pairs(leafMaterials_) do
        m:SetShaderParameter("foliage_eye",Variant(Vector4(0,0,0,0)))
    end
    leafMaterials_={}
end
local floor, ceil, min, max, abs = math.floor, math.ceil, math.min, math.max, math.abs
local sin, cos, pi = math.sin, math.cos, math.pi

---@class HomeTreeCell
---@field x integer
---@field y integer
---@field z integer
---@field tone integer
---@field ao integer

---@class HomeTreeGrid
---@field size number
---@field cells table<string, HomeTreeCell?>
---@field order HomeTreeCell[]
local Grid = {}
Grid.__index = Grid

---@param x integer
---@param y integer
---@param z integer
local function key(x, y, z) return x .. ":" .. y .. ":" .. z end

---@param size number
function Grid:Init(size)
    self.size = size
    self.cells = {}
    self.order = {}
end

---@param size number
---@return HomeTreeGrid
local function grid(size)
    local result = setmetatable({}, Grid)
    result:Init(size)
    return result
end

---@param x integer
---@param y integer
---@param z integer
---@param tone integer
function Grid:Set(x, y, z, tone)
    local k = key(x, y, z)
    local c = self.cells[k]
    if c then return end
    c = { x = x, y = y, z = z, tone = tone, ao = 255 }
    self.cells[k] = c
    self.order[#self.order + 1] = c
end

---@type Color[]
local BARK = {
    Color(.25, .18, .13), Color(.32, .23, .16), Color(.39, .28, .19),
    Color(.46, .33, .22), Color(.53, .40, .27), Color(.59, .46, .31),
    Color(.28, .34, .17), Color(.36, .40, .21),
}
---@type Color[][]
local LEAVES = {
    { Color(.19,.31,.17), Color(.25,.39,.19), Color(.32,.46,.22), Color(.39,.53,.25),
      Color(.47,.60,.29), Color(.56,.66,.34), Color(.64,.71,.40), Color(.70,.75,.47) },
    { Color(.17,.30,.21), Color(.22,.37,.24), Color(.28,.45,.27), Color(.35,.51,.30),
      Color(.42,.58,.33), Color(.50,.64,.37), Color(.58,.69,.42), Color(.65,.73,.49) },
    { Color(.33,.25,.12), Color(.44,.32,.13), Color(.56,.40,.14), Color(.66,.49,.18),
      Color(.76,.59,.23), Color(.85,.68,.30), Color(.91,.77,.39), Color(.95,.84,.51) },
}

-- 只保留外露表面，沿面合并连续同色格；外壳仍完整封闭，不改变实体轮廓。
---@param parent Node
---@param name string
---@param palette Color[]
---@param material Material
---@return integer
function Grid:Build(parent, name, palette, material)
    local cells = self.cells
    for _, c in ipairs(self.order) do
        local x, y, z = c.x, c.y, c.z
        if not cells[key(x-1,y,z)] or not cells[key(x+1,y,z)]
            or not cells[key(x,y-1,z)] or not cells[key(x,y+1,z)]
            or not cells[key(x,y,z-1)] or not cells[key(x,y,z+1)] then
            if name=="Leaves" then
                -- 叶簇上方和斜上方的占据格决定遮蔽，量化三级以保留合批能力。
                local covered=0
                for _,d in ipairs({2,4,6}) do
                    if cells[key(x,y+d,z)] then covered=covered+2 end
                    if cells[key(x+2,y+d,z)] then covered=covered+1 end
                    if cells[key(x-2,y+d,z)] then covered=covered+1 end
                    if cells[key(x,y+d,z+2)] then covered=covered+1 end
                    if cells[key(x,y+d,z-2)] then covered=covered+1 end
                end
                c.ao=255-floor(covered/7)*28
            end
        end
    end
    -- 仅输出真正朝外的面，颜色/AO/格点保持不变；不再为每簇复制完整六面盒。
    local quads = SurfaceMesh.Build(self, parent, name, palette, material)
    return quads
end

-- 树皮明暗沿竖向成小段延续，几何脊线与颜色共同构成树皮质感。
---@param x integer
---@param y integer
---@param z integer
---@param seed integer
---@return integer
local function barkTone(x,y,z,seed)
    if y < 8 and Noise.Hash3(floor(x/2),floor(y/4),floor(z/2)+seed) > .72 then
        return 7 + (Noise.Hash3(x,0,z+seed) > .5 and 1 or 0)
    end
    local strip = Noise.Hash3(x,floor(y/6),z+seed)
    return max(1,min(6,2+floor(strip*4.3)))
end

---@param target HomeTreeGrid
---@param points Vector3[]
---@param startRadius number
---@param endRadius number
---@param seed integer
local function woodPath(target, points, startRadius, endRadius, seed)
    local s = target.size
    for k = 1,#points-1 do
        local a = points[k] --[[@as Vector3]]
        local b = points[k+1] --[[@as Vector3]]
        local d = b-a
        local len2 = d:LengthSquared()
        local r0 = startRadius+(endRadius-startRadius)*(k-1)/(#points-1)
        local r1 = startRadius+(endRadius-startRadius)*k/(#points-1)
        local bound = max(r0,r1)+s
        for x = floor((min(a.x,b.x)-bound)/s),ceil((max(a.x,b.x)+bound)/s) do
            for z = floor((min(a.z,b.z)-bound)/s),ceil((max(a.z,b.z)+bound)/s) do
                for y = floor((min(a.y,b.y)-bound)/s),ceil((max(a.y,b.y)+bound)/s) do
                    local px,py,pz = (x+.5)*s-a.x,(y+.5)*s-a.y,(z+.5)*s-a.z
                    local t = max(0,min(1,(px*d.x+py*d.y+pz*d.z)/max(.00001,len2)))
                    local dx,dy,dz = abs(px-d.x*t),abs(py-d.y*t),abs(pz-d.z*t)
                    local ridge = (Noise.Value2(x*.42+seed,z*.42+floor(y/5)*.13,17)-.5)*s*1.2
                    local r = max(s*.72,r0+(r1-r0)*t+ridge)
                    if max(dx,dy,dz) <= r and dx+dz <= r*1.75 then
                        target:Set(x,y,z,barkTone(x,y,z,seed))
                    end
                end
            end
        end
    end
end

-- 一簇由数层方粒组成：宽台阶、错位的上层、小缺口与下垂末梢。
-- 噪声只侵蚀边缘，叶簇内部连续；色块以数格成片，避免逐粒杂色变成泡沫噪点。
---@param target HomeTreeGrid
---@param center Vector3
---@param radius number
---@param seed integer
---@param bias number
local function crownClump(target,center,radius,seed,bias)
    local s = target.size
    local rx,rz = radius,radius*(.78+Noise.Hash3(seed,3,1)*.24)
    local ry = max(s*1.6,radius*.50)
    for y=floor((center.y-ry)/s),floor((center.y+ry)/s) do
        local height=((y+.5)*s-center.y)/ry
        local terrace = 1.0
        if height > .58 then terrace=.56 elseif height > .10 then terrace=.84
        elseif height < -.62 then terrace=.54 elseif height < -.23 then terrace=.85 end
        local shiftX=floor(height*1.5)*s*.55
        local shiftZ=sin(seed+floor(height*3))*s*.6
        for x=floor((center.x-rx)/s)-1,ceil((center.x+rx)/s)+1 do
            for z=floor((center.z-rz)/s)-1,ceil((center.z+rz)/s)+1 do
                local dx=abs(((x+.5)*s-center.x-shiftX)/rx)
                local dz=abs(((z+.5)*s-center.z-shiftZ)/rz)
                local edge=max(dx,dz)+min(dx,dz)*.24
                local irregular=(Noise.Value2(x*.57+seed,z*.57,seed)-.5)*.25
                local notch=Noise.Hash3(floor(x/2),floor(y/2),floor(z/2)+seed)
                local limit=terrace+irregular-(notch>.79 and .16 or 0)
                if edge<limit then
                    local patch=Noise.Value3(x*.26,y*.32,z*.26,seed)
                    local shade=.45+height*.17+(patch-.5)*.65+bias
                    local speck=Noise.Hash3(x,y,z+seed)
                    if speck>.90 then shade=shade+.10 elseif speck<.06 then shade=shade-.09 end
                    local tone=max(1,min(8,1+floor(shade*8)))
                    target:Set(x,y,z,tone)
                end
            end
        end
    end
end

-- 只从已存在的叶格向外生长，颗粒始终有相邻支撑，不散成漂浮的噪点。
---@param target HomeTreeGrid
---@param seed integer
local function leafRelief(target,seed)
    ---@type {x:integer,y:integer,z:integer,tone:integer}[]
    local buds={}
    local function bud(x,y,z,tone)
        if not target.cells[key(x,y,z)] then
            buds[#buds+1]={x=x,y=y,z=z,tone=max(1,min(8,tone))}
        end
    end
    for _,c in ipairs(target.order) do
        local x,y,z=c.x,c.y,c.z
        local n=Noise.Hash3(x,y,z+seed)
        if n>.67 then bud(x,y+1,z,c.tone+1) end
        if n<.09 then bud(x,y-1,z,c.tone-1) end
        -- 四周只补一部分枝梢，保持叶簇大形和透景缝。
        if n>.87 then bud(x+1,y,z,c.tone) end
        if n<.12 then bud(x-1,y,z,c.tone-1) end
        if n>.42 and n<.54 then bud(x,y,z+1,c.tone) end
        if n>.23 and n<.35 then bud(x,y,z-1,c.tone) end
    end
    for _,c in ipairs(buds) do target:Set(c.x,c.y,c.z,c.tone) end
end

---@class HomeTreeOptions
---@field h number
---@field r number
---@field trunk number
---@field gold boolean
---@field lean number
---@field leanA number
---@field seed integer
---@param parent Node
---@param x number
---@param gy number
---@param z number
---@param o HomeTreeOptions
function M.Tree(parent,x,gy,z,o)
    local seed=o.seed
    local rng=Noise.Rng(seed)
    local root=parent:CreateChild("Tree")
    root.position=Vector3(x,gy,z)
    local wood,leaves=grid(.125),grid(.1875)
    local h,cr,tr=o.h,o.r,o.trunk
    local lx,lz=cos(o.leanA)*o.lean,sin(o.leanA)*o.lean
    ---@param t number
    ---@return Vector3
    local function trunkAt(t)
        return Vector3(lx*t*t+sin(t*pi)*.13,t*h,lz*t*t)
    end
    ---@type Vector3[]
    local points={}
    for i=0,10 do points[#points+1]=trunkAt(i/10) end
    woodPath(wood,points,tr,tr*.28,seed)
    -- 基部连续加厚，五条有宽度的根须埋入地表，不悬在树干旁边。
    woodPath(wood,{Vector3(0,-.18,0),trunkAt(.16)},tr*1.28,tr*.90,seed)
    for i=1,5 do
        local a=i*pi*2/5+rng:Range(-.22,.22)
        local d=Vector3(cos(a),0,sin(a))
        woodPath(wood,{trunkAt(.12),d*tr*1.4+Vector3(0,.25,0),d*tr*2.5+Vector3(0,-.12,0)},
            tr*.48,.09,seed+i)
    end
    -- 主冠高低错落；侧冠由可见分枝托住，层与层之间留下透景缝。
    local top=trunkAt(1)
    crownClump(leaves,top+Vector3(0,cr*.12,0),cr*.57,seed+20,.14)
    crownClump(leaves,top+Vector3(-cr*.28,cr*.37,cr*.13),cr*.36,seed+21,.20)
    local a0=rng:Range(0,2*pi)
    local count=o.gold and 7 or 6
    for i=1,count do
        local a=a0+i/count*2*pi+rng:Range(-.17,.17)
        local spread=cr*rng:Range(.61,.88)
        local level=.67+(i%3)*.105
        local p=trunkAt(level)+Vector3(cos(a)*spread,cr*.02,sin(a)*spread)
        local fork=trunkAt(level-.20)
        local mid=(fork+p)*.5+Vector3(0,.18,0)
        woodPath(wood,{fork,mid,p+Vector3(0,.18,0)},tr*.43,.11,seed+i*3)
        local radius=cr*rng:Range(.40,.55)
        crownClump(leaves,p+Vector3(0,.25,0),radius,seed+30+i,(i%3)*.035)
        -- 小枝末端形成向外探出的方形叶簇，边缘有颗粒，不能整棵像一团切方的球。
        local tip=p+Vector3(cos(a+.3)*radius*.8,-radius*.25,sin(a+.3)*radius*.8)
        woodPath(wood,{mid,p,tip},tr*.20,.075,seed+i*5)
        crownClump(leaves,tip+Vector3(0,.10,0),radius*.46,seed+50+i,-.025)
    end
    leafRelief(leaves,seed)
    local material=cache:GetResource("Material","Materials/HomeTreeVoxel.xml")
    local barkParts=wood:Build(root,"Bark",BARK,material)
    local palette=assert(LEAVES[o.gold and 3 or (seed%2+1)])
    local leafParts=leaves:Build(root,"Leaves",palette,leafMaterial(leaves.size))
    print(string.format("HomeTrees: seed=%d gold=%s wood=%d leaf=%d surfaceQuads=%d, 2 drawables",
        seed,tostring(o.gold),#wood.order,#leaves.order,barkParts+leafParts))
    return root
end

-- 盆栽与花箱：与庭院树同一套叶簇、遮蔽和叶片材质，只是叶粒减半。
---@class HomeShrubOptions
---@field kind string 'ball' 修剪过的球冠；'hedge' 沿 Z 的矮篱
---@field r number
---@field length number|nil
---@field seed integer
---@param parent Node
---@param x number
---@param y number
---@param z number
---@param o HomeShrubOptions
function M.Shrub(parent,x,y,z,o)
    local root=parent:CreateChild("Shrub")
    root.position=Vector3(x,y,z)
    local leaves=grid(.09375)
    local seed,r=o.seed,o.r
    local rng=Noise.Rng(seed)
    if o.kind=='hedge' then
        local half=(o.length or 1)*.5
        local n=max(1,floor(half*2/(r*1.1)+.5))
        for i=0,n do
            local t=-half+2*half*i/n
            local rr=r*rng:Range(.85,1.15)
            crownClump(leaves,Vector3(rng:Range(-.04,.04),rr*.42,t),rr,seed+i*7,(i%3)*.04)
            if i%2==1 then
                crownClump(leaves,Vector3(rng:Range(-.06,.06),rr*.95,t+rng:Range(-.1,.1)),rr*.55,seed+90+i,.12)
            end
        end
    else
        crownClump(leaves,Vector3(0,r*.55,0),r,seed,.06)
        crownClump(leaves,Vector3(r*.12,r*1.05,-r*.08),r*.70,seed+1,.14)
        crownClump(leaves,Vector3(-r*.10,r*1.45,r*.06),r*.40,seed+2,.20)
        local a0=rng:Range(0,2*pi)
        for i=1,4 do
            local a=a0+i*pi/2+rng:Range(-.3,.3)
            local d=r*rng:Range(.45,.62)
            crownClump(leaves,Vector3(cos(a)*d,r*(.35+(i%2)*.35),sin(a)*d),r*rng:Range(.48,.60),
                seed+10+i,(i%3)*.035-.02)
        end
    end
    leafRelief(leaves,seed)
    leaves:Build(root,"Leaves",assert(LEAVES[seed%2+1]),leafMaterial(leaves.size))
    return root
end

return M
