-- New/Begin allocates an opaque iron sword. Call Step once per frame until true.
-- A nil result from New or Step signals that the caller should keep its fallback.
local Visual = {}
local resource = 'model/forge-blades/IronSword.xml'
local defaults = {primary={.84,.89,.96}, secondary={.72,.78,.86}, grip={.15,.25,.43}}

---@param material Material
---@param colors table? Forge palette indices, keyed by primary, secondary and grip.
local function tint(material, colors)
    local presets = colors and require('combat.WeaponCatalog').ColorPresets
    for name, base in pairs(defaults) do
        local preset = presets and presets[colors[name]]
        local r,g,b = base[1],base[2],base[3]
        if preset then
            r,g,b = preset.rgb[1]/255,preset.rgb[2]/255,preset.rgb[3]/255
        end
        material:SetShaderParameter(name..'_color', Variant(Color(r,g,b,1)))
    end
end

function Visual.Dispose(v)
    if not v then return end
    if v.node then v.node:Remove() end
    if v.material then v.material:Dispose() end
    v.node,v.geometry,v.material,v.data = nil,nil,nil,nil
end

---@param parent Node
---@param tipY number? Model-space tip height after fitting, in metres.
---@param colors table?
function Visual.New(parent,tipY,colors)
    local v = {cursor=1,ready=false,visible=true}
    local ok,err = pcall(function()
        v.data = require('combat.models.IronSword')
        local source = assert(cache:GetResource('Material',resource),'missing IronSword material')
        v.material = assert(source:Clone('IronSwordHand'),'IronSword clone failed')
        tint(v.material,colors)
        v.node = parent:CreateChild('iron_sword_visual')
        v.node.temporary,v.node.enabled = true,false
        local scale = tipY and tipY/v.data.sockets.tip[2] or 1
        v.node.scale = Vector3(scale,scale,scale)
        v.geometry = assert(v.node:CreateComponent('CustomGeometry'))
        v.geometry.castShadows = true
        -- Both submasks (body and inset) are opaque and share the same BRDF.
        v.geometry:SetNumGeometries(1)
        v.geometry:BeginGeometry(0,TRIANGLE_LIST)
    end)
    if not ok then Visual.Dispose(v); return nil,tostring(err) end
    return v
end
Visual.Begin = Visual.New

local function upload(v)
    local m,g = v.data,v.geometry
    local last = math.min(v.cursor+31,m.triangles)
    for t=v.cursor,last do
        local pb,ub,cb = (t-1)*9,(t-1)*6,(t-1)*5
        local p = m.pos
        local color = Color(m.col[cb+1]/100,m.col[cb+2]/100,m.col[cb+3]/100,m.col[cb+4]/100)
        for i=0,2 do
            local j,k = pb+i*3,ub+i*2
            g:DefineVertex(Vector3(p[j+1]/m.scale,p[j+2]/m.scale,p[j+3]/m.scale))
            g:DefineNormal(Vector3(m.nrm[j+1]/m.scale,m.nrm[j+2]/m.scale,m.nrm[j+3]/m.scale))
            g:DefineColor(color)
            g:DefineTexCoord(Vector2(m.uv[k+1]/m.scale,m.uv[k+2]/m.scale))
        end
    end
    v.cursor = last+1
    if last < m.triangles then return false end
    g:Commit()
    assert(g:SetMaterial(0,v.material)~=false,'IronSword material binding failed')
    v.ready,v.node.enabled = true,v.visible
    return true
end

function Visual.Step(v)
    if not v or not v.node then return nil,'disposed iron sword' end
    if v.ready then return true end
    local ok,result = pcall(upload,v)
    if ok then return result end
    Visual.Dispose(v)
    return nil,tostring(result)
end

function Visual.SetVisible(v,visible)
    if v and v.node then
        v.visible = visible
        v.node.enabled = v.ready and visible
    end
end

function Visual.Recolor(v,colors)
    if not v or not v.material then return nil,'disposed iron sword' end
    local replacement
    local ok,err = pcall(function()
        replacement = assert(v.material:Clone('IronSwordTint'))
        tint(replacement,colors)
        if v.ready then assert(v.geometry:SetMaterial(0,replacement)~=false) end
    end)
    if not ok then
        if replacement then replacement:Dispose() end
        return nil,tostring(err)
    end
    local old = v.material
    v.material = replacement
    old:Dispose()
    return true
end
return Visual
