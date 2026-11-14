-- Offline only. Bindings enforce argument counts/types rather than Lua coercion.
local S=dofile('tests/combat/core_support.lua')
local P=require('combat.SwingPerf')
local F={S=S,P=P}
function F.LoadNomi(path)
    local f=assert(io.open(path or 'scripts/ruins/NomiController.lua'))
    local source=f:read('*a');f:close()
    local modules={['urhox-libs.Camera.ThirdPersonCamera']={},['game.BlockCharacter']={},
        ['game.NomiVoxelData']={},['ruins.TimeObject']={FindByVolume=function()return nil end},
        ['ruins.DebugLog']={enabled=false},['ruins.RuinsTerrain']={}}
    local env=setmetatable({require=function(name)return modules[name] or require(name)end,
        Ray=function(...)assert(select('#',...)==2);local o,d=...;assert(type(o)=='table' and type(d)=='table');return {origin=o,direction=d}end,
        IntVector3=function(x,y,z)return {x=x,y=y,z=z}end,
        VoxelRaycastResult={new=function(...)assert(select('#',...)==1);F.results=(F.results or 0)+1;return {hit=false,distance=math.huge}end}}, {__index=_G})
    source=source:gsub('return M%s*$', 'return N,TraceVolume')
    local run=assert(load(source,'actual Nomi offline','t',env))
    return run()
end
function F.Actor(N,wall,ground)
    local counts={ground=0,wall=0}
    local volume={collisionMask=1}
    local n=setmetatable({node={worldPosition=Vector3.ZERO},cc={onGround=true,radius=.32,height=1.65,collisionMask=1,collisionLayer=1}},{__index=N})
    n.world={Raycast=function(_,ray,distance,mask)
        assert(type(distance)=='number' and mask==1)
        local o,d=ray.origin,ray.direction
        if d.y<-.9 then
            counts.ground=counts.ground+1
            local y,normal=0,1
            if ground then y,normal=ground(o.x,o.z) end
            if y==nil or o.y-y>distance or o.y<y then return {} end
            return {{hit=true,volume=volume,position=Vector3(o.x,y,o.z),normal=Vector3(0,normal,0),distance=o.y-y}}
        end
        counts.wall=counts.wall+1
        if wall and math.abs(d.z)>1e-9 then
            local t=(wall-o.z)/d.z
            if t>=0 and t<=distance then return {{hit=true,volume=volume,distance=t}} end
        end
        return {}
    end}
    return n,counts
end
return F
