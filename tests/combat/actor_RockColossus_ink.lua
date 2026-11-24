-- Material binding, UV emission, phase isolation and resource fallback in a mock scene.
local H=dofile('tests/combat/actor_roles_support.lua')
local F=require('combat.enemies.actors.RockColossusFault')
Vector2=Vector2 or function(x,y) assert(x==x and y==y);return {x=x,y=y} end
local getResource,newMaterial=cache.GetResource,Material.new
local atlas={};local failure,reads,bindings=nil,0,0
function cache:GetResource(kind,path)
    if kind=='Texture2D' then
        assert(path==F.Atlas);reads=reads+1
        if failure=='missing' then return nil end
        return atlas
    end
    return getResource(self,kind,path)
end
function Material:new()
    local m=newMaterial(self)
    function m:SetSurfaceShader(path)
        assert(path=='Shaders/BLGL/RockFaultInk.shader' or path=='Shaders/BLGL/RockFaultStrata.shader')
        return failure~='shader'
    end
    function m:SetSurfaceTexture(name,tex)
        assert(name=='fault_atlas' and tex==atlas);bindings=bindings+1;return failure~='sampler'
    end
    return m
end
local e,_,combat=H.newLogic('RockColossus');local target=Vector3(1.3,0,3)
for _,case in ipairs({'ok','missing','shader','sampler'}) do
    failure=case;local f=F.New(H.scene);f:Lock(e);f:Brush(.48)
    local first,last=f.sections[1],f.sections[5];assert(first.warn and last.warn and first.brush>last.brush)
    if case=='ok' then
        assert(first.ink and first.ink.ground.bed==0 and last.ink.wall.bed==4)
        assert(first.ink.ground.brush>last.ink.ground.brush and bindings==15)
    else assert(not first.ink and not first.spray) end
    f:Step(e,.24,.01,target);assert(first.erupted and first.rock.enabled and last.warn)
    if case=='ok' then assert(first.spray.enabled and first.ink.wall.heat>0 and first.marker.enabled)
    else assert(not first.marker.enabled) end
    f:Step(e,1.05,.01,target);assert(not first.rock.enabled and not first.marker.enabled)
    f:Clear();assert(not f.root.enabled);f:Lock(e)
    if case=='ok' then assert(not first.spray.enabled and first.ink.ground.ash==-1) end
    f:Destroy();assert(not f.root and combat.hits==0)
end
assert(reads==4);cache.GetResource=getResource;Material.new=newMaterial;e:Destroy()
print('PASS RockColossus: 15 shader/atlas bindings, progressive warning, strata and spray, ash erase, cleanup and 3 fallback paths')
