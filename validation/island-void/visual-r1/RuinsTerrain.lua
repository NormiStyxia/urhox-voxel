-- 不规则空岛：同一岛域裁剪可见封闭网格、体素列和草密度。
-- Terrain 只作为 GrassField 高度采样源（viewMask=0，无物理组件）；真实地面
-- 由分块 CustomGeometry 顶/底/断缘组成，虚空没有可见面或碰撞列。
-- Height/HeightAt 无地面返回 VOID_Y；放置物体先 HasGround，安全点用 IsSafeGround。
-- 石阶/台缘沿用最新单体积方案：隐藏地形退到 -1，视觉 -1.2。

local Noise = require("ruins.Noise")
local Pal = require("ruins.RuinsPalette")
local P = Pal.P

local M = {}

M.CELL = 0.5
M.HALF = 84.0           -- 地形范围 [-84, 84]
M.Y_BASE = -18.0
M.Y_TOP = 10.0
M.COURT_R = 20.75       -- 龙庭边缘
M.RING_Y = 6.0          -- 内环 / 外环台面高度
M.RAVINE_IN = 39.5
M.RAVINE_OUT = 48.5
M.RAVINE_Y = -14.0 -- 仅兼容旧配色参数，不是地面
M.WALL_R = 51.0         -- 外城墙
M.RIM_R = 70.0
M.STAIR_HALF = 3.5      -- 大阶梯半宽
M.STAIR_END = 32.75     -- 阶梯顶端（离中心距离）
-- 可见石阶独占的网格脚印。底端留半米平踏步，顶端留到 0.5m 地形顶点边界的平平台。
M.STAIR_START = M.COURT_R - 0.5
M.STAIR_JOIN = math.ceil(M.STAIR_END / M.CELL) * M.CELL + M.CELL
M.STAIR_WALL_HALF = M.STAIR_HALF + 0.75
M.SNOW_Y = 31.0

local floor, sqrt, max, min, abs = math.floor, math.sqrt, math.max, math.min, math.abs

local function Smooth(e0, e1, x)
    local t = (x - e0) / (e1 - e0)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return t * t * (3 - 2 * t)
end
M.Smooth = Smooth


-- 集中的岛域/连接参数。预留方向不会自动生成桥或墙。
M.ISLAND = {
    mainRadius = 39.5, ringInner = 48.5, ringOuter = 70,
    bridgeHalfWidth = 4.5, bridgeMainZ = -39.25, bridgeRingZ = -49.0,
    safeMargin = 2.0, fallY = -5.0, hardFallY = -24.0,
    connections = { { name = "east", angle = 0 }, { name = "northwest", angle = 2.35 } },
}
M.VOID_Y = -128.0 -- 数值兼容哨兵；不用于造几何/落点

---@return number mainEdge, number innerEdge, number outerEdge
function M.Edges(angle)
    local ca, sa = math.cos(angle), math.sin(angle)
    local fine = (Noise.Value2(ca * 11 + 10, sa * 11 + 10, 3) - .5) * .65
    local main = M.ISLAND.mainRadius + 1.7 * math.sin(3 * angle + .6) + .9 * math.sin(5 * angle - .7) + fine
    local inner = M.ISLAND.ringInner - .8 + .7 * math.sin(3 * angle - .8) + .3 * math.sin(5 * angle) + fine * .5
    local outer = M.ISLAND.ringOuter + 2.7 * math.sin(3 * angle + .9) + 1.3 * math.sin(5 * angle - .4) + fine
    -- 四座角楼的 3.7m 基础也保留，不能通过裁墙补救地形缺口。
    local corner=1-Smooth(.12,.24,abs(math.cos(2*angle)))
    inner=min(inner,inner*(1-corner)+47.0*corner)
    -- 南路桥头、北殿整块基础、西塔台凸肩：柔和收束到保护轮廓。
    local gateAngle=math.atan(M.ISLAND.bridgeHalfWidth / -M.ISLAND.bridgeMainZ)
    local south = 1 - Smooth(gateAngle, gateAngle+.12, math.abs(math.atan(ca, -sa)))
    main = main * (1 - south) - M.ISLAND.bridgeMainZ * south
    inner = inner * (1 - south) - M.ISLAND.bridgeRingZ * south
    outer = max(outer, 69 * south)
    local north = 1 - Smooth(.20, .35, math.abs(math.atan(ca, sa)))
    outer = max(outer, 70.5 * north)
    local tower = 1 - Smooth(.13, .34, math.abs(math.atan(math.sin(angle + 2.9764), math.cos(angle + 2.9764))))
    main = max(main, 40.5 * tower)
    return main, inner, outer
end

-- 正数为岛内径向余量，负数为虚空。碰撞和网格按同一格中心取样。
---@return number
function M.EdgeDistance(x, z)
    local main, inner, outer = M.Edges(math.atan(z, x))
    local r = sqrt(x*x + z*z)
    return max(main-r, min(r-inner, outer-r))
end
---@return boolean
function M.HasGround(x, z, margin)
    return M.EdgeDistance(x,z) >= (margin or 0)
end

-- 碰撞区域侧视（d = |z|，南北镜像，所有长度单位为米）：
--  龙庭 y=0  ______|0.5____|1.0____ ... |6.0____________ 内环 y=6
--            d=20.25  20.75   21.75        31.75       33.5
--  隐藏地形 y=-1 ___________________________________________________
--  正面：扶墙 [-4.25,-3.5) | 净通道 [-3.5,3.5) | 扶墙 [3.5,4.25)
-- 检测目的：只有同一个可见体积承担踏面/立面/扶墙碰撞，不叠一份粗地形台阶。
-- 边界：底踏步先于圆形龙庭边缘，避免斜接出现 y=6 隐墙；末踏面 y=6 与平台齐平。
-- 每级 1m 深 > 胶囊直径 0.64m，0.5m 高 < stepHeight 0.55m；扶墙高 1m 仍挡人。
function M.InStair(x, z)
    local d = abs(z)
    return abs(x) < M.STAIR_HALF and d >= M.STAIR_START and d < M.STAIR_JOIN
end

function M.InStairFootprint(x, z)
    local d = abs(z)
    return abs(x) < M.STAIR_WALL_HALF and d >= M.STAIR_START and d < M.STAIR_JOIN
end

-- 阶梯台面高度（0.5m 一级、每级 1m 深；两端夹紧，不生成负台面/超高末级）
function M.StairY(z)
    return max(0, min(M.RING_Y, 0.5 * floor((abs(z) - M.COURT_R) + 1)))
end

-- 未裁剪的顶面延拓；先判新台阶，防止龙庭圆弧覆盖底踏步。
local function SurfaceHeight(x,z)
    if M.InStair(x,z) then return M.StairY(z) end
    local r=sqrt(x*x+z*z)
    if r<M.COURT_R then return 0 end
    local h = M.RING_Y
    if r > M.ISLAND.ringInner + 3 and abs(x) > 4 then
        h = h + Smooth(.55,.75,Noise.Fbm2(x*.08,z*.08,2,11)) * .6
    end
    return h
end
---@return number
function M.Height(x,z)
    if not M.HasGround(x,z) then return M.VOID_Y end
    return SurfaceHeight(x,z)
end
---@return number|nil
function M.GroundHeight(x,z)
    if M.HasGround(x,z) then return SurfaceHeight(x,z) end
    return nil
end

-- 岛底随离岸距离内收，偏心岩体向下垂落；没有跨越裂隙的底平面。
---@return number
function M.BottomHeight(x,z)
    local edge = max(0,M.EdgeDistance(x,z))
    local r = sqrt(x*x+z*z)
    local depth = r < 44 and 16 or 12
    local lobes = 4*math.exp(-((x+19)^2+(z-9)^2)/150)
        + 6*math.exp(-((x-20)^2+(z+19)^2)/90)
        + 4*math.exp(-((x+52)^2+(z+25)^2)/100)
    return min(SurfaceHeight(x,z)-1.3, 4.7
        - (depth + lobes + Noise.Value2(x*.12,z*.12,91)*2) * Smooth(0, r<44 and 12 or 8, edge))
end

-- 仅永久岛面可记录安全点：排除崖缘、台阶、墙顶和活动碎片。
---@return boolean
function M.IsSafeGround(x,y,z)
    if not M.HasGround(x,z,M.ISLAND.safeMargin) or M.InStairFootprint(x,z) then return false end
    return abs(y-SurfaceHeight(x,z)) < .45
end

-- 碰撞层顶面高度（0.5m 量化，略偏向下取：宁可脚陷进草里一点，也不要悬空）
function M.CollideHeight(x, z, height)
    if not M.HasGround(x,z) then return M.VOID_Y end
    -- 0.5m 粗网格的台阶前沿比石阶偏半格，叠上去会给胶囊两套立面/内部边。
    -- 脚印边界对齐粗网格；地基仍存在，破坏/回溯后不凭空生成上塔的隐藏坡道。
    local d = abs(z)
    if abs(x) < math.ceil(M.STAIR_WALL_HALF / M.CELL) * M.CELL
        and d >= floor(M.STAIR_START / M.CELL) * M.CELL and d < M.STAIR_JOIN then return -1.0 end
    local r2 = x * x + z * z
    if r2 < (M.COURT_R - 0.25) ^ 2 then return -1.0 end -- 龙庭地砖体积自带碰撞
    return floor((height or M.Height(x, z)) * 2.0 + 0.3) * 0.5
end

-- 显示层高度（藏在龙庭地砖 / 石阶下面）
function M.VisualHeight(x, z)
    -- 扶墙也负责遮住侧边三角面；结束压低在平台体积内，三角面升到 y=6 后才交回 Terrain。
    if abs(x) <= M.STAIR_WALL_HALF and abs(z) >= M.STAIR_START - M.CELL
        and abs(z) <= M.STAIR_JOIN - M.CELL then return -1.2 end
    local r2 = x * x + z * z
    -- 旧值 R-0.35 留出一圈 y=0 的 Terrain 与地砖同面；连三角面跨格范围一起藏在台缘下。
    if r2 < (M.COURT_R + 0.4) ^ 2 then return -1.2 end
    return SurfaceHeight(x, z)
end

-- 岩石配色（浮岩等体素岩块用）：倾斜 + 三维噪声扭曲的岩层，避免水平环带
local STRATA = { P.CLIFF_A, P.CLIFF_B, P.CLIFF_D, P.CLIFF_B, P.CLIFF_C, P.CLIFF_A }

local function StrataAt(y, x, z)
    local warp = Noise.Value3(x * 0.15, y * 0.15, z * 0.15, 31) * 3.0
    local s = y * 0.8 + x * 0.12 + z * 0.07 + warp
    local band = floor(s + Noise.Hash3(floor(x * 4), floor(y * 4), floor(z * 4)) * 0.9)
    return STRATA[(band % #STRATA) + 1]
end
M.StrataAt = StrataAt

-- 是否属于铺路
function M.IsPath(x, z)
    local r = sqrt(x * x + z * z)
    -- 南侧主路：出生点 → 城门 → 桥
    if abs(x) < 2.0 + Noise.Value2(z * 0.4, 1, 41) * 0.8 and z < -M.ISLAND.ringInner and z > -68 then return true end
    -- 内环铺石平台（柱廊一圈）
    if r >= M.COURT_R and r < 27.0 + (Noise.Value2(x * 0.3, z * 0.3, 42) - 0.5) * 1.5 then return true end
    -- 内环南北向直路（桥头 → 阶梯顶）
    if abs(x) < 3.0 and abs(z) >= M.STAIR_END - 0.5 and r < M.ISLAND.mainRadius then return true end
    -- 北殿前的石板地
    if abs(x) < 11 and z > 52 and z < 67 then return true end
    return false
end

-- ---------------------------------------------------------------- 碰撞层（隐藏体素）
local hiddenMat_ = nil
local function HiddenMaterial()
    if hiddenMat_ ~= nil then return hiddenMat_ end
    local m = Material:new()
    if not m:SetSurfaceShader("Shaders/BLGL/HiddenVoxel.shader") then
        print("RuinsTerrain: HiddenVoxel.shader failed; collision voxels will be visible")
        return nil
    end
    hiddenMat_ = m
    return m
end

---@param world VoxelPhysicsWorld
local function BuildCollision(world)
    local c, N, x0 = M.CELL, math.floor(M.HALF*2/M.CELL), -M.HALF
    local H, C, B = {}, {}, {}
    for i=-1,N do
        H[i],C[i],B[i] = {},{},{}
        for k=-1,N do
            local x,z=x0+(i+.5)*c,x0+(k+.5)*c
            local h=M.Height(x,z)
            H[i][k]=h
            C[i][k]=M.CollideHeight(x,z,h)
            B[i][k]=M.HasGround(x,z) and math.floor(M.BottomHeight(x,z)/c)*c or M.VOID_Y
        end
    end
    M.heightMap=H
    local vols, hidden = {},HiddenMaterial()
    local CH=32 -- 16m：减少空洞块包围盒的浪费
    local allocated,solid=0,0
    for ci=0,N-1,CH do for ck=0,N-1,CH do
        local i1,k1=min(N-1,ci+CH-1),min(N-1,ck+CH-1)
        local lo,hi=1e9,-1e9
        for i=ci,i1 do for k=ck,k1 do
            if C[i][k]~=M.VOID_Y then lo=min(lo,B[i][k]); hi=max(hi,C[i][k]) end
        end end
        if hi>lo then
            local ny=math.floor((hi-lo)/c+.5)
            local nx,nz=i1-ci+1,k1-ck+1
            local vol=world:CreateVolume(nx,ny,nz,c,Vector3(x0+ci*c,lo,x0+ck*c))
            local g=vol:GetGrid()
            for i=ci,i1 do for k=ck,k1 do
                if C[i][k]~=M.VOID_Y then
                    local top=math.floor((C[i][k]-lo)/c+.5)-1
                    local bottom=math.floor((B[i][k]-lo)/c+.5)
                    if top>=bottom then
                        g:FillBox(i-ci,bottom,k-ck,i-ci,top,k-ck,true)
                        solid=solid+top-bottom+1
                    end
                end
            end end
            g:PaintBox(0,0,0,nx-1,ny-1,nz-1,P.CLIFF_B)
            vol.destructible,vol.evictable=false,false
            if hidden then vol.material=hidden end
            world:FinalizeVolume(vol); vol:RebuildGeometry()
            vols[#vols+1]=vol; allocated=allocated+nx*ny*nz
        end
    end end
    M.collisionStats={chunks=#vols,allocated=allocated,solid=solid}
    print(string.format("RuinsTerrain: %d island chunks, %d allocated / %d solid cells",#vols,allocated,solid))
    return vols
end

-- ---------------------------------------------------------------- 显示层（Terrain + 草）
-- 控制图：R 铺石路  G 泥土  B 强制岩面  A 草地密度（GrassField 读 A）
-- 像素 (px, py) ↔ 世界 x = -HALF + px * 0.5，z = +HALF - py * 0.5（第 0 行是 +Z 北侧，同 Terrain UV）
local function BuildSplat(VH, NV)
    local img = Image:new()
    img:SetSize(NV, NV, 4)
    local c = M.CELL
    local x0 = -M.HALF
    local GW = {}
    for i = 0, NV - 1 do GW[i] = {} end
    M.grassWeight = GW
    local function Hv(i, k)
        i = max(0, min(NV - 1, i))
        k = max(0, min(NV - 1, k))
        return VH[i][k]
    end
    for py = 0, NV - 1 do
        local k = NV - 1 - py
        local z = x0 + k * c
        for i = 0, NV - 1 do
            local x = x0 + i * c
            local h = VH[i][k]
            local r = sqrt(x * x + z * z)
            local slope = max(abs(Hv(i + 1, k) - Hv(i - 1, k)), abs(Hv(i, k + 1) - Hv(i, k - 1))) / (2 * c)
            local path = M.IsPath(x, z) and 1.0 or 0.0
            local court = r < M.COURT_R + 0.2 or M.InStair(x, z)
            -- 泥土：路边、峡谷底、零星斑块
            local dirt = Smooth(0.68, 0.8, Noise.Fbm2(x * 0.09, z * 0.09, 3, 81))
            if h < M.RAVINE_Y + 2.5 then dirt = max(dirt, 0.75) end
            if path < 0.5 then
                for _, d in ipairs({ { 1.2, 0 }, { -1.2, 0 }, { 0, 1.2 }, { 0, -1.2 } }) do
                    if M.IsPath(x + d[1], z + d[2]) then dirt = max(dirt, 0.55) end
                end
            end
            local rock = Smooth(0.9, 1.4, slope)
            if h > M.SNOW_Y then rock = max(rock, 0.3) end
            local grass = 1.0
            if court or path > 0.5 then grass = 0 end
            grass = grass * (1 - Smooth(0.55, 0.85, slope))
            grass = grass * (1 - dirt * 0.85)
            if h < M.RAVINE_Y + 2.5 then grass = grass * 0.35 end
            if h > M.SNOW_Y - 2 then grass = grass * Smooth(M.SNOW_Y, M.SNOW_Y - 2, h) end
            -- 稀疏处带一点随机空斑（草甸不是均匀地毯）
            grass = grass * (0.55 + 0.45 * Smooth(0.25, 0.55, Noise.Fbm2(x * 0.2, z * 0.2, 2, 83)))
            grass = max(0, min(1, grass))
            if not M.HasGround(x,z,1.25) then grass=0 end
            GW[i][k] = grass
            img:SetPixel(i, py, Color(path, dirt, rock, grass))
        end
    end
    local tex = Texture2D:new()
    tex:SetNumLevels(1)
    tex:SetData(img, true)
    tex:SetFilterMode(FILTER_BILINEAR)
    tex:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    tex:SetAddressMode(COORD_V, ADDRESS_CLAMP)
    return tex
end

-- 同格中心裁剪顶/底，四邻空列才封侧缘。分块限制 Web 单网格顶点数。
---@param scene Scene
---@param mat Material
local function BuildIslandMesh(scene,mat)
    local c,N=M.CELL,math.floor(M.HALF*2/M.CELL)
    local CH=24
    local triangles,chunks=0,0
    local function Land(i,k)
        return M.heightMap[i] and M.heightMap[i][k]~=nil and M.heightMap[i][k]~=M.VOID_Y
    end
    local top,bottom={},{}
    for i=0,N do
        top[i],bottom[i]={},{}
        for k=0,N do
            local x,z=-M.HALF+i*c,-M.HALF+k*c
            top[i][k]=M.VisualHeight(x,z)
            bottom[i][k]=min(top[i][k]-1.3,M.BottomHeight(x,z))
        end
    end
    for ci=0,N-1,CH do for ck=0,N-1,CH do
        local geom
        ---@param a Vector3
        ---@param b Vector3
        ---@param d Vector3
        local function Tri(a,b,d,soil)
            if not geom then
                local node=scene:CreateChild("IslandShell")
                geom=node:CreateComponent("CustomGeometry")
                geom:BeginGeometry(0,TRIANGLE_LIST)
                geom.castShadows=true
                chunks=chunks+1
            end
            local ab=b-a --[[@as Vector3]]
            local normal=ab:CrossProduct(d-a):Normalized()
            for _,v in ipairs({a,b,d}) do
                geom:DefineVertex(v); geom:DefineNormal(normal)
                geom:DefineTexCoord(Vector2((v.x+M.HALF)/(M.HALF*2),(M.HALF-v.z)/(M.HALF*2)))
                geom:DefineColor(Color(soil or 0,0,0,1))
            end
            triangles=triangles+1
        end
        local function Quad(a,b,d,e,soil) Tri(a,b,d,soil); Tri(a,d,e,soil) end
        local function V(i,k,h) return Vector3(-M.HALF+i*c,h,-M.HALF+k*c) end
        -- 平坦岛内每 4m 合并顶面；底面使用带全部边界点的扇形，避免 T 接缝。
        -- 崖缘/台阶保留 .5m，不把小洞跨接成面。
        local used={}
        local function Key(i,k) return i*(N+1)+k end
        for i=ci,min(N-1,ci+CH-1) do for k=ck,min(N-1,ck+CH-1) do if Land(i,k) and not used[Key(i,k)] then
            local size=8
            local merge=i+size<=min(N,ci+CH) and k+size<=min(N,ck+CH)
            local h=top[i][k]
            local low,high=h,h
            if merge then
                for ii=i,i+size do for kk=k,k+size do
                    if not Land(ii,kk) or not Land(ii-1,kk-1) or used[Key(ii,kk)]
                        or abs(top[ii][kk]-h)>1.0 then merge=false end
                    low=min(low,top[ii][kk]); high=max(high,top[ii][kk])
                end end
            end
            if merge then
                if high-low<.0001 then
                    Quad(V(i,k,h),V(i,k+size,h),V(i+size,k+size,h),V(i+size,k,h))
                else
                    local tr={}
                    for t=0,size-1 do tr[#tr+1]=V(i,k+t,top[i][k+t]) end
                    for t=0,size-1 do tr[#tr+1]=V(i+t,k+size,top[i+t][k+size]) end
                    for t=0,size-1 do tr[#tr+1]=V(i+size,k+size-t,top[i+size][k+size-t]) end
                    for t=0,size-1 do tr[#tr+1]=V(i+size-t,k,top[i+size-t][k]) end
                    local tm=V(i+size/2,k+size/2,top[i+size/2][k+size/2])
                    for n=1,#tr do Tri(tm,tr[n],tr[n%#tr+1]) end
                end
                local rim={}
                for t=0,size-1 do rim[#rim+1]=V(i,k+t,bottom[i][k+t]) end
                for t=0,size-1 do rim[#rim+1]=V(i+t,k+size,bottom[i+t][k+size]) end
                for t=0,size-1 do rim[#rim+1]=V(i+size,k+size-t,bottom[i+size][k+size-t]) end
                for t=0,size-1 do rim[#rim+1]=V(i+size-t,k,bottom[i+size-t][k]) end
                local mid=V(i+size/2,k+size/2,bottom[i+size/2][k+size/2])
                for n=1,#rim do Tri(mid,rim[n%#rim+1],rim[n]) end
                for ii=i,i+size-1 do for kk=k,k+size-1 do used[Key(ii,kk)]=true end end
            else
            local a,b,d,e=V(i,k,top[i][k]),V(i,k+1,top[i][k+1]),V(i+1,k+1,top[i+1][k+1]),V(i+1,k,top[i+1][k])
            local aa,bb,dd,ee=V(i,k,bottom[i][k]),V(i,k+1,bottom[i][k+1]),V(i+1,k+1,bottom[i+1][k+1]),V(i+1,k,bottom[i+1][k])
            Quad(a,b,d,e); Quad(aa,ee,dd,bb)
            local function Edge(v,w,vb,wb)
                local vs,ws=v-Vector3(0,.35,0),w-Vector3(0,.35,0)
                Quad(w,v,vs,ws,1); Quad(ws,vs,vb,wb)
            end
            if not Land(i-1,k) then Edge(a,b,aa,bb) end
            if not Land(i,k+1) then Edge(b,d,bb,dd) end
            if not Land(i+1,k) then Edge(d,e,dd,ee) end
            if not Land(i,k-1) then Edge(e,a,ee,aa) end
            end
        end end end
        if geom then geom:Commit(); geom:SetMaterial(mat) end
    end end
    M.meshStats={triangles=triangles,chunks=chunks}
    print(string.format("RuinsTerrain: island shell %d triangles / %d chunks",triangles,chunks))
end

---@param scene Scene
local function BuildVisual(scene)
    local t0 = os.clock()
    local c = M.CELL
    local NV = (math.tointeger(M.HALF * 2 / c) or 336) + 1   -- 337 顶点
    local x0 = -M.HALF
    local VH = {}
    for i = 0, NV - 1 do
        local row = {}
        local x = x0 + i * c
        for k = 0, NV - 1 do row[k] = M.VisualHeight(x, x0 + k * c) end
        VH[i] = row
    end
    -- 16 位高度图：R = 高位、G = 低位（Terrain 对 ≥2 通道的图按 R + G/256 读取）
    local range = M.Y_TOP - M.Y_BASE
    local unit = range / 255.0
    local img = Image:new()
    local sourceN=math.floor((NV-1)/2)+1 -- 草高度源 1m，控制图仍为 .5m
    img:SetSize(sourceN, sourceN, 3)
    for py = 0, sourceN - 1 do
        local k = (sourceN - 1 - py)*2
        for i = 0, sourceN - 1 do
            local v = (VH[i*2][k] - M.Y_BASE) / unit
            if v < 0 then v = 0 elseif v > 255.99 then v = 255.99 end
            local hiB = floor(v)
            local loB = floor((v - hiB) * 256)
            img:SetPixelInt(i, py, hiB | (loB << 8))
        end
    end
    local node = scene:CreateChild("RuinsGround")
    node.position = Vector3(0, M.Y_BASE, 0)
    local t = node:CreateComponent("Terrain")
    t.patchSize = 8 -- 169 顶点 = 21 个 8m patch + 1，避免宽度被截断
    t.spacing = Vector3(c*2, unit, c*2)
    t.smoothing = false
    t.maxLodLevels = 3
    t.lodBias = 2.0
    t.castShadows = false
    t.heightMap = img
    t.viewMask = 0 -- 仅 GrassField 高度源；无 CollisionShape、无碰撞地板

    local splat = BuildSplat(VH, NV)
    M.splat = splat
    local mat = Material:new()
    if mat:SetSurfaceShader("Shaders/BLGL/RuinsGround.shader") then
        mat:SetSurfaceTexture("splat_map", splat)
        mat:SetShaderParameter("world_half", Variant(M.HALF))
        mat:SetShaderParameter("snow_y", Variant(M.SNOW_Y))
        mat:SetShaderParameter("deep_y", Variant(M.RAVINE_Y + 2.0))
    else
        print("RuinsTerrain: RuinsGround.shader failed, using PBRNoTexture")
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(0.35, 0.5, 0.25)))
    end
    t.material = mat
    BuildIslandMesh(scene,mat)
    M.groundMaterial = mat
    M.terrain = t
    M.terrainNode = node
    -- 方向自检：Terrain:GetHeight 与解析高度应一致
    local probe = Vector3(-40, 0, 60)
    print(string.format("RuinsTerrain: visual %dx%d in %.2fs, probe terrain=%.2f expect=%.2f", NV, NV, os.clock() - t0,
        t:GetHeight(probe), M.VisualHeight(probe.x, probe.z)))
    return node
end

-- 草地：GrassField（GPU 草叶）+ 野花；不支持的设备退回卡片草簇
---@param scene Scene
-- GrassField 扩展在部分 Web 引擎才有，当前 SDK 的 .emmylua 未收录；局部声明实际使用接口。
---@class RuinsGrassField: Component
---@field supported boolean
---@field material Material
---@field windDirection Vector2
---@field windStrength number
---@field windSpeed number
---@field SetInteractor fun(self:RuinsGrassField, slot:integer, pos:Vector3, radius:number)
local function BuildGrass(scene)
    local node = M.terrainNode
    local create=node.CreateComponent --[[@as fun(self:Node,name:string):RuinsGrassField|nil]]
    local grass = create(node,"GrassField")
    if grass==nil or not grass.supported then
        print("RuinsTerrain: GrassField not supported, using tuft fallback")
        if grass then node:RemoveComponent(grass) end
        M.grass = nil
        local Tufts = require("ruins.GrassTufts")
        M.tufts = Tufts.Build(scene, M)
        return
    end
    grass.densityMap = M.splat
    grass.densityChannel = 3
    grass.densityRange = Vector2(0.15, 0.75)
    grass.density = 110
    grass.bladeHeight = Vector2(0.22, 0.55)
    grass.bladeWidth = Vector2(0.008, 0.016)
    grass.clumpSize = 0.7
    grass.lean = 0.45
    grass.maxSlope = 42
    grass.viewDistance = 55
    grass.densityFalloffDistance = 16
    grass.castShadows = false
    grass.windDirection = Vector2(1, 0.35)
    grass.windStrength = 0.32
    grass.windSpeed = 3.5
    grass.gustSize = 14
    grass.flutter = 0.35
    grass.trampleRecoveryTime = 5
    local gm = grass.material:Clone()
    gm:SetShaderParameter("GrassRootColor", Variant(Vector4(0.020, 0.045, 0.012, 1.2)))
    gm:SetShaderParameter("GrassTipColor", Variant(Vector4(0.17, 0.30, 0.06, 0)))
    gm:SetShaderParameter("GrassDryColor", Variant(Vector4(0.32, 0.26, 0.08, 0.18)))
    grass.material = gm
    M.grass = grass
    -- 野花：白 / 金 / 时之蓝
    local fl = create(node,"GrassField")
    if fl==nil then return end
    fl.plantType = _G["GRASS_PLANT_FLOWER"]
    fl.densityMap = M.splat
    fl.densityChannel = 3
    fl.densityRange = Vector2(0.45, 0.95)
    fl.density = 2.5
    fl.bladeHeight = Vector2(0.38, 0.62)
    fl.bladeWidth = Vector2(0.003, 0.005)
    fl.flowerSize = 0.035
    fl.petalCount = 5
    fl.flowerCup = 0.3
    fl.viewDistance = 35
    fl.trampleRecoveryTime = 0
    fl.castShadows = false
    fl.windDirection = grass.windDirection
    fl.windStrength = grass.windStrength
    fl.windSpeed = grass.windSpeed
    local fm = fl.material:Clone()
    fm:SetShaderParameter("GrassFlowerColor", Variant(Vector4(0.85, 0.85, 0.80, 0)))
    fm:SetShaderParameter("GrassFlowerColor2", Variant(Vector4(0.25, 0.42, 0.95, 0.35)))
    fm:SetShaderParameter("GrassFlowerCenter", Variant(Vector4(0.95, 0.70, 0.20, 0.3)))
    fl.material = fm
    M.flowers = fl
    print("RuinsTerrain: GrassField ready")
end

-- 显示层顶点网格上的草地权重（0..1）
function M.GrassAt(x, z)
    local GW = M.grassWeight --[[@as table<number, table<number, number>>?]]
    if GW == nil then return 0 end
    local i = floor((x + M.HALF) / M.CELL + 0.5)
    local k = floor((z + M.HALF) / M.CELL + 0.5)
    local row = GW[i]
    if row == nil then return 0 end
    return row[k] or 0
end

-- 角色 / 龙压草：每帧调用
function M.SetInteractor(slot, pos, radius)
    local g = M.grass --[[@as RuinsGrassField?]]
    if g ~= nil then g:SetInteractor(slot, pos, radius) end
    local fl = M.flowers --[[@as RuinsGrassField?]]
    if fl ~= nil then fl:SetInteractor(slot, pos, radius) end
end

---@param world VoxelPhysicsWorld
---@param scene Scene
function M.Build(world, scene)
    local t0 = os.clock()
    local vols = BuildCollision(world)
    BuildVisual(scene)
    local ok, err = pcall(BuildGrass, scene)
    if not ok then print("RuinsTerrain: grass FAILED: " .. tostring(err)) end
    print(string.format("RuinsTerrain: total %.2fs", os.clock() - t0))
    return { volumes = vols }
end

-- 查表取地面高度（平滑真实高度；建造 / 摆放时用；超出范围走解析函数）
function M.HeightAt(x, z)
    if not M.HasGround(x,z) then return M.VOID_Y end
    local H = M.heightMap --[[@as table<number, table<number, number>>?]]
    if H ~= nil then
        local i = floor((x + M.HALF) / M.CELL)
        local k = floor((z + M.HALF) / M.CELL)
        local row = H[i]
        if row ~= nil and row[k] ~= nil then return row[k] end
    end
    return M.Height(x, z)
end

return M
