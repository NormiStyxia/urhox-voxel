-- Plain Lua 5.4. No game Runtime, file/network engine services, or physics.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local M={}
local v={}
v.__index=v
function v.__add(a,b) return Vector3(a.x+b.x,a.y+b.y,a.z+b.z) end
function v.__sub(a,b) return Vector3(a.x-b.x,a.y-b.y,a.z-b.z) end
function v.__mul(a,b) return Vector3(a.x*b,a.y*b,a.z*b) end
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x=x,y=y,z=z},v) end})
Vector3.ZERO=Vector3(0,0,0); Vector3.UP=Vector3(0,1,0); Vector3.FORWARD=Vector3(0,0,1); Vector3.RIGHT=Vector3(1,0,0)
Quaternion=function() return {} end
Ray=function(origin,direction) return {origin=origin,direction=direction} end
function M.Near(a,b) assert(math.abs(a-b)<1e-6,tostring(a)..' ~= '..tostring(b)) end
function M.Fixture()
    local terrain={VOID_Y=-128,ISLAND={safeMargin=2}}
    function terrain.HasGround(x,z,margin) return math.abs(x)<=50-(margin or 0) and math.abs(z)<=50-(margin or 0) end
    function terrain.GroundHeight(x,z) if terrain.HasGround(x,z) then return 0 end end
    function terrain.IsSafeGround(x,y,z) return terrain.HasGround(x,z,2) and y==0 end
    local combat={hits=0,deaths=0,aggros=0,pos=Vector3(0,0,1.8),damage=0}
    function combat.PlayerPos() return combat.pos end
    function combat.DamagePlayer(info) combat.hits=combat.hits+1; combat.damage=combat.damage+info.dmg end
    function combat.OnEnemyDead(_) combat.deaths=combat.deaths+1 end
    function combat.OnEnemyAggro(_) combat.aggros=combat.aggros+1 end
    return terrain,combat
end
function M.Tick(enemy,seconds,position)
    local elapsed=0
    while elapsed+1e-9<seconds do
        local dt=math.min(.01,seconds-elapsed)
        enemy:Update(dt,position); elapsed=elapsed+dt
    end
end
return M
