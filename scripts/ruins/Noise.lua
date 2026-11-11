-- ====================================================================
-- Noise.lua — 确定性哈希 / 值噪声 / fbm（地形、风化、随机配色共用）
-- ====================================================================

local M = {}

local floor = math.floor

-- 整数哈希 → [0,1)
function M.Hash3(x, y, z)
    local h = (x * 374761393 + y * 668265263 + z * 2147483647) & 0x7fffffff
    h = ((h ~ (h >> 13)) * 1274126177) & 0x7fffffff
    h = h ~ (h >> 16)
    return (h & 0xffffff) / 16777216.0
end
local Hash3 = M.Hash3

function M.Hash2(x, y) return Hash3(x, y, 1013) end
local Hash2 = M.Hash2

local function Fade(t) return t * t * (3 - 2 * t) end

-- 2D 值噪声，输出 [0,1)
function M.Value2(x, y, seed)
    seed = seed or 0
    local xi, yi = floor(x), floor(y)
    local xf, yf = x - xi, y - yi
    local a = Hash3(xi, yi, seed)
    local b = Hash3(xi + 1, yi, seed)
    local c = Hash3(xi, yi + 1, seed)
    local d = Hash3(xi + 1, yi + 1, seed)
    local u, v = Fade(xf), Fade(yf)
    return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
end
local Value2 = M.Value2

-- 3D 值噪声 [0,1)
function M.Value3(x, y, z, seed)
    seed = seed or 0
    local xi, yi, zi = floor(x), floor(y), floor(z)
    local xf, yf, zf = Fade(x - xi), Fade(y - yi), Fade(z - zi)
    local function L(a, b, t) return a + (b - a) * t end
    local s = seed * 7919
    local c000 = Hash3(xi, yi, zi + s)
    local c100 = Hash3(xi + 1, yi, zi + s)
    local c010 = Hash3(xi, yi + 1, zi + s)
    local c110 = Hash3(xi + 1, yi + 1, zi + s)
    local c001 = Hash3(xi, yi, zi + 1 + s)
    local c101 = Hash3(xi + 1, yi, zi + 1 + s)
    local c011 = Hash3(xi, yi + 1, zi + 1 + s)
    local c111 = Hash3(xi + 1, yi + 1, zi + 1 + s)
    return L(L(L(c000, c100, xf), L(c010, c110, xf), yf), L(L(c001, c101, xf), L(c011, c111, xf), yf), zf)
end

-- fbm：octaves 层叠，输出约 [0,1)
function M.Fbm2(x, y, octaves, seed)
    local sum, amp, norm, f = 0.0, 1.0, 0.0, 1.0
    for o = 1, octaves or 4 do
        sum = sum + Value2(x * f, y * f, (seed or 0) + o * 31) * amp
        norm = norm + amp
        amp = amp * 0.5
        f = f * 2.0
    end
    return sum / norm
end

-- 浮点坐标的格哈希（随机配色用）
function M.HashF(x, y, z)
    return Hash3(floor(x * 4.0), floor(y * 4.0), floor(z * 4.0))
end

-- 简单可复现随机数生成器（每个对象独立的种子流）
---@class NoiseRng
local Rng = {}
Rng.__index = Rng
function M.Rng(seed)
    return setmetatable({ s = (seed or 1) & 0x7fffffff }, Rng)
end
function Rng:Next()
    self.s = (self.s * 1103515245 + 12345) & 0x7fffffff
    return (self.s >> 8) / 8388608.0
end
function Rng:Range(a, b) return a + (b - a) * self:Next() end
function Rng:Int(a, b) return a + floor(self:Next() * (b - a + 1)) end

return M
