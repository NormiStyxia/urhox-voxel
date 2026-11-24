-- Run with the real actor and the offline scene API. Capture actual material bindings,
-- UVs, stamp clocks and node lifetime independently of GPU shader compilation.
package.path='scripts/?.lua;tests/?.lua;'..package.path
local H=require('combat.actor_roles_support')
local FX=require('combat.enemies.actors.WoodSpiritFX')
Vector2=Vector2 or function(x,y) return {x=x,y=y} end
local tex={name=FX.Atlas}
local priorGet=cache.GetResource
local fail,reads,bindings=nil,0,0
function cache:GetResource(kind,path)
    if path==FX.Atlas then
        assert(kind=='Texture2D'); reads=reads+1
        if fail~='atlas' then return tex end
        return nil
    end
    return priorGet(self,kind,path)
end
local priorNew=Material.new
function Material:new()
    local m=priorNew(self)
    function m:SetSurfaceShader(path)
        assert(path=='Shaders/BLGL/WoodSpiritBrush.shader')
        return fail~='shader'
    end
    function m:SetSurfaceTexture(name,resource)
        assert(name=='brush_atlas' and resource==tex)
        if fail=='sampler' then return false end
        bindings=bindings+1; return true
    end
    return m
end
local function spawn()
    local e=assert(H.newVisual('WoodSpirit')); e.aggro=true
    local target=Vector3(0,0,2.15)
    e:Face(target);e.lastTarget=target;e.attackIndex=1;e:StartAttack()
    return e,target
end
local e,target=spawn();local pool=e.woodFX
assert(reads==1 and bindings==3 and pool.brush.impact==0 and pool.stamps.land.material.impact==1)
H.T.Tick(e,.48,target);H.T.Near(pool.brush.phase,.48/.9)
H.T.Tick(e,.90-.48+.49,target);local land=pool.stamps.land
assert(land.active and land.node.enabled and land.material.phase>0 and land.material.phase<1)
local x,z=land.node.position.x,land.node.position.z
H.T.Near(z,e.attack.travel+.28)
e.position=Vector3(1,0,3);H.T.Tick(e,.04,target)
H.T.Near(land.node.position.x,x);H.T.Near(land.node.position.z,z)
e:Stagger(1,false);assert(not land.node.enabled and not pool.stamps.contact.node.enabled)
e:Reset();e:Destroy();assert(not pool.root and not land.material)
for _,failure in ipairs({'atlas','shader','sampler'}) do
    fail=failure
    e,target=spawn(); assert(not e.woodFX.brush and not e.woodFX.stamps.land.node)
    H.T.Tick(e,.47,target); assert(e.warning.visible and e.visual.warnings.line.enabled)
    assert(e.woodFX.slots[1].node.enabled,'existing bark chips should render with '..failure..' missing')
    e:Destroy()
end
print('PASS WoodSpirit brush: 1 atlas read, 3 independent material clocks, anchored landing, freeze/reset/destroy, 3 resource fallbacks')
