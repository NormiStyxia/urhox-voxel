-- W6: Submit the actual ordinary-breath shader variants on quiet frames.
-- Loading a Material alone (or disabling its Drawable) does not compile a PSO.
-- No gameplay particles, raycasts, damage, hit callbacks or camera changes.
local M = {}
---@class DragonShaderWarmup
---@field root Node
---@field ribbon Node
---@field motes BillboardSet
---@field ring Node|nil
---@field node Node|nil
---@field drawable Drawable|nil
---@field stage integer
---@field idle number
---@field frames integer
local W = {}; W.__index = W

---@param root Node
---@param ribbon Node
---@param motes BillboardSet
---@param ring Node|nil
---@return DragonShaderWarmup
function M.New(root, ribbon, motes, ring)
    return setmetatable({root=root, ribbon=ribbon, motes=motes, ring=ring,
        stage=1, idle=0, frames=0}, W)
end

function W:ClearProxy()
    if self.node then self.node:Remove() end
    self.node, self.drawable = nil, nil
    self.frames = 0
end

function W:CreateProxy()
    if self.stage == 2 then
        local node = self.root:CreateChild('DragonWarmupMote')
        local bb = node:CreateComponent('BillboardSet')
        bb:SetMaterial(self.motes:GetMaterial())
        bb:SetRelative(true); bb:SetSorted(false); bb:SetNumBillboards(1)
        local b = bb:GetBillboard(0)
        b.position = Vector3.ZERO; b.size = Vector2(.01, .01)
        -- VoxelFX.Texture supplies a transparent guard texel at (0,0).
        -- Keep the real BILLBOARD variant, but no color/depth pixels survive.
        b.uv = Rect(0, 0, 0, 0); b.color = Color(0, 0, 0, 0)
        b.enabled = true; bb:Commit()
        self.node, self.drawable = node, bb
    else
        local source = self.stage == 1 and self.ribbon or self.ring
        if not source then self.stage = 4; return end
        local node = source:Clone(LOCAL)
        node:SetParent(self.root)
        node.name = 'DragonWarmupMesh'
        local geom = node:GetComponent('CustomGeometry') --[[@as CustomGeometry]]
        local mat = geom:GetMaterial(0):Clone()
        if self.stage == 1 then
            mat:SetShaderParameter('strength', Variant(0.0))
        else
            mat:SetShaderParameter('alpha_scale', Variant(0.0))
        end
        geom:SetMaterial(mat)
        self.node, self.drawable = node, geom
    end
    self.drawable.castShadows = false
    self.drawable.occluder = false
    self.drawable.occludee = false
    self.node.temporary = true
    self.node.enabled = false
end

---@param dt number
---@param busy boolean
function W:Update(dt, busy)
    if self.stage > 3 then return end
    if busy or dt <= 0 or dt > .05 then
        if self.node then self.node.enabled = false end
        self.idle = 0
        return
    end
    self.idle = self.idle + dt
    if self.idle < .75 then return end
    local viewport = renderer:GetViewportForScene(self.root.scene, 0)
    local camera = viewport and viewport.camera
    if not camera or not camera.node then return end
    if self.node and self.node.enabled and self.frames >= 2 and self.drawable.inView then
        -- Visibility confirms submission opportunity, not backend compile success.
        self:ClearProxy()
        self.stage = self.stage + 1
        self.idle = 0
        return
    end
    if not self.node then self:CreateProxy() end
    if not self.node then return end
    -- In-frustum, non-degenerate geometry: offscreen/zero-scale nodes may be culled.
    local cn = camera.node
    self.node.worldPosition = cn.worldPosition + cn.worldDirection * math.max(1, camera.nearClip * 2)
    self.node.worldRotation = cn.worldRotation
    self.node.scale = self.stage == 2 and Vector3.ONE or Vector3(.02, .02, .02)
    self.node.enabled = true
    self.frames = self.frames + 1
    if self.frames >= 120 then
        self:ClearProxy()
        self.stage = 4
        print('DragonShaderWarmup: no visible draw confirmed; first-use compilation may remain')
    end
end

function W:Destroy()
    self:ClearProxy()
    self.stage = 4
end
return M
