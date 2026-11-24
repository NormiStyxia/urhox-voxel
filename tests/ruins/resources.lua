-- Run from the project root with Lua 5.4: lua tests/ruins/resources.lua
-- Exercises the real catalog, terrain, models and resource lifecycle with engine doubles.
package.path='scripts/?.lua;'..package.path
local Vec={}; Vec.__index=Vec
function Vector3(x,y,z) return setmetatable({x=x,y=y,z=z},Vec) end
function Vec.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function Vec.__add(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
function Vec.__div(a,n) return Vector3(a.x/n,a.y/n,a.z/n) end
function Vec:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function Vec:Normalized()
    local length=self:Length()
    assert(length>1e-10,'degenerate mesh face')
    return self/length
end
function Vec:CrossProduct(b)
    return Vector3(self.y*b.z-self.z*b.y,self.z*b.x-self.x*b.z,self.x*b.y-self.y*b.x)
end
function Ray(origin,direction) return {origin=origin,direction=direction} end
function Quaternion(deg,axis) return {deg=deg,axis=axis} end
function Color(r,g,b,a)
    assert(r>=0 and r<=1 and g>=0 and g<=1 and b>=0 and b<=1,'resource colour out of range')
    return {r,g,b,a}
end
function Variant(v) return v end
local function noop() end
CULL_NONE=0
Material={new=function() return {SetTechnique=noop,SetShaderParameter=noop,SetCullMode=noop,SetSurfaceShader=function() return true end} end}
cache={GetResource=function(_,_,path) return path end}
TRIANGLE_LIST=0

local Node={}; Node.__index=Node
function Node:CreateChild(name) return setmetatable({name=name},Node) end
function Node:Remove() assert(not self.removed); self.removed=true end
function Node:CreateComponent(kind)
    assert(kind=='CustomGeometry')
    local mesh={count=0,DefineColor=noop,BeginGeometry=noop}
    function mesh:DefineVertex() self.count=self.count+1 end
    function mesh:DefineNormal(n) assert(math.abs(n:Length()-1)<.0001,'invalid mesh normal') end
    function mesh:SetMaterial(m) self.material=m end
    function mesh:Commit() assert(self.count>0 and self.count%3==0 and self.material,'incomplete mesh') end
    return mesh
end

local Terrain=require('ruins.RuinsTerrain')
local Catalog=require('combat.MaterialCatalog')
local Resources=require('ruins.RuinsResources')
local World={}; World.__index=World
local wall={collisionMask=1}
function World:CreateVolume()
    local volume={GetGrid=function() return {FillBox=noop} end,RebuildGeometry=noop}
    self.volumes[volume]=true
    return volume
end
function World:FinalizeVolume(v) assert(self.volumes[v]) end
function World:RemoveVolume(v) assert(self.volumes[v]); self.volumes[v]=nil end
function World:Raycast(ray,length,mask)
    assert((mask & 2)==0,'character visual layer included')
    local p=ray.origin
    if ray.direction.y==-1 then
        local h=Terrain.GroundHeight(p.x,p.z)
        if self.holes and p.x>19 then return {} end
        if h and p.y>=h and p.y-length<=h then
            return {{hit=true,volume=wall,normal=Vector3(0,1,0),distance=p.y-h,position=Vector3(p.x,h,p.z)}}
        end
    elseif self.blocked then
        return {{hit=true,volume=wall,distance=.2}}
    end
    return {}
end
local function build(options)
    local world=setmetatable({volumes={}},World)
    return Resources.New(Node,world,options),world
end
local function unexpectedGrant() error('unexpected inventory grant') end
local safe=Vector3(3,0,-5.4)

-- Restore one receipt and collect every other site (including dynamic trees).
local restored='site:'..Catalog.Sites[#Catalog.Sites][1]
local claimedMap={[restored]=true}
local sampleTrees={{id='east_ancient',x=30.5,z=-14,trunk=.7},{id='tree_3',x=49.46,z=31.01,trunk=.45}}
local training,world=build({training=true,trees=sampleTrees,wasClaimed=function(key,kind)
    return kind=='time_wraith' or claimedMap[key]==true
end})
for _,site in ipairs(Catalog.Sites) do
    local name,itemId,count,x,z,mode=table.unpack(site)
    local key='site:'..name
    local item=assert(training.entries[key],key..' missing')
    assert(item.itemId==itemId and item.count==count,key..' yield')
    local tree=mode=='tree'
    if tree then
        local dx,dz=item.position.x-x,item.position.z-z
        assert(math.sqrt(dx*dx+dz*dz)<2.4 and math.sqrt(dx*dx+dz*dz)>1.0,key..' trunk standoff')
        assert(not item.baseCollider and not item.upperCollider,key..' must not add collision')
    else
        assert(item.position.x==x and item.position.z==z,key..' anchor')
    end
    if key==restored then
        assert(item.spent and not item.stock and not item.upperCollider,key..' receipt')
    else
        local target=assert(training:Nearest(item.position))
        assert(target.id==key and target.name==Catalog.ById[itemId].name)
        local upper,stock=item.upperCollider,item.stock
        assert(training:Claim(key,item.position,function(t)
            assert(t.key==key and t.source=='site' and t.itemId==itemId and t.count==count and not t.trainingKind)
            return true
        end))
        assert(item.spent and stock.removed)
        if not tree then assert(not world.volumes[upper] and world.volumes[item.baseCollider]) end
    end
    assert(not training:Claim(key,item.position,unexpectedGrant))
end
for _,t in ipairs(sampleTrees) do
    local key='site:'..t.id
    local item=assert(training.entries[key],key..' dynamic tree missing')
    assert(item.tree and not item.baseCollider and not item.upperCollider)
    local dx,dz=item.position.x-t.x,item.position.z-t.z
    assert(math.sqrt(dx*dx+dz*dz)<2.4 and math.sqrt(dx*dx+dz*dz)>1.0,key..' trunk standoff')
    assert(training:Claim(key,item.position,function(d)
        assert(d.itemId=='timber' and d.count==2 and d.verb=='取木')
        return true
    end))
    assert(item.spent and item.remains)
end
-- Respawn: once wasClaimed expires, Refresh restores stock, clears woodchips and restores collider.
claimedMap[restored]=false
assert(training:Refresh()>=1)
assert(not training.entries[restored].spent and training.entries[restored].stock and training.entries[restored].upperCollider)
assert(not training:SpawnDrop('beetle',safe),'unknown kind')
assert(not training:SpawnDrop('time_wraith',safe),'restored training receipt')
local id=assert(training:SpawnDrop('wood_spirit',Vector3(0,12,-45),safe))
assert(id==training:SpawnDrop('wood_spirit',safe),'one pending drop per training kind')
local pos=training.entries[id].position
assert(Terrain.HasGround(pos.x,pos.z) and pos.y<1,'flyer over ravine')
local feet=pos+Vector3(.5,0,.25)
assert(training:Nearest(feet).id==id)
assert(not training:Nearest(feet+Vector3(0,2,0)),'different floor')
world.blocked=true
assert(not training:Nearest(feet) and not training:Claim(id,feet,unexpectedGrant),'wall must block HUD and claim')
world.blocked=false
local accepted,reason=training:Claim(id,feet,function() return false,'full' end)
assert(not accepted and reason=='full' and training:Nearest(feet).id==id,'rejected grant must be retryable')
assert(not pcall(training.Claim,training,id,feet,function() error('simulated rollback') end))
assert(training:Claim(id,feet,function(t)
    local reward=Catalog.EnemyDrops.wood_spirit
    assert(t.trainingKind=='wood_spirit' and t.itemId==reward.id and t.count==reward.count)
    assert(not training:Claim(id,feet,unexpectedGrant),'reentrant claim')
    return true
end))
assert(not training:Claim(id,feet,unexpectedGrant) and not training:SpawnDrop('wood_spirit',safe))
training:Destroy(); training:Destroy(); assert(next(world.volumes)==nil,'training collider leak')

-- All ordinary kinds die in the same spot, with overlapping interaction radii.
local normal,normalWorld=build()
local ids={}
for kind,drop in pairs(Catalog.EnemyDrops) do
    local key=assert(normal:SpawnDrop(kind,Vector3(12,13,-7),safe))
    assert(not ids[key],'duplicate ordinary drop ID')
    ids[key]=drop
end
for key,drop in pairs(ids) do
    local entry=normal.entries[key]
    assert(normal:Nearest(entry.position).id==key,'nearest item among overlapping pickup radii')
    assert(normal:Claim(key,entry.position,function(t)
        assert(not t.trainingKind and not t.key and t.itemId==drop.id and t.count==drop.count)
        return true
    end))
    assert(not normal.entries[key])
end
normalWorld.holes=true
local holeDrop=assert(normal:SpawnDrop('time_wraith',Vector3(30,12,0),safe))
assert(normal.entries[holeDrop].position.x<19,'terrain height alone cannot support a drop')
normal:Destroy(); assert(next(normalWorld.volumes)==nil,'ordinary collider leak')

-- Exercise the scene's exact cast adapter as well as the native Raycast path.
local hitVolume
local gate,gateWorld=build({cast=function(a,b)
    if hitVolume then return .5,{volume=hitVolume} end
    if (a.x>7)~=(b.x>7) then return .4,{volume=wall} end
end})
local gateDrop=assert(gate:SpawnDrop('time_wraith',Vector3(13,12,-7),safe))
assert(gate.entries[gateDrop].position.x<=7,'airborne kill behind closed gate')
local site=gate.entries['site:court_vein']
local near=site.position+Vector3(1.3,0,0)
hitVolume=site.upperCollider
assert(gate:Nearest(near).id==site.id,'visible resource shell')
hitVolume=wall
assert(not gate:Nearest(near) and not gate:Claim(site.id,near,unexpectedGrant),'occluded resource shell')
gate:Destroy(); assert(next(gateWorld.volumes)==nil,'gate collider leak')
print(('PASS ruins resource sites (%d), catalog drops, wall/ground probes, training receipts, claims and cleanup'):format(#Catalog.Sites))
