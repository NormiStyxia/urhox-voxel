-- ====================================================================
-- DragonSpec.lua — 蓝白体素巨龙的解剖数据（静止参考姿态）
--
-- 坐标：米；+X = 龙的右侧，+Y 向上，+Z = 龙头朝向；原点在两前后足之间的地面。
-- 比例取自三视图（art/dragon/ref/dragon_ref.webp），按 1m = 100px 量：
--   髋顶 ≈ 2.4m，鬐甲 ≈ 2.7m，头顶 ≈ 4.6m，角尖 ≈ 5.3m，吻尖 z ≈ +2.1，尾尖 z ≈ -5.3
-- 骨骼名以 _R 结尾的部件只写右侧，左侧由 Expand() 沿 X 镜像生成。
-- 翅膀在「翼局部坐标」里按完全展开的飞行姿态描述（翼根为原点，+X 向外，
-- 翼膜位于 y=0 平面），地面收翼姿态由关节旋转得到。
-- ====================================================================

local Sculpt = require("dragon.DragonSculpt")

local M = {}

-- 型号信息：本文件描述的就是中号（原尺寸），小号 / 大号由 DragonVariants 在此基础上形变
M.id = "medium"
M.name = "中号 · 巨龙"
M.size = 1.0          -- 整体尺度（动画里按米写的常数乘它）
M.rideable = true
M.membraneThick = 0.04
-- 静止时足底接地点（右侧，世界静止坐标）：IK / 步态的静止足位
M.footRest = { F = { 0.48, 0.0, 1.02 }, H = { 0.92, 0.0, -1.12 } }

-- ---------------------------------------------------------------- 调色板
-- 槽位 40+，避开 VoxelTown 的 1-19
M.PAL = {
    BLUE_L = 40,  -- 主体浅冰蓝鳞片
    BLUE_M = 41,  -- 中蓝鳞片 / 翼骨
    BLUE_D = 42,  -- 关节装甲深蓝
    BLUE_X = 43,  -- 角、背刺：最深的蓝
    WHITE = 44,   -- 腹甲 / 颈前
    WHITE_S = 45, -- 腹甲接缝
    MEM = 46,     -- 翼膜
    MEM2 = 47,    -- 翼膜阶梯层
    CLAW = 48,    -- 爪、齿
    EYE = 49,     -- 瞳孔（冰蓝，单个像素）
    PUPIL = 50,   -- 瞳孔 / 鼻孔
    MOUTH = 51,   -- 口腔
    BLUE_P = 52,  -- 头冠浅色高光
    MEM_EDGE = 53, -- 翼骨边的浅蓝过渡
    BLUE_L2 = 54, -- 鳞片第二色阶
}
local P = M.PAL

-- 颜色值取自参考图 k-means（渲染后颜色），按引擎观感微调
M.PALETTE = {
    [P.BLUE_L] = { 0.47, 0.71, 1.00 },
    [P.BLUE_M] = { 0.31, 0.53, 0.92 },
    [P.BLUE_D] = { 0.28, 0.43, 0.75 },
    [P.BLUE_X] = { 0.17, 0.26, 0.53 },
    [P.WHITE] = { 0.97, 0.98, 1.00 },
    [P.WHITE_S] = { 0.84, 0.88, 0.96 },
    [P.MEM] = { 0.97, 0.98, 1.00 },
    [P.MEM2] = { 0.88, 0.91, 0.97 },
    [P.CLAW] = { 0.96, 0.97, 1.00 },
    [P.EYE] = { 0.12, 0.42, 0.95 },
    [P.PUPIL] = { 0.04, 0.06, 0.14 },
    [P.MOUTH] = { 0.42, 0.16, 0.24 },
    [P.BLUE_P] = { 0.68, 0.84, 0.99 },
    [P.MEM_EDGE] = { 0.66, 0.80, 0.97 },
    [P.BLUE_L2] = { 0.40, 0.64, 0.97 },
}
-- 自发光：翼膜 / 白甲加一点点（眼睛不发光），模拟薄膜透光与次表面散射，背光面不发灰
M.EMISSIVE = {
    [P.MEM] = { 0.85, 0.9, 1.0, 0.22 },
    [P.MEM2] = { 0.8, 0.86, 1.0, 0.18 },
    [P.MEM_EDGE] = { 0.6, 0.78, 1.0, 0.12 },
    [P.WHITE] = { 0.85, 0.9, 1.0, 0.08 },
}

M.VOXEL_BODY = 0.08
M.VOXEL_HEAD = 0.055
M.VOXEL_WING = 0.10

-- ---------------------------------------------------------------- 骨骼
-- { 名称, 父, 枢轴(世界静止坐标) }；wing 部件的枢轴在 DragonRig 里由翼数据生成
M.BONES = {
    { "body", nil, { 0, 1.9, 0 } },
    { "pelvis", "body", { 0, 2.0, -0.75 } },
    { "waist", "pelvis", { 0, 2.03, -0.22 } },
    { "chest", "waist", { 0, 2.08, 0.35 } },
    { "neck1", "chest", { 0, 2.5, 0.8 } },
    { "neck2", "neck1", { 0, 2.98, 0.85 } },
    { "neck3", "neck2", { 0, 3.45, 0.88 } },
    { "neck4", "neck3", { 0, 3.9, 0.96 } },
    { "head", "neck4", { 0, 4.3, 1.1 } },
    { "jaw", "head", { 0, 4.19, 1.3 } },
    -- 前肢：肩 → 肘 → 腕
    { "armU_R", "chest", { 0.47, 1.75, 0.88 } },
    { "armL_R", "armU_R", { 0.5, 1.0, 0.76 } },
    { "hand_R", "armL_R", { 0.47, 0.33, 0.88 } },
    -- 后肢：髋 → 膝 → 跗（踵）→ 踝/足
    { "legU_R", "pelvis", { 0.74, 1.8, -0.9 } },
    { "legL_R", "legU_R", { 0.86, 1.06, -0.66 } },
    { "legM_R", "legL_R", { 0.92, 0.52, -1.42 } },
    { "foot_R", "legM_R", { 0.92, 0.14, -1.3 } },
}

-- 颈、尾中心线（用于配色判断腹侧/背侧）
local NECK_PTS = { { 2.35, 0.76, 0.4 }, { 2.98, 0.86, 0.34 }, { 3.45, 0.89, 0.305 }, { 3.9, 0.97, 0.285 }, { 4.3, 1.1, 0.27 } }
local TAIL_PTS = {
    { -1.3, 1.82, 0.47 }, { -1.85, 1.42, 0.4 }, { -2.4, 1.1, 0.33 }, { -2.95, 0.87, 0.27 },
    { -3.5, 0.7, 0.21 }, { -4.0, 0.59, 0.165 }, { -4.45, 0.52, 0.13 }, { -4.85, 0.5, 0.10 },
}
-- 尾骨枢轴 = 中心线节点
for i, t in ipairs(TAIL_PTS) do
    M.BONES[#M.BONES + 1] = { "tail" .. i, i == 1 and "pelvis" or ("tail" .. (i - 1)), { 0, t[2], t[1] } }
end

---@return number zc, number r
local function NeckAt(y)
    local pts = NECK_PTS
    if y <= pts[1][1] then return pts[1][2], pts[1][3] end
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        if y <= b[1] then
            local t = (y - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
        end
    end
    local l = pts[#pts]
    return l[2], l[3]
end

---@return number yc, number r
local function TailAt(z)
    local pts = TAIL_PTS
    if z >= pts[1][1] then return pts[1][2], pts[1][3] end
    for i = 1, #pts - 1 do
        local a, b = pts[i], pts[i + 1]
        if z >= b[1] then
            local t = (z - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
        end
    end
    local l = pts[#pts]
    return l[2], l[3]
end

-- ---------------------------------------------------------------- 配色规则
local H = Sculpt.Hash3
local floor, abs, max, min = math.floor, math.abs, math.max, math.min

-- 大块鳞片（约 0.36m），背脊一侧偏中蓝、两侧浅蓝为主（参考图的明暗分布）
local function Scales(x, y, z, dorsal)
    local s = 0.28
    local j = floor(y / s)
    local off = (j % 2) * 0.5
    local h = H(floor(x / s + off) + 17, j * 3 + 5, floor(z / s + off) - 11)
    local d = dorsal or 0
    if h < 0.1 + 0.3 * d then return P.BLUE_M end
    if h < 0.42 + 0.2 * d then return P.BLUE_L2 end
    return P.BLUE_L
end

-- 腹甲：V 形接缝（参考图正面胸口的人字形叠甲）
local function BellyPlate(x, y, z, seamAxis)
    local v
    if seamAxis == "z" then v = z + abs(x) * 0.35 else v = y + abs(x) * 0.55 end
    if (v % 0.32) < 0.04 then return P.WHITE_S end
    return P.WHITE
end

local function Clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end

local function TorsoColor(x, y, z)
    -- 胸口白甲：正面中线一条，向下收窄
    local w = 0.17 + 0.12 * max(0, min(1, (y - 1.35) / 1.0))
    if z > 0.85 and abs(x) < w and y < 2.5 then return BellyPlate(x, y, z, "y") end
    -- 腹部下侧
    local bellyY = 1.74 + 0.05 * math.cos(z * 2.1)
    if y < bellyY and abs(x) < 0.38 then return P.WHITE end -- 腹底纯白：细接缝在掠射角下会爬动闪烁
    return Scales(x, y, z, Clamp01((y - 2.25) / 0.4))
end

local function NeckColor(x, y, z)
    local zc, r = NeckAt(y)
    if z - zc > r * 0.45 and abs(x) < 0.24 then return P.WHITE end
    return Scales(x, y, z, Clamp01((zc - z) / r))
end

local function TailColor(x, y, z)
    local yc, r = TailAt(z)
    if y - yc < -0.2 * r and abs(x) < r * 0.85 then return BellyPlate(x, y, z, "z") end
    return Scales(x, y, z, Clamp01((y - yc) / r))
end

-- 关节装甲（深蓝块）：肘后、膝前、跗关节、腕
local ARMOR = {
    { 0.5, 0.78, 1.0, 0.12 },    -- 前腿正面护甲
    { 0.48, 0.38, 1.08, 0.08 },  -- 前腕
    { 0.98, 1.0, -0.48, 0.12 },  -- 后膝正面
    { 0.7, 0.95, 0.72, 0.13 },   -- 肘外侧
    { 1.06, 1.06, -0.62, 0.13 }, -- 膝外侧
    { 1.06, 0.5, -1.45, 0.1 },   -- 跗外侧
}
local function LimbColor(x, y, z)
    local ax = abs(x)
    for _, a in ipairs(ARMOR) do
        local dx, dy, dz = ax - a[1], y - a[2], z - a[3]
        if dx * dx + dy * dy + dz * dz < a[4] * a[4] then return P.BLUE_D end
    end
    -- 四肢内侧偏白
    return Scales(x, y, z)
end

local function HeadColor(x, y, z)
    -- 下巴 / 上唇白
    if y < 4.27 and z > 1.25 then return P.WHITE end
    -- 头顶、吻背中蓝鳞
    if y > 4.5 and abs(x) < 0.13 then return P.BLUE_M end
    local i, j, k = floor(x / 0.12), floor(y / 0.1), floor(z / 0.12)
    if H(i, j, k) < 0.25 then return P.BLUE_P end
    return P.BLUE_L
end

local function JawColor(x, y, z)
    if y > 4.16 and abs(x) < 0.11 and z > 1.42 then return P.MOUTH end
    if y < 4.1 or abs(x) < 0.1 then return P.WHITE end
    return P.BLUE_L
end

local function TailTipColor(x, y, z)
    local dz = z + 5.05
    local dy = y - 0.5
    local r = abs(dz) * 0.7 + abs(dy) + abs(x)
    if r < 0.17 then return P.WHITE end
    if r > 0.3 then return P.BLUE_D end
    return P.BLUE_M
end

-- ---------------------------------------------------------------- 体块构造
local PRIMS = {}
local function add(p)
    PRIMS[#PRIMS + 1] = p
    return p
end
local function E(bone, c, r, color, o)
    o = o or {}
    o.type, o.bone, o.c, o.r, o.color = "ellipsoid", bone, c, r, color
    return add(o)
end
local function C(bone, a, b, ra, rb, color, o)
    o = o or {}
    o.type, o.bone, o.a, o.b, o.r, o.color = "cone", bone, a, b, { ra, rb }, color
    return add(o)
end
local function B(bone, c, h, color, o)
    o = o or {}
    o.type, o.bone, o.c, o.h, o.color = "box", bone, c, h, color
    return add(o)
end
local function F(bone, base, u, v, len, h, color, o)
    o = o or {}
    o.type, o.bone, o.base, o.u, o.v, o.len, o.h, o.color = "fin", bone, base, u, v, len, h, color
    return add(o)
end
local function RH(bone, c, u, v, a, b, thick, color, o)
    o = o or {}
    o.type, o.bone, o.c, o.u, o.v, o.a, o.b, o.thick, o.color = "rhombus", bone, c, u, v, a, b, thick, color
    return add(o)
end

local PL = nil -- 鳞片浮雕（随机凸起会让表面发脏，关闭；层次靠配色和体块台阶）

-- 躯干
E("pelvis", { 0, 1.93, -0.85 }, { 0.64, 0.48, 0.62 }, TorsoColor, { k = 0.22, plate = PL })
E("pelvis", { 0, 1.95, -1.2 }, { 0.47, 0.38, 0.45 }, TorsoColor, { k = 0.2, plate = PL })
E("waist", { 0, 1.92, -0.2 }, { 0.66, 0.6, 0.56 }, TorsoColor, { k = 0.22, plate = PL })
E("chest", { 0, 2.02, 0.5 }, { 0.75, 0.68, 0.72 }, TorsoColor, { k = 0.22, plate = PL })
E("chest", { 0, 1.74, 0.88 }, { 0.56, 0.42, 0.42 }, TorsoColor, { k = 0.2, plate = PL })
E("chest", { 0, 2.42, 0.55 }, { 0.52, 0.32, 0.62 }, TorsoColor, { k = 0.2, plate = PL })
-- 肩部翼根隆起：翅膀从胸侧外缘长出来，而不是插在脊线上（参考冰与火翼根枢轴在胸侧外）
E("chest", { 0.62, 2.42, 0.45 }, { 0.3, 0.26, 0.32 }, TorsoColor, { k = 0.16, sym = true })

-- 颈
for i = 1, 4 do
    local a, b = NECK_PTS[i], NECK_PTS[i + 1]
    C("neck" .. i, { 0, a[1], a[2] }, { 0, b[1], b[2] }, a[3], b[3], NeckColor, { k = 0.14, plate = PL })
end
-- 颈前白色叠甲：下缘外翘
do
    local y = 2.62
    local seg = { { 2.98, "neck1" }, { 3.45, "neck2" }, { 3.9, "neck3" }, { 9, "neck4" } }
    while y < 4.16 do
        local zc, r = NeckAt(y)
        local bone = "neck4"
        for _, s in ipairs(seg) do
            if y < s[1] then bone = s[2]; break end
        end
        B(bone, { 0, y, zc + r * 0.86 }, { 0.16 + r * 0.14, 0.1, 0.13 }, P.WHITE, { rot = { -26, 0, 0 }, round = 0.03 })
        y = y + 0.19
    end
end

-- 头（体素 0.055）
E("head", { 0, 4.44, 1.32 }, { 0.3, 0.25, 0.3 }, HeadColor, { k = 0.1 })
E("head", { 0, 4.31, 1.38 }, { 0.33, 0.17, 0.25 }, HeadColor, { k = 0.1 })
B("head", { 0, 4.33, 1.76 }, { 0.17, 0.11, 0.3 }, HeadColor, { k = 0.08, round = 0.06, rot = { 5, 0, 0 } })
B("head", { 0, 4.43, 1.62 }, { 0.12, 0.05, 0.24 }, P.BLUE_M, { k = 0.05, round = 0.03, rot = { 6, 0, 0 } })
E("head", { 0, 4.32, 2.03 }, { 0.15, 0.1, 0.07 }, HeadColor, { k = 0.06 })
B("head", { 0.17, 4.56, 1.62 }, { 0.1, 0.04, 0.12 }, P.BLUE_M, { sym = true, rot = { 0, -15, 18 }, round = 0.02 })
-- 眼睛：浅色眼白 + 深色瞳孔（像素风，不发光）。
-- 直接用最终世界坐标（不参与头部缩放），贴在实测的脸侧表面上（y≈4.50, z≈1.69 处表面 x≈0.20）；
-- 瞳孔对齐头部体素网格（0.055m）的一个格心：x=4s, y=(81+0.5)s, z=31s，prio 让它压过眼白
B("head", { 0.205, 4.48, 1.68 }, { 0.05, 0.06, 0.1 }, P.CLAW, { sym = true, worldSpace = true, tag = "eye" })
-- 瞳孔：深色，1 宽 × 2 高，放在眼白最前一列（k=32，z=1.76）→ 目光朝前
B("head", { 0.235, 4.51, 1.76 }, { 0.03, 0.045, 0.026 }, P.PUPIL, { sym = true, worldSpace = true, prio = 0.2, tag = "pupil" })
-- 上眼睑：眼白上方一道深蓝线（j=83），压低眼神
B("head", { 0.225, 4.5925, 1.69 }, { 0.035, 0.026, 0.1 }, P.BLUE_X, { sym = true, worldSpace = true, prio = 0.2, tag = "eyelid" })
B("head", { 0.07, 4.38, 2.08 }, { 0.026, 0.02, 0.03 }, P.PUPIL, { sym = true, tag = "nostril" })
C("head", { 0.12, 4.25, 1.92 }, { 0.12, 4.12, 1.95 }, 0.03, 0.012, P.CLAW, { sym = true, tag = "tooth" })
C("head", { 0.09, 4.25, 1.75 }, { 0.09, 4.16, 1.76 }, 0.022, 0.01, P.CLAW, { sym = true, tag = "tooth" })
F("head", { 0, 4.66, 1.38 }, { 0, 0, -1 }, { 0, 1, -0.4 }, 0.22, 0.22, P.BLUE_P, { sweep = 0.1, thick = 0.1, tag = "crest" })
F("head", { 0, 4.58, 1.08 }, { 0, 1, 0 }, { 0, 0.2, -1 }, 0.2, 0.3, P.BLUE_X, { sweep = -0.06, thick = 0.1, tag = "crest" })
F("head", { 0.12, 4.45, 1.02 }, { 0, 1, 0 }, { 0.3, 0.1, -1 }, 0.18, 0.3, P.BLUE_X, { sym = true, sweep = -0.08, thick = 0.09, tag = "crest" })
F("head", { 0.1, 4.28, 0.98 }, { 0, 1, 0 }, { 0.3, -0.15, -1 }, 0.16, 0.26, P.BLUE_X, { sym = true, sweep = -0.1, thick = 0.09, tag = "crest" })
-- 角：四段弧（anchor = 角根，型号变体以它为中心缩放角长）
local HORN_ROOT = { 0.17, 4.58, 1.22 }
C("head", { 0.17, 4.58, 1.22 }, { 0.26, 4.74, 0.98 }, 0.11, 0.095, P.BLUE_X, { sym = true, tag = "horn", anchor = HORN_ROOT })
C("head", { 0.26, 4.74, 0.98 }, { 0.33, 4.86, 0.74 }, 0.095, 0.08, P.BLUE_X, { sym = true, tag = "horn", anchor = HORN_ROOT })
C("head", { 0.33, 4.86, 0.74 }, { 0.36, 5.04, 0.58 }, 0.08, 0.06, P.BLUE_X, { sym = true, tag = "horn", anchor = HORN_ROOT })
C("head", { 0.36, 5.04, 0.58 }, { 0.33, 5.22, 0.56 }, 0.06, 0.035, P.BLUE_X, { sym = true, tag = "horn", anchor = HORN_ROOT })
C("head", { 0.33, 5.22, 0.56 }, { 0.28, 5.32, 0.62 }, 0.035, 0.012, P.BLUE_X, { sym = true, tag = "horn", anchor = HORN_ROOT })
C("head", { 0.29, 4.78, 0.92 }, { 0.42, 4.84, 0.78 }, 0.05, 0.015, P.BLUE_X, { sym = true, tag = "horn", anchor = HORN_ROOT })
-- 颊侧鳍状冠（白 / 浅蓝）
F("head", { 0.24, 4.56, 1.2 }, { 0, 1, 0 }, { 0.7, 1.0, -0.5 }, 0.15, 0.3, P.BLUE_P, { sym = true, sweep = 0.05, thick = 0.09 , tag = "cheek" })
F("head", { 0.28, 4.45, 1.2 }, { 0, 1, 0 }, { 1, 0.45, -0.45 }, 0.2, 0.5, P.WHITE, { sym = true, sweep = 0.05, thick = 0.1 , tag = "cheek" })
F("head", { 0.3, 4.32, 1.18 }, { 0, 1, 0 }, { 1, -0.05, -0.4 }, 0.2, 0.52, P.WHITE, { sym = true, sweep = -0.03, thick = 0.1 , tag = "cheek" })
F("head", { 0.28, 4.2, 1.17 }, { 0, 1, 0 }, { 1, -0.6, -0.35 }, 0.15, 0.34, P.BLUE_P, { sym = true, sweep = -0.06, thick = 0.09 , tag = "cheek" })

-- 下颚
B("jaw", { 0, 4.12, 1.7 }, { 0.15, 0.075, 0.3 }, JawColor, { k = 0.06, round = 0.04, rot = { -3, 0, 0 } })
E("jaw", { 0, 4.14, 1.38 }, { 0.26, 0.12, 0.2 }, JawColor, { k = 0.08 })
C("jaw", { 0.1, 4.16, 1.86 }, { 0.1, 4.25, 1.88 }, 0.025, 0.01, P.CLAW, { sym = true, tag = "tooth" })

-- 背刺（颈后、背、尾）
do
    local neckSp = { { 2.82, "neck1" }, { 3.15, "neck2" }, { 3.5, "neck3" }, { 3.82, "neck3" }, { 4.12, "neck4" } }
    for n, s in ipairs(neckSp) do
        local zc, r = NeckAt(s[1])
        F(s[2], { 0, s[1], zc - r + 0.06 }, { 0, 1, 0 }, { 0, -0.3, -1 }, 0.32, 0.38 - n * 0.015, P.BLUE_X,
            { sweep = -0.16, thick = 0.2, tag = "spike" })
    end
    local backSp = { { 0.5, 2.68, "chest" }, { 0.12, 2.56, "chest" }, { -0.28, 2.5, "waist" }, { -0.7, 2.42, "pelvis" }, { -1.08, 2.4, "pelvis" } }
    for _, s in ipairs(backSp) do
        F(s[3], { 0, s[2] - 0.04, s[1] }, { 0, 0, -1 }, { 0, 1, -0.25 }, 0.34, 0.33, P.BLUE_X, { sweep = 0.12, thick = 0.22, tag = "spike" })
    end
    for i = 1, 7 do
        local a, b = TAIL_PTS[i], TAIL_PTS[i + 1]
        local zm, ym, rm = (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5, (a[3] + b[3]) * 0.5
        local dz, dy = b[1] - a[1], b[2] - a[2]
        local l = math.sqrt(dz * dz + dy * dy)
        local hgt = 0.26 - (i - 1) * 0.026
        F("tail" .. i, { 0, ym + rm - 0.04, zm }, { 0, dy / l, dz / l }, { 0, 1, 0 }, 0.3 - i * 0.015, hgt + 0.04, P.BLUE_X,
            { sweep = 0.1, thick = 0.2 - i * 0.012, tag = "spike" })
    end
end

-- 尾
for i = 1, 7 do
    local a, b = TAIL_PTS[i], TAIL_PTS[i + 1]
    C("tail" .. i, { 0, a[2], a[1] }, { 0, b[2], b[1] }, a[3], b[3], TailColor, { k = 0.1, plate = i < 5 and PL or nil })
end
C("tail8", { 0, 0.5, -4.85 }, { 0, 0.5, -5.0 }, 0.1, 0.08, TailColor)
RH("tail8", { 0, 0.5, -5.08 }, { 0, 0, 1 }, { 0, 1, 0 }, 0.32, 0.22, 0.1, TailTipColor, { tag = "tailblade" })
RH("tail8", { 0, 0.5, -5.08 }, { 0, 0, 1 }, { 1, 0, 0 }, 0.32, 0.22, 0.1, TailTipColor, { tag = "tailblade" })

-- 前肢
E("armU_R", { 0.52, 1.62, 0.9 }, { 0.34, 0.4, 0.35 }, LimbColor, { k = 0.12, plate = PL })
C("armU_R", { 0.48, 1.7, 0.88 }, { 0.5, 1.0, 0.76 }, 0.33, 0.27, LimbColor, { k = 0.1, plate = PL })
C("armL_R", { 0.5, 1.0, 0.76 }, { 0.47, 0.35, 0.88 }, 0.27, 0.23, LimbColor, { k = 0.08 })
C("hand_R", { 0.47, 0.33, 0.88 }, { 0.48, 0.12, 0.97 }, 0.23, 0.23, LimbColor, { k = 0.06 })
E("hand_R", { 0.48, 0.1, 1.02 }, { 0.2, 0.1, 0.2 }, P.BLUE_M, { k = 0.06 })
-- 趾 / 爪：记入 M.DIGITS（右侧），大号型号把它们拆成可独立弯曲的趾骨
M.DIGITS = {}
local function Digit(limb, n, bone, a1, b1, r1, a2, b2, r2)
    C(bone, a1, b1, r1[1], r1[2], P.BLUE_M, { tag = "digit" })
    C(bone, a2, b2, r2[1], r2[2], P.CLAW, { tag = "claw" })
    M.DIGITS[#M.DIGITS + 1] = { limb = limb, n = n, parent = bone, a1 = a1, b1 = b1, r1 = r1, a2 = a2, b2 = b2, r2 = r2 }
end
for n, dx in ipairs({ -0.13, -0.045, 0.045, 0.13 }) do
    Digit("F", n, "hand_R", { 0.48 + dx, 0.09, 1.05 }, { 0.48 + dx * 1.25, 0.075, 1.2 }, { 0.058, 0.052 },
        { 0.48 + dx * 1.25, 0.08, 1.18 }, { 0.48 + dx * 1.3, 0.04, 1.33 }, { 0.07, 0.03 })
end

-- 后肢
E("legU_R", { 0.72, 1.5, -0.92 }, { 0.22, 0.44, 0.4 }, LimbColor, { k = 0.14, plate = PL })
C("legU_R", { 0.74, 1.8, -0.9 }, { 0.84, 1.06, -0.68 }, 0.26, 0.2, LimbColor, { k = 0.1, plate = PL })
C("legL_R", { 0.84, 1.06, -0.68 }, { 0.92, 0.52, -1.42 }, 0.22, 0.19, LimbColor, { k = 0.08 })
E("legL_R", { 0.88, 0.88, -0.95 }, { 0.18, 0.22, 0.26 }, LimbColor, { k = 0.08 })
C("legM_R", { 0.92, 0.52, -1.42 }, { 0.92, 0.14, -1.3 }, 0.2, 0.19, LimbColor, { k = 0.06 })
E("foot_R", { 0.92, 0.1, -1.15 }, { 0.21, 0.1, 0.25 }, P.BLUE_M, { k = 0.06 })
for n, dx in ipairs({ -0.14, -0.047, 0.047, 0.14 }) do
    Digit("H", n, "foot_R", { 0.92 + dx, 0.09, -1.08 }, { 0.92 + dx * 1.25, 0.075, -0.84 }, { 0.062, 0.056 },
        { 0.92 + dx * 1.25, 0.08, -0.86 }, { 0.92 + dx * 1.3, 0.04, -0.71 }, { 0.07, 0.03 })
end
C("foot_R", { 0.92, 0.18, -1.36 }, { 0.92, 0.07, -1.52 }, 0.05, 0.02, P.BLUE_X)

-- ---------------------------------------------------------------- 关节球
-- 防裂缝：关节处一个挂在父骨骼上的内部球（半径 = 较细一侧截面 ×0.85 − 1.5 格），prio 只在球内
-- 生效、不碰外表面。子关节弯曲时父骨骼的球填住缝；整条龙没有任何重复体素，不会共面闪烁。
do
    local VB = 0.08 * 1.5
    local J = {
        { "pelvis", { 0, 2.03, -0.22 }, 0.58 }, { "waist", { 0, 2.08, 0.35 }, 0.6 },
        { "chest", { 0, 2.5, 0.8 }, NECK_PTS[1][3] }, { "neck1", { 0, 2.98, 0.86 }, NECK_PTS[2][3] },
        { "neck2", { 0, 3.45, 0.89 }, NECK_PTS[3][3] }, { "neck3", { 0, 3.9, 0.97 }, NECK_PTS[4][3] },
        { "pelvis", { 0, TAIL_PTS[1][2], TAIL_PTS[1][1] }, TAIL_PTS[1][3] },
        { "chest", { 0.47, 1.75, 0.88 }, 0.3 }, { "armU_R", { 0.5, 1.0, 0.76 }, 0.23 }, { "armL_R", { 0.47, 0.33, 0.88 }, 0.2 },
        { "pelvis", { 0.74, 1.8, -0.9 }, 0.26 }, { "legU_R", { 0.84, 1.06, -0.68 }, 0.2 },
        { "legL_R", { 0.92, 0.52, -1.42 }, 0.18 }, { "legM_R", { 0.92, 0.14, -1.3 }, 0.17 },
    }
    for i = 1, 6 do J[#J + 1] = { "tail" .. i, { 0, TAIL_PTS[i + 1][2], TAIL_PTS[i + 1][1] }, TAIL_PTS[i + 1][3] } end
    for _, j in ipairs(J) do
        local r = j[3] * 0.85 - VB
        if r > 0.05 then
            local c = j[2]
            local sym = (j[1]:sub(-2) ~= "_R") and c[1] ~= 0 or nil
            E(j[1], c, { r, r, r }, P.BLUE_L, { prio = 0.4, sym = sym, joint = true })
        end
    end
end

-- ---------------------------------------------------------------- 翅膀
-- 右翼，翼局部坐标（翼根为原点）的完全展开姿态
M.WING = {
    root = { 0.74, 2.5, 0.45 }, -- 世界静止坐标（肩部隆起外侧）
    elbow = { 1.1, 0, 0.18 },
    wrist = { 2.55, 0, -0.02 },
    -- 指骨：a = 从 +X 朝 -Z 的展开角（度），L = 全长；关节在 joint*L 处
    fingers = {
        { a = 8, L = 4.6 },
        { a = 34, L = 3.8 },
        { a = 60, L = 3.05 },
        { a = 90, L = 2.35 },
    },
    joint = 0.52,
    flank = { -0.3, 0, -1.4 }, -- 翼膜后缘贴体点（向脊线内收，贴住背侧）
    scallop = 0.16,
    strips = 2,                -- 每个指间翼膜的插值薄片数
    -- 大骨弧度（调研起调值）：沿骨长 0/25/50/75/100% 的前缘偏移比例与半径比例
    bones = {
        -- offs = 向前缘凸的偏移/骨长，arch = 向背侧拱起/骨长（中点峰值）；冰与火 + 蝙蝠解剖整合
        humerus = { r0 = 0.24, arch = 0.04, offs = { 0, 0.04, 0.06, 0.045, 0 }, rads = { 1.0, 0.9, 0.78, 0.74, 0.8 } },
        forearm = { r0 = 0.2, arch = 0.05, offs = { 0, 0.06, 0.1, 0.07, 0 }, rads = { 1.1, 0.88, 0.77, 0.8, 1.12 } },
    },
}

-- 关节锚点（指骨关节点、指尖）
local function FingerPoints(w)
    local wx, wz = w.wrist[1], w.wrist[3]
    local out = {}
    for i, f in ipairs(w.fingers) do
        local a = math.rad(f.a)
        local dx, dz = math.cos(a), -math.sin(a)
        out[i] = {
            dir = { dx, 0, dz },
            joint = { wx + dx * f.L * w.joint, 0, wz + dz * f.L * w.joint },
            tip = { wx + dx * f.L, 0, wz + dz * f.L },
        }
    end
    return out
end
M.FingerPoints = FingerPoints

-- 翼骨体块（翼局部坐标；骨骼名在 Rig 里拼 _R/_L）
-- w 缺省为中号 M.WING；型号变体传入已按 w.unit 缩放过的翼数据，粗细常数同比缩放
function M.WingBonePrims(w)
    w = w or M.WING
    local u = w.unit or 1.0
    local fp = FingerPoints(w)
    local list = {}
    local function Cw(bone, a, b, ra, rb, color)
        list[#list + 1] = Sculpt.Prepare({ type = "cone", bone = bone, a = a, b = b, r = { ra * u, rb * u }, color = color, k = 0.04 * u })
    end
    local function Ew(bone, c, r, color)
        list[#list + 1] = Sculpt.Prepare({ type = "ellipsoid", bone = bone, c = c, r = { r[1] * u, r[2] * u, r[3] * u }, color = color, k = 0.04 * u })
    end
    local O = { 0, 0, 0 }
    -- 弧形大骨：沿二次弧线分段拼接，向翼前缘（+Z）拱起；两端关节粗、中段收细
    -- 弧形大骨：按采样点（t = 0/.25/.5/.75/1）拼 4 段锥体，向翼前缘（+Z）拱起；
    -- offs = 偏移 / 骨长，rads = 半径 / r0（肘、腕处膨大、中段收细）
    local function CurvedBone(bone, a, b, r0, offs, rads, arch)
        local dx, dz = b[1] - a[1], b[3] - a[3]
        local L = math.sqrt(dx * dx + dz * dz)
        local nx, nz = -dz / L, dx / L
        if nz < 0 then nx, nz = -nx, -nz end
        local prev
        for i = 1, #offs do
            local t = (i - 1) / (#offs - 1)
            local o = offs[i] * L
            local lift = (arch or 0) * L * 4 * t * (1 - t) -- 向背侧拱起
            local p = { a[1] + dx * t + nx * o, lift, a[3] + dz * t + nz * o }
            local r = r0 * rads[i] -- Cw 内再乘 u
            if prev ~= nil then Cw(bone, prev.p, p, prev.r, r, P.BLUE_M) end
            prev = { p = p, r = r }
        end
    end
    local wb = w.bones
    Ew("wing", O, { 0.22, 0.2, 0.22 }, P.BLUE_M)
    CurvedBone("wing", O, w.elbow, wb.humerus.r0, wb.humerus.offs, wb.humerus.rads, wb.humerus.arch)
    Ew("wfore", w.elbow, { 0.32, 0.22, 0.26 }, P.BLUE_M) -- 肘：尺骨鹰嘴膨大
    CurvedBone("wfore", w.elbow, w.wrist, wb.forearm.r0, wb.forearm.offs, wb.forearm.rads, wb.forearm.arch)
    Ew("whand", w.wrist, { 0.24, 0.18, 0.22 }, P.BLUE_D) -- 腕骨结
    local W = w.wrist
    Cw("whand", { W[1] + 0.04 * u, 0, W[3] + 0.1 * u }, { W[1] + 0.12 * u, 0.03 * u, W[3] + 0.4 * u }, 0.08, 0.025, P.CLAW)
    for i, f in ipairs(fp) do
        -- 一指 = 翼前缘，粗；其余指骨细（参考图翼面大面积是白膜）
        local r0, r1 = (i == 1) and 0.16 or 0.13, (i == 1) and 0.14 or 0.1
        Cw("wf" .. i, W, f.joint, r0, r1, P.BLUE_M)
        Cw("wf" .. i .. "m", f.joint, f.tip, r1, (i == 1) and 0.08 or 0.06, P.BLUE_M)
    end
    return list
end

-- ---------------------------------------------------------------- 命中区 / 挂点
M.HIT_ZONES = {
    { name = "head", bone = "head", offset = { 0, 0.08, 0.35 }, radius = 0.42 },
    { name = "neck", bone = "neck2", offset = { 0, 0.2, 0.05 }, radius = 0.45 },
    { name = "chest", bone = "chest", offset = { 0, -0.05, 0.25 }, radius = 0.8 },
    { name = "torso", bone = "waist", offset = { 0, 0, 0 }, radius = 0.68 },
    { name = "pelvis", bone = "pelvis", offset = { 0, 0, -0.15 }, radius = 0.68 },
    { name = "wingRoot_R", bone = "wing_R", offset = { 0.3, 0, 0 }, radius = 0.35 },
    { name = "wingRoot_L", bone = "wing_L", offset = { -0.3, 0, 0 }, radius = 0.35 },
    { name = "armF_R", bone = "armU_R", offset = { 0.02, -0.35, -0.05 }, radius = 0.32 },
    { name = "armF_L", bone = "armU_L", offset = { -0.02, -0.35, -0.05 }, radius = 0.32 },
    { name = "legH_R", bone = "legU_R", offset = { 0.05, -0.3, 0.05 }, radius = 0.45 },
    { name = "legH_L", bone = "legU_L", offset = { -0.05, -0.3, 0.05 }, radius = 0.45 },
    { name = "tailBase", bone = "tail2", offset = { 0, -0.15, -0.25 }, radius = 0.38 },
    { name = "tailTip", bone = "tail7", offset = { 0, 0, -0.35 }, radius = 0.3 },
}
-- 挂点：喉部（吐息起点）、口腔、胸腔共鸣（声音）
M.SOCKETS = {
    { name = "mouth", bone = "head", offset = { 0, -0.04, 0.95 } },
    { name = "throat", bone = "neck4", offset = { 0, 0.0, 0.3 } },
    { name = "chestCore", bone = "chest", offset = { 0, 0, 0.4 } },
    { name = "saddle", bone = "chest", offset = { 0, 0.66, -0.12 } }, -- 骑乘鞍座（胸背，翼根之间）
}

-- ---------------------------------------------------------------- 展开对称
local function MirrorName(name)
    if name:sub(-2) == "_R" then return name:sub(1, -3) .. "_L" end
    return nil
end
M.MirrorName = MirrorName

local function MirrorVec(v)
    return v and { -v[1], v[2], v[3] } or nil
end

-- Prepare 算出的派生字段（包围盒、旋转矩阵、局部轴）不能跟着拷，否则镜像体块仍用原侧的包围盒
local DERIVED = { bmin = true, bmax = true, m = true, cx = true, cy = true, cz = true, fu = true, fv = true, fw = true,
    ax = true, ay = true, az = true, dx = true, dy = true, dz = true, invLen2 = true, ra = true, rb = true }
local function CopyPrim(p, bone)
    local q = {}
    for k, v in pairs(p) do if not DERIVED[k] then q[k] = v end end
    q.bone = bone
    for _, key in ipairs({ "c", "a", "b", "base", "u", "v", "anchor" }) do
        if p[key] then q[key] = MirrorVec(p[key]) end
    end
    if p.rot then q.rot = { p.rot[1], -p.rot[2], -p.rot[3] } end
    if type(p.color) == "function" then
        local f = p.color
        q.color = function(x, y, z, pr) return f(-x, y, z, pr) end
    end
    q.sym = nil
    return q
end

-- 头部整体缩放（围绕头骨枢轴）：参考图头部明显宽于颈部
M.HEAD_SCALE = 1.18
M.HEAD_WIDEN = 1.14 -- 额外横向加宽（正视图头部与颊冠更宽）
local HEAD_PIVOT = { 0, 4.3, 1.1 }
local function ScaleAbout(v, c, s)
    return { c[1] + (v[1] - c[1]) * s, c[2] + (v[2] - c[2]) * s, c[3] + (v[3] - c[3]) * s }
end
local function ScaleHeadPrim(p)
    local s, c = M.HEAD_SCALE, HEAD_PIVOT
    local wx = M.HEAD_WIDEN
    for _, key in ipairs({ "c", "a", "b", "base", "anchor" }) do
        if p[key] then
            local v = ScaleAbout(p[key], c, s)
            v[1] = v[1] * wx
            p[key] = v
        end
    end
    if p.type == "ellipsoid" then p.r = { p.r[1] * s * wx, p.r[2] * s, p.r[3] * s }
    elseif p.type == "cone" then p.r = { p.r[1] * s, p.r[2] * s }
    elseif p.type == "box" then
        p.h = { p.h[1] * s * wx, p.h[2] * s, p.h[3] * s }
        if p.round then p.round = p.round * s end
    elseif p.type == "fin" then
        p.len, p.h = p.len * s, p.h * s
        if p.sweep then p.sweep = p.sweep * s end
        if p.thick then p.thick = p.thick * s end
    end
    if type(p.color) == "function" then
        local f = p.color
        p.color = function(x, y, z, pr)
            return f(c[1] + (x / wx - c[1]) / s, c[2] + (y - c[2]) / s, c[3] + (z - c[3]) / s, pr)
        end
    end
end
local headScaled = false

-- 未预处理的体块副本（不改动模块内的 PRIMS，可反复调用）
local function CopyRaw(p)
    local q = {}
    for k, v in pairs(p) do if not DERIVED[k] then q[k] = v end end
    return q
end
M.MirrorPrim = CopyPrim

---展开对称、施加头部缩放，返回未 Prepare 的体块（供型号变体再做形变）
---@return table prims, table bones
function M.ExpandRaw()
    if not headScaled then
        headScaled = true
        for _, p in ipairs(PRIMS) do
            if (p.bone == "head" or p.bone == "jaw") and not p.worldSpace then ScaleHeadPrim(p) end
        end
        for _, b in ipairs(M.BONES) do
            if b[1] == "jaw" then b[3] = ScaleAbout(b[3], HEAD_PIVOT, M.HEAD_SCALE) end
        end
    end
    local prims = {}
    for _, p in ipairs(PRIMS) do
        prims[#prims + 1] = CopyRaw(p)
        local mb = MirrorName(p.bone)
        if mb ~= nil then
            prims[#prims + 1] = CopyPrim(p, mb)
        elseif p.sym then
            prims[#prims + 1] = CopyPrim(p, p.bone)
        end
    end
    local bones = {}
    for _, b in ipairs(M.BONES) do
        bones[#bones + 1] = { name = b[1], parent = b[2], pivot = b[3] }
        local mb = MirrorName(b[1])
        if mb ~= nil then
            local mp = b[2] and (MirrorName(b[2]) or b[2]) or nil
            bones[#bones + 1] = { name = mb, parent = mp, pivot = MirrorVec(b[3]) }
        end
    end
    return prims, bones
end

---@return table prims, table bones
function M.Expand()
    local prims, bones = M.ExpandRaw()
    for i, p in ipairs(prims) do prims[i] = Sculpt.Prepare(p) end
    return prims, bones
end

-- 每根骨骼的体素尺寸
function M.VoxelSizeOf(bone)
    if bone == "head" or bone == "jaw" then return M.VOXEL_HEAD end
    return M.VOXEL_BODY
end

return M
