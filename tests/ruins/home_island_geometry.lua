-- Offline regression for the island silhouette, emitted water mesh, and fall recovery.
package.path='scripts/?.lua;'..package.path
local home=require('ruins.HomeIsland')
local terrain=require('ruins.RuinsTerrain')
terrain.home=home
local function upvalue(fn,name)
    for i=1,100 do
        local key,value=debug.getupvalue(fn,i)
        if key==name then return value end
        if not key then break end
    end
    error('missing generator '..name)
end
local noop=function() end
Vector3=setmetatable({},{__call=function(_,x,y,z) return {x=x,y=y,z=z} end})
Vector3.UP,Vector3.ZERO=Vector3(0,1,0),Vector3(0,0,0)
Vector2,Color,TRIANGLE_LIST=noop,noop,0
Material={new=function() return {SetSurfaceShader=function()return true end} end}
local triangles,falls,minY=0,0,math.huge
local vertices={}
local geometry=setmetatable({DefineVertex=function(_,v)
    vertices[#vertices+1]=v
    minY=math.min(minY,v.y)
    if #vertices==3 then
        triangles=triangles+1
        local a,b,c=table.unpack(vertices)
        if math.max(a.y,b.y,c.y)-math.min(a.y,b.y,c.y)>1 then falls=falls+1 end
        vertices={}
    end
end},{__index=function()return noop end})
upvalue(home.Build,'water')({CreateChild=function()return {CreateComponent=function()return geometry end}end})
assert(triangles>falls and falls>=2 and minY < -6,'pool must have a vertical spillway')
local function ground(x,z) return terrain.HasGround(home.x+x,home.z+z) end
assert(ground(0,0) and ground(12,3) and ground(-12,-6),'missing central terrain')
assert(not ground(24,17) and not ground(-24,17) and not ground(-24,-17) and not ground(24,-17),'shoreline reaches a rectangular corner')
local source=assert(io.open('scripts/ruins/NomiController.lua'));local code=source:read('*a');source:close()
local actor={cc={onGround=true,SetLinearVelocity=noop},node={},camTarget={},ResetJump=noop,UpdateCamera=noop,safeT=0}
local env=setmetatable({N=actor,Terrain=terrain},{__index=_G})
for _,name in ipairs({'UpdateSafety','ReturnFromVoid'}) do
    local body=assert(code:match('(function N:'..name..'%b().-)\nend'))..'\nend'
    assert(load(body,name,'t',env))()
end
actor.fallbackPos=Vector3(home.x+5,home.base+.1,home.z-12)
actor.node.worldPosition=Vector3(home.x+12,home.base+1.75,home.z+3)
actor.cc.Teleport=function(_,p)actor.node.worldPosition=p end
assert(not actor:UpdateSafety(.5) and actor.safePos.x==home.x+12)
actor.node.worldPosition=Vector3(home.x+30,-25,home.z+18);actor.cc.onGround=false
assert(actor:UpdateSafety(.1) and actor.node.worldPosition==actor.safePos,'fell outside current home region')
actor.safePos=nil;actor:ReturnFromVoid();assert(actor.node.worldPosition==actor.fallbackPos)
print(('PASS home shoreline, pool %d triangles, waterfall %d triangles, same-island safe point and fallback'):format(triangles-falls,falls))
