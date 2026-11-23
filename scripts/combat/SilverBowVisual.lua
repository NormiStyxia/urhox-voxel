-- Silver bow geometry uses the same grip-local axes as ThornBow. The static string
-- can be hidden independently when the draw controller takes over the string.
local V = { ENABLED = true, STEP_VERTICES = 1200, PAD = .10, SCALE = 1.32 }
local cached
local function loadModel()
    if cached then return cached end
    local f = assert(cache:GetFile('model/forge-blades/SilverBow.mesh.json'), 'missing silver bow mesh')
    local ok, text = pcall(f.ReadString, f)
    f:Close()
    assert(ok, text)
    local m = cjson.decode(text)
    assert(m.name == 'silver_bow' and m.formatVersion == 1 and m.vertexStride == 13)
    assert(m.scale == 10000 and m.nscale == 1000 and m.uvScale == 10000 and m.height > 0)
    for _, name in ipairs({'body','crystal','string'}) do
        local p = m[name]
        assert(#p.v > 0 and #p.v % 13 == 0 and #p.i == p.triangles*3 and p.triangles > 0)
        for _, n in ipairs(p.v) do assert(math.type(n) and n % 1 == 0, 'invalid packed value') end
        for _, i in ipairs(p.i) do assert(i % 1 == 0 and i >= 1 and i*13 <= #p.v, 'invalid index') end
    end
    assert(m.sockets.stringZ < 0 and #m.bounds.min == 3 and #m.bounds.max == 3)
    cached = m
    return m
end

local function append(g, part, first, last)
    local v = part.v
    for k = first,last do
        local b = (part.i[k]-1)*13
        g:DefineVertex(Vector3(v[b+1]/10000,v[b+2]/10000,v[b+3]/10000))
        g:DefineNormal(Vector3(v[b+4]/1000,v[b+5]/1000,v[b+6]/1000))
        g:DefineColor(Color(v[b+7]/100,v[b+8]/100,v[b+9]/100,v[b+10]/100))
        g:DefineTexCoord(Vector2(v[b+12]/10000,v[b+13]/10000))
    end
end

function V.Dispose(v)
    if not v then return end
    if v.node then pcall(v.node.Remove,v.node); v.node=nil end
    for _,key in ipairs({'material','crystal'}) do
        if v[key] then pcall(v[key].Dispose,v[key]); v[key]=nil end
    end
end

local function clone(path,name)
    local m=assert(cache:GetResource('Material',path),'missing '..path)
    return assert(m:Clone(name),'failed to clone '..path)
end
local function geometry(node,mask,shadows)
    local g=assert(node:CreateComponent('CustomGeometry'))
    g.viewMask=mask; g.lightMask=mask; g.zoneMask=mask; g.castShadows=shadows
    return g
end
local function create(parent,scale,mask,shadows,shown)
    if not V.ENABLED then return nil,'disabled' end
    local v={cursor=1, phase=1, ready=false, shown=shown, scale=scale}
    local ok,err=pcall(function()
        local m=loadModel()
        v.material=clone('model/forge-blades/SilverBow.xml','SilverBowBody')
        v.crystal=clone('model/forge-blades/SilverBowCrystal.xml','SilverBowIce')
        v.node=parent:CreateChild('silver_bow_visual'); v.node.temporary=true
        v.node.scale=Vector3(scale,scale,scale); v.node.enabled=false
        v.geometry=geometry(v.node,mask,shadows); v.geometry:SetNumGeometries(2)
        v.stringNode=v.node:CreateChild('silver_bow_string'); v.stringNode.enabled=false
        v.stringGeometry=geometry(v.stringNode,mask,false)
        v.stringZ=m.sockets.stringZ*scale
        local lo,hi=math.huge,-math.huge
        for i=2,#m.string.v,13 do lo=math.min(lo,m.string.v[i]); hi=math.max(hi,m.string.v[i]) end
        v.stringHalf=(hi-lo)*scale/(2*m.scale)
    end)
    if not ok then V.Dispose(v);return nil,tostring(err) end
    return v
end
function V.SetVisible(v,show)
    if not (v and v.node) then return end
    v.shown=show==true
    v.node.enabled=v.ready and v.shown
    v.stringNode.enabled=v.ready and v.shown and not v.stringHidden
end
function V.Step(v)
    if not v or v.failed then return false end
    if v.ready then return true end
    local ok,err=pcall(function()
        local m=loadModel()
        local part=({m.body,m.crystal,m.string})[v.phase]
        local g=v.phase==3 and v.stringGeometry or v.geometry
        local slot=v.phase==2 and 1 or 0
        if v.cursor==1 then g:BeginGeometry(slot,TRIANGLE_LIST) end
        local last=math.min(#part.i,v.cursor+V.STEP_VERTICES-1)
        append(g,part,v.cursor,last)
        v.cursor=last+1
        if last==#part.i then
            if v.phase==2 then
                g:Commit(); assert(g:SetMaterial(0,v.material)~=false); assert(g:SetMaterial(1,v.crystal)~=false)
            elseif v.phase==3 then
                g:Commit(); assert(g:SetMaterial(0,v.material)~=false); v.ready=true; V.SetVisible(v,v.shown)
            end
            v.phase=v.phase+1;v.cursor=1
        end
    end)
    if not ok then V.Dispose(v);v.failed=tostring(err);return false end
    return v.ready
end
function V.New(pivot,halfHeight)
    local ok,m=pcall(loadModel)
    if not ok then return nil,tostring(m) end
    return create(pivot,(2*halfHeight+V.PAD)*V.SCALE/m.height,0xFFFFFFFF,false,false)
end
function V.BeginShowroom(parent,mask,low)
    local v,err=create(parent,1,mask,not low,true)
    if not v then return nil,err end
    return {silver=v,node=v.node,material=v.material,blueprint={bounds=loadModel().bounds},step=function(job)
        local done=V.Step(job.silver); assert(not job.silver.failed,job.silver.failed);return done
    end}
end
function V.DisposeShowroom(job)
    if job then V.Dispose(job.silver);job.silver=nil;job.material=nil end
end
function V.BackRotation() return Quaternion(35,90,0) end
function V.StringZ(v) return v and v.stringZ end
function V.StringHalf(v) return v and v.stringHalf end
function V.SetStringVisible(v,show)
    if v and v.stringNode then v.stringHidden=not show; V.SetVisible(v,v.shown) end
end
function V.SetAim(v,k)
    if v and v.node then local t=math.max(0,math.min(1,k));v.node.rotation=Quaternion(0,55*t,-16*t) end
end
function V.SetBend(v,meters)
    if v and v.material and v.lastBend~=meters then
        local bend=Variant(meters/v.scale);v.material:SetShaderParameter('bend',bend);v.crystal:SetShaderParameter('bend',bend);v.lastBend=meters
    end
end
-- Use the same forge palette indices as the other showroom weapons.
function V.Recolor(v,colors)
    if not (v and v.material and colors) then return end
    local paletteFor=require('combat.ForgeShowroomBlades').Palette
    local palette=paletteFor(colors)
    -- The stock palette leaves the authored lacquer exactly as shown in the showroom.
    -- A custom primary dye modulates the silver pigment underneath the neutral coat.
    local stock=paletteFor(require('combat.WeaponCatalog').Definitions.bow.colors).primary
    local dye=palette.primary
    v.material:SetShaderParameter('paint_tint',Variant(Vector3(dye[1]/stock[1],dye[2]/stock[2],dye[3]/stock[3])))
    for key,name in pairs({secondary='leaf_color',accent='crystal_color',grip='grip_color'}) do
        local c=palette[key];local mat=key=='accent' and v.crystal or v.material
        if c then mat:SetShaderParameter(name,Variant(Color(c[1],c[2],c[3],1))) end
    end
end
return V
