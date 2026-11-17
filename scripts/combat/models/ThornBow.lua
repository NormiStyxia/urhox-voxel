-- Runtime asset boundary for the thorn-flower bow. Mesh data is generated JSON;
-- rendering, bend animation and back-slung orientation live in ThornBowVisual.
local M={}
local RESOURCE='model/forge-blades/ThornBow.mesh.json'
---@type table?
local cached

local function Finite(value)
    return type(value)=='number' and value==value and math.abs(value)<math.huge
end

local function Vector(value)
    return type(value)=='table' and #value==3
        and Finite(value[1]) and Finite(value[2]) and Finite(value[3])
end

local function CheckPart(part,stride)
    assert(type(part)=='table' and Finite(part.triangles)
        and part.triangles>0 and part.triangles%1==0,'invalid triangle count')
    assert(type(part.v)=='table' and #part.v>0 and #part.v%stride==0,'invalid vertex buffer')
    assert(type(part.i)=='table' and #part.i==part.triangles*3,'invalid index buffer')
    for _,value in ipairs(part.v) do
        assert(Finite(value) and value%1==0,'invalid packed vertex')
    end
    local count=#part.v/stride
    for _,index in ipairs(part.i) do
        assert(Finite(index) and index%1==0 and index>=1 and index<=count,'vertex index out of bounds')
    end
end

local function Validate(model)
    assert(type(model)=='table' and model.formatVersion==1
        and model.vertexStride==11 and model.name=='thorn_bow','unsupported thorn bow format')
    assert(model.scale==10000 and model.nscale==1000,'unsupported thorn bow quantization')
    assert(Finite(model.height) and model.height>0,'invalid thorn bow height')
    assert(type(model.bounds)=='table' and Vector(model.bounds.min) and Vector(model.bounds.max),'invalid bounds')
    for axis=1,3 do assert(model.bounds.min[axis]<=model.bounds.max[axis],'inverted bounds') end
    local sockets=model.sockets
    assert(type(sockets)=='table' and Vector(sockets.grip) and Vector(sockets.top)
        and Vector(sockets.bottom) and Finite(sockets.stringZ) and Finite(sockets.crystalTip),'invalid sockets')
    CheckPart(model.body,model.vertexStride)
    CheckPart(model.crystal,model.vertexStride)
    CheckPart(model.string,model.vertexStride)
    return model
end

--- Decode and validate once; callers share the read-only mesh tables.
--- Errors propagate to ThornBowVisual's guarded creation and existing voxel fallback.
---@return table
function M.Load()
    if cached then return cached end
    local file=assert(cache:GetFile(RESOURCE),'missing thorn bow mesh: '..RESOURCE)
    local ok,raw=pcall(file.ReadString,file)
    file:Close()
    assert(ok,raw)
    local decoded=cjson.decode(raw)
    cached=Validate(decoded) -- failed loads never poison the cache; later attempts can retry
    return cached
end

return M
