-- In-hand / on-back visual for the generated wing sword (tools: art/weapon_gen/wingsword.py).
-- Visual only: hit geometry, sockets, trails and timing still come from the voxel blueprint.
-- Any failure returns nil so WeaponRig keeps showing the voxel sword.
local Blades=require('combat.ForgeShowroomBlades')
local V={}
V.ENABLED=true            -- kill switch: false = always show the voxel sword
V.WIDTH,V.DEPTH=1.3,1.25  -- visual-only thickening; length is fitted to the voxel blade tip
local MATERIAL='model/forge-blades/WingSword.xml'
local MASK=0xFFFFFFFF
---@param material Material
---@param colors table?
local function Tint(material,colors)
    for key,c in pairs(Blades.Palette(colors)) do
        material:SetShaderParameter(key..'_color',Variant(Color(c[1],c[2],c[3],1)))
    end
end
---@param pivot Node weapon_grip_sword pivot (hand/back follow it)
---@param tipY number voxel blade tip height in pivot space (metres, already visually scaled)
---@param colors table? {primary,secondary,accent[,grip]} palette indices
---@return table? visual
---@return string? err
function V.New(pivot,tipY,colors)
    if not V.ENABLED then return nil,'disabled' end
    local visual={}
    local ok,err=pcall(function()
        local data=Blades.Data('W')
        local source=assert(cache:GetResource('Material',MATERIAL),'wing material unavailable')
        visual.material=assert(source:Clone('WingSwordHand'),'wing material clone failed')
        Tint(visual.material,colors)
        visual.material:SetShaderParameter('flow_strength',Variant(.7))
        local node=pivot:CreateChild('wing_sword_visual')
        node.temporary=true
        visual.node=node
        local s=tipY/data.sockets.tip[2]
        node.scale=Vector3(s*V.WIDTH,s,s*V.DEPTH)
        local g=assert(node:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
        g.viewMask=MASK;g.lightMask=MASK;g.zoneMask=MASK;g.castShadows=false
        g:BeginGeometry(0,TRIANGLE_LIST)
        local span=data.uvHeight
        for _,v in ipairs(data.vertices) do
            g:DefineVertex(Vector3(v.p[1],v.p[2],v.p[3]))
            g:DefineNormal(Vector3(v.n[1],v.n[2],v.n[3]))
            g:DefineColor(Color(v.c[1],v.c[2],v.c[3],v.shade))
            g:DefineTexCoord(Vector2(v.glow,(v.p[2]-data.uvBase)/span))
        end
        g:Commit()
        assert(g:SetMaterial(0,visual.material)~=false,'wing material binding failed')
        node.enabled=false
    end)
    if not ok then
        V.Dispose(visual)
        return nil,tostring(err)
    end
    return visual
end
---@param visual table?
---@param colors table?
function V.Recolor(visual,colors)
    if visual and visual.material then pcall(Tint,visual.material,colors) end
end
---@param visual table?
---@param visible boolean
function V.SetVisible(visual,visible)
    if visual and visual.node and visual.node.enabled~=visible then visual.node.enabled=visible end
end
---@param visual table?
function V.Dispose(visual)
    if not visual then return end
    if visual.node then pcall(visual.node.Remove,visual.node);visual.node=nil end
    if visual.material then pcall(visual.material.Dispose,visual.material);visual.material=nil end
end
return V
