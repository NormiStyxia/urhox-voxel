-- Offline resource-cache double. The decoder supports the generated mesh's JSON
-- subset (objects, arrays, unescaped strings, numbers), not arbitrary JSON.
-- Production uses the engine's cjson; no test parser ships in scripts/.
local M={}

function M.Decode(raw)
    local pos=1
    local function Skip()
        local _,last=raw:find('^%s*',pos)
        pos=(last or pos-1)+1
    end
    local function Take(token)
        Skip()
        if raw:sub(pos,pos)==token then pos=pos+1;return true end
        return false
    end
    local function String()
        assert(Take('"'),'expected string')
        local last=assert(raw:find('"',pos,true),'unterminated string')
        local value=raw:sub(pos,last-1)
        assert(not value:find(string.char(92),1,true),'escaped strings outside mesh test subset')
        pos=last+1
        return value
    end
    local Value
    Value=function()
        Skip()
        if Take('{') then
            local result={}
            if Take('}') then return result end
            repeat
                local key=String();assert(Take(':'))
                result[key]=Value()
                if Take('}') then return result end
            until not Take(',')
            error('invalid object')
        elseif Take('[') then
            local result={}
            if Take(']') then return result end
            repeat
                result[#result+1]=Value()
                if Take(']') then return result end
            until not Take(',')
            error('invalid array')
        elseif raw:sub(pos,pos)=='"' then
            return String()
        end
        local token=assert(raw:match('^%-?%d+%.?%d*[eE]?[+-]?%d*',pos),'expected number')
        pos=pos+#token
        return assert(tonumber(token),'invalid number')
    end
    local value=Value();Skip()
    assert(pos>#raw,'trailing data')
    return value
end

function M.GetFile(_,path)
    assert(path=='model/forge-blades/ThornBow.mesh.json','unexpected mesh resource')
    if rawget(_G,'THORN_MESH_MISSING') then return nil end
    local file=io.open('assets/'..path,'rb')
    if not file then return nil end
    return {ReadString=function() return file:read('*a') end,
        Close=function() file:close() end}
end

return M
