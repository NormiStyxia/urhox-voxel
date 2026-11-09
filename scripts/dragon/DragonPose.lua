-- ====================================================================
-- DragonPose.lua — 姿态表：关节名 → {x, y, z} 欧拉角（度），可混合、叠加、镜像
--
-- 约定：
--   * 关节旋转 = Rz * Ry * Rx（DragonRig.Euler），相对静止姿态（静止 = 单位旋转）。
--   * 左右对称关节用 SetSym 写右侧，左侧自动取 (x, -y, -z)。
--   * 指骨第二节 wfNm：x = 指尖下弯（出翼平面，绕指骨的平面内法线），
--     y = 翼平面内折叠（收翼时远端指节向后下折）；左翼由右翼四元数镜像，左右写同一个值。
--   * pose.body = { x, y, z, dx, dy, dz }：身体姿态层（相对 COM 的俯仰/偏航/侧倾 + 位移）
-- ====================================================================

local Rig = require("dragon.DragonRig")

local M = {}

---@return {j: table<string, number[]>, body: number[]}
function M.New()
    ---@type number[]
    local body = { 0, 0, 0, 0, 0, 0 }
    return { j = {}, body = body }
end

---@param pose table
---@param name string
function M.Set(pose, name, x, y, z)
    pose.j[name] = { x or 0, y or 0, z or 0 }
end

-- 左右对称写入：base 不带后缀
function M.SetSym(pose, base, x, y, z)
    x, y, z = x or 0, y or 0, z or 0
    pose.j[base .. "_R"] = { x, y, z }
    pose.j[base .. "_L"] = { x, -y, -z }
end

-- 单侧写入并自动镜像符号：side = "_R" / "_L"
function M.SetSide(pose, base, side, x, y, z)
    x, y, z = x or 0, y or 0, z or 0
    if side == "_L" then y, z = -y, -z end
    pose.j[base .. side] = { x, y, z }
end

-- 身体姿态层：俯仰 / 偏航 / 侧倾（度）+ 位移（米）
function M.SetBody(pose, x, y, z, dx, dy, dz)
    local b = pose.body
    b[1], b[2], b[3], b[4], b[5], b[6] = x or 0, y or 0, z or 0, dx or 0, dy or 0, dz or 0
end

function M.Get(pose, name)
    return pose.j[name]
end

-- 在已有值上叠加
function M.AddTo(pose, name, x, y, z)
    local e = pose.j[name]
    if e == nil then
        pose.j[name] = { x or 0, y or 0, z or 0 }
    else
        e[1], e[2], e[3] = e[1] + (x or 0), e[2] + (y or 0), e[3] + (z or 0)
    end
end

function M.AddSym(pose, base, x, y, z)
    M.AddTo(pose, base .. "_R", x, y, z)
    M.AddTo(pose, base .. "_L", x, -(y or 0), -(z or 0))
end

function M.Copy(p)
    local q = M.New()
    for k, v in pairs(p.j) do q.j[k] = { v[1], v[2], v[3] } end
    for i = 1, 6 do q.body[i] = p.body[i] end
    return q
end

-- 线性混合：out = a*(1-t) + b*t（缺省关节视为 0）
function M.Blend(a, b, t, out)
    out = out or M.New()
    local s = 1.0 - t
    for k, v in pairs(a.j) do
        local w = b.j[k]
        if w ~= nil then
            out.j[k] = { v[1] * s + w[1] * t, v[2] * s + w[2] * t, v[3] * s + w[3] * t }
        else
            out.j[k] = { v[1] * s, v[2] * s, v[3] * s }
        end
    end
    for k, w in pairs(b.j) do
        if a.j[k] == nil then out.j[k] = { w[1] * t, w[2] * t, w[3] * t } end
    end
    for i = 1, 6 do out.body[i] = a.body[i] * s + b.body[i] * t end
    return out
end

-- 加权累加（多状态混合用）：acc += p * w
function M.Accumulate(acc, p, w)
    for k, v in pairs(p.j) do
        local e = acc.j[k]
        if e == nil then
            acc.j[k] = { v[1] * w, v[2] * w, v[3] * w }
        else
            e[1], e[2], e[3] = e[1] + v[1] * w, e[2] + v[2] * w, e[3] + v[3] * w
        end
    end
    for i = 1, 6 do acc.body[i] = acc.body[i] + p.body[i] * w end
    return acc
end

-- 把姿态写入骨架节点（不处理 IK）。scale：整体幅度系数（关节测试用 1）
---@param rig DragonRig
function M.Apply(rig, pose)
    local curl = rig.curlAxis
    for name, node in pairs(rig.bones) do
        if name:sub(1, 2) ~= "wm" then
            local e = pose.j[name]
            if e == nil then
                node.rotation = Quaternion()
            elseif curl[name] ~= nil then
                local c = curl[name]
                local q = Quaternion(e[2], Vector3.UP) * Quaternion(-e[1], c.axis)
                if c.mirror then q = Rig.MirrorQuat(q) end
                node.rotation = q
            else
                node.rotation = Rig.Euler(e[1], e[2], e[3])
            end
        end
    end
    local b = pose.body
    rig.body.rotation = Rig.Euler(b[1], b[2], b[3])
    rig.body.position = rig.restPos.body + Vector3(b[4], b[5], b[6])
end

return M
