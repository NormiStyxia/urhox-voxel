-- Asset loading/cache/failure contracts; no engine executable or rendered pixels.
package.path='scripts/?.lua;tests/combat/?.lua;'..package.path
local Mock=require('weapon_mock')
local Assets=require('asset_mock')
local realDecode=cjson.decode
local reads,closes=0,0
local raw='{}'
local missing,readFailure=false,false
cache.GetFile=function(_,path)
    assert(path=='model/forge-blades/ThornBow.mesh.json')
    reads=reads+1
    if missing then return nil end
    return {
        ReadString=function() if readFailure then error('read failure') end;return raw end,
        Close=function() closes=closes+1 end,
    }
end
local function Fresh() return assert(loadfile('scripts/combat/models/ThornBow.lua'))() end

local file=assert(io.open('assets/model/forge-blades/ThornBow.mesh.json','rb'))
raw=file:read('*a');file:close()
local loader=Fresh()
local model=loader.Load()
assert(loader.Load()==model and reads==1 and closes==1,'successful mesh is cached')

local function RejectThenRecover(fault)
    local candidate=Fresh()
    local before=closes
    cjson.decode=function(text)
        local data=realDecode(text)
        fault(data)
        return data
    end
    assert(not pcall(candidate.Load),'bad asset must be rejected')
    assert(closes==before+1,'file must close before parsing/validation')
    cjson.decode=realDecode
    assert(candidate.Load().body.triangles==6320,'failed load must allow retry')
end
RejectThenRecover(function() error('invalid JSON') end)
RejectThenRecover(function(data) data.formatVersion=2 end)
RejectThenRecover(function(data) data.body.v={} end)
RejectThenRecover(function(data) data.body.i[1]=0 end)
RejectThenRecover(function(data) data.body.i[1]=#data.body.v end)
RejectThenRecover(function(data) data.string.i[1]=1.5 end)
RejectThenRecover(function(data) data.body.v[1]=0/0 end)
RejectThenRecover(function(data) data.sockets.stringZ=nil end)

loader=Fresh();readFailure=true
local before=closes
assert(not pcall(loader.Load) and closes==before+1,'close on read failure')
readFailure=false
assert(loader.Load())

-- Both consumers fall back without throwing or leaking partial scene nodes.
package.loaded['combat.models.ThornBow']=Fresh()
package.loaded['combat.ThornBowVisual']=nil
local Visual=require('combat.ThornBowVisual')
missing=true
local parent=Mock.Node('parent')
local visual,err=Visual.New(parent,.5)
assert(visual==nil and err:find('missing thorn bow mesh',1,true))
local job,jobErr=Visual.BeginShowroom(parent,0x40000000,false)
assert(job==nil and jobErr:find('missing thorn bow mesh',1,true))
assert(#parent.children==0,'failed load must not create scene nodes')

missing=false;cache.GetFile=Assets.GetFile
rawset(_G,'THORN_MATERIAL_MISSING',false)
visual=assert(Visual.New(parent,.5))
while not Visual.Step(visual) do assert(not visual.failed) end
Visual.Dispose(visual)
print('thorn_bow_asset OK: cache, validation, closure, fallback, recovery')
