-- In-hand / on-back visual for the generated wing sword (tools: art/weapon_gen/wingsword.py).
-- Visual only: hit geometry, sockets, trails and timing still come from the voxel blueprint.
-- Any failure returns nil so WeaponRig keeps showing the voxel sword.
local Blades=require('combat.ForgeShowroomBlades')
local V={}
V.ENABLED=true            -- kill switch: false = always show the voxel sword
V.WIDTH,V.DEPTH=1.3,1.25  -- visual-only thickening; length is fitted to the voxel blade tip
local MATERIAL='model/forge-blades/WingSword.xml'
local CRYSTAL='model/forge-blades/WingSwordCrystal.xml'
-- Sheath/draw projection: the blade turns into this hologram, then breaks apart.
local HOLO='model/forge-blades/WingSwordHolo.xml'
local MASK=0xFFFFFFFF
-- Same masks as WingSword.shader cw: core/gem glow bands and the .6r/.4b shoulder.
local function IsCrystal(v)
    return v.glow>=.30 or (v.c[3]>=.32 and v.c[3]<.80 and v.c[1]>=.5)
end
V.IsCrystal=IsCrystal
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
        local data=Blades.Data()
        local source=assert(cache:GetResource('Material',MATERIAL),'wing material unavailable')
        visual.material=assert(source:Clone('WingSwordHand'),'wing material clone failed')
        Tint(visual.material,colors)
        visual.material:SetShaderParameter('flow_strength',Variant(.7))
        -- Translucent sapphire inset; missing material keeps the opaque look.
        local crystal=cache:GetResource('Material',CRYSTAL)
        visual.crystal=crystal and crystal:Clone('WingSwordCrystalHand') or nil
        if visual.crystal then Tint(visual.crystal,colors) end
        local node=pivot:CreateChild('wing_sword_visual')
        node.temporary=true
        visual.node=node
        local s=tipY/data.sockets.tip[2]
        node.scale=Vector3(s*V.WIDTH,s,s*V.DEPTH)
        local g=assert(node:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
        visual.geometry=g
        g.viewMask=MASK;g.lightMask=MASK;g.zoneMask=MASK;g.castShadows=false
        local span=data.uvHeight
        local vertices=data.vertices
        -- Geometry 0 = opaque metal/edges/grip, 1 = translucent crystal triangles.
        g:SetNumGeometries(visual.crystal and 2 or 1)
        for index=0,visual.crystal and 1 or 0 do
            g:BeginGeometry(index,TRIANGLE_LIST)
            for i=1,#vertices,3 do
                if not visual.crystal or IsCrystal(vertices[i])==(index==1) then
                    for j=i,i+2 do
                        local v=vertices[j]
                        g:DefineVertex(Vector3(v.p[1],v.p[2],v.p[3]))
                        g:DefineNormal(Vector3(v.n[1],v.n[2],v.n[3]))
                        g:DefineColor(Color(v.c[1],v.c[2],v.c[3],v.shade))
                        g:DefineTexCoord(Vector2(v.glow,(v.p[2]-data.uvBase)/span))
                    end
                end
            end
        end
        g:Commit()
        assert(g:SetMaterial(0,visual.material)~=false,'wing material binding failed')
        if visual.crystal then assert(g:SetMaterial(1,visual.crystal)~=false,'crystal material binding failed') end
        node.enabled=false
        -- Hologram twin (all triangles, one unlit additive material). Optional:
        -- without it the rig falls back to the plain show/hide.
        local holo=cache:GetResource('Material',HOLO)
        visual.holoMaterial=holo and holo:Clone('WingSwordHoloHand') or nil
        if visual.holoMaterial then
            Tint(visual.holoMaterial,colors)
            local holoNode=pivot:CreateChild('wing_sword_holo')
            holoNode.temporary=true
            holoNode.scale=node.scale
            local h=assert(holoNode:CreateComponent('CustomGeometry'),'CustomGeometry unavailable')
            h.viewMask=MASK;h.lightMask=MASK;h.zoneMask=MASK;h.castShadows=false
            h:BeginGeometry(0,TRIANGLE_LIST)
            for _,v in ipairs(vertices) do
                h:DefineVertex(Vector3(v.p[1],v.p[2],v.p[3]))
                h:DefineNormal(Vector3(v.n[1],v.n[2],v.n[3]))
                h:DefineTexCoord(Vector2(v.glow,(v.p[2]-data.uvBase)/span))
            end
            h:Commit()
            assert(h:SetMaterial(0,visual.holoMaterial)~=false,'holo material binding failed')
            holoNode.enabled=false
            visual.holoNode=holoNode
            visual.holo,visual.cut=-1,-1
        end
    end)
    if not ok then
        V.Dispose(visual)
        return nil,tostring(err)
    end
    return visual
end
---@param visual table?
---@param colors table?
function V.Recolor(visual,colors,deferred)
    if not visual or not visual.material then return end
    if visual.holoMaterial then pcall(Tint,visual.holoMaterial,colors) end
    local material,crystal
    local ok,err=pcall(function()
        material=assert(visual.material:Clone('WingSwordTint'))
        Tint(material,colors)
        if visual.crystal then crystal=assert(visual.crystal:Clone('WingCrystalTint'));Tint(crystal,colors) end
        assert(visual.geometry:SetMaterial(0,material)~=false,'wing tint binding failed')
        if crystal then assert(visual.geometry:SetMaterial(1,crystal)~=false,'crystal tint binding failed') end
    end)
    if not ok then
        pcall(visual.geometry.SetMaterial,visual.geometry,0,visual.material)
        if visual.crystal then pcall(visual.geometry.SetMaterial,visual.geometry,1,visual.crystal) end
        if material then material:Dispose() end
        if crystal then crystal:Dispose() end
        error(err)
    end
    local oldMaterial,oldCrystal=visual.material,visual.crystal
    local finished=false
    local transaction={}
    function transaction.Commit()
        if finished then return end
        finished=true
        pcall(oldMaterial.Dispose,oldMaterial)
        if oldCrystal then pcall(oldCrystal.Dispose,oldCrystal) end
    end
    function transaction.Rollback()
        if finished then return end
        -- Restore existing handles: rollback must not depend on another Clone.
        visual.geometry:SetMaterial(0,oldMaterial)
        if oldCrystal then visual.geometry:SetMaterial(1,oldCrystal) end
        visual.material,visual.crystal=oldMaterial,oldCrystal
        finished=true
        pcall(material.Dispose,material)
        if crystal then pcall(crystal.Dispose,crystal) end
    end
    visual.material,visual.crystal=material,crystal
    if not deferred then transaction.Commit() end
    return transaction
end
function V.SetGrade(visual,grade)
    if not visual or visual.grade==grade then return end
    visual.grade=grade
    visual.material:SetShaderParameter('blade_emit',Variant(({.01,.09,.2})[grade]))
    visual.material:SetShaderParameter('gold_metal',Variant(({.05,.2,.35})[grade]))
    visual.material:SetShaderParameter('crystal_amt',Variant(({0,.55,1})[grade]))
    if visual.crystal then
        visual.crystal:SetShaderParameter('crystal_alpha',Variant(({.94,.68,.42})[grade]))
        visual.crystal:SetShaderParameter('inner_glow',Variant(({0,.2,.55})[grade]))
    end
end

--- Swing charge 0..1 brightens the crystal interior (cached to avoid per-frame Variants).
---@param visual table?
---@param k number
function V.SetCharge(visual,k)
    if not visual or not visual.crystal then return end
    local q=math.floor(math.max(0,math.min(1,k))*16+.5)
    if visual.chargeStep==q then return end
    visual.chargeStep=q
    V.chargeValues=V.chargeValues or {}
    local value=V.chargeValues[q]
    if not value then value=Variant(q/16);V.chargeValues[q]=value end
    visual.crystal:SetShaderParameter('charge',value)
end
V.holoValues={}
---@param x number
---@return integer
local function Step(x) return math.floor(math.max(0,math.min(1,x))*32+.5) end
---@param q integer
local function StepValue(q)
    local value=V.holoValues[q]
    if not value then value=Variant(q/32);V.holoValues[q]=value end
    return value
end
---@param visual table?
---@return boolean
function V.HasHolo(visual) return visual~=nil and visual.holoNode~=nil end
--- Projection layer: holo = brightness 0..1, cut = dissolve front 0..1 (1 = gone).
--- Quantized to 1/32 with cached Variants; no allocation once warmed up.
---@param visual table?
---@param holo number
---@param cut number
function V.SetHolo(visual,holo,cut)
    if not visual or not visual.holoNode then return end
    local h,c=Step(holo),Step(cut)
    local on=h>0 and c<32
    if visual.holoNode.enabled~=on then visual.holoNode.enabled=on end
    if not on then return end
    if visual.holo~=h then visual.holo=h;visual.holoMaterial:SetShaderParameter('holo',StepValue(h)) end
    if visual.cut~=c then visual.cut=c;visual.holoMaterial:SetShaderParameter('cut',StepValue(c)) end
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
    if visual.crystal then pcall(visual.crystal.Dispose,visual.crystal);visual.crystal=nil end
    if visual.holoNode then pcall(visual.holoNode.Remove,visual.holoNode);visual.holoNode=nil end
    if visual.holoMaterial then pcall(visual.holoMaterial.Dispose,visual.holoMaterial);visual.holoMaterial=nil end
end
return V
