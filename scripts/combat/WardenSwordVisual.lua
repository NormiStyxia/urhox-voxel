-- Construct with New, call Step once per frame until it returns true.
-- Visibility requests made during upload take effect after both passes commit.
local V = {}
local source, batches
local materialRoot = 'model/forge-blades/'
local defaults = {
    primary = {.78,.84,.93}, secondary = {.84,.65,.36}, grip = {.12,.17,.31},
    amber = {1,.54,.075}, accent = {.08,.46,.92},
}

local function paletteColor(colors, presets, key)
    local preset = colors and presets[colors[key]]
    if preset then return Color(preset.rgb[1]/255, preset.rgb[2]/255, preset.rgb[3]/255, 1) end
    local c = defaults[key]
    return Color(c[1],c[2],c[3],1)
end

function V.Recolor(visual, colors)
    if not visual or visual.disposed then return end
    local presets = require('combat.WeaponCatalog').ColorPresets
    for _,key in ipairs({'primary','secondary','grip'}) do
        visual.material:SetShaderParameter(key..'_color',Variant(paletteColor(colors,presets,key)))
    end
    for _,key in ipairs({'accent','amber'}) do
        visual.crystal:SetShaderParameter(key..'_color',Variant(paletteColor(colors,presets,key)))
    end
end

function V.Dispose(visual)
    if not visual or visual.disposed then return end
    visual.disposed = true
    if visual.node then visual.node:Remove() end
    if visual.material then visual.material:Dispose() end
    if visual.crystal then visual.crystal:Dispose() end
end

local function cloneMaterial(name)
    local mat = assert(cache:GetResource('Material',materialRoot..name..'.xml'),'missing '..name)
    return assert(mat:Clone(name..'Instance'),'cannot clone '..name)
end

function V.IsCrystal(submask)
    return submask >= .75
end

function V.New(pivot,tipY,colors)
    local visual = {pass=1, index=1, visible=true}
    local ok,err = pcall(function()
        if not source then
            local data = require('combat.models.WardenSword')
            local groups = {{},{}}
            for t=1,data.triangles do
                local group = groups[V.IsCrystal(data.uv[(t-1)*6+1]/data.uvScale) and 2 or 1]
                group[#group+1] = t
            end
            source,batches = data,groups
        end
        visual.material = cloneMaterial('WardenSword')
        visual.crystal = cloneMaterial('WardenSwordCrystal')
        V.Recolor(visual,colors)
        visual.node = pivot:CreateChild('warden_sword_visual')
        visual.node.temporary = true
        visual.node.enabled = false
        local scale = tipY and tipY/source.sockets.tip[2] or 1
        visual.node.scale = Vector3(scale,scale,scale)
        visual.geometry = assert(visual.node:CreateComponent('CustomGeometry'))
        visual.geometry:SetNumGeometries(2)
        visual.geometry.castShadows = false
    end)
    if not ok then V.Dispose(visual); return nil,tostring(err) end
    return visual
end

local function uploadFace(geometry, t)
    local pos,col,uv = source.pos,source.col,source.uv
    local p,c,u = (t-1)*9,(t-1)*5,(t-1)*6
    local ab = Vector3(pos[p+4]-pos[p+1],pos[p+5]-pos[p+2],pos[p+6]-pos[p+3])
    local ac = Vector3(pos[p+7]-pos[p+1],pos[p+8]-pos[p+2],pos[p+9]-pos[p+3])
    local normal = ab:CrossProduct(ac):Normalized()
    local color = Color(col[c+1]/100,col[c+2]/100,col[c+3]/100,col[c+4]/100)
    for _=1,3 do
        geometry:DefineVertex(Vector3(pos[p+1]/source.scale,pos[p+2]/source.scale,pos[p+3]/source.scale))
        geometry:DefineNormal(normal)
        geometry:DefineColor(color)
        geometry:DefineTexCoord(Vector2(uv[u+1]/source.uvScale,uv[u+2]/source.uvScale))
        p,u = p+3,u+2
    end
end

local function advance(visual)
    local g = visual.geometry
    local batch = batches[visual.pass]
    if visual.index==1 then g:BeginGeometry(visual.pass-1,TRIANGLE_LIST) end
    local last = math.min(visual.index+47,#batch)
    for i=visual.index,last do uploadFace(g,batch[i]) end
    visual.index = last+1
    if last<#batch then return false end
    if visual.pass==1 then visual.pass,visual.index=2,1; return false end
    g:Commit()
    assert(g:SetMaterial(0,visual.material)~=false,'opaque binding failed')
    assert(g:SetMaterial(1,visual.crystal)~=false,'crystal binding failed')
    visual.complete = true
    visual.node.enabled = visual.visible
    return true
end

function V.Step(visual)
    if not visual or visual.disposed then return nil,'disposed' end
    if visual.complete then return true end
    local ok,result = pcall(advance,visual)
    if not ok then V.Dispose(visual); return nil,tostring(result) end
    return result
end

function V.SetVisible(visual,visible)
    if not visual or visual.disposed then return end
    visual.visible = visible
    if visual.complete then visual.node.enabled=visible end
end

return V
